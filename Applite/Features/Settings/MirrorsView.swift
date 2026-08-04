//
//  MirrorsView.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import SwiftUI

struct MirrorsView: View {
    @AppStorage(Preferences.mirrorEnabled) var mirrorEnabled
    @AppStorage(Preferences.mirrorAPIDomain) var apiDomain
    @AppStorage(Preferences.mirrorBrewGitRemote) var brewGitRemote
    @AppStorage(Preferences.mirrorCoreGitRemote) var coreGitRemote
    @AppStorage(Preferences.mirrorBottleDomain) var bottleDomain

    var body: some View {
        Form {
            Section("Mirror") {
                Toggle("Enabled", isOn: $mirrorEnabled)

                LabeledContent("Presets") {
                    Menu("Presets") {
                        ForEach(mirrorPresets) { preset in
                            Button(preset.name) {
                                apiDomain = preset.apiDomain
                                brewGitRemote = preset.brewGitRemote
                                coreGitRemote = preset.coreGitRemote
                                bottleDomain = preset.bottleDomain
                            }
                        }
                    }
                    .menuStyle(.borderedButton)
                    .fixedSize()
                }
            }

            Section("Environment Variables") {
                EnvironmentInput(title: "HOMEBREW_API_DOMAIN", text: $apiDomain)
                EnvironmentInput(title: "HOMEBREW_BREW_GIT_REMOTE", text: $brewGitRemote)
                EnvironmentInput(title: "HOMEBREW_CORE_GIT_REMOTE", text: $coreGitRemote)
                EnvironmentInput(title: "HOMEBREW_BOTTLE_DOMAIN", text: $bottleDomain)
            }
        }
        .formStyle(.grouped)
    }

    private let mirrorPresets: [MirrorPreset] = [
        .init(
            name: "USTC",
            apiDomain: "https://mirrors.ustc.edu.cn/homebrew-bottles/api",
            brewGitRemote: "https://mirrors.ustc.edu.cn/brew.git",
            coreGitRemote: "https://mirrors.ustc.edu.cn/homebrew-core.git",
            bottleDomain: "https://mirrors.ustc.edu.cn/homebrew-bottles"
        ),
        .init(
            name: "Tsinghua University",
            apiDomain: "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api",
            brewGitRemote: "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git",
            coreGitRemote: "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git",
            bottleDomain: "https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
        ),
        .init(
            name: "Aliyun",
            apiDomain: "https://mirrors.aliyun.com/homebrew-bottles/api",
            brewGitRemote: "https://mirrors.aliyun.com/homebrew/brew.git",
            coreGitRemote: "https://mirrors.aliyun.com/homebrew/homebrew-core.git",
            bottleDomain: "https://mirrors.aliyun.com/homebrew/homebrew-bottles"
        ),
    ]

    private struct MirrorPreset: Identifiable {
        var id: String {
            name
        }

        let name: String
        let apiDomain: String
        let brewGitRemote: String
        let coreGitRemote: String
        let bottleDomain: String
    }
}
