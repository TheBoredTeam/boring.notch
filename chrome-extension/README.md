# Boring Notch — YouTube Music browser bridge

A Manifest V3 browser extension that lets Boring Notch show and control whatever is
playing in the **official YouTube Music web player** at `music.youtube.com`.

This is an alternative to the existing "YouTube Music" source, which drives the
third-party [Pear Desktop](https://github.com/pear-devs/pear-desktop) app. Both sources
work; pick one in **Settings → Media → Music Source**.

## How it fits together

```
YouTube Music tab or PWA window
  ├── src/player.js    MAIN world     reads #movie_player + navigator.mediaSession
  ├── src/content.js   isolated       relays page <-> service worker
  └── src/background.js service worker WebSocket client, 20s keepalive
        │
        │  ws://127.0.0.1:26539   loopback only, token authenticated
        ▼
  Boring Notch  (BrowserBridgeServer -> YouTubeMusicPWAController)
```

A browser extension cannot listen on a socket, so Boring Notch is the server and the
extension is the client. The listener binds `127.0.0.1` only and is started solely while
the "YouTube Music (Browser)" source is selected.

## Install

1. In Boring Notch, open **Settings → Media** and set **Music Source** to
   **YouTube Music (Browser)**. A **Browser Extension** section appears with a pairing
   token — leave it open.
2. Go to `chrome://extensions` and turn on **Developer mode**.
3. Click **Load unpacked** and choose this `chrome-extension` folder.
4. Open the extension's options (click its toolbar icon), paste the pairing token, and
   press **Save**.
5. Open `music.youtube.com` and play something. The status in both the extension options
   and the Boring Notch settings pane should go green.

Works in any Chromium browser with MV3 support — Chrome, Brave, Edge, Arc, Vivaldi —
including YouTube Music installed as a PWA/app window.

## Permissions, and why each is needed

| Permission | Why |
|---|---|
| `storage` | remembers the pairing token and port |
| `alarms` | revives the service worker if Chrome shuts it down mid-playback |
| `https://music.youtube.com/*` | the only site the extension reads or controls |

There is no `tabs` permission and no `<all_urls>`. The extension talks to exactly one
host and one loopback port, and sends nothing anywhere else.

## Security model

Loopback is reachable by any process on the machine — including any web page the user has
open — so binding to `127.0.0.1` is not by itself an access control. What actually gates
the bridge is a 128-bit token that Boring Notch generates and the user pastes in here.

- A connection that does not present the correct token in its `hello` is rejected and
  closed, and never becomes the active client.
- An unauthenticated connection cannot disconnect an already-paired extension.
- Unauthenticated connections are capped so they cannot accumulate.
- Regenerating the token in Boring Notch immediately invalidates the old pairing.

## Reading YouTube Music's state

Verified against the live site. The obvious sources are not all trustworthy, so:

| What | Source | Why not the obvious one |
|---|---|---|
| playing / paused | `navigator.mediaSession.playbackState` | `movie_player.getPlayerState()` reports buffering/unstarted during normal playback, and `#play-pause-button`'s `title` goes stale |
| title / artist / album | `navigator.mediaSession.metadata` | the DOM byline is "Artist • 613M views • 3.4M likes" on video entries |
| artwork | `mediaSession.metadata.artwork`, last entry | entries are listed smallest first |
| position | `video.currentTime` | — |
| duration | `movie_player.getDuration()` | `video.duration` is `NaN` for a moment after every track change |
| volume | `movie_player.getVolume()` (0–100) | `video.volume` is 0–1 |
| repeat | `ytmusic-player-bar[repeat-mode]` → `NONE`/`ALL`/`ONE` | — |
| favourite | `ytmusic-like-button-renderer[like-status]` | — |

`player.js` runs in the MAIN world because `#movie_player` is a page global and is not
reachable from an isolated content script. All selectors live in the `SEL` object at the
top of that file, so a YouTube Music redesign is a one-place fix.

## Wire protocol (v1)

Every message carries `v: 1`. JSON text frames.

**Extension → Boring Notch**

```jsonc
{ "v":1, "type":"hello", "token":"<pairing token>", "client":"chrome-extension",
  "extensionId":"…", "extensionVersion":"1.0.0", "source":"youtube-music" }

{ "v":1, "type":"state", "state": {
    "hasTrack": true, "isPlaying": true,
    "title":"…", "artist":"…", "album":"…", "artworkUrl":"https://…",
    "duration": 210.5, "position": 12.25,
    "volume": 0.75, "isMuted": false,
    "repeatMode": "off" | "one" | "all", "isFavorite": false } }

{ "v":1, "type":"ping" }   // every 20s; also keeps the MV3 worker alive
{ "v":1, "type":"bye" }
```

Every field of `state` except `isPlaying` is optional. A missing field means "unchanged",
not "zero".

**Boring Notch → extension**

```jsonc
{ "v":1, "type":"welcome", "app":"BoringNotch" }
{ "v":1, "type":"pong" }
{ "v":1, "type":"error", "reason":"unauthorized" }
{ "v":1, "type":"command",
  "action":"play"|"pause"|"toggle"|"next"|"previous"|"seek"|"setVolume"
          |"toggleShuffle"|"toggleRepeat"|"setFavorite",
  "value": 42.5 }   // seek: seconds · setVolume: 0–1 · setFavorite: 0 or 1
```

## Testing without a browser

`test/bridge-sim.mjs` impersonates the extension so the Boring Notch side can be
exercised on its own. Node 22+, no dependencies:

```bash
node test/bridge-sim.mjs <pairing-token> [port]
```

It connects, sends a fake now-playing state, and prints any commands the app sends back —
so you can select the source in Boring Notch and click the notch controls to confirm they
reach a client. Type `help` for the interactive commands.

## Troubleshooting

**Status stays "Not connected"** — Boring Notch must be running with **YouTube Music
(Browser)** selected; the listener only exists while that source is active.

**"Pairing token rejected"** — the token was regenerated in Boring Notch. Copy the current
one and save again.

**Nothing updates after Chrome has been idle** — MV3 shuts service workers down after 30s
idle. The 20s keepalive normally prevents this, and an alarm plus the next page event
revives it. Reloading the YouTube Music tab always recovers.

**Port already in use** — change the port in Boring Notch's settings and enter the same
value here.
