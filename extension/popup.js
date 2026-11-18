// MultiPad Popup Controller

document.addEventListener('DOMContentLoaded', async () => {
  const statusBadge = document.getElementById('statusBadge');
  const unpairedView = document.getElementById('unpairedView');
  const lockedView = document.getElementById('lockedView');
  const unlockedView = document.getElementById('unlockedView');
  const currentDomainEl = document.getElementById('currentDomain');
  const credentialsList = document.getElementById('credentialsList');
  const noMatchesState = document.getElementById('noMatchesState');
  const searchInput = document.getElementById('searchInput');
  const pairBtn = document.getElementById('pairBtn');
  const refreshLockBtn = document.getElementById('refreshLockBtn');

  let currentTab = null;
  let allCredentials = [];

  // Determine current active tab
  try {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs && tabs.length > 0) {
      currentTab = tabs[0];
      const url = new URL(currentTab.url || 'about:blank');
      currentDomainEl.innerText = url.hostname || 'Unknown site';
    }
  } catch (err) {
    currentDomainEl.innerText = 'Desktop tab';
  }

  function setView(state) {
    unpairedView.classList.add('hidden');
    lockedView.classList.add('hidden');
    unlockedView.classList.add('hidden');

    statusBadge.className = 'status-badge';

    if (state === 'unlocked') {
      unlockedView.classList.remove('hidden');
      statusBadge.innerText = 'Unlocked';
      statusBadge.classList.add('status-unlocked');
    } else if (state === 'locked') {
      lockedView.classList.remove('hidden');
      statusBadge.innerText = 'Locked';
      statusBadge.classList.add('status-locked');
    } else {
      unpairedView.classList.remove('hidden');
      statusBadge.innerText = 'Unpaired';
      statusBadge.classList.add('status-offline');
    }
  }

  async function checkState() {
    chrome.runtime.sendMessage({ action: 'CHECK_STATUS' }, async (res) => {
      if (chrome.runtime.lastError || !res || !res.success) {
        setView('unpaired');
        return;
      }

      if (res.status === 'locked') {
        setView('locked');
      } else if (res.status === 'unlocked') {
        setView('unlocked');
        await loadCredentials();
      } else {
        setView('unpaired');
      }
    });
  }

  async function loadCredentials() {
    if (!currentTab || !currentTab.url) return;

    chrome.runtime.sendMessage(
      { action: 'QUERY_CREDENTIALS', url: currentTab.url },
      (res) => {
        if (chrome.runtime.lastError || !res || !res.success) {
          if (res && res.locked) {
            setView('locked');
            return;
          }
          renderCredentials([]);
          return;
        }

        allCredentials = res.matches || [];
        renderCredentials(allCredentials);
      }
    );
  }

  function renderCredentials(credentials) {
    credentialsList.innerHTML = '';

    if (credentials.length === 0) {
      noMatchesState.classList.remove('hidden');
      return;
    }

    noMatchesState.classList.add('hidden');

    for (const cred of credentials) {
      const card = document.createElement('div');
      card.className = 'credential-card';

      const header = document.createElement('div');
      header.className = 'card-header';

      const title = document.createElement('div');
      title.className = 'card-title';
      title.innerText = cred.title || 'Login';

      header.appendChild(title);

      if (cred.totp) {
        const totpChip = document.createElement('div');
        totpChip.className = 'totp-chip';
        totpChip.innerText = `⏱ ${cred.totp}`;
        totpChip.title = 'Click to copy TOTP code';
        totpChip.onclick = () => copyText(cred.totp, totpChip);
        header.appendChild(totpChip);
      }

      const username = document.createElement('div');
      username.className = 'card-username';
      username.innerText = cred.username || '(No username)';

      const actions = document.createElement('div');
      actions.className = 'card-actions';

      const autofillBtn = document.createElement('button');
      autofillBtn.className = 'btn-action btn-autofill';
      autofillBtn.innerText = '⚡ Autofill';
      autofillBtn.onclick = () => autofill(cred);

      const copyPassBtn = document.createElement('button');
      copyPassBtn.className = 'btn-action';
      copyPassBtn.innerText = '🔑 Copy Password';
      copyPassBtn.onclick = () => copyText(cred.password, copyPassBtn);

      actions.appendChild(autofillBtn);
      actions.appendChild(copyPassBtn);

      card.appendChild(header);
      card.appendChild(username);
      card.appendChild(actions);

      credentialsList.appendChild(card);
    }
  }

  async function autofill(credential) {
    if (!currentTab || !currentTab.id) return;
    try {
      await chrome.tabs.sendMessage(currentTab.id, {
        action: 'AUTOFILL_CREDENTIAL',
        credential: credential,
      });
      window.close();
    } catch (err) {
      console.warn('MultiPad: autofill dispatch failed', err);
    }
  }

  async function copyText(text, btnElement) {
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      const originalText = btnElement.innerText;
      btnElement.innerText = '✓ Copied!';
      setTimeout(() => {
        btnElement.innerText = originalText;
      }, 1500);
    } catch (err) {
      console.warn('MultiPad: failed to copy to clipboard', err);
    }
  }

  // Filter credentials on search
  searchInput.addEventListener('input', (e) => {
    const q = e.target.value.toLowerCase().trim();
    if (!q) {
      renderCredentials(allCredentials);
      return;
    }
    const filtered = allCredentials.filter((c) => {
      return (
        (c.title && c.title.toLowerCase().includes(q)) ||
        (c.username && c.username.toLowerCase().includes(q))
      );
    });
    renderCredentials(filtered);
  });

  // Pairing button event
  pairBtn.addEventListener('click', () => {
    pairBtn.disabled = true;
    pairBtn.innerText = 'Pairing...';
    chrome.runtime.sendMessage({ action: 'PAIR' }, (res) => {
      pairBtn.disabled = false;
      pairBtn.innerText = 'Pair with MultiPad';
      if (res && res.success) {
        checkState();
      } else {
        alert(res ? res.error : 'Pairing failed. Make sure MultiPad desktop is open.');
      }
    });
  });

  // Refresh lock button
  refreshLockBtn.addEventListener('click', () => {
    checkState();
  });

  // Initial load
  await checkState();
});
