//
//  ICloudSyncManager.swift
//  Applite
//
//  Created on 2026.02.09.
//

import Foundation
import OSLog

/// Manages iCloud Key-Value Store sync for previously installed cask IDs
@MainActor
final class ICloudSyncManager: ObservableObject {
    @Published private(set) var previouslyInstalledCaskIds: Set<CaskId> = []

    private let store = NSUbiquitousKeyValueStore.default
    private static let storeKey = "previouslyInstalledCasks"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: ICloudSyncManager.self)
    )

    init() {
        loadFromStore()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChangeExternally(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )

        store.synchronize()
    }

    // MARK: - Public methods

    func addCask(_ id: CaskId) {
        guard isEnabled else { return }
        guard !previouslyInstalledCaskIds.contains(id) else { return }

        previouslyInstalledCaskIds.insert(id)
        saveToStore()
        Self.logger.info("Added cask '\(id)' to app history")
    }

    func addCasks(_ ids: Set<CaskId>) {
        guard isEnabled else { return }
        let newIds = ids.subtracting(previouslyInstalledCaskIds)
        guard !newIds.isEmpty else { return }

        previouslyInstalledCaskIds.formUnion(newIds)
        saveToStore()
        Self.logger.info("Added \(newIds.count) cask(s) to app history")
    }

    func removeCask(_ id: CaskId) {
        previouslyInstalledCaskIds.remove(id)
        saveToStore()
        Self.logger.info("Removed cask '\(id)' from app history")
    }

    func clearAll() {
        previouslyInstalledCaskIds.removeAll()
        store.removeObject(forKey: Self.storeKey)
        store.synchronize()
        Self.logger.info("Cleared all app history")
    }

    // MARK: - Private

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Preferences.iCloudSyncEnabled.rawValue)
    }

    private func loadFromStore() {
        guard let data = store.data(forKey: Self.storeKey) else { return }

        do {
            let ids = try JSONDecoder().decode([String].self, from: data)
            previouslyInstalledCaskIds = Set(ids)
            Self.logger.info("Loaded \(ids.count) cask(s) from iCloud KVS")
        } catch {
            Self.logger.error("Failed to decode iCloud KVS data: \(error.localizedDescription)")
        }
    }

    private func saveToStore() {
        do {
            let data = try JSONEncoder().encode(Array(previouslyInstalledCaskIds))
            store.set(data, forKey: Self.storeKey)
            store.synchronize()
        } catch {
            Self.logger.error("Failed to encode iCloud KVS data: \(error.localizedDescription)")
        }
    }

    @objc
    nonisolated private func storeDidChangeExternally(_ notification: Notification) {
        Task { @MainActor in
            Self.logger.info("Received external iCloud KVS change")

            guard let data = store.data(forKey: Self.storeKey) else { return }

            do {
                let remoteIds = try JSONDecoder().decode([String].self, from: data)
                let remoteSet = Set(remoteIds)
                // Union merge — never lose installs from either side
                previouslyInstalledCaskIds.formUnion(remoteSet)
                saveToStore()
                Self.logger.info("Merged external changes, total: \(self.previouslyInstalledCaskIds.count) cask(s)")
            } catch {
                Self.logger.error("Failed to decode external iCloud KVS data: \(error.localizedDescription)")
            }
        }
    }
}
