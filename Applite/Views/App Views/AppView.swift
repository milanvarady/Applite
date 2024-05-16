//
//  AppView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import SwiftUI
import CircularProgress

/// App view role
enum AppRole {
    case installAndManage   // Used in the download section, or when searching
    case update             // Used in the update section
    case installed          // Used in the installed section
}

/// Shows an application's icon and provides controls for installing, updating, uninstalling and opening the app. Used all across the app.
struct AppView: View {
    /// A ``Cask`` object to display
    @ObservedObject var cask: Cask
    /// Role of the app, e.g. install, updated or uninstall
    var role: AppRole
    
    @Environment(\.openWindow) var openWindow
    
    @EnvironmentObject var caskData: CaskData
    
    // Alerts
    @State var showingBrewPathError = false
    @State var failureAlertMessage = ""
    @State var showingFailureAlert = false
    
    // Success animation
    @State var successCheckmarkScale = 0.0001
    @State var keepSuccessIndicator = false
    
    /// App view dimensions, and spacing
    public static let dimensions: (width: CGFloat, height: CGFloat, spacing: CGFloat) = (width: 320, height: 80, spacing: 20)
    
    var body: some View {
        HStack {
            // Icon name and description
            iconAndDescriptionView
            
            // Buttons
            actionsView
        }
        .buttonStyle(.plain)
        .frame(width: Self.dimensions.width, height: Self.dimensions.height)
    }

    private var iconAndDescriptionView: some View {
        return HStack {
            if let iconURL = URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(cask.id)/AppIcon.png"),
               let faviconURL = URL(string: "https://icon.horse/icon/\(cask.homepageURL?.host ?? "")") {
                AppIconView(
                    iconURL: iconURL,
                    faviconURL: faviconURL,
                    cacheKey: cask.id
                )
                .padding(.leading, 5)
            }

            // Name and description
            VStack(alignment: .leading) {
                Text(cask.name)
                    .font(.system(size: 16, weight: .bold))
                
                Text(cask.description)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .alert("Broken Brew Path", isPresented: $showingBrewPathError) {
            Button("OK", role: .cancel) {
                showingBrewPathError = false
            }
        } message: {
            Text(LocalizedStringKey(DependencyManager.brokenPathOrIstallMessage))
        }
    }
    
    @ViewBuilder
    private var actionsView: some View {
        if self.cask.progressState == .idle {
            if !keepSuccessIndicator {
                // Buttons
                switch role {
                case .installAndManage:
                    if cask.isInstalled {
                        OpenAndManageAppView(cask: cask, deleteButton: false)
                    } else {
                        DownloadButton(cask: cask)
                            .padding(.trailing, 5)
                    }
                    
                case .update:
                    UpdateButton(cask: cask)
                    
                case .installed:
                    OpenAndManageAppView(cask: cask, deleteButton: true)
                        .padding(.trailing, 5)
                }
            } else {
                // Success checkmark
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.green)
            }
        } else {
            // Progress indicator
            switch cask.progressState {
            case .busy(let task):
                ProgressView() {
                    if !task.isEmpty {
                        Text(task)
                            .font(.system(size: 12))
                    }
                }
                .scaleEffect(0.8)
                
            case .downloading(let percent):
                CircularProgressView(count: Int(percent * 100),
                                     total: 100,
                                     progress: CGFloat(percent),
                                     fontOne: Font.system(size: 16).bold(),
                                     lineWidth: 6,
                                     showBottomText: false)
                    .frame(width: 40, height: 40)
                
            case .success:
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.green)
                    .scaleEffect(successCheckmarkScale)
                    .onAppear {
                        withAnimation(.spring(blendDuration: 0.5)) {
                            successCheckmarkScale = 1
                        }
                        
                        if self.role == .installAndManage {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.spring(blendDuration: 1)) {
                                    successCheckmarkScale = 0.0001
                                }
                            }
                        } else {
                            keepSuccessIndicator = true
                        }
                    }
                
            case .failed(let output):
                HStack {
                    Text("Error")
                        .foregroundStyle(.red)
                    
                    Button {
                        // Open new window with shell output
                        openWindow(value: output)
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.bordered)
                    
                    Button("OK") {
                        cask.progressState = .idle
                    }
                    .buttonStyle(.bordered)
                }
                .onAppear {
                    // Alert for install errors
                    if output.contains("It seems there is already an App") {
                        failureAlertMessage = String(localized: "\(cask.name) is already installed. If you want to add it to \(Bundle.main.appName) click more options (chevron icon) and press Force Install.")
                        showingFailureAlert = true
                    } else if output.contains("Could not resolve host") {
                        failureAlertMessage = String(localized: "Couldn't download app. No internet connection, or host is unreachable.")
                        showingFailureAlert = true
                    } else if output.lowercased().contains("pinentry") {
                        failureAlertMessage = output
                        showingFailureAlert = true
                    }
                }
                .alert("Error", isPresented: $showingFailureAlert) {
                    Button("OK") { }
                    
                    Button("View Error") {
                        // Open new window with shell output
                        openWindow(value: output)
                        cask.progressState = .idle
                    }
                } message: {
                    Text(failureAlertMessage)
                }
                
            case .idle:
                EmptyView()
            }
        }
    }
    
    /// Button used in the Download section, downloads the app
    private struct DownloadButton: View {
        @ObservedObject var cask: Cask
        
        @EnvironmentObject var caskData: CaskData
        
        // Alerts
        @State var showingPopover = false
        @State var showingCaveats = false
        @State var showingBrewError = false
        @State var showingForceInstallConfirmation = false
        
        @State var buttonFill = false
        
        var body: some View {
            /// Download button
            Button {
                if cask.caveats != nil {
                    // Show caveats dialog
                    showingCaveats = true
                    return
                }
                
                download()
            } label: {
                Image(systemName: "arrow.down.to.line.circle\(buttonFill ? ".fill" : "")")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
            }
            .padding(.trailing, -8)
            .onHover { isHovering in
                // Hover effect
                withAnimation(.snappy) {
                    buttonFill = isHovering
                }
            }
            .alert("App caveats", isPresented: $showingCaveats) {
                Button("Download Anyway") {
                    download()
                }
                
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(cask.caveats ?? "")
            }
            .alert("Broken Brew Path", isPresented: $showingBrewError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(DependencyManager.brokenPathOrIstallMessage)
            }
            
            // More actions popover
            Button() {
                showingPopover = true
            } label: {
                Image(systemName: "chevron.down")
                    .padding(.vertical)
                    .contentShape(Rectangle())
            }
            .popover(isPresented: $showingPopover) {
                VStack(alignment: .leading, spacing: 6) {
                    // Open homepage
                    if let homepageLink = cask.homepageURL {
                        Link(destination: homepageLink, label: {
                            Label("Homepage", systemImage: "house")
                        })
                        .foregroundColor(.primary)
                    } else {
                        Text("No homepage found")
                            .fontWeight(.thin)
                    }

                    // Force install button
                    Button {
                        showingForceInstallConfirmation = true
                    } label: {
                        Label("Force Install", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                    }
                }
                .padding(8)
                .buttonStyle(.plain)
            }
            .confirmationDialog("Are you sure you want to force install \(cask.name)? This will override any current installation!", isPresented: $showingForceInstallConfirmation) {
                Button("Yes") {
                    download(force: true)
                }
                
                Button("Cancel", role: .cancel) { }
            }
        }
        
        private func download(force: Bool = false) {
            // Check if brew path is valid
            if !BrewPaths.isSelectedBrewPathValid() {
                showingBrewError = true
                return
            }
            
            Task {
                await cask.install(caskData: caskData, force: force)
            }
        }
    }
    
    /// Button used in the Download section, launches, uninstalls or reinstalls the app
    private struct OpenAndManageAppView: View {
        @StateObject var cask: Cask
        let deleteButton: Bool
        
        @EnvironmentObject var caskData: CaskData
        
        @State var appNotFoundShowing = false
        @State var showingPopover = false
        
        @State private var isOptionKeyDown = false
        
        var body: some View {
            // Lauch app
            Button("Open") {
                let result = cask.launchApp()
                
                if result.didFail {
                    appNotFoundShowing = true
                }
            }
            .font(.system(size: 14))
            .buttonStyle(.bordered)
            .clipShape(Capsule())
            .alert("App couldn't be located", isPresented: $appNotFoundShowing) {
                Button("OK", role: .cancel) { }
            }
            
            if deleteButton {
                UninstallButton(cask: cask)
            }
            
            // More options popover
            Button() {
                showingPopover = true
            } label: {
                Image(systemName: "chevron.down")
                    .padding(.vertical)
                    .contentShape(Rectangle())
            }
            .popover(isPresented: $showingPopover) {
                VStack(alignment: .leading, spacing: 6) {
                    // Reinstall button
                    Button {
                        Task {
                            await cask.reinstall(caskData: caskData)
                        }
                    } label: {
                        Label("Reinstall", systemImage: "arrow.2.squarepath")
                    }
                    
                    // Uninstall button
                    Button(role: .destructive) {
                        Task {
                            await cask.uninstall(caskData: caskData)
                        }
                    } label: {
                        Label("Uninstall", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    
                    // Uninstall completely button
                    Button(role: .destructive) {
                        Task {
                            await cask.uninstall(caskData: caskData, zap: true)
                        }
                    } label: {
                        Label("Uninstall Completely", systemImage: "trash.fill")
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
                .buttonStyle(.plain)
            }
        }
    }
    
    private struct UpdateButton: View {
        @EnvironmentObject var caskData: CaskData
        @StateObject var cask: Cask
        
        var body: some View {
            Button {
                Task {
                    await MainActor.run { cask.progressState = .busy(withTask: "Updating") }
                    
                    _ = await cask.update(caskData: caskData)
                }
            } label: {
                Image(systemName: "arrow.uturn.down.circle.fill")
                    .font(.system(size: 20))
            }
            .foregroundColor(.blue)
        }
    }
    
    private struct UninstallButton: View {
        @StateObject var cask: Cask
        
        @EnvironmentObject var caskData: CaskData
        
        @State var showingError = false
        
        var body: some View {
            Button {
                Task {
                    await MainActor.run { cask.progressState = .busy(withTask: "Uninstalling") }
                    
                    _ = await cask.uninstall(caskData: caskData)
                }
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 20))
            }
            .foregroundColor(.primary)
        }
    }
}

struct AppView_Previews: PreviewProvider {
    static var previews: some View {
        AppView(cask: Cask(), role: .installAndManage)
    }
}
