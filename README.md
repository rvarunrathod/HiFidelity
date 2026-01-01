# HiFidelity
<img width="170" src="./HiFidelity/Assets.xcassets/AppIcon.appiconset/Icon-macOS-Dark-512x512@1x.png" alt="HiFidelity App Icon" align="left"/>

<div>
<h3>HiFidelity</h3>
<p>A modern, offline-first audiophile music player for macOS with high-fidelity audio playback</p>
<a href="https://github.com/rvarunrathod/HiFidelity/releases/latest"><img src="docs/assets/macos_download.png" width="140" alt="Download for macOS"/></a>
</div>

<br/><br/>

<p align="center">
  <a href="https://github.com/rvarunrathod/HiFidelity/releases">
    <img alt="GitHub Downloads (all assets, all releases)" src="https://img.shields.io/github/downloads/rvarunrathod/HiFidelity/total?label=Downloads&style=flat-square&color=blue">
  </a>
  <a href="https://github.com/rvarunrathod/HiFidelity/releases/latest">
    <img alt="Latest Release" src="https://img.shields.io/github/v/release/rvarunrathod/HiFidelity?label=Latest%20Release&style=flat-square&color=00796b">
  </a>
  <a href="https://github.com/rvarunrathod/HiFidelity/">
    <img src="https://img.shields.io/badge/platform-macOS-blue.svg?label=Platform&style=flat-square&logo=apple" alt="Platform"/>
  </a>
</p>

<p align="center">
  <a href="https://github.com/rvarunrathod/HiFidelity/stargazers">
    <img src="https://img.shields.io/badge/⭐%20Give%20a%20Star-Support%20the%20project-orange?style=for-the-badge" alt="Give a Star">
  </a>
</p>



![HiFidelity Music Player](docs/images/musicPlayer.png)


---

## Guide for DMG Installation

> [!IMPORTANT]
>  
> After you install the Application and try to open it, you will see message like this: *Apple could not verify “HiFidelity.app” is free of malware that may harm your Mac or compromise your privacy.*
>
> ## Solution
> you have to bypass Gatekeeper for this (I don't want to pay apple for opensource apps)
> This will solve the occupation issue
> 
> ` xattr -d com.apple.quarantine /Applications/HiFidelity.app` 

## ✨ Features

- Powered by the BASS (un4seen) audio library for professional-grade audio quality and TagLib for meta-data reading
- Support for 10+ audio formats including lossless and high-resolution files
  - **Lossless & Hi-Res**: FLAC, OGA, WAV, AIFF, AIF, APE, WV, TTA, DFF, DSF  
  - **Compressed**: MP3, MP2, AAC, OGG, OPUS, M4A, M4B, M4P, MP4, M4V, MPC  
  - **Specialized**: CAF, WEBM, SPX
- **Bit-perfect playback** with sample rate synchronization and Obtain Exclusive Access of audio device **(Hog mode)**
- **Gapless Playback**: Seamless transitions between tracks with no silence or interruption
- **ReplayGain**: Replay Gain from metadata or EBU R128 louness normalization (turn on replayGain from audio settings) (to scan for R128 loudness, right click on track -> scan for track/album/artists -> press refresh button to load calculated value)
- Built-in equalizer with customizable presets
- Browse by tracks, albums, artists, or genres
- **Smart Recommendations**: Auto play functionality, you don't have to think what to play next
- **Lyrics Support**:
  - Download lyrics directly within the app from [lrclib](https://lrclib.net/)
  - Real-time line-by-line lyrics highlighting
- **Mini Player**: Compact floating window with integrated queue and lyrics panels
- **Audio device change** option within UI
- **Advanced Search**: Find tracks instantly across your entire library with FTS5 (Rebuild search index if you not able to see any results: Settings -> Advanced -> Rebuild FTS)
- **Playback History**: Keep track of what you've listened to
- **Favorites**: Mark and organize your favorite tracks
- Import playlist with m3u or Import Folder as playlist
- Menu bar controls and Now Playing info

## 🔮 Upcoming Features

- ~~Automatic scanning and updating of the music library~~ ( ✅ [1.0.4](https://github.com/rvarunrathod/HiFidelity/releases/tag/v1.0.4) )
- ~~A compact Mini Player mode~~ ( ✅ [1.0.5](https://github.com/rvarunrathod/HiFidelity/releases/tag/v1.0.5) )
- ~~Let user change audio output device from UI~~ ( ✅ [1.0.6](https://github.com/rvarunrathod/HiFidelity/releases/tag/v1.0.6) ) 
- ~~ReplayGain and volume normalization~~ ( ✅ [1.0.8](https://github.com/rvarunrathod/HiFidelity/releases/tag/v1.0.8) ) 
- Audio visualizers (waveform / spectrum)
- ... 

## 📷 Screenshots & Demos

#### Audio Features
<div align="center">
  <img src="docs/images/Equalizer.png" alt="Equalizer" width="600" style="margin: 10px;">
</div>



#### Smart Features & Demos
<div align="center">
  <table border="0">
    <tr>
      <td width="50%" align="center">
        <b>Mini Player</b><br>
        <video src="https://github.com/user-attachments/assets/9f7c32b4-80f8-41e7-90a1-afa1394e65e1" controls width="100%"></video>
      </td>
      <td width="50%" align="center">
        <b>Lyrics Support</b><br>
        <video src="https://github.com/user-attachments/assets/03c41edd-96ef-4c41-8b21-2bba1f59e535" controls width="100%"></video>
      </td>
    </tr>
    <tr>
      <td width="50%" align="center">
        <b>Advanced Search</b><br>
        <video src="https://github.com/user-attachments/assets/eded563a-a699-46eb-82c6-3e8a4c0cd019" controls width="100%"></video>
      </td>
      <td width="50%" align="center">
        <b>Autoplay Queue</b><br>
        <video src="https://github.com/user-attachments/assets/ef5f1d09-e1fb-4369-b8ac-1c7feafaab59" controls width="100%"></video>
      </td>
    </tr>
  </table>
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

---

<div align="center">
<h3>Built with ❤️ for music lovers who value quality, privacy, and control</h3>
</div>
