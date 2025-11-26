#
#  audio-gen.sh
#  HiFidelity
#
#  Created by Varun Rathod on 24/11/25.


#!/bin/bash
# ============================================================
# Convert a single FLAC file into ALL BASS-supported formats
# Embed album art ONLY where supported
# ============================================================

INPUT="$1"

if [ -z "$INPUT" ]; then
    echo "Usage: $0 <input.flac>"
    exit 1
fi

if [ ! -f "$INPUT" ]; then
    echo "Error: File not found: $INPUT"
    exit 1
fi

OUTDIR="bass_converted"
mkdir -p "$OUTDIR"

NAME=$(basename "$INPUT" .flac)
BASE="$OUTDIR/$NAME"

echo "Converting: $INPUT"
echo "Output directory: $OUTDIR"
echo

# ------------------------------------------------------------
# Extract album art (JPEG)
# ------------------------------------------------------------
COVER="$OUTDIR/cover.jpg"
ffmpeg -loglevel error -y -i "$INPUT" -an -vcodec mjpeg "$COVER"

HAS_COVER=0
if [ -f "$COVER" ]; then
    HAS_COVER=1
    echo "✓ Album art extracted"
else
    echo "⚠ No album art found in input"
fi

echo

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
# Audio-only conversion (no cover)
convert_audio() {
    local codec="$1"
    local outfile="$2"
    ffmpeg -loglevel error -y -i "$INPUT" -map 0:a -vn -c:a "$codec" "$outfile"
}

# Audio + cover (only allowed formats)
convert_with_art_mp4() {
    local outfile="$2"
    echo "→ Creating $outfile (with art)"
    ffmpeg -loglevel error -y \
        -i "$INPUT" -i "$COVER" \
        -map 0:a -map 1:v \
        -c:a aac -c:v copy \
        -f mp4 \
        "$outfile"
}

convert_with_art_mp3() {
    local outfile="$1"
    echo "→ Creating $outfile (with art)"
    ffmpeg -loglevel error -y \
        -i "$INPUT" -i "$COVER" \
        -map 0:a -map 1:v \
        -c:a libmp3lame -c:v copy \
        "$outfile"
}

convert_with_art_flac() {
    local outfile="$1"
    echo "→ Creating $outfile (with art)"
    ffmpeg -loglevel error -y \
        -i "$INPUT" -i "$COVER" \
        -map 0:a -map 1:v \
        -c:a flac -c:v copy \
        -f flac \
        "$outfile"
}

convert_with_art_mka() {
    local outfile="$1"
    echo "→ Creating $outfile (with art)"
    ffmpeg -loglevel error -y \
        -i "$INPUT" -i "$COVER" \
        -map 0:a -map 1:v \
        -c:a flac -c:v copy \
        -f matroska \
        "$outfile"
}

convert_with_art_ape() {
    local outfile="$1"
    echo "→ Creating $outfile (with art)"
    ffmpeg -loglevel error -y \
        -i "$INPUT" \
        -c:a ape \
        "$outfile"
    # Embed art using APEv2 tagging (Monkey's Audio doesn't support streams)
    apetag="$outfile.apetag"
    ffmpeg -loglevel error -y -i "$COVER" -f apetag "$apetag"
}

# ------------------------------------------------------------
# SUPPORTED ART FORMATS
# ------------------------------------------------------------

# MP3 (with art)
if [ $HAS_COVER -eq 1 ]; then
    convert_with_art_mp3 "$BASE.mp3"
else
    convert_audio libmp3lame "$BASE.mp3"
fi

# FLAC (with art)
if [ $HAS_COVER -eq 1 ]; then
    convert_with_art_flac "$BASE.flac"
else
    convert_audio flac "$BASE.flac"
fi

# MP4-family (with art)
EXTS_MP4=(m4a m4b mp4 m4v m4p)
for ext in "${EXTS_MP4[@]}"; do
    if [ $HAS_COVER -eq 1 ]; then
        convert_with_art_mp4 "$INPUT" "$BASE.$ext"
    else
        convert_audio aac "$BASE.$ext"
    fi
done

# MKA (with art)
if [ $HAS_COVER -eq 1 ]; then
    convert_with_art_mka "$BASE.mka"
else
    convert_audio flac "$BASE.mka"
fi

# APE (art embedded via APE tag)
if ffmpeg -hide_banner -encoders | grep -q ape; then
    if [ $HAS_COVER -eq 1 ]; then
        convert_with_art_ape "$BASE.ape"
    else
        convert_audio ape "$BASE.ape"
    fi
else
    echo "⚠ Skipping .ape (encoder not available)"
fi


# ------------------------------------------------------------
# NON-ART FORMATS
# ------------------------------------------------------------

echo
echo "→ Creating non-art formats..."

# MP1 — force MPEG format
echo "→ Creating $BASE.mp1"
ffmpeg -loglevel error -y -i "$INPUT" -map 0:a -vn -c:a mp2 -f mp3 "$BASE.mp1"

# MP2
convert_audio mp2 "$BASE.mp2"

# OGG / OPUS / WV / TTA / SPX (all supported muxers)
convert_audio libvorbis  "$BASE.ogg"
convert_audio libopus    "$BASE.opus"
convert_audio wavpack    "$BASE.wv"
convert_audio tta        "$BASE.tta"
convert_audio libspeex   "$BASE.spx"

# Musepack (.mpc) — NOT SUPPORTED by your FFmpeg
if ffmpeg -hide_banner -formats | grep -q " mpck"; then
    convert_audio musepack "$BASE.mpc"
else
    echo "⚠ Skipping $BASE.mpc (Musepack muxer not supported in your FFmpeg)"
fi

# WAV / AIFF / CAF
convert_audio pcm_s16le  "$BASE.wav"
convert_audio pcm_s16be  "$BASE.aiff"
convert_audio pcm_s16be  "$BASE.aif"
convert_audio pcm_s16le  "$BASE.caf"

# WEBM
ffmpeg -loglevel error -y -i "$INPUT" -map 0:a -c:a libopus -f webm "$BASE.webm"

# DSD formats (.dsf / .dff) — unsupported by your FFmpeg
if ffmpeg -hide_banner -formats | grep -q " dsf"; then
    convert_audio dsd_lsbf "$BASE.dsf"
else
    echo "⚠ Skipping $BASE.dsf (DSF muxer not supported in your FFmpeg)"
fi

if ffmpeg -hide_banner -formats | grep -q " dff"; then
    convert_audio dsd_lsbf "$BASE.dff"
else
    echo "⚠ Skipping $BASE.dff (DFF muxer not supported in your FFmpeg)"
fi


echo
echo "✔ DONE — artwork only embedded where supported"
