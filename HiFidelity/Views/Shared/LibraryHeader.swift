//
//  LibraryHeader.swift
//  HiFidelity
//
//  Created by Varun Rathod

import SwiftUI

/// Unified header for library views with consistent height and styling
struct LibraryHeader: View {
    let title: String
    let count: Int
    let sortOptions: [SortOption]
    let filterOptions: [FilterOption]?
    
    @Binding var selectedSort: SortOption
    @Binding var selectedFilter: FilterOption?
    
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        HStack(spacing: 16) {
            // Count label
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Sort order toggle (ascending/descending)
            Button {
                selectedSort = SortOption(
                    id: selectedSort.id,
                    title: selectedSort.title,
                    type: selectedSort.type,
                    ascending: !selectedSort.ascending
                )
            } label: {
                Image(systemName: selectedSort.ascending ? "arrow.up" : "arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.clear)
                    )
            }
            .buttonStyle(.plain)
            
            // Sort menu - single icon with context menu
            Menu {
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
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.clear)
                    )
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            
            // Filter button
            if let filters = filterOptions, !filters.isEmpty {
                Menu {
                    ForEach(filters) { filter in
                        Button {
                            selectedFilter = selectedFilter == filter ? nil : filter
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
                        Divider()
                        Button("Clear Filter") {
                            selectedFilter = nil
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(height: 52) // Fixed height for consistency
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Models

/// Sort options for library views
struct SortOption: Identifiable, Equatable {
    let id: String
    let title: String
    let type: SortType
    var ascending: Bool
    
    enum SortType {
        case alphabetical
        case dateAdded
        case year
        case trackCount
        case albumCount
        case playCount
    }
}

/// Filter options for library views
struct FilterOption: Identifiable, Equatable {
    let id: String
    let title: String
    let predicate: String
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selectedSort = SortOption(id: "name", title: "Name", type: .alphabetical, ascending: true)
        @State private var selectedFilter: FilterOption? = nil
        
        let sortOptions = [
            SortOption(id: "name", title: "Name", type: .alphabetical, ascending: true),
            SortOption(id: "recent", title: "Recently Added", type: .dateAdded, ascending: false),
            SortOption(id: "tracks", title: "Track Count", type: .trackCount, ascending: false)
        ]
        
        let filterOptions = [
            FilterOption(id: "2020s", title: "2020s", predicate: "year >= 2020"),
            FilterOption(id: "2010s", title: "2010s", predicate: "year >= 2010 AND year < 2020")
        ]
        
        var body: some View {
            LibraryHeader(
                title: "150 albums",
                count: 150,
                sortOptions: sortOptions,
                filterOptions: filterOptions,
                selectedSort: $selectedSort,
                selectedFilter: $selectedFilter
            )
            .frame(width: 800)
        }
    }
    
    return PreviewWrapper()
}

