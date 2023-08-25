//
//  ImportCasks.swift
//  Applite
//
//  Created by Milán Várady on 2023. 08. 12..
//

import Foundation

enum CaskImportError: Error {
    case FileReadError
    case ParseError
}

func readCaskFile(url: URL) throws -> [String] {
    do {
        let content = try String(contentsOf: url)
        var casks: [String] = []
        let brewfileRegex = /cask "([\w-]+)"/
        
        if content.contains("cask \"") {
            // Brewfile
            let matches = content.matches(of: brewfileRegex)
            casks = matches.map({ String($0.1) })
        } else {
            // Txt file
            casks = content.components(separatedBy: .newlines)
            
            // Trim whitespace
            casks = casks.map({ $0.trimmingCharacters(in: .whitespaces) })
        }
        
        // Remove empty elements
        casks = casks.filter({ !$0.isEmpty })
        
        if casks.isEmpty {
            throw CaskImportError.ParseError
        }
        
        return casks
    } catch {
        throw CaskImportError.FileReadError
    }
}

func installImportedCasks(casks: [String], caskData: CaskData) async {
    let casksToInstall: [Cask] = await caskData.casks.filter({ casks.contains($0.id) })
    
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
