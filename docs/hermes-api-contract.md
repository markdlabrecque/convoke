# Installed Hermes contract: evidence and blocked integration

Evidence dates: initial inspection 2026-11-16; source-only follow-up and coordinator-supplied durable reconciliation 2026-11-17. Tracks [issue 62](https://github.com/markdlabrecque/convoke/issues/62), under [epic 61](https://github.com/markdlabrecque/convoke/issues/61).

**Disposition: H0 is NOT accepted. Runtime dependants remain gated.** This document can merge as accurate evidence without completing issue 62. No Hermes backend, phone approval, memory setup, or safe remote-stop implementation is enabled by this change.

## Authoritative owner decisions — 2026-11-17

The owner explicitly stated: **“I want Convoke to share the memory with the main Hermes agent.”** This supersedes the earlier owner-isolated memory requirement and proposed preferred exclusive-profile path. Convoke is intended to use **shared built-in memory in the configured main-agent profile**, not a dedicated profile or external provider. The decision is recorded in the latest [issue 62](https://github.com/markdlabrecque/convoke/issues/62) and [epic 61](https://github.com/markdlabrecque/convoke/issues/61) comments following [PR 77](https://github.com/markdlabrecque/convoke/pull/77), merged at `f35d6ec0366a37170d902daf2910eb79f5a275d0`.

- Stable Convoke owner/authentication identity, upstream header identity and active-turn lease identify and authorize Convoke work; **none partitions `MEMORY.md` or `USER.md`**. Explicit owner consent accepts sharing with the main agent, not unrelated users, multi-user access or removal of Convoke authentication.
- Reconnect creates a fresh transcript; Start/End on the same socket retains that session. Transcript freshness does not isolate shared memory or erase retained transcripts.
- B3's isolation-design blocker is superseded, **not a memory-acceptance pass**. Shared-memory semantics, retention, ordinary main-agent memory effects and concurrent main-agent writer behavior still need reviewed evidence. No global-memory integrity claim follows from B1 or this decision.
- No memory seeding, deletion, reset, configuration change, provider/profile provisioning, restart or live probe is authorized. Ordinary shared-memory effects must be understood and accepted before rollout, not exercised by this documentation task.

**Current architecture — unmodified Hermes, no maintained fork:** the owner subsequently withdrew isolated core-development approval. [Issue 78](https://github.com/markdlabrecque/convoke/issues/78) and [issue 84](https://github.com/markdlabrecque/convoke/issues/84) are stopped/blocked; preserve their experimental source for reference only. No core patches, private-API monkeypatches, source overlays, custom builds or plugin-delivered core replacements may ship. Do not resume, merge, publish, deploy or clean up those experiments. The experimental clone's origin points to installed source and must never be pushed to. Use unmodified official Hermes with supported public plugin APIs, or propose a different architecture for review.

**Next bounded investigation:** [issue 87](https://github.com/markdlabrecque/convoke/issues/87) assesses supported plugin reporting to Convoke, including real identity, delivery failure and exactly what each lifecycle observation proves. It is source/document work only, not plugin/server implementation or installation. Existing public hooks do not establish complete tool-resource closure; a handler-return or cancellation-request report is not an all-work cessation acknowledgement. Lost-admission recovery is a separate obligation. No weaker lease/unknown policy, silent tool restriction, uncertain POST replay, live probe, configuration/permission/memory change or restart is authorized. B1 remains reconciled; B2/B3 shared-memory acceptance/B4/B5 and runtime dependants remain gated.

## What remains in H0 / issue 62

- **Done:** B1's original probe is durably reconciled as failed/ceased; do not repeat it. The memory-isolation design decision is superseded, not an acceptance pass.
- **B2a, architecture first:** establish supported recoverable admission/ownership before effects and lost-response handling without a core patch or uncertain action replay. A reporting channel alone cannot create that guarantee.
- **B2b, architecture first:** establish exact supported resource coverage and real settlement on natural completion and cancellation, or retain unknown. Issue 87 must state what public-plugin reports can and cannot prove; a telemetry-only outcome does not satisfy closure.
- **B3:** review intended shared-memory semantics, retention/flush/reset limits, recall and concurrent main-agent writers. No isolated profile or separate Convoke reset is required or authorized.
- **B4/B5, separately authorized evidence:** after B2 design review, obtain safe one-time approval/control and successful/failed/incomplete/compressed/closed-stream evidence with exact private identities and a correct bounded harness.
- Reconcile the resulting source/live API, finite wire/auth/capability and concurrency contract before explicitly accepting H0. Missing controls remain blockers; merging evidence does not close the gate. Physical-iPhone acceptance belongs to issue 75, not H0.

## Evidence vocabulary and installation

- **Live** means an actual local HTTP result, not a capability flag proving execution.
- **Source** means inspected installed code. It is not a live exercise or a guarantee that every branch runs on this listener.
- **Required** means the intended Convoke interface/policy below, not an already implemented feature.
- **Blocked** means downstream work must not substitute a weaker control.

Read-only installation commands:

```sh
git -C ~/.hermes/hermes-agent rev-parse HEAD
git -C ~/.hermes/hermes-agent describe --tags --always
git -C ~/.hermes/hermes-agent status --short
```

Results: commit `3b421578588243f920886e6fe79a6faa87ea026e`, tag `v0.23.1`, clean working tree at inspection. Live `GET /health` also reports `0.23.1`. This fingerprints source on disk; it does not establish the running process's exact loaded commit.

Local API origin is `http://127.0.0.1:8642`; `/v1` is an API path prefix, **not** the prefix for `/api/sessions`. No public service was created. No production or password-vault access, nor direct Hermes source/config/permissions/global-memory edits were performed; the incomplete inference probe's possible memory effects are explicitly unproven below. A bounded inference request was authorized by the owner after initial read-only inspection. All further inference/tool/approval/stop exercises remain paused pending a reviewed recoverable-identity and bounded-cleanup contract. The original unknown-run quarantine has been reconciled as described below; that does not authorize new probes.

## Live evidence ledger

All credentials were used only in process memory, never command arguments/output/Git. The existing local Hermes dotenv supplied `API_SERVER_KEY`; it was not a vault reference. No credential provisioning or rotation was needed. Requests used Python `urllib.request`; JSON summaries printed structure/status only, not request, model, reasoning, tool, or transcript content. Identifiers below are synthetic placeholders, not captured real IDs.

| Request / observation | Actual outcome | What this does **not** prove |
| --- | --- | --- |
| Unauthenticated `GET /v1/models`, `/v1/capabilities` | Both 401 | Phone authentication is not implemented |
| Authenticated `GET /v1/models` | 200, advertises `hermes-agent` | Agent completion/tool behavior |
| Authenticated `GET /v1/capabilities` | 200; features/endpoints below | Approval execution or stop cessation |
| Authenticated `GET /v1/toolsets` | 200; enabled set below | All actions require approval |
| `GET /health` | 200, version `0.23.1` | Process source fingerprint or idle state |
| Authorized `POST /api/sessions` with `{}` | 201, new session object | Transcript retention/reset semantics after a real turn |
| Authorized `POST /api/sessions/<new-id>/chat/stream` with a fresh probe key | 200; initial session header matches create ID; two data frames, with session/run/sequence metadata | Successful terminal ordering, effective ID after compression, or any live stop/approval behavior |
| Probe terminated by outer 55-second command timeout | No terminal result captured; HTTP client process ended | Remote termination, successful denial, or successful bounded stop |

The inference prompt requested only a trivial fixed reply and explicitly no tools or memory changes. Its text is intentionally not reproduced here. No controlled tool/approval/stop request was subsequently submitted. No uncertain POST was retried. The empty session and inference may be retained by Hermes; no DELETE/reset/cleanup mutation was attempted.

### Harness defect versus upstream safety evidence

The probe incorrectly looked for `event` inside native session JSON rather than reading SSE `event:` lines. It printed two event names as absent, but their structural keys matched the initial run/message frames described in source. Do **not** call those two event names live-verified. Native session payloads use `seq`/`ts`; run-event payloads use a different envelope.

The 25-second socket timeout was an inactivity timeout, not an absolute wall-clock budget; heartbeat traffic can keep it open. The outer command killed the process at 55 seconds before its cleanup code ran. The probe did not persist the run/session IDs privately. At the time it therefore could not address `GET /v1/runs/{run_id}` or `POST /v1/runs/{run_id}/stop` for this exact run. This is a harness failure, not proof that Hermes ignored a correctly issued stop. Fixing the parser or timeout does **not** authorize another live run.

**Historical unknown-run quarantine; B1 now reconciled:** remote cessation was unknown after the harness exited. On 2026-11-17 the coordinator reported read-only durable reconciliation in [issue 62 comments](https://github.com/markdlabrecque/convoke/issues/62). This follow-up incorporates that supplied observation; it did not repeat the database/HTTP investigation. Connection closure, elapsed time, an idle listener or `stopping` alone still cannot establish cessation.

The coordinator verified the listener's Hermes home and open state DB, then used SQLite `mode=ro` and `query_only` to match exactly one API admission by **both** the original 2026-11-17 06:47:12–06:48:11 UTC command window and equality to the known synthetic probe input. The admission was terminal/failed, generation 1, with committed `gateway.admission.result.v1`: `failed=true`, `completed=false`, `interrupted=false`, `failure_reason=timeout`, `tool_call_count=0`; no nonterminal worker remained for that session. Both API admissions in that DB were terminal. No real identifiers, input or receipt bodies are reproduced here. Session last activity at 06:52:11 UTC is **not** an exact settlement timestamp.

**Observed versus inferred:** the supplied durable record plus source settlement ordering supports cessation of this exact canonical probe, not successful inference, cancellation, bounded-stop acceptance, or memory integrity. `session_authority.SessionAuthority._drain` awaits `_execute_claimed` before `session_settlement_recovery.settle_and_deliver`; `session_results.finish_result` commits the receipt and terminal admission. The recovered durable request ID returned HTTP 404 from `GET /v1/runs/{id}`: this is **not** live terminal-status evidence. Native admission lacked persisted `run_owner_scope`; its public alias is observer-lifetime state. Knowing a DB request ID does not establish HTTP control ownership.

No documented read-only run-by-key/list route was established for routine lost-acceptance recovery. Keep new live probes paused until B2's identity and cleanup contract is reviewed. Do not guess IDs, stop unrelated work, retry uncertain POSTs, resolve unknown admissions, restart the gateway or alter policy to obtain a pass.

The probe computed built-in-memory hashes before inference, but the process did not reach its after-run comparison and did not retain those hashes. **After-run memory checks are unproven**; there is no claim that the run left global memory unchanged. No write was requested, and no memory content/hash is published here.

## Required capabilities and exact upstream interfaces

Live `/v1/capabilities` reports bearer authentication and these flags as true: `session_resources`, `session_chat`, `session_chat_streaming`, `run_status`, `run_events_sse`, `run_stop`, `run_approval_response`, `approval_events`, `tool_progress_events`, `run_submission`, and `run_unknown_resolution`. Continuity/key headers are `X-Hermes-Session-Id` and `X-Hermes-Session-Key`. `memory_write_api`, `admin_config_rw`, `jobs_admin`, `audio_api`, and `realtime_voice` are false. Durable run idempotency is advertised with 86400-second retention; it does not authorize automatic retries of uncertain actions.

`run_unknown_resolution=true` indicates the authority branch is enabled. It is essential to inspect the authority implementation as well as the legacy adapter: their approval request shapes differ.

All protected upstream requests carry `Authorization: Bearer <server-only-Hermes-key>`. JSON POSTs carry `Content-Type: application/json`; native stream responses are SSE. Never send this key to the phone, put it in a URL, or forward it across an origin redirect. No request override may expand tools, provider access, permissions, or profiles.

| Interface | Source contract / required usage | Live execution evidence |
| --- | --- | --- |
| `POST /api/sessions` | `{}` creates a new ID; 201 `{"object":"hermes.session","session":{"id":"<session>"}}` (projection, additional metadata omitted) | Create 201 verified |
| `POST /api/sessions/{id}/chat/stream` | `{"message":"<user-text>"}`, stable server-derived `X-Hermes-Session-Key`; use freshly created transcript ID in path | Initial stream only; terminal behavior blocked |
| `GET /v1/runs/{run_id}` | Poll exact known **owned** run; response includes `status`, `run_id`, `session_id`; authority projection can include `admission_id`, `execution_generation`, `pending_controls`, output/usage | Coordinator's recovered native durable request ID returned 404; no successful live status evidence; never forward raw output/status object to phone |
| `POST /v1/runs/{run_id}/approval` | Authority: **exactly** `{"request_id":"<prompt>","execution_generation":1,"choice":"once"}` or `choice:"deny"` | Not exercised; generation must be captured/validated, not guessed |
| Same approval route, legacy branch | `{"request_id":"<request>","choice":"once"}` / `"deny"`; do not send `all`, `resolve_all`, `session`, or `always` | Not exercised; do not silently switch to this body if authority rejects |
| `POST /v1/runs/{run_id}/stop` | `{}`; may return `{"run_id":"<run>","status":"stopping"}` (authority can add `admission_id`) or an already-terminal status projection | Not exercised; ack ≠ cessation |
| `GET /v1/runs/{run_id}/events` | Advertised native run-event SSE; separate framing from session-chat stream | Discovery only; no replay/resume implementation authorized |

Session key validation in source strips whitespace, rejects CR/LF/NUL, limits to 256 characters and requires API-key authentication. Effective session IDs must also be bounded/validated before reuse in a path/header. A client-supplied key/ID is not authentication or authority.

### Session stream ordering and final-answer gate — source only

Sources: `gateway/platforms/api_server.py::_handle_session_chat_stream`, `_SessionEventQueue`; `api_server_runs.py::terminal_run_status`; `api_server_openai_routes.py::_response_status`, `_result_flags`.

A sanitized **source-derived** successful sequence (not the live transcript):

```text
HTTP 200
X-Hermes-Session-Id: <initial-session>
event: run.started
data: {"session_id":"<initial-session>","run_id":"<run>","seq":1,"ts":0,"user_message":{},"runtime":{}}

event: message.started
data: {"session_id":"<initial-session>","run_id":"<run>","seq":2,"ts":0,"message":{"id":"<message>","role":"assistant"}}

[zero or more delta/commentary/tool/approval events, none eligible for speech]

event: assistant.completed
data: {"session_id":"<effective-session>","run_id":"<run>","seq":3,"ts":0,"message_id":"<message>","content":"<final-answer>","completed":true,"partial":false,"interrupted":false,"runtime":{}}

event: run.completed
data: {"session_id":"<effective-session>","run_id":"<run>","seq":4,"ts":0,"message_id":"<message>","completed":true,"partial":false,"interrupted":false,"messages":[],"usage":{},"runtime":{}}

event: done
data: {"session_id":"<initial-session>","run_id":"<run>","seq":5,"ts":0}

EOF
```

Actual SSE uses `event:`/`data:` at column zero, a blank line between events, and optional `: keepalive` comments. HTTP headers, bracketed annotation and EOF above are explanatory, not SSE fields. Numbers/placeholders illustrate shape, not captured values. Sequence advances for every emitted event, so real terminal sequence numbers need not be 3/4/5. `_SessionEventQueue` stamps native payloads with `session_id`, `run_id`, `seq`, `ts`, not necessarily JSON `event`.

Source emits `assistant.completed` even for failed/cancelled results: its name alone is **not** success. `interrupted` maps to `run.cancelled`; `failed`, `partial`, or `completed:false` maps to `run.failed`. Exceptions can produce `error` followed by `done`, without a successful terminal pair. Bot Chat handoff has another `run.queued`/error path: never target canonical Bot Chat; use a fresh API transcript. Reject failed/incomplete/queued/unknown outcomes for speech. Only a validated matching successful `assistant.completed` + `run.completed` pair can release final text for synthesis; validate terminal completion of the stream, not deltas or `done` alone. Live ordering remains blocked.

Compression can change the effective ID in terminal events while the initial HTTP header and final queue-stamped `done` still identify the original session. Validate and adopt terminal effective ID **within this connection only** after a successful terminal sequence; never overwrite it with `done` or reuse it after reconnect. Actual compression ID-change behavior is source-only, not live-verified. Non-streaming `/chat` can perform a policy-gated retry; it is not an acceptable substitute for the chosen no-automatic-retry stream contract.

### Approval identity and one-time choices — source only

Sources: `api_server.py::_approval_request_event`, `_register_session_stream_approval`; `api_server_runs.py::_handle_run_approval`; `api_server_authority_runs.py::respond_run`; `gateway/session_api_turn.py::run_api_turn`; `tools/approval.py::resolve_gateway_approval`; `tools/approval_gateway_wait.py`.

Approval events may contain untrusted command/description data. Source redaction is not a guarantee that tool arguments are safe to log/speak. The stream bridge carries a `request_id` and may carry `execution_generation`; the authority status/control projection is another generation source. The authority responder requires the exact current prompt and integer generation, rejects extra body keys, checks the admission is started, and refuses stale/missing prompts. Examples of source errors: `invalid_params` (400), `stale_generation` / `approval_not_pending` (409). Legacy response is `{"object":"hermes.run.approval_response","run_id":"<run>","choice":"once","request_id":"<request>","resolved":1}`; **do not assume authority returns this legacy response**. Authority success response must be live-verified before implementing its decoder.

Source choices can include `once`, `session`, `always`, `deny`, or deny-only restrictions. Convoke accepts only explicitly advertised `once`/`deny`, binds the exact pending request, and never promotes consent to persistent/session-wide permission. Legacy queue resolution pops an exact request under a lock; replay finds no pending approval (409). Gateway wait captures `timeout_s`, fails closed on timeout/notify failure/interruption; coalesced `once` applies to the leader, not all follower actions. None of this is live execution-after-approval/replay evidence. Authority generation fencing, restricted-choice behavior, and successful resolution require the authorized controlled exercise **after the recoverable-identity/cleanup gate is reviewed** and a safe tool setup is agreed.

### Stop/lost-ID control — blocker, not a timeout fallback

Sources: `api_server.py::_drain_session_stream_task_on_disconnect`, `_run_agent`; `api_server_runs.py::_handle_stop_run`; `api_server_authority_runs.py::stop_run`; `gateway/session_api_turn.py::observe_api_turn`, `schedule_orphan`.

- Legacy native disconnect interrupts an agent if one is referenced and then awaits the task with no explicit timeout. No-agent path cancels/awaits the task.
- The enabled authority route delegates `_run_agent` into the durable FIFO. `observe_api_turn` explicitly shields its waiter: cancelling the request removes its observer **but keeps the canonical turn alive**. Admission can also commit while its caller is cancelled; orphan scheduling can still run it.
- Authority stop cancels an exact queued admission or interrupts the exact running generation; running return is `stopping`, not a terminal-cessation guarantee. `unknown_execution` is a refusal, not completed/cancelled.
- No verified bounded stop exists for a native stream closed before the client knows its generated run ID. The current failed probe demonstrates a lost-ID evidence gap, not that a correctly issued stop failed.
- A local deadline/socket close/task cancellation/forced success response cannot prove upstream cessation. Keep the owner's active-turn slot quarantined on uncertainty, do not retry or admit another turn, and report a fixed stop-unconfirmed error. A finite HTTP timeout bounds the client wait only.

Selecting `/v1/runs` instead of session chat is **not** an accepted fallback. The detailed source trace and narrow upstream options below explain why route selection alone does not fix B2. Upstream bounded cessation still needs proof or an approved capability change.

### Recoverable identity trace and upstream remediation — source only

The following citations refer to the installed clean commit, not mutable latest documentation. Source root: [`NousResearch/hermes-agent@3b421578`](https://github.com/NousResearch/hermes-agent/tree/3b421578588243f920886e6fe79a6faa87ea026e). All paths in this subsection are relative to that root.

| Boundary | Source-owned finding | Consequence / gate |
| --- | --- | --- |
| Native session submission | `gateway/platforms/api_server.py::APIServerAdapter._prepare_session_chat` constructs run kwargs without a caller `request_id` or `run_owner_scope`; `_handle_session_chat_stream` creates a UUID public run ID. `gateway/session_api_turn.py::admit_api_steps` can use an internal request ID, active run ID, or generated identity, but native HTTP preparation does not expose caller identity binding. | A pre-created session ID is a transcript identity, not a pre-admitted turn ID. Supplying arbitrary JSON `request_id` is not a supported recovery contract. |
| Native alias lifetime | `session_api_turn.py::run_api_turn` binds the stream's approval/public alias to an admission and removes it in `finally`; `observe_api_turn` shields the canonical waiter while dropping the observer on cancellation. | Initial frames can precede durable admission; disconnect may lose the alias while work remains. B1's durable ID recovery is not a reusable HTTP recovery mechanism. |
| Runs submission | `api_server_runs.py::_handle_runs`, `_admit_run_to_authority`, `_run_idempotency_identity`: server UUID, scope from profile/credential, fingerprint of body plus session key; ledger lookup before concurrency, then atomic reserve, then authority admission with persisted owner scope. | No caller-assigned public run ID. The ledger reservation and authority admission are distinct steps; a recovery design must distinguish reserved/not admitted, queued, executing, terminal and unknown, including crash windows. |
| Lost acceptance lookup | `api_server_runs.py::_http_routes`, `_handle_runs`, `_replay_or_conflict`; `api_server_run_idempotency.py::RunIdempotencyStore.lookup`. The registered ordinary run routes have GET by run ID, not GET by idempotency key. Official `website/docs/user-guide/features/api-server.md`, “Runs API” / “POST /v1/runs”, documents exact **POST replay** returning 202 and the original run ID. | Internal `lookup` is not a public read-only lookup endpoint: it opens `BEGIN IMMEDIATE`, can extend retention, and prunes stale terminal rows before reading. Exposing it unchanged would not meet a strictly read-only recovery contract. No supported HTTP key-to-run lookup or two-phase pre-admission identity was found in these routes. **Do not retry an uncertain POST under the current owner contract**, even though upstream documents deduplication. |
| Owned status | `api_server_runs.py::_request_owns_run`, `_load_owned_run`, `_durable_run_status`; `session_api_turn.py::owns_api_run`; `api_server_authority_runs.py::run_admission`, `run_projection`. Authorization precedes projection, using an in-memory owner, scoped ledger record, or persisted admission owner stamp. | A 404 is neither no-admission nor cessation. Profile/credential scopes hash the current API credential; rotation is not transparent recovery authority. Durable run scope is distinct from Convoke's stable authenticated owner/header identity; neither partitions built-in memory. |
| Freshness if route changes | `_handle_runs` selects explicit `session_id` before declared session key; otherwise a stable key selects its retained conversation and history. Official API guide, “Conversation and terminal-result semantics”, confirms this. | Sending only the stable header key to Runs can resume history, violating fresh transcripts. A reviewed alternative must select a fresh explicit session every connection, retain the configured main-agent profile for intended shared memory, and never use a response chain. |

**B2 design requirements and historical options, not implementation authorization:** core development under issues 78/84 is now stopped. Any integration must use unmodified official Hermes and supported public APIs, or a separately reviewed different architecture. Issue 87 assesses plugin reporting, not a presumed fix for admission recovery or general cessation. The capabilities below remain requirements/options for review; they do not authorize adding endpoints to Hermes.

1. **Required recovery capability (currently missing):** authenticated read-only lookup by a caller-persisted unguessable admission key, with owner scope and target bound durably before work can execute. Alternatively expose a caller-known turn identity / reserve-then-submit protocol with the same guarantees. Return bounded metadata only (no prompt/output), exact run/admission/generation and explicit reserved/queued/running/terminal/unknown state. Define conflicts, crash windows, retention/expiry, credential rotation and “not found” semantics. Lookup must never admit, replay, resolve or restart work. A local journal alone cannot close a server-generated-ID lost-response window.
2. **Explicit policy revision only:** the owner could separately approve exact same-key POST reconciliation after reviewing deduplication, ledger/admission crash windows and retention. That is not permission granted here, does not solve bounded stop or background lifetime, and must never become a fresh-key retry. No alternate route is selected now.
3. **Remain blocked:** if neither recovery interface nor policy revision is accepted, retain the native route as evidence only and keep runtime work gated. Read-only operational DB reconciliation is an exceptional owner-supervised procedure, not permission to embed SQLite access in Convoke.

### Cancellation, settlement and delegated work — source only

- `gateway/platforms/api_server_authority_runs.py::stop_run` cancels an exact queued admission (rechecking a queued→started race), or calls authority interrupt for a running generation and returns `stopping`. Unknown execution is refused. `gateway/session_authority.py::SessionAuthority.interrupt` generation-fences the signal, latches a pre-adoption stop if needed, calls `agent/interrupt_compat.py::request_hard_interrupt`, and returns without waiting for settlement.
- `agent/interrupt_control.py::InterruptControlMixin.interrupt` aborts the active request, signals agent execution/tool-worker threads and propagates hard interrupt to `_active_children`. **Active inline children are signalled; it is incorrect to say all children survive.** Signal success is not a join, process-exit acknowledgement or finite cessation bound.
- Background delegations are explicitly different: `SessionAuthority.interrupt` says they continue and report back; session `/stop`, close/reset have broader semantics. `gateway/session_ancillary.py::_interrupt_delegations` selects the session's delegations; `tools/async_delegation.py::interrupt_for_session` returns a count of successful signal calls, not terminal joins. `refuse_for_session` can fence new dispatches during session ending. These are source seams, not an accepted non-destructive HTTP cleanup API; close/reset must not be substituted for run stop or used on unrelated sessions.
- Official `website/docs/developer-guide/subagent-lifecycle-api.md` distinguishes `CANCEL_REQUESTED` from terminal results, describes cooperative cancellation and in-process handle retention, and refuses reconnect replacement after process restart. This plugin API is **not** `/v1/runs` or a promise that HTTP run stop controls all background work.
- `SessionAuthority._drain` / `_execute_claimed`, `gateway/session_settlement_recovery.py::settle_and_deliver` and `gateway/session_results.py::finish_result` own canonical terminal settlement. A committed receipt is stronger evidence than observer EOF or adapter acknowledgement, but a parent receipt alone does not prove all separately managed background delegates ceased. Adapter shutdown/interrupted status must not be confused with a joined execution.

**Required upstream cleanup contract:** exact owner/turn/generation identity recoverable before action; an explicit scope covering queued work, adopted agent, inline children, background delegates and any owned tool processes; fence new child dispatch; request stop; await source-owned terminal acknowledgements for that scope; return terminal only after settlement, otherwise explicit unknown/stop-unconfirmed. No finite wall-clock cessation guarantee was established in the inspected call chain. An API deadline must bound the wait while preserving uncertainty, not manufacture stopped state. Excluding delegation/tools would require an explicitly approved, enforced capability restriction—not a no-tools prompt or a silent requirement downgrade. No such restriction was configured here.

**Next live gate:** coordinator/owner first reviews the identity and full-lifetime cleanup design (including lost acceptance before ID, queued→started race and approval-wait). Only then separately authorize a bounded, non-destructive fixture with privately journalled exact IDs. Demonstrate terminal receipts for the defined child scope as well as failed/unknown/refused cases before lifting B2. B1 clearance alone is insufficient.

## Profile, memory, retention, destructive tools and concurrency

**Source:** Default requests use the listener's current/default profile. `/p/<profile>/...` uses profile middleware and profile-scoped authentication; unsupported profiles fail closed. Convoke must pin the configured main-agent profile/origin for intended shared memory and must not expose arbitrary profile selection. No new/modified profile was created.

`agent/agent_init.py` constructs built-in `MemoryStore` without an owner/session-key parameter. `tools/memory_tool_store.py::_target_path` uses the profile memory directory's `MEMORY.md`/`USER.md`. An external provider can receive gateway identity (`agent/agent_init_memory_provider.py::_memory_provider_init_kwargs`), but that does not retrofit isolation into built-in files. `api_server_memory_sessions.py` caches external managers by transcript lifecycle; this is not proof of restart retention keyed to owner.

**Prior read-only local config projection:** built-in memory and user profile are enabled; `memory.provider` is not configured. No memory content was printed. A stable key is an identity interface, **not a partition of those files**. Shared built-in memory with the configured main agent is now the intended product behavior, explicitly approved by the owner; cross-reconnect/restart retention and ordinary shared-memory effects remain unverified. Do not disable memory, seed/delete files, reset state, change configuration or install a provider to obtain acceptance.

### Historical isolation research — source only, not current recommendations

The following options were researched before the owner's explicit sharing decision. Preserve them as historical source findings only: **do not select/provision an exclusive profile or external provider for the current scope**. The prior preference for a dedicated exclusive-owner profile is superseded.

Primary official docs at the installed commit: [Profiles](https://github.com/NousResearch/hermes-agent/blob/3b421578588243f920886e6fe79a6faa87ea026e/website/docs/user-guide/profiles.md), [Memory Providers](https://github.com/NousResearch/hermes-agent/blob/3b421578588243f920886e6fe79a6faa87ea026e/website/docs/user-guide/features/memory-providers.md), and [Memory provider plugin contract](https://github.com/NousResearch/hermes-agent/blob/3b421578588243f920886e6fe79a6faa87ea026e/website/docs/developer-guide/memory-provider-plugin.md). These are local official documentation inspected read-only, not claims of live provider acceptance. Paths below are installed source relative to the same commit.

| Option | What source/docs support | What must be decided/proved |
| --- | --- | --- |
| **Dedicated single-owner profile with built-in files** | Profiles isolate Hermes state by `HERMES_HOME`; `tools/memory_tool.py::get_memory_dir`, `memory_tool_store.py::MemoryStore._target_path` use that home's `memories/MEMORY.md` and `USER.md`. Files survive fresh transcript IDs and ordinary process restarts by storage design. Official profiles guide warns two writers to one home share/compound memory. | **Inference, not live proof:** exclusive owner→profile mapping could implement single-owner isolation without a provider. It is profile-level isolation, not dynamic header-key partitioning, and not an OS/tool sandbox. Requires explicit acceptance of that mapping, separate authorized blank profile/routing/auth setup, no clone of existing memory, no shared writers, and cross-session/restart/isolation/retention acceptance. No profile is created or selected here. |
| **Bundled RetainDB provider** | `plugins/memory/retaindb/__init__.py::RetainDBMemoryProvider.initialize` uses project partition and `kwargs.user_id` (default `default`), a fresh session ID, remote client and profile-local durable write queue; `_Client.get_profile` reads by user/project rather than transcript. | It does **not** directly map `gateway_session_key` to user ID. The exact executing authority route's identity must be traced/verified; passing a stable header does not establish stable owner partitioning. Requires credentials/service, approved data export/retention and provider setup; no network/provider call or initialization was performed. |
| **Bundled ByteRover provider** | `plugins/memory/byterover/__init__.py::ByteRoverMemoryProvider.initialize` binds storage to `<hermes_home>/byterover`, not a header/user namespace. Official provider docs describe persistent context. | Profile-scoped alternative, not owner-key isolation within a shared profile. Requires external `brv` availability/setup and lifetime/retention acceptance; not installed/configured/run for this task. |
| **Catalog provider (e.g. Honcho)** | Official provider guide describes gateway peer aliases/pinning and cross-session modeling. `agent/agent_init_memory_provider.py::_memory_provider_init_kwargs` forwards gateway identity and profile identity to providers. | Documentation is an option, not installed implementation evidence for a chosen plugin revision. No catalog plugin source was fetched or installed. Review the chosen revision's actual API→owner mapping, cross-session recall, restart flush and privacy before selecting. Pinning all gateway users to one peer is sharing, not isolation unless the profile is exclusively this owner. |
| **Existing main-agent profile shared built-in memory — current product choice** | Current built-in files and no configured external provider, per prior sanitized config observation. | The explicit owner decision accepts sharing with the main Hermes agent. It does not accept unrelated users or waive authentication. Semantics, retention and concurrent main-agent writer behavior still require evidence; no setup/mutation is authorized here. |

External providers are **additive**: the official provider guide states built-in files remain active alongside the provider. Selecting an isolated provider alone therefore does not eliminate the existing global-profile memory surface. `agent/agent_init_memory_provider.py::resolve_memory_provider` also warns and returns no external provider when unavailable, leaving built-in memory. Under the former isolation requirement, provider-only isolation would therefore have been insufficient. That design requirement is superseded; no external provider is selected or required now. Do not invoke provider initialization/status/setup merely as a “read”: initialization can create queues/directories, seed identity or start background syncing.

`gateway/platforms/api_server_memory_sessions.py::ApiServerMemorySessions` is an in-process `(profile home, transcript session ID)` manager cache, with exclusive checkout, idle eviction, and shutdown flush. It is not an owner-key store or restart persistence guarantee. Fresh transcripts intentionally do not inherit that cache; durable recall and pending-write settlement must be proved independently. Official provider docs describe turn sync, session-end extraction and mirrored built-in writes: these operations also matter to the definition of a fully settled cleanup, beyond a parent terminal receipt.

**B3 revised evidence gate:** the isolation-design choice is superseded by explicit shared-memory consent. Before claiming acceptance, define transcript and shared built-in-file retention, ordinary main-agent read/write effects, and any pending-write/flush settlement on the selected route. Establish fresh A/B transcript IDs with intended shared recall across fresh transcripts and ordinary restarts, without claiming header-key partitioning. Establish behavior when the main agent writes concurrently: Convoke's owner lease does not lock that writer or prove safe shared-file updates. Define any reset as a separate owner-authorized operation, not an isolated Convoke namespace reset. Source storage design supports feasibility, **not observed retention, concurrent-write safety or global integrity**. Restart, memory writes, resets and live acceptance probes remain unauthorized here; any future fixture requires separate bounded approval. No global content was inspected and B1 gives no memory-integrity evidence.

**Accepted application policy:** each authenticated WebSocket reconnect creates a fresh transcript, never reloads history or resumes a prior session; Start/End on the same socket keeps that session. A single configured owner identity and its stable upstream key survive server restarts/token rotation for authentication/turn ownership, not file partitioning. The configured main-agent profile supplies intended shared built-in memory. Transcript freshness does not erase Hermes-persisted history. The owner has not approved destructive transcript cleanup, provider migration, or any global-memory reset; do none. Memory reset is not reconnect. Exact upstream retention/deletion and shared-memory persistence/effects remain unverified.

**Live tool exposure:** `/v1/toolsets` reports enabled `web`, `browser`, `terminal`, `file`, `code_execution`, `vision`, `image_gen`, `skills`, `todo`, `memory`, `session_search`, `connections`, `delegation`, `cronjob`. These execute server-side. Approval guards for dangerous actions are not an exhaustive sandbox or a promise that every write/destructive action prompts. A no-tool prompt is not enforced capability isolation. Do not send a destructive command just to elicit approval. A non-destructive, narrowly understood approval-triggering fixture without permission/config expansion was not established before quarantine; controlled approval/stop acceptance remains blocked.

**Concurrency:** one active turn per authenticated owner, across connections/restarts as required by runtime safety handling. Reserve the slot before any upstream session/action request; concurrent submit receives fixed `busy`. Shared `X-Hermes-Session-Key` is not a lock; no safe parallel-memory evidence was obtained. The Convoke owner slot does not serialize the main agent or other profile writers. Their concurrent built-in-memory behavior remains an evidence gate; do not disable them, alter their configuration or claim global integrity to obtain a pass. Unknown remote lifetime keeps the slot quarantined until reconciled. A process restart is not evidence of remote cessation and must not silently clear unknown ownership. Recovery after abrupt process death remains out of scope, not falsely guaranteed.

## Required Convoke wire/auth interface (gated design, not shipped)

The following is the concrete proposed handoff for separate server/client tickets, conditional on H0 remediation. It is **not live Hermes output**, an implemented schema, or authorization to start dependants. `ios/Convoke/Core/ResponseAccumulator.swift` rejects unknown types/extra keys. Existing `/conversation` has only `user.text` input and ordered `agent.text`/`agent.audio`/`agent.done` output. Therefore unsolicited new messages break legacy clients.

### Selection and authentication

- Missing backend setting remains `openai`, preserving generic non-streaming requests, voice prompt and history behavior. Hermes is explicit backend opt-in, never inferred from a URL/model name.
- Hermes clients offer WebSocket subprotocol `convoke.hermes.v1` on `/conversation`; the Hermes server authenticates **before upgrade or remote creation** and echoes that exact selection. Missing/unsupported selection is a fixed 426 refusal; invalid/missing bearer credential is 401. No fallback into unauthenticated generic handling in Hermes mode. Generic mode does not emit the new events.
- Phone uses `Authorization: Bearer <separate-Convoke-client-token>` over private WSS to its provisioned origin only. Never reuse the Hermes credential. No query credentials, cross-origin redirects, credential downgrade to WS, or arbitrary endpoint token forwarding. A new client without provisioned Hermes mode can still consume legacy text/audio/done; it cannot downgrade an authenticated Hermes session to obtain approval implicitly.
- Server configuration supplies stable owner ID; authenticate then derive `convoke:<configured-owner-id>` as the upstream key. Constrain owner ID to 1–100 ASCII letters/digits/`-`/`_` to stay within the 256-character upstream header cap. Client cannot select owner, profile, key, session, run or generation. Token rotation keeps owner ID/key. This header is an identity interface, never a built-in-memory key enforcement mechanism; intended main-agent sharing does not weaken authentication or authorize other users.
- Factory input is an authenticated-owner value, not raw client identity fields. Per-connection session owns random transcript/turn/connection generations, effective session ID, run ID, current approval mapping, deadlines and cancellation. Shared factory holds no mutable per-connection state.

### Exact finite application messages

All JSON frames remain at most 32768 UTF-8 bytes. Except the separately bounded untrusted approval label, status/error fields are fixed codes/opaque synthetic tokens, never upstream prose. Reject unknown types, extra fields, invalid types/choices, binary frames, stale generations, or invalid ordering. These examples define proposed exact field sets:

```json
{"type":"agent.status","code":"working"}
{"type":"agent.status","code":"waiting_for_approval"}
{"type":"agent.status","code":"stopping"}
{"type":"agent.error","code":"stop_unconfirmed"}
{"type":"agent.approval.request","token":"<opaque-token>","label":"<untrusted-display-only>","choices":["approve","deny"],"expires_in_ms":30000}
{"type":"user.approval.response","token":"<opaque-token>","choice":"approve"}
```

`agent.status.code` is exactly `working | waiting_for_approval | stopping`. `agent.error.code` is exactly `busy | upstream_unavailable | upstream_failed | incomplete | deadline_exceeded | approval_denied | approval_expired | approval_invalid | approval_unsupported | stop_unconfirmed | protocol_error`. Error UI text is a local fixed mapping. `stopping` is never rendered as stopped. `stop_unconfirmed` terminates the local conversation while quarantining upstream ownership, not marking success.

Approval token: 32 random bytes encoded as 64 lowercase hex characters, generated by Convoke, distinct from Hermes request/run IDs. Bind server-side to authenticated owner, connection, turn generation, exact run/request/generation, allowed choices and expiry; consume atomically **before** at-most-once upstream POST. Never accept client-supplied Hermes IDs or retry a lost approval acknowledgement. Token/credentials/IDs are not logged. Display label is escaped plain text, 1–512 UTF-8 bytes, never truncated into misleading partial consent; if a safe complete label cannot fit, refuse/stop rather than approve unseen action. Never speak it.

`expires_in_ms` is an integer 1–30000, computed as the smaller of remaining absolute turn budget, captured upstream approval window, and 30 seconds; no timer reset extends the turn. Failure to establish the upstream window/generation is a blocked/unsupported approval, not a guessed default. Deny-only upstream cards use `choices:["deny"]`. A response choice is exactly `approve | deny`, must be offered, and maps to upstream `once | deny`. Duplicate, expired, stale, cross-owner/connection/turn, terminal or stopped tokens are rejected without a second POST. Expiry/disconnect/denial/legacy client/unsupported choice must stop the turn, invalidate all tokens and never yield successful `agent.done`.

Ordering: `user.text` → `working` → zero or more permitted status/approval frames → verified final-answer gate → unchanged `agent.text`, sequential zero-based audio chunks, matching `agent.done`. No approval or additional status after final-answer speech starts. An error is terminal, at most once, never followed by successful done/audio. `busy` rejects the offending connection/turn without cancelling another connection's active run. Local Stop/End conversation must invoke the runtime stop owner, not merely cancel speech. Preserve existing backpressure, close handling and EOF-plus-playback-drain microphone gating. PCM stays 24 kHz mono signed 16-bit little-endian, each decoded chunk ≤16384 bytes, total ≤8 MiB; metadata does not weaken those limits.

No absolute turn budget or remote-stop deadline is accepted yet: those numbers cannot establish bounded cessation. The runtime ticket must obtain verified upstream stop control before implementation/acceptance. This is why the wire proposal is gated rather than a ready-to-implement runtime contract.

## Blockers and minimal owner decisions

| Blocker | Required evidence / explicit remediation decision | Scope implications |
| --- | --- | --- |
| B1: Original probe lifetime — **reconciled** | Coordinator-supplied read-only durable terminal receipt plus awaited-execution settlement ordering establishes canonical probe cessation; recovered request ID returned 404, not live terminal status. | Does not prove cancellation/stop, successful inference or memory integrity; does not authorize new probes |
| B2: Lost-ID and scoped settlement — **open; architecture blocked** | First review a no-core-patch recovery/cleanup architecture. Issue 87 assesses supported plugin observations, correlation and reporting gaps; separately establish recoverable admission before effects and full-lifetime evidence on normal completion and cancellation. Only then authorize queued/running/approval-wait, close-before-ID and child/delegation evidence. | Issues 78/84 core implementation approvals are withdrawn. Plugin telemetry, handler return, parent terminal or stop acknowledgement alone cannot clear the lease; route switching and uncertain POST replay are not accepted fixes |
| B3: Isolation design — **superseded**; shared-memory acceptance — **open** | Owner explicitly chose shared built-in memory with the configured main-agent profile. Establish semantics, retention, ordinary main-agent effects, cross-transcript/restart recall and concurrent main-agent writer behavior before acceptance. | No exclusive profile/provider is required or recommended now; no seeding/deletion/reset/config changes or probes authorized. Stable identity/header/lease does not partition files; sharing consent does not waive Convoke auth or admit unrelated users |
| B4: Safe approval exercise and wire variants — **open** | After B2 design review and explicit probe authorization, agree on a non-destructive approval-triggering fixture without expansion; verify authority generation/body/success/error shapes, one-time execution, deny, expiry, replay and stop. | B1 clearance does not lift the coordinator's live-probe pause; no policy expansion authorized |
| B5: Missing terminal/compression/error evidence — **open** | After B2 review and explicit authorization, capture sanitized success, failure/incomplete, effective-ID change and stream-close outcomes with privately retained IDs and a correct absolute-budget SSE harness. | Durable B1 failure is not live terminal-wire acceptance; no model/hardware dependency belongs in normal CI |

Do not close issue 62, unblock runtime tickets, claim memory retention, or claim Hermes acceptance on the basis of this documentation merge. Coordinator owns downstream scheduling. Later physical-iPhone acceptance remains separate; this Linux evidence is not device QA.

## Downstream wording and scheduling reconciliation

Epic 61 and issues 62–75 now carry the current no-fork/H0 gate explicitly; downstream implementation tickets are blocked rather than ready to start. Their current bodies supersede historical plans/comments. Issues 63–75 use stable authenticated owner/upstream identity and intended shared main-agent memory, not a per-owner memory-file partition. [Issue 64](https://github.com/markdlabrecque/convoke/issues/64)'s key acceptance and [issue 69](https://github.com/markdlabrecque/convoke/issues/69)'s coordination refer to identity, not file isolation. [Issue 75](https://github.com/markdlabrecque/convoke/issues/75)'s runbook must state that any shared main-agent memory reset needs separate explicit authorization; no separately resettable Convoke namespace exists.

[Issue 62](https://github.com/markdlabrecque/convoke/issues/62) now lists B1 reconciled and the remaining B2a admission recovery, B2b natural/cancelled resource settlement, B3 shared-memory acceptance, B4 approval and B5 terminal-stream evidence separately. [Issue 70](https://github.com/markdlabrecque/convoke/issues/70) consumes an accepted contract, not the stopped experimental APIs. Accepted research in issues 80/82 remains historical evidence; its core-extension recommendations are not current delivery authorization. Issue 87 is the next bounded source-only assessment, not H0 acceptance or permission for dependent implementation.

## Verification of this evidence-only change

**No-fork/ticket reconciliation:** compared current full issue bodies/comments against the merged contract and both accepted research reports; corrected issue bodies/queue labels and read them back through `gh-axi`. Issue 87 is a child of epic 61 and the only open ready-for-agent Hermes ticket; it is assessment-only. Checked the documentation diff for whitespace and policy consistency. No code, test, fixture or test configuration changed; no runtime tests or historical process experiments were rerun for this documentation-only update. No Hermes runtime/source/configuration, credentials or memory were accessed. Earlier command counts below are historical evidence, not fresh acceptance.

**Prior merged evidence PR:** no automated tests/fixtures/config were changed; the following are historical results from that PR, not follow-up rerun claims:

- `swift test --package-path server` with Swift 6.4.2 on Linux: **53 executed, 1 skipped, 0 failures** (optional real Kokoro smoke skipped).
- `bash ios/Convoke/scripts/test-portable-core.sh`: **71 passed**, limited portable core with test-only Combine stand-in, not real Apple adapters/audio.
- Node v24.20.0 `node --test .sandcastle/models.test.mts`: **7 passed**.
- Existing CI's protocol JSON syntax command: **0 JSON files**. This is an honest existing coverage gap, not schema validation evidence; issue 71 owns executable schemas/examples.
- Evidence/source cross-review checked native SSE versus run-event envelopes, legacy versus authority approval bodies, terminal flags, memory file scoping, and disconnect versus stop semantics. No live success is inferred from source or capability flags.
- `git diff --check` must pass before merge. Hosted PR checks must pass; Apple-only suites were not run locally. No new live-model or hardware CI dependency was introduced.

**Earlier 2026-11-17 source-research follow-up verification (historical):** read research, writing-tests and PR skills; performed the research directly under the explicit no-delegates constraint. Verification tier is source/document consistency plus the existing offline commit-tier suites, not a new live Hermes E2E exercise. Rechecked cited installed source symbols against the clean commit, native versus Runs ownership/identity, signal versus settlement, inline versus background children, and provider versus built-in memory scoping. Official API and lifecycle documentation inspected at the installed revision: [API server](https://github.com/NousResearch/hermes-agent/blob/3b421578588243f920886e6fe79a6faa87ea026e/website/docs/user-guide/features/api-server.md) and [Subagent lifecycle API](https://github.com/NousResearch/hermes-agent/blob/3b421578588243f920886e6fe79a6faa87ea026e/website/docs/developer-guide/subagent-lifecycle-api.md).

- Reran `swift test --package-path server`: **53 executed, 1 skipped, 0 failures** (optional Kokoro smoke skipped).
- Reran `bash ios/Convoke/scripts/test-portable-core.sh`: **71 passed**, portable scope only.
- Reran `~/.config/nvm/versions/node/v24.20.0/bin/node --test .sandcastle/models.test.mts`: **7 passed**.
- `git diff --check` passed. Only this document is changed; no automated tests/fixtures/config were edited. No new live inference/tool/approval/stop request, uncertain POST retry, Hermes mutation, memory-content inspection or root-checkout edit was performed. B1's DB/HTTP observations are explicitly attributed to the coordinator, not rerun here.

**2026-11-17 owner-decision continuation verification:** read the writing-tests and PR skills, the merged contract at `f35d6ec`, and full current issue 62/61/78 comments via `gh-axi`; read issues 63–75 for downstream wording conflicts. Used focused document/diff consistency as the cheapest sufficient verification tier, plus required existing offline commit-tier checks:

- `swift test --package-path server`: **53 executed, 1 skipped, 0 failures** (optional Kokoro smoke skipped).
- `bash ios/Convoke/scripts/test-portable-core.sh`: **71 passed**, portable scope only, not Apple/device acceptance.
- `~/.config/nvm/versions/node/v24.20.0/bin/node --test .sandcastle/models.test.mts`: **7 passed**.
- `git diff --check` passed; only `docs/hermes-api-contract.md` changed. Checked that active policy, historical research, wire identity and B1–B5 agree with the owner decision and issue 78's development-only controls. No tests/fixtures/config edits, runtime changes, root-checkout edits, Hermes live probes, memory operations or installed-source investigation were performed in this continuation. Prior live/source evidence remains attributed and historical; no new runtime acceptance is claimed.
