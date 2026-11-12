import ConvokeCore
import OSLog
import SwiftUI

@main
struct ConvokeApp: App {
    @StateObject private var session = SessionController(
        transport: WebSocketTransport(), recognition: AppleSpeechCapture(),
        timer: DeadlineTimer(), silenceTimer: DeadlineTimer(), player: PCMPlayer(),
        log: { message in Logger(subsystem: "com.convoke.app", category: "session").error("\(message, privacy: .public)") }
    )

    var body: some Scene {
        WindowGroup { ContentView(session: session) }
    }
}
