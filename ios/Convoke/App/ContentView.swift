import ConvokeCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var session: SessionController

    var body: some View {
        VStack(spacing: 24) {
            Text("Convoke").font(.largeTitle)
            TextField(SessionController.exampleURL, text: $session.serverURL)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(session.state != .disconnected)
                .accessibilityLabel("Server WebSocket URL")
            Button(session.state == .disconnected ? "Connect" : "Disconnect") {
                if session.state == .disconnected {
                    Task { await session.connect() }
                } else {
                    session.disconnect()
                }
            }
            .buttonStyle(.bordered)
            Text(session.statusText)
                .accessibilityLabel("Session state: \(session.statusText)")
            if let error = session.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: \(error)")
            }
            Button(session.isConversationActive ? "End conversation" : "Start conversation") {
                if session.isConversationActive {
                    session.endConversation()
                } else {
                    Task { await ConvokeApp.requestConversationStart() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.isConversationActive && session.state != .ready && session.state != .disconnected)
            Text("Developer-only. Use a trusted network. Speech is recognized on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
