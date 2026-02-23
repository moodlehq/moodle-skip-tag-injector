#!/usr/bin/env bats
# Tests for inject_skip_tag
# Requires bats-core >= 1.5: https://github.com/bats-core/bats-core
# Install: sudo apt-get install bats
# Run:     bats tests/inject_skip_tag.bats
SCRIPT="$(dirname "$BATS_TEST_DIRNAME")/inject_skip_tag"
FIXTURE="$(dirname "$BATS_TEST_FILENAME")/fixtures/sample.feature"
# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Print a message + file snippet (useful when an assertion fails).
print_file_context() {
  local file="$1" needle="$2"
  echo "--- file: $file"
  if [ -n "$needle" ]; then
    echo "--- context for: $needle"
    grep -n -C2 -F "$needle" "$file" || true
  else
    echo "--- head"
    head -n 40 "$file" || true
  fi
}

# Normalise a flaky list file stream for stable comparisons.
# - trims whitespace
# - skips blank lines and comments (#...)
# - strips optional public/ prefix after the | delimiter
normalise_flaky_stream() {
  sed -E 's/^[[:space:]]+//;s/[[:space:]]+$//;s/\|public\//|/;' \
    | grep -v -E '^[[:space:]]*$|^[[:space:]]*#'
}

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------
setup() {
  # Fresh temp moodle root for every test — never mutates real fixtures
  TEST_TMP="$(mktemp -d)"
  mkdir -p "$TEST_TMP/tests/fixtures"
  cp "$FIXTURE" "$TEST_TMP/tests/fixtures/sample.feature"
  # Temp dir that holds a private copy of the script + flaky_tests/
  SCRIPT_TMP="$(mktemp -d)"
  cp "$SCRIPT" "$SCRIPT_TMP/inject_skip_tag"
  chmod +x "$SCRIPT_TMP/inject_skip_tag"
  mkdir -p "$SCRIPT_TMP/flaky_tests"
}
teardown() {
  rm -rf "$TEST_TMP" "$SCRIPT_TMP"
}
# Write a flaky list and run the injector against TEST_TMP as the moodle root.
# Usage: run_injector <branch> <browser> "scenario|path" ["scenario|path" ...]
run_injector() {
  local branch="$1" browser="$2"; shift 2
  local flaky_file="$SCRIPT_TMP/flaky_tests/${branch}_${browser}_flaky_tests.txt"
  printf '%s\n' "$@" > "$flaky_file"
  run "$SCRIPT_TMP/inject_skip_tag" "$branch" "$browser" "$TEST_TMP"
}
feature_file() {
  echo "$TEST_TMP/tests/fixtures/sample.feature"
}
# Count how many times a literal string appears in the feature file
count_in_feature() {
  grep -Fc "$1" "$(feature_file)" || true
}
# ---------------------------------------------------------------------------
# Argument / file handling
# ---------------------------------------------------------------------------
@test "exits with error when called with wrong number of arguments" {
  run "$SCRIPT_TMP/inject_skip_tag" only_one_arg
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Usage:"
}
@test "exits cleanly with warning when flaky tests file does not exist" {
  # Call the script directly — do NOT write a flaky file so the "not found" path is hit
  run "$SCRIPT_TMP/inject_skip_tag" nonexistent_branch chrome "$TEST_TMP"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Warning: Flaky scenarios file not found"
}
@test "errors and continues when feature file path does not exist" {
  run_injector test chrome "Some scenario|tests/fixtures/nonexistent.feature"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Error: Test file not found"
}
@test "warns and continues when scenario name is not found in feature file" {
  run_injector test chrome "This scenario does not exist|tests/fixtures/sample.feature"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Warning: Scenario 'This scenario does not exist' not found"
}
# ---------------------------------------------------------------------------
# Tag injection
# ---------------------------------------------------------------------------
@test "injects @skip as a new tag line above a plain scenario" {
  run_injector test chrome "Simple scenario without tags|tests/fixtures/sample.feature"
  [ "$status" -eq 0 ]
  grep -B1 "Scenario: Simple scenario without tags" "$(feature_file)" | grep -q "@skip" \
    || { print_file_context "$(feature_file)" "Scenario: Simple scenario without tags"; false; }
}
@test "appends @skip to an existing tag line" {
  run_injector test chrome "Scenario with an existing tag|tests/fixtures/sample.feature"
  [ "$status" -eq 0 ]
  grep -q "@existing_tag @skip" "$(feature_file)"
}
@test "injects @skip for a scenario name containing parentheses" {
  run_injector test chrome \
    "Scenario with special chars (javascript enabled)|tests/fixtures/sample.feature"
  [ "$status" -eq 0 ]
  grep -B1 "Scenario: Scenario with special chars (javascript enabled)" \
    "$(feature_file)" | grep -q "@skip" \
    || { print_file_context "$(feature_file)" "Scenario: Scenario with special chars (javascript enabled)"; false; }
}
@test "injects @skip above a Scenario Outline" {
  run_injector test chrome "Scenario outline without tags|tests/fixtures/sample.feature"
  [ "$status" -eq 0 ]
  grep -B1 "Scenario Outline: Scenario outline without tags" "$(feature_file)" | grep -q "@skip" \
    || { print_file_context "$(feature_file)" "Scenario Outline: Scenario outline without tags"; false; }
}
@test "processes multiple scenarios listed in a single flaky file" {
  run_injector test chrome \
    "Simple scenario without tags|tests/fixtures/sample.feature" \
    "Scenario with special chars (javascript enabled)|tests/fixtures/sample.feature"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Simple scenario without tags"
  echo "$output" | grep -q "javascript enabled"
  grep -B1 "Scenario: Simple scenario without tags" "$(feature_file)" | grep -q "@skip"
  grep -B1 "Scenario: Scenario with special chars" "$(feature_file)" | grep -q "@skip"
}
# ---------------------------------------------------------------------------
# Duplicate @skip prevention
# ---------------------------------------------------------------------------
@test "does not duplicate @skip when run twice on the same scenario" {
  run_injector test chrome "Simple scenario without tags|tests/fixtures/sample.feature"
  local count_after_first
  count_after_first="$(count_in_feature "@skip")"
  run_injector test chrome "Simple scenario without tags|tests/fixtures/sample.feature"
  local count_after_second
  count_after_second="$(count_in_feature "@skip")"
  [ "$count_after_first" -eq "$count_after_second" ]
}
@test "does not add @skip when scenario already has a tag line without @skip" {
  # Fixture: "Scenario already tagged with skip" has @existing_tag @another_tag but NO @skip yet
  run_injector test chrome "Scenario already tagged with skip|tests/fixtures/sample.feature"
  [ "$status" -eq 0 ]
  skip_count=$(grep -B1 "Scenario: Scenario already tagged with skip" "$(feature_file)" \
    | grep -Fc "@skip" || true)
  [ "$skip_count" -eq 1 ]
}
@test "does not add @skip when it already exists mid-tag-line" {
  # Fixture: "Scenario already skipped in the middle of tags" has @existing_tag @skip @another_tag
  local before
  before="$(count_in_feature "@skip")"
  run_injector test chrome \
    "Scenario already skipped in the middle of tags|tests/fixtures/sample.feature"
  [ "$status" -eq 0 ]
  local after
  after="$(count_in_feature "@skip")"
  [ "$before" -eq "$after" ]
}
# ---------------------------------------------------------------------------
# Cross-browser duplicate prevention
# ---------------------------------------------------------------------------
@test "does not duplicate @skip when same scenario appears in both browser flaky files" {
  run_injector test chrome "Simple scenario without tags|tests/fixtures/sample.feature"
  local count_after_chrome
  count_after_chrome="$(count_in_feature "@skip")"
  run_injector test firefox "Simple scenario without tags|tests/fixtures/sample.feature"
  local count_after_firefox
  count_after_firefox="$(count_in_feature "@skip")"
  [ "$count_after_chrome" -eq "$count_after_firefox" ]
}
@test "same scenario and feature file must not appear in both chrome and firefox flaky files" {
  # Checks that the same scenario name + normalised feature path is not listed in both
  # a chrome AND a firefox flaky file for the same branch.
  local flaky_dir
  flaky_dir="$(dirname "$BATS_TEST_DIRNAME")/flaky_tests"
  local failed=0

  for chrome_file in "$flaky_dir"/*_chrome_flaky_tests.txt; do
    [ -f "$chrome_file" ] || continue

    local branch
    branch=$(basename "$chrome_file" | sed 's/_chrome_flaky_tests.txt$//')

    local firefox_file="$flaky_dir/${branch}_firefox_flaky_tests.txt"
    [ -f "$firefox_file" ] || continue

    # Use temp files so we can rely on `comm` without process substitution.
    local chrome_tmp firefox_tmp
    chrome_tmp="$(mktemp)"
    firefox_tmp="$(mktemp)"

    normalise_flaky_stream < "$chrome_file" | sort -u > "$chrome_tmp"
    normalise_flaky_stream < "$firefox_file" | sort -u > "$firefox_tmp"

    local dupes
    dupes=$(comm -12 "$chrome_tmp" "$firefox_tmp")

    rm -f "$chrome_tmp" "$firefox_tmp"

    if [ -n "$dupes" ]; then
      echo "Branch $branch: duplicate scenario|feature in both chrome and firefox:"
      echo "$dupes"
      failed=1
    fi
  done

  [ "$failed" -eq 0 ]
}

@test "same scenario and feature file must not be duplicated within the same flaky file" {
  # Checks that a flaky list file does not contain the exact same scenario name +
  # normalised feature path more than once.
  local flaky_dir
  flaky_dir="$(dirname "$BATS_TEST_DIRNAME")/flaky_tests"

  local failed=0

  for flaky_file in "$flaky_dir"/*_flaky_tests.txt; do
    [ -f "$flaky_file" ] || continue

    local dupes
    dupes=$(normalise_flaky_stream < "$flaky_file" \
      | sort \
      | uniq -d)

    if [ -n "$dupes" ]; then
      echo "Duplicate scenario|feature entries found in $(basename "$flaky_file"):"
      echo "$dupes"
      failed=1
    fi
  done

  [ "$failed" -eq 0 ]
}
