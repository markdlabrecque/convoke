# Task

Verify ticket #{{ISSUE_IID}} on branch `{{BRANCH}}` at `{{TIP_SHA}}`, based on `{{BASE_BRANCH}}` at `{{BASE_SHA}}`. Do not fix code.

## Issue

{{TICKET}}

## Rules

- Never edit tracked files, commit, push, or use `gh`. Keep HEAD at `{{TIP_SHA}}` on `{{BRANCH}}` and the worktree clean.
- Put verification output in `{{EVIDENCE_DIR}}`.
- Verify actual behavior using available tests and inspect the implementation and tests. Keep command output as reproducible evidence. Do not claim checks you did not run.
- This run targets the `spike-3` integration branch, not main. The owner explicitly performs Mac/Xcode and physical-iPhone testing after merge. This Linux container lacks Apple SDKs and hardware. Mark those checks Pending in the verdict rather than treating their unavailability alone as FAIL or INCONCLUSIVE. PASS means the available checks and code review support merging into spike-3, not that Apple-platform acceptance passed. A known code defect or failing available check still prevents PASS.
- Do not access a Mac or production host. For documentation tasks, check the instructions and honest Pending result fields; the owner fills in actual Mac/iPhone evidence later.

## Procedure

1. Classify the change as a bugfix or feature.
2. Run targeted checks and inspect the relevant diff. For bugfixes, compare behavior at `{{BASE_SHA}}` and `{{TIP_SHA}}` where practical; return to the tip before finishing.
3. Write `{{EVIDENCE_DIR}}/verdict.md`. First line must be exactly `VERDICT: PASS`, `VERDICT: FAIL`, or `VERDICT: INCONCLUSIVE`. State the change type, commands/checks run and results, evidence filenames, and anything not verified.
4. Confirm `git status` is clean and HEAD is `{{TIP_SHA}}` on `{{BRANCH}}`.

Then output:

<promise>COMPLETE</promise>
