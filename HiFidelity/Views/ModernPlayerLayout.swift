//
//  ModernPlayerLayout.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Modern three-panel layout: Sidebar | Main Content | Optional Panels + Bottom Playback Bar
struct ModernPlayerLayout: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @EnvironmentObject var appCoordinator: AppCoordinator
    @StateObject private var trackInfoManager = TrackInfoManager()
    
    @State private var selectedTab: NavigationTab = .home
    @State private var selectedEntity: EntityType?
    @State private var showSettings = false
    @State private var rightPanelTab: RightPanelTab = .queue
    @AppStorage("showRightPanel") private var showRightPanel = true
    @AppStorage("showLeftSidebar") private var showLeftSidebar = true
    @State private var searchText = ""
    @State private var isSearchActive = false
    
    // Dynamic minimum width based on visible panels
    private var minimumWidth: CGFloat {
        switch (showLeftSidebar, showRightPanel) {
        case (true, true):   return 1100  // Both panels open
        case (true, false),
             (false, true):  return 900   // One panel open
        case (false, false): return 900   // No panels open (just main content)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top: App Header
            AppHeader(
                selectedTab: $selectedTab,
                searchText: $searchText,
                isSearchActive: $isSearchActive,
                showLeftSidebar: $showLeftSidebar,
                showRightPanel: $showRightPanel,
                showSettings: $showSettings
            )
            
            Divider()
            
            // Main content area with responsive layout
            ResponsiveMainLayout(
                showLeftSidebar: $showLeftSidebar,
                showRightPanel: $showRightPanel,
                                selectedTab: $selectedTab,
                selectedEntity: $selectedEntity,
                searchText: $searchText,
                isSearchActive: $isSearchActive,
                rightPanelTab: $rightPanelTab
            )
        }
        .frame(minWidth: minimumWidth, idealWidth: 1400, minHeight: 680, idealHeight: 900)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: showSettings) { _, isShowing in
            if isShowing {
                // When opening from gear icon, show appearance tab
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(
                        name: .openSettings,
                        object: SettingsTab.appearance
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsAbout)) { _ in
            // Open settings and switch to about tab
            showSettings = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(
                    name: .openSettings,
                    object: SettingsTab.about
                )
            }
        }
        .sheet(isPresented: $appCoordinator.showCreatePlaylist) {
            if let track = appCoordinator.trackForNewPlaylist {
                CreatePlaylistWithTrackView(track: track)
            } else {
                CreatePlaylistView()
            }
        }
        .environmentObject(trackInfoManager)
        .onChange(of: trackInfoManager.isVisible) { _, isVisible in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if isVisible {
                    showRightPanel = true
                    rightPanelTab = .trackInfo
                } else {
                    // Close the right panel when track info is hidden
                    if rightPanelTab == .trackInfo {
                        showRightPanel = false
                    }
                }
            }
        }
        .onChange(of: selectedTab) { _, _ in
            // Clear entity selection when switching tabs
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedEntity = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goToHome)) { _ in
            // Clear entity selection when home button is clicked
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedEntity = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowTrackInfo"))) { notification in
            // Show track info panel when requested from context menu
            if let track = notification.object as? Track {
                trackInfoManager.show(track: track)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToEntity)) { notification in
            // Navigate to entity (album or artist) when requested from context menu
            if let entity = notification.object as? EntityType {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedTab = .home  // Switch to home tab
                    selectedEntity = entity  // Set the selected entity
                }
            }
        }

    }
}

/// Enum representing the main navigation tabs in the app
enum NavigationTab: String, CaseIterable, Identifiable {
    case home
    case playlists
    case discover
    
    var id: String { rawValue }
}
// MARK: - Preview

#Preview {
    ModernPlayerLayout()
        .environmentObject(DatabaseManager.shared)
        .frame(width: 1200, height: 800)
}


