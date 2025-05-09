//
//  BundleAppNameExtension.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 17..
//

import Foundation

extension Bundle {
    var version: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
    }
    
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
    }
}
