import ConvokeCore
import OSLog
import SwiftUI

/// No audio playback in this task. The companion playback task replaces this.
@MainActor
private final class PendingPlayer: ConversationPlayer {
    func stop() {}
}

@main
struct ConvokeApp: App {
    @StateObject private var session = SessionController(
        transport: WebSocketTransport(), recognition: AppleSpeechCapture(),
        timer: DeadlineTimer(), player: PendingPlayer(),
        log: { message in Logger(subsystem: "com.convoke.app", category: "session").error("\(message, privacy: .public)") }
    )

    var body: some Scene {
        WindowGroup { ContentView(session: session) }
    }
}
