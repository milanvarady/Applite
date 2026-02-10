//
//  AppPaths.swift
//  Applite
//
//  Created by Milán Várady on 2026. 02. 09..
//

import Foundation

enum AppPaths {
    static let applicationSupport: URL = URL
        .applicationSupportDirectory
        .appending(path: "Applite", directoryHint: .isDirectory)
    
    static let database = Self.applicationSupport
        .appending(path: "casks.sqlite")
    
    // TODO: call this somewhere
    static func createApplicationSupportIfNeeded() throws {
        try FileManager.default.createDirectory(
            at: Self.applicationSupport,
            withIntermediateDirectories: true
        )
    }
}
