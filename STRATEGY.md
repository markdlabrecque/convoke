# Convoke Strategy

## Vision

<!-- vision: author-approved 2026-11-23 -->

`convoke` exists so that a person can talk with their own agent hands-free and hear it answer, through a server they run themselves.
It serves the single owner who self-hosts the server, and it turns their spoken utterance into finalized text for the agent and the agent's reply into speech.
It owns exactly one thing: the spoken turn between a user and an agent.

### Hands-free first

Once a conversation starts, nothing in it requires touching or looking at the phone until the user ends it, with the call's End control, a CarPlay control or a headset button.
The user can speak over a reply, which stops playback and begins the next utterance.
A conversation continues when the phone locks or the app leaves the foreground, and it is presented as a call so the live microphone is always visible, and a CarPlay screen driven by the same iPhone app is welcome.
The phone's built-in voice speaks fixed phrases for failures, reconnecting and long waits, and two kinds of agent-supplied text, spoken as received and capped at 80 characters: a short status, and the description of an action approved by an assumed yes.
A dropped connection is retried for up to 60 seconds with the microphone closed, and after that the conversation ends and waits for an explicit start.
An agent's permission request is asked aloud, and the app matches one short utterance on the device against a fixed list of yes and no words, without sending it to the agent as a turn.
An unmatched answer is asked once more, and a second unmatched answer, silence, or a request that cannot be asked aloud counts as yes, whatever the action, with the user hearing afterwards what was approved.

### The agent belongs to someone else

Convoke holds no agent logic of its own: it does not judge which actions are safe, and the assumed yes is the only decision it makes on a user's behalf.
It is agnostic about what receives its text: anything the owner wires up behind an OpenAI-compatible chat endpoint, such as Hermes, Claude Code, Codex or Pi.
The server speaks only that endpoint, and its code names no agent and knows no agent's tools.
An adapter for an agent's native API is a separate program in its own repository that presents that endpoint, using only its agent's documented public surface.
Progress, permission requests and cancellation reach Convoke only through optional extensions to that endpoint, published in `protocol/` as a versioned spec with JSON Schemas and fixtures, and an adapter is Convoke-compatible only when it passes them.
The owner maintains one reference adapter, for Hermes, in a sibling repository: the documentation links to it as the worked example, and CI runs an end-to-end check against it that must pass before anything merges.
Wiring an agent up is the owner's job, and beyond that example the documentation explains how in general, without a guide for a particular hosted provider.
Convoke works with unmodified, officially released agents: no fork, core patch, private-API monkeypatch or custom build ships, and a feature the public surface cannot support safely waits.
The iPhone app is a microphone, a speaker and a socket, and matching a spoken yes or no is the only interpretation of words it does: there are no voice commands, not even one to end a conversation.

### Fail closed, never substitute

A missing or invalid setting stops the server at startup and says why.
An agent error or an empty reply closes the turn, with no echo in its place, and a speech failure closes the turn, with the agent's reply never spoken in another voice.
Provisional recognition text is never sent in place of a finalized transcript, and an interrupted turn is discarded and never resumes, on reconnect or otherwise.
The one deliberate downgrade: when an adapter announces an extension version the server does not know, the server runs it as a plain endpoint, without progress, spoken approvals or cancellation, and says so in one line at startup.

### Speech stays with its owner

Recognition runs on the iPhone, with no cloud fallback and no server-side recognizer.
The user's audio never leaves the phone and is never stored, and only finalized text crosses the wire.
Conversation history is kept as text on the owner's server, capped in size and never expired by age, so a disconnect does not make the agent forget.
It is kept per phone, under an identifier the app generates, which is not a secret and is not checked.
The owner deletes that history with an explicit command on the server, never by voice, and it is never shown or cached on the phone.
Logs carry sizes, counts and status codes, never words or audio.
Where the text goes behind the endpoint is the owner's choice, and when the endpoint is neither loopback nor a private address the server says at startup that text will leave the machine, blocking nothing and with no setting to silence it.
The server binds loopback by default, and wider reach is an explicit choice by the person running it.
The microphone is open inside a conversation the user started, or it is closed: there is no paused state that listens for a wake phrase, and connecting, launching the app or a failed reconnect never starts listening.

### Every wait and every buffer has a limit

Turn text, frames, queued audio, capture length, stored history, agent-supplied spoken text, the retry window and turn duration each have a stated cap.
Crossing a cap rejects the input or closes the connection, and nothing is truncated silently.
Disconnect, deadline and a failed write cancel the upstream work, not only the socket.

### A claim is only as strong as its evidence

Software tests, simulator runs and physical-iPhone checks are different kinds of evidence and are reported separately.
A check that did not run is recorded as pending, waived or deferred, never as passed.
Physical-iPhone acceptance does not block a merge, a failing reference-adapter check does until the adapter is fixed or pinned, and work may close with exceptions that stay written down where the next reader finds them.
A behavior change shows a failing check before it and a passing check after it, from deterministic tests in which each assertion has one owning test.
Session, conversation, turn, utterance and reply mean what `GLOSSARY.md` says they mean.

### Scope

Convoke is not an agent, not an agent framework, not a speech model, not the agent's long-term memory and not a chat-log viewer.
It is not a hosted or multi-user service, and it has no application authentication, not even a bearer token, even though a connection can drive an agent whose permission requests are pre-approved: access control belongs to the network its owner controls.
The iPhone on iOS 26 is the only client: no browser client and no Android client, including one a contributor offers to maintain.
Agent-text streaming, resuming an interrupted turn, manual submit, tap-to-approve controls, wake phrases, voice commands, cloud recognition, in-server agent adapters, tool-to-phrase tables, sorting actions into safe and dangerous, and expiring history by age are out of scope.

A change aligns when it makes the spoken turn more hands-free, more reliable, more private or more honest about what was verified, without adding agent logic, a substitute for the agent's reply, an unbounded wait, or a path that opens the microphone outside a conversation the user started.
A change should be resisted when it needs a tap or a glance mid-conversation, sends or stores audio, logs what was said, shows history on the phone, adds a voice command, patches the agent instead of using its public surface, puts code for a particular agent or provider in the server, adds a second client or an authentication layer, widens exposure by default, or claims a physical result no one observed.
