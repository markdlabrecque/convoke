# Task

Verify ticket #{{ISSUE_IID}} on branch `{{BRANCH}}` at `{{TIP_SHA}}`, based on `{{BASE_BRANCH}}` at `{{BASE_SHA}}`. Do not fix code.

## Issue

{{TICKET}}

## Rules

- Never edit tracked files, commit, push, or use `gh`. Keep HEAD at `{{TIP_SHA}}` on `{{BRANCH}}` and the worktree clean.
- Put verification output in `{{EVIDENCE_DIR}}`.
- Verify actual behavior using the available tests, scripts, or manual checks. Do not claim checks you did not run. If visual behavior is relevant, capture and inspect screenshots; otherwise use reproducible command output as evidence.

## Procedure

1. Classify the change as a bugfix or feature.
2. Run targeted checks and inspect the relevant diff. For bugfixes, compare behavior at `{{BASE_SHA}}` and `{{TIP_SHA}}` where practical; return to the tip before finishing.
3. Write `{{EVIDENCE_DIR}}/verdict.md`. First line must be exactly `VERDICT: PASS`, `VERDICT: FAIL`, or `VERDICT: INCONCLUSIVE`. State the change type, commands/checks run and results, evidence filenames, and anything not verified.
4. Confirm `git status` is clean and HEAD is `{{TIP_SHA}}` on `{{BRANCH}}`.

Then output:

<promise>COMPLETE</promise>
