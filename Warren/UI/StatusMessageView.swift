//
//  StatusMessageView.swift
//  Warren
//
//  The non-running states. Each one says what happened and offers the one thing
//  worth doing about it — never an empty list, never an alert.
//

import SwiftUI

struct StatusMessageView: View {
    let state: TailnetState
    let onChooseBinary: () -> Void
    let onOpenTailscale: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .loading:
                message("Checking Tailscale…", symbol: "ellipsis.circle")

            case .binaryNotFound:
                message("Tailscale not found", symbol: "questionmark.folder")
                caption("Warren looks in /Applications, /usr/local/bin and /opt/homebrew/bin.")
                Button("Choose location…", action: onChooseBinary)
                    .buttonStyle(MenuRowButtonStyle())

            case .needsLogin:
                message("Not logged in to Tailscale", symbol: "person.crop.circle.badge.questionmark")
                Button("Open Tailscale", action: onOpenTailscale)
                    .buttonStyle(MenuRowButtonStyle())

            case .disconnected:
                message("Tailscale is disconnected", symbol: "network.slash")
                Button("Open Tailscale", action: onOpenTailscale)
                    .buttonStyle(MenuRowButtonStyle())

            case .starting:
                message("Tailscale is starting…", symbol: "ellipsis.circle")

            case .unreachable(let failure):
                message(failure.summary, symbol: "exclamationmark.triangle")
                if let detail = failure.detail, !detail.isEmpty {
                    DisclosureGroup("Details") {
                        Text(detail)
                            .font(.caption)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                    .font(.caption)
                    .padding(.horizontal, 10)
                }

            case .ready:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }

    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .foregroundStyle(.secondary)
            .menuRowInsets()
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
    }
}
