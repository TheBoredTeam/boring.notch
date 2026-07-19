#!/usr/bin/env node
/**
 * Impersonates the Boring Notch browser extension so the app side of the bridge can be
 * tested without installing anything in a browser.
 *
 * Requires Node 22+ (for the built-in WebSocket client). No dependencies.
 *
 *   node test/bridge-sim.mjs <pairing-token> [port]
 *
 * Sends a fake now-playing state and prints every command the app sends back, so you can
 * select "YouTube Music (Browser)" in Boring Notch and click the notch controls to verify
 * they reach a client.
 */

const token = process.argv[2];
const port = Number(process.argv[3] || 26539);

if (!token) {
  console.error('usage: node test/bridge-sim.mjs <pairing-token> [port]');
  console.error('the token is in Boring Notch -> Settings -> Media -> Browser Extension');
  process.exit(2);
}

const state = {
  hasTrack: true,
  isPlaying: true,
  title: 'Bridge Simulator',
  artist: 'Boring Notch',
  album: 'Local Test',
  artworkUrl: null,
  duration: 240,
  position: 0,
  volume: 0.6,
  isMuted: false,
  repeatMode: 'off',
  isFavorite: false,
};

const ws = new WebSocket(`ws://127.0.0.1:${port}`);
const send = (msg) => ws.send(JSON.stringify({ v: 1, ...msg }));
const pushState = () => send({ type: 'state', state });

ws.addEventListener('open', () => {
  console.log(`connected to 127.0.0.1:${port}`);
  send({
    type: 'hello',
    token,
    client: 'bridge-sim',
    extensionId: 'bridge-sim',
    extensionVersion: '1.0.0',
    source: 'youtube-music',
  });
});

ws.addEventListener('message', (event) => {
  let msg;
  try {
    msg = JSON.parse(event.data);
  } catch {
    return;
  }

  switch (msg.type) {
    case 'welcome':
      console.log('authenticated — Boring Notch accepted the token');
      pushState();
      break;

    case 'error':
      console.error(`rejected: ${msg.reason}`);
      if (msg.reason === 'unauthorized') {
        console.error('copy the current token from Boring Notch and try again');
      }
      break;

    case 'command':
      console.log(`<- command ${msg.action}${msg.value != null ? ' ' + msg.value : ''}`);
      applyCommand(msg);
      pushState();
      break;

    default:
      break;
  }
});

ws.addEventListener('close', () => {
  console.log('disconnected');
  process.exit(0);
});

ws.addEventListener('error', (err) => {
  console.error('socket error — is Boring Notch running with "YouTube Music (Browser)" selected?');
  console.error(String(err.message || err));
});

function applyCommand({ action, value }) {
  switch (action) {
    case 'play': state.isPlaying = true; break;
    case 'pause': state.isPlaying = false; break;
    case 'toggle': state.isPlaying = !state.isPlaying; break;
    case 'next': state.title = 'Next Track'; state.position = 0; break;
    case 'previous': state.title = 'Previous Track'; state.position = 0; break;
    case 'seek': if (typeof value === 'number') state.position = value; break;
    case 'setVolume': if (typeof value === 'number') state.volume = value; break;
    case 'toggleShuffle': break;
    case 'toggleRepeat':
      state.repeatMode = { off: 'all', all: 'one', one: 'off' }[state.repeatMode] || 'off';
      break;
    case 'setFavorite': state.isFavorite = Boolean(value); break;
    default: break;
  }
}

// Keepalive plus a ticking position, so the app sees a live, advancing track.
setInterval(() => {
  if (ws.readyState !== WebSocket.OPEN) return;
  send({ type: 'ping' });
}, 20_000);

setInterval(() => {
  if (ws.readyState !== WebSocket.OPEN) return;
  if (state.isPlaying) {
    state.position = (state.position + 1) % state.duration;
    pushState();
  }
}, 1_000);

// Interactive control so you can drive the app from here too.
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => {
  const [cmd, arg] = chunk.trim().split(/\s+/);
  switch (cmd) {
    case 'help':
      console.log('play | pause | title <text> | artist <text> | fav | nofav | quit');
      break;
    case 'play': state.isPlaying = true; pushState(); break;
    case 'pause': state.isPlaying = false; pushState(); break;
    case 'title': state.title = arg || 'Untitled'; pushState(); break;
    case 'artist': state.artist = arg || 'Unknown'; pushState(); break;
    case 'fav': state.isFavorite = true; pushState(); break;
    case 'nofav': state.isFavorite = false; pushState(); break;
    case 'quit': send({ type: 'bye' }); ws.close(); break;
    case '': break;
    default: console.log(`unknown: ${cmd} (try "help")`);
  }
});
