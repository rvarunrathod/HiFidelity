# HiFidelity
<img width="170" src="docs/assets/AppIcon512x512.png" alt="HiFidelity App Icon" align="left"/>

<div>
<h3>HiFidelity</h3>
<p>A modern, offline-first music player for macOS with high-fidelity audio playback</p>
<a href="https://github.com/rvarunrathod/HiFidelity/releases/latest"><img src="docs/assets/macos_download.png" width="140" alt="Download for macOS"/></a>
</div>
<br/><br/>

<div align="center">
<a href="https://github.com/rvarunrathod/HiFidelity/releases"><img alt="GitHub Downloads (all assets, all releases)" src="https://img.shields.io/github/downloads/rvarunrathod/HiFidelity/total?label=Downloads&style=flat-square&color=ba68c8"></a>
<a href="https://github.com/rvarunrathod/HiFidelity/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/rvarunrathod/HiFidelity?label=Stars&style=flat-square&color=f9a825"></a>
<a href="https://github.com/rvarunrathod/HiFidelity/blob/main/LICENSE"><img alt="License" src="https://img.shields.io/github/license/rvarunrathod/HiFidelity?label=License&style=flat-square&color=388e3c"></a>
<a href="https://github.com/rvarunrathod/HiFidelity/releases/latest"><img alt="Latest Release" src="https://img.shields.io/github/v/release/rvarunrathod/HiFidelity?label=Latest%20Release&style=flat-square&color=00796b"></a>
<a href="https://github.com/rvarunrathod/HiFidelity/"><img src="https://img.shields.io/badge/platform-macOS-blue.svg?label=Platform&style=flat-square&logo=apple" alt="Platform"/></a>
  
</div>



![Home View - Albums](docs/images/Home-page-albums.png)


---

## ✨ Features

- Powered by the BASS (un4seen) audio library for professional-grade audio quality and TagLib for meta-data reading
- Support for 10+ audio formats including lossless and high-resolution files
  - **Lossless & Hi-Res**: FLAC, OGA, WAV, AIFF, AIF, APE, WV, TTA, DFF, DSF  
  - **Compressed**: MP3, MP2, AAC, OGG, OPUS, M4A, M4B, M4P, MP4, M4V, MPC  
  - **Specialized**: CAF, WEBM, SPX
- **Gapless Playback**: Seamless transitions between tracks with no silence or interruption
- Built-in equalizer with customizable presets
- Browse by tracks, albums, artists, or genres
- **Smart Recommendations**: Auto play functionality, you don't have to think what to play next
- **Lyrics**: Directly download lyrics within App and, Synced lyrics support with real-time highlighting powered by [lrclib](https://lrclib.net/)
- **Advanced Search**: Find tracks instantly across your entire library with FTS5 
- **Playback History**: Keep track of what you've listened to
- **Favorites**: Mark and organize your favorite tracks
- Menu bar controls and Now Playing info

## 🔮 Upcoming Features

- ReplayGain and volume normalization 
- Automatic scanning and updating of the music library
- let user change audio output device from UI
- Audio visualizers  (waveform / spectrum)
- A compact Mini Player mode 
- ... 

## 📷 Screenshots

#### Library Views
<div align="center">
  <img src="docs/images/Album-view.png" alt="Album View" width="600" style="margin: 10px;">
  <img src="docs/images/Home-page-artists.png" alt="Artists View" width="600" style="margin: 10px;">
  <img src="docs/images/Home-page-tracks.png" alt="Tracks View" width="600" style="margin: 10px;">
</div>

#### Audio Features
<div align="center">
  <img src="docs/images/Equalizer.png" alt="Equalizer" width="600" style="margin: 10px;">
</div>

#### Smart Features
<div align="center">
  <img src="docs/images/Autoplay-queue.png" alt="Autoplay Queue" height="400" style="margin: 10px;">
  <img src="docs/images/Lyrics%20support.png" alt="Lyrics Support" height="400" style="margin: 10px;">
  <img src="docs/images/Search-view.png" alt="Search View" height="500" width="600" style="margin: 10px;">
</div>

## 🛠 Requirements

- **macOS 14.0** (Sonoma) or later
- Apple Silicon or Intel Macs 

## 📥 Installation

#### 🍺 Install via Homebrew (Recommended)

```bash
brew tap rvarunrathod/tap
brew install --cask rvarunrathod/tap/hifidelity
```

#### Download for macOS
  
- You can download the latest signed macOS build from the Releases page:
- **[Download Latest Release](https://github.com/rvarunrathod/HiFidelity/releases/latest)**
- After downloading, move **HiFidelity.app** to your **Applications** folder.

#### First Launch?

1. Open **Settings → Library** Add folders containing your music files.
2. HiFidelity will automatically scan and import your music.
3. Start enjoying your music collection!

## ⚡ Development 

- Make sure you’re running macOS 14 or later
- Clone the repository
- Open `HiFidelity.xcodeproj` in Xcode 15 or later

---

#### Privacy & Security

- **No Internet Required**: Works completely offline
- **No Data Collection**: This app don't collect or transmit any data
- **Sandboxed**: Follows macOS security best practices

#### Acknowledgments

- [**BASS Audio Library**](https://www.un4seen.com/): Professional audio engine
- [**TagLib**](https://taglib.org/): Metadata extraction
- [**GRDB**](https://github.com/groue/GRDB.swift): Fast, reliable local database
- [**Sparkle**](https://github.com/sparkle-project/Sparkle): A software update framework for macOS
- [**Lrclib**](https://lrclib.net/): Utility for mass-downloading LRC synced lyrics for your offline music library. 
- [**Petrichor**](https://github.com/kushalpandya/Petrichora): Learned lot from this code

---
<div align="center">
<h3>⭐ If you like this project, please give it a star!</h3>
</div>
