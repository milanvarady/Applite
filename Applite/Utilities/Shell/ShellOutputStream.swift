//
//  ShellOutputStream.swift
//  Applite
//
//  Created by Milán Várady on 2023. 01. 14..
//

import Foundation
import Combine

/// Streams the output of a shell command in real time
public class ShellOutputStream {
    public let outputPublisher = PassthroughSubject<String, Never>()
    
    private var output: String = ""
    private var task: Process?
    private var fileHandle: FileHandle?
    
    /// Runs shell command
    ///
    /// - Parameters:
    ///  - command: Shell command to run
    ///  - environmentVariables: (optional) Environment varables to include in the command
    ///
    /// - Returns: A ``ShellResult`` containing the output and exit status of command
    public func run(_ command: String, environmentVariables: String = "") async -> ShellResult {
        self.task = Process()
        self.task?.launchPath = "/bin/zsh"
        self.task?.arguments = ["-l", "-c", "\(!environmentVariables.isEmpty ? environmentVariables : "") script -q /dev/null \(command)"]
        
        let pipe = Pipe()
        self.task?.standardOutput = pipe
        self.fileHandle = pipe.fileHandleForReading
        
        // Read in output changes
        self.fileHandle?.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            
            if data.count > 0 {
                let text = String(data: data, encoding: .utf8) ?? ""
                
                // Send new changes
                Task { @MainActor in
                    self.outputPublisher.send(text)
                }
                
                self.output += text
            } else if !(self.task?.isRunning ?? false) {
                self.fileHandle?.readabilityHandler = nil
            }
        }
        
        self.task?.launch()
        
        self.task?.waitUntilExit()
        
        return ShellResult(output: self.output, didFail: self.task?.terminationStatus ?? -1 != 0)
    }
}
