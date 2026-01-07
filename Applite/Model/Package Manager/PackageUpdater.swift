//
//  PackageUpdater.swift
//  Applite
//
//   Created by Subham mahesh
//   licensed under the MIT

import Foundation
import SwiftUI
import OSLog
import UserNotifications

/// Manages automatic package updates and notifications
@MainActor
final class PackageUpdater: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isAutoUpdateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isAutoUpdateEnabled, forKey: "PackageAutoUpdateEnabled")
            if isAutoUpdateEnabled {
                scheduleAutoUpdate()
            } else {
                cancelAutoUpdate()
            }
        }
    }
    
    @Published var autoUpdateFrequency: UpdateFrequency {
        didSet {
            UserDefaults.standard.set(autoUpdateFrequency.rawValue, forKey: "PackageAutoUpdateFrequency")
            if isAutoUpdateEnabled {
                scheduleAutoUpdate()
            }
        }
    }
    
    @Published var lastUpdateCheck: Date? {
        didSet {
            if let date = lastUpdateCheck {
                UserDefaults.standard.set(date, forKey: "PackageLastUpdateCheck")
            }
        }
    }
    
    @Published var updateResults: [UpdateResult] = []
    @Published var isUpdating = false
    
    // MARK: - Private Properties
    
    private let coordinator: PackageManagerCoordinator
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: PackageUpdater.self)
    )
    
    private var updateTimer: Timer?
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - Initialization
    
    init(coordinator: PackageManagerCoordinator) {
        self.coordinator = coordinator
        
        // Load preferences
        self.isAutoUpdateEnabled = UserDefaults.standard.bool(forKey: "PackageAutoUpdateEnabled")
        self.autoUpdateFrequency = UpdateFrequency(rawValue: UserDefaults.standard.string(forKey: "PackageAutoUpdateFrequency") ?? UpdateFrequency.daily.rawValue) ?? .daily
        self.lastUpdateCheck = UserDefaults.standard.object(forKey: "PackageLastUpdateCheck") as? Date
        
        // Setup notification permissions
        Task {
            await requestNotificationPermission()
        }
        
        // Schedule auto update if enabled
        if isAutoUpdateEnabled {
            scheduleAutoUpdate()
        }
    }
    
    deinit {
        cancelAutoUpdate()
    }
    
    // MARK: - Auto Update Management
    
    private func scheduleAutoUpdate() {
        cancelAutoUpdate()
        
        let interval = autoUpdateFrequency.timeInterval
        updateTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performAutoUpdate()
            }
        }
        
        logger.info("Auto update scheduled with frequency: \(autoUpdateFrequency.rawValue)")
    }
    
    private func cancelAutoUpdate() {
        updateTimer?.invalidate()
        updateTimer = nil
        logger.info("Auto update cancelled")
    }
    
    private func performAutoUpdate() async {
        guard !isUpdating else { return }
        
        logger.info("Performing automatic package update")
        
        // Check for outdated packages
        await coordinator.loadOutdatedPackages()
        
        guard !coordinator.outdatedPackages.isEmpty else {
            logger.info("No packages to update")
            lastUpdateCheck = Date()
            return
        }
        
        // Send notification about available updates
        await sendUpdateAvailableNotification(count: coordinator.outdatedPackages.count)
        
        // Perform updates
        await updateAllPackages()
        
        lastUpdateCheck = Date()
    }
    
    // MARK: - Manual Update Operations
    
    func checkForUpdates() async {
        logger.info("Manual check for updates")
        await coordinator.loadOutdatedPackages()
        lastUpdateCheck = Date()
    }
    
    func updateAllPackages() async {
        guard !isUpdating else { return }
        
        isUpdating = true
        updateResults = []
        
        logger.info("Starting update all packages")
        
        let outdatedPackages = coordinator.outdatedPackages
        guard !outdatedPackages.isEmpty else {
            isUpdating = false
            return
        }
        
        var results: [UpdateResult] = []
        
        for package in outdatedPackages {
            let result = await updatePackage(package)
            results.append(result)
        }
        
        updateResults = results
        isUpdating = false
        
        // Send completion notification
        let successCount = results.filter { $0.success }.count
        let failureCount = results.count - successCount
        
        await sendUpdateCompletionNotification(
            successCount: successCount,
            failureCount: failureCount
        )
        
        // Refresh data
        await coordinator.refreshAllData()
        
        logger.info("Completed update all packages: \(successCount) successful, \(failureCount) failed")
    }
    
    func updatePackagesFor(manager: PackageManagerType) async {
        guard !isUpdating else { return }
        
        isUpdating = true
        updateResults = []
        
        logger.info("Updating packages for manager: \(manager.displayName)")
        
        let packages = coordinator.getOutdatedPackagesByManager(manager)
        var results: [UpdateResult] = []
        
        for package in packages {
            let result = await updatePackage(package)
            results.append(result)
        }
        
        updateResults = results
        isUpdating = false
        
        await coordinator.refreshAllData()
        
        logger.info("Completed updates for \(manager.displayName)")
    }
    
    private func updatePackage(_ package: GenericPackage) async -> UpdateResult {
        let startTime = Date()
        
        do {
            await coordinator.updatePackage(package)
            
            let duration = Date().timeIntervalSince(startTime)
            return UpdateResult(
                package: package,
                success: true,
                duration: duration,
                error: nil
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return UpdateResult(
                package: package,
                success: false,
                duration: duration,
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Notification Management
    
    private func requestNotificationPermission() async {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                logger.info("Notification permission granted")
            } else {
                logger.warning("Notification permission denied")
            }
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
        }
    }
    
    private func sendUpdateAvailableNotification(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Package Updates Available", comment: "Notification title for available updates")
        content.body = String(localized: "\(count) packages have updates available", comment: "Notification body for available updates")
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "package-updates-available",
            content: content,
            trigger: nil
        )
        
        do {
            try await notificationCenter.add(request)
            logger.info("Sent update available notification")
        } catch {
            logger.error("Failed to send update notification: \(error.localizedDescription)")
        }
    }
    
    private func sendUpdateCompletionNotification(successCount: Int, failureCount: Int) async {
        let content = UNMutableNotificationContent()
        
        if failureCount == 0 {
            content.title = String(localized: "Package Updates Complete", comment: "Notification title for successful updates")
            content.body = String(localized: "Successfully updated \(successCount) packages", comment: "Notification body for successful updates")
        } else {
            content.title = String(localized: "Package Updates Complete", comment: "Notification title for mixed update results")
            content.body = String(localized: "\(successCount) successful, \(failureCount) failed", comment: "Notification body for mixed update results")
        }
        
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "package-updates-complete",
            content: content,
            trigger: nil
        )
        
        do {
            try await notificationCenter.add(request)
            logger.info("Sent update completion notification")
        } catch {
            logger.error("Failed to send completion notification: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types

enum UpdateFrequency: String, CaseIterable, Identifiable {
    case hourly = "hourly"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .hourly: return String(localized: "Every Hour", comment: "Hourly update frequency")
        case .daily: return String(localized: "Daily", comment: "Daily update frequency")
        case .weekly: return String(localized: "Weekly", comment: "Weekly update frequency")
        case .monthly: return String(localized: "Monthly", comment: "Monthly update frequency")
        }
    }
    
    var timeInterval: TimeInterval {
        switch self {
        case .hourly: return 3600
        case .daily: return 86400
        case .weekly: return 604800
        case .monthly: return 2628000
        }
    }
}

struct UpdateResult: Identifiable {
    let id = UUID()
    let package: GenericPackage
    let success: Bool
    let duration: TimeInterval
    let error: String?
    let timestamp = Date()
    
    var formattedDuration: String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            return String(format: "%.1fm", duration / 60)
        }
    }
}