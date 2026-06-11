//
//  RemoteState.swift
//  HiFidelity
//
//  DTOs for the HTTP remote-control read endpoints. Track is NEVER encoded
//  directly — `RemoteTrack(_ t: Track)` enumerates fields explicitly so
//  `Track.url` (a security-scoped path) can never leak across the wire.
//

import Foundation

/// Snapshot of `PlaybackController.shared` for `GET /state`.
struct RemoteState: Encodable {
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double
    let progress: Double
    let volume: Double
    let isMuted: Bool
    let repeatMode: String          // "off" | "all" | "one"
    let isShuffleEnabled: Bool
    let currentTrack: RemoteTrack?
    let queue: [RemoteTrack]
    let currentQueueIndex: Int
    let stream: RemoteStreamInfo?
}

/// Public-safe representation of a `Track`. Constructed only via the
/// `init(_:)` initializer below, which performs an explicit per-field copy
/// and never reads `Track.url`.
struct RemoteTrack: Encodable {
    let trackId: Int64
    let title: String
    let artist: String
    let album: String
    let albumArtist: String?
    let composer: String?
    let genre: String?
    let year: String?
    let duration: Double
    let isFavorite: Bool
    let trackNumber: Int?
    let discNumber: Int?
    let albumId: Int64?
    let artistId: Int64?
    let genreId: Int64?
    let format: String?
    let codec: String?
    let bitrate: Int?
    let sampleRate: Int?
    let bitDepth: Int?
    let channels: Int?

    /// Build a wire DTO from a database-resident `Track`. Returns `nil` if
    /// the track has no `trackId` (i.e. has not yet been persisted) — such
    /// tracks have no stable identifier and cannot be addressed by a remote
    /// client.
    init?(_ t: Track) {
        guard let id = t.trackId else { return nil }
        self.trackId = id
        self.title = t.title
        self.artist = t.artist
        self.album = t.album
        self.albumArtist = t.albumArtist
        self.composer = t.composer.isEmpty ? nil : t.composer
        self.genre = t.genre.isEmpty ? nil : t.genre
        self.year = t.year.isEmpty ? nil : t.year
        self.duration = t.duration
        self.isFavorite = t.isFavorite
        self.trackNumber = t.trackNumber
        self.discNumber = t.discNumber
        self.albumId = t.albumId
        self.artistId = t.artistId
        self.genreId = t.genreId
        self.format = t.format.isEmpty ? nil : t.format
        self.codec = t.codec
        self.bitrate = t.bitrate
        self.sampleRate = t.sampleRate
        self.bitDepth = t.bitDepth
        self.channels = t.channels
        // INVARIANT: t.url is intentionally NEVER read here.
    }
}

/// Mirror of `BASSStreamInfo` for the wire. The struct does not carry a
/// codec field — codec/format come from `Track.codec`/`Track.format`.
struct RemoteStreamInfo: Encodable {
    let frequency: Int
    let channels: Int
    let bitrate: Int
    let bitDepth: Int

    init(_ info: BASSStreamInfo) {
        self.frequency = info.frequency
        self.channels = info.channels
        self.bitrate = info.bitrate
        self.bitDepth = info.bitDepth
    }
}
