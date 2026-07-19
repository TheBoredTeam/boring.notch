/**
 * Service worker: owns the WebSocket connection to the Boring Notch app.
 *
 * Direction of travel:
 *   content.js --(state)--> here --(ws)--> Boring Notch
 *   Boring Notch --(ws command)--> here --> content.js --> player.js
 *
 * MV3 service workers are torn down after 30s idle. Since Chrome 116, WebSocket
 * traffic resets that timer, so KEEPALIVE_MS must stay comfortably under 30s.
 * chrome.alarms revives us if we do get shut down while the user is still playing.
 */

const PROTOCOL_VERSION = 1;
const DEFAULT_PORT = 26539;
// Boring Notch falls back to these if the default port is taken, so try each in turn
// rather than making the user find and type a number.
const CANDIDATE_PORTS = [26539, 26540, 26541];
const KEEPALIVE_MS = 20_000;
const ALARM_NAME = 'bn-bridge-keepalive';
const RECONNECT_MIN_MS = 1_000;
const RECONNECT_MAX_MS = 30_000;

let socket = null;
let keepaliveTimer = null;
let reconnectTimer = null;
let reconnectDelay = RECONNECT_MIN_MS;
let lastTabId = null;
let portIndex = 0;
let lastState = null;
let status = { connected: false, authenticated: false, error: null };

// ---------------------------------------------------------------- config

async function getConfig() {
  const stored = await chrome.storage.local.get(['port', 'enabled', 'lastGoodPort']);
  return {
    // An explicit port always wins; otherwise start from whichever port worked last.
    port: Number(stored.port) || 0,
    lastGoodPort: Number(stored.lastGoodPort) || 0,
    enabled: stored.enabled !== false,
  };
}

/** Ports to try, most-likely first, without repeats. */
function portsToTry({ port, lastGoodPort }) {
  if (port) return [port];
  const ordered = [lastGoodPort, ...CANDIDATE_PORTS].filter(Boolean);
  return [...new Set(ordered)];
}

async function setStatus(patch) {
  status = { ...status, ...patch };
  try {
    await chrome.storage.session.set({ status });
  } catch (err) {
    /* storage.session unavailable during teardown */
  }
  try {
    chrome.runtime.sendMessage({ type: 'statusChanged', status }, () => {
      void chrome.runtime.lastError; // no options page open
    });
  } catch (err) {
    /* nobody listening */
  }
}

// ---------------------------------------------------------------- socket

function clearTimers() {
  if (keepaliveTimer) {
    clearInterval(keepaliveTimer);
    keepaliveTimer = null;
  }
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

function send(message) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return false;
  try {
    socket.send(JSON.stringify({ v: PROTOCOL_VERSION, ...message }));
    return true;
  } catch (err) {
    console.warn('[BoringNotch] send failed:', err);
    return false;
  }
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  const delay = reconnectDelay;
  reconnectDelay = Math.min(reconnectDelay * 2, RECONNECT_MAX_MS);
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

async function connect() {
  const config = await getConfig();

  if (!config.enabled) {
    await setStatus({ connected: false, authenticated: false, error: null });
    return;
  }
  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
    return;
  }

  clearTimers();

  const candidates = portsToTry(config);
  const port = candidates[portIndex % candidates.length];

  let ws;
  try {
    ws = new WebSocket(`ws://127.0.0.1:${port}`);
  } catch (err) {
    await setStatus({ connected: false, authenticated: false, error: String(err) });
    portIndex += 1;
    scheduleReconnect();
    return;
  }
  socket = ws;

  ws.addEventListener('open', async () => {
    if (socket !== ws) return;
    reconnectDelay = RECONNECT_MIN_MS;
    portIndex = 0;
    await chrome.storage.local.set({ lastGoodPort: port });
    await setStatus({ connected: true, authenticated: false, error: null });

    send({
      type: 'hello',
      client: 'chrome-extension',
      extensionId: chrome.runtime.id,
      extensionVersion: chrome.runtime.getManifest().version,
      source: 'youtube-music',
    });

    // Keeps both the connection and this service worker alive.
    keepaliveTimer = setInterval(() => {
      if (!send({ type: 'ping' })) return;
    }, KEEPALIVE_MS);

    if (lastState) send({ type: 'state', state: lastState });
    resyncFromPage();
  });

  ws.addEventListener('message', async (event) => {
    if (socket !== ws) return;
    let msg;
    try {
      msg = JSON.parse(event.data);
    } catch (err) {
      return;
    }
    if (!msg || typeof msg.type !== 'string') return;

    switch (msg.type) {
      case 'welcome':
        await setStatus({ connected: true, authenticated: true, error: null });
        resyncFromPage();
        break;
      case 'command':
        dispatchCommand(msg);
        break;
      case 'pong':
        break;
      case 'error':
        await setStatus({
          connected: true,
          authenticated: false,
          error: String(msg.reason || 'error'),
        });
        break;
      default:
        break;
    }
  });

  ws.addEventListener('close', async () => {
    if (socket !== ws) return;
    socket = null;
    clearTimers();
    // Nothing here? Try the next candidate port on the following attempt.
    if (!status.authenticated) portIndex += 1;
    await setStatus({ connected: false, authenticated: false });
    scheduleReconnect();
  });

  ws.addEventListener('error', () => {
    // 'close' always follows; reconnect is handled there.
    if (socket !== ws) return;
    void setStatus({ error: 'Boring Notch is not reachable. Is it running with “YouTube Music (Browser)” selected?' });
  });
}

function disconnect() {
  clearTimers();
  if (socket) {
    const ws = socket;
    socket = null;
    try {
      ws.close();
    } catch (err) {
      /* already closing */
    }
  }
  void setStatus({ connected: false, authenticated: false });
}

// ---------------------------------------------------------------- page bridge

async function targetTabId() {
  if (lastTabId != null) return lastTabId;
  const { tabId } = await chrome.storage.session.get('tabId');
  if (tabId != null) {
    lastTabId = tabId;
    return tabId;
  }
  // Host permission for music.youtube.com is enough to query for it by URL;
  // this path only matters right after the worker is revived from scratch.
  try {
    const tabs = await chrome.tabs.query({ url: 'https://music.youtube.com/*' });
    if (tabs && tabs.length) {
      lastTabId = tabs[tabs.length - 1].id;
      return lastTabId;
    }
  } catch (err) {
    console.warn('[BoringNotch] tab lookup failed:', err);
  }
  return null;
}

async function dispatchCommand(msg) {
  const tabId = await targetTabId();
  if (tabId == null) return;
  try {
    await chrome.tabs.sendMessage(tabId, {
      type: 'command',
      action: msg.action,
      value: msg.value,
    });
  } catch (err) {
    // Tab closed or navigated away from YouTube Music.
    lastTabId = null;
    await chrome.storage.session.remove('tabId');
  }
}

async function resyncFromPage() {
  const tabId = await targetTabId();
  if (tabId == null) return;
  try {
    await chrome.tabs.sendMessage(tabId, { type: 'resync' });
  } catch (err) {
    lastTabId = null;
  }
}

// ---------------------------------------------------------------- events

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message) return false;

  if (message.type === 'state' || message.type === 'contentReady') {
    if (sender.tab && sender.tab.id != null) {
      lastTabId = sender.tab.id;
      void chrome.storage.session.set({ tabId: sender.tab.id });
    }
    if (message.type === 'state') {
      lastState = message.state;
      send({ type: 'state', state: message.state });
    }
    if (!socket) void connect();
    sendResponse({ ok: true });
    return false;
  }

  if (message.type === 'getStatus') {
    sendResponse({ status, lastState });
    return false;
  }

  if (message.type === 'reconnect') {
    disconnect();
    reconnectDelay = RECONNECT_MIN_MS;
    void connect();
    sendResponse({ ok: true });
    return false;
  }

  return false;
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM_NAME && !socket) void connect();
});

chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'local') return;
  if (changes.port || changes.enabled) {
    disconnect();
    reconnectDelay = RECONNECT_MIN_MS;
    void connect();
  }
});

chrome.runtime.onStartup.addListener(() => void bootstrap());
chrome.runtime.onInstalled.addListener(() => void bootstrap());

async function bootstrap() {
  // 1 minute is the shortest period Chrome honours for alarms.
  await chrome.alarms.create(ALARM_NAME, { periodInMinutes: 1 });
  await connect();
}

void bootstrap();
