//
//  UpdateView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI

/// Update section
struct UpdateView: View {
    var casks: [CaskViewModel]

    @Environment(CaskManager.self) var caskManager

    @State var searchText = ""
    @State var isUpdatingAll = false
    @State var updateAllButtonRotation = 0.0

    @State var showingGreedyUpdateConfirm = false
    @State var loadAlert = AlertManager()

    /// Filtered casks based on local search text
    var filteredCasks: [CaskViewModel] {
        if searchText.isEmpty {
            return casks
        }
        let query = searchText.lowercased()
        return casks.filter {
            $0.name.lowercased().contains(query) || $0.token.lowercased().contains(query)
        }
    }

    var updateAllButton: some View {
        Button {
            isUpdatingAll = true

            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                updateAllButtonRotation = 360.0
            }

            caskManager.updateAll(caskManager.outdatedViewModels)
        } label: {
            HStack {
                Image(systemName: "arrow.2.circlepath")
                    .rotationEffect(.degrees(updateAllButtonRotation))

                Text("Update All", comment: "Update all button title")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.vertical)
        .disabled(isUpdatingAll)
    }

    var body: some View {
        VStack {
            // App grid
            AppGridView(casks: filteredCasks, appRole: .update)
                .overlay(alignment: .bottom) {
                    if filteredCasks.count > 1 {
                        updateAllButton
                            .shadow(radius: 8)
                            .padding(.vertical)
                    }
                }
        }
        .overlay {
            if casks.isEmpty {
                ContentUnavailableView(
                    "No Updates Available",
                    systemImage: "checkmark.circle",
                    description: Text("All your apps are up to date.", comment: "Update view no updates available description")
                )
            } else if filteredCasks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Update")
        .searchable(text: $searchText, placement: .toolbar)
        .toolbar {
            ToolbarItems(loadAlert: loadAlert)
        }
        .alertManager(loadAlert)
        .onChange(of: caskManager.outdatedViewModels.isEmpty) { _, becameEmpty in
            if becameEmpty {
                isUpdatingAll = false
                updateAllButtonRotation = 0
            }
        }
    }
}

#Preview {
    UpdateView(casks: Array(repeating: .dummy, count: 8))
        .frame(width: 500, height: 400)
}
