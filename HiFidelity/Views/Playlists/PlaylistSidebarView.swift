//
//  PlaylistSidebarView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI
import AppKit

/// Playlist sidebar showing pinned and user playlists
struct PlaylistSidebarView: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    @Binding var selectedTab: NavigationTab
    @Binding var selectedEntity: EntityType?
    
    @StateObject private var viewModel = PlaylistSidebarViewModel()
    @State private var searchText = ""
    @State private var showCreatePlaylist = false
    @AppStorage("playlistSortOption") private var sortOptionId: String = "name"
    @AppStorage("playlistSortAscending") private var sortAscending = true
    @State private var sortOption: PlaylistSortOption = .name
    @State private var isSelectionMode = false
    @State private var selectedPlaylistIds: Set<String> = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Playlists header
            playlistsHeader
            
            Divider()
                .opacity(0) // invisible
            
            // Search bar
            searchBar
            
            Divider()
            
            // Playlist items
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 90)
            } else if viewModel.allPlaylists.isEmpty {
                emptyStateView
                    .padding(.bottom, 90)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        // Smart Playlists Section
                        if !viewModel.smartPlaylists.isEmpty {
                            Section {
                                ForEach(viewModel.smartPlaylists) { playlist in
                                    playlistRow(playlist)
                                }
                            } header: {
                                sectionHeader(title: "Smart Playlists")
                            }
                        }
                        
                        // Pinned Playlists Section
                        if !viewModel.pinnedPlaylists.isEmpty {
                            Section {
                                ForEach(viewModel.pinnedPlaylists) { playlist in
                                    playlistRow(playlist)
                                }
                            } header: {
                                sectionHeader(title: "Pinned")
                            }
                        }
                        
                        // All Playlists Section
                        if !viewModel.userPlaylists.isEmpty {
                            Section {
                                ForEach(viewModel.userPlaylists) { playlist in
                                    playlistRow(playlist)
                                }
                            } header: {
                                sectionHeader(title: "Playlists")
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .padding(.bottom, 90)
            }
        }
        .background(Color.black.opacity(0.02))
        .task {
            await viewModel.loadPlaylists()
        }
        .onAppear {
            // Restore saved sort option
            if let savedOption = PlaylistSortOption(rawValue: sortOptionId) {
                sortOption = savedOption
            }
            // Apply initial sort
            viewModel.sortPlaylists(by: sortOption, ascending: sortAscending)
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.filterPlaylists(query: newValue)
        }
        .onChange(of: sortOption) { _, newOption in
            sortOptionId = newOption.rawValue
            viewModel.sortPlaylists(by: sortOption, ascending: sortAscending)
        }
        .onChange(of: sortAscending) { _, _ in
            viewModel.sortPlaylists(by: sortOption, ascending: sortAscending)
        }
        .sheet(isPresented: $showCreatePlaylist) {
            CreatePlaylistView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            Task {
                await viewModel.loadPlaylists()
                viewModel.sortPlaylists(by: sortOption, ascending: sortAscending)
            }
        }
    }
    
    // MARK: - Header
    
    private var playlistsHeader: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                // Selection mode UI
                Button {
                    isSelectionMode = false
                    selectedPlaylistIds.removeAll()
                } label: {
                    Text("Cancel")
                        .font(AppFonts.labelMedium)
                        .foregroundColor(theme.currentTheme.primaryColor)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("\(selectedPlaylistIds.count) selected")
                    .font(AppFonts.labelMedium)
                    .foregroundColor(.secondary)
                
                Button {
                    deleteSelectedPlaylists()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(selectedPlaylistIds.isEmpty)
            } else {
                // Normal mode UI
                Image(systemName: "music.note.list")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
                
                Text("Playlists")
                    .font(AppFonts.sidebarHeader)
                
                Spacer()
                
                // Selection mode toggle button
                SelectionModeButton(action: { 
                    isSelectionMode = true 
                })
                
                // Create button
                CreatePlaylistButton(action: { showCreatePlaylist = true })
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 52)
    }

    private struct SortMenuButton: View {
        @Binding var sortOption: PlaylistSortOption
        @Binding var sortAscending: Bool
        @State private var isHovered = false
        @ObservedObject var theme = AppTheme.shared
        
        var body: some View {
            Menu {
                // Sort options
                ForEach(PlaylistSortOption.allCases, id: \.self) { option in
                    Button {
                        if sortOption == option {
                            sortAscending.toggle()
                        } else {
                            sortOption = option
                            sortAscending = true
                        }
                    } label: {
                        HStack {
                            Text(option.label)
                            Spacer()
                            if sortOption == option {
                                Image(systemName: sortAscending ? option.ascendingIcon : option.descendingIcon)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovered ? theme.currentTheme.primaryColor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isHovered ? theme.currentTheme.primaryColor.opacity(0.12) : Color.clear)
                    )
                    .scaleEffect(isHovered ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            }
            .frame(width: 32)
            .menuStyle(.borderlessButton)
            .onHover { hovering in
                isHovered = hovering
            }
            .help("Sort Playlists")
        }
    }
    
    private struct CreatePlaylistButton: View {
        let action: () -> Void
        @State private var isHovered = false
        @ObservedObject var theme = AppTheme.shared
        
        var body: some View {
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isHovered ? .white : theme.currentTheme.primaryColor)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isHovered ? theme.currentTheme.primaryColor : theme.currentTheme.primaryColor.opacity(0.12))
                    )
                    .scaleEffect(isHovered ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .help("Create New Playlist")
        }
    }
    
    private struct SelectionModeButton: View {
        let action: () -> Void
        @State private var isHovered = false
        @ObservedObject var theme = AppTheme.shared
        
        var body: some View {
            Button(action: action) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovered ? theme.currentTheme.primaryColor : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(isHovered ? theme.currentTheme.primaryColor.opacity(0.12) : Color.clear)
                    )
                    .scaleEffect(isHovered ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
            }
            .help("Select Playlists")
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            
            TextField("Search playlists", text: $searchText)
                .textFieldStyle(.plain)
                .font(AppFonts.labelMedium)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            
            // Sort button
            SortMenuButton(
                sortOption: $sortOption,
                sortAscending: $sortAscending
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: 46)
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }
    
    // MARK: - Playlist Row
    
    private func playlistRow(_ playlist: PlaylistItem) -> some View {
        let isSelected = selectedPlaylistIds.contains(playlist.id)
        let canBeDeleted = if case .user = playlist.type { true } else { false }
        
        return HStack(spacing: 12) {
            // Selection checkbox (only for user playlists in selection mode)
            if isSelectionMode && canBeDeleted {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? theme.currentTheme.primaryColor : .secondary)
            }
            
            // Artwork
            artworkView(for: playlist)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(AppFonts.sidebarItem)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if playlist.isPinned {
                        Image(systemName: "pin.fill")
                            .font(AppFonts.captionSmall)
                            .foregroundColor(theme.currentTheme.primaryColor)
                    }
                    
                    if case .smart(let smartType) = playlist.type {
                        Text(smartType.description)
                            .font(AppFonts.captionMedium)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Playlist • \(playlist.trackCount) \(playlist.trackCount == 1 ? "song" : "songs")")
                            .font(AppFonts.captionMedium)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPlaylistSelected(playlist) ? theme.currentTheme.primaryColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode && canBeDeleted {
                // Toggle selection
                if isSelected {
                    selectedPlaylistIds.remove(playlist.id)
                } else {
                    selectedPlaylistIds.insert(playlist.id)
                }
            } else if !isSelectionMode {
                // Normal navigation
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedEntity = .playlist(playlist)
                }
            }
        }
        .if(!isSelectionMode) { view in
            view.contextMenu {
                playlistContextMenu(playlist)
            }
        }
    }


    
    // MARK: - Artwork View
    
    private func artworkView(for playlist: PlaylistItem) -> some View {
        Group {
            if let imageData = playlist.artworkData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.currentTheme.primaryColor.opacity(0.4),
                                theme.currentTheme.primaryColor.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: playlist.icon)
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isPlaylistSelected(_ playlist: PlaylistItem) -> Bool {
        guard case .playlist(let selectedPlaylist) = selectedEntity else {
            return false
        }
        return selectedPlaylist.id == playlist.id
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private func playlistContextMenu(_ playlist: PlaylistItem) -> some View {
        if case .user(let playlistModel) = playlist.type {
            Button {
                Task {
                    await viewModel.togglePin(playlist: playlist)
                }
            } label: {
                Label(playlist.isPinned ? "Unpin" : "Pin to Top", systemImage: playlist.isPinned ? "pin.slash" : "pin")
            }
            
            Divider()
            
            Button {
                exportPlaylistToM3U(playlist: playlistModel)
            } label: {
                Label("Export as M3U", systemImage: "square.and.arrow.up")
            }
            
            Divider()
            
            Button {
                isSelectionMode = true
                selectedPlaylistIds.insert(playlist.id)
            } label: {
                Label("Select Multiple", systemImage: "checkmark.circle")
            }
            
            Divider()
            
            Button(role: .destructive) {
                Task {
                    try await databaseManager.deletePlaylist(playlist)
                }
            } label: {
                Label("Delete Playlist", systemImage: "trash")
            }
        }
    }

    
    private func deleteSelectedPlaylists() {
        Task {
            for playlistId in selectedPlaylistIds {
                // Find the playlist in the viewModel
                if let playlist = viewModel.allPlaylists.first(where: { $0.id == playlistId }),
                   case .user = playlist.type {
                    do {
                        try await databaseManager.deletePlaylist(playlist)
                    } catch {
                        Logger.error("Failed to delete playlist \(playlist.name): \(error)")
                    }
                }
            }
            // Exit selection mode and clear selections
            isSelectionMode = false
            selectedPlaylistIds.removeAll()
        }
    }
    
    private func exportPlaylistToM3U(playlist: Playlist) {
        guard let playlistId = playlist.id else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!]
        panel.nameFieldStringValue = "\(playlist.name).m3u"
        panel.message = "Export playlist to M3U file"
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    try await databaseManager.exportPlaylistToM3U(
                        playlistId: playlistId,
                        saveURL: url,
                        useRelativePaths: false
                    )
                    
                    Logger.info("Successfully exported playlist '\(playlist.name)' to \(url.path)")
                    
                    // Show success notification
                    await MainActor.run {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } catch {
                    Logger.error("Failed to export playlist: \(error)")
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text(searchText.isEmpty ? "No playlists yet\nCreate your first playlist" : "No playlists found")
                .font(AppFonts.labelMedium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Playlist Sidebar ViewModel

@MainActor
final class PlaylistSidebarViewModel: ObservableObject {
    @Published var allPlaylists: [PlaylistItem] = []
    @Published var smartPlaylists: [PlaylistItem] = []
    @Published var pinnedPlaylists: [PlaylistItem] = []
    @Published var userPlaylists: [PlaylistItem] = []
    @Published var isLoading = false
    
    private let database = DatabaseManager.shared
    
    func loadPlaylists() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Load smart playlists
            smartPlaylists = SmartPlaylistType.allCases.map { type in
                PlaylistItem(
                    id: "smart_\(type.rawValue)",
                    name: type.rawValue,
                    isPinned: false,
                    type: .smart(type)
                )
            }
            
            // Load user playlists from cache for better performance
            let userPlaylistModels = try await DatabaseCache.shared.getAllPlaylists()
            let userPlaylistItems = userPlaylistModels.map { playlist in
                PlaylistItem(
                    id: "user_\(playlist.id ?? 0)",
                    name: playlist.name,
                    isPinned: playlist.isFavorite,
                    type: .user(playlist)
                )
            }
            
            // Separate pinned and regular playlists
            pinnedPlaylists = userPlaylistItems.filter { $0.isPinned }
            userPlaylists = userPlaylistItems.filter { !$0.isPinned }
            
            allPlaylists = smartPlaylists + userPlaylistItems
            
            Logger.debug("Loaded \(smartPlaylists.count) smart playlists, \(userPlaylistItems.count) user playlists from cache")
        } catch {
            Logger.error("Failed to load playlists: \(error)")
        }
    }
    
    func filterPlaylists(query: String) {
        guard !query.isEmpty else {
            // Reset filtering by reloading
            Task { await loadPlaylists() }
            return
        }
        
        let lowercased = query.lowercased()
        
        smartPlaylists = smartPlaylists.filter { $0.name.lowercased().contains(lowercased) }
        pinnedPlaylists = pinnedPlaylists.filter { $0.name.lowercased().contains(lowercased) }
        userPlaylists = userPlaylists.filter { $0.name.lowercased().contains(lowercased) }
    }
    
    func sortPlaylists(by option: PlaylistSortOption, ascending: Bool) {
        let sortFunction: (PlaylistItem, PlaylistItem) -> Bool = { item1, item2 in
            let result: Bool
            
            switch option {
            case .name:
                result = item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
            case .dateCreated:
                let date1 = item1.createdDate ?? Date.distantPast
                let date2 = item2.createdDate ?? Date.distantPast
                result = date1 < date2
            case .dateModified:
                let date1 = item1.modifiedDate ?? Date.distantPast
                let date2 = item2.modifiedDate ?? Date.distantPast
                result = date1 < date2
            case .trackCount:
                result = item1.trackCount < item2.trackCount
            }
            
            return ascending ? result : !result
        }
        
        pinnedPlaylists.sort(by: sortFunction)
        userPlaylists.sort(by: sortFunction)
    }
    
    func togglePin(playlist: PlaylistItem) async {
        guard case .user(var playlistModel) = playlist.type else { return }
        
        do {
            playlistModel.isFavorite.toggle()
            try await database.updatePlaylist(playlistModel)
            await loadPlaylists()
        } catch {
            Logger.error("Failed to toggle pin: \(error)")
        }
    }
}


// MARK: - View Extension

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedTab: NavigationTab = .home
        @State private var selectedEntity: EntityType?
        
        var body: some View {
            PlaylistSidebarView(
                selectedTab: $selectedTab,
                selectedEntity: $selectedEntity
            )
            .environmentObject(DatabaseManager.shared)
            .frame(width: 280, height: 800)
        }
    }
    
    return PreviewWrapper()
}


