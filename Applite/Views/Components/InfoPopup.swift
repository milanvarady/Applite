//
//  InfoPopup.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.11.
//

import SwiftUI

struct InfoPopup: View {
    let text: LocalizedStringKey
    let sfSymbol: String
    let color: Color

    @State var showPopover: Bool = false

    init(text: LocalizedStringKey, sfSymbol: String = "info.circle", color: Color = .primary) {
        self.text = text
        self.sfSymbol = sfSymbol
        self.color = color
    }

    var body: some View {
        Image(systemName: sfSymbol)
            .foregroundStyle(color)
            .onHover { hover in
                showPopover = hover
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover) {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: 400)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(16)
            }
    }
}

#Preview {
    InfoPopup(text: "")
}
