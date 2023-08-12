//
//  ImportCasks.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 12..
//

import Foundation

enum CaskImportError: Error {
    case FileReadError
}

func readCaskFile(url: URL) throws -> String {
    do {
        let content = try String(contentsOf: url)
        return content
    } catch {
        throw CaskImportError.FileReadError
    }
}

func installImportedCasks(caskText: String, caskData: CaskData) async {
    var caskList = caskText.components(separatedBy: .newlines)
    caskList = caskList.map({ $0.trimmingCharacters(in: .whitespaces) }) // Trim whitespace
    caskList = caskList.filter({ !$0.isEmpty }) // Remove empty elements
    
    let casksToInstall = await caskData.casks.filter({ caskList.contains($0.id) })
    
    await withTaskGroup(of: Void.self) { group in
        for cask in casksToInstall {
            group.addTask {
                if !cask.isInstalled {
                    await cask.install(caskData: caskData)
                }
            }
        }
    }
}
