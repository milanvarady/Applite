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
    // Extra vertical padding because popover is kind of bugged when it displays long text
    let extraTopPadding: CGFloat
    let extraBottomPadding: CGFloat

    @State var showPopover: Bool = false

    init(text: LocalizedStringKey, sfSymbol: String = "info.circle", color: Color = .primary, extraPaddingForLines: Int? = nil) {
        self.text = text
        self.sfSymbol = sfSymbol
        self.color = color

        if let extraPaddingForLines {
            self.extraTopPadding = CGFloat(extraPaddingForLines * 3)
            self.extraBottomPadding = CGFloat(extraPaddingForLines * 1)
        } else {
            self.extraTopPadding = 0
            self.extraBottomPadding = 0
        }
    }

    var body: some View {
        // A real Button (not a bare hover-only Image) so keyboard and VoiceOver users can open the
        // popover too; hover still opens it for mouse users. The info text is exposed as the
        // accessibility label so assistive tech announces it without having to open the popover (F2).
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: sfSymbol)
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            showPopover = hover
        }
        .popover(isPresented: $showPopover) {
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: true, vertical: true)
                .padding(16)
                .padding(.top, extraTopPadding)
                .padding(.bottom, extraBottomPadding)
        }
        .accessibilityLabel(Text(text))
    }
}

#Preview {
    InfoPopup(text: "")
}
