//
//  CreatePlaylistView.swift
//  HiFidelity
//
//  Created by Varun Rathod on 31/10/25.
//

import SwiftUI
import AppKit

/// Modern playlist creation view
struct CreatePlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var databaseManager: DatabaseManager
    @ObservedObject var theme = AppTheme.shared
    
    @State private var playlistName = ""
    @State private var description = ""
    @State private var selectedImage: NSImage?
    @State private var compressedImageData: Data?
    @State private var isFavorite = false
    @State private var selectedColorScheme: PlaylistColorScheme = .auto
    
    @State private var isCreating = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showImportSuccess = false
    @State private var importMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 32) {
                    // Artwork section
                    artworkSection
                    
                    // Details section
                    detailsSection
                    
                    // Options section
                    optionsSection
                }
                .padding(32)
            }
            
            Divider()
            
            // Footer with buttons
            footer
        }
        .frame(width: 600, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Import Success", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(importMessage)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text("Create Playlist")
                .font(.system(size: 20, weight: .bold))
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    importFromM3U()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14))
                        Text("Import M3U")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.currentTheme.primaryColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .help("Import playlists from M3U files (up to 25 files)")
                
                Button {
                    importFromFolder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                        Text("Import Folder")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(theme.currentTheme.primaryColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.currentTheme.primaryColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .help("Import playlists from folders (up to 25 folders)")
            }
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Artwork Section
    
    private var artworkSection: some View {
        VStack(spacing: 16) {
            Text("Artwork")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 24) {
                // Artwork preview
                artworkPreview
                
                // Artwork controls
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add custom artwork to personalize your playlist")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    
                    Button {
                        selectImage()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "photo")
                            Text(selectedImage == nil ? "Choose Image" : "Change Image")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(theme.currentTheme.primaryColor)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    if selectedImage != nil {
                        Button {
                            selectedImage = nil
                            compressedImageData = nil
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text("Remove")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Spacer()
            }
        }
    }
    
    private var artworkPreview: some View {
        ZStack {
            if let image = selectedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 180, height: 180)
                    .cornerRadius(12)
                    .shadow(radius: 10)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.currentTheme.primaryColor.opacity(0.6),
                                theme.currentTheme.primaryColor
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 180, height: 180)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .shadow(radius: 10)
            }
        }
    }
    
    // MARK: - Details Section
    
    private var detailsSection: some View {
        VStack(spacing: 20) {
            // Playlist name
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Name")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text("*")
                        .foregroundColor(.red)
                }
                
                TextField("My Awesome Playlist", text: $playlistName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            
            // Description
            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                
                TextEditor(text: $description)
                    .font(.system(size: 14))
                    .frame(height: 80)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Options Section
    
    private var optionsSection: some View {
        VStack(spacing: 20) {
            Text("Options")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Pin to top
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pin to Top")
                        .font(.system(size: 14, weight: .medium))
                    Text("Keep this playlist at the top of your library")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $isFavorite)
                    .labelsHidden()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            
            // Color scheme
            VStack(alignment: .leading, spacing: 12) {
                Text("Color Scheme")
                    .font(.system(size: 14, weight: .medium))
                
                HStack(spacing: 12) {
                    ForEach(PlaylistColorScheme.allCases, id: \.self) { scheme in
                        ColorSchemeButton(
                            scheme: scheme,
                            isSelected: selectedColorScheme == scheme
                        ) {
                            selectedColorScheme = scheme
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            .buttonStyle(.plain)
            
            Button {
                Task {
                    await createPlaylist()
                }
            } label: {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    }
                    Text(isCreating ? "Creating..." : "Create Playlist")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(playlistName.isEmpty ? Color.gray : theme.currentTheme.primaryColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(playlistName.isEmpty || isCreating)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
    
    // MARK: - Actions
    
    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image for your playlist"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let image = NSImage(contentsOf: url) {
                selectedImage = image
                compressedImageData = ImageCompressor.compress(image: image, maxSize: 512)
            }
        }
    }
    
    private func createPlaylist() async {
        guard !playlistName.isEmpty else { return }
        
        isCreating = true
        defer { isCreating = false }
        
        do {
            var playlist = Playlist(
                name: playlistName.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
                isSmart: false
            )
            
            playlist.customArtworkData = compressedImageData
            playlist.colorScheme = selectedColorScheme == .auto ? nil : selectedColorScheme.rawValue
            playlist.isFavorite = isFavorite
            
            let createdPlaylist = try await databaseManager.createPlaylist(playlist)
            
            // Notify success with the created playlist
            NotificationCenter.default.post(name: .playlistCreated, object: createdPlaylist)
            
            dismiss()
        } catch {
            errorMessage = "Failed to create playlist: \(error.localizedDescription)"
            showError = true
            Logger.error("Failed to create playlist: \(error)")
        }
    }
    
    private func importFromM3U() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!, .init(filenameExtension: "m3u8")!]
        panel.message = "Choose M3U playlist files to import (max 25)"
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            
            guard !urls.isEmpty else { return }
            
            Task {
                isCreating = true
                defer { isCreating = false }
                
                do {
                    if urls.count == 1, let url = urls.first {
                        // Single file import
                        let result = try await databaseManager.importPlaylistFromM3U(m3uURL: url)
                        
                        // Show success message
                        importMessage = "Successfully imported '\(result.playlist.name)'\n\(result.foundCount) tracks added"
                        if result.skippedCount > 0 {
                            importMessage += "\n\(result.skippedCount) tracks not found in library"
                        }
                        showImportSuccess = true
                        
                        Logger.info("M3U Import: Success - \(result.foundCount) found, \(result.skippedCount) skipped")
                    } else {
                        // Multiple files import
                        let results = try await databaseManager.importMultiplePlaylistsFromM3U(m3uURLs: urls)
                        
                        if results.isEmpty {
                            errorMessage = "Failed to import any playlists"
                            showError = true
                            return
                        }
                        
                        // Calculate totals
                        let totalPlaylists = results.count
                        let totalTracks = results.reduce(0) { $0 + $1.foundCount }
                        let totalSkipped = results.reduce(0) { $0 + $1.skippedCount }
                        
                        // Show success message
                        importMessage = "Successfully imported \(totalPlaylists) playlist\(totalPlaylists == 1 ? "" : "s")\n\(totalTracks) tracks added"
                        if totalSkipped > 0 {
                            importMessage += "\n\(totalSkipped) tracks not found in library"
                        }
                        showImportSuccess = true
                        
                        Logger.info("M3U Import: \(totalPlaylists) playlists imported - \(totalTracks) found, \(totalSkipped) skipped")
                    }
                } catch {
                    errorMessage = "Failed to import M3U playlist(s): \(error.localizedDescription)"
                    showError = true
                    Logger.error("Failed to import M3U: \(error)")
                }
            }
        }
    }
    
    private func importFromFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose folders to import as playlists (max 25)"
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            
            guard !urls.isEmpty else { return }
            
            Task {
                isCreating = true
                defer { isCreating = false }
                
                do {
                    if urls.count == 1, let url = urls.first {
                        // Single folder import
                        let result = try await databaseManager.importPlaylistFromFolder(folderURL: url)
                        
                        // Show success message
                        importMessage = "Successfully imported '\(result.playlist.name)'\n\(result.foundCount) tracks added"
                        if result.skippedCount > 0 {
                            importMessage += "\n\(result.skippedCount) tracks not found in library"
                        }
                        showImportSuccess = true
                        
                        Logger.info("Folder Import: Success - \(result.foundCount) found, \(result.skippedCount) skipped")
                    } else {
                        // Multiple folders import
                        let results = try await databaseManager.importMultiplePlaylistsFromFolders(folderURLs: urls)
                        
                        if results.isEmpty {
                            errorMessage = "Failed to import any folders"
                            showError = true
                            return
                        }
                        
                        // Calculate totals
                        let totalPlaylists = results.count
                        let totalTracks = results.reduce(0) { $0 + $1.foundCount }
                        let totalSkipped = results.reduce(0) { $0 + $1.skippedCount }
                        
                        // Show success message
                        importMessage = "Successfully imported \(totalPlaylists) playlist\(totalPlaylists == 1 ? "" : "s") from folders\n\(totalTracks) tracks added"
                        if totalSkipped > 0 {
                            importMessage += "\n\(totalSkipped) tracks not found in library"
                        }
                        showImportSuccess = true
                        
                        Logger.info("Folder Import: \(totalPlaylists) playlists imported - \(totalTracks) found, \(totalSkipped) skipped")
                    }
                } catch {
                    errorMessage = "Failed to import folder(s): \(error.localizedDescription)"
                    showError = true
                    Logger.error("Failed to import folder: \(error)")
                }
            }
        }
    }
}

// MARK: - Color Scheme Button

struct ColorSchemeButton: View {
    let scheme: PlaylistColorScheme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(scheme.gradient)
                    .frame(width: 40, height: 40)
                    .overlay {
                        if isSelected {
                            Circle()
                                .stroke(Color.primary, lineWidth: 3)
                        }
                    }
                
                Text(scheme.displayName)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Playlist Color Scheme

enum PlaylistColorScheme: String, CaseIterable {
    case auto = "auto"
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case orange = "orange"
    case green = "green"
    case teal = "teal"
    
    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .green: return "Green"
        case .teal: return "Teal"
        }
    }
    
    var gradient: LinearGradient {
        switch self {
        case .auto:
            return LinearGradient(
                colors: [Color.gray.opacity(0.6), Color.gray],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .blue:
            return LinearGradient(
                colors: [Color.blue.opacity(0.6), Color.blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .purple:
            return LinearGradient(
                colors: [Color.purple.opacity(0.6), Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pink:
            return LinearGradient(
                colors: [Color.pink.opacity(0.6), Color.pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .red:
            return LinearGradient(
                colors: [Color.red.opacity(0.6), Color.red],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .orange:
            return LinearGradient(
                colors: [Color.orange.opacity(0.6), Color.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .green:
            return LinearGradient(
                colors: [Color.green.opacity(0.6), Color.green],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .teal:
            return LinearGradient(
                colors: [Color.teal.opacity(0.6), Color.teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Image Compressor

struct ImageCompressor {
    /// Compress image to standard size and quality
    /// - Parameters:
    ///   - image: Original NSImage
    ///   - maxSize: Maximum dimension (width or height) in pixels
    /// - Returns: Compressed JPEG data
    static func compress(image: NSImage, maxSize: CGFloat = 512) -> Data? {
        // Calculate new size maintaining aspect ratio
        let originalSize = image.size
        let aspectRatio = originalSize.width / originalSize.height
        
        var newSize: CGSize
        if originalSize.width > originalSize.height {
            newSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            newSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
        }
        
        // Create resized image
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        
        resizedImage.unlockFocus()
        
        // Convert to JPEG with 80% quality
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.8]
              ) else {
            return nil
        }
        
        Logger.info("Image compressed: Original size ~\(originalSize.width)x\(originalSize.height), New size \(newSize.width)x\(newSize.height), Data size: \(jpegData.count / 1024)KB")
        
        return jpegData
    }
}

// MARK: - Notification Extension

// MARK: - Preview

#Preview {
    CreatePlaylistView()
        .environmentObject(DatabaseManager.shared)
}

