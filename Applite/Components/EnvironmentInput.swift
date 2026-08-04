//
//  EnvironmentInput.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import SwiftUI

/// Labelled text field for a single environment variable (used by the Mirror settings).
struct EnvironmentInput: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
        }
    }
}
