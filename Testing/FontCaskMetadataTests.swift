import Foundation

@main
enum FontCaskMetadataTests {
    static func main() throws {
        let font = try decode(artifacts: [["font": ["FiraCode-Regular.ttf"]]])
        let app = try decode(artifacts: [["app": ["Sample.app"]]])
        let renamedFont = try decode(artifacts: [["font": ["Source.ttf", ["target": "Renamed.ttf"]]]])
        let packageFont = try decode(
            token: "font-sf-pro",
            artifacts: [["pkg": ["SFProFonts.pkg"]]],
            rubySourcePath: "Casks/font/font-s/font-sf-pro.rb"
        )
        let regularPackage = try decode(
            token: "package-app",
            artifacts: [["pkg": ["Sample.pkg"]]],
            rubySourcePath: "Casks/p/package-app.rb"
        )
        let nonDefaultTapFontPath = try decode(
            token: "font-sample",
            tap: "example/tap",
            artifacts: [["pkg": ["Sample.pkg"]]],
            rubySourcePath: "Casks/font/font-sample.rb"
        )
        let emptyFont = try decode(artifacts: [["font": [String]()]])
        let noArtifacts = try decode(artifacts: nil)

        precondition(font.isFontCask, "A cask with a font artifact must be recognized as a font")
        precondition(!app.isFontCask, "App artifacts must not classify a cask as a font")
        precondition(renamedFont.isFontCask, "Font option objects must not break cask decoding")
        precondition(
            renamedFont.artifacts?.first?.font == ["Source.ttf"],
            "String font paths must be retained while option objects are ignored"
        )
        precondition(packageFont.isFontCask, "Package-installed casks under Casks/font must be recognized as fonts")
        precondition(!regularPackage.isFontCask, "Other package casks must not be classified as fonts")
        precondition(!nonDefaultTapFontPath.isFontCask, "Non-default tap source paths must not classify fonts")
        precondition(!emptyFont.isFontCask, "An empty font artifact must not create an empty category entry")
        precondition(!noArtifacts.isFontCask, "Casks without artifacts must remain non-font casks")
        print("PASS: Homebrew font artifact classification")
    }

    private static func decode(
        token: String = "sample",
        tap: String = "homebrew/cask",
        artifacts: [[String: Any]]?,
        rubySourcePath: String? = nil
    ) throws -> CaskDTO {
        var object: [String: Any] = [
            "token": token,
            "full_token": tap == "homebrew/cask" ? token : "\(tap)/\(token)",
            "tap": tap,
            "name": ["Sample"],
            "homepage": "",
            "url": "https://example.test/sample.dmg",
            "deprecated": false,
            "disabled": false
        ]
        if let artifacts {
            object["artifacts"] = artifacts
        }
        if let rubySourcePath {
            object["ruby_source_path"] = rubySourcePath
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(CaskDTO.self, from: data)
    }
}
