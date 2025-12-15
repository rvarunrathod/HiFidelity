//
//  LibrarySettings.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI

struct LibrarySettings: View {
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    @StateObject private var folderWatcher = FolderWatcherService.shared
    
    @State private var folders: [Folder] = []
    @State private var showRemoveConfirmation = false
    @State private var folderToRemove: Folder?
    @State private var showRemoveAllConfirmation = false
    @State private var isLoading = false
    @AppStorage("enableFolderWatcher") private var enableFolderWatcher = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Import progress section
            if databaseManager.isImporting {
                importProgressSection
                Divider()
            }
            
            // Folder monitoring control
            folderMonitoringSection
            
            Divider()
            
            if isLoading {
                loadingView
            } else if folders.isEmpty {
                emptyStateView
            } else {
                // Folders table
                VStack(spacing: 0) {
                    // Action buttons
                    actionButtons
                    
                    Divider()
                    
                    // Folders list
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(folders) { folder in
                                FolderRow(
                                    folder: folder,
                                    isImporting: databaseManager.isImporting,
                                    onScan: {
                                        Task {
                                            await scanFolder(folder)
                                        }
                                    },
                                    onRemove: {
                                        folderToRemove = folder
                                        showRemoveConfirmation = true
                                    }
                                )
                                
                                if folder.id != folders.last?.id {
                                    Divider()
                                        .padding(.leading, 60)
                                }
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor))
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                }
            }
        }
        .alert("Remove Folder?", isPresented: $showRemoveConfirmation, presenting: folderToRemove) { folder in
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    await removeFolder(folder)
                }
            }
        } message: { folder in
            Text("This will remove '\(folder.name)' from your library. This cannot be undone.")
        }
        .alert("Remove All Folders?", isPresented: $showRemoveAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                Task {
                    await removeAllFolders()
                }
            }
        } message: {
            Text("This will remove all \(folders.count) folders from your library. This cannot be undone.")
        }
        .task {
            await loadFolders()
        }
        .onReceive(NotificationCenter.default.publisher(for: .foldersDataDidChange)) { _ in
            Task {
                await loadFolders()
            }
        }
    }
    
    // MARK: - Import Progress Section
    
    private var importProgressSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Icon
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(width: 24)
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Importing Music")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    if !databaseManager.currentImportingFolder.isEmpty {
                        Text(databaseManager.currentImportingFolder)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(theme.currentTheme.primaryColor)
                    }
                    
                    if !databaseManager.importStatusMessage.isEmpty {
                        Text(databaseManager.importStatusMessage)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Progress percentage
                if databaseManager.importProgress > 0 {
                    Text("\(Int(databaseManager.importProgress * 100))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.currentTheme.primaryColor)
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.currentTheme.primaryColor)
                        .frame(width: max(0, geometry.size.width * databaseManager.importProgress), height: 4)
                        .animation(.easeInOut, value: databaseManager.importProgress)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.currentTheme.primaryColor.opacity(0.05))
    }
    
    // MARK: - Folder Monitoring Section
    
    private var folderMonitoringSection: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: folderWatcher.isWatching ? "eye.fill" : "eye.slash.fill")
                .font(.system(size: 16))
                .foregroundColor(folderWatcher.isWatching ? theme.currentTheme.primaryColor : .secondary)
                .frame(width: 24)
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text("Automatic Folder Monitoring")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(folderWatcher.isWatching 
                    ? "Watching \(folderWatcher.watchedFoldersCount) folder\(folderWatcher.watchedFoldersCount == 1 ? "" : "s") for changes" 
                    : "Enable to automatically update your library when files change")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: $enableFolderWatcher)
                .toggleStyle(SwitchToggleStyle())
                .labelsHidden()
                .onChange(of: enableFolderWatcher) { _, newValue in
                    handleMonitoringToggle(newValue)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("Music Folders")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button {
                databaseManager.addFolder()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add Folder")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(databaseManager.isImporting ? Color.gray : theme.currentTheme.primaryColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(databaseManager.isImporting)
            .opacity(databaseManager.isImporting ? 0.5 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Scan All button
            Button {
                Task {
                    await scanAllFolders()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                    Text("Scan All")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(databaseManager.isImporting ? .gray : theme.currentTheme.primaryColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(databaseManager.isImporting ? Color.gray.opacity(0.15) : theme.currentTheme.primaryColor.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .disabled(databaseManager.isImporting)
            .opacity(databaseManager.isImporting ? 0.5 : 1.0)
            
            // Delete All button
            Button {
                showRemoveAllConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                    Text("Delete All")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(databaseManager.isImporting ? .gray : .red)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(databaseManager.isImporting ? Color.gray.opacity(0.15) : Color.red.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .disabled(databaseManager.isImporting)
            .opacity(databaseManager.isImporting ? 0.5 : 1.0)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("No Music Folders")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            Text("Add folders to build your music library")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                databaseManager.addFolder()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add Your First Folder")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(databaseManager.isImporting ? Color.gray : theme.currentTheme.primaryColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(databaseManager.isImporting)
            .opacity(databaseManager.isImporting ? 0.5 : 1.0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(theme.currentTheme.primaryColor)
            Text("Loading folders...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    
    // MARK: - Folder Monitoring
    
    private func handleMonitoringToggle(_ enabled: Bool) {
        if enabled {
            folderWatcher.startWatching(databaseManager: databaseManager)
        } else {
            folderWatcher.stopWatching()
        }
    }
    
    // MARK: - Data Loading
    
    private func loadFolders() async {
        isLoading = true
        do {
            folders = try await DatabaseCache.shared.getFolders()
        } catch {
            Logger.error("Failed to load folders: \(error)")
        }
        isLoading = false
    }
    
    private func scanFolder(_ folder: Folder) async {
        // Prevent scanning when import is already in progress
        guard !databaseManager.isImporting else {
            NotificationManager.shared.addMessage(.warning, "Please wait for the current import to finish")
            return
        }
        
        do {
            try await databaseManager.rescanFolder(folder)
            await loadFolders()
        } catch {
            Logger.error("Failed to scan folder \(folder.name): \(error)")
        }
    }
    
    private func scanAllFolders() async {
        // Prevent scanning when import is already in progress
        guard !databaseManager.isImporting else {
            NotificationManager.shared.addMessage(.warning, "Please wait for the current import to finish")
            return
        }
        
        for folder in folders {
            do {
                try await databaseManager.rescanFolder(folder)
            } catch {
                Logger.error("Failed to scan folder \(folder.name): \(error)")
            }
        }
        
        await loadFolders()
    }
    
    private func removeFolder(_ folder: Folder) async {
        // Prevent removing folders when import is in progress
        guard !databaseManager.isImporting else {
            NotificationManager.shared.addMessage(.warning, "Please wait for the current import to finish")
            return
        }
        
        do {
            try await databaseManager.removeFolder(folder)
            await loadFolders()
        } catch {
            Logger.error("Failed to remove folder: \(error)")
        }
    }
    
    private func removeAllFolders() async {
        // Prevent removing folders when import is in progress
        guard !databaseManager.isImporting else {
            NotificationManager.shared.addMessage(.warning, "Please wait for the current import to finish")
            return
        }
        
        for folder in folders {
            do {
                try await databaseManager.removeFolder(folder)
            } catch {
                Logger.error("Failed to remove folder \(folder.name): \(error)")
            }
        }
        
        await loadFolders()
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: Folder
    let isImporting: Bool
    let onScan: () -> Void
    let onRemove: () -> Void
    
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    private func relocateFolder() {
        let panel = NSOpenPanel()
        panel.title = "Locate Folder: \(folder.name)"
        panel.message = "Select the new location of this folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            if response == .OK, let newURL = panel.url {
                Task {
                    do {
                        try await PathRecoveryManager.shared.relocateFolder(
                            oldFolderURL: folder.url,
                            newFolderURL: newURL
                        )
                        Logger.info("✓ Successfully relocated folder: \(folder.name)")
                    } catch {
                        Logger.error("Failed to relocate folder: \(error)")
                    }
                }
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Folder icon
            Image(systemName: "folder.fill")
                .font(.system(size: 30))
                .foregroundColor(theme.currentTheme.primaryColor)
                .frame(width: 40)
            
            // Folder path (left column)
            HStack {
                Text(folder.url.path)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .help(folder.url.path)
            
            // Status (right column)
            HStack(spacing: 8) {
                
                // Action buttons (shown on hover)
                HStack(spacing: 6) {
                    // Relocate button
                    Button {
                        relocateFolder()
                    } label: {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 12))
                            .foregroundColor(isImporting ? .gray : .orange)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(isImporting ? Color.gray.opacity(0.15) : Color.orange.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting)
                    .opacity(isImporting ? 0.5 : 1.0)
                    .help("Relocate folder if moved")
                    
                    // Scan button
                    Button {
                        onScan()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(isImporting ? .gray : theme.currentTheme.primaryColor)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(isImporting ? Color.gray.opacity(0.15) : theme.currentTheme.primaryColor.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting)
                    .opacity(isImporting ? 0.5 : 1.0)
                    .help("Scan folder")
                    
                    // Delete button
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(isImporting ? .gray : .red)
                            .frame(width: 24, height: 24)
                            .background(
                                Circle()
                                    .fill(isImporting ? Color.gray.opacity(0.15) : Color.red.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isImporting)
                    .opacity(isImporting ? 0.5 : 1.0)
                    .help("Remove folder")
                }
                .transition(.scale.combined(with: .opacity))
            }
            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.5) : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LibrarySettings()
        .environmentObject(DatabaseManager.shared)
        .frame(width: 700, height: 600)
}
