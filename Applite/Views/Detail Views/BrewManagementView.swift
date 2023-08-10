//
//  BrewManagementView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 09..
//

import SwiftUI
import os

/// Displays info and provides tools to manage brew installation
struct BrewManagementView: View {
    @Binding var modifyingBrew: Bool
    
    @State var updateDone = false
    @State var reinstallDone = false
    
    // These will be loaded in asynchronously
    @State var homebrewVersion = "loading..."
    @State var numberOfCasks = "loading..."
    @State var isAppBrewInstalled = false
    
    @State var isPresentingReinstallConfirm = false
    
    @State var updateFailed = false
    @State var reinstallFailed = false
    
    let logger = Logger()
    
    var body: some View {
        VStack(alignment: .leading) {
            // Title
            Text("Manage Homebrew")
                .font(.system(size: 32, weight: .bold))
            
            Text("This application uses the [Homebrew](https://brew.sh/) (brew for short) package manager to download apps. Homebrew is a free and open source command line utility that can download useful developer tools as well as desktop applications.")
                .padding(.bottom)
            
            // Info section
            Text("Info")
                .font(.title)
            
            // Show Homebrew version and number of installed casks
            Group {
                Text("**Homebrew version:** \(NSLocalizedString(homebrewVersion, comment: "homebrewVersion"))")
                Text("**Number of apps installed:** \(NSLocalizedString(numberOfCasks, comment: "numberOfCasks installed"))")
            }
            
            // Actions section
            HStack {
                Text("Actions")
                    .font(.title)
                
                // Progress indicator
                SmallProgressView()
                    .opacity(modifyingBrew ? 1 : 0)
            }
            .padding(.top, 3)
            .padding(.bottom, -1)
            
            Group {
                HStack {
                    // Update brew button
                    Button {
                        modifyingBrew = true
                        
                        Task {
                            logger.info("Updating brew started")
                            
                            let result = await shell("\(BrewPaths.currentBrewExecutable) update")
                            
                            logger.info("Brew update output: \(result.output)")
                            
                            await MainActor.run {
                                if result.didFail {
                                    updateFailed = true
                                    logger.error("Brew update failed")
                                } else {
                                    logger.info("Brew update successful")
                                    updateDone = true
                                }
                                
                                modifyingBrew = false
                            }
                        }
                    } label: {
                        Label("Update Homebrew", systemImage: "arrow.uturn.down.circle")
                    }
                    .bigButton()
                    .disabled(modifyingBrew)
                    .padding(.trailing, 3)
                    .alert("Update failed", isPresented: $updateFailed, actions: {})
                    
                    // Checkmark if success
                    if updateDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                
                Text("**Warning:** All other app functions will be disabled during the update!")
                    .padding(.bottom)
                
                // Reinstall brew button
                HStack {
                    Button {
                        isPresentingReinstallConfirm = true
                    } label: {
                        Label(isAppBrewInstalled ? "Reinstall Homebrew" : "Install Separate Brew", systemImage: "wrench.and.screwdriver")
                    }
                    .bigButton(foregroundColor: .orange)
                    .disabled(modifyingBrew)
                    .confirmationDialog("Are you sure you wan't to \(isAppBrewInstalled ? "re" : "")install Homebrew?", isPresented: $isPresentingReinstallConfirm) {
                        Button("Yes") {
                            modifyingBrew = true
                            
                            Task {
                                do {
                                    try await BrewInstallation.installHomebrew()
                                } catch {
                                    reinstallFailed = true
                                }
                                
                                if !reinstallFailed {
                                    reinstallDone = true
                                }
                                
                                modifyingBrew = false
                            }
                        }
                        
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        if isAppBrewInstalled {
                            Text("All currently installed apps will be unlinked from \(Bundle.main.appName).")
                        } else {
                            Text("A new Homebrew installation will be installed into ~/Library/Application Support/\(Bundle.main.appName)")
                        }
                    }
                    .alert("Reinstall failed", isPresented: $reinstallFailed, actions: {
                        Button("OK", role: .cancel) { }
                    })
                    
                    if reinstallDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                
                Text("**Note:** This will reinstall \(Bundle.main.appName)'s Homebrew installation at `~/Library/Application Support/\(Bundle.main.appName)/homebrew`")
                    .padding(.bottom, 2)
                
                Text("**Warning:** After reinstalling, all currently installed apps will be unlinked from \(Bundle.main.appName). They won't be deleted, but you won't be able to update or uninstall them via \(Bundle.main.appName).")
            }
            
            Spacer()
        }
        .frame(maxWidth: 800)
        .padding(12)
        .task {
            // Check if brew is installed in application support
            isAppBrewInstalled = isBrewPathValid(path: BrewPaths.getBrewExectuablePath(for: .appPath))
            
            // Get version
            let versionOutput = await shell("\(BrewPaths.currentBrewExecutable) --version").output
            
            if let version = versionOutput.firstMatch(of: /Homebrew ([\d\.]+)/) {
                homebrewVersion = String(version.1)
            } else {
                homebrewVersion = "N/a"
                numberOfCasks = "N/a"
                return
            }
            
            // Get number of installed casks
            let countOutput = await shell("\(BrewPaths.currentBrewExecutable) list --cask | wc -w").output
            
            numberOfCasks = countOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

struct BrewManagementView_Previews: PreviewProvider {
    static var previews: some View {
        BrewManagementView(modifyingBrew: .constant(false))
    }
}
