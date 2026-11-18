// Adversarial DOM Test Suite for MultiPad content.js
// Runs in Node.js using JSDOM

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

  // Mock chrome runtime API
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
                  id: 'cred-1',
                  title: 'Example Login',
                  username: 'alice@example.com',
                  password: 'SecretPassword123!',
                  totp: '123456',
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

  // Mock getComputedStyle for isVisible
  window.getComputedStyle = (el) => {
    return {
      display: 'block',
      visibility: 'visible',
      opacity: '1',
    };
  };

  return { dom, window, document, messagesSent, messageListeners };
}

console.log('=== RUNNING EMPIRICAL CONTENT SCRIPT ADVERSARIAL TESTS ===\n');

// -------------------------------------------------------------
// TEST 1: dataset.multipadTracked breaking Popup Autofill
// -------------------------------------------------------------
(() => {
  console.log('--- TEST 1: Popup Autofill after initial page scan ---');
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

  // Execute content.js in this window
  env.window.eval(contentJsCode);

  // In browser, content script runs at document_idle, so DOMContentLoaded has fired
  env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

  const passField = env.document.getElementById('passField');
  const userField = env.document.getElementById('userField');

  console.log('passField dataset.multipadTracked after init:', passField.dataset.multipadTracked);

  // Now simulate user clicking "⚡ Autofill" in popup
  let autofillResponse = null;
  const autofillMsg = {
    action: 'AUTOFILL_CREDENTIAL',
    credential: {
      username: 'alice@example.com',
      password: 'SecretPassword123!',
    },
  };

  for (const listener of env.messageListeners) {
    listener(autofillMsg, {}, (res) => {
      autofillResponse = res;
    });
  }

  console.log('Popup autofill response:', JSON.stringify(autofillResponse));
  console.log('userField value:', userField.value);
  console.log('passField value:', passField.value);

  if (!autofillResponse || !autofillResponse.success) {
    console.log('BUG CONFIRMED: Popup autofill FAILS because dataset.multipadTracked skips already-tracked inputs in findFormFields()!\n');
  } else {
    console.log('Autofill succeeded.\n');
  }
})();

// -------------------------------------------------------------
// TEST 2: SPA / Dynamic Injection without initial fields
// -------------------------------------------------------------
(() => {
  console.log('--- TEST 2: SPA / Dynamic Form Injection (init with 0 forms) ---');
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body id="appRoot">
        <div id="loading">Loading SPA...</div>
      </body>
    </html>
  `);

  // Execute content.js when DOM has NO forms
  env.window.eval(contentJsCode);

  console.log('Messages sent during initial load:', env.messagesSent.length);

  // Now SPA renders the form
  const formHtml = `
    <form id="dynamicLoginForm">
      <input type="text" name="username" id="dynUser">
      <input type="password" name="password" id="dynPass">
      <button type="submit">Log In</button>
    </form>
  `;
  env.document.getElementById('appRoot').innerHTML = formHtml;

  // Let MutationObserver fire (JSDOM fires mutation observers on next tick)
  setImmediate(() => {
    const dynPass = env.document.getElementById('dynPass');
    console.log('Messages sent after dynamic injection:', env.messagesSent.length);
    console.log('Has QUERY_CREDENTIALS been sent?:', env.messagesSent.some(m => m.action === 'QUERY_CREDENTIALS'));

    // Try focusing dynPass
    dynPass.dispatchEvent(new env.window.Event('focus'));

    const dropdown = env.document.querySelector('.multipad-autofill-dropdown');
    console.log('Was autofill dropdown rendered on focus?', dropdown !== null);

    if (env.messagesSent.length === 0 && dropdown === null) {
      console.log('BUG CONFIRMED: When page loads empty, QUERY_CREDENTIALS is NEVER called, and dynamically injected forms NEVER get credential suggestions!\n');
    }
  });
})();

// -------------------------------------------------------------
// TEST 3: Shadow DOM Penetration
// -------------------------------------------------------------
(() => {
  console.log('--- TEST 3: Shadow DOM Penetration ---');
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <div id="customHost"></div>
      </body>
    </html>
  `);

  const host = env.document.getElementById('customHost');
  const shadow = host.attachShadow({ mode: 'open' });
  shadow.innerHTML = `
    <form id="shadowLoginForm">
      <input type="text" name="username" id="shadowUser">
      <input type="password" name="password" id="shadowPass">
      <button type="submit">Sign In</button>
    </form>
  `;

  env.window.eval(contentJsCode);

  const shadowPass = shadow.getElementById('shadowPass');
  console.log('Shadow DOM password field tracked?:', shadowPass.dataset.multipadTracked || 'false');
  console.log('Messages sent (QUERY_CREDENTIALS):', env.messagesSent.length);

  if (!shadowPass.dataset.multipadTracked && env.messagesSent.length === 0) {
    console.log('BUG CONFIRMED: Shadow DOM inputs are completely invisible to document.querySelectorAll in content.js!\n');
  }
})();

// -------------------------------------------------------------
// TEST 4: Non-standard inputs (type="tel") and search input preceding username
// -------------------------------------------------------------
(() => {
  console.log('--- TEST 4: Form with Search Input preceding Login Fields ---');
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form id="complexForm">
          <input type="text" name="search" id="searchInput" placeholder="Search products...">
          <input type="text" name="username" id="realUsername" autocomplete="username">
          <input type="password" name="password" id="pwdInput">
          <button type="submit">Log In</button>
        </form>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);

  // Check which input was paired with pwdInput
  // In content.js:
  // form.querySelectorAll('input[type="text"], ...')
  // candidates.find(c => c !== pwdInput && isVisible(c))
  // Because searchInput is the first visible input[type="text"], candidates.find picks searchInput!
  const searchInput = env.document.getElementById('searchInput');
  const realUsername = env.document.getElementById('realUsername');
  const pwdInput = env.document.getElementById('pwdInput');

  console.log('searchInput id:', searchInput.id);
  console.log('realUsername id:', realUsername.id);

  // Simulate autofill
  let autofillListener = null;
  for (const l of env.messageListeners) autofillListener = l;

  // Reset tracked dataset so autofill finds the form
  delete pwdInput.dataset.multipadTracked;

  autofillListener(
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: 'victim_user', password: 'secret_password' },
    },
    {},
    () => {}
  );

  console.log('searchInput.value after autofill:', searchInput.value);
  console.log('realUsername.value after autofill:', realUsername.value);

  if (searchInput.value === 'victim_user' && realUsername.value === '') {
    console.log('BUG CONFIRMED: candidates.find picks the first visible text input (searchInput) instead of the actual username input!\n');
  }
})();

// -------------------------------------------------------------
// TEST 5: Phone Number Login (input[type="tel"])
// -------------------------------------------------------------
(() => {
  console.log('--- TEST 5: Phone Number Login (input[type="tel"]) ---');
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <form id="telLoginForm">
          <input type="tel" name="phone" id="phoneInput" placeholder="Mobile Phone Number">
          <input type="password" name="password" id="telPassword">
          <button type="submit">Sign In</button>
        </form>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);

  let autofillListener = null;
  for (const l of env.messageListeners) autofillListener = l;

  const phoneInput = env.document.getElementById('phoneInput');
  const telPassword = env.document.getElementById('telPassword');
  delete telPassword.dataset.multipadTracked;

  autofillListener(
    {
      action: 'AUTOFILL_CREDENTIAL',
      credential: { username: '+1234567890', password: 'PhoneSecret123!' },
    },
    {},
    () => {}
  );

  console.log('phoneInput value after autofill:', phoneInput.value);
  console.log('telPassword value after autofill:', telPassword.value);

  if (phoneInput.value === '' && telPassword.value === 'PhoneSecret123!') {
    console.log('BUG CONFIRMED: input[type="tel"] is completely ignored as a username candidate!\n');
  }
})();

// -------------------------------------------------------------
// TEST 6: Formless login submission capture via Enter key
// -------------------------------------------------------------
(() => {
  console.log('--- TEST 6: Formless / AJAX login submission without <form> or submit button ---');
  const env = createEnvironment(`
    <!DOCTYPE html>
    <html>
      <body>
        <div class="login-container">
          <input type="text" name="username" id="ajaxUser">
          <input type="password" name="password" id="ajaxPass">
          <div class="btn-login" id="customLoginBtn">Sign In</div>
        </div>
      </body>
    </html>
  `);

  env.window.eval(contentJsCode);
  env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

  const ajaxUser = env.document.getElementById('ajaxUser');
  const ajaxPass = env.document.getElementById('ajaxPass');

  ajaxUser.value = 'alice_ajax';
  ajaxPass.value = 'SecretAjax123!';

  // User presses Enter in password field
  const enterEvent = new env.window.KeyboardEvent('keydown', { key: 'Enter', keyCode: 13, bubbles: true });
  ajaxPass.dispatchEvent(enterEvent);

  const captureMessages = env.messagesSent.filter(m => m.action === 'CAPTURE_CREDENTIAL');
  console.log('Captured credentials via Enter key in formless container:', captureMessages.length);

  if (captureMessages.length === 0) {
    console.log('BUG CONFIRMED: Submissions via Enter key or non-submit elements in formless containers are never captured!\n');
  }
})();

