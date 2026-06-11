//
//  RemoteBrowseHandlers.swift
//  HiFidelity
//
//  Read-only library browse routes (GET) and three queue-from-browse
//  POST routes that bridge browse → playback. Read handlers run off
//  main on the FlyingFox executor; the three POST handlers hop to
//  MainActor.run before invoking the queue mutators.
//

import Foundation
import FlyingFox
import GRDB

// MARK: - Browse DTOs
//
// Wire DTOs for the browse endpoints. All artwork blobs are dropped —
// remote clients fetch artwork separately via /artwork/:trackId with
// the persistent ETag-driven cache.

/// Page wrapper for /tracks responses.
struct RemoteTracksPage: Encodable {
    let tracks: [RemoteTrack]
    let total: Int
    let limit: Int
    let offset: Int
}

/// Page wrapper for /albums responses.
struct RemoteAlbum: Encodable {
    let id: Int64
    let title: String
    let albumArtist: String?
    let year: String?
    let trackCount: Int
    let totalDuration: Double
    let releaseType: String?

    init?(_ a: Album) {
        guard let aid = a.id else { return nil }
        self.id = aid
        self.title = a.title
        self.albumArtist = a.albumArtist
        self.year = a.year
        self.trackCount = a.trackCount
        self.totalDuration = a.totalDuration
        self.releaseType = a.releaseType
        // INVARIANT: a.artworkData is intentionally never read here.
    }
}

struct RemoteArtist: Encodable {
    let id: Int64
    let name: String
    let trackCount: Int
    let albumCount: Int

    init?(_ a: Artist) {
        guard let aid = a.id else { return nil }
        self.id = aid
        self.name = a.name
        self.trackCount = a.trackCount
        self.albumCount = a.albumCount
        // INVARIANT: a.artworkData is intentionally never read here.
    }
}

struct RemotePlaylist: Encodable {
    let id: Int64
    let name: String
    let description: String?
    let trackCount: Int
    let totalDuration: Double
    let isFavorite: Bool
    let isSmart: Bool
    let playCount: Int

    init?(_ p: Playlist) {
        guard let pid = p.id else { return nil }
        self.id = pid
        self.name = p.name
        self.description = p.description
        self.trackCount = p.trackCount
        self.totalDuration = p.totalDuration
        self.isFavorite = p.isFavorite
        self.isSmart = p.isSmart
        self.playCount = p.playCount
        // INVARIANT: p.customArtworkData is intentionally never read here.
    }
}

extension RemoteControlServer {
    /// Register the M4 browse + queue-from-browse routes on the server.
    func registerBrowseRoutes(on server: HTTPServer) async {
        await registerListRoutes(on: server)
        await registerEntityTrackRoutes(on: server)
        await registerQueueFromBrowseRoutes(on: server)
    }

    // MARK: - List endpoints

    private func registerListRoutes(on server: HTTPServer) async {
        // GET /tracks?limit=&offset=&q=
        await server.appendRoute("GET /tracks") { request in
            let limit = clampLimit(request.query.first(where: { $0.name == "limit" })?.value, fallback: 100, max: 10_000)
            let offset = max(0, Int(request.query.first(where: { $0.name == "offset" })?.value ?? "") ?? 0)
            let q = request.query.first(where: { $0.name == "q" })?.value
            do {
                if let q, !q.isEmpty {
                    // searchTracks doesn't take an offset, so fetch up to
                    // `offset + limit` weighted results and slice the page
                    // out in memory. `total` reflects the real match count
                    // up to the search ceiling so the client can paginate.
                    let ceiling = max(1, min(offset + limit, 10_000))
                    let allMatches = try await DatabaseManager.shared.searchTracks(query: q, limit: ceiling)
                    let allDTOs = allMatches.compactMap { RemoteTrack($0) }
                    let lower = min(offset, allDTOs.count)
                    let upper = min(lower + limit, allDTOs.count)
                    let page = Array(allDTOs[lower..<upper])
                    return jsonResponse(RemoteTracksPage(tracks: page, total: allDTOs.count, limit: limit, offset: offset))
                }
                let (page, total) = try await fetchTracksPage(limit: limit, offset: offset)
                return jsonResponse(RemoteTracksPage(tracks: page, total: total, limit: limit, offset: offset))
            } catch {
                Logger.error("RemoteControlServer /tracks failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }

        // GET /albums?limit=&offset=&q=
        await server.appendRoute("GET /albums") { request in
            let limit = clampLimit(request.query.first(where: { $0.name == "limit" })?.value, fallback: 100, max: 10_000)
            let offset = max(0, Int(request.query.first(where: { $0.name == "offset" })?.value ?? "") ?? 0)
            let q = request.query.first(where: { $0.name == "q" })?.value
            do {
                let albums: [Album]
                if let q, !q.isEmpty {
                    // searchAlbums doesn't take an offset — paginate the
                    // ranked result list in memory.
                    let ceiling = max(1, min(offset + limit, 10_000))
                    let all = try await DatabaseManager.shared.searchAlbums(query: q, limit: ceiling)
                    let lower = min(offset, all.count)
                    let upper = min(lower + limit, all.count)
                    albums = Array(all[lower..<upper])
                } else {
                    albums = try await DatabaseManager.shared.dbQueue.read { db -> [Album] in
                        try Album
                            .order(Album.Columns.sortName)
                            .limit(limit, offset: offset)
                            .fetchAll(db)
                    }
                }
                let dtos = albums.compactMap { RemoteAlbum($0) }
                return jsonResponse(dtos)
            } catch {
                Logger.error("RemoteControlServer /albums failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }

        // GET /artists?limit=&offset=&q=
        await server.appendRoute("GET /artists") { request in
            let limit = clampLimit(request.query.first(where: { $0.name == "limit" })?.value, fallback: 100, max: 10_000)
            let offset = max(0, Int(request.query.first(where: { $0.name == "offset" })?.value ?? "") ?? 0)
            let q = request.query.first(where: { $0.name == "q" })?.value
            do {
                let artists: [Artist]
                if let q, !q.isEmpty {
                    // searchArtists doesn't take an offset — paginate the
                    // ranked result list in memory.
                    let ceiling = max(1, min(offset + limit, 10_000))
                    let all = try await DatabaseManager.shared.searchArtists(query: q, limit: ceiling)
                    let lower = min(offset, all.count)
                    let upper = min(lower + limit, all.count)
                    artists = Array(all[lower..<upper])
                } else {
                    artists = try await DatabaseManager.shared.dbQueue.read { db -> [Artist] in
                        try Artist
                            .order(Artist.Columns.sortName)
                            .limit(limit, offset: offset)
                            .fetchAll(db)
                    }
                }
                let dtos = artists.compactMap { RemoteArtist($0) }
                return jsonResponse(dtos)
            } catch {
                Logger.error("RemoteControlServer /artists failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }

        // GET /playlists
        await server.appendRoute("GET /playlists") { _ in
            do {
                let playlists = try await DatabaseManager.shared.dbQueue.read { db -> [Playlist] in
                    try Playlist
                        .order(Playlist.Columns.sortOrder, Playlist.Columns.name)
                        .fetchAll(db)
                }
                let dtos = playlists.compactMap { RemotePlaylist($0) }
                return jsonResponse(dtos)
            } catch {
                Logger.error("RemoteControlServer /playlists failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }
    }

    // MARK: - Per-entity track listings

    private func registerEntityTrackRoutes(on server: HTTPServer) async {
        // GET /albums/:albumId/tracks
        await server.appendRoute("GET /albums/:albumId/tracks") { request in
            guard let raw = request.routeParameters["albumId"], let id = Int64(raw) else {
                return RemoteResponse.badRequest("invalid albumId")
            }
            do {
                let tracks = try await DatabaseManager.shared.getTracksForAlbum(albumId: id)
                return jsonResponse(tracks.compactMap { RemoteTrack($0) })
            } catch {
                Logger.error("RemoteControlServer /albums/\(id)/tracks failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }

        // GET /artists/:artistId/tracks
        await server.appendRoute("GET /artists/:artistId/tracks") { request in
            guard let raw = request.routeParameters["artistId"], let id = Int64(raw) else {
                return RemoteResponse.badRequest("invalid artistId")
            }
            do {
                let tracks = try await DatabaseManager.shared.getTracksForArtist(artistId: id)
                return jsonResponse(tracks.compactMap { RemoteTrack($0) })
            } catch {
                Logger.error("RemoteControlServer /artists/\(id)/tracks failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }

        // GET /playlists/:id/tracks
        await server.appendRoute("GET /playlists/:playlistId/tracks") { request in
            guard let raw = request.routeParameters["playlistId"], let id = Int64(raw) else {
                return RemoteResponse.badRequest("invalid playlistId")
            }
            do {
                let tracks = try await DatabaseManager.shared.getTracksForPlaylist(playlistId: id)
                return jsonResponse(tracks.compactMap { RemoteTrack($0) })
            } catch {
                Logger.error("RemoteControlServer /playlists/\(id)/tracks failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }
    }

    // MARK: - Queue-from-browse (POST)

    private func registerQueueFromBrowseRoutes(on server: HTTPServer) async {
        // POST /queue/playTracks { trackIds: [Int64], startAt: Int }
        await server.appendRoute("POST /queue/playTracks") { request in
            guard isRemoteOriginAllowed(request) else { return RemoteResponse.forbidden("origin not allowed") }
            let req: PlayTracksRequest
            switch await decodeBody(PlayTracksRequest.self, from: request) {
            case .value(let v): req = v
            case .failure(let r): return r
            }
            guard !req.trackIds.isEmpty else {
                return RemoteResponse.badRequest("trackIds empty")
            }
            do {
                let tracks = try await fetchTracksByIds(req.trackIds)
                guard !tracks.isEmpty else {
                    return RemoteResponse.badRequest("no matching tracks")
                }
                // Resolve startAt against the requested id, not the filtered
                // index: fetchTracksByIds drops ids that no longer resolve, so
                // a track deleted between list-load and tap would shift every
                // index and start playback on the wrong row. Locate the tapped
                // id in the surviving tracks; fall back to a clamped index when
                // that id is itself gone.
                let requestedIndex = max(0, min(req.startAt, req.trackIds.count - 1))
                let targetId = req.trackIds[requestedIndex]
                let startAt = tracks.firstIndex { $0.trackId == targetId }
                    ?? max(0, min(req.startAt, tracks.count - 1))
                await MainActor.run {
                    PlaybackController.shared.playTracks(tracks, startingAt: startAt)
                }
                return RemoteResponse.ok
            } catch {
                Logger.error("RemoteControlServer /queue/playTracks failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }

        // POST /queue/add { trackIds: [Int64] }
        await server.appendRoute("POST /queue/add") { request in
            guard isRemoteOriginAllowed(request) else { return RemoteResponse.forbidden("origin not allowed") }
            let req: TrackIdsRequest
            switch await decodeBody(TrackIdsRequest.self, from: request) {
            case .value(let v): req = v
            case .failure(let r): return r
            }
            guard !req.trackIds.isEmpty else {
                return RemoteResponse.badRequest("trackIds empty")
            }
            do {
                let tracks = try await fetchTracksByIds(req.trackIds)
                guard !tracks.isEmpty else {
                    return RemoteResponse.badRequest("no matching tracks")
                }
                await MainActor.run {
                    PlaybackController.shared.addToQueue(tracks)
                }
                return RemoteResponse.ok
            } catch {
                Logger.error("RemoteControlServer /queue/add failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }

        // POST /queue/playNext { trackIds: [Int64] }
        await server.appendRoute("POST /queue/playNext") { request in
            guard isRemoteOriginAllowed(request) else { return RemoteResponse.forbidden("origin not allowed") }
            let req: TrackIdsRequest
            switch await decodeBody(TrackIdsRequest.self, from: request) {
            case .value(let v): req = v
            case .failure(let r): return r
            }
            guard !req.trackIds.isEmpty else {
                return RemoteResponse.badRequest("trackIds empty")
            }
            do {
                let tracks = try await fetchTracksByIds(req.trackIds)
                guard !tracks.isEmpty else {
                    return RemoteResponse.badRequest("no matching tracks")
                }
                // playNext(_:) inserts a single track immediately after the
                // current one. To preserve list order, insert in reverse —
                // each insert pushes earlier inserts down by one slot.
                await MainActor.run {
                    for t in tracks.reversed() {
                        PlaybackController.shared.playNext(t)
                    }
                }
                return RemoteResponse.ok
            } catch {
                Logger.error("RemoteControlServer /queue/playNext failed: \(error)")
                return RemoteResponse.serverError("internal error")
            }
        }
    }
}

// MARK: - Helpers (file scope, non-isolated)

/// Encode any Encodable as JSON (sorted keys for cache-friendly output).
private func jsonResponse<T: Encodable>(_ value: T) -> HTTPResponse {
    do {
        let data = try RemoteETag.canonicalJSONEncoder.encode(value)
        return HTTPResponse(
            statusCode: .ok,
            headers: [
                .contentType: "application/json; charset=utf-8",
                HTTPHeader("Cache-Control"): "no-store"
            ],
            body: data
        )
    } catch {
        Logger.error("RemoteControlServer JSON encode failed: \(error)")
        return RemoteResponse.serverError("encode failed")
    }
}

/// Clamp the user-supplied `limit` query param into a sane range.
private func clampLimit(_ raw: String?, fallback: Int, max upper: Int) -> Int {
    guard let raw, let n = Int(raw) else { return fallback }
    return Swift.max(1, Swift.min(n, upper))
}

/// Fetch a page of tracks (full schema, ordered by sort_artist/title).
private func fetchTracksPage(limit: Int, offset: Int) async throws -> ([RemoteTrack], Int) {
    try await DatabaseManager.shared.dbQueue.read { db -> ([RemoteTrack], Int) in
        let total = try Track.filter(Track.Columns.isDuplicate == false).fetchCount(db)
        let rows = try Track
            .filter(Track.Columns.isDuplicate == false)
            .order(Track.Columns.sortTitle, Track.Columns.title)
            .limit(limit, offset: offset)
            .fetchAll(db)
        let dtos = rows.compactMap { RemoteTrack($0) }
        return (dtos, total)
    }
}

/// Fetch full Track rows for the given DB ids in a single read transaction.
/// FULL schema (not lightweight) — the playback engine needs `url`.
private func fetchTracksByIds(_ ids: [Int64]) async throws -> [Track] {
    try await DatabaseManager.shared.dbQueue.read { db -> [Track] in
        let fetched = try Track.fetchAll(db, keys: ids)
        // Preserve caller-supplied order (DB returns in row order).
        let byId: [Int64: Track] = Dictionary(uniqueKeysWithValues: fetched.compactMap { t in
            guard let tid = t.trackId else { return nil }
            return (tid, t)
        })
        return ids.compactMap { byId[$0] }
    }
}
