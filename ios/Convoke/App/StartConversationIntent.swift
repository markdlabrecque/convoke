import AppIntents
import Foundation

struct StartConversationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Conversation"
    static let description = IntentDescription("Open Convoke and start a conversation using your saved server.")
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult {
        guard systemContext.currentMode == .foreground else { throw StartError.foregroundUnavailable }
        switch await ConvokeApp.requestConversationStart() {
        case .unavailable: throw StartError.foregroundUnavailable
        case .connectionInProgress: throw StartError.connectionInProgress
        case .alreadyInProgress, .accepted: return .result()
        }
    }

    private enum StartError: LocalizedError, CustomLocalizedStringResourceConvertible {
        case foregroundUnavailable, connectionInProgress

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .foregroundUnavailable: "Open Convoke and tap Start conversation again."
            case .connectionInProgress: "Convoke is connecting. Try Start conversation again once it connects."
            }
        }
        var errorDescription: String? { String(localized: localizedStringResource) }
    }
}

struct ConvokeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartConversationIntent(),
            phrases: ["Start a conversation with \(.applicationName)"],
            shortTitle: "Start Conversation",
            systemImageName: "mic"
        )
    }
}
