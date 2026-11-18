import XCTest
import NIOCore
@testable import ConvokeServer

final class ConversationConfigTests: XCTestCase {
    func testDefaultsWithUnsetOrBlankBindHost() throws {
        for environment in [[:], ["CONVOKE_BIND_HOST": ""], ["CONVOKE_BIND_HOST": " \t\n"]] {
            let config = try ConversationConfig(environment: environment)
            XCTAssertEqual(config.bindHost, "127.0.0.1")
            XCTAssertEqual(config.turnTimeout, .seconds(120))
        }
    }

    func testExplicitHostAndValidTimeouts() throws {
        for seconds in [10, 240, 3600] {
            let config = try ConversationConfig(environment: [
                "CONVOKE_BIND_HOST": " 100.64.0.1 ",
                "CONVOKE_TURN_TIMEOUT_SECONDS": String(seconds),
            ])
            XCTAssertEqual(config.bindHost, "100.64.0.1")
            XCTAssertEqual(config.turnTimeout, .seconds(Int64(seconds)))
        }
    }

    func testInvalidTimeoutsAreRejected() {
        for value in ["9", "3601", "0", "10.5", ""] {
            XCTAssertThrowsError(try ConversationConfig(environment: ["CONVOKE_TURN_TIMEOUT_SECONDS": value]))
        }
    }

    func testExplicitTimeoutOverridesEnvironment() throws {
        let config = try ConversationConfig(
            environment: ["CONVOKE_TURN_TIMEOUT_SECONDS": "invalid"], turnTimeout: .milliseconds(500)
        )
        XCTAssertEqual(config.turnTimeout, .milliseconds(500))
    }
}
