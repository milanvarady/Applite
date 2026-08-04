//
//  Remark.swift
//  Applite
//
//  Created by Milán Várady on 2026.08.03.
//

import SwiftUI

/// A bold, coloured "**Title:** message" line used for notes/warnings inside Form sections.
/// Returns `Text` so it composes inline as a section row.
func remark(title: LocalizedStringKey, color: Color, message: LocalizedStringKey) -> Text {
    Text(title)
        .foregroundStyle(color)
        .fontWeight(.bold)
    +
    Text(": ")
        .foregroundStyle(color)
        .fontWeight(.bold)
    +
    Text(message)
}
