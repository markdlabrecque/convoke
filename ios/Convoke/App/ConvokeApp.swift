import ConvokeCore
import OSLog
import SwiftUI
import UIKit

@main
@MainActor
struct ConvokeApp: App {
    // Register for backgrounding before either the view or a cold App Intent can use the session.
    private static let runtime: (session: SessionController, backgroundObserver: NotificationCenter.ObservationToken) = {
        let session = SessionController(
            transport: WebSocketTransport(), recognition: AppleSpeechCapture(waitForActivation: waitForActiveScene),
            timer: DeadlineTimer(), silenceTimer: DeadlineTimer(), player: PCMPlayer(),
            log: { message in Logger(subsystem: "com.convoke.app", category: "session").error("\(message, privacy: .public)") }
        )
        // Inactivity alone can mean a permission sheet is open.
        let observer = NotificationCenter.default.addObserver(of: UIApplication.self, for: .didEnterBackground) { _ in
            session.disconnect()
        }
        return (session, observer)
    }()

    var body: some Scene {
        WindowGroup { ContentView(session: Self.runtime.session) }
    }

    @discardableResult
    static func requestConversationStart() async -> SessionController.StartRequest {
        await runtime.session.requestConversationStart(whenActive: waitForActiveScene)
    }

    private static func waitForActiveScene(while isCurrent: @MainActor () -> Bool) async -> Bool {
        // Foreground intents can arrive just ahead of scene activation. Wait briefly
        // within this invocation, never leave a flag for some future app launch.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while isCurrent(), !Task.isCancelled, clock.now < deadline {
            if UIApplication.shared.applicationState == .active,
               UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }) {
                return true
            }
            do { try await clock.sleep(for: .milliseconds(40)) }
            catch { return false }
        }
        return false
    }
}
