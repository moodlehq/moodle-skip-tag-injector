# AGENTS.md — moodle-skip-tag-injector

## What this repo is

A bash tool used by Moodle CI to inject the `@skip` tag above known-flaky Behat
scenarios in a Moodle checkout, immediately before the Behat run. It edits the
`.feature` files **in the CI workspace only** — nothing is ever committed back to
Moodle core.

The repo is two things:

- [`inject_skip_tag`](inject_skip_tag) — the script. Rarely changes.
- [`flaky_tests/`](flaky_tests) — per-branch, per-browser lists of scenarios to skip.
  **This is what changes ~every time.**

## The hard rule

> **A scenario must NEVER be skipped for both Chrome and Firefox on the same branch.**

Moodle CI runs Behat on both Chrome and Firefox. Skipping a flaky test on one
browser is acceptable because the other browser still provides coverage. Skipping
it on both means the scenario is not tested at all — that is a silent loss of
coverage, not a flaky-test fix.

So: when the user reports a flaky test, you must know **which browser** it was
flaky on, and add it to **that browser's list only**. If the browser is not
stated and not inferable from the failure output, ask — do not guess.

This rule is enforced by a bats test (`same scenario and feature file must not
appear in both chrome and firefox flaky files`), which compares the two lists
per branch after normalising away the `public/` prefix. A violation fails CI on
the PR.

## Repo layout

```
inject_skip_tag                       # the script (bash + awk)
flaky_tests/<branch>_<browser>_flaky_tests.txt
tests/inject_skip_tag.bats            # bats-core suite, run by GitHub Actions
tests/fixtures/sample.feature         # fixture for the injection tests
.github/workflows/tests.yml           # runs `bats tests/inject_skip_tag.bats`
```

`<branch>` is Moodle's 3-digit `$branch` from `version.php` (405, 500, 501, 502,
503). `<browser>` is the CI `BROWSER` value: `chrome`, `firefox`, or `browserkit`.

The `browserkit` lists exist but are intentionally empty — browserkit runs are
non-JS and don't suffer the timing flakiness that the JS browsers do. Don't add
entries there unless the user explicitly asks.

## Line format — read this carefully

Each line is:

```
<scenario name>|<path to .feature relative to the Moodle root>
```

**Scenario name first, path second.** The [README.md](README.md) documents this
backwards (`<relative_file_path>|<scenario_name>`) — the README is wrong, the
script is right (`IFS='|' read -r scenario_name filepath`, [inject_skip_tag:28](inject_skip_tag:28)).
Trust the existing file contents and the script, not the README.

### `public/` prefix depends on the branch

Moodle moved its web root into `public/` in 5.1. So:

| Branch | Moodle | Path prefix |
|--------|--------|-------------|
| 405    | 4.5    | none — `mod/forum/tests/behat/...` |
| 500    | 5.0    | none — `mod/forum/tests/behat/...` |
| 501    | 5.1    | `public/mod/forum/tests/behat/...` |
| 502    | 5.2    | `public/mod/forum/tests/behat/...` |
| 503    | 5.3    | `public/mod/forum/tests/behat/...` |

Getting this wrong doesn't fail CI here — it fails silently at Behat time with
`Error: Test file not found`, and the flaky test keeps failing. Always match the
prefix already used by the other lines in the same file.

### Scenario names must be exact and complete

The injector anchors its match: `^[[:space:]]*Scenario( Outline)?: <name>$`. The
name must be byte-identical to what's in the `.feature` file, all the way to the
end of the line. A truncated or paraphrased name silently does nothing (you get a
`Warning: Scenario '...' not found`, which nobody reads in a CI log).

Two commits in the history exist purely to fix this (`da3a278 Add full scenario
names`, `b8d97a4`). Verify before adding — see below.

Other name constraints:

- `Scenario Outline:` is supported, same as `Scenario:`.
- Regex metacharacters (parentheses, `.`, `+`, `[`) are escaped by the script, so
  names like `Hide/Show toggle with javascript enabled` and
  `... (javascript enabled)` work fine.
- A scenario name containing a literal `|` **cannot** be listed — it collides with
  the field delimiter.
- Do not add inline comments. The `#` comment check in the script is applied to
  the *second* field, so a `# ...` line that contains a `|` is not actually
  skipped and will be parsed as a real entry.

## Adding a flaky test — the procedure

1. **Establish the browser.** Chrome or Firefox. Ask if unclear.
2. **Establish the branches.** Default is every branch where the scenario exists.
   Lists are not identical across branches — e.g. `Duplicate custom report` is in
   500–503 Firefox but not 405, because the scenario doesn't exist there.
3. **Verify the scenario name against a real checkout** before editing. Local
   checkouts are at `/home/simey/moodles/integration_<NNN>/moodle`
   (`integration_main` = 503). For example:

   ```bash
   grep -n "^\s*Scenario" \
     /home/simey/moodles/integration_405/moodle/group/tests/behat/create_groups.feature
   ```
   ```
   8:  Scenario: Assign students to groups
   64:  Scenario: Assign students to groups with site user identity configured
   ```

   This confirms the full name, the exact file path, and whether the scenario
   exists on that branch at all. It also shows why the exact name matters: these
   two scenarios share a prefix, and listing the shorter one skips *only* the
   shorter one — the injector's match is anchored, so there is no accidental
   prefix match in either direction.
4. **Check the opposite browser's list** for the same branch. If the scenario is
   already there, stop and tell the user — adding it would break the hard rule.
5. **Append** the entry to the end of the file. That's the convention throughout
   the history; the lists are not sorted.
6. **Run the hygiene checks** (below).

## Verifying changes

The full suite needs `bats-core` (`sudo apt-get install -y bats`), which is not
currently installed on this machine — GitHub Actions runs it on every push and PR.

The two list-hygiene tests can be reproduced locally without bats. Run this from
the repo root after any edit to `flaky_tests/`:

```bash
export LC_ALL=C   # required — comm and sort disagree under a UTF-8 locale
for c in flaky_tests/*_chrome_flaky_tests.txt; do
  b=$(basename "$c" _chrome_flaky_tests.txt)
  f="flaky_tests/${b}_firefox_flaky_tests.txt"; [ -f "$f" ] || continue
  d=$(comm -12 \
    <(sed -E 's/\|public\//|/' "$c" | grep -v '^[[:space:]]*$' | sort -u) \
    <(sed -E 's/\|public\//|/' "$f" | grep -v '^[[:space:]]*$' | sort -u))
  [ -n "$d" ] && { echo "OVERLAP on $b:"; echo "$d"; }
done
for f in flaky_tests/*_flaky_tests.txt; do
  d=$(sed -E 's/\|public\//|/' "$f" | grep -v '^[[:space:]]*$' | sort | uniq -d)
  [ -n "$d" ] && { echo "DUPE in $f:"; echo "$d"; }
done
echo "checks done"
```

Silent output (beyond `checks done`) means clean.

To smoke-test an actual injection against a throwaway copy of a checkout:

```bash
./inject_skip_tag 503 chrome /path/to/a/scratch/moodle/copy
```

It prints one line per entry: `Injected @skip tag into ...`, `Warning: Scenario
'...' not found`, or `Error: Test file not found`. **Never run it against a
checkout you care about** — it rewrites `.feature` files in place.

## How the injection behaves

- If the line above the scenario is already a tag line, `@skip` is appended to it.
  Otherwise a new `@skip` line is inserted with matching indentation.
- It is idempotent — re-running never produces a duplicate `@skip`, and it
  detects an existing `@skip` anywhere in the tag line, not just at the end.
- A missing list file is a warning and `exit 0`, not an error — CI branches
  without a list are simply left alone.
- A missing `.feature` file or unmatched scenario name is reported and the script
  continues to the next entry. **Nothing fails the CI job.** That is deliberate,
  but it means a typo in a list is invisible unless someone reads the log.

## How CI consumes this

`moodle-ci-runner` has a module,
`runner/main/modules/moodle-skip-tag-injector/moodle-skip-tag-injector.sh`, which
runs during the `behat` jobtype config phase:

```bash
"${PATHTOSKIPTAGINJECTOR}/inject_skip_tag" "${MOODLE_BRANCH}" "${BROWSER}" "${CODEDIR}"
```

`MOODLE_BRANCH` is read from `version.php` (or `public/version.php`), `BROWSER` is
the job's browser, `CODEDIR` is the Moodle checkout. If `PATHTOSKIPTAGINJECTOR`
is unset the whole step is skipped with a warning.

Note that this repo only *adds the tag*. The actual exclusion happens in the
Behat run's tag filter (`BEHAT_TAGS`, e.g. `~@skip`), configured on the CI job —
not here, and not in Moodle core.

## Conventions

- Branch off `main`, PR to `moodlehq/moodle-skip-tag-injector`.
- Recent commits are prefixed with the tracker issue (`MDL-86190: ...`) when one
  exists; otherwise a short imperative subject (`Add lists for 5.3`) is fine.
- Keep list edits and script changes in separate commits.
- When the underlying flakiness is fixed, the entry should be *removed* — there
  are several such commits (`Remove flaky h5p tests from list`, `Remove MFA test
  from list`). These lists are meant to shrink, not just grow. If the user gives
  you a tracker issue for the root cause, mention it in the commit message so the
  entry can be found and removed later.
