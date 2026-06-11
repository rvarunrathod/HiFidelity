//
//  SettingsView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Main settings view with tabbed interface
struct SettingsView: View {
    @ObservedObject var theme = AppTheme.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab: SettingsTab = .appearance
    
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            HStack {
                // Sidebar
                settingsSidebar
                    .frame(minWidth: 200, maxWidth: 200)
                
                Divider()
                
                // Content
                settingsContent
                    .frame(minWidth: 500)
            }
        }
        .frame(width: 800, height: 600)
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 32)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Sidebar
    
    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsSidebarButton(
                    theme: theme,
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }
            
            Spacer()
        }
        .padding(12)
    }
    
    // MARK: - Content
    
    @ViewBuilder
    private var settingsContent: some View {
        Group {
            switch selectedTab {
            case .appearance:
                ScrollView {
                    AppearanceSettings(theme: theme)
                        .padding(24)
                }
            case .audio:
                ScrollView {
                    AudioSettingsView()
                        .padding(24)
                }
            case .library:
                    LibrarySettings()
            case .remote:
                RemoteControlSettings()
            case .advanced:
                ScrollView {
                    AdvancedSettings()
                        .padding(24)
                }
            case .about:
                ScrollView {
                    AboutMenuView()
                        .padding(24)
                }
            }
        }
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance
    case audio
    case library
    case remote
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .audio: return "Audio"
        case .library: return "Library"
        case .remote: return "Remote Control"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .audio: return "speaker.wave.3.fill"
        case .library: return "music.note.list"
        case .remote: return "antenna.radiowaves.left.and.right"
        case .advanced: return "gearshape.2.fill"
        case .about: return "info.circle.fill"
        }
    }
}

// MARK: - Sidebar Button

private struct SettingsSidebarButton: View {
    @ObservedObject var theme = AppTheme.shared
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                
                Text(tab.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(textColor)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(backgroundColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private var iconColor: Color {
        isSelected ? theme.currentTheme.primaryColor : (isHovered ? .primary : .secondary)
    }
    
    private var textColor: Color {
        isSelected ? .primary : (isHovered ? .primary.opacity(0.9) : .secondary)
    }
    
    private var backgroundColor: Color {
        isSelected ? theme.currentTheme.primaryColor.opacity(0.15) : (isHovered ? Color(nsColor: .windowBackgroundColor) : .clear)
    }
}

#Preview {
    SettingsView()
        .environmentObject(DatabaseManager.shared)
}

