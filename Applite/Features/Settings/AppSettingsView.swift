import SwiftUI
import ButtonKit

struct AppSettingsView: View {
    @Environment(CaskManager.self) private var caskManager
    let alert: AlertManager

    @AppStorage(Preferences.catalogUpdateFrequency) private var catalogUpdateFrequency
    @AppStorage(Preferences.includeCasksFromTaps) private var includeCasksFromTaps
    @AppStorage(Preferences.detectExternallyInstalledApps) private var detectExternallyInstalledApps
    @AppStorage(Preferences.offerHomebrewManagement) private var offerHomebrewManagement
    @AppStorage(Preferences.overrideIntuneManagement) private var overrideIntune
    @AppStorage(Preferences.overrideAppStoreManagement) private var overrideAppStore
    @AppStorage(Preferences.overrideSetappManagement) private var overrideSetapp
    @AppStorage(Preferences.overrideArtCraftManagement) private var overrideArtCraft
    @AppStorage(Preferences.notificationSuccess) private var notificationOnSuccess
    @AppStorage(Preferences.notificationFailure) private var notificationOnFailure
    @AppStorage(Preferences.appdirOn) private var appdirOn
    @AppStorage(Preferences.appdirPath) private var appdirPath
    @State private var previousIncludeCasksFromTaps: Bool?

    private var managementSettings: [Bool] {
        [detectExternallyInstalledApps, offerHomebrewManagement,
         overrideIntune, overrideAppStore, overrideSetapp, overrideArtCraft]
    }

    var body: some View {
        Form {
            catalogSettings
            detectionSettings
            Section("Installation Location") {
                AppdirSelectorView()
            }
            managementSettingsSection
            Section("Notifications") {
                Toggle("Successful installs & updates", isOn: $notificationOnSuccess)
                Toggle("Failed installs & updates", isOn: $notificationOnFailure)
            }
            overrideSettings
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            refreshCatalogBanner
        }
        .onAppear {
            if previousIncludeCasksFromTaps == nil {
                previousIncludeCasksFromTaps = includeCasksFromTaps
            }
        }
        .onChange(of: detectExternallyInstalledApps) { _, _ in
            caskManager.applyExternalAppDetectionSetting(surfacingErrorsIn: alert)
        }
        .onChange(of: managementSettings) { _, _ in
            caskManager.applyAppManagementSettings(surfacingErrorsIn: alert)
        }
        .onChange(of: [String(appdirOn), appdirPath]) { _, _ in
            caskManager.applyExternalAppDetectionSetting(debounce: true, surfacingErrorsIn: alert)
        }
    }

    private var catalogSettings: some View {
        Section("App Catalog") {
            Picker("Fetch app catalog every:", selection: $catalogUpdateFrequency) {
                ForEach(CatalogUpdateFrequency.allCases) { frequency in
                    Text(frequency.description).tag(frequency)
                }
            }
            Toggle(isOn: $includeCasksFromTaps) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include Third-Party Taps", comment: "Brew settings tap toggle title")
                    Text("Also show apps from Homebrew taps (third-party repositories) you've added manually. (Homebrew: `tap`)", comment: "Brew settings tap toggle description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(caskManager.isRefreshingCatalog)
        }
    }

    private var detectionSettings: some View {
        Section("Installed App Detection") {
            Toggle(isOn: $detectExternallyInstalledApps) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detect externally installed apps")
                    Text("Include apps installed outside Homebrew in Installed. Turning this off does not change your apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var managementSettingsSection: some View {
        Section {
            Toggle(isOn: $offerHomebrewManagement) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offer Manage with Homebrew")
                    Text("Show management actions for external apps with an exact, enabled Homebrew cask. Reinstalling requires confirmation. Other app sources remain protected unless explicitly overridden below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !detectExternallyInstalledApps {
                        Text("Requires external app detection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!detectExternallyInstalledApps)
            GreedyUpgradeToggle()
        } header: {
            Text("Homebrew Management")
        } footer: {
            Text("Managing external apps and all source overrides are off by default. Existing Homebrew-managed apps keep their normal controls.")
        }
    }

    private var overrideSettings: some View {
        Section {
            overrideToggle(.intune, isOn: $overrideIntune)
            overrideToggle(.appStore, isOn: $overrideAppStore)
            overrideToggle(.setapp, isOn: $overrideSetapp)
            overrideToggle(.artCraft, isOn: $overrideArtCraft)
        } header: {
            Text("Advanced: App Management Source Overrides")
        } footer: {
            Text("Requires external app detection and Offer Manage with Homebrew. Overrides only lift Applite's protection for the selected source. They do not remove device enrollment, organizational policies, or licensing requirements. Replacing an app may affect its license and settings; the original manager may reinstall it. Every detected source must be overridden. Disable Offer Manage with Homebrew to suspend all overrides without forgetting your choices. Running operations are not undone.")
        }
        .disabled(!detectExternallyInstalledApps || !offerHomebrewManagement)
    }

    private func overrideToggle(_ source: ProtectedAppInstallation.Source, isOn: Binding<Bool>) -> some View {
        Toggle(source.overrideTitle, isOn: Binding(
            get: { isOn.wrappedValue },
            set: { enabled in
                caskManager.requestManagementSourceOverride(source, enabled: enabled, surfacingErrorsIn: alert)
            }
        ))
    }

    @ViewBuilder
    private var refreshCatalogBanner: some View {
        if let previousIncludeCasksFromTaps, previousIncludeCasksFromTaps != includeCasksFromTaps {
            HStack {
                Text("Refresh the app catalog to apply your changes")
                Spacer()
                AsyncButton {
                    let requestedIncludeCasksFromTaps = includeCasksFromTaps
                    if await caskManager.loadData(forceSync: true, surfacingErrorsIn: alert) {
                        self.previousIncludeCasksFromTaps = requestedIncludeCasksFromTaps
                    }
                } label: {
                    Label("Refresh Catalog", systemImage: "arrow.clockwise")
                }
                .disabled(caskManager.isRefreshingCatalog)
            }
            .padding()
            .background(.bar)
        }
    }
}
