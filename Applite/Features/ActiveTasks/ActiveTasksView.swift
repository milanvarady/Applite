//
//  ActiveTasksView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 12..
//

import SwiftUI

struct ActiveTasksView: View {
    @Environment(CaskManager.self) var caskManager

    @State private var showingStopConfirm = false

    var body: some View {
        VStack {
            if let batch = caskManager.batchProgress {
                HStack {
                    Label(
                        "\(batch.label) \(batch.completed) of \(batch.total)…",
                        systemImage: "square.stack.3d.down.forward"
                    )
                    .font(.headline)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button(role: .destructive) {
                        showingStopConfirm = true
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .confirmationDialog(
                        "Stop the bulk operation?",
                        isPresented: $showingStopConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Stop \(batch.total - batch.completed) remaining", role: .destructive) {
                            caskManager.cancelBatch()
                        }
                        Button("Continue", role: .cancel) { }
                    } message: {
                        Text("Apps already finished stay installed; the rest are cancelled.", comment: "Batch stop confirmation message")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }

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
