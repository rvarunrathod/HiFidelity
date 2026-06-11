//
//  RemoteControlSettings.swift
//  HiFidelity
//
//  Settings pane for the HTTP remote-control feature.
//

import SwiftUI
import AppKit

struct RemoteControlSettings: View {
    @StateObject private var server = RemoteControlServer.shared

    @AppStorage(RemoteSettings.Keys.enabled) private var enabled: Bool = false
    @AppStorage(RemoteSettings.Keys.port) private var portValue: Int = Int(RemoteSettings.defaultPort)
    @AppStorage(RemoteSettings.Keys.bonjourName) private var bonjourNameStored: String = ""

    @State private var portString: String = ""
    @State private var nameString: String = ""
    @State private var isApplying: Bool = false
    @State private var lastError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Remote Control")
                    .font(.title2)
                    .fontWeight(.semibold)

                toggleSection
                Divider()
                connectionSection
                Divider()
                addressesSection
                Divider()
                threatModelSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            portString = String(portValue)
            nameString = bonjourNameStored.isEmpty ? RemoteSettings.bonjourName : bonjourNameStored
            // Recompute the URL list each time the pane appears so the
            // shown addresses reflect the current network state without
            // running a live NWPathMonitor in the background.
            if server.isRunning {
                server.refreshAllURLs()
            }
        }
    }

    // MARK: - Sections

    private var toggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable Remote Control", isOn: $enabled)
                .toggleStyle(.switch)
                .onChange(of: enabled) { _, newValue in
                    Task {
                        if newValue {
                            await startServer()
                        } else {
                            await stopServer()
                        }
                    }
                }
            Text("Lets your iPad, phone, or another computer on the same Wi-Fi control playback through a web page.")
                .font(.caption)
                .foregroundColor(.secondary)
            if let lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection")
                .font(.title3)
                .fontWeight(.semibold)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.subheadline)
                    TextField("7666", text: $portString, onCommit: { applyPortChange() })
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("Default 7666. Must be 1024 or higher.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Service Name")
                        .font(.subheadline)
                    TextField("HiFidelity", text: $nameString, onCommit: { applyNameChange() })
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Text("How this Mac shows up on your local network.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if isApplying {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Applying…").font(.caption)
                }
            }
        }
        .disabled(isApplying)
    }

    private var addressesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connect from another device")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                if server.isRunning {
                    Button {
                        server.refreshAllURLs()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh URLs")
                }
            }
            Text("Open this URL in Safari on your iPad or phone.")
                .font(.caption)
                .foregroundColor(.secondary)

            if server.isRunning {
                if let primary = server.primaryURL {
                    urlRow(primary.absoluteString, isPrimary: true)
                } else {
                    Text("Resolving address…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if !server.allURLs.isEmpty {
                    DisclosureGroup("All addresses") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(server.allURLs, id: \.absoluteString) { url in
                                urlRow(url.absoluteString, isPrimary: false)
                            }
                            Text("Use any of these if Bonjour does not work for you.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(.top, 6)
                    }
                }
            } else {
                Text("Server is off.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var threatModelSection: some View {
        DisclosureGroup("About security") {
            Text("Anyone on this Wi-Fi can control playback. Disable when you're on a public or untrusted network.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 6)
        }
    }

    // MARK: - URL row

    private func urlRow(_ urlString: String, isPrimary: Bool) -> some View {
        HStack(spacing: 8) {
            Text(urlString)
                .font(.system(.body, design: .monospaced))
                .fontWeight(isPrimary ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(urlString, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .help("Copy URL")
        }
    }

    // MARK: - Actions

    private func startServer() async {
        isApplying = true
        lastError = nil
        defer { isApplying = false }
        do {
            try await server.start()
        } catch {
            lastError = "Failed to start: \(error.localizedDescription)"
            // Roll back the toggle so the user can see the failure clearly.
            enabled = false
            Logger.error("RemoteControlSettings start failed: \(error)")
        }
    }

    private func stopServer() async {
        isApplying = true
        lastError = nil
        defer { isApplying = false }
        await server.stop()
    }

    private func applyPortChange() {
        guard let parsed = Int(portString.trimmingCharacters(in: .whitespaces)),
              parsed >= 1024, parsed <= 65535 else {
            // Revert the field to the persisted value.
            portString = String(portValue)
            return
        }
        guard parsed != portValue else { return }
        portValue = parsed
        if server.isRunning {
            Task { await restartServer() }
        }
    }

    private func applyNameChange() {
        let trimmed = nameString.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            nameString = bonjourNameStored.isEmpty ? RemoteSettings.bonjourName : bonjourNameStored
            return
        }
        guard trimmed != bonjourNameStored else { return }
        bonjourNameStored = trimmed
        if server.isRunning {
            Task { await restartServer() }
        }
    }

    private func restartServer() async {
        isApplying = true
        lastError = nil
        defer { isApplying = false }
        do {
            try await server.restart()
        } catch {
            lastError = "Failed to restart: \(error.localizedDescription)"
            Logger.error("RemoteControlSettings restart failed: \(error)")
        }
    }
}

#Preview {
    RemoteControlSettings()
}
