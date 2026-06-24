//
//  CaskInfoWindowView.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.02.
//

import SwiftUI

struct CaskInfoWindowView: View {
    let info: CaskAdditionalInfo
    @Environment(\.openURL) private var openURL

    var body: some View {
        Table(rows) {
            TableColumn("Property", value: \.property)
                .width(120)

            TableColumn("Value") { row in
                if let url = row.url {
                    Link(row.value, destination: url)
                } else {
                    Text(row.value)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // Data structure to represent each row
    private struct Row: Identifiable {
        let id = UUID()
        let property: String
        let value: String
        let url: URL?

        init(property: String, value: String, url: URL? = nil) {
            self.property = property
            self.value = value
            self.url = url
        }
    }

    private var rows: [Row] {
        var result: [Row] = [
            Row(property: "Token", value: info.token),
            Row(property: "Full Token", value: info.full_token),
            Row(property: "Tap", value: info.tap),
            Row(property: "Homepage", value: info.homepage.absoluteString, url: info.homepage),
            Row(property: "URL", value: info.url.absoluteString, url: info.url),
            Row(property: "Installed Version", value: info.installed ?? "Not installed"),
            Row(property: "Bundle Version", value: info.bundle_version ?? "Not installed"),
            Row(property: "Auto Updates", value: (info.auto_updates ?? false) ? "Yes" : "No")
        ]

        if let outdated = info.outdated {
            result.append(Row(property: "Outdated", value: outdated ? "Yes" : "No"))
        }

        if let installedTime = info.installed_time {
            result.append(Row(property: "Installation Date",
                              value: dateFormatter.string(from: installedTime)))
        }

        result.append(Row(property: "Deprecated", value: info.deprecated ? "Yes" : "No"))

        if info.deprecated {
            if let date = info.deprecation_date {
                result.append(Row(property: "Deprecation Date",
                                  value: date))
            }
            if let reason = info.deprecation_reason {
                result.append(Row(property: "Deprecation Reason", value: reason))
            }
            if let replacement = info.deprecation_replacement {
                result.append(Row(property: "Deprecation Replacement", value: replacement))
            }
        }

        result.append(Row(property: "Disabled", value: info.disabled ? "Yes" : "No"))

        if info.disabled {
            if let date = info.disable_date {
                result.append(Row(property: "Disabled Date",
                                  value: date))
            }
            if let reason = info.disable_reason {
                result.append(Row(property: "Disabled Reason", value: reason))
            }
            if let replacement = info.disable_replacement {
                result.append(Row(property: "Disabled Replacement", value: replacement))
            }
        }

        return result
    }
}

#Preview {
    CaskInfoWindowView(info: .dummy)
}
