//
//  String+LimitedToLines.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import Foundation

extension String {
    /// Returns a new string with the first `maxLines` lines of the original string,
    /// with an optional suffix added if lines were truncated
    /// - Parameters:
    ///   - maxLines: The maximum number of lines to include
    ///   - suffix: Optional text to append if lines were truncated (default: "...")
    /// - Returns: A new string with at most `maxLines` lines plus optional suffix
    func limitedToLines(_ maxLines: Int, suffix: String = "") -> String {
        guard maxLines > 0 else { return "" }

        let lines = self.components(separatedBy: .newlines)
        if lines.count <= maxLines {
            return self
        } else {
            let limitedLines = lines.prefix(maxLines)
            return limitedLines.joined(separator: "\n") + suffix
        }
    }
}
