# Convoke Factory environment

Factory v2 project data is in `factory.toml`; executable workflow code and private
runtime dependencies come from the installed Factory bundle. There is no project
npm package or project workflow override. Common agent guidance is in
`../docs/agent-instructions.md`.

## Build the sandbox image

From the repository root:

```bash
docker build --pull=false \
  --build-arg AGENT_UID="$(id -u)" \
  --build-arg AGENT_GID="$(id -g)" \
  -t sandcastle-convoke-server .factory
```

The Dockerfile pins Swift 6.4.2 (matching Linux CI), Node 24.20.0, Pi 1.5.2 and
Playwright 1.65.1. The upstream Swift and Node image digests are pinned too. The
numeric image user must match the host UID/GID. `.dockerignore` excludes everything
except image source and the explicitly allowlisted `writing-tests` skill, including
`.env`, evidence, logs and worktrees. No provider
or tracker credentials are built into the image. OpenAI Pi receives per-run
credentials from the existing host Pi login; standard sandboxes do not need a
GitHub login.

The image includes the reviewed snapshot at `skills/writing-tests/SKILL.md`, copied
from the host's `~/.agents/skills/writing-tests/SKILL.md`. Pi discovers it at
`/home/agent/.pi/agent/skills/writing-tests/SKILL.md` without host skill mounts.
To update the guidance, refresh that snapshot, review the diff and rebuild the image.
Only this skill is allowlisted in `.dockerignore`; adding another requires explicit
review of its build-context inclusion.

On 2026-11-16 the skill-enabled image passed an offline, non-root check using Pi's
skill loader: discovery, prompt advertisement, readable content and no diagnostics.
An offline Chromium launch/DOM/cleanup smoke check also passed. Logs are in
`.factory/logs/image-writing-tests-{build,smoke}.log`. These image checks do not
claim ticket completion or a rerun of application tests. The rebuilt image is tagged
`sandcastle-convoke-server:latest`; `sandcastle-convoke-server:before-writing-tests`
retains the preceding image for rollback. Existing containers are unchanged.

This replaces the temporary local-only `Dockerfile.permissions` compatibility
layer. The image can now be built without any prior Convoke image.

## Inspect and operate

```bash
factory config explain --project "$PWD"
factory doctor --project "$PWD" --probe-filesystem
pi auth check --provider openai
factory selection explain <ticket-number> --project "$PWD"
```

Selection explanation reads GitHub but does not launch work. Dispatch, including
its dry run, can run analysis; request operator approval before using it as a
check. Normal launch also enforces Factory's isolated image/browser capability
check, sandbox setup checks and independent verifier checks.

The current policy selects `ready-for-agent`, excludes blocked/human-held tickets,
uses subtasks when available, and permits three concurrent runs across Factory's
shared board. Automatic squash merge is enabled. `required_checks = []` retains
Factory's all-checks gate; it does not disable CI gating. Scheduling is separate
host state and was left off during this setup. Ticket labels were not changed.

## Verification of this environment

On 2026-11-16 the rebuilt image passed:

- Numeric user and home/workspace write/rename/remove checks as UID/GID 1000:1000.
- Pi CLI version/help startup, Swift version and Node version checks.
- The selected Factory runtime's isolated Playwright/Chromium image capability gate.
- `swift build --package-path server --jobs 4`.
- `swift test --package-path server --jobs 4`: 51 tests, 1 opt-in Kokoro skip,
  0 failures.
- `bash ios/Convoke/scripts/test-portable-core.sh --jobs 4`: 73 tests, 0 failures.

Linux suites ran in a disposable source copy with no host credentials mounted.
Build and test logs are local ignored files in `.factory/logs/`. These checks do
not claim a real model invocation, ticket delivery, Apple-platform validation,
physical audio acceptance or an opt-in live Kokoro smoke test. See
`../docs/development.md` for platform and acceptance boundaries.
