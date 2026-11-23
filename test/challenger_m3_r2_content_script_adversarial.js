// Challenger M3 Round 2 — Adversarial DOM & Content Script Test Suite
// Runs in Node.js with JSDOM

const { JSDOM } = require('/tmp/dom_test/node_modules/jsdom');
const fs = require('fs');
const path = require('path');

const contentJsCode = fs.readFileSync(path.resolve(__dirname, '../extension/content.js'), 'utf8');

function createEnvironment(initialHtml = '<!DOCTYPE html><html><body></body></html>', url = 'https://example.com/login') {
  const dom = new JSDOM(initialHtml, {
    url: url,
    runScripts: 'outside-only',
    pretendToBeVisual: true,
  });

  const { window } = dom;
  const { document } = window;

  const messagesSent = [];
  const messageListeners = [];

  window.chrome = {
    runtime: {
      sendMessage: (msg, callback) => {
        messagesSent.push(msg);
        if (msg.action === 'QUERY_CREDENTIALS') {
          if (callback) {
            callback({
              success: true,
              matches: [
                {
                  id: 'cred-primary',
                  title: 'Primary Account',
                  username: 'primary@example.com',
                  password: 'PrimaryPassword123!',
                  totp: '112233',
                },
                {
                  id: 'cred-secondary',
                  title: 'Secondary Admin',
                  username: 'admin@example.com',
                  password: 'AdminPassword999!',
                  totp: '654321',
                },
              ],
            });
          }
        } else if (callback) {
          callback({ success: true });
        }
      },
      onMessage: {
        addListener: (listener) => {
          messageListeners.push(listener);
        },
      },
      lastError: null,
    },
  };

  window.getComputedStyle = (el) => {
    if (el && el.getAttribute && el.getAttribute('data-hidden') === 'true') {
      return { display: 'none', visibility: 'hidden', opacity: '0' };
    }
    return { display: 'block', visibility: 'visible', opacity: '1' };
  };

  return { dom, window, document, messagesSent, messageListeners };
}

let allPassed = true;
function assert(condition, message) {
  if (!condition) {
    console.error(`❌ ASSERTION FAILED: ${message}`);
    allPassed = false;
  } else {
    console.log(`✅ PASS: ${message}`);
  }
}

console.log('=== RUNNING CHALLENGER ROUND 2 ADVERSARIAL DOM TESTS ===\n');

// ----------------------------------------------------------------------------
// DEFECT 3: Popup Autofill on Scanned Pages
// ----------------------------------------------------------------------------
console.log('--- SUITE 1: Defect 3 Re-verification (Popup Autofill on Scanned Pages) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form id="loginForm">
          <input type="text" name="username" id="userField">
          <input type="password" name="password" id="passField">
          <button type="submit">Sign In</button>
        </form>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);
  env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

  const passField = env.document.getElementById('passField');
  const userField = env.document.getElementById('userField');

  assert(passField.dataset.multipadTracked === 'true', 'Password field is tracked on initial scan');

  // Trigger autofill 1st time
  let autofillRes1 = null;
  const listener = env.messageListeners[0];
  listener(
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'alice@example.com', password: 'SecretPassword123!' },
    },
    {},
    (res) => { autofillRes1 = res; }
  );

  assert(autofillRes1 && autofillRes1.success === true, 'First popup autofill succeeds');
  assert(userField.value === 'alice@example.com', 'userField populated with alice@example.com');
  assert(passField.value === 'SecretPassword123!', 'passField populated with SecretPassword123!');

  // Trigger autofill 2nd time with different credentials
  let autofillRes2 = null;
  listener(
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'bob@example.com', password: 'NewPassword456!' },
    },
    {},
    (res) => { autofillRes2 = res; }
  );

  assert(autofillRes2 && autofillRes2.success === true, 'Second popup autofill succeeds on same scanned page');
  assert(userField.value === 'bob@example.com', 'userField updated to bob@example.com');
  assert(passField.value === 'NewPassword456!', 'passField updated to NewPassword456!');

  // Trigger on page with NO fields
  const emptyEnv = createEnvironment('<!DOCTYPE html><html><body><p>No forms here</p></body></html>');
  emptyEnv.window.eval(contentJsCode);
  let emptyRes = null;
  emptyEnv.messageListeners[0](
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'user', password: 'pwd' },
    },
    {},
    (res) => { emptyRes = res; }
  );
  assert(emptyRes && emptyRes.success === false, 'Popup autofill gracefully returns false on page without fields');
  assert(emptyRes && emptyRes.error === 'No login fields found on page', 'Correct error message on empty page');

  // Trigger on password-only field (no username field)
  const pwdOnlyEnv = createEnvironment(`
    <!DOCTYPE html>
    <html><body><form><input type="password" id="singlePwd"></form></body></html>
  `);
  pwdOnlyEnv.window.eval(contentJsCode);
  let pwdOnlyRes = null;
  pwdOnlyEnv.messageListeners[0](
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: '', password: 'SoloPassword!' },
    },
    {},
    (res) => { pwdOnlyRes = res; }
  );
  const singlePwd = pwdOnlyEnv.document.getElementById('singlePwd');
  assert(pwdOnlyRes && pwdOnlyRes.success === true, 'Autofill succeeds for single password field');
  assert(singlePwd.value === 'SoloPassword!', 'Solo password input populated correctly');
})();

console.log('');

// ----------------------------------------------------------------------------
// DEFECT 4: Dynamic SPA Forms Injection & Suggestion Dropdown
// ----------------------------------------------------------------------------
console.log('--- SUITE 2: Defect 4 Re-verification (Dynamic SPA Forms) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body id="spaRoot">
        <div id="loader">App initializing...</div>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);

  assert(
    env.messagesSent.some((m) => m.action === 'QUERY_CREDENTIALS'),
    'QUERY_CREDENTIALS proactively dispatched at init even when 0 forms present'
  );

  // Dynamically inject login modal
  const spaRoot = env.document.getElementById('spaRoot');
  const modalDiv = env.document.createElement('div');
  modalDiv.id = 'loginModal';
  modalDiv.innerHTML = `
    <form id="modalForm">
      <input type="text" name="username" id="modalUser" autocomplete="username">
      <input type="password" name="password" id="modalPass">
      <button type="submit" id="modalSubmit">Login</button>
    </form>
  `;
  spaRoot.appendChild(modalDiv);

  // Allow MutationObserver to fire
  setImmediate(() => {
    const modalPass = env.document.getElementById('modalPass');
    const modalUser = env.document.getElementById('modalUser');

    assert(modalPass.dataset.multipadTracked === 'true', 'Dynamic password field tracked by MutationObserver');

    // Simulate focus on dynamic password field
    modalPass.dispatchEvent(new env.window.Event('focus'));

    const dropdown = env.document.querySelector('.multipad-autofill-dropdown');
    assert(dropdown !== null, 'Autofill dropdown rendered on focus of dynamically injected input');

    // Enter key capture on dynamic form without submit button click
    modalUser.value = 'dynamic_user';
    modalPass.value = 'DynamicPassword123!';
    const enterEvt = new env.window.KeyboardEvent('keydown', { key: 'Enter', keyCode: 13, bubbles: true });
    modalPass.dispatchEvent(enterEvt);

    const captures = env.messagesSent.filter((m) => m.action === 'CAPTURE_CREDENTIAL');
    assert(captures.length > 0, 'Credential capture dispatched via Enter key on dynamic form');
    assert(captures[0].username === 'dynamic_user', 'Captured username matches dynamic_user');
    assert(captures[0].password === 'DynamicPassword123!', 'Captured password matches DynamicPassword123!');
  });
})();

console.log('');

// ----------------------------------------------------------------------------
// DEFECT 5: Preceding Search Inputs & Complex Form Identification
// ----------------------------------------------------------------------------
console.log('--- SUITE 3: Defect 5 Re-verification (Preceding Search & Form Isolation) ---');
(() => {
  // Test A: Search input preceding username input
  const envA = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form id="storeForm">
          <input type="search" name="search" id="storeSearch" placeholder="Search products...">
          <input type="text" name="filter_query" id="storeFilter">
          <input type="email" name="user_email" id="actualEmail" autocomplete="email">
          <input type="password" name="user_pwd" id="actualPwd">
          <button type="submit">Sign In</button>
        </form>
      </body>
    </html>
  `);

  envA.window.eval(contentJsCode);

  const storeSearch = envA.document.getElementById('storeSearch');
  const storeFilter = envA.document.getElementById('storeFilter');
  const actualEmail = envA.document.getElementById('actualEmail');
  const actualPwd = envA.document.getElementById('actualPwd');

  // Trigger autofill via popup
  envA.messageListeners[0](
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'shopper@domain.com', password: 'CartPassword99!' },
    },
    {},
    () => {}
  );

  assert(storeSearch.value === '', 'Preceding search input remains untouched');
  assert(storeFilter.value === '', 'Preceding filter input remains untouched');
  assert(actualEmail.value === 'shopper@domain.com', 'Actual email input receives username/email');
  assert(actualPwd.value === 'CartPassword99!', 'Actual password input receives password');

  // Test B: Hidden dummy inputs before visible username
  const envB = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form id="hiddenTrickyForm">
          <input type="text" name="username" id="honeypot" data-hidden="true">
          <input type="text" name="user" id="visibleUser">
          <input type="password" name="password" id="visiblePwd">
          <button type="submit">Submit</button>
        </form>
      </body>
    </html>
  `);

  envB.window.eval(contentJsCode);
  const honeypot = envB.document.getElementById('honeypot');
  const visibleUser = envB.document.getElementById('visibleUser');

  envB.messageListeners[0](
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'clever_user', password: 'StrongPassword!' },
    },
    {},
    () => {}
  );

  assert(honeypot.value === '', 'Hidden honeypot input is not selected');
  assert(visibleUser.value === 'clever_user', 'Visible username input is selected');

  // Test C: Open Shadow DOM inputs
  const envC = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <div id="webComponent"></div>
      </body>
    </html>
  `);

  const comp = envC.document.getElementById('webComponent');
  const shadow = comp.attachShadow({ mode: 'open' });
  shadow.innerHTML = `
    <form>
      <input type="text" name="username" id="shadowUser">
      <input type="password" name="password" id="shadowPwd">
    </form>
  `;

  envC.window.eval(contentJsCode);
  const shadowPwd = shadow.getElementById('shadowPwd');
  assert(shadowPwd.dataset.multipadTracked === 'true', 'Shadow DOM password field tracked');

  envC.messageListeners[0](
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'shadow_user', password: 'ShadowSecret1!' },
    },
    {},
    () => {}
  );

  const shadowUser = shadow.getElementById('shadowUser');
  assert(shadowUser.value === 'shadow_user', 'Shadow DOM username autofilled');
  assert(shadowPwd.value === 'ShadowSecret1!', 'Shadow DOM password autofilled');
})();

console.log('');

// ----------------------------------------------------------------------------
// SUITE 4: Feature 8 — Multi-Step Step 1 Form Detection & Autofill (identity_only)
// ----------------------------------------------------------------------------
console.log('--- SUITE 4: Feature 8 (Multi-Step Step 1 Identity-Only Form) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form id="step1Form">
          <input type="email" name="identifier" id="step1User" autocomplete="username">
          <button type="submit">Next</button>
        </form>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);
  const step1User = env.document.getElementById('step1User');

  assert(step1User.dataset.multipadTracked === 'true', 'Step 1 identity input tracked without password field');

  // Popup autofill into Step 1 identity field
  let autofillRes = null;
  env.messageListeners[0](
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'step1_alice@domain.com', password: 'IgnoredPassword' },
    },
    {},
    (res) => { autofillRes = res; }
  );

  assert(autofillRes && autofillRes.success === true, 'Autofill succeeds for identity_only form');
  assert(step1User.value === 'step1_alice@domain.com', 'Step 1 username populated correctly');
})();

console.log('');

// ----------------------------------------------------------------------------
// SUITE 5: Feature 8 — Standalone 2FA / OTP Form Detection & Autofill (otp_only)
// ----------------------------------------------------------------------------
console.log('--- SUITE 5: Feature 8 (Standalone 2FA / OTP Form Detection) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form id="otpForm">
          <input type="text" name="otp_code" id="otpField" autocomplete="one-time-code" maxlength="6">
          <button type="submit">Verify</button>
        </form>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);
  const otpField = env.document.getElementById('otpField');

  assert(otpField.dataset.multipadTracked === 'true', 'Standalone OTP field tracked');

  let autofillRes = null;
  env.messageListeners[0](
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'user@example.com', password: 'pwd', totp: '876543' },
    },
    {},
    (res) => { autofillRes = res; }
  );

  assert(autofillRes && autofillRes.success === true, 'Autofill succeeds for standalone OTP form');
  assert(otpField.value === '876543', 'OTP field populated with live TOTP code');
})();

console.log('');

// ----------------------------------------------------------------------------
// SUITE 6: Feature 7 — Reactive Framework Autofill & Value Tracker Clearing
// ----------------------------------------------------------------------------
console.log('--- SUITE 6: Feature 7 (Reactive Framework & Value Tracker Clearing) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form id="reactForm">
          <input type="text" name="username" id="reactUser">
          <input type="password" name="password" id="reactPass">
        </form>
      </body>
    </html>
  `);

  const reactUser = env.document.getElementById('reactUser');
  let trackerValue = 'initial';
  reactUser._valueTracker = {
    getValue: () => trackerValue,
    setValue: (val) => { trackerValue = val; },
  };

  let inputEventFired = false;
  let changeEventFired = false;
  let blurEventFired = false;

  reactUser.addEventListener('input', (e) => {
    inputEventFired = true;
    assert(e.bubbles === true, 'Input event bubbles');
    assert(e.composed === true, 'Input event is composed');
  });

  reactUser.addEventListener('change', (e) => {
    changeEventFired = true;
    assert(e.bubbles === true, 'Change event bubbles');
  });

  reactUser.addEventListener('blur', (e) => {
    blurEventFired = true;
    assert(e.composed === true, 'Blur event is composed (Angular touched support)');
  });

  env.window.eval(contentJsCode);

  env.messageListeners[0](
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'react_dev@fb.com', password: 'ReactPassword123!' },
    },
    {},
    () => {}
  );

  assert(reactUser.value === 'react_dev@fb.com', 'React input populated via prototype descriptor');
  assert(inputEventFired, 'Synthetic InputEvent was fired');
  assert(changeEventFired, 'Synthetic Change event was fired');
  assert(blurEventFired, 'Synthetic Blur event was fired');
})();

console.log('');

// ----------------------------------------------------------------------------
// SUITE 7: Feature 10 — Automated TOTP Clipboard Copy & Toast Notification
// ----------------------------------------------------------------------------
console.log('--- SUITE 7: Feature 10 (Automated TOTP Copy & Toast Notification) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form><input type="password" id="totpTestPass"></form>
      </body>
    </html>
  `);

  let copiedClipboardText = null;
  env.window.navigator.clipboard = {
    writeText: async (text) => {
      copiedClipboardText = text;
      return true;
    },
  };

  env.window.eval(contentJsCode);

  env.messageListeners[0](
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'totp_user', password: 'pwd', totp: '334455' },
    },
    {},
    () => {}
  );

  assert(copiedClipboardText === '334455', 'Live TOTP automatically copied to clipboard');

  const toastHost = env.document.getElementById('multipad-toast-host');
  assert(toastHost !== null, 'In-page TOTP toast notification banner mounted in DOM');
})();

console.log('');

// ----------------------------------------------------------------------------
// SUITE 8: Feature 9 — In-Field Shield Badge Injection & Dropdown Trigger
// ----------------------------------------------------------------------------
console.log('--- SUITE 8: Feature 9 (In-Field Shield Badge Injection) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form><input type="password" id="badgePassField"></form>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);
  const badgeHosts = env.document.querySelectorAll('.multipad-field-badge-host');
  assert(badgeHosts.length > 0, 'In-field shield badge host injected into document');

  const badge = badgeHosts[0];
  assert(badge.dataset.multipadBadge === 'true', 'Badge element has multipadBadge dataset marker');
})();

console.log('');

// ----------------------------------------------------------------------------
// SUITE 9: Feature 9 — Floating Dropdown Keyboard Navigation
// ----------------------------------------------------------------------------
console.log('--- SUITE 9: Feature 9 (Floating Dropdown Keyboard Navigation) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form id="keyNavForm">
          <input type="text" name="username" id="keyUser">
          <input type="password" name="password" id="keyPass">
        </form>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);
  const keyPass = env.document.getElementById('keyPass');
  const keyUser = env.document.getElementById('keyUser');

  // Focus to open dropdown
  keyPass.dispatchEvent(new env.window.Event('focus'));

  // Navigate down to item index 1 (Secondary Admin)
  keyPass.dispatchEvent(new env.window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
  keyPass.dispatchEvent(new env.window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));

  // Press Enter to select
  const enterEvt = new env.window.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true });
  keyPass.dispatchEvent(enterEvt);

  assert(enterEvt.defaultPrevented === true, 'Enter key prevented default form submission');
  assert(keyUser.value === 'admin@example.com', 'ArrowDown + Enter selected credential at index 1');
  assert(keyPass.value === 'AdminPassword999!', 'Password populated for index 1 credential');
})();

console.log('');

// ----------------------------------------------------------------------------
// SUITE 10: Feature 9 — Viewport Collision Detection (Vertical Flipping)
// ----------------------------------------------------------------------------
console.log('--- SUITE 10: Feature 9 (Viewport Collision & Flip Above Input) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form><input type="password" id="collisionPass"></form>
      </body>
    </html>
  `);

  const collisionPass = env.document.getElementById('collisionPass');
  // Mock bounding rect near the bottom of a 768px viewport (spaceBelow = 768 - 740 = 28px < 220px)
  collisionPass.getBoundingClientRect = () => ({
    top: 700,
    bottom: 740,
    left: 100,
    right: 300,
    width: 200,
    height: 40,
  });

  env.window.innerHeight = 768;
  env.window.innerWidth = 1024;

  env.window.eval(contentJsCode);

  collisionPass.dispatchEvent(new env.window.Event('focus'));

  const dropdownHost = env.document.querySelector('.multipad-autofill-dropdown');
  assert(dropdownHost !== null, 'Dropdown rendered on near-bottom input');
})();

console.log('');

// ----------------------------------------------------------------------------
// SUITE 11: Feature 11 Integration — FILL_GENERATED_PASSWORD Message Handling
// ----------------------------------------------------------------------------
console.log('--- SUITE 11: Feature 11 (FILL_GENERATED_PASSWORD Handling) ---');
(() => {
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form><input type="password" id="targetGenPwd"></form>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);
  const targetGenPwd = env.document.getElementById('targetGenPwd');

  let fillRes = null;
  env.messageListeners[0](
    {
      action: 'FILL_GENERATED_PASSWORD',
      password: 'GeneratedSecureSecret#2026',
    },
    {},
    (res) => { fillRes = res; }
  );

  assert(fillRes && fillRes.success === true, 'FILL_GENERATED_PASSWORD succeeds');
  assert(targetGenPwd.value === 'GeneratedSecureSecret#2026', 'Generated password injected into password input');
})();

setTimeout(() => {
  console.log('\n========================================');
  if (allPassed) {
    console.log('🎉 ALL CHALLENGER ROUND 2 ADVERSARIAL DOM TESTS PASSED!');
    process.exit(0);
  } else {
    console.error('❌ SOME CHALLENGER ROUND 2 ADVERSARIAL DOM TESTS FAILED!');
    process.exit(1);
  }
}, 100);

