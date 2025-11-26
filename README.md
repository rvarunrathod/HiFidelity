# HiFidelity

**A modern, offline-first music player for macOS with high-fidelity audio playback**

HiFidelity is a native macOS music player built for audiophiles and music enthusiasts who want complete control over their music library without relying on streaming services or cloud storage.

![Home View - Albums](docs/images/Home-page-albums.png)

---

## Features

### High-Fidelity Audio Playback
- Powered by the BASS audio library for professional-grade audio quality
- Support for 30+ audio formats including lossless and high-resolution files
- Built-in equalizer with customizable presets
- Advanced audio effects and DSP processing

### Comprehensive Format Support
HiFidelity supports 35+ audio formats:

**Lossless & Hi-Res**: FLAC, OGA, WAV, AIFF, AIF, APE, WV, TTA, DFF, DSF  
**Compressed**: MP3, MP2, AAC, OGG, OPUS, M4A, M4B, M4P, MP4, M4V, MPC  
**Specialized**: CAF, WEBM, SPX

### Smart Music Library
- Fast, local sqlite database for instant access to your entire library
- Automatic metadata extraction using TagLib
- Browse by tracks, albums, artists, or genres
- Embedded album artwork support
- Custom playlists with full management capabilities

### Intelligent Features
- **Smart Recommendations**: Auto play functionality, you don't have to think what to play next.
- **Lyrics Display**: Synced lyrics support with real-time highlighting
- **Advanced Search**: Find tracks instantly across your entire library
- **Play Queue Management**: Full control over what plays next
- **Playback History**: Keep track of what you've listened to
- **Favorites**: Mark and organize your favorite tracks

### Modern macOS Experience
- Beautiful native SwiftUI interface
- Menu bar controls and Now Playing info
- Optimized for Apple Silicon and Intel Macs

### Privacy-First Design
- 100% offline - no internet connection required
- Your music stays on your Mac
- No tracking, no analytics, no data collection
- Secure file access with macOS sandbox permissions

---

## Screenshots

### Library Views
<div align="center">
  <img src="docs/images/Album-view.png" alt="Album View" height="350" style="margin: 10px;">
  <img src="docs/images/Home-page-artists.png" alt="Artists View" height="350" style="margin: 10px;">
</div>

<div align="center">
  <img src="docs/images/Home-page-tracks.png" alt="Tracks View" height="350" style="margin: 10px;">
</div>

### Audio Features
<div align="center">
  <img src="docs/images/Equalizer.png" alt="Equalizer" height="400" style="margin: 10px;">
</div>

### Smart Features
<div align="center">
  <img src="docs/images/Autoplay-queue.png" alt="Autoplay Queue" height="350" style="margin: 10px;">
  <img src="docs/images/Lyrics%20support.png" alt="Lyrics Support" height="350" style="margin: 10px;">
</div>

<div align="center">
  <img src="docs/images/Search-view.png" alt="Search View" height="350" style="margin: 10px;">
</div>

---

## Requirements

- **macOS 14.0** (Sonoma) or later

---

## Installation

### From Source

1. Clone the repository:
```bash
git clone https://github.com/rvarunrathod/HiFidelity.git
cd HiFidelity
```

2. Open `HiFidelity.xcodeproj` in Xcode 15 or later

3. Build and run (⌘R)

### First Launch

1. Grant HiFidelity access to your music folders when prompted
2. Add folders containing your music files via **Settings → Library**
3. HiFidelity will automatically scan and import your music
4. Start enjoying your music collection!

---

## Technology Stack

HiFidelity is built with modern Apple technologies:

- **BASS Audio Library**: Professional audio engine
- **TagLib**: Metadata extraction
- **GRDB**: Fast, reliable local database
- **Sparkle**: A software update framework for macOS

---

## Privacy & Security

- **No Internet Required**: Works completely offline
- **No Data Collection**: We don't collect or transmit any data
- **Sandboxed**: Follows macOS security best practices
- **Secure File Access**: Uses security-scoped bookmarks for persistent file access

---

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

### Development Setup

1. Xcode 15+ required
2. Swift 6.0+ toolchain
3. All dependencies are included in the repository

---

## Support

- **GitHub Issues**: Report bugs and request features
- **Sponsor**: Support development

---

## Acknowledgments

- [**BASS Audio Library**](https://www.un4seen.com/)
- [**TagLib**](https://taglib.org/)
- [**GRDB**](https://github.com/groue/GRDB.swift)
- [**Sparkle**](https://github.com/sparkle-project/Sparkle)
- [**Petrichor**](https://github.com/kushalpandya/Petrichora): Learned lot from that code

---

**Built with ❤️ for music lovers who value quality, privacy, and control**

[Website](https://github.com/rvarunrathod/HiFidelity) • [Wiki](https://github.com/rvarunrathod/HiFidelity/wiki) • [Issues](https://github.com/rvarunrathod/HiFidelity/issues)

