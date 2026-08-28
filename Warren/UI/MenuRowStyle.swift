//
//  MenuRowStyle.swift
//  Warren
//
//  A button that behaves like a menu item inside the panel.
//

import SwiftUI

struct MenuRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(highlight(isPressed: configuration.isPressed))
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }

    private func highlight(isPressed: Bool) -> Color {
        if isPressed { return Color.accentColor.opacity(0.35) }
        return isHovering ? Color.primary.opacity(0.08) : Color.clear
    }
}

extension View {
    /// Horizontal padding that lines content up with the menu rows.
    func menuRowInsets() -> some View {
        padding(.horizontal, 10).padding(.vertical, 5)
    }
}
