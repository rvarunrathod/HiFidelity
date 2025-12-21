//
//  AppHeader.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Top application header with logo, search, and navigation controls
struct AppHeader: View {
    @Binding var selectedTab: NavigationTab
    @Binding var searchText: String
    @Binding var isSearchActive: Bool
    @Binding var showLeftSidebar: Bool
    @Binding var showRightPanel: Bool
    @Binding var showSettings: Bool
    
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Logo and sidebar toggle
            leadingSection
            
            Spacer()
            
            // Center: Navigation and search
            centerSection
            
            Spacer()
            Spacer()
            
            // Right: Controls
            trailingSection
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 14)
        .frame(height: 68)
        .background(headerBackground)
    }
    
    // MARK: - Leading Section
    
    private var leadingSection: some View {
        HStack(spacing: 2) {
            // App logo
            Image("HiFidelity long Logo")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(theme.currentTheme.primaryColor)
                .frame(width: 140, height: 64)
            
            // Left sidebar toggle
            ToggleButton(
                icon: "sidebar.left",
                isActive: showLeftSidebar
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showLeftSidebar.toggle()
                }
            }
        }
    }
    
    // MARK: - Center Section
    
    private var centerSection: some View {
        HStack(spacing: 12) {
            // Home button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    // Always go to home and clear search/entity
                    selectedTab = .home
                    searchText = ""
                    isSearchActive = false
                    
                    // Post notification to clear entity selection
                    NotificationCenter.default.post(name: .goToHome, object: nil)
                }
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(selectedTab == .home ? .white : .secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(selectedTab == .home ? theme.currentTheme.primaryColor.opacity(0.60) : Color.primary.opacity(0.04))
                            .shadow(color: selectedTab == .home ? theme.currentTheme.primaryColor.opacity(0.3) : .clear, radius: 4, y: 1)
                    )
            }
            .buttonStyle(PlainScaleButtonStyle())
            .help("Go to Home")
            
            // Search bar
            SearchBar(
                text: $searchText,
                isActive: $isSearchActive
            )
        }
    }
    
    // MARK: - Trailing Section
    
    private var trailingSection: some View {
        HStack(spacing: 2) {
            // Right sidebar toggle
            ToggleButton(
                icon: "sidebar.right",
                isActive: showRightPanel
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    showRightPanel.toggle()
                }
            }

            // GitHub link
            GitHubButton()
            
            // Refresh library button
            RefreshButton()
                .help("Refresh Library")
            
            // Notifications
            NotificationTray()
            
            // Settings
            SettingsButton(action: { showSettings = true })
        }
    }
    
    // MARK: - Background
    
    private var headerBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.03)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1),
                alignment: .bottom
            )
    }
}

// MARK: - Subcomponents

/// Refresh library button - clears cache and reloads all views
private struct RefreshButton: View {
    @State private var isRefreshing = false
    @State private var isHovered = false
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                isRefreshing = true
            }
            performRefresh()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing
                        ? .linear(duration: 1.0).repeatForever(autoreverses: false)
                        : .default,
                    value: isRefreshing
                )
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(isRefreshing ? theme.currentTheme.primaryColor : .secondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isRefreshing ? theme.currentTheme.primaryColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                        .shadow(color: isRefreshing ? theme.currentTheme.primaryColor.opacity(0.15) : .clear, radius: 3, y: 1)
                )
                .scaleEffect(isHovered && !isRefreshing ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func performRefresh() {
        Task {
            // Notify views to reload
            await MainActor.run {
                NotificationCenter.default.post(name: .refreshLibraryData, object: nil)
                NotificationManager.shared.addMessage(.info, "Library refreshed")
            }
            
            // Stop animation after reload
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                withAnimation {
                    isRefreshing = false
                }
            }
        }
    }
}

/// Reusable toggle button for sidebar controls
private struct ToggleButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(isActive ? theme.currentTheme.primaryColor : .secondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isActive ? theme.currentTheme.primaryColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                        .shadow(color: isActive ? theme.currentTheme.primaryColor.opacity(0.15) : .clear, radius: 3, y: 1)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Enhanced GitHub button with hover effects
private struct GitHubButton: View {
    @State private var isHovered = false
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        Button {
            if let url = URL(string: About.appWebsite) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Image("github-icon")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 17, height: 17)
                .foregroundColor(isHovered ? .white : theme.currentTheme.primaryColor)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isHovered ? theme.currentTheme.primaryColor : theme.currentTheme.primaryColor.opacity(0.12))
                        .shadow(color: theme.currentTheme.primaryColor.opacity(isHovered ? 0.3 : 0.15), radius: isHovered ? 6 : 3, y: isHovered ? 2 : 1)
                )
                .scaleEffect(isHovered ? 1.06 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("View on GitHub")
    }
}

/// Settings button with hover effects
private struct SettingsButton: View {
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Settings")
    }
}

/// Centralized search bar component
private struct SearchBar: View {
    @Binding var text: String
    @Binding var isActive: Bool
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isFocused ? .primary : .secondary)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            
            TextField("What do you want to play?", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFocused)
                .onSubmit {
                    if !text.isEmpty {
                        isActive = true
                    }
                }
            
            if !text.isEmpty {
                Button {
                    text = ""
                    isActive = false
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Color.primary.opacity(isFocused ? 0.1 : 0), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(isFocused ? 0.08 : 0.03), radius: isFocused ? 8 : 4, y: 2)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                isActive = false
            } else if newValue.count >= 2 {
                isActive = true
            }
        }
        // Listen for global focus dismissal
        .onReceive(NotificationCenter.default.publisher(for: .dismissAllFocus)) { _ in
            isFocused = false
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab: NavigationTab = .home
        @State private var searchText = ""
        @State private var isSearchActive = false
        @State private var showLeftSidebar = true
        @State private var showRightPanel = true
        @State private var showSettings = false
        
        var body: some View {
            AppHeader(
                selectedTab: $selectedTab,
                searchText: $searchText,
                isSearchActive: $isSearchActive,
                showLeftSidebar: $showLeftSidebar,
                showRightPanel: $showRightPanel,
                showSettings: $showSettings
            )
            .frame(width: 1200, height: 60)
        }
    }
    
    return PreviewWrapper()
}

