@testable import swsh
import XCTest

class ExternalCommandTests: XCTestCase {
    func testDescriptionNoEscape() throws {
        let cmd = ExternalCommand("cat", arguments: ["foo", "bar"], addEnv: ["quux": "YOLO-WORLD", "x": "42"])
        XCTAssertEqual(cmd.description, "quux=YOLO-WORLD x=42 cat foo bar")
    }

    func testDescriptionWithEscapes() throws {
        let zalgo = "Z\u{032e}\u{031e}\u{0320}\u{0359}\u{0354}\u{0345}\u{1e00}\u{0317}\u{031e}\u{0348}" +
            "\u{033b}\u{0317}\u{1e36}\u{0359}\u{034e}\u{032f}\u{0339}\u{031e}\u{0353}G\u{033b}O\u{032d}" +
            "\u{0317}\u{032e}"
        let cmd = ExternalCommand(
            "run a program",
            arguments: ["foo", #"\"#, "", zalgo],
            addEnv: ["$a": "YOLO WORLD", "x": "4$2'"]
        )
        XCTAssertEqual(cmd.description, #"'$a'='YOLO WORLD' x='4$2'\''' 'run a program' foo '\' '' '"# + zalgo + "'")
    }
}
