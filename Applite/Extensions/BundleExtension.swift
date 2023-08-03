//
//  BundleAppNameExtension.swift
//  Applite
//
//  Created by Milán Várady on 2023. 06. 17..
//

import Foundation

extension Bundle {
    var appName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
        object(forInfoDictionaryKey: "CFBundleName") as? String ??
        ""
    }
    
    var version: String {
        return infoDictionary?["CFBundleShortVersionString"] as! String
    }
    
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as! String
    }
}
