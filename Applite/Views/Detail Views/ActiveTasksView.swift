//
//  ActiveTasksView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 12..
//

import SwiftUI

struct ActiveTasksView: View {
    @EnvironmentObject var caskManager: CaskManager
    
    var body: some View {
        VStack {
            if caskManager.activeTasks.isEmpty {
                Text("No Active Tasks", comment: "No active tasks available message")
                    .font(.title)
            } else {
                AppGridView(casks: caskManager.activeTasks.map { $0.cask }, appRole: .update)
            }

            Spacer()
        }
        .navigationTitle("Active Tasks")
        .padding()
    }
}

#Preview {
    ActiveTasksView()
}
