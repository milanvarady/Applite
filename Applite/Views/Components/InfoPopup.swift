//
//  InfoPopup.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.11.
//

import SwiftUI

struct InfoPopup: View {
    let text: LocalizedStringKey

    @State var showPopover: Bool = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Image(systemName: "info.circle")
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
