//
//  ExportFile.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI

struct ExportFile: FileDocument {
    static let readableContentTypes = [UTType.plainText]

    var text = ""

    // Creates new, empty document
    init(initialText: String = "") {
        text = initialText
    }

    // Loads data that has been saved previously
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        }
    }

    // This will be called when the system wants to write our data to disk
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
