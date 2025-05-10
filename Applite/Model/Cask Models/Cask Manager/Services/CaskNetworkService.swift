//
//  CaskNetworkService.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import Foundation
import OSLog

/// Responsible for all network operations related to cask data
struct CaskNetworkService {
    // URLs
    private static let caskAPIURL = URL(string: "https://formulae.brew.sh/api/cask.json")!
    private static let analyticsAPIURL = URL(string: "https://formulae.brew.sh/api/analytics/cask-install/365d.json")!

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: CaskNetworkService.self)
    )

    /// Fetches cask information from the Homebrew API
    /// - Returns: An array of CaskInfo objects
    func fetchCaskInfo() async throws -> [CaskInfo] {
        // Fetch Data Transfer Objects from Homebrew API
        let DTOObjects = try await fetchData(from: Self.caskAPIURL, as: [CaskDTO].self)
        return DTOObjects.compactMap { try? CaskInfo(fromDTO: $0) }
    }

    /// Fetches analytics data from the Homebrew API
    /// - Returns: BrewAnalytics object containing download statistics
    func fetchAnalyticsData() async throws -> BrewAnalytics {
        return try await fetchData(from: Self.analyticsAPIURL, as: BrewAnalytics.self)
    }

    /// Fetches cask information from taps using the brew CLI
    /// - Returns: An array of CaskInfo objects from taps
    func fetchTapCaskInfo() async -> [CaskInfo] {
        // Check if taps are enabled
        let enabled = UserDefaults.standard.value(forKey: Preferences.includeCasksFromTaps.rawValue) as? Bool ?? true

        // If not return empty array
        guard enabled else {
            return []
        }

        guard let tapInfoRubyScriptPath = Bundle.main.path(forResource: "brew-tap-cask-info", ofType: "rb") else {
            logger.error("Failed to locate tap info ruby script")
            return []
        }

        let arguments = [BrewPaths.currentBrewExecutable.quotedPath(), "ruby", tapInfoRubyScriptPath.paddedWithQuotes()]
        let command = arguments.joined(separator: " ")

        var shellOutput = ""

        // We need to use stream here because the regular runAsync cannot handle an output this long
        do {
            for try await line in Shell.stream(command) {
                shellOutput += line + "\n"
            }
        } catch {
            logger.error("Failed to load tap cask info from shell: \(error).\nOutput: \(shellOutput)")
        }

        // Extract JSON data (text between [] marks)
        guard let match = shellOutput.firstMatch(of: /\[((.|\n|\r)*)\]/) else {
            return []
        }

        let jsonString = match.0

        guard let jsonData = jsonString.data(using: .utf8) else {
            logger.error("Failed to conver json string to data during tap compilation")
            return []
        }

        guard let caskDTOs = try? JSONDecoder().decode([CaskDTO].self, from: jsonData) else {
            logger.error("Failed to decode json data during tap compilation")
            return []
        }

        let casks = caskDTOs.compactMap { try? CaskInfo(fromDTO: $0) }

        return casks
    }

    /// Generic method to fetch and decode data from a URL
    /// - Parameters:
    ///   - url: The URL to fetch data from
    ///   - type: The type to decode the data into
    /// - Returns: Decoded object of specified type
    private func fetchData<T: Decodable>(from url: URL, as type: T.Type) async throws -> T {
        let sessionConfiguration = NetworkProxyManager.getURLSessionConfiguration()
        let urlSession = URLSession(configuration: sessionConfiguration)

        let (data, _) = try await urlSession.data(from: url)
        return try JSONDecoder().decode(type, from: data)
    }
}
