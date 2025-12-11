//
//  LibraryTabButton.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Tab button for library navigation - LINE Design System Segmented Control Style
struct LibraryTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .fixedSize()
                    .frame(width: 16, height: 16)
                
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.currentTheme.primaryColor.opacity(0.80) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                    .shadow(color: isSelected ? theme.currentTheme.primaryColor.opacity(0.3) : .clear, radius: isSelected ? 4 : 0, y: 1)
            )
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

