//
//  UpdateButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

struct UpdateButton: View {
    var cask: CaskViewModel
    @Environment(CaskManager.self) var caskManager

    var body: some View {
        Button {
            caskManager.update(cask)
        } label: {
            Image(systemName: "arrow.uturn.down.circle.fill")
                .font(.system(size: 20))
        }
        .foregroundColor(.blue)
    }
}
