//
//  AppDelegate.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import Foundation
import AppKit

class ApplicationDelegate: NSObject, NSApplicationDelegate {
    // Close app after last window closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
