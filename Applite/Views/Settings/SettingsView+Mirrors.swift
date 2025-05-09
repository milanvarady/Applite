//
//  SettingsView+Mirrors.swift
//  Applite
//
//  Created by Milán Várady on 2025.05.09.
//

import SwiftUI

extension SettingsView {
    struct MirrorsView: View {
        @AppStorage(Preferences.mirrorEnabled.rawValue) var mirrorEnabled: Bool = false
        @AppStorage(Preferences.mirrorAPIDomain.rawValue) var apiDomain: String = ""
        @AppStorage(Preferences.mirrorBrewGitRemote.rawValue) var brewGitRemote: String = ""
        @AppStorage(Preferences.mirrorCoreGitRemote.rawValue) var coreGitRemote: String = ""
        @AppStorage(Preferences.mirrorBottleDomain.rawValue) var bottleDomain: String = ""

        var body: some View {
            VStack(alignment: .leading) {
                Text("Mirror")
                    .bold()

                Toggle("Enabled", isOn: $mirrorEnabled)

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

                Divider()
                    .padding(.vertical)

                VStack(alignment: .leading, spacing: 12) {
                    EnvironmentInput(title: "HOMEBREW_API_DOMAIN", text: $apiDomain)
                    EnvironmentInput(title: "HOMEBREW_BREW_GIT_REMOTE", text: $brewGitRemote)
                    EnvironmentInput(title: "HOMEBREW_CORE_GIT_REMOTE", text: $coreGitRemote)
                    EnvironmentInput(title: "HOMEBREW_BOTTLE_DOMAIN", text: $bottleDomain)
                }
            }
            .padding()
        }

        struct EnvironmentInput: View {
            let title: String
            @Binding var text: String

            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .fontWeight(.light)
                    TextField(title, text: $text)
                        .textFieldStyle(.roundedBorder)
                }
            }
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
}
