//
//  TrackTableView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

/// Optimized table view for displaying tracks with sortable columns
/// Now uses NSTableView (AppKit) to bypass SwiftUI's 10 column limitation
struct TrackTableView: View {
    let tracks: [Track]
    @Binding var selection: Track.ID?
    @Binding var sortOrder: [KeyPathComparator<Track>]
    let onPlayTrack: (Track) -> Void
    let isCurrentTrack: (Track) -> Bool
    
    // Optional playlist context
    var playlistContext: NSTrackTableView.PlaylistContext?
    
    var body: some View {
        NSTrackTableView(
            tracks: tracks,
            selection: $selection,
            sortOrder: $sortOrder,
            onPlayTrack: onPlayTrack,
            isCurrentTrack: isCurrentTrack,
            playlistContext: playlistContext
        )
    }
}


// MARK: - Preview

#Preview {
    TrackTableView(
        tracks: [],
        selection: .constant(nil),
        sortOrder: .constant([KeyPathComparator(\Track.title)]),
        onPlayTrack: { _ in },
        isCurrentTrack: { _ in false }
    )
    .environmentObject(DatabaseManager.shared)
    .frame(width: 800, height: 600)
}

