//
//  String+NumberOfLines.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import Foundation

extension String {
    var numberOfLines: Int {
        self.components(separatedBy: .newlines).count - 1
    }
}
