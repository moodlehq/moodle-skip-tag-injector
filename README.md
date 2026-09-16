# moodle-skip-tag-injector

This project provides a script to inject the `@skip` tag into specified flaky scenarios in Moodle Behat test files. 
This is useful for avoiding the execution of known flaky tests during Continuous Integration (CI) runs, ensuring more stable and reliable test results.

### Purpose

The `inject_skip_tag` script is designed to:
- Read a list of flaky scenarios and their corresponding file paths.
- Modify the specified Behat test files by adding the `@skip` tag above the flaky scenarios.
- Help streamline CI processes by skipping tests that are known to fail intermittently.

### Prerequisites

- A file listing the flaky scenarios in the format: `<scenario_name>|<relative_file_path>`.
- Access to the Moodle root directory where the Behat test files are located.

### Usage

Run the script with the following parameters:
### Parameters

- `<branch>`: The branch name (used to locate the flaky scenarios file).
- `<browser>`: The browser name (used to locate the flaky scenarios file).
- `<path/to/moodle/root>`: The absolute path to the Moodle root directory.

```
./inject_skip_tag <branch> <browser> <path/to/moodle/root>
```
### Flaky Scenarios File

The script expects a file named `<branch>_<browser>_flaky_tests.txt` in the `flaky_tests/` directory. Each line in the file should follow this format:

```
<scenario_name>|<relative_file_path>
```

- `scenario_name`: The full name of the scenario to skip, exactly as it appears after `Scenario:` or `Scenario Outline:` in the feature file. The match is anchored, so the name must be complete — a truncated name matches nothing.
- `relative_file_path`: The path to the Behat test file, relative to the Moodle root directory.

For example:

```
Assign students to groups|group/tests/behat/create_groups.feature
```

The path is branch-dependent: Moodle 5.1 and later store the web root under `public/`, so the same entry for branch 501 and above reads `Assign students to groups|public/group/tests/behat/create_groups.feature`.

See [AGENTS.md](AGENTS.md) for the full rules on maintaining these lists — in particular, a scenario must never be skipped on both Chrome and Firefox for the same branch, since that removes it from CI coverage entirely.

### Output

- The script will inject the `@skip` tag above the specified scenarios in the test files.
- It will log messages indicating success, warnings for missing scenarios, or errors for missing files.

## Notes

- Ensure the script has execute permissions: `chmod +x inject_skip_tag`.
- The script modifies test files in place. Use version control to track changes.
