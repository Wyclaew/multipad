// MultiPad Popup UI & Controller Test Suite (Node.js + JSDOM)
// MultiPad v1.4.0 — Milestone 2 Feature 11

const { JSDOM } = require('/tmp/dom_test/node_modules/jsdom');
const fs = require('fs');
const path = require('path');

const popupHtml = fs.readFileSync(path.resolve(__dirname, '../extension/popup.html'), 'utf8');
const popupCss = fs.readFileSync(path.resolve(__dirname, '../extension/popup.css'), 'utf8');
const popupJsCode = fs.readFileSync(path.resolve(__dirname, '../extension/popup.js'), 'utf8');

let allPassed = true;
function assert(condition, message) {
  if (!condition) {
    console.error(`❌ ASSERTION FAILED: ${message}`);
    allPassed = false;
  } else {
    console.log(`✅ PASS: ${message}`);
  }
}

console.log('=== RUNNING POPUP UI & GENERATOR TEST SUITE ===\n');

// ----------------------------------------------------------------------------
// TEST 1: Container Dimensions & Design System Styling
// ----------------------------------------------------------------------------
console.log('--- TEST 1: Container Dimensions & Slate/Indigo CSS Tokens ---');
(() => {
  assert(popupCss.includes('width: 380px;'), 'CSS specifies width: 380px');
  assert(popupCss.includes('height: 520px;'), 'CSS specifies height: 520px');
  assert(popupCss.includes('--md-sys-color-primary: #818CF8;'), 'CSS declares primary indigo token #818CF8');
  assert(popupCss.includes('--md-sys-color-background: #0F172A;'), 'CSS declares background slate token #0F172A');
  assert(popupCss.includes('--md-sys-color-surface: #1E293B;'), 'CSS declares surface slate token #1E293B');
})();

console.log('');

// ----------------------------------------------------------------------------
// TEST 2: Popup DOM Initialization, Tabs & Credential Cards
// ----------------------------------------------------------------------------
console.log('--- TEST 2: Tab Navigation & Credential Card Rendering ---');
(() => {
  const dom = new JSDOM(popupHtml, {
    url: 'chrome-extension://multipad-id/popup.html',
    runScripts: 'outside-only',
    pretendToBeVisual: true,
  });

  const { window } = dom;
  const { document } = window;

  const messagesSent = [];
  const tabMessages = [];

  window.crypto = {
    getRandomValues: (buffer) => {
      for (let i = 0; i < buffer.length; i++) {
        buffer[i] = Math.floor(Math.random() * 4294967296);
      }
      return buffer;
    },
  };

  let clipboardText = '';
  window.navigator.clipboard = {
    writeText: async (t) => { clipboardText = t; return true; },
  };

  window.chrome = {
    tabs: {
      query: async () => [{ id: 42, url: 'https://login.example.com' }],
      sendMessage: async (id, msg) => { tabMessages.push({ id, msg }); return { success: true }; },
    },
    runtime: {
      sendMessage: (msg, callback) => {
        messagesSent.push(msg);
        if (msg.action === 'CHECK_STATUS') {
          callback({ success: true, status: 'unlocked', version: '1.4.0' });
        } else if (msg.action === 'QUERY_CREDENTIALS') {
          callback({
            success: true,
            matches: [
              {
                id: 'cred-1',
                title: 'Example Account',
                username: 'alice_user',
                password: 'SecretPass123!',
                totp: '123456',
              },
            ],
          });
        }
      },
      lastError: null,
    },
  };

  window.eval(popupJsCode);
  document.dispatchEvent(new window.Event('DOMContentLoaded'));

  setImmediate(() => {
    // Assert current domain rendered
    const currentDomain = document.getElementById('currentDomain');
    assert(currentDomain.innerText === 'login.example.com', 'Current domain accurately populated from active tab');

    // Assert status badge
    const statusBadge = document.getElementById('statusBadge');
    assert(statusBadge.innerText === 'Unlocked', 'Status badge shows Unlocked');

    // Assert credential card rendered
    const cards = document.querySelectorAll('.credential-card');
    assert(cards.length === 1, 'Credential card rendered');

    const card = cards[0];
    assert(card.querySelector('.card-title').innerText === 'Example Account', 'Card title rendered');
    assert(card.querySelector('.card-username').innerText === 'alice_user', 'Card username rendered');
    assert(card.querySelector('.totp-code').innerText === '123 456', 'Live TOTP formatted with space');

    // Test tab navigation to Generator
    const tabBtnGenerator = document.getElementById('tabBtnGenerator');
    const viewGenerator = document.getElementById('viewGenerator');
    const viewVault = document.getElementById('viewVault');

    tabBtnGenerator.click();
    assert(tabBtnGenerator.classList.contains('active'), 'Generator tab marked active');
    assert(!viewGenerator.classList.contains('hidden'), 'Generator view visible');
    assert(viewVault.classList.contains('hidden'), 'Vault view hidden');

    // Test generated secret
    const secretText = document.getElementById('generatedSecretText').innerText;
    assert(secretText.length === 20, 'Default password generated with length 20');

    // Test entropy segments
    const entSeg4 = document.getElementById('entSeg4');
    assert(entSeg4.classList.contains('very-strong'), '20-char password achieves Very Strong entropy');

    // Test direct Fill action
    const fillSecretBtn = document.getElementById('fillSecretBtn');
    fillSecretBtn.click();

    setImmediate(() => {
      assert(tabMessages.length > 0, 'FILL_GENERATED_PASSWORD dispatched to tab');
      assert(tabMessages[0].msg.action === 'FILL_GENERATED_PASSWORD', 'Action matches FILL_GENERATED_PASSWORD');
      assert(tabMessages[0].msg.password === secretText, 'Password passed to active tab matches generated text');
    });
  });
})();

console.log('');

// ----------------------------------------------------------------------------
// TEST 3: Passphrase Mode Generation
// ----------------------------------------------------------------------------
console.log('--- TEST 3: Passphrase Generator Mode ---');
(() => {
  const dom = new JSDOM(popupHtml, {
    url: 'chrome-extension://multipad-id/popup.html',
    runScripts: 'outside-only',
    pretendToBeVisual: true,
  });

  const { window } = dom;
  const { document } = window;

  window.crypto = {
    getRandomValues: (buffer) => {
      for (let i = 0; i < buffer.length; i++) {
        buffer[i] = Math.floor(Math.random() * 4294967296);
      }
      return buffer;
    },
  };

  window.chrome = {
    tabs: { query: async () => [{ id: 1, url: 'https://site.com' }] },
    runtime: {
      sendMessage: (msg, cb) => cb({ success: true, status: 'unlocked' }),
      lastError: null,
    },
  };

  window.eval(popupJsCode);
  document.dispatchEvent(new window.Event('DOMContentLoaded'));

  setImmediate(() => {
    // Switch to generator
    document.getElementById('tabBtnGenerator').click();

    // Switch to passphrase mode
    const modeBtnPassphrase = document.getElementById('modeBtnPassphrase');
    modeBtnPassphrase.click();

    assert(modeBtnPassphrase.classList.contains('active'), 'Passphrase mode active');

    const phrase = document.getElementById('generatedSecretText').innerText;
    const parts = phrase.split('-');
    assert(parts.length === 5, 'Passphrase generated with default 5 words separated by hyphen');

    // Check title case capitalization
    const firstWord = parts[0];
    assert(firstWord[0] === firstWord[0].toUpperCase(), 'Words capitalized in TitleCase');
  });
})();

setTimeout(() => {
  console.log('\n========================================');
  if (allPassed) {
    console.log('🎉 ALL POPUP UI & GENERATOR TESTS PASSED!');
    process.exit(0);
  } else {
    console.error('❌ SOME POPUP TESTS FAILED!');
    process.exit(1);
  }
}, 200);
