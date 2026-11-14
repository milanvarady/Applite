import Foundation

@main
enum FontCaskMetadataTests {
    static func main() throws {
        let font = try decode(artifacts: [["font": ["FiraCode-Regular.ttf"]]])
        let app = try decode(artifacts: [["app": ["Sample.app"]]])
        let emptyFont = try decode(artifacts: [["font": [String]() ]])
        let noArtifacts = try decode(artifacts: nil)

        precondition(font.isFontCask, "A cask with a font artifact must be recognized as a font")
        precondition(!app.isFontCask, "App artifacts must not classify a cask as a font")
        precondition(!emptyFont.isFontCask, "An empty font artifact must not create an empty category entry")
        precondition(!noArtifacts.isFontCask, "Casks without artifacts must remain non-font casks")
        print("PASS: Homebrew font artifact classification")
    }

    private static func decode(artifacts: [[String: Any]]?) throws -> CaskDTO {
        var object: [String: Any] = [
            "token": "sample",
            "full_token": "homebrew/cask/sample",
            "tap": "homebrew/cask",
            "name": ["Sample"],
            "homepage": "",
            "url": "https://example.test/sample.dmg",
            "deprecated": false,
            "disabled": false
        ]
        if let artifacts {
            object["artifacts"] = artifacts
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(CaskDTO.self, from: data)
    }
}
