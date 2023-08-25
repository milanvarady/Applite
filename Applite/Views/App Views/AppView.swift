//
//  AppView.swift
//  Applite
//
//  Created by Milán Várady on 2022. 09. 24..
//

import SwiftUI
import CachedAsyncImage
import Shimmer
import PZCircularControl

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
        func appIconView(iconURL: URL, faviconURL: URL) -> some View {
            CachedAsyncImage(url: iconURL) { phase in
                Group {
                    if let image = phase.image {
                        image
                            .resizable()
                    } else if phase.error != nil {
                        // If fails fallback to homepage favicon
                        CachedAsyncImage(url: faviconURL) { faviconPhase in
                            
                            if let image = faviconPhase.image {
                                image
                                    .resizable()
                            } else if phase.error != nil {
                                PlaceholderAppIcon()
                            }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.gray)
                            .shimmering()
                    }
                }
                .frame(width: 54, height: 54)
            }
        }
        
        return HStack {
            appIconView(iconURL: URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(cask.id)/AppIcon.png")!,
                        faviconURL: URL(string: "https://icon.horse/icon/\(cask.homepageURL.host ?? "")")!)
            .padding(.leading, 5)
            
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
            Text(LocalizedStringKey(BrewInstallation.brokenPathOrIstallMessage))
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
                        OpenAndManageAppView(cask: cask, deleteButton: false, moreOptionsButton: true)
                    } else {
                        DownloadButton(cask: cask)
                            .padding(.trailing, 5)
                    }
                    
                case .update:
                    UpdateButton(cask: cask)
                    
                case .installed:
                    OpenAndManageAppView(cask: cask, deleteButton: true, moreOptionsButton: false)
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
                PZCircularControl(
                    PZCircularControlParams(
                        innerBackgroundColor: Color.clear,
                        outerBackgroundColor: Color.gray.opacity(0.5),
                        tintColor: LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .bottomLeading, endPoint: .topLeading),
                        textColor: .blue,
                        barWidth: 4.0,
                        glowDistance: 10.0,
                        font: .system(size: 10),
                        initialValue: CGFloat(percent)
                    )
                )
                .font(.system(size: 10))
                .frame(width: 54, height: 54)
                
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
                        failureAlertMessage = String(localized:"Couldn't download app. No internet connection, or host is unreachable.")
                        showingFailureAlert = true
                    }
                }
                .alert("Error", isPresented: $showingFailureAlert) {
                    Button("OK", role: .cancel) { }
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
        
        @State var showingPopover = false
        @State var isPresentingCaveats = false
        @State var isPresentingBrewError = false
        @State var isPresentingForceInstallConfirmation = false
        @State var showingPkgAlert = false
        
        @State var buttonFill = false
        
        var body: some View {
            /// Download button
            Button {
                if cask.caveats != nil {
                    // Show caveats dialog
                    isPresentingCaveats = true
                    return
                }
                
                if cask.pkgInstaller {
                    // Show pkg installer alert
                    showingPkgAlert = true
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
            .alert("App caveats", isPresented: $isPresentingCaveats) {
                Button("Download Anyway") {
                    download()
                }
                
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(cask.caveats ?? "")
            }
            .alert("Broken Brew Path", isPresented: $isPresentingBrewError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(BrewInstallation.brokenPathOrIstallMessage)
            }
            .alert("Install will likely fail", isPresented: $showingPkgAlert, actions: {
                Button("Download Anyway") {
                    Task {
                        download()
                    }
                }
                
                Button("Troubleshooting") {
                    if let url = URL(string: "https://aerolite.dev/applite/troubleshooting.html") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Button("Cancel", role: .cancel) { }
            }, message: {
                Text("Installing requires admin password and will most likely fail. We are working on a solution, in the meantime see troubleshooting for more information.")
            })
            
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
                    Link(destination: cask.homepageURL, label: {
                        Label("Homepage", systemImage: "house")
                    })
                    .foregroundColor(.primary)
                    
                    // Force install button
                    Button {
                        isPresentingForceInstallConfirmation = true
                    } label: {
                        Label("Force Install", systemImage: "bolt.trianglebadge.exclamationmark.fill")
                    }
                }
                .padding(8)
                .buttonStyle(.plain)
            }
            .confirmationDialog("Are you sure you want to force install \(cask.name)? This will override any current installation!", isPresented: $isPresentingForceInstallConfirmation) {
                Button("Yes") {
                    download(force: true)
                }
                
                Button("Cancel", role: .cancel) { }
            }
        }
        
        private func download(force: Bool = false) {
            // Check if brew path is valid
            if !BrewPaths.isSelectedBrewPathValid() {
                isPresentingBrewError = true
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
        let moreOptionsButton: Bool
        
        @EnvironmentObject var caskData: CaskData
        
        @State var appNotFoundShowing = false
        @State var showingPopover = false
        
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
            .alert("App coundn't be located", isPresented: $appNotFoundShowing) {
                Button("OK", role: .cancel) { }
            }
            
            if deleteButton {
                UninstallButton(cask: cask)
            }
            
            if moreOptionsButton {
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
                        }
                    }
                    .padding(8)
                    .buttonStyle(.plain)
                }
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
