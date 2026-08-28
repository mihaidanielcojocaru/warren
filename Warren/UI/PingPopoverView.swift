//
//  PingPopoverView.swift
//  Warren
//

import SwiftUI

struct PingPopoverView: View {
    let session: PingSession
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ping \(session.deviceName)").font(.headline)
                Spacer()
                if session.isRunning { ProgressView().controlSize(.small) }
            }

            if let failure = session.failure {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if let output = session.output {
                ScrollView {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            } else {
                Text("Waiting for a reply…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Done", action: onDismiss)
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
