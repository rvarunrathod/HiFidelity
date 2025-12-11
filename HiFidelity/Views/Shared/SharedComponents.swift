//
//  SharedComponents.swift
//  HiFidelity
//
//  Created by Varun Rathod on 03/11/25.
//

import SwiftUI

// MARK: - View Mode Button

struct ViewModeButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(isSelected ? theme.currentTheme.primaryColor : .secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            isSelected
                                ? theme.currentTheme.primaryColor.opacity(0.12)
                                : (isHovered ? Color.primary.opacity(0.06) : Color.clear)
                        )
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
                isHovered = hovering
        }
    }
}

// MARK: - View Mode

enum ViewMode {
    case grid
    case list
}


// MARK: - Custom Button Styles

struct PlainHoverButtonStyle: ButtonStyle {
    @State private var isHovered = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : (isHovered ? 1.02 : 1.0))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
