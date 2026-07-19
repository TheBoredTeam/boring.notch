'use strict';

const DEFAULT_PORT = 26539;

const $ = (id) => document.getElementById(id);
const form = $('form');
const tokenInput = $('token');
const portInput = $('port');
const enabledInput = $('enabled');
const statusEl = $('status');
const statusText = $('status-text');
const savedEl = $('saved');
const nowPlaying = $('now-playing');

function renderStatus(status) {
  const classes = ['status'];
  let text;

  if (!status) {
    classes.push('status--idle');
    text = 'Checking…';
  } else if (status.authenticated) {
    classes.push('status--ok');
    text = 'Connected to Boring Notch.';
  } else if (status.error) {
    classes.push('status--err');
    text = status.error;
  } else if (status.connected) {
    classes.push('status--warn');
    text = 'Connected — waiting for Boring Notch to accept the token…';
  } else {
    classes.push('status--warn');
    text = 'Not connected. Is Boring Notch running with “YouTube Music (Browser)” selected?';
  }

  statusEl.className = classes.join(' ');
  statusText.textContent = text;
}

function renderNowPlaying(state) {
  if (!state || !state.hasTrack) {
    nowPlaying.hidden = true;
    return;
  }
  nowPlaying.hidden = false;
  $('np-title').textContent = state.title || '—';
  $('np-artist').textContent = [state.artist, state.album].filter(Boolean).join(' — ');
}

async function refresh() {
  try {
    const reply = await chrome.runtime.sendMessage({ type: 'getStatus' });
    if (reply) {
      renderStatus(reply.status);
      renderNowPlaying(reply.lastState);
    }
  } catch (err) {
    renderStatus({ connected: false, error: 'Extension service worker is not responding.' });
  }
}

async function load() {
  const stored = await chrome.storage.local.get(['port', 'token', 'enabled']);
  tokenInput.value = stored.token || '';
  portInput.value = Number(stored.port) || DEFAULT_PORT;
  enabledInput.checked = stored.enabled !== false;
  await refresh();
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  const port = Number(portInput.value) || DEFAULT_PORT;
  await chrome.storage.local.set({
    token: tokenInput.value.trim(),
    port,
    enabled: enabledInput.checked,
  });
  savedEl.hidden = false;
  setTimeout(() => {
    savedEl.hidden = true;
  }, 2000);
  setTimeout(refresh, 400);
});

$('reconnect').addEventListener('click', async () => {
  try {
    await chrome.runtime.sendMessage({ type: 'reconnect' });
  } catch (err) {
    /* worker asleep; it reconnects on wake */
  }
  setTimeout(refresh, 500);
});

chrome.runtime.onMessage.addListener((message) => {
  if (message && message.type === 'statusChanged') {
    renderStatus(message.status);
    void refresh();
  }
  return false;
});

setInterval(refresh, 3000);
void load();
