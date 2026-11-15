# Convoke domain model

Convoke lets a user speak to an agent and hear its replies without submitting each utterance manually. The iPhone handles listening and playback; the server obtains agent replies and synthesizes their speech.

Use [GLOSSARY.md](../GLOSSARY.md) for definitions. This document describes relationships, lifecycle rules and their mapping to the current code. It is not a test-results record or a claim that physical playback acceptance has passed.

## One domain, two cooperating applications

The iPhone and server use the same interaction language. They are not separate domain contexts just because they run on different devices.

```text
Session
  conversation history shared across its conversations
  Conversation, zero or more over the session's lifetime
    Turn, repeated sequentially
      User utterance
        Transcript, provisional during recognition, finalized before submission
      Agent reply
        Reply text
        Spoken rendering using a voice
```

This is a conceptual relationship diagram, not a storage schema. A session may end before any conversation starts. A conversation may end without submitting an utterance, and a submitted turn may be interrupted before its reply is heard. Conversations and turns are not persisted records in the current implementation.

## Boundaries agreed for this model

- **Session** names the shared interaction context. **Conversation** names a single period of hands-free interaction inside it. Ending a conversation does not inherently mean forgetting its history.
- **Turn** names the whole user/agent exchange, including playback. **Utterance** names only the user's spoken contribution. Do not call an utterance and its reply two separate turns.
- **Reply** names the agent's answer, not a transport response. Its text and audio are representations of the same answer.
- **Conversation history** names context available to the agent, not a recording of what the user heard. A finalized transcript is the user's recognized text, not both sides of the interaction.

These naming choices were confirmed with the owner. They clarify the model without changing current behavior or renaming code in this documentation pass.

## Session and conversation are different lifetimes

In the current implementation, a successful connection establishes a session. It does not start microphone capture. Starting a conversation activates the sequential listen/reply loop in that session.

Ending a conversation can leave the session available for another conversation. Earlier context is then still available to the agent. Disconnecting ends both the conversation and the session; connecting again establishes a new session with no retained history from the old one.

There is an important implementation constraint. The protocol has no way to cancel one unfinished reply while preserving the session. If the user ends a conversation before reply delivery is complete, the app disconnects. In that case End conversation ends the session too. Once delivery is complete, stopping the remaining playback can preserve the session.

```text
Connect successfully
  Session exists, no conversation active, microphone off

Start conversation
  Conversation active
    listen for an utterance
    finalize its transcript
    submit accepted text
    receive and play the agent's reply
    complete the turn
    listen again

End conversation
  if reply delivery is unfinished: end session as well
  otherwise: stop listening/playback, retain session

Disconnect
  end conversation and discard session context
```

The server does not receive Start conversation or End conversation events. It cannot identify or count the separate conversations within a session. The app tracks whether a conversation is active; the server retains history for the connection.

## From utterance to turn

While listening, recognition produces provisional text and committed segments. Convoke ends audio input and waits for the finalized transcript before submitting a contribution. Provisional text is not a substitute if finalization fails.

A silent capture attempt or an empty finalized transcript produces no submitted turn. An oversized utterance is rejected locally rather than sent as a partial contribution. Capture timing, size limits and error messages are specified in [the iPhone guide](../ios/Convoke/README.md), not in the glossary.

After a valid utterance is submitted, Convoke keeps the microphone off while waiting for and playing the reply. Turns are sequential. The user cannot interrupt a reply by speaking over it; barge-in is not part of the current model.

A turn can finish successfully, fail or be stopped. Stopping playback is not successful completion of that turn, even if the entire reply has already arrived.

## A reply has several completion boundaries

The agent produces its complete reply text before speech synthesis begins. Text generation is not streamed. Kokoro can produce reply audio incrementally, and the iPhone can receive audio while playing earlier audio. The macOS speech adapter still buffers its synthesis internally.

Keep these boundaries distinct:

| Boundary | What has finished | What it does not establish |
| --- | --- | --- |
| Reply text generated | The agent has supplied the answer's text | Audio generation, delivery or playback |
| Synthesis EOF | The server has consumed the audio source successfully | That the phone received or played every sample |
| Reply delivery complete | The phone validated `agent.done` against the received audio sequence and count | That queued audio has played |
| Playback drained | All scheduled audio has received the player's played-back completion callbacks | Successful delivery if EOF is still unvalidated; independent proof of audible speaker output |
| Successful turn completion | Delivery is validated and playback is drained for the same current reply | Physical-device acceptance or proof that speech was intelligible |

Listening resumes only after successful turn completion, and only while the conversation is still active. Empty playback buffers before delivery completes mean an underrun, not the end of a turn. Later audio belongs to the same reply; it is not a new turn.

Playback-start notification means the player node started. It is not a claim that the first sound physically reached the user's ears. Multiple network frames are likewise not proof of early audible playback.

## Conversation history is context, not a hearing record

The server adds the user's accepted text to history before asking the agent for a reply. It adds the reply text before speech synthesis and playback finish. It does not wait for confirmation that the user heard the answer.

Consequently, a reply stopped after delivery can remain in history even though the user did not hear all of it. Another conversation in the same session can use that reply as context. There is no heard/unheard flag or completed-turn ledger in the current model.

History is bounded and held in memory. The server retains at most 40 user/agent messages and removes older whole pairs as new contributions arrive. It does not retain every contribution indefinitely. Disconnecting discards that history, and neither audio nor a durable conversation transcript is stored by Convoke.

The agent, recognizer and voice have different roles. The recognizer supplies the user's text; the agent generates an answer using available context; the voice renders that answer as speech. A speech-synthesis failure is not permission to change voices automatically. Current configuration details belong in [the server guide](../server/README.md).

## Scenarios that test the boundaries

These are model expectations and code-derived behavior, not a new record of executed acceptance tests.

| Scenario | Interpretation |
| --- | --- |
| The user connects and waits without starting | A session exists, but there is no active conversation and no microphone capture |
| The user completes three exchanges without touching the phone | One conversation contains three turns in the same session; listening resumes after each complete reply |
| The user stops while listening, then starts again | The first conversation ends and another begins in the same session; available history is retained |
| The user stops after validated delivery but before playback drains | The conversation ends and the turn is stopped, not successfully completed; the session and reply text in history can remain |
| The user stops during playback while the reply is still arriving | The conversation and session end because unfinished delivery cannot be cancelled independently |
| The audio queue runs dry before delivery completes | The turn is still in progress; the microphone stays off and later audio continues the same reply |
| Permission or recognition preparation fails before submission | The conversation stops without a submitted turn; an otherwise open session can remain ready |
| A final transcript contains a recognition mistake | It is still finalized text; finalization is not a guarantee of linguistic accuracy |
| The server or audio source fails after some speech was delivered | The turn fails; partial speech is not successful completion and no automatic voice fallback is allowed |
| A callback from a stopped reply arrives after another reply starts | It belongs to the old interaction and must not complete the new turn or restart listening |
| The user disconnects and manually connects again | A new session begins; old history and unfinished turns are not resumed |

## Mapping the language to the code

Existing names do not all match this model. Use this table when reading the code; do not infer a domain boundary from a class name alone.

| Domain concept or boundary | Current implementation | Naming caveat |
| --- | --- | --- |
| Session and history | Server [`Conversation`](../server/Sources/ConvokeServer/Conversation.swift), one instance per connection | Despite its name, this class covers the session, not one Start-to-End conversation |
| Active conversation | iPhone [`SessionController`](../ios/Convoke/Core/SessionController.swift), `isConversationActive`, `startConversation`, `endConversation` | The controller manages both session and conversation lifetimes |
| User utterance and transcript | [`SpeechCapture`](../ios/Convoke/Core/SessionController.swift), [`AppleSpeechCapture`](../ios/Convoke/App/AppleSpeechCapture.swift) | Capture comments sometimes call the user's contribution a turn; prefer utterance in new documentation |
| Agent and reply text | Server [`Agent`](../server/Sources/ConvokeServer/Agent.swift), `reply(to:)`, `ChatMessage` | Agent is the answering participant, not the synthesizer or voice |
| Reply delivery validation | [`ResponseAccumulator`](../ios/Convoke/Core/ResponseAccumulator.swift) | Response is a protocol/implementation name; it does not define another domain entity |
| Current reply and completion | `SessionController.Reply`, `networkFinished`, `playerDrained` | These flags describe separate completion conditions, not different replies |
| Reply speech | Server [`SpeechSynthesizer`](../server/Sources/ConvokeServer/SpeechSynthesizer.swift), [`KokoroSpeechSynthesizer`](../server/Sources/ConvokeServer/KokoroSpeechSynthesizer.swift), [`MacSpeechSynthesizer`](../server/Sources/ConvokeServer/MacSpeechSynthesizer.swift) | Synthesizer is a technical role; voice names the speaking identity |
| Reply playback | iPhone [`PCMPlayer`](../ios/Convoke/App/PCMPlayer.swift), [`PCMPlaybackQueue`](../ios/Convoke/Core/PCMPlaybackQueue.swift), [`PCMPlaybackLifetime`](../ios/Convoke/Core/PCMPlaybackQueue.swift) | Scheduling and draining audio are not independent proof of audible output |
| Visible Listening state | `SessionController.State.recording` | Recording here means live capture for recognition, not a persisted audio recording |

## Model versus verification

Definitions and lifecycle expectations are not proof that every adapter obeys them. In particular, the Mac verification in [PR #36](https://github.com/markdlabrecque/convoke/pull/36) records failed upstream-cancellation assertions and failed opt-in simulator audio initialization. Physical early playback and the remaining device checks are not established by this domain model.

Use [development and verification records](development.md) and the individual Slice 4 verification documents for executed results. Do not turn a desired invariant in this document into a Pass entry without running the appropriate check.
