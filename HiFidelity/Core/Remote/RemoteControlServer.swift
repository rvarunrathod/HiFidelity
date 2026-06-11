//
//  RemoteControlServer.swift
//  HiFidelity
//
//  HTTP remote-control server skeleton (M1). Routes are added in later
//  milestones (M2+). Off-by-default; gated on `RemoteSettings.isEnabled`.
//

import Foundation
import FlyingFox

// MARK: - Settings accessors

/// Centralized accessors for the remote-control UserDefaults keys.
/// Single read site so the rest of the codebase can stay UserDefaults-string free.
enum RemoteSettings {
    /// UserDefaults key names. Keep in sync with `@AppStorage` keys in
    /// `RemoteControlSettings.swift`.
    enum Keys {
        static let enabled = "remote.enabled"
        static let port = "remote.port"
        static let bonjourName = "remote.bonjourName"
    }

    /// Whether the user has enabled the HTTP remote-control server.
    /// Default: `false` (off, opt-in feature).
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.enabled)
    }

    /// Default TCP port the server binds to. macOS sandbox blocks ports < 1024
    /// for non-root processes, so we default to a high IANA-unassigned port.
    static let defaultPort: UInt16 = 7666

    /// User-configured port, clamped into a safe sandboxed range.
    static var port: UInt16 {
        let raw = UserDefaults.standard.object(forKey: Keys.port) as? Int
        guard let raw, raw >= 1024, raw <= 65535 else { return defaultPort }
        return UInt16(raw)
    }

    /// Resolved Bonjour service name. Falls back to the Mac's localized name,
    /// then to a fixed string so the field is never empty.
    static var bonjourName: String {
        if let stored = UserDefaults.standard.string(forKey: Keys.bonjourName),
           !stored.trimmingCharacters(in: .whitespaces).isEmpty {
            return stored
        }
        if let host = ProcessInfo.processInfo.hostName.split(separator: ".").first,
           !host.isEmpty {
            return String(host)
        }
        return "HiFidelity"
    }
}

/// Long-lived `@MainActor` singleton that owns the FlyingFox `HTTPServer`
/// instance and its lifecycle. Reads/writes must occur on the main actor;
/// route handlers (which run on FlyingFox's executor) explicitly hop here
/// via `MainActor.run` when they need to touch app state.
@MainActor
final class RemoteControlServer: ObservableObject {
    static let shared = RemoteControlServer()

    // MARK: - Published State

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var port: UInt16
    @Published private(set) var bonjourName: String
    @Published private(set) var primaryURL: URL?
    @Published private(set) var allURLs: [URL] = []

    // MARK: - Private

    private var server: HTTPServer?
    private var serverTask: Task<Void, Never>?
    private var netService: NetService?
    private var bonjourDelegate: RemoteBonjourDelegate?

    private init() {
        // Resolve initial port + Bonjour name from UserDefaults via the
        // `RemoteSettings` accessors. These values are captured once at
        // server start; live updates happen through `restart()` after the
        // user edits Settings (M6).
        self.port = RemoteSettings.port
        self.bonjourName = RemoteSettings.bonjourName
    }

    // MARK: - Lifecycle

    /// Start the HTTP server. No-op if already running.
    func start() async throws {
        guard !isRunning else {
            Logger.debug("RemoteControlServer.start called while already running; ignoring")
            return
        }

        // Re-read settings each start so port / name changes take effect.
        let resolvedPort = RemoteSettings.port
        let resolvedName = RemoteSettings.bonjourName

        let httpServer = HTTPServer(port: resolvedPort)
        await registerRoutes(on: httpServer)

        // FlyingFox's `run()` blocks for the lifetime of the server; we
        // launch it on a detached Task so callers return as soon as the
        // listener is up.
        let runTask = Task { [weak self] in
            do {
                try await httpServer.run()
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        Logger.error("RemoteControlServer run loop ended with error: \(error)")
                        self?.isRunning = false
                    }
                }
            }
        }

        do {
            try await httpServer.waitUntilListening(timeout: 5)
        } catch {
            runTask.cancel()
            await httpServer.stop(timeout: 1)
            Logger.error("RemoteControlServer failed to listen on port \(resolvedPort): \(error)")
            throw error
        }

        self.server = httpServer
        self.serverTask = runTask
        self.port = resolvedPort
        self.bonjourName = resolvedName
        self.isRunning = true
        Logger.info("RemoteControlServer started on port \(resolvedPort)")

        // Publish Bonjour AFTER the listener is up. NetService runs on the
        // main run loop; we are already on @MainActor here.
        publishBonjour(name: resolvedName, port: resolvedPort)

        // Populate the URL list once at startup. Settings refreshes on
        // appear and via the manual "Refresh URLs" button after that —
        // network interface changes are infrequent and the live monitor
        // wasn't worth its overhead.
        refreshAllURLs()
    }

    /// Stop the HTTP server. No-op if not running.
    func stop() async {
        unpublishBonjour()
        primaryURL = nil
        allURLs = []
        guard let httpServer = server else {
            isRunning = false
            return
        }
        await httpServer.stop(timeout: 3)
        serverTask?.cancel()
        server = nil
        serverTask = nil
        isRunning = false
        Logger.info("RemoteControlServer stopped")
    }

    // MARK: - Bonjour

    /// Publish the HTTP service over mDNS as `_hifidelity._tcp`. Auto-rename
    /// is allowed; `RemoteBonjourDelegate` writes the resolved name back to
    /// `bonjourName` so Settings reflects reality.
    private func publishBonjour(name: String, port: UInt16) {
        let svc = NetService(
            domain: "local.",
            type: "_hifidelity._tcp.",
            name: name,
            port: Int32(port)
        )
        let delegate = RemoteBonjourDelegate { [weak self] resolvedName in
            Task { @MainActor in
                guard let self else { return }
                if self.bonjourName != resolvedName {
                    self.bonjourName = resolvedName
                }
            }
        }
        svc.delegate = delegate
        svc.schedule(in: .main, forMode: .default)
        svc.publish()
        self.netService = svc
        self.bonjourDelegate = delegate
    }

    private func unpublishBonjour() {
        netService?.stop()
        netService?.remove(from: .main, forMode: .default)
        netService = nil
        bonjourDelegate = nil
    }

    // MARK: - URL list

    /// Recompute the list of URLs that point at this server. Called once on
    /// `start()`, again from the Settings pane (`onAppear` + manual refresh
    /// button) — there is no live network monitor.
    func refreshAllURLs() {
        let port = self.port
        let ips = NetworkInterfaceLister.activeIPv4Addresses()
        var urls: [URL] = []
        for ip in ips {
            if let url = URL(string: "http://\(ip):\(port)/") {
                urls.append(url)
            }
        }
        self.allURLs = urls

        // Primary URL: prefer the Bonjour <name>.local form (works on all
        // Apple devices, falls through router NAT). Fallback to the first
        // en* IPv4 address if Bonjour is not yet published.
        if !bonjourName.isEmpty {
            self.primaryURL = URL(string: "http://\(bonjourName).local:\(port)/")
        } else {
            self.primaryURL = urls.first
        }
    }

    /// Convenience: stop then start. Used by Settings when the user edits
    /// the port or Bonjour name while the server is running.
    func restart() async throws {
        await stop()
        try await start()
    }

    // MARK: - Routes

    /// Register routes on the supplied `HTTPServer` instance.
    private func registerRoutes(on server: HTTPServer) async {
        await registerStateRoutes(on: server)
        await registerCommandRoutes(on: server)
        await registerBrowseRoutes(on: server)
        await registerWebUIRoutes(on: server)
    }

    /// Static-file routes serving the bundled HTML/CSS/JS web client.
    /// HEAD mirrors GET (RFC 9110): same headers, empty body.
    private func registerWebUIRoutes(on server: HTTPServer) async {
        let webSubdir = "RemoteControl/web"
        let indexHandler = RemoteBundleHTTPHandler(
            resourceName: "index",
            resourceExtension: "html",
            subdirectory: webSubdir,
            contentType: "text/html; charset=utf-8",
            cacheControl: "no-cache"
        )
        // app.js / style.css ship inside the app bundle and change with every
        // build, so revalidate on each load (`no-cache`) — otherwise browsers
        // serve a stale UI for up to an hour after an app update. Offline
        // caching is handled by the service worker, not the HTTP layer.
        let appJsHandler = RemoteBundleHTTPHandler(
            resourceName: "app",
            resourceExtension: "js",
            subdirectory: webSubdir,
            contentType: "application/javascript; charset=utf-8",
            cacheControl: "no-cache"
        )
        let styleCssHandler = RemoteBundleHTTPHandler(
            resourceName: "style",
            resourceExtension: "css",
            subdirectory: webSubdir,
            contentType: "text/css; charset=utf-8",
            cacheControl: "no-cache"
        )
        await server.appendRoute("GET /", to: indexHandler)
        await server.appendRoute("GET /index.html", to: indexHandler)
        await server.appendRoute("GET /assets/app.js", to: appJsHandler)
        await server.appendRoute("GET /assets/style.css", to: styleCssHandler)
        let manifestHandler = RemoteBundleHTTPHandler(
            resourceName: "manifest",
            resourceExtension: "webmanifest",
            subdirectory: webSubdir,
            contentType: "application/manifest+json",
            cacheControl: "no-cache"
        )
        let icon192Handler = RemoteBundleHTTPHandler(
            resourceName: "icon-192",
            resourceExtension: "png",
            subdirectory: webSubdir,
            contentType: "image/png"
        )
        let icon512Handler = RemoteBundleHTTPHandler(
            resourceName: "icon-512",
            resourceExtension: "png",
            subdirectory: webSubdir,
            contentType: "image/png"
        )
        // Service worker must be served from the scope root (`/sw.js`) with
        // `no-cache` so browsers always revalidate it and pick up updates.
        let swHandler = RemoteBundleHTTPHandler(
            resourceName: "sw",
            resourceExtension: "js",
            subdirectory: webSubdir,
            contentType: "application/javascript; charset=utf-8",
            cacheControl: "no-cache"
        )
        await server.appendRoute("GET /manifest.webmanifest", to: manifestHandler)
        await server.appendRoute("GET /assets/icon-192.png", to: icon192Handler)
        await server.appendRoute("GET /assets/icon-512.png", to: icon512Handler)
        await server.appendRoute("GET /sw.js", to: swHandler)

        // HEAD: rerun the GET path but drop the body. (B006)
        await server.appendRoute("HEAD /") { request in
            await stripBody(try await indexHandler.handleRequest(request))
        }
        await server.appendRoute("HEAD /index.html") { request in
            await stripBody(try await indexHandler.handleRequest(request))
        }
        await server.appendRoute("HEAD /assets/app.js") { request in
            await stripBody(try await appJsHandler.handleRequest(request))
        }
        await server.appendRoute("HEAD /assets/style.css") { request in
            await stripBody(try await styleCssHandler.handleRequest(request))
        }
        await server.appendRoute("HEAD /manifest.webmanifest") { request in
            await stripBody(try await manifestHandler.handleRequest(request))
        }
        await server.appendRoute("HEAD /assets/icon-192.png") { request in
            await stripBody(try await icon192Handler.handleRequest(request))
        }
        await server.appendRoute("HEAD /assets/icon-512.png") { request in
            await stripBody(try await icon512Handler.handleRequest(request))
        }
        await server.appendRoute("HEAD /sw.js") { request in
            await stripBody(try await swHandler.handleRequest(request))
        }
    }

    /// M2 read-only routes: `/state` (current playback snapshot, ETag-keyed)
    /// and `/artwork/:trackId` (raw image bytes, content-addressable).
    /// HEAD mirrors GET (RFC 9110): same headers, empty body.
    private func registerStateRoutes(on server: HTTPServer) async {
        // GET /state — JSON snapshot of PlaybackController, hash-derived ETag.
        let stateHandler: @Sendable (HTTPRequest) async throws -> HTTPResponse = { request in
            let state = await MainActor.run { RemoteStateProvider.snapshot() }
            let data: Data
            do {
                data = try RemoteETag.canonicalJSONEncoder.encode(state)
            } catch {
                Logger.error("RemoteControlServer /state encode failed: \(error)")
                return RemoteResponse.serverError("state encode failed")
            }
            let tag = RemoteETag.etag(forJSON: data)
            if let inm = request.headers[HTTPHeader("If-None-Match")], inm == tag {
                let headers: HTTPHeaders = [.eTag: tag, HTTPHeader("Cache-Control"): "no-store"]
                return HTTPResponse(statusCode: .notModified, headers: headers)
            }
            let headers: HTTPHeaders = [
                .contentType: "application/json; charset=utf-8",
                .eTag: tag,
                HTTPHeader("Cache-Control"): "no-store"
            ]
            return HTTPResponse(statusCode: .ok, headers: headers, body: data)
        }
        await server.appendRoute("GET /state", handler: stateHandler)
        await server.appendRoute("HEAD /state") { request in
            await stripBody(try await stateHandler(request))
        }

        // GET /artwork/:trackId — raw bytes; ETag derives from id PLUS a
        // short content fingerprint so deleted/replaced artwork yields a
        // fresh tag and never serves a 304 for a missing track. Cache-Control
        // omits `immutable` on purpose: the URL is id-addressed, not
        // content-addressed, so the browser must revalidate against the
        // fingerprint ETag to pick up re-tagged cover art.
        let artworkHandler: @Sendable (HTTPRequest) async throws -> HTTPResponse = { request in
            guard let raw = request.routeParameters["trackId"],
                  let trackId = Int64(raw) else {
                return RemoteResponse.badRequest("invalid trackId")
            }
            do {
                // Existence check first — return 404 before any ETag work.
                guard let result = try RemoteArtworkLoader.data(forTrackId: trackId) else {
                    return RemoteResponse.notFound("not found")
                }
                let tag = RemoteETag.artworkETag(trackId: trackId, bytes: result.data)
                if let inm = request.headers[HTTPHeader("If-None-Match")], inm == tag {
                    let headers: HTTPHeaders = [
                        .eTag: tag,
                        HTTPHeader("Cache-Control"): "public, max-age=31536000"
                    ]
                    return HTTPResponse(statusCode: .notModified, headers: headers)
                }
                let headers: HTTPHeaders = [
                    .contentType: result.contentType,
                    .eTag: tag,
                    HTTPHeader("Cache-Control"): "public, max-age=31536000"
                ]
                return HTTPResponse(statusCode: .ok, headers: headers, body: result.data)
            } catch {
                Logger.error("RemoteControlServer /artwork/\(trackId) DB read failed: \(error)")
                return RemoteResponse.serverError("artwork read failed")
            }
        }
        await server.appendRoute("GET /artwork/:trackId", handler: artworkHandler)
        await server.appendRoute("HEAD /artwork/:trackId") { request in
            await stripBody(try await artworkHandler(request))
        }
    }
}

/// Drop the body from an HTTPResponse, preserving status code and headers.
/// Used for HEAD handlers that mirror GET (RFC 9110: HEAD = GET sans body).
/// RFC 9110 also says HEAD SHOULD report the same `Content-Length` a GET
/// would; FlyingFox only auto-sets that header when absent, so we set it
/// explicitly from the GET body size before emptying the body.
@Sendable
func stripBody(_ response: HTTPResponse) async -> HTTPResponse {
    var headers = response.headers
    if headers[.contentLength] == nil, let body = try? await response.bodyData {
        headers[.contentLength] = String(body.count)
    }
    return HTTPResponse(statusCode: response.statusCode, headers: headers, body: Data())
}

// MARK: - Bonjour delegate

/// `NetServiceDelegate` that captures the published name (which Bonjour may
/// rename on collision, e.g. "HiFidelity (2)") and surfaces it back to
/// `RemoteControlServer`.
final class RemoteBonjourDelegate: NSObject, NetServiceDelegate {
    private let onResolved: @Sendable (String) -> Void

    init(onResolved: @escaping @Sendable (String) -> Void) {
        self.onResolved = onResolved
    }

    func netServiceDidPublish(_ sender: NetService) {
        Logger.info("Bonjour: published _hifidelity._tcp as \"\(sender.name)\" on port \(sender.port)")
        onResolved(sender.name)
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        Logger.error("Bonjour: failed to publish _hifidelity._tcp: \(errorDict)")
    }

    func netServiceDidStop(_ sender: NetService) {
        Logger.debug("Bonjour: stopped publishing _hifidelity._tcp \"\(sender.name)\"")
    }
}
