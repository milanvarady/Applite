//
//  ShellResult.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 01..
//

import Foundation

/// Returned by functions that run shell commands, ``shell(_:)-51uzj`` and ``ShellOutputStream``
public struct ShellResult {
    let output: String
    let didFail: Bool
}
