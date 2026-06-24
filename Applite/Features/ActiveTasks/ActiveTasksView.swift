//
//  ActiveTasksView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 12..
//

import SwiftUI

struct ActiveTasksView: View {
    @Environment(CaskManager.self) var caskManager

    var body: some View {
        VStack {
            AppGridView(casks: caskManager.activeTasks.map(\.viewModel), appRole: .update)
            Spacer()
        }
        .overlay {
            if caskManager.activeTasks.isEmpty {
                ContentUnavailableView("No Active Tasks", systemImage: "gear.badge.checkmark")
            }
        }
        .navigationTitle("Active Tasks")
        .padding()
    }
}

#Preview {
    ActiveTasksView()
}
