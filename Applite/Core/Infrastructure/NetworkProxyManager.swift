//
//  NetworkProxyManager.swift
//  Applite
//
//  Created by Milán Várady on 01/04/2024.
//

import Foundation
import OSLog

struct NetworkProxyManager {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NetworkProxyManager")

    static func getSystemProxySettings() throws -> NetworkProxyConfiguration {
        guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as? [String: Any] else {
            Self.logger.warning("Failed to get system network proxy settings")
            throw NetworkProxyError.failedToGetSystemSettings
        }

        // Get preferneces
        let proxyEnabled: Bool = UserDefaults.standard.value(forKey: Preferences.networkProxyEnabled.rawValue) as? Bool ?? true
        let preferredProxyTypeString: String = UserDefaults.standard.string(forKey: Preferences.preferredProxyType.rawValue) ?? ""
        let preferredProxyType: NetworkProxyType? = NetworkProxyType(rawValue: preferredProxyTypeString)

        if !proxyEnabled {
            throw NetworkProxyError.proxyNotEnabled
        }

        // Determine proxy type
        let httpProxyEnabled = proxySettings[kCFNetworkProxiesHTTPEnable as String] as? Bool ?? false
        let httpsProxyEnabled = proxySettings[kCFNetworkProxiesHTTPSEnable as String] as? Bool ?? false
        let socks5ProxyEnabled = proxySettings[kCFNetworkProxiesSOCKSEnable as String] as? Bool ?? false

        var proxyType: NetworkProxyType? = nil

        // First, try to set it to preferred proxy method
        if let preferredProxyTypeUnwrapped = preferredProxyType {
            switch preferredProxyTypeUnwrapped {
            case .http:
                if httpProxyEnabled {
                    proxyType = .http
                }
            case .https:
                if httpsProxyEnabled {
                    proxyType = .https
                }
            case .socks5:
                if socks5ProxyEnabled {
                    proxyType = .socks5
                }
            }
        }

        // If no preferred method is selected, check other methods
        if proxyType == nil {
            proxyType = if httpProxyEnabled {
                .http
            } else if httpsProxyEnabled {
                .https
            } else if socks5ProxyEnabled {
                .socks5
            } else {
                throw NetworkProxyError.proxyNotEnabled
            }
        }

        // Check proxy type for nil
        guard let proxyType = proxyType else {
            throw NetworkProxyError.proxyNotEnabled
        }

        // Get proxy host
        guard let proxyHost = switch proxyType {
            case .http:
                proxySettings[kCFNetworkProxiesHTTPProxy as String] as? String
            case .https:
                proxySettings[kCFNetworkProxiesHTTPSProxy as String] as? String
            case .socks5:
                proxySettings[kCFNetworkProxiesSOCKSProxy as String] as? String
        }
        // guard else
        else {
            throw NetworkProxyError.noProxyHost
        }

        // Get proxy port
        guard let proxyPort = switch proxyType {
            case .http:
                proxySettings[kCFNetworkProxiesHTTPPort as String] as? Int
            case .https:
                proxySettings[kCFNetworkProxiesHTTPSPort as String] as? Int
            case .socks5:
                proxySettings[kCFNetworkProxiesSOCKSPort as String] as? Int
        }
        // guard else
        else {
            throw NetworkProxyError.noProxyPort
        }

        Self.logger.notice("Network proxy enabled. \(proxyType.URLPrefix, privacy: .public)\(proxyHost):\(proxyPort)")

        return NetworkProxyConfiguration(type: proxyType, host: proxyHost, port: proxyPort)
    }

    static func getURLSessionConfiguration() -> URLSessionConfiguration {
        let sessionConfiguration = URLSessionConfiguration.default

        // Add proxy settings
        if let proxySettings = try? Self.getSystemProxySettings() {
            switch proxySettings.type {
            case .http:
                sessionConfiguration.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable: 1,
                    kCFNetworkProxiesHTTPPort: proxySettings.port,
                    kCFNetworkProxiesHTTPProxy: proxySettings.host
                ]
            case .https:
                sessionConfiguration.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPSEnable: 1,
                    kCFNetworkProxiesHTTPSPort: proxySettings.port,
                    kCFNetworkProxiesHTTPSProxy: proxySettings.host
                ]
            case .socks5:
                sessionConfiguration.connectionProxyDictionary = [
                    kCFNetworkProxiesSOCKSEnable: 1,
                    kCFNetworkProxiesSOCKSPort: proxySettings.port,
                    kCFNetworkProxiesSOCKSProxy: proxySettings.host
                ]
            }

        }

        return sessionConfiguration
    }
}

struct NetworkProxyConfiguration {
    let type: NetworkProxyType
    let host: String
    let port: Int

    var fullString: String {
        return "\(type.URLPrefix)\(host):\(port)"
    }
}

enum NetworkProxyType: String, CaseIterable, Identifiable {
    case http
    case https
    case socks5

    var URLPrefix: String {
        switch self {
        case .http:
            return "http://"
        case .https:
            return "https://"
        case .socks5:
            return "socks5://"
        }
    }

    var displayName: String {
        switch self {
        case .http:
            return "HTTP"
        case .https:
            return "HTTPS"
        case .socks5:
            return "SOCKS5"
        }
    }

    var id: String {
        self.rawValue
    }
}

enum NetworkProxyError: LocalizedError {
    case failedToGetSystemSettings
    case proxyNotEnabled
    case noProxyHost
    case noProxyPort

    var errorDescription: String? {
        switch self {
        case .failedToGetSystemSettings:
            return "Failed to get system proxy settings"
        case .proxyNotEnabled:
            return "Proxy is not enabled"
        case .noProxyHost:
            return "No proxy host specified"
        case .noProxyPort:
            return "No proxy port specified"
        }
    }
}
