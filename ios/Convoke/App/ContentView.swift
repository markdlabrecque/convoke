import ConvokeCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var session: SessionController
    @Environment(\.scenePhase) private var scenePhase

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
                    Task { await session.startConversation() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.isConversationActive && session.state != .ready)
            Text("Developer-only. Use a trusted network. Speech is recognized on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onChange(of: scenePhase) { phase in
            // Foreground-only. A permission sheet makes the scene inactive, so
            // disconnect only on background, not while requesting permissions.
            if phase == .background { session.disconnect() }
        }
    }
}
