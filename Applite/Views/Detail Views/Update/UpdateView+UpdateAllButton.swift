//
//  UpdateView+UpdateAllButton.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import SwiftUI

extension UpdateView {
    var updateAllButton: some View {
        Button {
            isUpdatingAll = true
            
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                updateAllButtonRotation = 360.0
            }

            caskManager.updateAll(casks)
        } label: {
            HStack {
                Image(systemName: "arrow.2.circlepath")
                    .rotationEffect(.degrees(updateAllButtonRotation))
                
                Text("Update All")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.vertical)
        .disabled(isUpdatingAll)
    }
}
