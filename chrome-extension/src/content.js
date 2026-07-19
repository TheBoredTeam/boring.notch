/**
 * Isolated-world relay between the MAIN-world page adapter (player.js) and the
 * extension service worker.
 *
 * player.js cannot talk to chrome.* APIs and the service worker cannot touch the
 * page's JS globals, so this sits in the middle and does nothing else.
 */

(() => {
  'use strict';

  const PAGE = 'bn-ytm-page'; // from player.js
  const EXT = 'bn-ytm-ext'; // to player.js

  let lastState = null;

  // ------------------------------------------------- page -> service worker

  window.addEventListener('message', (event) => {
    // Only accept messages this window posted to itself. Without both checks any
    // embedded frame or injected script could feed us fabricated playback state.
    if (event.source !== window) return;
    if (event.origin !== window.location.origin) return;

    const data = event.data;
    if (!data || data.source !== PAGE || data.type !== 'state') return;

    lastState = data.state;
    try {
      chrome.runtime.sendMessage({ type: 'state', state: data.state }, () => {
        // Reading lastError suppresses "Unchecked runtime.lastError" noise when the
        // service worker is asleep. It will be woken by the next message anyway.
        void chrome.runtime.lastError;
      });
    } catch (err) {
      // Extension context invalidated (reload/update). The page adapter keeps
      // running harmlessly; nothing to recover here.
    }
  });

  // ------------------------------------------------- service worker -> page

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message) return false;

    if (message.type === 'command') {
      window.postMessage(
        { source: EXT, type: 'command', action: message.action, value: message.value },
        window.location.origin
      );
      sendResponse({ ok: true });
      return false;
    }

    if (message.type === 'resync') {
      window.postMessage({ source: EXT, type: 'resync' }, window.location.origin);
      sendResponse({ ok: true, state: lastState });
      return false;
    }

    return false;
  });

  // Announce ourselves so the worker can connect (and wake it if it had idled out).
  try {
    chrome.runtime.sendMessage({ type: 'contentReady' }, () => {
      void chrome.runtime.lastError;
    });
  } catch (err) {
    /* extension reloaded; ignore */
  }
})();
