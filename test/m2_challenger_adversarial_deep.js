// Challenger M2 — Deep Adversarial Stress Suite for Content Script & Manifest
// Tests Features 7, 8, 9, 10 with edge cases and framework simulations.
// MultiPad v1.4.0

const { JSDOM } = require('/tmp/dom_test/node_modules/jsdom');
const fs = require('fs');
const path = require('path');

const contentJsCode = fs.readFileSync(path.resolve(__dirname, '../extension/content.js'), 'utf8');
const manifestJson = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../extension/manifest.json'), 'utf8'));

let allPassed = true;
let totalTests = 0;
let passedTests = 0;

function assert(condition, message) {
  totalTests++;
  if (!condition) {
    console.error(`❌ FAIL: ${message}`);
    allPassed = false;
  } else {
    passedTests++;
    console.log(`✅ PASS: ${message}`);
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

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
  let clipboardText = null;
  const shadowRootsCreated = [];

  // Intercept attachShadow to capture created shadow roots for verification
  const origAttachShadow = window.Element.prototype.attachShadow;
  window.Element.prototype.attachShadow = function (init) {
    const root = origAttachShadow.call(this, init);
    shadowRootsCreated.push({ host: this, init, root });
    return root;
  };

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
                  title: 'Account 1',
                  username: 'user1@example.com',
                  password: 'Password1!',
                  totp: '123456',
                },
                {
                  id: 'cred-2',
                  title: 'Account 2',
                  username: 'user2@example.com',
                  password: 'Password2!',
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

  // Mock navigator.clipboard
  window.navigator.clipboard = {
    writeText: async (text) => {
      clipboardText = text;
      return true;
    },
  };

  window.getComputedStyle = (el) => {
    if (el && el.getAttribute && el.getAttribute('data-hidden') === 'true') {
      return { display: 'none', visibility: 'hidden', opacity: '0' };
    }
    return { display: 'block', visibility: 'visible', opacity: '1' };
  };

  return {
    dom,
    window,
    document,
    messagesSent,
    messageListeners,
    shadowRootsCreated,
    getClipboardText: () => clipboardText,
  };
}

async function runAllSuites() {
  console.log('================================================================');
  console.log('  CHALLENGER M2: DEEP ADVERSARIAL CONTENT SCRIPT TEST HARNESS   ');
  console.log('================================================================\n');

  // -----------------------------------------------------------------------------
  // AREA 1: FEATURE 7 — REACT 16+, ANGULAR & SHADOW DOM BUBBLING
  // -----------------------------------------------------------------------------
  console.log('--- AREA 1: Feature 7 Reactive Framework Autofill Injection ---');

  // Test 1.1: React 16+ _valueTracker simulation
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <form>
            <input type="text" id="reactInput" name="username">
            <input type="password" id="reactPwd" name="password">
          </form>
        </body>
      </html>
    `);

    const input = env.document.getElementById('reactInput');

    // Simulate React 16+ internal _valueTracker
    let trackedVal = '';
    input._valueTracker = {
      getValue: () => trackedVal,
      setValue: (v) => { trackedVal = '' + v; },
      stopTracking: () => {},
    };

    let reactSyntheticChangeFired = false;
    let reactLastSeenValue = '';

    // React event listener checks tracker difference on input event
    input.addEventListener('input', () => {
      if (input._valueTracker.getValue() !== input.value) {
        reactSyntheticChangeFired = true;
        reactLastSeenValue = input.value;
        input._valueTracker.setValue(input.value);
      }
    });

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    // Trigger autofill via chrome message listener
    const listener = env.messageListeners[0];
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'react.user@domain.com', password: 'ReactPassword123!' },
      },
      {},
      () => {}
    );

    assert(input.value === 'react.user@domain.com', 'React input has new value populated');
    assert(reactSyntheticChangeFired === true, 'React synthetic change event triggered via _valueTracker reset');
    assert(reactLastSeenValue === 'react.user@domain.com', 'React change handler received populated value');
  })();

  // Test 1.2: Angular form control ng-touched and ng-dirty simulation
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <form>
            <input type="text" id="ngInput" name="username">
            <input type="password" id="ngPwd" name="password">
          </form>
        </body>
      </html>
    `);

    const input = env.document.getElementById('ngInput');
    let ngTouched = false;
    let ngDirty = false;
    let ngValue = '';

    // Simulate Angular DefaultValueAccessor
    input.addEventListener('input', (e) => {
      ngDirty = true;
      ngValue = e.target.value;
    });
    input.addEventListener('blur', () => {
      ngTouched = true;
    });

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const listener = env.messageListeners[0];
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'angular.dev@domain.com', password: 'AngularPassword123!' },
      },
      {},
      () => {}
    );

    assert(ngDirty === true, 'Angular control marked ng-dirty on input event');
    assert(ngTouched === true, 'Angular control marked ng-touched on blur event');
    assert(ngValue === 'angular.dev@domain.com', 'Angular model received updated value');
  })();

  // Test 1.3: Shadow DOM boundary event traversal (composed: true)
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <div id="webComponentHost"></div>
        </body>
      </html>
    `);

    const host = env.document.getElementById('webComponentHost');
    const shadow = host.attachShadow({ mode: 'open' });
    const form = env.document.createElement('form');
    const shadowInput = env.document.createElement('input');
    shadowInput.type = 'text';
    shadowInput.name = 'username';
    const shadowPwd = env.document.createElement('input');
    shadowPwd.type = 'password';
    shadowPwd.name = 'password';

    form.appendChild(shadowInput);
    form.appendChild(shadowPwd);
    shadow.appendChild(form);

    // Outer document listeners
    let outerInputEvent = null;
    let outerBlurEvent = null;
    let outerChangeEvent = null;

    env.document.addEventListener('input', (e) => { outerInputEvent = e; });
    env.document.addEventListener('blur', (e) => { outerBlurEvent = e; });
    env.document.addEventListener('change', (e) => { outerChangeEvent = e; });

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const listener = env.messageListeners[0];
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'shadow@domain.com', password: 'ShadowPassword123!' },
      },
      {},
      () => {}
    );

    assert(outerInputEvent !== null, 'Outer document received input event from inside Shadow DOM');
    assert(outerInputEvent && outerInputEvent.composed === true, 'InputEvent has composed: true');
    assert(outerBlurEvent !== null, 'Outer document received blur event from inside Shadow DOM');
    assert(outerBlurEvent && outerBlurEvent.composed === true, 'Blur FocusEvent has composed: true');
    assert(outerChangeEvent !== null, 'Outer document received change event from inside Shadow DOM');
    assert(outerChangeEvent && outerChangeEvent.composed === true, 'ChangeEvent has composed: true');
  })();

  // Test 1.4: HTMLTextAreaElement value injection
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <form>
            <textarea id="myTextArea" name="notes"></textarea>
          </form>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const textarea = env.document.getElementById('myTextArea');
    textarea.focus();

    // Trigger FILL_GENERATED_PASSWORD while textarea is activeElement
    const listener = env.messageListeners[0];
    let fillRes = null;
    listener(
      { action: 'FILL_GENERATED_PASSWORD', password: 'TextAreaPassword999#' },
      {},
      (r) => { fillRes = r; }
    );

    assert(fillRes && fillRes.success === true, 'FILL_GENERATED_PASSWORD succeeds on active textarea');
    assert(textarea.value === 'TextAreaPassword999#', 'Textarea value populated via prototype descriptor');
  })();

  // -----------------------------------------------------------------------------
  // AREA 2: FEATURE 8 — MULTI-STEP LOGIN & STANDALONE FORMS
  // -----------------------------------------------------------------------------
  console.log('\n--- AREA 2: Feature 8 Multi-Step Login & Standalone Form Detection ---');

  // Test 2.1: Google Step 1 standalone identifier form
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <form id="gaia_loginform">
            <input type="email" name="identifier" id="identifierId" autocomplete="username">
            <button type="button" id="identifierNext">Next</button>
          </form>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const idInput = env.document.getElementById('identifierId');
    assert(idInput.dataset.multipadTracked === 'true', 'Google Step 1 identifierId tracked');

    // Verify badge attached
    const badges = env.document.querySelectorAll('.multipad-field-badge-host');
    assert(badges.length === 1, 'In-field shield badge attached to Google Step 1 input');

    // Trigger autofill
    const listener = env.messageListeners[0];
    let res = null;
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'google.user@gmail.com', password: 'GooglePassword123!' },
      },
      {},
      (r) => { res = r; }
    );

    assert(res && res.success === true, 'Autofill succeeded on Google Step 1');
    assert(idInput.value === 'google.user@gmail.com', 'Google Step 1 input populated with username');
  })();

  // Test 2.2: Apple / Shopify Step 1 forms
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <!-- Shopify Step 1 -->
          <form id="shopify-login">
            <input type="text" name="account[email]" id="account_email" autocomplete="username">
            <button type="submit">Continue with email</button>
          </form>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const shopifyInput = env.document.getElementById('account_email');
    assert(shopifyInput.dataset.multipadTracked === 'true', 'Shopify Step 1 email input tracked');

    const listener = env.messageListeners[0];
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'shopify.merchant@shop.com', password: 'ShopifyPassword123!' },
      },
      {},
      () => {}
    );
    assert(shopifyInput.value === 'shopify.merchant@shop.com', 'Shopify Step 1 populated');
  })();

  // Test 2.3: Standalone 2FA / OTP Form Detection & Live TOTP Suggestion
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <form id="otpForm">
            <input type="text" name="otp" autocomplete="one-time-code" maxlength="6" inputmode="numeric" id="otpField">
            <button type="submit">Verify Code</button>
          </form>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const otpField = env.document.getElementById('otpField');
    assert(otpField.dataset.multipadTracked === 'true', 'Standalone OTP field tracked');

    // Verify badge attached
    const badges = env.document.querySelectorAll('.multipad-field-badge-host');
    assert(badges.length === 1, 'In-field badge attached to OTP field');

    // Trigger autofill on OTP form
    const listener = env.messageListeners[0];
    let res = null;
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'testuser', password: 'pwd', totp: '998877' },
      },
      {},
      (r) => { res = r; }
    );

    assert(res && res.success === true, 'Autofill succeeded on OTP form');
    assert(otpField.value === '998877', 'OTP field populated with live TOTP code');
    assert(env.getClipboardText() === '998877', 'TOTP code copied to clipboard during OTP autofill');
  })();

  // Test 2.4: Multi-step credential memory preservation across step 1 and step 2
  await (async () => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <div id="auth-container">
            <!-- Step 1: Identifier only -->
            <form id="step1-form">
              <input type="email" name="identifier" id="step1-email">
              <button type="submit" id="step1-btn">Next</button>
            </form>
          </div>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const step1Input = env.document.getElementById('step1-email');

    // Step 1: Autofill credential
    const listener = env.messageListeners[0];
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'multistep.user@example.com', password: 'MultiStepPassword123!' },
      },
      {},
      () => {}
    );
    assert(step1Input.value === 'multistep.user@example.com', 'Step 1 input autofilled');

    // Simulate Step 2 SPA DOM transition: replace step1-form with step2-form (password only)
    const container = env.document.getElementById('auth-container');
    container.innerHTML = `
      <form id="step2-form">
        <input type="password" name="password" id="step2-pwd">
        <button type="submit" id="step2-submit">Log In</button>
      </form>
    `;

    // Wait for MutationObserver microtask to observe and initialize step2-form
    await sleep(25);

    const step2Pwd = env.document.getElementById('step2-pwd');
    assert(step2Pwd.dataset.multipadTracked === 'true', 'Step 2 password field tracked by MutationObserver');

    step2Pwd.value = 'MultiStepPassword123!';

    // Dispatch keydown Enter on step2-pwd to trigger submission capture
    step2Pwd.dispatchEvent(new env.window.KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

    // Check messagesSent for CAPTURE_CREDENTIAL
    const captureMsgs = env.messagesSent.filter((m) => m.action === 'CAPTURE_CREDENTIAL');
    assert(captureMsgs.length > 0, 'CAPTURE_CREDENTIAL message sent on Step 2 submission');
    if (captureMsgs.length > 0) {
      const lastCapture = captureMsgs[captureMsgs.length - 1];
      assert(
        lastCapture.username === 'multistep.user@example.com',
        'Step 1 username preserved in Step 2 password submission'
      );
      assert(
        lastCapture.password === 'MultiStepPassword123!',
        'Step 2 password correctly captured'
      );
    }
  })();

  // -----------------------------------------------------------------------------
  // AREA 3: FEATURE 9 — IN-FIELD BADGE, CLOSED SHADOW DOM & DROPDOWN COLLISION
  // -----------------------------------------------------------------------------
  console.log('\n--- AREA 3: Feature 9 In-Field Badge, Shadow DOM Isolation & Collision ---');

  // Test 3.1: In-field badge injection in closed Shadow DOM and CSS isolation
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <head>
          <style>
            * {
              color: red !important;
              visibility: hidden !important;
              font-size: 0px !important;
            }
            .shield-btn {
              display: none !important;
            }
            svg {
              display: none !important;
            }
          </style>
        </head>
        <body>
          <form>
            <input type="text" id="isolatedInput" name="username">
            <input type="password" id="isolatedPwd" name="password">
          </form>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const badgeHost = env.document.querySelector('.multipad-field-badge-host');
    assert(badgeHost !== null, 'Badge host element found in DOM');
    assert(badgeHost.shadowRoot === null, 'Badge host uses closed Shadow DOM (shadowRoot is null to outside)');

    // In-page querySelector cannot penetrate closed Shadow DOM
    const externalQueryShield = env.document.querySelectorAll('.shield-btn');
    assert(externalQueryShield.length === 0, 'Host page querySelector cannot find inner .shield-btn inside closed shadow');

    const externalQuerySvg = env.document.querySelectorAll('svg');
    assert(externalQuerySvg.length === 0, 'Host page querySelector cannot find inner SVG inside closed shadow');

    // Confirm shadow root was created with mode: closed
    const badgeShadowRecord = env.shadowRootsCreated.find((s) => s.host === badgeHost);
    assert(badgeShadowRecord && badgeShadowRecord.init.mode === 'closed', 'Badge shadow root created with mode: "closed"');
  })();

  // Test 3.2: Floating dropdown collision detection (<220px bottom space)
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <form>
            <input type="text" id="normalInput" name="username">
            <input type="password" id="bottomInput" name="password">
          </form>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    env.window.innerHeight = 800;
    env.window.innerWidth = 1024;

    // Case A: Normal input with plenty of bottom space (>220px)
    const normalInput = env.document.getElementById('normalInput');
    normalInput.getBoundingClientRect = () => ({
      top: 150,
      bottom: 180,
      left: 100,
      right: 300,
      width: 200,
      height: 30,
    });

    normalInput.focus();
    normalInput.dispatchEvent(new env.window.FocusEvent('focus'));

    const dropdownHostA = env.document.getElementById('multipad-autofill-host');
    assert(dropdownHostA !== null, 'Dropdown host created on focus for normal input');

    // Find dropdown inner in shadowRootsCreated
    const dropdownShadowA = env.shadowRootsCreated.find((s) => s.host === dropdownHostA);
    assert(dropdownShadowA && dropdownShadowA.init.mode === 'closed', 'Dropdown uses closed Shadow DOM');
    const dropdownInnerA = dropdownShadowA.root.querySelector('.multipad-autofill-dropdown-inner');
    // Normal input bottom=180 -> top should be 180 + 4 = 184px
    assert(dropdownInnerA.style.top === '184px', 'Normal dropdown rendered below input at rect.bottom + 4 (184px)');

    // Case B: Bottom input near screen edge (bottom space = 800 - 690 = 110 < 220px)
    const bottomInput = env.document.getElementById('bottomInput');
    bottomInput.getBoundingClientRect = () => ({
      top: 660,
      bottom: 690,
      left: 100,
      right: 300,
      width: 200,
      height: 30,
    });

    bottomInput.focus();
    bottomInput.dispatchEvent(new env.window.FocusEvent('focus'));

    const dropdownHostB = env.document.getElementById('multipad-autofill-host');
    const dropdownShadowB = env.shadowRootsCreated.find((s) => s.host === dropdownHostB);
    const dropdownInnerB = dropdownShadowB.root.querySelector('.multipad-autofill-dropdown-inner');
    // Space below: 800 - 690 = 110 < 220. Space above: 660 > 188.
    // dropdownHeight = 180. Expected flipped top = 660 - 180 - 4 = 476px.
    assert(dropdownInnerB.style.top === '476px', 'Collision detected: dropdown flipped above input to 476px');

    // Case C: Small viewport with constrained space both above and below (innerH = 200, top = 40, bottom = 70)
    // Space below = 200 - 70 = 130 < 220, but space above = 40 < 188.
    // Should NOT flip to negative top; should stay at rect.bottom + 4 = 74px.
    env.window.innerHeight = 200;
    bottomInput.getBoundingClientRect = () => ({
      top: 40,
      bottom: 70,
      left: 100,
      right: 300,
      width: 200,
      height: 30,
    });
    bottomInput.focus();
    bottomInput.dispatchEvent(new env.window.FocusEvent('focus'));

    const dropdownShadowC = env.shadowRootsCreated[env.shadowRootsCreated.length - 1];
    const dropdownInnerC = dropdownShadowC.root.querySelector('.multipad-autofill-dropdown-inner');
    assert(dropdownInnerC.style.top === '74px', 'Constrained viewport: does not flip into negative space, stays below');

    // Case D: Horizontal clamping near right edge (innerW = 1000, left = 850, dropdownWidth = 260)
    // Max allowed left = 1000 - 260 - 8 = 732px.
    env.window.innerHeight = 800;
    env.window.innerWidth = 1000;
    normalInput.getBoundingClientRect = () => ({
      top: 150,
      bottom: 180,
      left: 850,
      right: 980,
      width: 130,
      height: 30,
    });
    normalInput.focus();
    normalInput.dispatchEvent(new env.window.FocusEvent('focus'));

    const dropdownShadowD = env.shadowRootsCreated[env.shadowRootsCreated.length - 1];
    const dropdownInnerD = dropdownShadowD.root.querySelector('.multipad-autofill-dropdown-inner');
    assert(dropdownInnerD.style.left === '732px', 'Horizontal clamping: dropdown clamped to 732px to prevent viewport overflow');
  })();

  // Test 3.3: Keyboard navigation (ArrowDown, ArrowUp, Enter, Tab, Escape)
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <form id="keyForm">
            <input type="text" id="keyUser" name="username">
            <input type="password" id="keyPass" name="password">
            <button type="submit" id="subBtn">Submit</button>
          </form>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const keyUser = env.document.getElementById('keyUser');
    const keyPass = env.document.getElementById('keyPass');

    // Focus input to open suggestions
    keyUser.focus();
    keyUser.dispatchEvent(new env.window.FocusEvent('focus'));

    assert(env.document.getElementById('multipad-autofill-host') !== null, 'Dropdown open on focus');

    // ArrowDown 1: index becomes 0 (Account 1: user1@example.com)
    keyUser.dispatchEvent(new env.window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));

    // ArrowDown 2: index becomes 1 (Account 2: user2@example.com)
    keyUser.dispatchEvent(new env.window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));

    // ArrowDown 3: cyclic wrap to index 0
    keyUser.dispatchEvent(new env.window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));

    // ArrowUp: cyclic wrap back to index 1
    keyUser.dispatchEvent(new env.window.KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));

    // Enter on index 1: fills user2@example.com and prevents default form submission
    let formSubmitted = false;
    env.document.getElementById('keyForm').addEventListener('submit', () => {
      formSubmitted = true;
    });

    const enterEvent = new env.window.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true });
    keyUser.dispatchEvent(enterEvent);

    assert(enterEvent.defaultPrevented === true, 'Enter key prevented default form submission');
    assert(keyUser.value === 'user2@example.com', 'Enter selected and populated Account 2 username');
    assert(keyPass.value === 'Password2!', 'Enter populated Account 2 password');
    assert(formSubmitted === false, 'Form was NOT prematurely submitted on Enter autofill');

    // Test Escape key dismisses suggestions
    keyUser.focus();
    keyUser.dispatchEvent(new env.window.FocusEvent('focus'));
    assert(env.document.getElementById('multipad-autofill-host') !== null, 'Dropdown re-opened');

    const escapeEvent = new env.window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true });
    keyUser.dispatchEvent(escapeEvent);
    assert(escapeEvent.defaultPrevented === true, 'Escape key prevented default');
    assert(env.document.getElementById('multipad-autofill-host') === null, 'Escape dismissed dropdown host from DOM');

    // Test Tab key: when index selected, autofills credential
    keyUser.focus();
    keyUser.dispatchEvent(new env.window.FocusEvent('focus'));
    assert(env.document.getElementById('multipad-autofill-host') !== null, 'Dropdown re-opened for Tab test');

    // ArrowDown to index 0
    keyUser.dispatchEvent(new env.window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
    // Tab key
    keyUser.dispatchEvent(new env.window.KeyboardEvent('keydown', { key: 'Tab', bubbles: true }));
    assert(keyUser.value === 'user1@example.com', 'Tab key autofilled credential at selected index');
  })();

  // -----------------------------------------------------------------------------
  // AREA 4: FEATURE 10 — AUTOMATED TOTP COPY & TOAST BANNER
  // -----------------------------------------------------------------------------
  console.log('\n--- AREA 4: Feature 10 Automated TOTP Copy & Toast Notification ---');

  // Test 4.1: Automatic TOTP clipboard copying via navigator.clipboard.writeText
  (() => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <form>
            <input type="text" id="totpUser" name="username">
            <input type="password" id="totpPwd" name="password">
          </form>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const listener = env.messageListeners[0];
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'totp.user@example.com', password: 'Password123!', totp: '789123' },
      },
      {},
      () => {}
    );

    assert(env.getClipboardText() === '789123', 'Live TOTP code automatically transferred to navigator.clipboard');
  })();

  // Test 4.2: Toast banner rendering in closed Shadow DOM, formatted code and auto-dismiss
  await (async () => {
    const env = createEnvironment(`
      <!DOCTYPE html>
      <html>
        <body>
          <form>
            <input type="text" id="toastUser" name="username">
            <input type="password" id="toastPwd" name="password">
          </form>
        </body>
      </html>
    `);

    env.window.eval(contentJsCode);
    env.document.dispatchEvent(new env.window.Event('DOMContentLoaded'));

    const listener = env.messageListeners[0];
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'toast.user@example.com', password: 'Password123!', totp: '543210' },
      },
      {},
      () => {}
    );

    const toastHost = env.document.getElementById('multipad-toast-host');
    assert(toastHost !== null, 'Toast host #multipad-toast-host mounted in DOM');
    assert(toastHost.shadowRoot === null, 'Toast host encapsulated in closed Shadow DOM');

    const toastShadowRecord = env.shadowRootsCreated.find((s) => s.host === toastHost);
    assert(toastShadowRecord && toastShadowRecord.init.mode === 'closed', 'Toast shadow root created with mode: "closed"');
    const toastCodeEl = toastShadowRecord.root.querySelector('.code');
    assert(toastCodeEl.textContent === '543 210', 'Toast formats 6-digit TOTP with space ("543 210")');

    // Triggering another autofill replaces previous toast without duplicates
    listener(
      {
        action: 'AUTOFILL_CREDENTIAL',
        credential: { username: 'toast.user2@example.com', password: 'Password123!', totp: '111222' },
      },
      {},
      () => {}
    );

    const allToasts = env.document.querySelectorAll('#multipad-toast-host');
    assert(allToasts.length === 1, 'Toast replaced cleanly, no duplicate toast banners stacked');

    // Wait for auto-dismiss (3500ms timeout)
    await sleep(3600);
    assert(env.document.getElementById('multipad-toast-host') === null, 'Toast banner auto-dismissed after 3500ms');
  })();

  // Test 4.3: Manifest permissions check
  (() => {
    assert(manifestJson.manifest_version === 3, 'manifest.json is Manifest V3');
    assert(manifestJson.permissions.includes('clipboardWrite'), 'manifest.json permissions include "clipboardWrite"');
    assert(manifestJson.permissions.includes('activeTab'), 'manifest.json permissions include "activeTab"');
    assert(manifestJson.permissions.includes('storage'), 'manifest.json permissions include "storage"');
    assert(manifestJson.permissions.includes('tabs'), 'manifest.json permissions include "tabs"');
    assert(manifestJson.version === '1.4.0', 'manifest.json version is bumped to 1.4.0');
    assert(manifestJson.content_scripts[0].matches.includes('<all_urls>'), 'content_scripts matches all_urls');
  })();

  console.log('\n================================================================');
  console.log(`RESULTS: ${passedTests} / ${totalTests} tests passed.`);
  if (allPassed) {
    console.log('🎉 ALL DEEP ADVERSARIAL CHALLENGER TESTS PASSED!');
    process.exit(0);
  } else {
    console.error('💥 ADVERSARIAL CHALLENGES FAILED!');
    process.exit(1);
  }
}

runAllSuites().catch((err) => {
  console.error('Test suite error:', err);
  process.exit(1);
});
