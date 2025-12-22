//
//  NSTrackTableView.swift
//  HiFidelity
//
//  AppKit-based track table view with unlimited columns
//

import SwiftUI
import AppKit

/// NSTableView-based track table with unlimited columns
struct NSTrackTableView: NSViewRepresentable {
    
    /// Context for playlist-specific operations
    struct PlaylistContext {
        let playlist: PlaylistItem
        let onRemove: () -> Void
    }
    
    let tracks: [Track]
    @Binding var selection: Track.ID?
    @Binding var sortOrder: [KeyPathComparator<Track>]
    let onPlayTrack: (Track) -> Void
    let isCurrentTrack: (Track) -> Bool
    var playlistContext: PlaylistContext?
    
    @EnvironmentObject private var trackInfoManager: TrackInfoManager
    @EnvironmentObject private var appCoordinator: AppCoordinator
    @ObservedObject var playback = PlaybackController.shared
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        // Store reference in coordinator
        context.coordinator.tableView = tableView
        
        // Configure table view
        tableView.style = .fullWidth
        tableView.rowSizeStyle = .default
        tableView.allowsMultipleSelection = false
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        
        // Configure header view with context menu
        let headerView = NSTableHeaderView()
        headerView.menu = context.coordinator.createHeaderMenu()
        tableView.headerView = headerView
        
        // Set delegate and data source
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        
        // Configure scroll view
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // Add columns
        context.coordinator.setupColumns(tableView)
        
        // Restore column customization
        context.coordinator.restoreColumnState(tableView)
        
        // Set target/action for double-click
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClick(_:))
        
        // Enable context menu for rows
        tableView.menu = context.coordinator.createContextMenu()
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        
        // Check if tracks actually changed before reloading
        let tracksChanged = context.coordinator.tracks.count != tracks.count ||
                           !context.coordinator.tracks.elementsEqual(tracks, by: { $0.id == $1.id })
        
        // Update coordinator data
        context.coordinator.tracks = tracks
        context.coordinator.selection = $selection
        context.coordinator.onPlayTrack = onPlayTrack
        context.coordinator.isCurrentTrack = isCurrentTrack
        context.coordinator.playlistContext = playlistContext
        context.coordinator.sortOrder = $sortOrder
        
        // Only reload if tracks actually changed
        if tracksChanged {
            tableView.reloadData()
        }
        
        // Update selection
        if let selectedId = selection,
           let index = tracks.firstIndex(where: { $0.id == selectedId }),
           !tableView.selectedRowIndexes.contains(index) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if selection == nil && !tableView.selectedRowIndexes.isEmpty {
            tableView.deselectAll(nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            tracks: tracks,
            selection: $selection,
            sortOrder: $sortOrder,
            onPlayTrack: onPlayTrack,
            isCurrentTrack: isCurrentTrack,
            playlistContext: playlistContext
        )
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var tracks: [Track]
        var selection: Binding<Track.ID?>
        var sortOrder: Binding<[KeyPathComparator<Track>]>
        var onPlayTrack: (Track) -> Void
        var isCurrentTrack: (Track) -> Bool
        var playlistContext: NSTrackTableView.PlaylistContext?
        
        weak var tableView: NSTableView?
        private var columnIdentifiers: [ColumnType] = []
        
        init(
            tracks: [Track],
            selection: Binding<Track.ID?>,
            sortOrder: Binding<[KeyPathComparator<Track>]>,
            onPlayTrack: @escaping (Track) -> Void,
            isCurrentTrack: @escaping (Track) -> Bool,
            playlistContext: NSTrackTableView.PlaylistContext?
        ) {
            self.tracks = tracks
            self.selection = selection
            self.sortOrder = sortOrder
            self.onPlayTrack = onPlayTrack
            self.isCurrentTrack = isCurrentTrack
            self.playlistContext = playlistContext
            
            super.init()
            
            // Listen for global focus dismissal
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(dismissFocus),
                name: .dismissAllFocus,
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc private func dismissFocus() {
            // Make the table view resign first responder to lose focus
            DispatchQueue.main.async { [weak self] in
                if let window = self?.tableView?.window {
                    window.makeFirstResponder(nil)
                }
            }
        }
        
        // MARK: - NSTableViewDataSource
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            return tracks.count
        }
        
        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            guard row < tracks.count else { return nil }
            return tracks[row]
        }
        
        // MARK: - NSTableViewDelegate
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < tracks.count,
                  let columnId = tableColumn?.identifier,
                  let columnType = ColumnType(rawValue: columnId.rawValue) else {
                return nil
            }
            
            // Try to reuse cell view for better performance
            let reuseIdentifier = NSUserInterfaceItemIdentifier(columnType.rawValue + "Cell")
            
            let track = tracks[row]
            let isCurrent = isCurrentTrack(track)
            
            // Reuse or create cell view
            let cellView = tableView.makeView(withIdentifier: reuseIdentifier, owner: self) as? NSTableCellView
                         ?? NSTableCellView()
            cellView.identifier = reuseIdentifier
            
            // Clear previous content
            cellView.subviews.forEach { $0.removeFromSuperview() }
            
            return createCellContent(for: track, column: columnType, isCurrent: isCurrent, cellView: cellView)
        }
        
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            return 48 // Match SwiftUI table row height
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let selectedRow = tableView.selectedRow
            
            if selectedRow >= 0 && selectedRow < tracks.count {
                selection.wrappedValue = tracks[selectedRow].id
            } else {
                selection.wrappedValue = nil
            }
        }
        
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            // Handle sort descriptor changes
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key else { return }
            
            updateSortOrder(from: key, ascending: descriptor.ascending)
        }
        
        // MARK: - Column Setup
        
        func setupColumns(_ tableView: NSTableView) {
            columnIdentifiers = [
                .title, .artist, .album, .genre, .year,
                .trackNumber, .discNumber, .duration,
                .playCount, .codec, .dateAdded, .filename
            ]
            
            for columnType in columnIdentifiers {
                let column = createColumn(for: columnType)
                tableView.addTableColumn(column)
            }
        }
        
        private func createColumn(for type: ColumnType) -> NSTableColumn {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(type.rawValue))
            column.title = type.title
            column.minWidth = type.minWidth
            column.width = type.idealWidth
            column.maxWidth = type.maxWidth
            column.resizingMask = .userResizingMask
            
            // Set sort descriptor
            if let sortKey = type.sortKey {
                column.sortDescriptorPrototype = NSSortDescriptor(key: sortKey, ascending: true)
            }
            
            // Set initial visibility
            column.isHidden = type.defaultHidden
            
            return column
        }
        
        // MARK: - Cell Creation
        
        private func createCellContent(for track: Track, column: ColumnType, isCurrent: Bool, cellView: NSTableCellView) -> NSView? {
            switch column {
            case .title:
                return createTitleCell(track: track, isCurrent: isCurrent, cellView: cellView)
            case .artist:
                return createTextCell(text: track.artist, cellView: cellView)
            case .album:
                return createTextCell(text: track.album, cellView: cellView)
            case .genre:
                return createTextCell(text: track.genre, cellView: cellView)
            case .year:
                return createTextCell(text: track.year, cellView: cellView)
            case .trackNumber:
                return createNumberCell(value: track.trackNumber, cellView: cellView)
            case .discNumber:
                return createNumberCell(value: track.discNumber, cellView: cellView)
            case .duration:
                return createDurationCell(track: track, cellView: cellView)
            case .playCount:
                return createNumberCell(value: track.playCount, cellView: cellView)
            case .codec:
                return createTextCell(text: track.codec ?? "—", cellView: cellView)
            case .dateAdded:
                return createDateCell(date: track.dateAdded, cellView: cellView)
            case .filename:
                return createTextCell(text: track.filename, cellView: cellView)
            }
        }
        
        private func createTitleCell(track: Track, isCurrent: Bool, cellView: NSTableCellView) -> NSView {
            let containerView = NSView()
            
            // Artwork view
            let artworkView = NSImageView()
            artworkView.imageScaling = .scaleProportionallyUpOrDown
            artworkView.wantsLayer = true
            artworkView.layer?.cornerRadius = 4
            artworkView.translatesAutoresizingMaskIntoConstraints = false
            
            // Set placeholder first
            let placeholder = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
            artworkView.image = placeholder
            
            // Try to get cached artwork synchronously first
            if let trackId = track.trackId,
               let cachedArtwork = ArtworkCache.shared.getCachedArtwork(for: trackId, size: 40) {
                artworkView.image = cachedArtwork
            } else if let trackId = track.trackId  {
                // Load artwork asynchronously with weak capture
                ArtworkCache.shared.getArtwork(for: trackId, size: 40) { [weak artworkView] image in
                    DispatchQueue.main.async {
                        artworkView?.image = image ?? placeholder
                    }
                }
            }
            
            // Title label
            let titleLabel = NSTextField(labelWithString: track.title)
            titleLabel.font = isCurrent ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            
            containerView.addSubview(artworkView)
            containerView.addSubview(titleLabel)
            
            NSLayoutConstraint.activate([
                artworkView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
                artworkView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                artworkView.widthAnchor.constraint(equalToConstant: 40),
                artworkView.heightAnchor.constraint(equalToConstant: 40),
                
                titleLabel.leadingAnchor.constraint(equalTo: artworkView.trailingAnchor, constant: 10),
                titleLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
                titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8)
            ])
            
            cellView.addSubview(containerView)
            containerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                containerView.topAnchor.constraint(equalTo: cellView.topAnchor),
                containerView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: cellView.bottomAnchor)
            ])
            
            // Prefetch nearby artwork
            if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                prefetchArtwork(startingAt: index)
            }
            
            return cellView
        }
        
        private func createTextCell(text: String, cellView: NSTableCellView) -> NSView {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            
            cellView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8)
            ])
            
            return cellView
        }
        
        private func createNumberCell(value: Int?, cellView: NSTableCellView) -> NSView {
            let text = value.map { String($0) } ?? "—"
            let label = NSTextField(labelWithString: text)
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            
            cellView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8)
            ])
            
            return cellView
        }
        
        private func createDurationCell(track: Track, cellView: NSTableCellView) -> NSView {
            let label = NSTextField(labelWithString: track.formattedDuration)
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            
            cellView.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                label.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8)
            ])
            
            return cellView
        }
        
        private func createDateCell(date: Date?, cellView: NSTableCellView) -> NSView {
            let text = date.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none) } ?? "—"
            return createTextCell(text: text, cellView: cellView)
        }
        
        // MARK: - Actions
        
        @objc func doubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < tracks.count else { return }
            onPlayTrack(tracks[row])
        }
        
        func createContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            menu.identifier = NSUserInterfaceItemIdentifier("trackContextMenu")
            return menu
        }
        
        // MARK: - Context Menu for Tracks
        
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            
            // Check if this is the header menu (column visibility)
            if menu.identifier == NSUserInterfaceItemIdentifier("headerMenu") {
                updateHeaderMenu(menu)
                return
            }
            
            // Otherwise it's the track context menu
            guard let tableView = tableView else { return }
            
            // Get the clicked row
            let row = tableView.clickedRow
            guard row >= 0 && row < tracks.count else { return }
            
            let track = tracks[row]
            
            // Playback actions
            let playItem = NSMenuItem(title: "Play", action: #selector(playTrack(_:)), keyEquivalent: "")
            playItem.target = self
            playItem.representedObject = track
            menu.addItem(playItem)
            
            let playNextItem = NSMenuItem(title: "Play Next", action: #selector(playNext(_:)), keyEquivalent: "")
            playNextItem.target = self
            playNextItem.representedObject = track
            menu.addItem(playNextItem)
            
            let queueItem = NSMenuItem(title: "Add to Queue", action: #selector(addToQueue(_:)), keyEquivalent: "")
            queueItem.target = self
            queueItem.representedObject = track
            menu.addItem(queueItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // Add to Playlist submenu
            let addToPlaylistItem = NSMenuItem(title: "Add to Playlist", action: nil, keyEquivalent: "")
            let playlistSubmenu = NSMenu()
            
            let newPlaylistItem = NSMenuItem(title: "New Playlist...", action: #selector(createPlaylistWithTrack(_:)), keyEquivalent: "")
            newPlaylistItem.target = self
            newPlaylistItem.representedObject = track
            playlistSubmenu.addItem(newPlaylistItem)
            
            // Get user playlists
            let userPlaylists = DatabaseCache.shared.allPlaylists.filter { !$0.isSmart }
            if !userPlaylists.isEmpty {
                playlistSubmenu.addItem(NSMenuItem.separator())
                for playlist in userPlaylists {
                    let playlistItem = NSMenuItem(title: playlist.name, action: #selector(addToPlaylist(_:)), keyEquivalent: "")
                    playlistItem.target = self
                    playlistItem.representedObject = (track, playlist)
                    playlistSubmenu.addItem(playlistItem)
                }
            }
            
            addToPlaylistItem.submenu = playlistSubmenu
            menu.addItem(addToPlaylistItem)
            
            // Remove from playlist (if in playlist context)
            if let context = playlistContext, !context.playlist.isSmart {
                let removeItem = NSMenuItem(title: "Remove from Playlist", action: #selector(removeFromPlaylist(_:)), keyEquivalent: "")
                removeItem.target = self
                removeItem.representedObject = (track, context)
                menu.addItem(removeItem)
            }
            
            menu.addItem(NSMenuItem.separator())
            
            // File system actions
            let finderItem = NSMenuItem(title: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
            finderItem.target = self
            finderItem.representedObject = track
            menu.addItem(finderItem)
            
            let infoItem = NSMenuItem(title: "Get Info", action: #selector(showTrackInfo(_:)), keyEquivalent: "")
            infoItem.target = self
            infoItem.representedObject = track
            menu.addItem(infoItem)
            
            menu.addItem(NSMenuItem.separator())
            
            // Navigation actions (only show if not unknown)
            var hasNavigationItems = false
            
            if !track.album.isEmpty && track.album != "Unknown Album" {
                let goToAlbumItem = NSMenuItem(title: "Go to Album '\(track.album)'", action: #selector(goToAlbum(_:)), keyEquivalent: "")
                goToAlbumItem.target = self
                goToAlbumItem.representedObject = track
                menu.addItem(goToAlbumItem)
                hasNavigationItems = true
            }
            
            if !track.artist.isEmpty && track.artist != "Unknown Artist" {
                let goToArtistItem = NSMenuItem(title: "Go to Artist '\(track.artist)'", action: #selector(goToArtist(_:)), keyEquivalent: "")
                goToArtistItem.target = self
                goToArtistItem.representedObject = track
                menu.addItem(goToArtistItem)
                hasNavigationItems = true
            }

            
            if hasNavigationItems {
                menu.addItem(NSMenuItem.separator())
            }

            
            // R128 Scanning submenu (only if enabled)
            if ReplayGainSettings.shared.isEnabled {
                let scanR128Item = NSMenuItem(title: "Scan R128 Loudness", action: nil, keyEquivalent: "")
                let scanSubmenu = NSMenu()
                
                let scanTrackItem = NSMenuItem(title: "This Track", action: #selector(scanTrackR128(_:)), keyEquivalent: "")
                scanTrackItem.target = self
                scanTrackItem.representedObject = track
                scanSubmenu.addItem(scanTrackItem)
                
                let scanAlbumItem = NSMenuItem(title: "Album '\(track.album)'", action: #selector(scanAlbumR128(_:)), keyEquivalent: "")
                scanAlbumItem.target = self
                scanAlbumItem.representedObject = track
                scanSubmenu.addItem(scanAlbumItem)
                
                let scanArtistItem = NSMenuItem(title: "Artist '\(track.artist)'", action: #selector(scanArtistR128(_:)), keyEquivalent: "")
                scanArtistItem.target = self
                scanArtistItem.representedObject = track
                scanSubmenu.addItem(scanArtistItem)
                
                scanR128Item.submenu = scanSubmenu
                menu.addItem(scanR128Item)
                
                menu.addItem(NSMenuItem.separator())
            }
            
            // Favorite toggle
            let favoriteTitle = track.isFavorite ? "Remove from Favorites" : "Add to Favorites"
            let favoriteItem = NSMenuItem(title: favoriteTitle, action: #selector(toggleFavorite(_:)), keyEquivalent: "")
            favoriteItem.target = self
            favoriteItem.representedObject = track
            menu.addItem(favoriteItem)
        }
        
        private func updateHeaderMenu(_ menu: NSMenu) {
            // Update menu item states based on current column visibility
            guard let tableView = tableView else { return }
            
            for columnType in ColumnType.allCases {
                let menuItem = NSMenuItem(
                    title: columnType.title,
                    action: #selector(toggleColumn(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = columnType.rawValue
                menuItem.isEnabled = true
                
                // Set checkmark based on visibility
                let identifier = NSUserInterfaceItemIdentifier(columnType.rawValue)
                if let column = tableView.tableColumn(withIdentifier: identifier) {
                    menuItem.state = column.isHidden ? .off : .on
                }
                
                menu.addItem(menuItem)
            }
        }
        
        // MARK: - Context Menu Actions
        
        @objc func playTrack(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.playTrack(track)
        }
        
        @objc func playNext(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.playNext(track)
        }
        
        @objc func addToQueue(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.addToQueue(track)
        }
        
        @objc func createPlaylistWithTrack(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.showCreatePlaylist(with: track)
        }
        
        @objc func addToPlaylist(_ sender: NSMenuItem) {
            guard let (track, playlist) = sender.representedObject as? (Track, Playlist) else { return }
            TrackContextMenuBuilder.addToPlaylist(track, playlist: playlist)
        }
        
        @objc func removeFromPlaylist(_ sender: NSMenuItem) {
            guard let (track, context) = sender.representedObject as? (Track, NSTrackTableView.PlaylistContext) else { return }
            TrackContextMenuBuilder.removeFromPlaylist(track, playlistItem: context.playlist, onRemove: context.onRemove)
        }
        
        @objc func showInFinder(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.showInFinder(track)
        }
        
        @objc func showTrackInfo(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.showTrackInfo(track)
        }
        
        @objc func toggleFavorite(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.toggleFavorite(track)
        }
        
        @objc func scanTrackR128(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.scanTrackR128(track)
        }
        
        @objc func scanAlbumR128(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.scanAlbumR128(track)
        }
        
        @objc func scanArtistR128(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.scanArtistR128(track)
        }
        
        @objc func goToAlbum(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.navigateToAlbum(track)
        }
        
        @objc func goToArtist(_ sender: NSMenuItem) {
            guard let track = sender.representedObject as? Track else { return }
            TrackContextMenuBuilder.navigateToArtist(track)
        }

        
        func createHeaderMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.delegate = self
            menu.identifier = NSUserInterfaceItemIdentifier("headerMenu")
            return menu
        }
        
        @objc func toggleColumn(_ sender: NSMenuItem) {
            guard let tableView = tableView,
                  let columnId = sender.representedObject as? String else { return }
            
            let identifier = NSUserInterfaceItemIdentifier(columnId)
            if let column = tableView.tableColumn(withIdentifier: identifier) {
                column.isHidden.toggle()
                
                // Update menu item state
                sender.state = column.isHidden ? .off : .on
                
                // Save column state
                saveColumnState(tableView)
            }
        }
        
        // MARK: - Sorting
        
        private func updateSortOrder(from key: String, ascending: Bool) {
            let order: SortOrder = ascending ? .forward : .reverse
            
            let comparator: KeyPathComparator<Track>
            switch key {
            case "title": comparator = KeyPathComparator(\.title, order: order)
            case "artist": comparator = KeyPathComparator(\.artist, order: order)
            case "album": comparator = KeyPathComparator(\.album, order: order)
            case "genre": comparator = KeyPathComparator(\.genre, order: order)
            case "year": comparator = KeyPathComparator(\.year, order: order)
            case "trackNumber": comparator = KeyPathComparator(\.trackNumber, order: order)
            case "discNumber": comparator = KeyPathComparator(\.discNumber, order: order)
            case "duration": comparator = KeyPathComparator(\.duration, order: order)
            case "playCount": comparator = KeyPathComparator(\.playCount, order: order)
            case "codec": comparator = KeyPathComparator(\.sortableCodec, order: order)
            case "dateAdded": comparator = KeyPathComparator(\.sortableDateAdded, order: order)
            case "filename": comparator = KeyPathComparator(\.filename, order: order)
            default: return
            }
            
            sortOrder.wrappedValue = [comparator]
        }
        
        // MARK: - Column Persistence
        
        func restoreColumnState(_ tableView: NSTableView) {
            // Restore from UserDefaults
            if let data = UserDefaults.standard.data(forKey: "nsTableColumnState"),
               let state = try? JSONDecoder().decode(ColumnState.self, from: data) {
                
                for (identifier, width) in state.columnWidths {
                    if let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(identifier)) {
                        column.width = width
                    }
                }
                
                for (identifier, hidden) in state.columnVisibility {
                    if let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(identifier)) {
                        column.isHidden = hidden
                    }
                }
            }
        }
        
        func saveColumnState(_ tableView: NSTableView) {
            var widths: [String: CGFloat] = [:]
            var visibility: [String: Bool] = [:]
            
            for column in tableView.tableColumns {
                let id = column.identifier.rawValue
                widths[id] = column.width
                visibility[id] = column.isHidden
            }
            
            let state = ColumnState(columnWidths: widths, columnVisibility: visibility)
            if let data = try? JSONEncoder().encode(state) {
                UserDefaults.standard.set(data, forKey: "nsTableColumnState")
            }
        }
        
        // MARK: - Prefetching
        
        private func prefetchArtwork(startingAt index: Int) {
            // Prefetch next 20 tracks' artwork for smooth scrolling
            let endIndex = min(index + 20, tracks.count)
            guard endIndex > index else { return }
            
            let trackIds = tracks[index..<endIndex].compactMap { $0.trackId }
            ArtworkCache.shared.preloadArtwork(for: trackIds, size: 40)
        }
    }
}

// MARK: - Column Types

enum ColumnType: String, CaseIterable {
    case title
    case artist
    case album
    case genre
    case year
    case trackNumber
    case discNumber
    case duration
    case playCount
    case codec
    case dateAdded
    case filename
    
    var title: String {
        switch self {
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .genre: return "Genre"
        case .year: return "Year"
        case .trackNumber: return "Track #"
        case .discNumber: return "Disc #"
        case .duration: return "Duration"
        case .playCount: return "Play Count"
        case .codec: return "Codec"
        case .dateAdded: return "Date Added"
        case .filename: return "Filename"
        }
    }
    
    var minWidth: CGFloat {
        switch self {
        case .title: return 200
        case .artist, .album: return 100
        case .genre: return 80
        case .year: return 60
        case .trackNumber, .discNumber: return 50
        case .duration: return 70
        case .playCount: return 60
        case .codec: return 60
        case .dateAdded: return 90
        case .filename: return 100
        }
    }
    
    var idealWidth: CGFloat {
        switch self {
        case .title: return 300
        case .artist, .album: return 180
        case .genre: return 120
        case .year: return 80
        case .trackNumber, .discNumber: return 60
        case .duration: return 80
        case .playCount: return 80
        case .codec: return 80
        case .dateAdded: return 120
        case .filename: return 180
        }
    }
    
    var maxWidth: CGFloat {
        switch self {
        case .title, .artist, .album: return 500
        case .filename: return 300
        case .genre: return 200
        case .year: return 100
        case .trackNumber, .discNumber: return 80
        case .duration, .playCount: return 100
        case .codec: return 120
        case .dateAdded: return 150
        }
    }
    
    var defaultHidden: Bool {
        switch self {
        case .title, .artist, .album, .year, .duration: return false
        default: return true
        }
    }
    
    var sortKey: String? {
        return rawValue
    }
}

// MARK: - Column State

struct ColumnState: Codable {
    var columnWidths: [String: CGFloat]
    var columnVisibility: [String: Bool]
}

// MARK: - Track Extension for Sorting

extension Track {
   // These provide non-optional values for Table sorting
   
   var sortableTrackNumber: Int {
       trackNumber ?? Int.max
   }
   
   var sortableDiscNumber: Int {
       discNumber ?? Int.max
   }
   
   var sortableBitrate: Int {
       bitrate ?? 0
   }
   
   var sortableSampleRate: Int {
       sampleRate ?? 0
   }
   
   var sortablePlayCount: Int {
       playCount
   }
   
   var sortableDateAdded: Date {
       dateAdded ?? Date.distantPast
   }
   
   var sortableAlbumArtist: String {
       albumArtist ?? ""
   }
   
   var sortableCodec: String {
       codec ?? ""
   }
}
