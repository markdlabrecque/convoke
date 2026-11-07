# Task

Implement ONE GitHub issue on the current branch, cut from `{{BASE_BRANCH}}`.

## Issue #{{ISSUE_IID}}: {{ISSUE_TITLE}}

{{TICKET}}

## Environment

- This is the Convoke server/protocol repository. The repository plan is `plan.md`; the protocol specification and fixtures belong in `protocol/`. Server code belongs in `server/`.
- The repository may not yet have an established server stack or test suite. Inspect the existing files and issue before choosing or introducing tooling; avoid broad scaffolding unrelated to the issue.
- Tests run in the project-specific Linux container. Run the most relevant available checks and report commands/results honestly. If no relevant test command exists, say so.
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
