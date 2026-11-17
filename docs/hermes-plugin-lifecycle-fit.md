# Hermes plugin lifecycle fit: a core-owned boundary, not a wrapper certificate

Assessment for [issue 82](https://github.com/markdlabrecque/convoke/issues/82), under [epic 61](https://github.com/markdlabrecque/convoke/issues/61). **Documentation-only recommendation for coordinator review. No implementation or runtime unblock.** Four-hour human-equivalent bounded assessment: source/API mapping 2h, first-slice specification 1h, checks/review 1h; not a second broad stop spike.

## Recommendation

**Use a small new public core-owned invocation capability with plugin-owned resource adapters. Do not implement settlement as execution middleware or an observer.** Existing supported plugin seams can supply behavior and routing, but none supplies the registration-before-effects, producer seal and transitive physical acknowledgement contract Convoke needs. The terminal-environment seam is real but is not a lifecycle interception seam for built-in `local`, and its actual factory refuses hosted environments. The public subagent lifecycle service is useful but is not an all-caused-work closure certificate.

Recommend **one first implementation task, 16–24 human hours**, delivering the generic in-process core/plugin contract and one fixed foreground leaf conformance adapter together. Keep host-mode ownership registration explicitly unsupported in this first slice. Do not switch isolation modes, change tools or install anything to make it work. This is a smaller, concrete consumer for the missing generic seam, not a second scheduler or a distributed resource supervisor. A future host-compatible implementation would require a separately reviewed bridge, not merely serializing the same Python capability.

The first adapter proves engineering composition for one closed operation; it does **not** make ordinary arbitrary terminal commands, descendants, delegates, remote effects or unrestricted main-agent turns covered. H0 remains blocked pending actual coverage and acceptance. Keep [recovery issue 78](https://github.com/markdlabrecque/convoke/issues/78) independent; this task does not depend on its mutable work or authorize a coverage patch there.

## Evidence boundary and pins

Reuse [the merged tool-stop spike](hermes-tool-stop-spike.md), especially its resource matrix and normal-completion predicate. No repeat OS experiments, fixture runs, model requests, Hermes imports, live HTTP/approval/stop calls or plugin installation. That report's test totals are **historical evidence only**, not this assessment's checks.

All Hermes source reads were immutable `git show` operations at `/home/mark/Projects/hermes-convoke-control/code`. No Hermes working-tree reads/edits, fetch/push to its origin, installed state/config/secrets, production or 1Password access. Convoke has no applicable repository `AGENTS.md`; global instructions and research/writing-tests skills were read. Research was performed directly, overriding the research skill's delegation default as explicitly requested. No automated tests or fixtures were inspected or changed.

| Pin | Full revision | Role |
| --- | --- | --- |
| T | `083c5e4cf384a66e070672b03ab9027f1b2b6a75` | Actual plugin/API/runtime definitions inspected |
| R | `1fd35ae9b67a70d5f90719cda57c736fe14ed5b3` | Frozen recovery contract only, not ongoing implementation |
| B | `3b421578588243f920886e6fe79a6faa87ea026e` | Baseline supplied; no additional baseline investigation needed |

Citations below identify exact definitions at these pins. Reproduce with `git -C /home/mark/Projects/hermes-convoke-control/code show <full-pin>:<path>`; line numbers are from that immutable object. T/R are local review objects; no invented upstream links or publication of Hermes changes.

### Pinned primary-source definitions

| Ref | Pin, path, definitions and lines | Authority |
| --- | --- | --- |
| P1 | T `hermes_cli/data/plugin_api.json:1–145`; generated `website/docs/developer-guide/plugins/public-api.md:10–18,27–38,74–81` | Allowed plugin imports; `agent.subagent_lifecycle`, `agent.terminal_env_provider`, public `PluginContext`, `BaseEnvironment`. **No `agent.owned_execution` entry.** Validator warns rather than proving support for private imports. |
| P2 | T `hermes_cli/plugins_context.py:269–307,483–492,741–750,857–875`; `hermes_cli/plugins_registrars.py:61–68,87–92,108–143` | Actual tool/middleware/environment/delegation registration and direct registry dispatch; no invocation ownership parameter. |
| P3 | T `hermes_cli/middleware.py:102–150,162–216`, `_run_execution_chain`; `website/docs/developer-guide/middleware.md:40–55,79–89,259–280` | Single-use downstream callback; before-next failure continues chain; after-next failure preserves result; downstream error propagates. |
| P4 | T `agent/tool_executor.py:662–675,679–834,862–866`, `_pre_tool_block`, `_dispatch_authorized_once`, `_run_agent_tool_execution_middleware`, `_abandoned_sequential_result`; `agent/inline_tool_executors.py:21–30,33–87` | Real order and IDs; unknown marker inside authorized callback, outside Relay/wrappers; terminal observer may be emitted for an abandoned worker. |
| P5 | T `agent/terminal_env_provider.py:20–60,115–122`, `TerminalEnvironmentProvider`; `agent/terminal_env_registry.py:24–44,53–68`; `tools/terminal_tool_backends.py:236–295`, `_build_plugin_env`, `_create_environment` | In-process environment factory, reserved built-in names, classification defaults; explicit host refusal **before** `create_environment`. |
| P6 | T `website/docs/developer-guide/terminal-environment-plugin.md:15–36,106–135,137–163,210–252` | Environment executes commands/file tools, cleanup is session teardown/idle release or detach, streams are argv placement, not joins. Hosted environments cannot run. |
| P7 | T `hermes_cli/plugin_isolation.py:36–84,100–135`, host tables and launcher; `hermes_cli/plugin_host.py:72–95,112–166,179–227,343–385,422–436,478–568,571–608` | Profile-scoped host, host generation, restart/shutdown, context replay and proxy restrictions; launcher prefix is not a containment/cessation contract. |
| P8 | T `hermes_cli/plugin_host_wire.py:102–171,174–252,296–343,356–436`, `Opaque`, `encode/decode/restore`, `Channel`; `hermes_cli/plugin_host_child.py:162–218,228–262,362–382` | JSON value codec, callback direction, per-request threads, caller context lifetime, remote error/EOF semantics. |
| P9 | T `hermes_cli/plugins_context.py:193–205,207–242,798–825,878–899`; `hermes_cli/plugins_ledger.py:29–66,88–101`; `hermes_cli/plugin_host.py:230–267,438–458`; `hermes_cli/plugin_host_child.py:417–425` | Profile/session context, unload cleanup and cancellation, registration versus work lifetime, load abandonment, session-event load fence. |
| P10 | T `website/docs/developer-guide/delegation-provider-plugin.md:8–25,92–99,197–201`; `agent/subagent_lifecycle.py:48–110,269–287,325–400,415–450` | Core retains child lifecycle; public service launches/waits/cancels/results with session-bound capability; no run/epoch/admission transitive closure fact. |
| P11 | T `agent/owned_execution.py:10–114`; `gateway/session_owned_execution.py:8–58` | Private process-local worker/stop scope, sticky unknown, root return not seal; admission/generation binding and signal fence. |
| P12 | T `hermes_cli/plugins_manifest.py:239–273,380–398`; `plugins/AGENTS.md:149–188` | Advisory dependencies/order; API/manifest version distinction; additive compatibility and public-surface publication requirements. |
| P13 | T `hermes_cli/plugins_dispatch.py:26–67,350–430` | Some hooks abandon timed-out workers without joining; pre-tool timeout policy is not all-hook fail-open. No wrapper closure follows. |
| P14 | R `website/docs/developer-guide/api-run-recovery-r-contract-amendment.md:25–35,109–158,160–201` | Missing map stays unconfirmed; coverage excludes all-tool/restart cessation; publication freshness is not physical closure. |

## Existing capability versus missing contract

| Candidate | Existing public capability | Missing / fit verdict |
| --- | --- | --- |
| Tool request/execution middleware | `ctx.register_middleware(kind, callback)`: rewrite args, wrap/replace downstream, short-circuit, registration-order nesting. Narrow callback signatures tolerate added context. [P2–P4] | **Not an enforcement or closure boundary.** Failure before `next_call` is fail-open. A short-circuit can create work without reaching T's unknown marker. Result preservation prevents duplicate downstream dispatch, not unregistered effects. No producer seal, join, exact owner/epoch/admission capability or outer-wrapper attestation. |
| Observer / plugin event bus | Hooks report outcomes; `ctx.emit` queues namespaced events fire-and-forget; terminal observer can describe timeout while actual worker lives. Some hook workers are abandoned without join. [P4,P9,P13] | Events are observations, not authoritative acknowledgements. Unload/cancel/result receipt does not certify side work finished. Do not build a parallel Convoke join ledger from telemetry. |
| Terminal environment provider | Public ABC + `ctx.register_terminal_environment_provider`; plugin owns returned environment's implementation of `execute` and `cleanup`; factory routes unknown backend names. [P1,P2,P5,P6] | Useful future backend-owned adapter, **not a local wrapper**. `local`, docker, modal, managed_modal, daytona, vercel_sandbox and ssh are reserved by registry. `task_id` is reuse/persistence identity, not exact invocation liability. `cleanup` may detach; provider flags and `exec_prefix` are not physical completion evidence. No per-execute ownership token or required stop/join result. |
| Host-isolated environment | Registrar can proxy a `TerminalEnvironmentProvider` ABC. [P5,P7] | Do not confuse registration with usability: `_build_plugin_env` detects hosted provider and refuses before sandbox creation. `create_environment`'s arbitrary environment return is not a supported remote environment proxy. No host-mode terminal adapter is available to reuse. |
| Delegation provider | Per-task route/parameters; absent configured backend fails closed. Docs and registrar explicitly retain spawn, isolation, depth, concurrency, background units and stop fan-out in **core**. [P2,P10] | Routing is not delegation ownership. A provider cannot take over transitive child joins. This is precedent for the recommended core/plugin split, not an alternate implementation. |
| Public subagent lifecycle | `ctx.subagent_lifecycle` → `SubagentLifecycleService.launch/status/wait/cancel/result/reconnect/steer`; serializable session-bound handles and host remote facade. [P1,P9,P10] | Real public API, not overlooked. `wait` waits recorded future/result; unknown handle can return `completed=True` with UNKNOWN diagnostic. `cancel` reports interrupt acceptance. Result terminality does not prove nested tool/cleanup cessation; handle lacks owner/run/epoch/admission/generation binding required here. Do not reinterpret `completed` as settled. |
| Private `OwnedExecution` | Core retains actual futures/workers; `stop` signals owned callbacks; snapshot acknowledges root return + no known workers + no sticky unknown. [P11] | Extend internally, **do not import from plugin** or expose whole object. T marks uncertainty on authorized dispatch, never clears it; `returned()` does not close submission. It is not a public plugin contract or a complete invocation graph. |

### Exact ordering matters

The generic middleware guide summarizes policy before execution middleware. The inspected tool implementation is more precise: Relay wraps `_hermes_pipeline`; tool-request middleware runs there; tool-execution middleware wraps `_authorized_dispatch`; that callback first marks unknown, then calls `_dispatch_authorized_once`, which runs scope/pre-tool hooks, pruned-arg checks, guardrails and execution preparation. Treat the actual definitions as authority; a lifecycle fence inserted only inside the authorized callback misses outer request/Relay/execution-wrapper effects. [P3,P4]

The future invocation must therefore begin **before the first effect-capable callback**, and remain liable through post hooks, transformations and cleanup. A policy refusal proves the base handler did not start, not that prior wrappers did nothing. Preserve all existing authorization behavior. An unadapted wrapper/hook makes the envelope unknown even if the adapted leaf joins. A callback captured before reload remains associated with that captured load, never whatever same-named plugin is now registered.

## Host RPC: capabilities, limitations, failure semantics

**Source-supported:** one host per profile for third-party plugins; bundled plugins remain in process. `HOST_OBJECT_BASES` permits selected ABC object registrations, `HOST_REMOTE_FACADES` permits data-returning services; unsupported methods are explicit. An optional launcher argv prefix does not itself establish OS containment, resource ownership or remote cancellation. [P7]

The codec transmits JSON scalars/collections, bytes envelopes and dataclass records; paths become strings, ABC type hints can restore supported types. Other objects become `Opaque`. Child-owned callbacks/provider objects can become references to host proxies, but that is **not symmetric arbitrary object transport**. Parent `PluginHost.invoke` encodes callback args without a reference resolver; child `_decode_args` decodes without one. Thus a parent `next_call` arrives as opaque, not a callable downstream bridge. Hosted execution middleware cannot be assumed to implement the in-process wrapping example; calling it would fail, and before-next failure falls through under the middleware rule. This is source reasoning, not a newly run probe. [P3,P7,P8]

A returned provider object only becomes a useful proxy when a supported declared ABC return type permits it; otherwise parent `_resolve_result_ref` releases it and returns an opaque placeholder. A Popen, Event, Thread, agent or SDK handle cannot be made authoritative simply by passing it through `ctx`. The actual terminal factory's early refusal is stronger than the ABC docstring's placeholder warning. [P5,P7,P8]

`Channel` supports nested bidirectional calls on separate daemon request threads. While an outbound request is in flight, `origin` can recover its caller's context; after request completion/timeout that context entry is removed. Spontaneous calls use profile base context, not an exact run's durable ownership capability. Copying ContextVars is not registering workers or preserving dispatch rights. [P7,P8]

EOF/channel loss fails pending calls with `PluginHostUnavailable`; remote exceptions are encoded and re-raised as supported exceptions or `PluginHostError`. A timeout stops the caller waiting, **not** the remote request thread. Host shutdown waits/kills the exact host process; restart rotates host generation and reloads plugins with a bounded budget. None of error/EOF/host exit/reload proves arbitrary descendants, previously accepted RPCs or remote jobs ceased. Host generation protects proxy reference reuse; it is separate from runtime epoch, admission generation and plugin-load identity. [P7,P8]

**First-slice decision:** refuse the new owned-tool registrar under host isolation before accepting an adapter. Keep ordinary plugin behavior intact, but such invocations cannot gain closure eligibility. Do not add a transparent `next_call` bridge or distributed join in this slice. If later funded, handles remain authoritative in their creating process/backend; only bounded tokens/facts (`identity`, `load_id`, `resource_id`, signal outcome, producer seal, physical join evidence) may cross. Core must authenticate each sender/load and bind registration before launch, track outstanding RPC/continuations, reject stale/duplicate/conflicting facts and mark lost-host obligations unknown. Existing session-event load checks do not provide that generic ownership protocol. Reconnect/replay must not relaunch an action. This is a missing contract, not an estimate or promise of remote proof.

## Proposed minimum public contract (not implemented)

### Ownership boundary

**Core owns** authoritative run binding, invocation creation, stop/admission linearization, producer rights, continuation/resource ledger, effective implementation/wrapper identity, eligibility aggregation, callback/worker tracking, source signal fan-out, root seal, and projection into existing settlement. **Plugin owns** only its adapter's exact handles, no-new-work discipline, source-specific stop and physical completion evidence. Core trusts a reviewed adapter's narrowly declared contract, not a plugin's arbitrary `covered=True` assertion. Untrusted plugin Python is not a confinement proof.

No plugin can clear global `unconfirmed`, select another owner by session name, certify siblings, reconstruct lost joins, or make its own unload an acknowledgement. Core never imports a specific plugin. This follows Hermes's public boundary/compatibility rules. [P1,P11,P12]

### Typed surface to publish

Proposed new public `agent.tool_lifecycle` definitions and one `PluginContext` registrar; these names do **not** exist at T. Python notation describes the exact first contract, not executable code in this PR:

```python
ExecutionIdentityV1 = frozen_record(
    owner_scope_id: str, run_id: str, runtime_epoch: str,
    admission_id: str, generation: int, invocation_id: str)
AdapterContractV1 = frozen_record(
    contract_version: Literal[1], adapter_id: str, implementation_revision: str,
    backend_id: str, coverage_scope: str, mode: Literal["in_process"])
# Core binds registration_id + plugin_load_id + effective wrapper-chain revision.
# Identity fields are bounded opaque IDs, never paths, payload or credentials.

class OwnedToolV1(Protocol):
    contract: AdapterContractV1
    def run(self, args: dict, scope: InvocationScopeV1) -> str: ...

ctx.tool_lifecycle_capabilities() -> LifecycleCapabilitiesV1
# {contract_versions: (1,), modes: ("in_process",)}; no runtime readiness claim
ctx.register_owned_tool(*, name: str, toolset: str, schema: dict,
                        implementation: OwnedToolV1) -> PluginRegistration
# No override support in v1. Concrete registration, not a tool-name allowlist.

class InvocationScopeV1(Protocol):
    identity: ExecutionIdentityV1             # read-only, core-issued
    def fork(self, *, kind: Literal["child", "continuation"]) -> InvocationScopeV1: ...
    def reserve(self, *, kind: str) -> ResourceTokenV1: ...
    def begin(self, resource: ResourceTokenV1) -> bool: ...
    def attach_stop(self, resource: ResourceTokenV1,
                    signal: Callable[[], None]) -> None: ...
    def never_started(self, resource: ResourceTokenV1) -> None: ...
    def joined(self, resource: ResourceTokenV1) -> None: ...
    def unknown(self, *, reason: UnknownReasonV1) -> None: ...
    def seal(self) -> None: ...
```

`ResourceTokenV1` is an opaque core object tied to the issuing scope, unique resource ID, registration/load and full execution identity, not a PID/session key. `UnknownReasonV1` is a fixed enum: `unsupported`, `lost_handle`, `adapter_failed`, `plugin_lost`, `unaccounted_work`, `identity_mismatch`. Capabilities are data, scope/token methods are **in-process only**; do not send them through the generic codec. Publish only these supported types/methods in `plugin_api.json`, regenerate public API docs and document semantics. Private `OwnedExecution` stays internal.

The registrar validates mode/version/contract, callable/type shapes, registration ownership and duplicate conflicts **before publication**; errors raise rather than warn-and-return-success. It binds the reviewed implementation, not only its declared string revision. New registration is not proof of full envelope coverage. `register_tool` is unchanged and remains legacy/unadapted. Missing lifecycle capability refuses owned registration, never silently registers as covered legacy. No global plugin API version bump, automatic plugin install or permission grant.

### State and linearization rules

1. Core mints the invocation under the existing exact execution's stop/registration gate, before Relay/request/execution middleware and hooks. Start with coverage **unproven**. A reviewed implementation/backend plus fully accounted captured callback chain may establish closed coverage; any unadapted callback/handler path contributes permanent unsupported uncertainty for this invocation. Empty known handles alone cannot establish coverage.
2. `reserve` records a pending resource **before** effectful launch. `begin` atomically checks producer rights and stop latch and changes reserved→launching. If stop wins, it returns false; caller must not launch and records `never_started`. If begin wins, launch is already liable even if stop arrives before the handle is obtained. Never run plugin code under the core lock.
3. `attach_stop` binds the exact source-owned signal after handle creation. If stop already latched, core immediately schedules that signal outside the gate. The launching obligation persists across this gap, preventing a false zero. Spawn failure may use `never_started` only when the source knows no effect was accepted; ambiguous launch/handle loss calls `unknown`. A begun resource cannot otherwise be dropped.
4. `joined` is legal only after the adapter has actually observed its exact resource's lifetime end, including its defined cleanup. It does not mean tool success or rollback. Join/never-started acknowledgements are idempotent for the same fact; conflicting, stale or foreign-token mutations are rejected and cannot close anything. No evidence is routed to a successor. Signal return/failure is a distinct core fact, never a join.
5. `fork` reserves a child/continuation producer before handing off/scheduling it. Root/tool return closes only its own producer; reserved continuations retain independent rights until sealed. No fresh fork/reserve after that producer seals. Stop revokes new effectful `begin`/producer creation even in previously reserved continuations; cleanup/acknowledgement can proceed on pre-existing liabilities. A required effectful cleanup must have its explicit reserved resource before stop. No reopening a closed scope.
6. `seal` irreversibly closes that producer's registration right. Core seals the synchronous adapter producer on actual return/finally, not on timeout/abandoned waiter, and independently accounts for worker exit and reserved continuations. A plugin seal is not a worker ack. Core seals root on real root return and holds post-processing/cleanup obligations until they physically finish. Already registered children may finish after parent result.
7. Unknown/unsupported/lost evidence is absorbing for that invocation in v1; joining a good sibling cannot erase it. Existing sticky unknown executions remain unknown. Foreground/background or cross-execution transfer is **unsupported** in v1; routing a handle elsewhere cannot release original liability. No background product policy is selected.

Closure eligibility is conjunction of: exact authoritative binding; terminal canonical receipt; root physically returned and producer sealed; each invocation's reviewed complete coverage; all producers/continuations sealed; all resources and transitive children physically joined or positively never-started; all source signal tasks settled; no unknown, lost handle, pending launch or transfer. Normal completion and stop use this **same** predicate. Scope facts can be diagnostic while the outer execution remains ineligible. There is no `remove_unknown`, `certify_tool_name` or auto-stop-to-seal API.

### Normal sequence

1. Bind served owner/run/epoch/admission/generation; mint invocation and pin implementation/load/callback identities before any effective callback. Unknown context cannot be replaced by `session_id`/`task_id` from `tool_hook_ids`. [P4,P11]
2. Run existing policy pipeline with obligations around every effect-capable part. Resolve actual effective args/backend/implementation after rewrites without losing earlier liabilities. If a wrapper short-circuits, its own work still needs coverage; no handler-return shortcut.
3. Adapter reserves and begins each resource, creates it, attaches exact stop, waits for actual completion and acknowledges its resources. Reserve finalizer/continuation before parent ack. Return result independently.
4. Core observes real worker exit and finishes accounted post hooks/transforms; seals producers. Once the whole graph and canonical receipt satisfy the predicate, normal completion may settle without any stop request. An unknown sibling still blocks lease release and the next turn.

### Stop sequence

1. Authenticate exact authoritative identity; latch stopped under the same gate as begin/register. Accepted but not begun work proves never-started, or remains pending. No inferred newer admission/generation.
2. Signal exact owned handles outside the gate, including handles attached after the stop latch; keep signal tasks and launch-inflight liabilities. Signal failure records uncertainty, not success.
3. Caller wait budget may end; retain worker/resource/continuation obligations and existing fail-closed lease. Tool result, exception, cancellation or observer delivery is not an ack.
4. Source owners join the actual resources/finalizers and seal. Aggregate the same normal predicate; stopped-but-held child, lost plugin or uncertain remote work stays unconfirmed indefinitely under existing identity policy. No stop of unrelated main-agent/session work.

### Failure and compatibility decisions

| Condition | Required first-slice behavior |
| --- | --- |
| Plugin disabled/missing, incompatible version, load abandoned | No owned registration/certificate. Keep ordinary missing-tool/error behavior; legacy dispatch if it already exists remains unknown, never implicitly covered. |
| Adapter exception before/after effect | Positive no-start evidence may discharge that resource only; ambiguous acceptance or handle loss stays unknown. Do not retry downstream or downgrade the ownership error into a certificate. |
| Middleware raises before next / after next / short-circuits | Preserve existing fail-open/result-preservation semantics; core eligibility remains fail-closed. Unadapted envelope stays unknown regardless of downstream result. |
| Order changes/reload/unload while active | Freeze each invocation's callback/registration/load identity. Disposal stops new eligible registrations but cannot delete live obligations. Retain old source handles through joins; if unavailable, mark lost. New load cannot ack old work. Cleanup exceptions/cancel requests are not joins. |
| Host crashes/restarts/hangs or RPC times out | v1 owned registrar refused in host mode. Any legacy hosted path stays unknown; timeout/EOF/reload cannot discharge its work. No transparent replay of effectful launch. |
| Stale owner/run/epoch/admission/generation/resource callback | Reject; never signal or certify successor. Plugin load and host generation are additional identities, not substitutes for execution binding. |
| Unknown legacy tool/inline dispatch/direct `ctx.dispatch_tool` | Retain conservative unknown. A plugin-owned tool nesting direct registry dispatch cannot claim it is covered without core-created child obligations. No blanket terminal exemption. |
| Old plugin / old Hermes | Old methods, hook signatures, tools and behavior remain valid. New plugin probes local capability method/version and refuses owned registration when absent; `requires_hermes` is supplementary, not sole negotiation. `requires_plugins` is advisory and cannot enforce safety ordering. [P12] |
| Core restart/missing join map | Preserve R's unconfirmed semantics and identity-only indefinite retention. Do not upgrade `all_tool_cessation` or `restart_cessation`; freshness/expiry affects payload access, not execution. [P14] |

Shared main-agent memory, irreversible effects and unrelated concurrent main-agent work remain unchanged. This contract neither isolates/resets memory nor promises rollback. Existing fail-closed lease is not weakened to make the narrow adapter appear useful.

## ONE recommended first implementation specification

**Proposed title:** Add core-owned plugin invocation closure with one fixed foreground leaf (not filed or authorized).

**Goal:** demonstrate natural and stopped closure through the public registration path, with exact identity and unknown-preserving aggregation, without adding a generally enabled tool or replacing terminal backend. Use one generic core extension and one private-to-conformance plugin example; production publication/install is a separate authorization.

**Concrete adapter:** `FixedPythonLeafV1`, in-process only, registered as a unique synthetic owned tool in a temporary plugin discovery environment. Its schema accepts no command, path, argv, backend, environment or network inputs. It launches an absolute Python executable with fixed reviewed `-I -S -B -c` code: read one control-pipe byte, write fixed bounded output, exit. No shell, imports that launch work, descendants, sockets, persistence or promotion. Minimal disposable environment/cwd; no startup scripts or credentials. Test harness controls normal release through the private synchronization seam, not model arguments. Stop closes/releases that exact control pipe; escalation, if needed solely for teardown, targets the still-owned unreaped Popen handle, never PID/name scanning or a group-wide proof.

Adapter owns the exact Popen, control writer, output reader worker, descriptors and finalizer. Reserve each before start, include launch/reader-start failure paths, wait/reap the direct process, observe reader exit and join it, close descriptors and finish finalizer before acknowledgements. Core separately owns adapter/tool worker lifetime. No hidden `BaseEnvironment.execute` deadline thread, persistent shell, background registry or SDK transport is used. Reuse the prior spike's fixed-leaf shape in future tests rather than repeat its OS experiment during this assessment.

**Coverage label:** `fixed_python_leaf_v1/direct_process+io+finalizer`, closed only for the pinned fixed implementation and completely accounted invocation envelope. Evidence is not “Python is safe”: implementation review constrains precisely what this leaf can create. Arbitrary user-supplied Python, terminal commands, escapees, descendants, remote accepted work, delegation, promotion and durable restart joins remain unsupported/unknown. This adapter is **engineering proof**, not useful general H0 coverage. If owner requires ordinary tools immediately, the honest bounded finding is that another backend-specific closure contract is missing; do not expand this task into containment architecture.

### Edit boundaries (future Hermes implementation only)

| Files | Exact responsibility |
| --- | --- |
| New `agent/tool_lifecycle.py`; existing `agent/owned_execution.py` | Publish narrow types/capability implementation; internal per-invocation graph, begin/stop gate, producer seals and conjunction. Do not export private ownership object. |
| `gateway/session_owned_execution.py` | Supply complete owner/run/runtime epoch/admission/generation binding from authoritative admission context, not plugin args. No R storage/DDL/retention changes. |
| `agent/tool_executor.py`, `agent/inline_tool_executors.py` | Create outer envelope early enough for Relay/request callbacks; retain it through actual worker exit, result processing and inline/legacy paths. Conservative unknown for unadapted chain; no tool-name exceptions. |
| `hermes_cli/plugins_context.py`, `hermes_cli/plugins_ledger.py` | New capabilities method/owned registrar, load-bound registration and active-obligation retention across disposal; no core import of specific plugin. |
| `hermes_cli/plugin_isolation.py` | Explicit host-unsupported registrar entry/reason. No new host proxy or wire protocol in this slice. |
| `hermes_cli/data/plugin_api.json`, generated `website/docs/developer-guide/plugins/public-api.md`, new developer contract page | Supported exports, lifecycle/failure/compatibility contract and concrete conformance consumer. |
| Proposed new conformance plugin under `tests/plugins/fixtures/fixed_owned_leaf/` plus focused `tests/agent/` and `tests/plugins/` cases | Synthetic adapter only, real temporary discovery registration. Exact fixture placement to follow existing conventions when implementation is authorized. No default tool/config activation. |
| `gateway/platforms/api_server_run_recovery.py` only if projection needs it | Keep existing outward settlement shape/semantics; consume stronger internal ack, no new readiness/coverage claim. Coordinate overlapping edits separately, not wait for or bundle R. |

If implementation cannot maintain the early envelope through existing callback paths within this estimate, stop with the exact unaccounted boundary and re-estimate; do not shrink the fence to the handler. No blanket observer exemption and no unsupported wrapper allowlist by name.

### Acceptance plan — specification, not tests executed here

Cheapest sufficient tiers: production-state **units** for identity/graph/failure behavior; one **plugin-discovery + fixed local process integration boundary** for real registrar/adapter wiring. No new full agent/model/live HTTP journey: those would duplicate existing ownership ingress evidence without cheaply proving the changed contract. Before future test work read writing-tests and pinned area instructions; reuse existing test infrastructure after inspection then, not source-reading/change-detector tests.

- Units against production ledger/gates: fully covered normal completion closes without stop; held child, open continuation, pending launch, unknown sibling and legacy invocation each block. Joining a leaf never removes unknown. Root return alone is not a seal of children or physical return of abandoned work.
- Deterministic begin/stop races using Events at actual gates, not sleeps: stop-before-begin refuses launch; begin-before-stop retains launch obligation and delivers stop on late handle attach; spawn ambiguity, reader-start failure and signal failure remain unconfirmed. No successful closure from timeout/cancel/result text.
- Identity/registration units: wrong owner/run/epoch/admission/generation/load/resource cannot ack or signal another execution; duplicate same ack is harmless; conflicting ack fails; seal prevents new rights; unload/reload and callback ordering changes preserve old liabilities. A disposed registration does not lose the source stopper/handle.
- Wrapper units: before-next exception still falls through once under old semantics **but never gains coverage**; after-next exception does not repeat effects; short-circuit and added unadapted request/post hook keep envelope unknown. Retained asynchronous cleanup cannot disappear on result return. Host-mode registrar refuses before launch; capability absent/version mismatch cannot publish a covered tool.
- One offline integration through real discovery with temporary home: narrow conformance plugin, no installed state. Fixed subprocess and I/O/finalizer are independently held/released. Natural completion of two successive covered synthetic scopes settles without housekeeping stop; stop accepted while a resource is held remains unconfirmed until actual joins. Mixed unknown sibling stays blocked. Missing required registration/coverage mutations must fail the relevant boundary assertion. Verify cleanup of only fixture-owned handles, even on failure.
- Compatibility: frozen legacy plugin discovery still works unchanged and remains unknown; no default enabled tool/backend, policy, permission or isolation changes; no change to R capability exclusions or retention. These are behavioral assertions, not exact registry-count snapshots.

**Estimate: 16–24h human-equivalent**, one coherent task: graph/identity/gates 6–8h; public registrar/envelope/disposal integration 4–6h; fixed adapter plus cheapest-tier tests 4–6h; compatibility/docs/review 2–4h. Compared with the earlier spike's 12–16h core+leaf suggestion, this includes the newly established public registration and plugin unload/mode compatibility boundary. Dependencies: coordinator approval of this spec and an implementation base containing accepted T (with shared-file coordination when assigned). **No dependency on R completion**, remote provider access or new product policy. Stop and re-estimate before any host distributed join, useful arbitrary terminal coverage, transfer or containment work.

## Decisions and unknowns for coordinator

1. Approve/reject this one technical first slice and its estimate; this report is not permission to implement, install or publish it upstream.
2. Accept explicit in-process-only conformance scope, with no isolation/config switch. If host operation is a must for the first slice, this recommendation cannot deliver it within the same estimate: request a separate reviewed bridge contract, not opaque handle transport.
3. Useful ordinary-tool coverage still requires funding specific source-owned adapters/containment or remote authority contracts. Arbitrary descendants and remote all-caused-work proof remain **unknown absent a real contract**. No new tool restriction or background-transfer product decision is selected here.

Already resolved and **not reopened**: shared main-agent memory, identity-only indefinite-unknown retention, fail-closed lease, independent R work, no runtime acceptance/unblock. No new tickets/threads/agents created.

## Actual verification and handoff boundary

Only this Markdown report changes. Actual documentation checks: an inline Python standard-library check resolved **25 pinned source objects / 72 citation ranges**, **14 source references**, **1 local Markdown link** and **1 balanced fenced block**, with no trailing whitespace; exit 0. This validates citation existence/range bounds and structure, not semantic correctness automatically; definitions and conclusions were source-reviewed above. Root `package.json` has no scripts or configured Markdown-lint command. `git diff --cached --check` checked the staged new report's whitespace, exit 0. No automated test/fixture, Hermes, Swift or server suite was run; no historical T/R count is claimed as current evidence. Documentation PR goes to Convoke coordinator review, not self-merge/issue closure. Preserve this managed worktree while unmerged; clean-only cleanup after coordinator approval/merge, never force.
