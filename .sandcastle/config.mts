// Project settings shared by main.mts and dispatch.mts. Edit this file when adapting to a project.
// Reference config for personal projects: GitHub issues and PRs, the Pi agent with GPT models, and
// PRs merged automatically once CI passes. Install it into a project as .sandcastle/config.mts.
// The client / Affinity Bridge reference (GitLab, Claude Code, MRs a person merges) is config.mts.

export const TRACKER = {
  kind: "github" as "gitlab" | "github", // picks tracker.github.mts
  host: "github.com",
  project: "markdlabrecque/convoke", // the GitHub repo, as gh -R takes it
  // Milestone (title). The dispatcher only picks issues in it, and the ticket graph looks for
  // blockers among its open issues. undefined = every open issue in the repo.
  milestone: undefined as string | undefined,
};

// The only three models this config uses (pi provider/id). Rough Claude equivalents: sol = Opus,
// terra = Sonnet, luna = Haiku. Every model below must be one of these; main.mts and dispatch.mts refuse
// to run otherwise.
const MODELS = {
  sol: "openai/gpt-6.1-sol",
  terra: "openai/gpt-6.1-terra",
  luna: "openai/gpt-6-luna",
};

// The Pi coding agent (https://pi.dev) runs the implementer and verifier in the container and the
// ticket analysis on the host. All of them use the host's pi login (Sign in with ChatGPT; check it with
// `pi auth check --provider openai`). Each container run gets a fresh OAuth access token from
// `pi auth print-bearer-token`, good for about an hour, so one implementer or verifier run must finish
// within that. Nothing goes in .sandcastle/.env.
export const AGENT = {
  provider: "pi" as "claude" | "pi",
  // The implementer's model comes from the ticket: every ticket must carry exactly one of these
  // labels. One without (or with two) is not started; the board says why.
  modelLabels: {
    "model:sol": MODELS.sol,
    "model:terra": MODELS.terra,
    "model:luna": MODELS.luna,
  } as Record<string, string>,
  model: MODELS.sol, // fixed: the verifier
  // Reasoning effort: "off" | "minimal" | "low" | "medium" | "high" | "xhigh".
  thinking: "high" as "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | undefined,
};

// After the verifier passes and the branch is pushed, Sandcastle opens a PR and merges it once every
// CI check on the pushed commit passes. This is a deterministic gate (ci.mts): failed checks, no
// checks, or checks still running at the deadline mean no merge, and the PR is left as a draft. CI must
// run on every PR (no `paths` filter), or PRs that touch no matching file will never merge.
export const MERGE = {
  auto: true,
  method: "squash" as "merge" | "squash" | "rebase",
};

// Every label Sandcastle filters on or writes. main.mts and dispatch.mts check they all exist in the
// repo at startup and offer to create any that are missing; declining quits the run.
export const LABELS = {
  // An issue must carry ALL of these to be picked.
  ready: ["ready-for-agent"],
  // An issue carrying ANY of these is never picked.
  exclude: ["blocked", "needs-human", "wontfix"],
  // Added when the implementer reports a blocker the graph can't resolve. Keep it in `exclude`.
  needsHuman: "needs-human",
  // Set once the work is merged: on a whole issue when its PR merges, on a parent once every one of
  // its sub-issues is closed. The `ready` labels come off; the issue stays open for you to close.
  done: "merged",
};

export const allLabels = () => [...new Set([...LABELS.ready, ...LABELS.exclude, LABELS.needsHuman, LABELS.done, ...Object.keys(AGENT.modelLabels)])];

// GitHub sub-issues.
export const SUBTASKS = {
  // true: a ready issue with sub-issues is a container, and each open sub-issue is a run of its own
  // (closed once its PR merges). false, or `--whole-issues`: every ready issue is one run.
  enabled: true,
};

// Ticket graph: dependency analysis and conflict holds (see graph.mts).
export const GRAPH = {
  model: MODELS.terra, // fixed: the read-only analysis on the host
  maxAnalysesPerPass: 5,
  analysisTimeoutMinutes: 10,
  // Paths whose overlap never holds a ticket back: exact file, or directory ending in "/".
  conflictIgnore: [] as string[],
  // Manifests of tickets that left the catalogue are deleted after this long.
  pruneAfterDays: 30,
};
