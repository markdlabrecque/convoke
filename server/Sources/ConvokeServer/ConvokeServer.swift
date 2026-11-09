import Foundation
import Vapor

@main
enum ConvokeServer {
    static func main() async throws {
        var environment = try Environment.detect()
        try LoggingSystem.bootstrap(from: &environment)
        let app = try await Application.make(environment)
        do {
            try configure(app)
            try await app.execute()
            try await app.asyncShutdown()
        } catch {
            try? await app.asyncShutdown()
            // A plain one-line message, not a crash trace.
            let message = (error as? Abort)?.reason ?? "\(error)"
            FileHandle.standardError.write(Data("ConvokeServer cannot start: \(message)\n".utf8))
            exit(1)
        }
    }
}
