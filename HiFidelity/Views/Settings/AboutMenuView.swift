//
//  AboutMenuView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 26/11/25.
//

import SwiftUI
import Sparkle

struct AboutMenuView: View {
    @State private var libraryStats: LibraryStats?
    @AppStorage("automaticUpdatesEnabled")
    private var automaticUpdatesEnabled = true
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            appInfoSection

            if let stats = libraryStats, stats.totalFolders > 0 {
                libraryStatisticsSection
            }

            footerSection
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadLibraryStats()
        }
    }
    
    private func loadLibraryStats() async {
        do {
            libraryStats = try await DatabaseCache.shared.getLibraryStats()
        } catch {
            Logger.error("Failed to load library stats: \(error)")
        }
    }

    // MARK: - App Info Section

    private var appInfoSection: some View {
        VStack(spacing: 16) {
            appIcon
            appDetails
        }
    }

    private var appIcon: some View {
        Group {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Image(systemName: "drop.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)
            }
        }
    }

    private var appDetails: some View {
        VStack(spacing: 8) {
            Text(About.appTitle)
                .font(.title)
                .fontWeight(.bold)

            Text(AppInfo.version)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Toggle("Check for updates automatically", isOn: $automaticUpdatesEnabled)
                .help("Automatically download and install updates when available")
                .onChange(of: automaticUpdatesEnabled) { _, newValue in
                    if let appDelegate = NSApp.delegate as? AppDelegate,
                       let updater = appDelegate.updaterController?.updater {
                        updater.automaticallyChecksForUpdates = newValue
                    }
                }
        }
    }

    // MARK: - Library Statistics Section

    private var libraryStatisticsSection: some View {
        VStack(spacing: 12) {
            Text("Library Statistics")
                .font(.headline)

            if let stats = libraryStats {
                statisticsRow(stats: stats)
            }
        }
    }

    private func statisticsRow(stats: LibraryStats) -> some View {
        HStack(spacing: 30) {
            statisticItem(
                value: "\(stats.totalFolders)",
                label: "Folders"
            )

            statisticItem(
                value: "\(stats.totalTracks)",
                label: "Tracks"
            )

            statisticItem(
                value: stats.formattedDuration,
                label: "Total Duration"
            )

            statisticItem(
                value: stats.formattedStorage,
                label: "Total Storage"
            )
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }

    private func statisticItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack(spacing: 20) {
            FooterLink(
                icon: "globe",
                title: "Website",
                url: URL(string: About.appWebsite)!,
                tooltip: "Visit project website"
            )
            
            FooterLink(
                icon: "questionmark.circle",
                title: "Help",
                url: URL(string: About.appWiki)!,
                tooltip: "Visit Help Wiki"
            )
            
            FooterLink(
                icon: "doc.text",
                title: "License",
                url: URL(string: "\(About.appWebsite)/blob/main/LICENSE"),
                tooltip: "View license"
            )
            
            FooterLink(
                icon: "folder",
                title: "App Data",
                action: {
                    let appDataURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                        .appendingPathComponent(Bundle.main.bundleIdentifier ?? About.bundleIdentifier)
                    
                    if let url = appDataURL {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                },
                tooltip: "Show app data directory in Finder"
            )
        }
    }
    
    private struct FooterLink: View {
        let icon: String
        let title: String
        var url: URL?
        var action: (() -> Void)?
        let tooltip: String
        
        @State private var isHovered = false
        
        var body: some View {
            if let url = url {
                Link(destination: url) {
                    linkContent
                }
                .buttonStyle(.plain)
                .help(tooltip)
            } else if let action = action {
                Button(action: action) {
                    linkContent
                }
                .buttonStyle(.plain)
                .help(tooltip)
            }
        }
        
        private var linkContent: some View {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(isHovered ? .accentColor : .secondary)
            .underline(isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }

}

#Preview {
    ScrollView {
        AboutMenuView()
            .padding(24)
    }
    .frame(width: 600, height: 500)
}
