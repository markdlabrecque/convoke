# Hermes tool-stop confirmation: bounded evidence spike

For [issue 80](https://github.com/markdlabrecque/convoke/issues/80), under [epic 61](https://github.com/markdlabrecque/convoke/issues/61). Documentation and synthetic evidence only. **Research accepted via PR 81; H0 and runtime dependants remain gated.**

## Current disposition — evidence retained, core delivery plan superseded

The owner subsequently required unmodified official Hermes, no maintained fork, and stopped core implementation in issues 78/84. Core-extension follow-ups below are historical recommendations, not an authorized delivery plan. T/R describe local experimental source, not installed or official public capabilities. Preserve experiments for reference; no resumption, publication, deployment or cleanup is authorized. No private monkeypatch, overlay, custom build or plugin-delivered core replacement is an acceptable workaround.

[Issue 87's follow-up assessment](hermes-plugin-reporting-contract.md) reused this evidence to assess supported public plugin reporting. Observing handler return or cancellation is not proof of complete resource settlement; lost-admission recovery remains separate. Hermes integration is now deferred; see the [current project priority](development.md#current-priority-finish-the-server-and-ios-app) and the [retained Hermes contract](hermes-api-contract.md).

## Verdict

Convoke can truthfully confirm **settlement of an exact, declared, completely accounted execution scope**, not that arbitrary work caused by a tool has stopped everywhere. Queueing serializes admission; it does not establish ownership of tool effects or join their lifetimes.

At accepted T, Hermes has useful source-owned root/worker/future acknowledgements and exact-generation stop signalling. It deliberately marks tool coverage unknown at the authorized-dispatch seam. That flag has no clearing path. A completed response can therefore coexist with an unconfirmed settlement indefinitely, even after all tracked workers exit. R fixes identity and payload-retention semantics, not this missing proof. Neither Convoke's cleanup consumer in [issue 70](https://github.com/markdlabrecque/convoke/issues/70) nor live acceptance in [issue 75](https://github.com/markdlabrecque/convoke/issues/75) supplies it.

**Feasible, recommended:** incrementally extend `OwnedExecution` with source-owned **per-invocation obligations**, explicit producer closure, typed coverage, compositional joins and exact identity fences. Use the same settlement predicate for ordinary completion and cancellation. A reviewed adapter may discharge only its own obligation; it cannot clear uncertainty from another invocation. Begin with a fixed, source-controlled foreground leaf and the closure/composition core, not arbitrary `terminal` commands. This is an implementation recommendation, not permission to change code, toolsets, permissions, memory or UX.

**Not feasible as a general guarantee:** parent return, signal acknowledgement, process-group signalling, stdout EOF, or even direct-process-plus-I/O joins cannot establish cessation of arbitrary descendants, remote accepted work, plugins or already committed effects. Without a source-owned closed resource graph or an independently reviewed containment/remote lifecycle contract, those invocations remain unsupported/unknown. No blanket tool-name exemption is safe.

**Product consequence:** a coverage core and one leaf are useful engineering progress, but do not yet make unrestricted main-agent tool turns generally releasable. The owner must review a coverage rollout and the remaining unsupported cases; do not quietly trade safety for a Ready button. Shared main-agent memory remains the approved target.

## Provenance and evidence vocabulary

- **Source-supported:** inspected immutable Git objects, not a claim about loaded installed code or current R work.
- **Historical Hermes-path evidence:** accepted T's committed canonical journey and its recorded results; not rerun here.
- **Synthetic local evidence:** this PR's Python-only facts and subprocess experiment; no Hermes import or integration.
- **Proposed invariant:** a specification for follow-up work, not an implemented capability.
- **Unknown:** no adequate proof within this bounded spike; never synonymous with stopped.

| Pin | Full immutable revision | Use |
| --- | --- | --- |
| B | `3b421578588243f920886e6fe79a6faa87ea026e` | Installed-source baseline supplied by coordinator; not inspected through the installation |
| T | `083c5e4cf384a66e070672b03ab9027f1b2b6a75` | Accepted canonical ownership journey and its source ancestry |
| R | `1fd35ae9b67a70d5f90719cda57c736fe14ed5b3` | Approved recovery wire/freshness design; **not unpublished R implementation** |

All Hermes reads used committed objects in the independent review clone. To reproduce a citation, set `HERMES_REVIEW_CLONE` to that clone and use `git -C "$HERMES_REVIEW_CLONE" show <full-pin>:<path>`. Line ranges below refer to those exact objects. T/R are local review commits: this report does not invent public upstream URLs for them or publish them. B's public [source tree](https://github.com/NousResearch/hermes-agent/tree/3b421578588243f920886e6fe79a6faa87ea026e) is supplemental; the Git objects are the evidence.

Root and relevant agent/tools/gateway instructions were read from T; Convoke's local area has no additional `AGENTS.md`. Research and writing-tests skills were read. Research was performed directly as requested, without an agent/thread delegation. No Hermes working tree, installed state, config, secrets or memory was read or changed. No fetch/push to the Hermes origin, listener call, actual terminal-tool invocation, model request, approval/stop probe, deployment or restart occurred.

### Pinned primary-source index

These are definitions, not inferred facade paths. Where code is unchanged at B/T, both objects were compared; the local environment, shared base/output and process registry are byte-identical at those pins.

| Ref | Pin, path, exact definitions / lines | Finding supported |
| --- | --- | --- |
| S1 | T `agent/owned_execution.py:12–115`: `mark_unjoinable_tool`, `submit_background`, `OwnedExecution.{submit,_ack,register_stop,stop,returned,track_worker,snapshot}` | Sticky uncertainty; submission/stop lock and execution-side gate; futures retained until done callback; physical-worker Events; root acknowledgement; stop callbacks are signals |
| S2 | T `agent/tool_executor.py:754–834`: `_run_agent_tool_execution_middleware`, nested `_authorized_dispatch`; `:870–901` `_poll_sequential_future`; `:906` onward `_run_sequential_tool_execution_middleware` | Unknown marked before `_dispatch_authorized_once`, not cleared by a successful result; sequential caller can abandon a pending future |
| S3 | T `hermes_cli/middleware.py:102–134,144–224`: `apply_tool_request_middleware`, `run_tool_execution_middleware`, `_run_execution_chain`; T `agent/relay_tools.py:16–71` `execute` | Rewrites, wrappers and short-circuit execution precede/ surround handler dispatch; single-use downstream callback is not a transitive lifetime contract |
| S4 | T `tools/daemon_pool.py:23–40`: `DaemonThreadPoolExecutor.submit`; T `tools/thread_context.py` `propagate_context_to_thread` | Submission copies context and enters `owned.submit`; context propagation is not ownership registration for every arbitrary thread/process |
| S5 | T `gateway/session_owned_execution.py:8–58`: `fenced_signal`, `signal_fence`, `adoption_lock`, `owned_api_execution`; T `gateway/session_ingress.py:414–420` `_admission_scope` | Scope keyed by admission/generation, requires durable `run_owner_scope`; root-return recorded in finally; successor adoption waits for old signal calls |
| S6 | T `gateway/session_runtime_workers.py:134–166`: `start_turn_worker`, `track_turn_worker`, `physical_workers` | Worker-done Event retained independently of cancelled asyncio waiter; worker registration before scheduling |
| S7 | T `gateway/session_authority.py:934–971,1017–1055`: `SessionAuthority.interrupt`, `adopt_agent`, `publish_execution` | Generation-fenced interruption, pre-adoption stop latch, ordinary turn stop excludes background delegates; late publication rejected after execution returns |
| S8 | T `gateway/platforms/api_server_run_recovery.py:103–120,143–217`: `_settlement_snapshot`, `_signal`, `stop_and_settle` | Receipt plus actual acknowledgements plus settled signals required; never-claimed queue cancellation special case; exact admission/generation; wait budget does not cancel source work |
| S9 | T `tools/async_delegation.py:916–1009,1399–1470`: `_dispatch_admitted`, `interrupt_all`, `interrupt_for_session`, `refuse_for_session`; T `tools/delegate_tool_dispatch.py:139–204,428–513`: `_run_children_parallel`, `_dispatch_unit`, `_dispatch_background` | Async record can finalize before actual exit; real daemon future retained, owned stop callback registered; detach policy and session-selector controls are not per-run physical joins |
| S10 | T `agent/interrupt_control.py:163–273`: `InterruptControlMixin.interrupt`; T `tools/delegate_tool_child_run.py:129–165,906–1047,1071–1174`: `_attach_child`, `_signal_child_stop`, `_ChildRun.{await_child,account_background_processes,cleanup}` | Active children signalled, late attach inherits stop; timeout can abandon worker, deferred close/cleanup; process handoffs reported separately |
| S11 | B/T `tools/environments/local.py:972–1030,1149–1209`: `_kill_process_group_posix`, `LocalEnvironment.{_run_bash,_wait_for_process}` | Popen with separate session; best-effort group and snapshot descendant cleanup with identity checks; owner-death group released on foreground return, intentionally not a descendant-cessation receipt |
| S12 | B/T `tools/environments/base.py:508–613,727–804`: `BaseEnvironment.{_wait_for_process,execute}`; B/T `tools/environments/base_output.py:210–266,269–488`: `_pipe_stdin`, `_popen_bash`, `ProcessHandle`, `_ThreadedProcessHandle`, `_drain_stdout`, `_drain_fd_waiter`, `_start_drain_thread` | Separate stdin/drain workers; bounded joins without a required joined-thread acknowledgement; drain may end after direct process exit without EOF; SDK cancellation is not remote completion proof |
| S13 | B/T `tools/process_registry.py:1139–1153,1245–1270,1393–1416,2456–2471,2685–2723`: `ProcessRegistry.{_track_started,adopt_local,_finish_reader,transfer_ownership}`, `_handoff_process`; T `tools/terminal_tool_background.py:252` onward `yield_to_background_handler` | Registry reader registration/adoption; local handle and reader transfer; owner/task/session routing transfer is not exact execution-obligation transfer |
| S14 | T `tools/process_registry_ownership.py:23–79`: `ProcessOwnershipMixin.{_owns_job,_spawn_job,_take_handoff_group,_return_handoff_group,_release_job_group}`; T `tools/process_registry_termination.py:33–131` `_terminate_host_pid`; T `hermes_cli/process_identity.py:830–839,1012–1088` ownership/release functions | Some background jobs intentionally outlive host; supervisor membership can be released; signalling/snapshot cleanup is not an arbitrary descendant join |
| S15 | T `agent/agent_init.py:1180–1202`: `init_agent`; T `tools/memory_tool_store.py:188–198,300–303,704–714`: `MemoryStore.__init__`, `_path_for`, `_write_file`; T `agent/memory_provider.py:21–33`: `ctx_bound`, `spawn_context_thread`; T `agent/inline_tool_executors.py:144` `_memory` | Built-in memory has profile files, not owner-key partitioning; atomic writes are committed effects; context-bound background thread helper is not a join registry |
| S16 | T `website/docs/developer-guide/api-run-recovery-t-review.md`, “Actual path and outcomes” / “Verification and negative controls”; T `tests/gateway/fixtures/api_owned_execution_peer.py` and `tests/gateway/test_api_owned_execution_journey.py` | Historical canonical wiring and negative controls only; see below |
| S17 | R `website/docs/developer-guide/api-run-recovery-r-contract-amendment.md:17–34,109–139,142–170,178–220` | Missing-runtime control remains unconfirmed; capability explicitly excludes all-tool/restart cessation; payload publication/expiry fencing is separate from execution closure |
| S18 | T `agent/deadline.py:329–387`: `run_bounded_sync`; called by `BaseEnvironment.execute` at S12 | Copies context into a bare daemon Thread and may abandon it on timeout; does not register its completion Event with `OwnedExecution` |

`MemoryStore._path_for` is the actual target definition at these pins; this is not a citation to an assumed `_target_path`. `ProcessHandle` and drain/stdin definitions live in `base_output.py`, not just the environment facade.

## What the actual Hermes evidence establishes

### Baseline versus accepted T versus R design

B does not contain `agent/owned_execution.py`. T introduces/uses the owned scope and daemon-pool registration; it does not change the local Popen/drain/registry code identified above. B already had canonical authority and cooperative interrupts; do not attribute T's explicit owned-stop acknowledgement API to the installed baseline.

T's `snapshot()` acknowledges only when `root_returned && pending_workers == 0 && !unconfirmed`. `stop_requested` is not necessary for acknowledgement: ordinary completion is conceptually supported **until a dispatched tool sets uncertainty**. `returned()` is not a producer seal; `submit()` rejects stopped execution but not root-returned execution. Thus it tracks real source workers, but is not yet a closed transitive invocation graph. A background stopper registration is not itself counted as a joined worker; the async path's daemon future is the relevant physical completion fact. [S1–S6]

The marker is set inside `_authorized_dispatch` **before** downstream guardrails/actual execution. It is conservative even if that downstream path refuses. Conversely plugin/Relay middleware runs outside that callback and may short-circuit it; no conclusion that arbitrary wrapper work is covered follows from the marker or a tool count. A replacement must account for the whole effective invocation envelope, including middleware, hook side work and finalization—not just annotate successful registry handlers. This is a source-review boundary, not a newly exercised exploit or an assertion that a particular installed plugin does this. [S2–S3]

Canonical receipt settlement and source lifetime settlement are different. T's endpoint additionally requires receipt terminal and successful signal completion. Never-claimed queue cancellation can settle without an executor ack because no generation ran. A queued→claim race must recover the exact new generation, not guess or cancel a successor. Read-only status, observer EOF, final tool text and HTTP `stopping` are not physical completion. [S5–S8]

R's frozen capability includes `control.coverage="source_owned_workers"`, `all_tool_cessation=false`, `restart_cessation=false`. R's missing-runtime response has null acknowledgements, false signals-settled and unconfirmed state, even with retained terminal identity evidence. Its publication gate stops expired output being reintroduced; it cannot stop executing code or recall effects. Identity-only indefinite-unknown retention is already approved; this spike does not re-open that decision. [S17]

### Reused historical T journey — not a new run

The accepted T review records the real canonical ingress→authority→tool middleware→daemon/async path with synthetic inference/handler edges. The source-created ownership context reaches both tool handler and async child. Root response completes while a child remains held; settlement remains unconfirmed. Owned stop invokes the real registered callback, but the held runner does not exit. After release and actual future/worker/signal completion, zero pending workers still yields `coverage_unknown=true`, `acknowledged=false`. [S16]

T records **1 focused pass** and **143 passes / 1 existing macOS-only skip** in its offline area set, plus two expected failing mutations (missing ingress binding; missing future tracking). Those are historical recorded results at T, not a current full-suite, installed-runtime, process-tree or live acceptance claim. Its fake `printf synthetic` argument was inspected by a fake handler, not executed. This spike neither repeats that journey nor calls a Hermes terminal tool.

## Coverage and lifecycle matrix

“Current” below means pinned T source, not a deployed capability. “Required” is proposed, not supplied by R. An exact execution identity includes served owner/profile scope, runtime epoch, admission, generation and invocation/resource ID. A transcript/session/task key alone is not that identity.

| Resource/category | Current registration, fence and stop | Actual completion / coverage boundary | Minimal required composition or remaining unknown |
| --- | --- | --- | --- |
| Never-claimed queued admission | Durable authority identity; cancel exact queue entry; recheck claim race | Terminal cancelled + no assigned generation proves no executor claim, not all activity in a session | Preserve queue proof; claim racing stop requires exact-generation recovery [S8] |
| Root / sequential or concurrent foreground tool worker | Owned scope; daemon future registered under submit/stop lock; execution-side stop gate; worker Event registered before scheduling | Root receipt/return and real future/Event can be distinguished from abandoned waiter; every authorized tool dispatch sticks unknown | Invocation token before any effective dispatch; retain root/child obligations past caller abandonment; normal producer seal [S1–S6] |
| Middleware, Relay, inline tools, hooks | Single-use downstream dispatch; inline executor table includes memory; wrappers may bypass handler | Handler return cannot certify arbitrary surrounding callback work or asynchronous hooks | Same outer invocation scope; attest effective implementation/backend/wrappers, register side work; unadapted wrapper stays unknown [S2–S3,S15] |
| Inline delegated agents | `_active_children` interrupt fan-out; late child attach checks parent's latched interrupt; daemon pools track real futures | Abandoned child result/registry cleanup is not thread exit; deferred close may run later | Child token registered before attach/submit; transitive tool/cleanup closure; close callback reserved before future ack [S4,S10] |
| Background delegation | Dispatch inserts record; `submit_background` registers cooperative stop; daemon submit owns future; ordinary turn interrupt deliberately leaves detached units | Forced `_finalize`/result delivery can precede physical exit; future stronger than record; nested tools retain uncertainty | Keep child in original execution graph after detach; explicit owned stop fans out. Define wake/result callbacks as obligations or fence them from launching work after closure [S1,S9–S10] |
| Local foreground direct Popen | New process session; host-death group ownership; bounded wait/kill, identity-checked group and descendant snapshot | Direct process exit is observable. Wait result is not a typed I/O join receipt. Group/snapshot signalling misses the general arbitrary-work proof | Leaf adapter needs exact Popen wait, stdin/drain/finalizer joins and closed producer evidence; report limited direct-process coverage, not arbitrary-shell cessation [S11–S12] |
| Nested environment deadline worker | `BaseEnvironment.execute` calls `run_bounded_sync`, which copies context into a bare daemon Thread | Timeout returns while its private done Event can remain unset; this is not a daemon-pool future or tracked runtime worker | Register the actual nested worker before start and retain it through finally; copied context alone cannot discharge it [S12,S18] |
| Stdout/stderr drain and stdin writer | Separate daemon threads; natural-exit code attempts bounded joins; interrupt/timeout has different join paths | Drain can stop on idle-after-parent-exit without EOF; timed `join()` return does not prove thread exit; EOF only proves writers of that pipe closed | Track exact thread completion, not “join called”; distinguish EOF, intentional capture closure, transfer and unknown. A successful I/O join discharges only I/O [S12] |
| Foreground→background promotion | Yield stops foreground drain and `adopt_local` starts registry reader; group ownership can move or be released | Original wait returns while process continues; source uses bounded drain join and assumes caller stopped it | One obligation, atomic accepted handoff before old owner releases; exclusive reader ownership; failed handoff preserves old owner. No zero-owner gap or treating yielded result as process exit [S12–S14] |
| Child→parent process handoff / persistent jobs | `transfer_ownership` updates owner/task/session routing under registry lock; `_owns_job` excludes some intentionally persistent jobs | Routing ownership not admission/generation accounting; registry completion and teardown do not certify all escapees | Retain original execution's liability while routing changes within it. Cross-execution transfer needs destination acceptance + explicit policy; transfer receipt ≠ cessation [S13–S14] |
| Remote environment / SDK / plugin work | `ProcessHandle` abstraction; SDK adapter thread + optional cancel callback; registry can poll sandbox logs | Local wrapper or transport termination proves neither remote job exit nor an already accepted action's cessation | Backend-specific durable job identity, no-further-dispatch fence and authoritative terminal join required. Otherwise unknown; no automatic retry or broad remote kill [S3,S12–S14] |
| Late completion / notification / callback | Authority publication generation fence; pool future ack and separate callback lifetimes | Suppressing late output does not prevent side effects; future done can precede callbacks that perform cleanup or dispatch | Pre-register continuations, close producer rights, retain join through cleanup; wrong epoch/generation ack cannot close or signal successor [S1,S7,S10,S17] |
| Host death / restart / lost in-memory join | Some host-death supervision and persisted process identities; R retains exact admission metadata | A missing map, dead root or restart cannot reconstruct lost joins; foreground group membership may already be released | Unconfirmed unless future separately approved durable closure protocol proves exact scope. Never reconstruct success from terminal receipt or PID absence [S11,S14,S17] |
| Shared main-agent memory and other committed effects | Built-in files chosen by profile, atomically written; owner identity does not partition them; contextual thread creation alone not a join | Stop cannot undo memory/file/network commits; concurrent main agent is intentionally outside Convoke's execution ownership | Join this execution's in-flight writers where source-owned; do not stop unrelated main-agent work, reset shared state or promise memory unchanged [S15] |

### Smallest source-supported local fact

A successful wait on an exact still-owned direct `Popen` handle establishes **that direct process has exited and been reaped**. An actually completed drain/stdin thread separately establishes that thread's lifetime ended. It does not establish EOF unless EOF was observed, and EOF does not establish all writers' processes exited. Hermes's current wait result does not combine these into a coverage certificate. Source explicitly preserves intended background survivors on foreground return and registry group release. Even an improved direct-process/I/O adapter must leave any unaccounted arbitrary descendants/remote work unknown. [S11–S14]

## New reproducible synthetic evidence

File: [`evidence/hermes_tool_stop_fixture.py`](evidence/hermes_tool_stop_fixture.py). Cheapest sufficient tiers: seven pure fact-composition units and two cases at **one fixed Python subprocess boundary**. They do not test production locking, adapter wiring, registry transfers or stop/dispatch races; those require follow-up tests against real ownership code.

Command actually run in this Convoke worktree:

```sh
python3 -I -B docs/evidence/hermes_tool_stop_fixture.py
git diff --check
```

Observed on Linux, Python **3.14.8**: **9 tests passed, 0 failed, 0 skipped**, exit 0. Whitespace exit 0. A separate in-memory mutation removed `and self.coverage` from `Facts.settled`; running only `test_parent_and_io_join_cannot_discharge_unknown` then produced **1 expected assertion failure**, with no subprocess launched and no file changed. This checks the synthetic unknown-preservation assertion, not Hermes code. The unmodified full fixture was rerun green afterward. A local report check also confirmed relative file links resolve and code fences are balanced; no repository Markdown-lint command is configured. Test names and outcomes are printed by `unittest`; no process IDs, user paths, payloads or transcripts are versioned. No Swift/server/device suite or Hermes check was run: only docs and this independent fixture changed. Existing app CI remains separate evidence, not a prerequisite for treating this fixture as an OS experiment.

Reproduce the in-memory negative control (the wrapper exits 0 only for exactly one intended failure):

```sh
python3 -I -B - <<'PY'
from pathlib import Path
import unittest
scope = {'__name__': 'spike_mutant'}
source = Path('docs/evidence/hermes_tool_stop_fixture.py').read_text()
source = source.replace('self.sealed and self.joined and self.coverage',
                        'self.sealed and self.joined')
exec(compile(source, '<synthetic-unknown-bypass>', 'exec'), scope)
suite = unittest.TestSuite([scope['CompositionEvidence'](
    'test_parent_and_io_join_cannot_discharge_unknown')])
result = unittest.TextTestRunner(verbosity=2).run(suite)
assert len(result.failures) == 1 and not result.errors
PY
```

| Evidence | Actual observation | Non-claim |
| --- | --- | --- |
| Pure proposed-facts units | Closed covered children settle normally without a stop; held child/open producer/unknown blocks closure; stale binding cannot replace facts; closed facts cannot reopen | Illustrates predicate and identity rules only; not an implemented registration/transfer state machine or proof of concurrency safety |
| Normal leaf subprocess | Fixed Python child signals readiness, waits for one pipe byte, exits after release; exact `Popen.wait()` succeeds; output reader reaches EOF and is joined | Only this fixture-created process and reader; not arbitrary `terminal`, Hermes lifecycle or descendants |
| Signal negative counterexample | SIGTERM handler writes a notification; after receipt, direct child is still held/running and reader unfinished; explicit pipe release is required before exit | Signal delivery/handler completion ≠ process completion; not a measurement of Hermes interrupt latency |
| Local-join negative counterexample | Even after direct process + output-reader joins, a separate fixture-owned Event-gated thread is still held; release and join that handle separately | Thread is deliberately **independent**, not an OS descendant. Demonstrates incomplete accounting, not an observed Hermes escape or descendant kill experiment |

The child uses absolute Python executable, `-I -S -B`, fixed code, disposable HOME/cwd, minimal environment, no shell/init/network/provider and no descendants. Synchronization uses Events, pipe bytes and Queue messages; finite timeouts are failure/teardown watchdogs only, not timing or retry-to-success assertions. Finally releases the independent thread, waits/reaps the exact child (kills only that unreaped handle on failure), joins readers/threads and closes pipes. No name lookup, group kill, shared environment reset or installed process is touched. The fixture intentionally avoids an orphaned-descendant experiment so cleanup retains exact local handles.

A counterexample is enough to refute “all work stopped” from partial joins; it is not evidence that the proposed Hermes contract already works. Arbitrary descendant limitations here are **Hermes source-supported**, not newly measured OS ancestry evidence.

## Minimal proposed ownership / settlement contract

### Facts, not a tool-name allowlist

Extend the existing ownership lifetime instead of building a second scheduler. Conceptual internal record (not a frozen HTTP schema):

```text
identity = owner/profile + runtime_epoch + admission + generation + invocation_id
resource = exact opaque handle + resource_id + parent invocation
coverage = declared_closed_scope | unsupported(reason) | lost(reason)
producer = open | sealed
join = pending | joined | unknown(reason)
stop = not_requested | requested | signal_returned | signal_failed
```

Coverage names the reviewed execution boundary and attested adapter implementation/backend/wrapper revision, not “terminal is safe”. `joined` describes lifetime only, not success, rollback or permission. Signal status is separate. Missing evidence, exceptions that lose a handle, unregistered escape or unsupported adapters propagate unknown; an empty set of *known* handles is not proof that no handles were missed.

A completed supported invocation may transition pending→joined after actual acknowledgements. An unknown invocation is not redeemed by joining a different leaf. Lost/unsupported coverage is absorbing for that invocation absent a separately specified authoritative reconciliation proof. Preserve old unresolved sticky runs as unknown; never retroactively convert their lack of per-invocation facts into covered emptiness.

### Registration, closure and races

1. **Before dispatch:** create an invocation obligation under the exact execution's registration/stop gate, before middleware or any callable can create effects. A plugin/request wrapper that runs before handler dispatch belongs to this envelope too. Registration failure prevents dispatch; if actual dispatch may already have occurred, record uncertainty, not “not started”.
2. **Stop linearization:** reuse the existing stopped gate and queued-worker execution check. Stop revokes new external dispatch for that scope; accepted-but-not-running invocations either prove never-started cancellation or remain pending. A start that wins the race must already be registered and receive stop. Cleanup/ack work remains permitted, but cannot spawn new effectful work without an existing tracked reservation. Never hold this lock while signalling third-party code.
3. **Producer rights:** root return seals the root's dispatch right on ordinary completion too. Already registered children may still own their own producer rights until they finish; root return alone does not revoke or erase them. A subtree closes only when all producer rights/continuation reservations are sealed and every resource joins. Return a tool result independently from this closure fact.
4. **Callbacks:** register cleanup/result-delivery/wake continuations before their parent ack can close. Future completion is not automatically completion of its later callbacks. A late callback with a stale epoch/generation/token cannot signal, register into or publish as a successor. If an unexpected callback can still cause effects, closure was premature; fail closed rather than reopen a certified closed scope.
5. **Transfers:** foreground→registry promotion is an atomic obligation move/alias within the same graph, acknowledged by the recipient before old release. Retain source liability on failure. Child→parent routing within one execution keeps the resource in that execution's transitive closure. Cross-execution/session transfer must not make the originating run look ceased: require explicit policy and a separately labelled transferred-active fact, not a stopped fact. First slice should keep these unsupported rather than invent that policy.
6. **Completion and cancellation:** use the same monotone settlement predicate below. Normal closure needs no synthetic “housekeeping stop”. Cancellation additionally fences dispatch and requests the existing source stops, but signal acknowledgements never substitute for joins. An uncancellable pending worker stays pending/unknown when the bounded caller wait ends.
7. **Restart:** preserve durable identity, but report lost runtime joins as unconfirmed. Do not infer worker exit from a missing registry/map, expire an unknown into safety, reconstruct a join from a receipt or resubmit the action. R's identity-only/payload policy remains separate.

Proposed scoped predicate:

```text
scope_settled = exact identity still authoritative
             AND root producer sealed and root physically returned
             AND every invocation has complete declared coverage
             AND every producer/continuation sealed
             AND every registered resource and transitive child actually joined
             AND no pending transfer or stop-signal task
             AND canonical receipt terminal
```

Per-invocation closure must be monotone and generation-local. Aggregation is conjunction, **not** “any good leaf clears coverage_unknown”. Where the product demands all caused work, `declared_closed_scope` must actually encompass that work; a direct-Popen-only certificate cannot satisfy it for arbitrary shell. A certificate limited to direct process/I/O may be useful diagnostics but cannot release that stronger lease.

### Why ordinary completion is a first-class acceptance case

At T a normal tool response plus all tracked futures still cannot acknowledge after the sticky marker. Simply adding better stop joins only makes cancellation more informative; it leaves every normal tool turn quarantined. Instead supported invocations must seal and acknowledge on their natural finally/completion path, aggregate up to root closure and permit the **next** covered turn without stop calls. Unsupported/unknown invocations still retain the lease. This does not weaken safety: it replaces a permanent undifferentiated flag only where complete positive evidence exists, not based on elapsed time, name, successful output or intention.

## Convoke consequences — no policy change selected

| Fact | Truthful presentation / lease consequence under existing fail-closed rule |
| --- | --- |
| Successful final response, execution scope not yet settled | Response completion is distinct from work settlement. Speech still requires the existing validated success/finality contract; completion alone does not authorize another owner turn. Review integration of closure into the normal turn lifecycle before rollout. |
| Stop accepted / signal callback returned | “Stop requested”; never “all tool work stopped”. Keep cleanup ownership and active-turn lease. |
| Exact reviewed scope terminal with complete closure evidence | May release that scope's lease under reviewed H0 contract; describe coverage accurately. No rollback or unrelated-session claim. |
| Unknown, unsupported, lost identity/join, timeout, mismatch or restart gap | Fixed stop-unconfirmed failure, retain/quarantine owner work; no automatic retry, no forced-success cleanup, no weaker route fallback. Bounded wait bounds Convoke, not remote cessation. |
| Transfer/persistent/remote work active outside a proved scope | Cannot silently call it stopped or release a lease requiring cessation. Needs an explicit reviewed product contract, not client-side optimism. |

Keep authorization and resource selection exact to this execution; never use “stop everything in profile/session” as a substitute. Sharing main-agent memory is not sharing ownership of its concurrent work. Stop may prevent future writes only while the owned writer is actually fenced/joined; it cannot undo a file rename, memory commit, external request or main-agent write already made. No separately resettable Convoke built-in memory namespace exists. [S7,S13,S15]

## Recommended follow-up specifications and estimates

These are **draft ticket specifications for coordinator review**, not filed/edited queued tickets and not implementation authorization. Estimates are human-equivalent, include focused verification/review, and do not authorize paid/live probes. Sequence by evidence, not by waiting for R retention work; coordinate shared files only when implementation is separately assigned.

### A. First implementation: invocation closure core + one fixed leaf — 12–16h

**Goal:** make natural completion and stop usable for a demonstrably closed, fixed foreground operation without loosening unknown defaults.

**Proposed locations:** extend `agent/owned_execution.py`; bind scope around the effective invocation envelope in `agent/tool_executor.py`/middleware integration; retain `gateway/session_owned_execution.py` and worker wiring; project bounded facts in `api_server_run_recovery.py`. Use one explicitly source-controlled fixed leaf adapter/fixture, not a terminal-name special case or installed toolset change. Keep legacy/unadapted paths sticky unknown. Account for callback/finalizer lifetime before ack.

**Acceptance:** pure production-state tests for normal closure, unknown conjunction, stop-before-register, accepted-before-stop/start-after-stop refusal, register/start-before-stop joining, callback-after-root-return, duplicate ack, stale owner/epoch/generation, lost-handle/exception, transfer refusal and concurrent unrelated execution. Events at the real linearization gates, not sleeps. Extend existing T harness only at its synthetic leaf edge to show two naturally completed covered turns can settle/release without an artificial stop, while held child and unknown sibling remain unconfirmed. Mutation omitting registration or coverage must fail. Reuse historical T binding evidence until this seam actually changes; no second full agent/HTTP journey solely for pure composition.

**Non-goals:** no arbitrary local shell, registry handoffs, persistent jobs, remote jobs, restart certainty, retention redesign, installed listener or new capability enablement. Output must say narrow coverage, not all-tools cessation. This slice alone does **not** unblock unrestricted H0.

### B. Local process/I/O obligation adapter and atomic transfers — 12–20h

**Goal:** attach exact direct-process, stdin, drain/reader and finalizer facts to source-controlled local invocations; cover foreground→background and same-execution child→parent ownership without gaps.

**Proposed locations:** `tools/environments/{local,base,base_output}.py`, `agent/deadline.py::run_bounded_sync`, `tools/terminal_tool_background.py`, `tools/process_registry{,_ownership}.py`; integrate with A's token, not a parallel lifetime system. The nested deadline worker needs its own registration/ack; merely propagating context into it does not track its lifetime. Do not turn existing best-effort group kills into asserted joins.

**Acceptance:** one fixed Python subprocess integration boundary proving direct exit separately from I/O closure; pure/gated handoff success/failure/stop races, old-reader-still-held case, reader-start failure, stale ack and unrelated-session survival. Held/escaped or unaccounted resource remains unknown even when parent and I/O join. No terminal-shell/descendant promise. General containment, if desired, is a separately estimated design requiring owner decision; not hidden inside this adapter.

### C. Delegation/continuation composition — 8–12h

**Goal:** inline and background children, deferred close, finalization and completion-triggered work retain original obligations past parent result. Preserve ordinary turn-interrupt versus explicit owned-stop policy.

**Proposed locations:** `tools/{daemon_pool,async_delegation,delegate_tool_dispatch,delegate_tool_child_run}.py`, relevant notification scheduling seam. Define whether a completion wake is part of the originating scope or separately admitted authorized work; no zero-owner dispatch window.

**Acceptance:** deterministic production-code units for late attach, record-finalized-but-future-held, callback-held-after-future, nested child unknown, stop/dispatch fence and same-execution transfer. One existing T journey extension if needed for changed wiring, not multiple duplicate E2Es. A forced registry-finalized row never settles a live future. Cross-session/execution detach stays unsupported absent an approved policy.

### D. Coverage inventory and scoped H0 consumer contract — 6–10h initially

**Goal:** map the actual intended enabled implementation/backend/wrapper paths to A–C's certificates or explicit unsupported reasons, then freeze bounded outward closure facts and normal/cancel semantics for Convoke. Source inventory only initially; no credentials, live discovery or configuration changes.

**Acceptance:** reviewed coverage manifest, conservative unknown defaults, mixed covered/unknown case, normal-completion lease release after full evidence, unknown/restart lease retention, exact identity/no retry and fixed redacted errors. **Owner decision checkpoint** if desired unrestricted tools include unjoinable work: further coverage implementation versus an explicitly approved capability/UX contract; this spike chooses neither. Do not publish `all_tool_cessation=true` for an incomplete inventory.

**Consumers:** [issue 70](https://github.com/markdlabrecque/convoke/issues/70) owns client lease/cancellation/shutdown consumption; [issue 75](https://github.com/markdlabrecque/convoke/issues/75) later owns authorized real acceptance. Their existing estimates are not replaced here. Real harmless-tool/device acceptance remains Pending and needs separate authorization. R identity storage and payload expiry proceed independently; no coverage patch is bundled into R.

Remote/plugin authoritative joins and post-restart proof are **not estimated implementation promises**. Discovery may establish no usable provider-side cancellation/closure mechanism. Stop and re-estimate before expanding into containment, arbitrary descendant supervision, new permissions, remote infrastructure or durable resource recovery.

## Needed owner/coordinator decisions and remaining unknowns

1. **Approve technical direction and first bounded slice:** per-invocation obligations with conservative legacy/unsupported default, natural completion closure and explicit coverage. Do not interpret this report as authorization to implement A–D.
2. **Review intended coverage before H0:** whether to fund additional adapters for the actual desired main-agent capabilities. Do not implicitly restrict toolsets, change permissions/isolation, weaken uncertain-stop UX or treat a fixed leaf as general acceptance. If broad unrestricted cessation remains required, the gaps remain blockers rather than being papered over.
3. **Transfer and background work:** decide how intentionally ongoing/cross-execution work and completion-triggered turns fit the product. A transferred-active receipt cannot be relabelled stopped. Default recommendation is retain the originating obligation/uncertainty until an approved contract says otherwise.
4. **Shared memory:** already approved; do not ask for an isolated profile. Separately review how to communicate irreversible effects/concurrent writer limits and plan the authorized acceptance evidence. No seeding/reset/migration or integrity test was performed.
5. **Restart:** current reviewed contract excludes restart cessation. Retain indefinite unknown identities as already approved. Any durable settlement/containment expansion needs a fresh specification/estimate, not R payload retention repurposed as a join journal.

Unknowns include completeness of tool/wrapper resource coverage, integration correctness of any future adapter, platform-specific process semantics (this fixture is POSIX-only), remote authoritative termination support, persistent/cross-run obligations and restart loss. No finite arbitrary cessation bound, all-descendant ownership, general memory integrity or rollback has been established.

## Review / completion boundary

The spike stays within the approved **8h human-equivalent budget** (2 source / 3 bounded evidence / 2 recommendation / 1 review). No material expansion undertaken; follow-up estimates above are recommendations, not additional spike work. Deliverable acceptance is the report, pinned lifecycle evidence, safely cleaned synthetic counterexamples and a docs/evidence-only Convoke PR for review—not a runtime gate pass. Preserve this T3 worktree while the PR is unmerged; cleanup only after coordinator merge when clean and safe, never force-remove. Issue 80 and other issues remain open until coordinator acceptance.
