//
//  PackageManagerSettingsView.swift
//  Applite
//
//  Created by Subham mahesh
//  licensed under the MIT
//

import SwiftUI

struct PackageManagerSettingsView: View {
    @ObservedObject var updater: PackageUpdater
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 24) {
                // Auto Update Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Automatic Updates")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable automatic updates", isOn: $updater.isAutoUpdateEnabled)
                        
                        if updater.isAutoUpdateEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Update Frequency")
                                    .font(.headline)
                                
                                Picker("Frequency", selection: $updater.autoUpdateFrequency) {
                                    ForEach(UpdateFrequency.allCases) { frequency in
                                        Text(frequency.displayName)
                                            .tag(frequency)
                                    }
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                
                                Text("Applite will automatically check for and install package updates.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Update History
                VStack(alignment: .leading, spacing: 16) {
                    Text("Update History")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if let lastCheck = updater.lastUpdateCheck {
                            Text("Last checked: \(lastCheck, style: .relative) ago")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never checked for updates")
                                .foregroundColor(.secondary)
                        }
                        
                        if !updater.updateResults.isEmpty {
                            RecentUpdatesView(results: updater.updateResults)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Notifications
                VStack(alignment: .leading, spacing: 16) {
                    Text("Notifications")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Applite will send notifications about package updates and installation results.")
                            .foregroundColor(.secondary)
                        
                        Button("Open System Preferences") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
            }
            .padding()
            .navigationTitle("Package Manager Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}

struct RecentUpdatesView: View {
    let results: [UpdateResult]
    
    private var recentResults: [UpdateResult] {
        Array(results.suffix(5))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Updates")
                .font(.headline)
            
            if recentResults.isEmpty {
                Text("No recent updates")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(spacing: 6) {
                    ForEach(recentResults) { result in
                        UpdateResultRow(result: result)
                    }
                }
            }
        }
    }
}

struct UpdateResultRow: View {
    let result: UpdateResult
    
    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.success ? .green : .red)
                .font(.caption)
            
            // Package info
            VStack(alignment: .leading, spacing: 2) {
                Text(result.package.name)
                    .font(.caption)
                    .fontWeight(.medium)
                
                HStack(spacing: 4) {
                    Text(result.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(result.formattedDuration)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let error = result.error {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Manager badge
            Text(result.package.manager.displayName)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    let coordinator = PackageManagerCoordinator()
    let updater = PackageUpdater(coordinator: coordinator)
    
    // Add some sample update results
    updater.updateResults = [
        UpdateResult(
            package: GenericPackage(
                id: "git",
                name: "Git",
                version: "2.42.0",
                manager: .homebrew,
                isInstalled: true
            ),
            success: true,
            duration: 15.3,
            error: nil
        ),
        UpdateResult(
            package: GenericPackage(
                id: "node",
                name: "Node.js",
                version: "18.17.0",
                manager: .homebrew,
                isInstalled: true
            ),
            success: false,
            duration: 5.2,
            error: "Permission denied"
        )
    ]
    
    return PackageManagerSettingsView(updater: updater)
}