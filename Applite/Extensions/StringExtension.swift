//
//  StringExtension.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation

extension String {
    func cleanANSIEscapeCodes() -> String {
        replacingOccurrences(of: "\\\u{001B}\\[[0-9;]*[a-zA-Z]", with: "", options: .regularExpression)
    }
}
