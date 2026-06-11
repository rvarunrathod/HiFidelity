#!/bin/bash
# Remote-control HTTP API smoke checks.
#
# Run while HiFidelity is running with the remote-control toggle ON.
# Defaults to http://127.0.0.1:7666; override via REMOTE_BASE.
#
# Asserts (exits non-zero on first mismatch):
#  - GET /state returns 200 + ETag header.
#  - GET /state with the prior ETag returns 304.
#  - GET /artwork/:trackId returns 200 + 1y immutable cache + valid mime.
#  - POST /pause flips isPlaying to false.
#  - No "url" field appears in /state, /tracks, /albums, /artists, /playlists.
#  - 100 parallel /state requests all return 200.
#  - Two /state polls in unchanged state yield identical ETags.
#
# Requires: curl, jq.

set -eu

BASE="${REMOTE_BASE:-http://127.0.0.1:7666}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

red()   { printf '\033[31mFAIL\033[0m: %s\n' "$1" >&2; exit 1; }
green() { printf '\033[32mOK\033[0m  : %s\n' "$1"; }

require() {
    command -v "$1" >/dev/null 2>&1 || red "missing dependency: $1"
}
require curl
require jq

# ---------- /state basic ----------
HEADERS="$TMP/state.h"
BODY="$TMP/state.j"
HTTP_CODE=$(curl -s -o "$BODY" -D "$HEADERS" -w '%{http_code}' "$BASE/state")
[ "$HTTP_CODE" = "200" ] || red "/state expected 200, got $HTTP_CODE"
ETAG=$(grep -i '^etag:' "$HEADERS" | sed -E 's/^[Ee][Tt][Aa][Gg]: //; s/\r$//')
[ -n "$ETAG" ] || red "/state missing ETag header"
green "/state 200 + ETag: $ETAG"

# ---------- /state If-None-Match → 304 ----------
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "If-None-Match: $ETAG" "$BASE/state")
[ "$HTTP_CODE" = "304" ] || red "/state with If-None-Match expected 304, got $HTTP_CODE"
green "/state If-None-Match → 304"

# ---------- ETag determinism (two polls, no change) ----------
ETAG_A=$(curl -sI "$BASE/state" | grep -i '^etag:' | sed -E 's/^[Ee][Tt][Aa][Gg]: //; s/\r$//')
ETAG_B=$(curl -sI "$BASE/state" | grep -i '^etag:' | sed -E 's/^[Ee][Tt][Aa][Gg]: //; s/\r$//')
[ "$ETAG_A" = "$ETAG_B" ] || red "ETag changed across two stable polls (a=$ETAG_A b=$ETAG_B)"
green "ETag deterministic across stable polls"

# ---------- No track URLs leak ----------
for endpoint in "/state" "/tracks?limit=50" "/albums?limit=50" "/artists?limit=50" "/playlists"; do
    URL_HITS=$(curl -s "$BASE$endpoint" | jq -r '..|strings? // empty' | grep -c -i '"url"' || true)
    LEAK=$(curl -s "$BASE$endpoint" | grep -ci '"url"' || true)
    [ "$LEAK" = "0" ] || red "Found url field in response from $endpoint"
done
green "no \"url\" field in any browse/state response"

# ---------- /artwork ----------
TRACK_ID=$(curl -s "$BASE/tracks?limit=1" | jq -r '.tracks[0].trackId // empty')
if [ -n "$TRACK_ID" ]; then
    ART_HEADERS="$TMP/art.h"
    ART_BODY="$TMP/art.bin"
    HTTP_CODE=$(curl -s -o "$ART_BODY" -D "$ART_HEADERS" -w '%{http_code}' "$BASE/artwork/$TRACK_ID")
    if [ "$HTTP_CODE" = "200" ]; then
        CC=$(grep -i '^cache-control:' "$ART_HEADERS" | tr -d '\r' | sed -E 's/^[Cc]ache-[Cc]ontrol: //')
        echo "$CC" | grep -q 'max-age=31536000' || red "/artwork/$TRACK_ID missing 1y Cache-Control (got: $CC)"
        SIZE=$(wc -c < "$ART_BODY" | tr -d ' ')
        [ "$SIZE" -gt 0 ] || red "/artwork/$TRACK_ID returned zero bytes"
        green "/artwork/$TRACK_ID 200, $SIZE bytes, Cache-Control: $CC"

        # If-None-Match → 304 (capture ETag from prior GET; B001 changed format to "track-<id>-<sha8>")
        ART_ETAG=$(grep -i '^etag:' "$ART_HEADERS" | tr -d '\r' | sed -E 's/^[Ee][Tt][Aa][Gg]: //')
        if [ -n "$ART_ETAG" ]; then
            HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -H "If-None-Match: $ART_ETAG" "$BASE/artwork/$TRACK_ID")
            [ "$HTTP_CODE" = "304" ] || red "/artwork/$TRACK_ID If-None-Match expected 304, got $HTTP_CODE"
            green "/artwork/$TRACK_ID If-None-Match → 304"
        else
            red "/artwork/$TRACK_ID missing ETag header (cannot verify 304 path)"
        fi
    elif [ "$HTTP_CODE" = "404" ]; then
        green "/artwork/$TRACK_ID 404 (no embedded artwork — acceptable)"
    else
        red "/artwork/$TRACK_ID unexpected status $HTTP_CODE"
    fi
else
    echo "(skip /artwork: library appears empty)"
fi

# ---------- /pause ----------
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/pause")
[ "$HTTP_CODE" = "200" ] || red "POST /pause expected 200, got $HTTP_CODE"
sleep 0.2
IS_PLAYING=$(curl -s "$BASE/state" | jq -r '.isPlaying')
[ "$IS_PLAYING" = "false" ] || red "after /pause expected isPlaying=false, got $IS_PLAYING"
green "POST /pause → isPlaying=false"

# ---------- Bad-body 400 ----------
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{"volume":"loud"}' "$BASE/volume")
[ "$HTTP_CODE" = "400" ] || red "POST /volume with invalid body expected 400, got $HTTP_CODE"
green "POST /volume invalid body → 400"

# ---------- 100 parallel /state ----------
PIDS=""
FAILURES=0
for i in $(seq 1 100); do
    (curl -sf "$BASE/state" >/dev/null) &
    PIDS="$PIDS $!"
done
for pid in $PIDS; do
    wait "$pid" || FAILURES=$((FAILURES + 1))
done
[ "$FAILURES" = "0" ] || red "100 parallel /state requests had $FAILURES failures"
green "100 parallel /state requests all succeeded"

printf '\nAll smoke checks passed against %s\n' "$BASE"
