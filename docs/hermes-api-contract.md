# Installed Hermes contract: evidence and blocked integration

Evidence date: 2026-11-16. Tracks [issue 62](https://github.com/markdlabrecque/convoke/issues/62), under [epic 61](https://github.com/markdlabrecque/convoke/issues/61).

**Disposition: H0 is NOT accepted. Runtime dependants remain gated.** This document can merge as accurate evidence without completing issue 62. No Hermes backend, phone approval, memory isolation, or safe remote-stop implementation is enabled by this change.

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

Local API origin is `http://127.0.0.1:8642`; `/v1` is an API path prefix, **not** the prefix for `/api/sessions`. No public service was created. No production or password-vault access, nor direct Hermes source/config/permissions/global-memory edits were performed; the incomplete inference probe's possible memory effects are explicitly unproven below. A bounded inference request was authorized by the owner after initial read-only inspection. All further inference/tool/approval exercises are now suspended under the unknown-run quarantine below.

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

The 25-second socket timeout was an inactivity timeout, not an absolute wall-clock budget; heartbeat traffic can keep it open. The outer command killed the process at 55 seconds before its cleanup code ran. The probe did not persist the run/session IDs privately. It therefore cannot address `GET /v1/runs/{run_id}` or `POST /v1/runs/{run_id}/stop` for this exact run. This is a harness failure, not proof that Hermes ignored a correctly issued stop. Fixing the parser or timeout does **not** authorize another live run.

**Unknown-run safety quarantine:** remote cessation is UNKNOWN. Connection close, elapsed time, an idle HTTP listener, or a `stopping` acknowledgement cannot clear quarantine. No more inference/tool/approval probes until the owner unambiguously confirms this exact probe is idle/ceased. Do not guess IDs, stop unrelated work, retry the inference, resolve unknown admissions, or change the gateway to obtain a pass.

No documented run-list or run-by-session HTTP endpoint was established that can recover this exact lost run unambiguously. Discovery/session-list endpoints are not proof of its identity or cessation. If an existing private record later supplies its exact run ID, authenticated **read-only** `GET /v1/runs/{that-id}` is the documented reconciliation interface; only an established terminal state can support cessation evidence. Otherwise the owner must confirm cessation through their existing local operational view. Do not restart/stop the gateway or alter policy on the owner's behalf.

The probe computed built-in-memory hashes before inference, but the process did not reach its after-run comparison and did not retain those hashes. **After-run memory checks are unproven**; there is no claim that the run left global memory unchanged. No write was requested, and no memory content/hash is published here.

## Required capabilities and exact upstream interfaces

Live `/v1/capabilities` reports bearer authentication and these flags as true: `session_resources`, `session_chat`, `session_chat_streaming`, `run_status`, `run_events_sse`, `run_stop`, `run_approval_response`, `approval_events`, `tool_progress_events`, `run_submission`, and `run_unknown_resolution`. Continuity/key headers are `X-Hermes-Session-Id` and `X-Hermes-Session-Key`. `memory_write_api`, `admin_config_rw`, `jobs_admin`, `audio_api`, and `realtime_voice` are false. Durable run idempotency is advertised with 86400-second retention; it does not authorize automatic retries of uncertain actions.

`run_unknown_resolution=true` indicates the authority branch is enabled. It is essential to inspect the authority implementation as well as the legacy adapter: their approval request shapes differ.

All protected upstream requests carry `Authorization: Bearer <server-only-Hermes-key>`. JSON POSTs carry `Content-Type: application/json`; native stream responses are SSE. Never send this key to the phone, put it in a URL, or forward it across an origin redirect. No request override may expand tools, provider access, permissions, or profiles.

| Interface | Source contract / required usage | Live execution evidence |
| --- | --- | --- |
| `POST /api/sessions` | `{}` creates a new ID; 201 `{"object":"hermes.session","session":{"id":"<session>"}}` (projection, additional metadata omitted) | Create 201 verified |
| `POST /api/sessions/{id}/chat/stream` | `{"message":"<user-text>"}`, stable server-derived `X-Hermes-Session-Key`; use freshly created transcript ID in path | Initial stream only; terminal behavior blocked |
| `GET /v1/runs/{run_id}` | Poll exact known run; response includes `status`, `run_id`, `session_id`; authority projection can include `admission_id`, `execution_generation`, `pending_controls`, output/usage | Not exercised; never forward raw output/status object to phone |
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

Source choices can include `once`, `session`, `always`, `deny`, or deny-only restrictions. Convoke accepts only explicitly advertised `once`/`deny`, binds the exact pending request, and never promotes consent to persistent/session-wide permission. Legacy queue resolution pops an exact request under a lock; replay finds no pending approval (409). Gateway wait captures `timeout_s`, fails closed on timeout/notify failure/interruption; coalesced `once` applies to the leader, not all follower actions. None of this is live execution-after-approval/replay evidence. Authority generation fencing, restricted-choice behavior, and successful resolution require the authorized controlled exercise **after quarantine is cleared** and a safe tool setup is agreed.

### Stop/lost-ID control — blocker, not a timeout fallback

Sources: `api_server.py::_drain_session_stream_task_on_disconnect`, `_run_agent`; `api_server_runs.py::_handle_stop_run`; `api_server_authority_runs.py::stop_run`; `gateway/session_api_turn.py::observe_api_turn`, `schedule_orphan`.

- Legacy native disconnect interrupts an agent if one is referenced and then awaits the task with no explicit timeout. No-agent path cancels/awaits the task.
- The enabled authority route delegates `_run_agent` into the durable FIFO. `observe_api_turn` explicitly shields its waiter: cancelling the request removes its observer **but keeps the canonical turn alive**. Admission can also commit while its caller is cancelled; orphan scheduling can still run it.
- Authority stop cancels an exact queued admission or interrupts the exact running generation; running return is `stopping`, not a terminal-cessation guarantee. `unknown_execution` is a refusal, not completed/cancelled.
- No verified bounded stop exists for a native stream closed before the client knows its generated run ID. The current failed probe demonstrates a lost-ID evidence gap, not that a correctly issued stop failed.
- A local deadline/socket close/task cancellation/forced success response cannot prove upstream cessation. Keep the owner's active-turn slot quarantined on uncertainty, do not retry or admit another turn, and report a fixed stop-unconfirmed error. A finite HTTP timeout bounds the client wait only.

A documented caller-known durable run identity could potentially avoid the lost-ID window on another route, but selecting `/v1/runs` instead of session chat requires a separately reviewed source/live contract, including admission, fresh-session memory semantics and stop. It is **not** an accepted fallback in this document. Upstream bounded cessation still needs proof or an approved upstream capability change.

## Profile, memory, retention, destructive tools and concurrency

**Source:** Default requests use the listener's current/default profile. `/p/<profile>/...` uses profile middleware and profile-scoped authentication; unsupported profiles fail closed. Convoke must pin one approved local profile/origin and must not expose arbitrary profile selection. No new/modified profile was created.

`agent/agent_init.py` constructs built-in `MemoryStore` without an owner/session-key parameter. `tools/memory_tool_store.py::_target_path` uses the profile memory directory's `MEMORY.md`/`USER.md`. An external provider can receive gateway identity (`agent/agent_init_memory_provider.py::_memory_provider_init_kwargs`), but that does not retrofit isolation into built-in files. `api_server_memory_sessions.py` caches external managers by transcript lifecycle; this is not proof of restart retention keyed to owner.

**Read-only local config projection:** built-in memory and user profile are enabled; `memory.provider` is not configured. No memory content was printed. Consequently a stable key is an identity interface, **not established owner-isolated persistent memory**. Cross-reconnect/restart retention and reset/isolation acceptance are blocked. Do not silently substitute global profile memory for the requested owner key, disable memory, seed/delete files, or install a provider.

**Accepted application policy:** each authenticated WebSocket reconnect creates a fresh transcript, never reloads history or resumes a prior session. A single configured owner identity and its stable memory key survive server restarts/token rotation. Transcript freshness does not erase Hermes-persisted history. The owner has not approved destructive transcript cleanup, provider migration, or any global-memory reset; do none. Memory reset is not reconnect. Exact upstream retention/deletion and owner-scoped memory persistence remain unverified.

**Live tool exposure:** `/v1/toolsets` reports enabled `web`, `browser`, `terminal`, `file`, `code_execution`, `vision`, `image_gen`, `skills`, `todo`, `memory`, `session_search`, `connections`, `delegation`, `cronjob`. These execute server-side. Approval guards for dangerous actions are not an exhaustive sandbox or a promise that every write/destructive action prompts. A no-tool prompt is not enforced capability isolation. Do not send a destructive command just to elicit approval. A non-destructive, narrowly understood approval-triggering fixture without permission/config expansion was not established before quarantine; controlled approval/stop acceptance remains blocked.

**Concurrency:** one active turn per authenticated owner, across connections/restarts as required by runtime safety handling. Reserve the slot before any upstream session/action request; concurrent submit receives fixed `busy`. Shared `X-Hermes-Session-Key` is not a lock; no safe parallel-memory evidence was obtained. Unknown remote lifetime keeps the slot quarantined until reconciled. A process restart is not evidence of remote cessation and must not silently clear unknown ownership. Recovery after abrupt process death remains out of scope, not falsely guaranteed.

## Required Convoke wire/auth interface (gated design, not shipped)

The following is the concrete proposed handoff for separate server/client tickets, conditional on H0 remediation. It is **not live Hermes output**, an implemented schema, or authorization to start dependants. `ios/Convoke/Core/ResponseAccumulator.swift` rejects unknown types/extra keys. Existing `/conversation` has only `user.text` input and ordered `agent.text`/`agent.audio`/`agent.done` output. Therefore unsolicited new messages break legacy clients.

### Selection and authentication

- Missing backend setting remains `openai`, preserving generic non-streaming requests, voice prompt and history behavior. Hermes is explicit backend opt-in, never inferred from a URL/model name.
- Hermes clients offer WebSocket subprotocol `convoke.hermes.v1` on `/conversation`; the Hermes server authenticates **before upgrade or remote creation** and echoes that exact selection. Missing/unsupported selection is a fixed 426 refusal; invalid/missing bearer credential is 401. No fallback into unauthenticated generic handling in Hermes mode. Generic mode does not emit the new events.
- Phone uses `Authorization: Bearer <separate-Convoke-client-token>` over private WSS to its provisioned origin only. Never reuse the Hermes credential. No query credentials, cross-origin redirects, credential downgrade to WS, or arbitrary endpoint token forwarding. A new client without provisioned Hermes mode can still consume legacy text/audio/done; it cannot downgrade an authenticated Hermes session to obtain approval implicitly.
- Server configuration supplies stable owner ID; authenticate then derive `convoke:<configured-owner-id>` as the upstream key. Constrain owner ID to 1–100 ASCII letters/digits/`-`/`_` to stay within the 256-character upstream header cap. Client cannot select owner, profile, key, session, run or generation. Token rotation keeps owner ID/key. Header scoping is still blocked as a memory-isolation guarantee.
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
| B1: Unknown live probe lifetime | Owner confirms exact probe idle/ceased via existing local operational view, or supplies an existing private exact run record for read-only terminal-status reconciliation. Do not send secrets/transcripts in chat. | No permission expansion required for confirmation; any gateway restart/control action needs separate owner authorization |
| B2: Lost-ID and bounded upstream stop | Establish caller-known exact identity before dispatch and demonstrate real queued/running/approval-wait cessation, including close-before-ID. If unsupported, request an upstream capability change instead of inventing a client fallback. | Changing Hermes source/config/policy is outside this task; selecting another route needs reviewed scope/contract and live gates |
| B3: Owner-key memory isolation/retention | Owner chooses an already-supported isolated memory mechanism with verified cross-session/restart behavior, or explicitly revises the owner-isolation requirement to accept existing profile-global memory. | Either configuration/provider/profile changes or accepting global memory is a scope/security decision, not implied permission |
| B4: Safe approval exercise and wire variants | After B1, agree on an existing non-destructive approval-triggering action requiring no expansion; verify authority generation/body/success/error shapes, one-time execution, deny, expiry, replay and stop. | Original exercise permission exists, but quarantine now forbids more probes; no policy expansion authorized |
| B5: Missing terminal/compression/error evidence | After B1/B2, capture bounded sanitized success, failure/incomplete, effective-ID change and stream-close outcomes with privately retained IDs and a correct absolute-budget SSE harness. | No model/hardware dependency belongs in normal CI; fixing harness alone does not clear B1 |

Do not close issue 62, unblock runtime tickets, claim memory retention, or claim Hermes acceptance on the basis of this documentation merge. Coordinator owns downstream scheduling. Later physical-iPhone acceptance remains separate; this Linux evidence is not device QA.

## Verification of this evidence-only change

No automated tests/fixtures/config were changed; existing commit-tier checks were run after reading the writing-tests skill:

- `swift test --package-path server` with Swift 6.4.2 on Linux: **53 executed, 1 skipped, 0 failures** (optional real Kokoro smoke skipped).
- `bash ios/Convoke/scripts/test-portable-core.sh`: **71 passed**, limited portable core with test-only Combine stand-in, not real Apple adapters/audio.
- Node v24.20.0 `node --test .sandcastle/models.test.mts`: **7 passed**.
- Existing CI's protocol JSON syntax command: **0 JSON files**. This is an honest existing coverage gap, not schema validation evidence; issue 71 owns executable schemas/examples.
- Evidence/source cross-review checked native SSE versus run-event envelopes, legacy versus authority approval bodies, terminal flags, memory file scoping, and disconnect versus stop semantics. No live success is inferred from source or capability flags.
- `git diff --check` must pass before merge. Hosted PR checks must pass; Apple-only suites were not run locally. No new live-model or hardware CI dependency was introduced.
