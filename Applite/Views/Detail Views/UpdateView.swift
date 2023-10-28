//
//  UpdateView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 14..
//

import SwiftUI
import Fuse

/// Update section
struct UpdateView: View {
    @EnvironmentObject var caskData: CaskData
    
    @State var searchText = ""
    @State var refreshing = false
    @State var isUpdatingAll = false
    @State var updateAllFinished = false
    @State var updateAllButtonRotation = 0.0
    
    @State var showingGreedyUpdateConfirm = false
    
    // Filter outdated casks
    var casks: [Cask] {
        var filteredCasks = caskData.casks.filter { $0.isOutdated }
        
        if !$searchText.wrappedValue.isEmpty {
            filteredCasks = filteredCasks.filter {
                (fuseSearch.search(searchText, in: $0.name)?.score ?? 1) < 0.4
            }
        }
        
        return filteredCasks
    }
    
    let fuseSearch = Fuse()

    var body: some View {
        ScrollView {
            // App grid
            AppGridView(casks: Array(caskData.outdatedCasks), appRole: .update)
                .padding()
            
            if casks.count > 1 {
                // Update all button
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
            
            // No updates availabe
            if casks.count == 0 {
                VStack {
                    Spacer()
                    
                    Text("No Updates Available")
                        .font(.title)
                    
                    Spacer()
                }
            }
        }
        .searchable(text: $searchText)
        .toolbar {
            Button {
                showingGreedyUpdateConfirm = true
            } label: {
                Label("Show All Updates", systemImage: "eye")
            }
            .labelStyle(.titleAndIcon)
            .alert("Notice", isPresented: $showingGreedyUpdateConfirm) {
                Button("Show All") {
                    Task {
                        await caskData.refreshOutdatedApps(greedy: true)
                    }
                }
                
                Button("Cancel", role: .cancel) { }
            } message: {
                VStack {
                    Text("This will show updates from applications that have auto-update turned off, i.e., applications that are taking care of their own updates.")
                }
            }
            
            // Refresh outdated casks
            if refreshing {
                SmallProgressView()
            }
            else {
                Button {
                    Task.init {
                        refreshing = true
                        await caskData.refreshOutdatedApps()
                        refreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}

struct UpdateView_Previews: PreviewProvider {
    static var previews: some View {
        UpdateView()
            .environmentObject(CaskData())
            .frame(width: 500, height: 400)
    }
}
