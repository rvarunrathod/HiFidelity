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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(headerBackground)
    }
    
    // MARK: - Leading Section
    
    private var leadingSection: some View {
        HStack(spacing: 24) {
            // App logo
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                theme.currentTheme.primaryColor,
                                theme.currentTheme.primaryColor.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("HiFidelity")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            // Left sidebar toggle
            ToggleButton(
                icon: "sidebar.left",
                isActive: showLeftSidebar
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLeftSidebar.toggle()
                }
            }
        }
    }
    
    // MARK: - Center Section
    
    private var centerSection: some View {
        HStack(spacing: 10) {
            // Home button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Always go to home and clear search/entity
                    selectedTab = .home
                    searchText = ""
                    isSearchActive = false
                    
                    // Post notification to clear entity selection
                    NotificationCenter.default.post(name: .goToHome, object: nil)
                }
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(selectedTab == .home ? theme.currentTheme.primaryColor : .secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(selectedTab == .home ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
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
        HStack(spacing: 4) {
            // Right sidebar toggle
            ToggleButton(
                icon: "sidebar.right",
                isActive: showRightPanel
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRightPanel.toggle()
                }
            }
            
            // Refresh library button
            RefreshButton()
            
            // Notifications
            NotificationTray()
            
            // Settings
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.clear))
            }
            .buttonStyle(PlainHoverButtonStyle())
        }
    }
    
    // MARK: - Background
    
    private var headerBackground: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(height: 1),
                alignment: .bottom
            )
    }
}

// MARK: - Subcomponents

/// Refresh library button - clears cache and reloads all views
private struct RefreshButton: View {
    @State private var isRefreshing = false
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.6)) {
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
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isRefreshing ? theme.currentTheme.primaryColor : .secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isRefreshing ? theme.currentTheme.primaryColor.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(PlainHoverButtonStyle())
        .disabled(isRefreshing)
        .help("Refresh library")
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
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(isActive ? theme.currentTheme.primaryColor : .secondary)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isActive ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(PlainHoverButtonStyle())
    }
}

/// Centralized search bar component
private struct SearchBar: View {
    @Binding var text: String
    @Binding var isActive: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
            
            TextField("What do you want to play?", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onSubmit {
                    if !text.isEmpty {
                        isActive = true
                    }
                }
            
            if !text.isEmpty {
                Button {
                    text = ""
                    isActive = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                isActive = false
            } else if newValue.count >= 2 {
                isActive = true
            }
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

