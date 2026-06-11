//
//  RemoteBundleHTTPHandler.swift
//  HiFidelity
//
//  Static-file HTTP handler that reads a single file from `Bundle.main`.
//  Avoids FlyingFox's `.directory(_:)` (which is CWD-relative) — sandbox
//  CWDs are unstable and we want a clean Bundle-rooted lookup.
//

import Foundation
import FlyingFox

struct RemoteBundleHTTPHandler: HTTPHandler {
    let resourceName: String
    let resourceExtension: String
    let subdirectory: String
    let contentType: String
    let cacheControl: String

    // Bundle resources are static for the app's lifetime, so the file is read
    // once at init and held in memory — every request (app.js/style.css are
    // `no-cache`, so each page load would otherwise hit disk) serves the
    // cached copy. `nil` means the resource was missing at startup → 404.
    private let cachedData: Data?

    init(
        resourceName: String,
        resourceExtension: String,
        subdirectory: String,
        contentType: String,
        cacheControl: String = "public, max-age=3600"
    ) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.subdirectory = subdirectory
        self.contentType = contentType
        self.cacheControl = cacheControl

        // Try the namespaced lookup first (folder reference layout) and
        // fall back to a flat lookup (synchronized group flattens
        // resources). Both are valid Xcode resource layouts.
        let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: subdirectory
        ) ?? Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension
        )
        guard let url else {
            Logger.error("RemoteBundleHTTPHandler: missing \(subdirectory)/\(resourceName).\(resourceExtension)")
            self.cachedData = nil
            return
        }
        do {
            self.cachedData = try Data(contentsOf: url)
        } catch {
            Logger.error("RemoteBundleHTTPHandler: read failed for \(url.lastPathComponent): \(error)")
            self.cachedData = nil
        }
    }

    func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let cachedData else {
            return RemoteResponse.notFound("not found")
        }
        let headers: HTTPHeaders = [
            .contentType: contentType,
            HTTPHeader("Cache-Control"): cacheControl
        ]
        return HTTPResponse(statusCode: .ok, headers: headers, body: cachedData)
    }
}
