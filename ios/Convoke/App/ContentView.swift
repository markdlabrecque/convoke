import ConvokeCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var session: SessionController
    @State private var errorOccurrence = 0

    private struct Feedback: Equatable {
        let status: String
        let error: String?
        let errorOccurrence: Int
    }

    var body: some View {
        let feedback = Feedback(status: session.statusText, error: session.errorMessage, errorOccurrence: errorOccurrence)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Convoke")
                    .font(.largeTitle)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Conversation status")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(feedback.status)
                        .font(.title2.bold())
                        .accessibilityLabel("Conversation status: \(feedback.status)")
                }
                .fixedSize(horizontal: false, vertical: true)

                if let error = feedback.error {
                    Text("Error: \(error)")
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    if session.isConversationActive {
                        session.endConversation()
                    } else {
                        Task { await ConvokeApp.requestConversationStart() }
                    }
                } label: {
                    actionLabel(session.isConversationActive ? "End conversation" : "Start conversation")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.isConversationActive && session.state != .ready && session.state != .disconnected)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Server WebSocket URL")
                        .accessibilityHidden(true)
                    TextField(SessionController.exampleURL, text: $session.serverURL)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(session.state != .disconnected)
                        .accessibilityLabel("Server WebSocket URL")
                }

                Button {
                    if session.state == .disconnected {
                        Task { await session.connect() }
                    } else {
                        session.disconnect()
                    }
                } label: {
                    actionLabel(session.state == .disconnected ? "Connect" : "Disconnect")
                }
                .buttonStyle(.bordered)

                Text("Developer-only. Use a trusted network. Speech is recognized on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onReceive(session.$errorMessage.dropFirst()) { error in
            // A retry can publish the same error before the next render.
            if error != nil { errorOccurrence += 1 }
        }
        .onChange(of: feedback) { old, new in
            // Speak changes together without moving focus or repeating a persistent error.
            let error = new.errorOccurrence != old.errorOccurrence ? new.error.map { "Error: \($0)" } : nil
            let status = new.status != old.status ? new.status : nil
            let changes = [error, status].compactMap { $0 }
            if !changes.isEmpty {
                AccessibilityNotification.Announcement(changes.joined(separator: " ")).post()
            }
        }
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 44, minHeight: 44)
    }
}
