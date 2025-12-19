//
//  PlaylistItem.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import Foundation

/// Unified playlist item that can represent both user and smart playlists
struct PlaylistItem: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let isPinned: Bool
    let type: PlaylistType
    
    enum PlaylistType: Equatable, Hashable {
        case user(Playlist)
        case smart(SmartPlaylistType)
        
        func hash(into hasher: inout Hasher) {
            switch self {
            case .user(let playlist):
                hasher.combine("user")
                hasher.combine(playlist.id)
            case .smart(let smartType):
                hasher.combine("smart")
                hasher.combine(smartType.rawValue)
            }
        }
    }
    
    var icon: String {
        switch type {
        case .user:
            return "music.note.list"
        case .smart(let smartType):
            return smartType.icon
        }
    }
    
    var trackCount: Int {
        switch type {
        case .user(let playlist):
            return playlist.trackCount
        case .smart:
            return 0 // Will be loaded dynamically
        }
    }
    
    var artworkData: Data? {
        switch type {
        case .user(let playlist):
            return playlist.customArtworkData
        case .smart:
            return nil
        }
    }
    
    var isSmart: Bool {
        if case .smart = type {
            return true
        }
        return false
    }
    
    var createdDate: Date? {
        switch type {
        case .user(let playlist):
            return playlist.createdDate
        case .smart:
            return nil
        }
    }
    
    var modifiedDate: Date? {
        switch type {
        case .user(let playlist):
            return playlist.modifiedDate
        case .smart:
            return nil
        }
    }
    
    static func == (lhs: PlaylistItem, rhs: PlaylistItem) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Smart playlist types
enum SmartPlaylistType: String, CaseIterable {
    case favorites = "Favorites"
    case topPlayed = "Top 25 Most Played"
    case recentlyPlayed = "Recently Played"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .favorites:
            return "heart.fill"
        case .topPlayed:
            return "chart.bar.fill"
        case .recentlyPlayed:
            return "clock.fill"
        }
    }
    
    var description: String {
        switch self {
        case .favorites:
            return "Your favorite tracks"
        case .topPlayed:
            return "Your most played tracks"
        case .recentlyPlayed:
            return "Recently played tracks"
        }
    }
}

/// Playlist sort options
enum PlaylistSortOption: String, CaseIterable, Hashable {
    case name = "Name"
    case dateCreated = "Date Created"
    case dateModified = "Date Modified"
    case trackCount = "Track Count"
    
    var label: String {
        rawValue
    }
    
    var ascendingIcon: String {
        switch self {
        case .name:
            return "arrow.up"
        case .dateCreated, .dateModified:
            return "arrow.up"
        case .trackCount:
            return "arrow.up"
        }
    }
    
    var descendingIcon: String {
        switch self {
        case .name:
            return "arrow.down"
        case .dateCreated, .dateModified:
            return "arrow.down"
        case .trackCount:
            return "arrow.down"
        }
    }
}
