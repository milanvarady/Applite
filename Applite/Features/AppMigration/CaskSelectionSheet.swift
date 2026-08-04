//
//  CaskSelectionSheet.swift
//  Applite
//
//  Created by Milán Várady on 2026.08.02.
//

import SwiftUI

/// A reusable checklist sheet for picking which casks to export or import.
///
/// The caller owns the data and presents it via `.sheet`; the sheet seeds every row as selected,
/// offers a Select-All/Deselect-All toggle and a live count, and returns the chosen view models
/// through `onConfirm` before dismissing itself.
struct CaskSelectionSheet: View {
    let title: LocalizedStringKey
    let confirmLabel: LocalizedStringKey
    /// Optional caption shown above the list (e.g. "N apps could not be found" on import).
    let note: LocalizedStringKey?
    /// Caller passes these pre-sorted.
    let casks: [CaskViewModel]
    let onConfirm: ([CaskViewModel]) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Keyed by `cask.id` (== `fullToken`), seeded with all ids so every row starts checked.
    @State private var selectedTokens: Set<String>

    init(
        title: LocalizedStringKey,
        confirmLabel: LocalizedStringKey,
        note: LocalizedStringKey? = nil,
        casks: [CaskViewModel],
        onConfirm: @escaping ([CaskViewModel]) -> Void
    ) {
        self.title = title
        self.confirmLabel = confirmLabel
        self.note = note
        self.casks = casks
        self.onConfirm = onConfirm
        _selectedTokens = State(initialValue: Set(casks.map(\.id)))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            List(casks) { cask in
                row(for: cask)
            }
            .listStyle(.inset)

            Divider()

            footer
        }
        .frame(width: 460, height: 520)
    }

    // MARK: - Private views (coupled to @State → kept in-file per project convention)

    private var allSelected: Bool {
        !casks.isEmpty && selectedTokens.count == casks.count
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                Text("\(selectedTokens.count) selected", comment: "Cask selection sheet count")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Toggle(isOn: selectAllBinding) {
                // Two calls, not `Text(cond ? "a" : "b", comment:)` — a ternary inside the literal
                // slot loses the comment during extraction, so both keys reach translators bare.
                if allSelected {
                    Text("Deselect All", comment: "Cask selection sheet: clear every checkbox")
                } else {
                    Text("Select All", comment: "Cask selection sheet: tick every checkbox")
                }
            }
            .toggleStyle(.checkbox)

            if let note {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func row(for cask: CaskViewModel) -> some View {
        Toggle(isOn: binding(for: cask)) {
            HStack(spacing: 8) {
                if let iconURL = cask.iconURL {
                    AppIconView(
                        iconURL: iconURL,
                        name: cask.name,
                        cacheKey: cask.iconCacheKey,
                        size: 24
                    )
                }

                Text(cask.name)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                onConfirm(casks.filter { selectedTokens.contains($0.id) })
                dismiss()
            } label: {
                Text(confirmLabel)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedTokens.isEmpty)
        }
        .padding()
    }

    // MARK: - Bindings

    private var selectAllBinding: Binding<Bool> {
        Binding(
            get: { allSelected },
            set: { selectAll in
                selectedTokens = selectAll ? Set(casks.map(\.id)) : []
            }
        )
    }

    private func binding(for cask: CaskViewModel) -> Binding<Bool> {
        Binding(
            get: { selectedTokens.contains(cask.id) },
            set: { isOn in
                if isOn {
                    selectedTokens.insert(cask.id)
                } else {
                    selectedTokens.remove(cask.id)
                }
            }
        )
    }
}

#Preview {
    CaskSelectionSheet(
        title: "Select Apps to Export",
        confirmLabel: "Export",
        casks: [.dummy]
    ) { _ in }
}
