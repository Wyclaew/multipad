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
