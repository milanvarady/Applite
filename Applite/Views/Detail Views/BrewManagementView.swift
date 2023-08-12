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
    
    static let logger = Logger()
    
    var body: some View {
        VStack(alignment: .leading) {
            // Title
            Text("Manage Homebrew")
                .font(.system(size: 32, weight: .bold))
            
            Text("This application uses the [Homebrew](https://brew.sh/) (brew for short) package manager to download apps. Homebrew is a free and open source command line utility that can download useful developer tools as well as desktop applications.")
                .padding(.bottom)
            
            InfoView()
            
            Divider()
            
            ActionsView(modifyingBrew: $modifyingBrew)
            
            Divider()
            
            ExportView()
            
            Spacer()
        }
        .frame(maxWidth: 800)
        .padding(12)
    }
    
    struct InfoView: View {
        @State var homebrewVersion = "loading..."
        @State var numberOfCasks = "loading..."
        
        var body: some View {
            // Info section
            Text("Info")
                .font(.title)
            
            // Show Homebrew version and number of installed casks
            Group {
                Text("**Homebrew version:** \(NSLocalizedString(homebrewVersion, comment: "homebrewVersion"))")
                Text("**Number of apps installed:** \(NSLocalizedString(numberOfCasks, comment: "numberOfCasks installed"))")
            }
            .task {
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
    
    struct ActionsView: View {
        @Binding var modifyingBrew: Bool
        
        @State var updateDone = false
        @State var reinstallDone = false
        
        @State var isAppBrewInstalled = false
        
        @State var isPresentingReinstallConfirm = false
        
        @State var updateFailed = false
        @State var reinstallFailed = false
        
        var body: some View {
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
            .task {
                // Check if brew is installed in application support
                isAppBrewInstalled = isBrewPathValid(path: BrewPaths.getBrewExectuablePath(for: .appPath))
            }
        }
    }
    
    struct ExportView: View {
        @EnvironmentObject var caskData: CaskData
        
        @State private var fileExporterPresented = false
        @State private var fileImporterPresented = false
        
        @State var showingExportError = false
        @State var showingImportError = false
        
        var body: some View {
            VStack(alignment: .leading) {
                Text("Export/Import apps")
                    .font(.title)
                
                Text("Export a file containing all currently installed applications. This can be imported to another device.")
            
            
                Button("Export apps to file") {
                    fileExporterPresented = true
                }
                .fileImporter(
                    isPresented: $fileExporterPresented,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let url):
                        var result = ""
                        
                        do {
                            result = try exportCasks(url: url[0])
                        } catch {
                            logger.error("Failed to export casks, output: \(result)")
                            showingExportError = true
                        }
                    case .failure(let error):
                        logger.error("\(error.localizedDescription)")
                    }
                }
                .alert("Export failed", isPresented: $showingExportError, actions: {})
                
                Button("Import cask file") {
                    fileImporterPresented = true
                }
                .fileImporter(
                    isPresented: $fileImporterPresented,
                    allowedContentTypes: [.plainText],
                    allowsMultipleSelection: false
                ) { result in
                    var caskText = ""
                    
                    switch result {
                    case .success(let url):
                        do {
                            caskText = try readCaskFile(url: url[0])
                            
                            installImported(caskText: caskText)
                        } catch {
                            logger.error("Failed to import cask")
                        }
                    case .failure(let error):
                        logger.error("\(error.localizedDescription)")
                        showingImportError = true
                    }
                }
                .alert("Import failed", isPresented: $showingImportError, actions: {})
            }
        }
        
        func installImported(caskText: String) {
            Task {
                await installImportedCasks(caskText: caskText, caskData: caskData)
            }
        }
    }
}

struct BrewManagementView_Previews: PreviewProvider {
    static var previews: some View {
        BrewManagementView(modifyingBrew: .constant(false))
    }
}
