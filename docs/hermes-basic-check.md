# Basic Hermes integration: owner live checklist

**Deferred and untested.** This checklist is retained for reference only. Do not run it as part of [server and iOS completion](development.md#current-priority-finish-the-server-and-ios-app). If the [owner live check](https://github.com/markdlabrecque/convoke/issues/95) is separately resumed, run it on a physical iPhone. Follow the [Hermes setup](../server/README.md#hermes) on the Linux development machine, using the existing Hermes configuration and the Kokoro sidecar. Use harmless, non-sensitive utterances; Hermes shares memory with the main agent and may retain conversation history. Record outcomes and timings only, not transcripts, audio, keys, or network identifiers. Leave unrun or inconclusive rows Pending.

| Procedure | Expected | Result |
| --- | --- | --- |
| 1. Connect the iPhone over WSS, start a conversation, and ask a plain question that needs no tool. | The connection succeeds and a relevant reply plays aloud. | Pending |
| 2. Ask a question that needs a harmless read-only tool, such as checking the Linux host's current time. | Hermes uses the tool and the phone plays the answer within the configured turn deadline. | Pending |
| 3. Create a disposable scratch directory with no real data. Ask Hermes to run a command known to be guarded under the existing policy, chosen so that any effect is confined to that directory and harmless even if it runs. Do not change the policy or grant approval. Check the directory afterwards. | Hermes refuses the command and the directory is untouched. If the command runs, stop the checklist and record the unexpected execution without recording transcript or command output. | Pending |
| 4. During a slow, harmless turn, tap End conversation while waiting for the reply. Check on the Hermes side whether that exact run carried on, without copying its content. Once its outcome is known and it is no longer running, reconnect and complete a new turn. | The phone stops waiting and does not speak the abandoned reply. Hermes may continue; record what is observed rather than inferring cancellation. The new turn receives a spoken reply. | Pending |
| 5. Tell Hermes a harmless fact to remember. Disconnect, reconnect, and start a fresh conversation with a different opening; ask for the fact back. | Hermes is expected to recall the fact from shared memory despite the fresh conversation. | Pending |
| 6. Open two conversations on separate connections with the same first sentence. Establish harmless context later in the first conversation, then check whether the second can continue it without restating it. | The second conversation may pick up the first Hermes session. Record whether it does; recall alone is not proof of session reuse because memory is shared. | Pending |
| 7. Speak one utterance for more than 60 seconds and another for about 3 minutes. Avoid pauses long enough to trigger the silence timeout and keep each transcript within 16 KiB of UTF-8. | Neither utterance cuts off at 60 seconds. Each submits once after the user stops speaking and gets a spoken reply. | Pending |
| 8. With `CONVOKE_TURN_TIMEOUT_SECONDS=600`, use a harmless turn that takes Hermes more than 120 seconds. Time it from submission. | There is no cutoff at the old 120-second deadline. The server delivers the reply within the raised deadline and the phone plays it in full. | Pending |

## Decide afterwards

- Whether to restrict the Hermes tools available to Convoke.
- Whether to send an explicit Hermes session identity.
- Whether to change the iPhone's silence timeout.
- Whether to add a best-effort stop request to Hermes.
