//
//  GenresTabView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Genres tab view displaying all genres in a grid layout
struct GenresTabView: View {
    @Binding var selectedEntity: EntityType?
    let isVisible: Bool
    
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    
    @State private var genres: [Genre] = []
    @State private var filteredGenres: [Genre] = []
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var selectedSort = SortOption(id: "name", title: "Name", type: .alphabetical, ascending: true)
    @State private var selectedFilter: FilterOption? = nil
    
    init(selectedEntity: Binding<EntityType?>, isVisible: Bool = true) {
        self._selectedEntity = selectedEntity
        self.isVisible = isVisible
    }
    
    private let sortOptions = [
        SortOption(id: "name", title: "Name", type: .alphabetical, ascending: true),
        SortOption(id: "tracks", title: "Track Count", type: .trackCount, ascending: false)
    ]
    
    private let filterOptions = [
        FilterOption(id: "popular", title: "Popular (20+ tracks)", predicate: "trackCount >= 20"),
        FilterOption(id: "medium", title: "Medium (10+ tracks)", predicate: "trackCount >= 10")
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            
            Divider()
            
            // Content
            if isLoading {
                loadingView
            } else if filteredGenres.isEmpty {
                if genres.isEmpty {
                    emptyStateView(icon: "guitars", message: "No genres in library")
                } else {
                    emptyStateView(icon: "line.3.horizontal.decrease.circle", message: "No genres match your filter")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)
                    ], spacing: 20) {
                        ForEach(filteredGenres) { genre in
                            GenreCard(genre: genre) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedEntity = .genre(genre)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue && !hasLoadedOnce {
                Task {
                    await loadGenres()
                    hasLoadedOnce = true
                }
            }
        }
        .onAppear {
            if isVisible && !hasLoadedOnce {
                Task {
                    await loadGenres()
                    hasLoadedOnce = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshLibraryData)) { _ in
            Task {
                await loadGenres()
            }
        }
        .onChange(of: selectedSort) { _, _ in
            applyFiltersAndSort()
        }
        .onChange(of: selectedFilter) { _, _ in
            applyFiltersAndSort()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(theme.currentTheme.primaryColor)
                
                Text("Loading genres...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 16) {
            // Count label
            Text("\(filteredGenres.count) genres")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Sort and Filter dropdown
            GenreOptionsDropdown(
                selectedSort: $selectedSort,
                selectedFilter: $selectedFilter,
                sortOptions: sortOptions,
                filterOptions: filterOptions
            )
            .frame(width: 32)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(height: 46)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func loadGenres() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            genres = try await databaseManager.getAllGenres()
            applyFiltersAndSort()
        } catch {
            Logger.error("Failed to load genres: \(error)")
        }
    }
    
    private func applyFiltersAndSort() {
        var result = genres
        
        // Apply track count filters
        if let filter = selectedFilter {
            switch filter.id {
            case "popular":
                result = result.filter { $0.trackCount >= 20 }
            case "medium":
                result = result.filter { $0.trackCount >= 10 }
            default:
                break
            }
        }
        
        // Apply sort
        switch selectedSort.type {
        case .alphabetical:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .trackCount:
            result.sort { $0.trackCount > $1.trackCount }
        default:
            break
        }
        
        if !selectedSort.ascending {
            result.reverse()
        }
        
        filteredGenres = result
    }
}

// MARK: - Genre Options Dropdown

private struct GenreOptionsDropdown: View {
    @Binding var selectedSort: SortOption
    @Binding var selectedFilter: FilterOption?
    let sortOptions: [SortOption]
    let filterOptions: [FilterOption]
    
    @ObservedObject private var theme = AppTheme.shared
    
    var body: some View {
        Menu {
            Section("Sort by") {
                ForEach(sortOptions) { option in
                    Button {
                        selectedSort = option
                    } label: {
                        HStack {
                            Text(option.title)
                            if selectedSort.id == option.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            Section("Sort order") {
                Button {
                    selectedSort = SortOption(
                        id: selectedSort.id,
                        title: selectedSort.title,
                        type: selectedSort.type,
                        ascending: true
                    )
                } label: {
                    HStack {
                        Text("Ascending")
                        if selectedSort.ascending {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                
                Button {
                    selectedSort = SortOption(
                        id: selectedSort.id,
                        title: selectedSort.title,
                        type: selectedSort.type,
                        ascending: false
                    )
                } label: {
                    HStack {
                        Text("Descending")
                        if !selectedSort.ascending {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            
            Divider()
            
            Section("Filter") {
                ForEach(filterOptions) { filter in
                    Button {
                        selectedFilter = (selectedFilter == filter) ? nil : filter
                    } label: {
                        HStack {
                            Text(filter.title)
                            if selectedFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                
                if selectedFilter != nil {
                    Button("Clear Filter") {
                        selectedFilter = nil
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 16, weight: .medium))
                if selectedFilter != nil {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(theme.currentTheme.primaryColor)
                }
            }
            .foregroundColor(selectedFilter != nil ? theme.currentTheme.primaryColor : .secondary)
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(selectedFilter != nil ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}

