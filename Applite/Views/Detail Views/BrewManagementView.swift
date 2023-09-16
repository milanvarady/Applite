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
        ScrollView {
            VStack {
                VStack(alignment: .leading) {
                    // Title
                    Text("Manage Homebrew")
                        .font(.system(size: 32, weight: .bold))
                    
                    Text("This application uses the [Homebrew](https://brew.sh/) (brew for short) package manager to download apps. Homebrew is a free and open source command line utility that can download useful developer tools as well as desktop applications.")
                        .padding(.bottom)
                    
                    section(title: "Info") {
                        InfoView()
                    }
                    .padding(.bottom)
                    
                    section(title: "Actions") {
                        ActionsView(modifyingBrew: $modifyingBrew)
                    }
                    .padding(.bottom)
                    
                    section(title: "Import/Export apps") {
                        ExportView()
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: 800)
                .padding(12)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    func section<Content: View>(title: LocalizedStringKey, @ViewBuilder content: ()->Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title)
            
            VStack(alignment: .leading) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quinary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    private enum NoticeType: String {
        case note = "Note"
        case warning = "Warning"
    }
    
    static private func notice(type: NoticeType, _ body: LocalizedStringKey) -> some View {
        Group {
            Text(LocalizedStringKey(type.rawValue))
                .bold()
                .foregroundColor(type == .note ? .blue : .orange)
            +
            Text(": ")
                .bold()
                .foregroundColor(type == .note ? .blue : .orange)
            +
            Text(body)
        }
    }
    
    struct InfoView: View {
        // These will be loaded in asynchronously
        @State var homebrewVersion = "loading..."
        @State var numberOfCasks = "loading..."
        
        var body: some View {
            // Show Homebrew version and number of installed casks
            VStack(alignment: .leading) {
                Group {
                    Text("Homebrew version: ") +
                    Text(homebrewVersion).fontWeight(.light)
                }
                
                Group {
                    Text("Number of apps installed: ") +
                    Text(numberOfCasks).fontWeight(.light)
                }
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
            HStack {
                // Update brew button
                updateButton
                
                // Checkmark if success
                if updateDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            
            notice(type: .warning, "All other app functions will be disabled during the update!")
            
            Divider()
                .padding(.vertical, 8)
            
            // Reinstall brew button
            HStack {
                reinstallButton
                    .task {
                        // Check if brew is installed in application support
                        isAppBrewInstalled = isBrewPathValid(path: BrewPaths.getBrewExectuablePath(for: .appPath))
                    }
                
                if reinstallDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            
            notice(type: .note, "This will (re)install \(Bundle.main.appName)'s Homebrew installation at: ~/Library/Application Support/\(Bundle.main.appName)/homebrew")
                .padding(.bottom, 3)
            
            notice(type: .warning, "After reinstalling, all currently installed apps will be unlinked from \(Bundle.main.appName). They won't be deleted, but you won't be able to update or uninstall them via \(Bundle.main.appName).")
            
            // Progress indicator
            if modifyingBrew {
                HStack {
                    Text("In progress...")
                        .bold()
                    SmallProgressView()
                }
            }
        }
        
        private var updateButton: some View {
            Button {
                withAnimation {
                    modifyingBrew = true
                }
                
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
                        
                        withAnimation {
                            modifyingBrew = false
                        }
                    }
                }
            } label: {
                Label("Update Homebrew", systemImage: "arrow.uturn.down.circle")
            }
            .disabled(modifyingBrew)
            .padding(.trailing, 3)
            .alert("Update failed", isPresented: $updateFailed, actions: {})
        }
        
        private var reinstallButton: some View {
            Button {
                isPresentingReinstallConfirm = true
            } label: {
                Label(isAppBrewInstalled ? "Reinstall Homebrew" : "Install Separate Brew", systemImage: "wrench.and.screwdriver")
            }
            .disabled(modifyingBrew)
            .confirmationDialog("Are you sure you wan't to \(isAppBrewInstalled ? "re" : "")install Homebrew?", isPresented: $isPresentingReinstallConfirm) {
                Button("Yes") {
                    withAnimation {
                        modifyingBrew = true
                    }
                    
                    Task {
                        do {
                            try await DependencyManager.installHomebrew()
                        } catch {
                            reinstallFailed = true
                        }
                        
                        if !reinstallFailed {
                            reinstallDone = true
                        }
                        
                        withAnimation {
                            modifyingBrew = false
                        }
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
        }
    }
    
    struct ExportView: View {
        @EnvironmentObject var caskData: CaskData
        
        @State private var fileExporterPresented = false
        @State private var fileImporterPresented = false
        
        @State var showingExportError = false
        @State var showingImportError = false
        
        @State var selectedExportFileType: CaskExportType = .txtFile
        
        var body: some View {
            VStack(alignment: .leading) {
                Text("Export a file containing all currently installed applications. This can be imported to another device.")
                
                Divider()
                    .padding(.vertical, 8)
            
                Button {
                    fileExporterPresented = true
                } label: {
                    Label("Export apps to file", systemImage: "square.and.arrow.up")
                }
                .fileImporter(
                    isPresented: $fileExporterPresented,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let url):
                        do {
                            try exportCasks(url: url[0], exportType: selectedExportFileType)
                        } catch {
                            logger.error("Failed to export casks")
                            showingExportError = true
                        }
                    case .failure(let error):
                        logger.error("\(error.localizedDescription)")
                    }
                }
                .alert("Export failed", isPresented: $showingExportError, actions: {})
                
                Picker("Export file type", selection: $selectedExportFileType) {
                    ForEach(CaskExportType.allCases) { type in
                        Text(LocalizedStringKey(type.rawValue))
                    }
                }
                .frame(maxWidth: 300)
                
                Divider()
                    .padding(.vertical, 6)
                
                Button {
                    fileImporterPresented = true
                } label: {
                    Label("Import apps", systemImage: "square.and.arrow.down")
                }
                .fileImporter(
                    isPresented: $fileImporterPresented,
                    allowedContentTypes: [.plainText, .data],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let url):
                        do {
                            let casks = try readCaskFile(url: url[0])
                            
                            installImported(casks: casks)
                        } catch {
                            logger.error("Failed to import cask. Reason: \(error.localizedDescription)")
                            showingImportError = true
                        }
                    case .failure(let error):
                        logger.error("\(error.localizedDescription)")
                        showingImportError = true
                    }
                }
                .alert("Import failed", isPresented: $showingImportError, actions: {})
                
                notice(type: .note, "When importing a Brewfile only casks will be installed. Other items like formulae and taps will be skipped.")
            }
        }
        
        func installImported(casks: [String]) {
            Task {
                await installImportedCasks(casks: casks, caskData: caskData)
            }
        }
    }
}

struct BrewManagementView_Previews: PreviewProvider {
    static var previews: some View {
        BrewManagementView(modifyingBrew: .constant(false))
    }
}
