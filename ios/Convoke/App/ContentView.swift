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
            Text(session.state.rawValue.capitalized)
                .accessibilityLabel("Session state: \(session.state.rawValue)")
            Button(session.state == .recording ? "Submit recording" : "Start recording") {
                Task {
                    if session.state == .recording {
                        await session.submitCapture()
                    } else {
                        await session.startCapture()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled((session.state != .ready && session.state != .recording) || session.isFinalizing)
            Text("Developer-only. Use a trusted network. Apple speech recognition may send audio off-device.")
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
