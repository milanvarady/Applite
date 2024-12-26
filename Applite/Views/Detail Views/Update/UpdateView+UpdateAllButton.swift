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
            
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for cask in casks {
                        group.addTask {
                            await cask.update(caskData: caskData)
                        }
                    }
                }
                
                await MainActor.run {
                    withAnimation(.linear(duration: 0.2)) {
                        updateAllButtonRotation = 0.0
                    }
                }
                
                updateAllFinished = true
            }
        } label: {
            HStack {
                Image(systemName: updateAllFinished ? "checkmark" : "arrow.2.circlepath")
                    .rotationEffect(.degrees(updateAllButtonRotation))
                
                Text("Update All")
            }
        }
        .bigButton(backgroundColor: .accentColor)
        .padding(.vertical)
        .disabled(isUpdatingAll)
    }
}
