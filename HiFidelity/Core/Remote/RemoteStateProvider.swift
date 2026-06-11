//
//  RemoteStateProvider.swift
//  HiFidelity
//
//  Snapshots `PlaybackController.shared` into a wire-safe `RemoteState`
//  DTO. Always invoked on the main actor — `PlaybackController` exposes
//  `@Published` properties and is not an actor, so reads must occur on
//  the main thread.
//

import Foundation

enum RemoteStateProvider {
    /// Capture a snapshot of `PlaybackController.shared`. MUST be called
    /// on the main actor; the `@MainActor` annotation enforces this.
    @MainActor
    static func snapshot() -> RemoteState {
        let pc = PlaybackController.shared
        let mode: String
        switch pc.repeatMode {
        case .off: mode = "off"
        case .all: mode = "all"
        case .one: mode = "one"
        }
        // The wire `queue` is compactMap-filtered to drop tracks with nil
        // `trackId`, but `currentQueueIndex` indexes the unfiltered queue.
        // Build a side-table mapping original -> filtered index so the
        // wire pair (queue, currentQueueIndex) always describes the same
        // array — otherwise the client would highlight the wrong row.
        let unfiltered = pc.queue
        var filtered: [RemoteTrack] = []
        filtered.reserveCapacity(unfiltered.count)
        var originalToFiltered: [Int] = Array(repeating: -1, count: unfiltered.count)
        for (i, track) in unfiltered.enumerated() {
            if let dto = RemoteTrack(track) {
                originalToFiltered[i] = filtered.count
                filtered.append(dto)
            }
        }
        let originalIndex = pc.currentQueueIndex
        let mappedIndex: Int
        if filtered.isEmpty {
            mappedIndex = -1
        } else if originalIndex < 0 || originalIndex >= unfiltered.count {
            mappedIndex = -1
        } else if originalToFiltered[originalIndex] != -1 {
            mappedIndex = originalToFiltered[originalIndex]
        } else {
            // Original slot was dropped: clamp to next surviving slot, or -1
            // if none survive after it.
            var fallback = -1
            for j in (originalIndex + 1)..<unfiltered.count where originalToFiltered[j] != -1 {
                fallback = originalToFiltered[j]
                break
            }
            mappedIndex = fallback
        }
        let currentDTO = pc.currentTrack.flatMap { RemoteTrack($0) }
        let streamDTO = pc.currentStreamInfo.map { RemoteStreamInfo($0) }
        // Clamp the wire volume to [0,1] and substitute 0.7 for NaN — the
        // client only falls back to a default when the field is null, so
        // a NaN here would silently disable the slider.
        let rawVolume = pc.volume
        let clampedVolume = rawVolume.isNaN ? 0.7 : max(0.0, min(1.0, rawVolume))
        return RemoteState(
            isPlaying: pc.isPlaying,
            currentTime: pc.currentTime,
            duration: pc.duration,
            progress: pc.progress,
            volume: clampedVolume,
            isMuted: pc.isMuted,
            repeatMode: mode,
            isShuffleEnabled: pc.isShuffleEnabled,
            currentTrack: currentDTO,
            queue: filtered,
            currentQueueIndex: mappedIndex,
            stream: streamDTO
        )
    }
}
