//
//  HomeView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Main content view with tabs for Tracks, Albums, Artists, and Genres
struct HomeView: View {
    @Binding var selectedEntity: EntityType?
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    
    @AppStorage("selectedLibraryTab") private var selectedLibraryTab: LibraryTab = .tracks
    
    var body: some View {
        VStack(spacing: 0) {
            // Library tabs
            libraryTabsHeader
            
            Divider()
            
            // Content based on selected tab
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
    
    init(selectedEntity: Binding<EntityType?> = .constant(nil)) {
        self._selectedEntity = selectedEntity
    }
    
    // MARK: - Library Tabs Header
    
    private var libraryTabsHeader: some View {
        HStack(spacing: 6) {
            ForEach(LibraryTab.allCases) { tab in
                LibraryTabButton(
                    title: tab.title,
                    icon: tab.icon,
                    isSelected: selectedLibraryTab == tab
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedLibraryTab = tab
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(height: 52)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.04))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        // Use ZStack with opacity to keep all views alive but show only the selected one
        ZStack {
            TracksTabView(isVisible: selectedLibraryTab == .tracks)
                .opacity(selectedLibraryTab == .tracks ? 1 : 0)
                .zIndex(selectedLibraryTab == .tracks ? 1 : 0)
            
            AlbumsTabView(selectedEntity: $selectedEntity, isVisible: selectedLibraryTab == .albums)
                .opacity(selectedLibraryTab == .albums ? 1 : 0)
                .zIndex(selectedLibraryTab == .albums ? 1 : 0)
            
            ArtistsTabView(selectedEntity: $selectedEntity, isVisible: selectedLibraryTab == .artists)
                .opacity(selectedLibraryTab == .artists ? 1 : 0)
                .zIndex(selectedLibraryTab == .artists ? 1 : 0)
            
            GenresTabView(selectedEntity: $selectedEntity, isVisible: selectedLibraryTab == .genres)
                .opacity(selectedLibraryTab == .genres ? 1 : 0)
                .zIndex(selectedLibraryTab == .genres ? 1 : 0)
        }
    }
}

// MARK: - Library Tab Enum

enum LibraryTab: String, CaseIterable, Identifiable {
    case tracks = "Tracks"
    case albums = "Albums"
    case artists = "Artists"
    case genres = "Genres"
    
    var id: String { rawValue }
    
    var title: String { rawValue }
    
    var icon: String {
        switch self {
        case .tracks: return "music.note"
        case .albums: return "square.stack"
        case .artists: return "person.2"
        case .genres: return "guitars"
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environmentObject(DatabaseManager.shared)
        .frame(width: 600, height: 800)
}

