//
//  SetupView.swift
//  Applite
//
//  Created by Milán Várady on 2023. 01. 03..
//

import SwiftUI
import AppKit

/// This view is shown when first launching the app. It welcomes the user and installs dependencies (Homebrew, Xcode Command Line Tools).
struct SetupView: View {
    enum Pages {
        case welcome,
             brewTypeSelection,
             brewPathSelection,
             brewInstall,
             allSet
    }
    
    @State var page: Pages = .welcome
    
    @State var isBrewPathValid = false
    @State var isBrewInstallDone = false

    enum PushDirection {
        case forward, backward
    }

    @State var pushDirection: PushDirection = .forward

    var body: some View {
        VStack {
            switch page {
            case .welcome:
                Welcome()
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))
                
                PageControlButtons(
                    page: $page,
                    pushDirection: $pushDirection,
                    canContinue: true,
                    pageAfter: .brewTypeSelection,
                    pageBefore: nil
                )

            case .brewTypeSelection:
                BrewTypeSelection(page: $page)
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))

            case .brewPathSelection:
                BrewPathSelection(isBrewPathValid: $isBrewPathValid)
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))
                
                PageControlButtons(
                    page: $page,
                    pushDirection: $pushDirection,
                    canContinue: isBrewPathValid,
                    pageAfter: .allSet,
                    pageBefore: .brewTypeSelection
                )

            case .brewInstall:
                BrewInstall(isDone: $isBrewInstallDone)
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))
                
                PageControlButtons(
                    page: $page,
                    pushDirection: $pushDirection,
                    canContinue: isBrewInstallDone,
                    pageAfter: .allSet,
                    pageBefore: nil
                )

            case .allSet:
                AllSet()
                    .transition(.push(from: pushDirection == .forward ? .trailing : .leading))
            }
        }
    }
    
    /// Adds a Back and Continue button to the bottom of the page
    ///
    /// - Parameters:
    ///   - page: Page binding so it can change the current page
    ///   - canContinue: Controls whether it can go to the next page yet or not
    ///   - pageAfter: Page when clicking on Continue
    ///   - pageBefore: Page when clicking on Back
    ///
    /// - Returns: ``View``
    private struct PageControlButtons: View {
        @Binding var page: Pages
        @Binding var pushDirection: PushDirection
        let canContinue: Bool
        let pageAfter: Pages
        let pageBefore: Pages?
        
        var body: some View {
            Spacer()
            
            Divider()
            
            HStack {
                Spacer()
                
                if let pageBefore {
                    Button("Back") {
                        pushDirection = .backward
                        withAnimation {
                            page = pageBefore
                        }
                    }
                    .bigButton(backgroundColor: Color(red: 0.7, green: 0.7, blue: 0.7))
                }
                
                Button("Continue") {
                    pushDirection = .forward
                    withAnimation {
                        page = pageAfter
                    }
                }
                .disabled(!canContinue)
                .bigButton(backgroundColor: canContinue ? .accentColor : .gray)
            }
            .padding(.trailing)
            .padding(.bottom, 8)
        }
    }
    
    /// Welcome page
    private struct Welcome: View {
        var body: some View {
            VStack {
                Text("Welcome to \(Bundle.main.appName)")
                    .font(.system(size: 36, weight: .bold))
                    .padding(.top, 50)
                    .padding(.bottom, 25)
                
                VStack(alignment: .leading, spacing: 16) {
                    Feature(sfSymbol: "square.and.arrow.down.on.square",
                            title: "Download apps with ease",
                            description: "Download third party applications with a single click. No more \"Drag to Applications folder\".")
                    
                    Feature(sfSymbol: "cursorarrow.and.square.on.square.dashed",
                            title: "Manage applications",
                            description: "Update and uninstall your applications. No more leftover files from deleted applications.")
                    
                    Feature(sfSymbol: "sparkle.magnifyingglass",
                            title: "Discover",
                            description: "Browse through a handpicked list of awesome apps.")
                }
            }
            .frame(maxWidth: 500)
        }
        
        /// A feature of the app to be displayed in the Welcome view
        private struct Feature: View {
            let sfSymbol: String
            let title: LocalizedStringKey
            let description: LocalizedStringKey
            
            var body: some View {
                HStack {
                    Image(systemName: sfSymbol)
                        .font(.system(size: 22))
                        .padding(.trailing, 5)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading) {
                        Text(title, comment: "Title")
                            .font(.system(size: 14, weight: .bold))
                        
                        Text(description, comment: "Description")
                            .font(.system(size: 12, weight: .light))
                    }
                }
            }
        }
    }
    
    /// Brew installation method selection page. User can choose to use their brew if they have or create a new installation.
    private struct BrewTypeSelection: View {
        @Binding var page: Pages
        
        var body: some View {
            VStack {
                Spacer()
                
                Text("Do you already have Homebrew installed?")
                    .font(.system(size: 26, weight: .bold))
                    .padding(.top, 10)
                    .padding(.bottom)
                
                HStack {
                    Button("Yes") {
                        page = .brewPathSelection
                        BrewPaths.selectedBrewOption = .defaultAppleSilicon
                    }
                    .bigButton()
                    
                    Button("No (I don't know what it is)") {
                        page = .brewInstall
                        BrewPaths.selectedBrewOption = .appPath
                    }
                    .bigButton(backgroundColor: .accentColor)
                }
                
                Spacer()
                
                Text("This application uses the free and open source [Homebrew](https://brew.sh/) package manager to download and manage applications. If you already have it installed on your system, you can use it right away. If you don't have brew installed or don't know what it is, select **No**. This will create a new brew installation just for \(Bundle.main.appName).")
                    .padding(.bottom, 22)
            }
            .frame(maxWidth: 540)
            .padding()
        }
    }
    
    /// User can provide installed brew path here
    private struct BrewPathSelection: View {
        @Binding var isBrewPathValid: Bool
        
        var body: some View {
            VStack(alignment: .center) {
                Spacer()
                
                Text("Provide Brew Executable Path")
                    .font(.system(size: 26, weight: .bold))
                    .padding(.bottom, 30)

                
                VStack(alignment: .leading) {
                    BrewPathSelectorView(isSelectedPathValid: $isBrewPathValid)
                    
                    Text("Selected brew path is invalid!")
                        .foregroundColor(.red)
                        .opacity(isBrewPathValid ? 0 : 1)
                        .padding(.bottom)
                    
                    Text("Appdir (optional)")
                        .font(.system(size: 16, weight: .bold))
                    
                    AppdirSelectorView()
                }
                .frame(width: 500)
                
                Spacer()
            }
            .frame(maxWidth: 540)
            .padding()
        }
    }
    
    /// Brew installation page
    private struct BrewInstall: View {
        /// This is needed so the parent view knows it can continue to the next page
        @Binding var isDone: Bool
        
        @State var failed = false
        
        // Alerts
        @State var showingAlert = false
        @State var showingCommandLineToolsAlert = false
        @State var showingPinentryAlert = false
        
        @StateObject var installationProgress = BrewInstallationProgress()
        
        enum SetupInstallError: Error {
            case homebrew
            case pinentry
        }
        
        var body: some View {
            VStack {
                Text("Installing dependencies")
                    .font(.system(size: 32, weight: .bold))
                    .padding(.vertical)
                
                // Xcode Command Line Tools
                VStack(alignment: .leading, spacing: 20) {
                    // Xcode Command Line Tools
                    dependencyView(title: "Xcode Command Line Tools",
                                   description: "You will be prompted to install the Xcode Command Line Tools, please click \"Install\" as it is required for this application to work. It will take a few minutes, you can see the progress on the installation window.",
                                   progressOrder: .waitingForXcodeCommandLineTools)
                    
                    
                    // Homebrew
                    dependencyView(title: "Homebrew",
                                   description: "[Homebrew](https://brew.sh) is a free and open source package manager tool that makes installing third party applications really easy. \(Bundle.main.appName) uses Homebrew under the hood to download and manage applications.",
                                   progressOrder: .fetchingHomebrew)
                    
                    // Pinentry
                    dependencyView(title: "Pinentry",
                                   description: "Pinentry is used to securely prompt for the admin password when it is required during the installation of an application.",
                                   progressOrder: .installingPinentry)
                    
                    // Retry button
                    if failed {
                        Button {
                            Task {
                                await installDependencies()
                            }
                        } label: {
                            Label("Retry Install", systemImage: "arrow.clockwise.circle")
                        }
                        .bigButton(backgroundColor: .accentColor)
                    }
                }
                .frame(width: 440)
                .task {
                    // Start installation when view loads
                    await installDependencies()
                }
                .onAppear() {
                    if !isCommandLineToolsInstalled() {
                        showingCommandLineToolsAlert = true
                    }
                }
                .alert(isPresented: $showingCommandLineToolsAlert) {
                    Alert(title: Text("Xcode Command Line Tools"),
                          message: Text("You will be prompted to install Xcode Command Line Tools. Please select \"Install\" as it is required for this application to work."))
                }
                .alert("Installation failed", isPresented: $showingAlert, actions: {
                    Button("Troubleshooting") {
                        if let url = URL(string: "https://aerolite.dev/applite/troubleshooting.html") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    
                    Button("Retry") {
                        
                    }
                    
                    Button("Quit", role: .destructive) { NSApplication.shared.terminate(self) }
                }, message: {
                    Text("Retry the installation or visit the troubleshooting page.")
                })
                .alert("Failed to install pinentry", isPresented: $showingPinentryAlert, actions: {
                    Button("OK") { }
                    
                    Button("Troubleshooting") {
                        if let url = URL(string: "https://aerolite.dev/applite/troubleshooting.html") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }, message: {
                    Text("You can safely continue, but you won't be able to install apps with .pkg installers.")
                })
            }
        }
        
        private func dependencyView(title: LocalizedStringKey, description: LocalizedStringKey, progressOrder: InstallPhase) -> some View {
            VStack(alignment: .leading) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .padding(.trailing, 4)
                    
                    if !failed {
                        if installationProgress.phase.rawValue > progressOrder.rawValue {
                            installedBadge
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    } else {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.red)
                    }
                }
                .frame(height: 30)
             
                Text(description)
            }
        }
        
        private func installDependencies() async {
            // Reset progress
            failed = false
            installationProgress.phase = .waitingForXcodeCommandLineTools
            
            do {
                try await DependencyManager.install(progressObject: installationProgress)
            } catch {
                failed = true
            }
            
            if !failed {
                self.isDone = true
            }
        }
        
        /// A little bagde that says "Installed"
        private var installedBadge: some View {
            HStack {
                Image(systemName: "checkmark")
                Text("Installed")
            }
            .padding(3)
            .foregroundColor(.white)
            .background(.green)
            .cornerRadius(4)
        }
    }
    
    /// Page shown when setup is complete
    private struct AllSet: View {
        @AppStorage(Preferences.setupComplete.rawValue) var setupComplete = false
        
        var body: some View {
            Text("All set!")
                .font(.system(size: 52, weight: .bold))
                .padding(.top, 40)
            
            Button("Start Using \(Bundle.main.appName)") {
                setupComplete = true
            }
            .bigButton(backgroundColor: .accentColor)
        }
    }
}

struct SetupView_Previews: PreviewProvider {
    static var previews: some View {
        SetupView()
            .frame(width: 600, height: 400)
    }
}
