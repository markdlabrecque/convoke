# Task

Implement ONE GitHub issue on the current branch, cut from `{{BASE_BRANCH}}`.

## Issue #{{ISSUE_IID}}: {{ISSUE_TITLE}}

{{TICKET}}

## Environment

- Convoke contains the Swift server in `server/`, protocol fixtures in `protocol/`, and the iPhone app and local ConvokeCore package in `ios/Convoke/`. The ticket is the implementation specification; there is no tracked root plan.md.
- The integration branch is `spike-3`. Factory opens PRs into that branch and automatically merges only after its CI gate passes. Changes to main are outside this run.
- This is a Linux container without Xcode, Apple SDKs, or a physical iPhone. Run all relevant available checks and record exact results. Write and inspect Apple-platform tests even when they cannot run here. Mark Mac/iPhone checks Pending for the owner after merge; their unavailability alone is not an implementation blocker or a claim that tests passed.
- The owner performs Mac/Xcode and physical-device acceptance after merge into spike-3. Do not contact a Mac or production host, invent hardware evidence, or weaken tests to hide a known defect. Model API or code defects still require investigation; only unavailable platform execution is deferred.
- You have no tracker access. Do not run `gh`, push, open a PR, comment on or close the issue. The orchestrator does that.

## Workflow

1. Explore the issue, relevant code, and tests.
2. Plan the smallest root-cause fix.
3. Add focused tests when appropriate, then implement.
4. Run relevant tests/checks and report the exact results.
5. Commit one change. The subject starts with `#{{ISSUE_IID}}: `; include `RALPH`, decisions, and blockers in the body. Never commit anything under `.sandcastle/`.
6. Stop after this issue.

If blocked or no code change is needed, do not commit; explain why. If a missing prerequisite is covered by another open issue, write `{{EVIDENCE_DIR}}/blocked.json` with the blocker issue number and evidence.

### Other open issues

{{CATALOGUE}}

When finished, output:

<promise>COMPLETE</promise>
