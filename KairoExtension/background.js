let ws = null;
let reconnectTimer = null;

function connect() {
  if (ws && ws.readyState <= WebSocket.OPEN) return;

  ws = new WebSocket("ws://localhost:8765");

  ws.onopen = () => {
    console.log("[Kairo] Connected to native app");
    clearInterval(reconnectTimer);
    reconnectTimer = null;
  };

  ws.onmessage = (event) => {
    try {
      const msg = JSON.parse(event.data);
      console.log("[Kairo] Command:", msg);
      dispatch(msg);
    } catch (e) {
      console.error("[Kairo] Parse error:", e);
    }
  };

  ws.onclose = () => {
    console.log("[Kairo] Disconnected, retrying in 5s...");
    ws = null;
    scheduleReconnect();
  };

  ws.onerror = () => {
    ws?.close();
  };
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setInterval(connect, 5000);
}

function dispatch(msg) {
  switch (msg.app) {
    case "youtube":
      handleYouTube(msg);
      break;
    case "browser":
      handleBrowser(msg);
      break;
    default:
      console.log("[Kairo] Unknown app:", msg.app);
  }
}

async function handleBrowser(msg) {
  if (msg.action === "pause_all_media") {
    const tabs = await chrome.tabs.query({ audible: true });
    for (const tab of tabs) {
      try {
        await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          func: () => {
            document.querySelectorAll("video, audio").forEach((m) => {
              if (!m.paused) {
                m.dataset.kairoPaused = "1";
                m.pause();
              }
            });
          },
        });
      } catch (e) {
        // Tab may not allow scripting
      }
    }
  } else if (msg.action === "resume_all_media") {
    const tabs = await chrome.tabs.query({});
    for (const tab of tabs) {
      try {
        await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          func: () => {
            document.querySelectorAll("video, audio").forEach((m) => {
              if (m.dataset.kairoPaused === "1") {
                delete m.dataset.kairoPaused;
                m.play();
              }
            });
          },
        });
      } catch (e) {
        // Tab may not allow scripting
      }
    }
  }
}

async function handleYouTube(msg) {
  const query = msg.query || "";
  const autoplay = msg.autoplay !== false;

  if (msg.action === "play" && query) {
    const searchURL = `https://www.youtube.com/results?search_query=${encodeURIComponent(query)}`;
    const tab = await chrome.tabs.create({ url: searchURL, active: true });

    if (autoplay) {
      chrome.tabs.onUpdated.addListener(function listener(tabId, info) {
        if (tabId === tab.id && info.status === "complete") {
          chrome.tabs.onUpdated.removeListener(listener);
          chrome.scripting.executeScript({
            target: { tabId: tab.id },
            func: clickFirstVideo,
          });
        }
      });
    }
  } else if (msg.action === "pause") {
    const tabs = await chrome.tabs.query({ url: "*://*.youtube.com/*" });
    for (const tab of tabs) {
      chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => document.querySelector("video")?.pause(),
      });
    }
  } else if (msg.action === "resume") {
    const tabs = await chrome.tabs.query({ url: "*://*.youtube.com/*" });
    for (const tab of tabs) {
      chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => document.querySelector("video")?.play(),
      });
    }
  }
}

function clickFirstVideo() {
  setTimeout(() => {
    const link = document.querySelector(
      "ytd-video-renderer a#video-title, ytd-rich-item-renderer a#video-title-link"
    );
    if (link) {
      link.click();
    }
  }, 1500);
}

connect();
