# Convoke

Convoke is a hands-free spoken interface to an agent. This glossary defines the language shared by the iPhone app and the server; [the domain model](docs/domain-model.md) describes their relationships and current behavior.

## Language

### Participants

**User**:
The person speaking to the agent and hearing its replies.
_Avoid_: Client when referring to the person

**Agent**:
The participant that answers the user's utterances using the session's conversation history. It is distinct from the voice that speaks its replies.
_Avoid_: Voice, speech model

**Voice**:
The speaking identity used to render the agent's replies as speech. Changing a voice does not make it a different agent.
_Avoid_: Agent, speech recognizer

### Interaction

**Session**:
The shared interaction context in which the agent can refer to earlier contributions. A session can contain multiple conversations.
_Avoid_: Conversation when referring to the entire shared-context lifetime

**Conversation**:
A continuous period of hands-free interaction within a session. Ending a conversation does not necessarily end its session.
_Avoid_: Session, connection

**Turn**:
One exchange consisting of a user utterance and the agent's reply, including hearing the spoken reply. A turn can be interrupted rather than completed.
_Avoid_: User turn, agent turn, request when referring to the whole exchange

**Utterance**:
The user's spoken contribution to a turn. Silence alone is not an utterance.
_Avoid_: Turn when referring only to the user's contribution

**Reply**:
The agent's answer to a submitted utterance. Its text and spoken rendering are two forms of the same reply, not separate turns.
_Avoid_: Response when referring to the domain answer rather than a transport response

### Text and context

**Transcript**:
The text recognized from a user utterance, whether provisional or finalized. It is not a record of both sides of a conversation.
_Avoid_: Conversation history, recording

**Finalized transcript**:
The recognizer's committed text for an utterance, as distinct from provisional recognition results. Finalized does not imply that every word was recognized correctly.
_Avoid_: Partial transcript, live transcript when referring to the submitted text

**Conversation history**:
The retained user and agent messages that provide context for later replies in the session.
_Avoid_: Transcript, audio history, conversation recording
