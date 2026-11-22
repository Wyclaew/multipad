// MultiPad Background Service Worker (Manifest V3)

const DEFAULT_BRIDGE_URL = 'http://127.0.0.1:48292';

async function getStoredConfig() {
  let pairingToken = '';
  let bridgeUrl = DEFAULT_BRIDGE_URL;

  // Prefer in-memory session storage for sensitive pairing token when available
  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.session) {
    try {
      const sData = await chrome.storage.session.get(['pairingToken', 'bridgeUrl']);
      if (sData && sData.pairingToken) pairingToken = sData.pairingToken;
      if (sData && sData.bridgeUrl) bridgeUrl = sData.bridgeUrl;
    } catch (_) {}
  }

  // Fallback to local storage if not in session
  if (!pairingToken && typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    try {
      const lData = await chrome.storage.local.get(['pairingToken', 'bridgeUrl']);
      if (lData && lData.pairingToken) pairingToken = lData.pairingToken;
      if (lData && lData.bridgeUrl) bridgeUrl = lData.bridgeUrl;
    } catch (_) {}
  }

  return {
    pairingToken,
    bridgeUrl,
  };
}

async function setStoredToken(token) {
  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.session) {
    try {
      await chrome.storage.session.set({ pairingToken: token });
    } catch (_) {}
  }
  if (typeof chrome !== 'undefined' && chrome.storage && chrome.storage.local) {
    try {
      await chrome.storage.local.set({ pairingToken: token });
    } catch (_) {}
  }
}

async function updateBadge(status) {
  try {
    if (status === 'unlocked') {
      await chrome.action.setBadgeText({ text: '' });
    } else if (status === 'locked') {
      await chrome.action.setBadgeText({ text: '🔒' });
      await chrome.action.setBadgeBackgroundColor({ color: '#EF4444' });
    } else {
      await chrome.action.setBadgeText({ text: '!' });
      await chrome.action.setBadgeBackgroundColor({ color: '#6B7280' });
    }
  } catch (err) {
    console.warn('MultiPad: failed to update badge', err);
  }
}

// Request helpers
async function fetchBridgeStatus() {
  const { bridgeUrl } = await getStoredConfig();
  try {
    const res = await fetch(`${bridgeUrl}/api/v1/status`, {
      method: 'GET',
      headers: { 'Accept': 'application/json' },
    });
    if (!res.ok) {
      // Fallback to /status if /api/v1/status not found
      const fallback = await fetch(`${bridgeUrl}/status`);
      const data = await fallback.json();
      await updateBadge(data.status);
      return { success: true, ...data };
    }
    const data = await res.json();
    await updateBadge(data.status);
    return { success: true, ...data };
  } catch (err) {
    await updateBadge('offline');
    return { success: false, error: 'Bridge offline or unreachable' };
  }
}

async function pairBridge(code = '') {
  const { bridgeUrl } = await getStoredConfig();
  try {
    let res = await fetch(`${bridgeUrl}/api/v1/pair`, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ code: code }),
    });
    if (!res.ok && res.status === 404) {
      res = await fetch(`${bridgeUrl}/pair`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ code: code }),
      });
    }
    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      return { success: false, error: errData.error || `Pairing failed: HTTP ${res.status}` };
    }
    const data = await res.json();
    if (data.token) {
      await setStoredToken(data.token);
      await fetchBridgeStatus();
      return { success: true, token: data.token };
    }
    return { success: false, error: 'No token returned by bridge' };
  } catch (err) {
    return { success: false, error: err.message };
  }
}

async function queryCredentials(url) {
  const { bridgeUrl, pairingToken } = await getStoredConfig();
  if (!pairingToken) {
    return { success: false, error: 'Not paired with MultiPad desktop' };
  }

  try {
    let res = await fetch(`${bridgeUrl}/api/v1/query`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${pairingToken}`,
      },
      body: JSON.stringify({ url }),
    });

    if (res.status === 404) {
      res = await fetch(`${bridgeUrl}/query`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${pairingToken}`,
        },
        body: JSON.stringify({ url }),
      });
    }

    if (res.status === 423) {
      await updateBadge('locked');
      return { success: false, locked: true, error: 'Vault is locked' };
    }

    if (res.status === 401) {
      return { success: false, unauthorized: true, error: 'Invalid or expired pairing token' };
    }

    if (!res.ok) {
      return { success: false, error: `Query failed with status ${res.status}` };
    }

    const data = await res.json();
    await updateBadge('unlocked');
    return { success: true, matches: data.matches || [] };
  } catch (err) {
    await updateBadge('offline');
    return { success: false, error: err.message };
  }
}

async function captureCredential(url, username, password) {
  const { bridgeUrl, pairingToken } = await getStoredConfig();
  if (!pairingToken) {
    return { success: false, error: 'Not paired' };
  }

  try {
    let res = await fetch(`${bridgeUrl}/api/v1/capture`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${pairingToken}`,
      },
      body: JSON.stringify({ url, username, password }),
    });

    if (res.status === 404) {
      res = await fetch(`${bridgeUrl}/capture`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${pairingToken}`,
        },
        body: JSON.stringify({ url, username, password }),
      });
    }

    if (res.status === 423) {
      return { success: false, locked: true, error: 'Vault is locked' };
    }

    if (!res.ok) {
      return { success: false, error: `Capture failed: ${res.status}` };
    }

    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
}

// Message routing
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    switch (message.action) {
      case 'CHECK_STATUS':
        sendResponse(await fetchBridgeStatus());
        break;

      case 'PAIR':
        // Protect PAIR so in-page content scripts cannot trigger pairing
        if (sender && sender.tab) {
          sendResponse({ success: false, error: 'Unauthorized: content scripts cannot initiate pairing' });
          break;
        }
        sendResponse(await pairBridge(message.code));
        break;

      case 'QUERY_CREDENTIALS': {
        // Confused deputy protection: authenticate domain via browser-verified sender.tab.url
        const targetUrl = (sender && sender.tab && sender.tab.url)
          ? sender.tab.url
          : (message.url || '');
        sendResponse(await queryCredentials(targetUrl));
        break;
      }

      case 'CAPTURE_CREDENTIAL': {
        const targetUrl = (sender && sender.tab && sender.tab.url)
          ? sender.tab.url
          : (message.url || '');
        sendResponse(await captureCredential(targetUrl, message.username, message.password));
        break;
      }

      case 'GET_CONFIG':
        // Protect GET_CONFIG so untrusted content scripts cannot extract pairing tokens
        if (sender && sender.tab) {
          sendResponse({ error: 'Unauthorized: content scripts cannot access configuration' });
          break;
        }
        sendResponse(await getStoredConfig());
        break;

      default:
        sendResponse({ error: 'Unknown action' });
    }
  })();
  return true; // Keep message port open for async response
});

// Periodic heartbeat & tab listener
chrome.tabs.onActivated.addListener(async () => {
  await fetchBridgeStatus();
});
