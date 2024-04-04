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

    static func getProxySettings() throws -> NetworkProxyConfiguration {
        let proxySettings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as? [String: Any]

        guard let httpProxyHost = proxySettings?[kCFNetworkProxiesHTTPProxy as String] as? String else {
            Self.logger.warning("No proxy host found")
            throw NetworkProxyError.noProxyHost
        }

        guard let httpProxyPort = proxySettings?[kCFNetworkProxiesHTTPPort as String] as? Int else {
            Self.logger.warning("No proxy port found")
            throw NetworkProxyError.noProxyPort
        }

        return NetworkProxyConfiguration(host: httpProxyHost, port: httpProxyPort)
    }

    static func getURLSessionConfiguration() -> URLSessionConfiguration {
        let sessionConfiguration = URLSessionConfiguration.default

        if let proxySettings = try? Self.getProxySettings() {
            sessionConfiguration.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable: 1,
                kCFNetworkProxiesHTTPPort: proxySettings.port,
                kCFNetworkProxiesHTTPProxy: proxySettings.host
            ]
        }

        return sessionConfiguration
    }
}

struct NetworkProxyConfiguration {
    let host: String
    let port: Int
}

enum NetworkProxyError: Error {
    case noProxyHost
    case noProxyPort
}
