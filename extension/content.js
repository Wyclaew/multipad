// MultiPad Content Script (Form Detection, Autofill & Submission Capture)
// MultiPad v1.4.0 — Features 7, 8, 9, 10

(() => {
  let matchedCredentials = [];
  let overlayHost = null;
  let autofillDropdownEl = null;
  let activeTargetInput = null;
  let activeFieldSet = null;
  let selectedDropdownIndex = -1;
  let rafPositionId = null;
  let lastIdentifiedUsername = '';

  // ---------------------------------------------------------------------------
  // Feature 8: Decoupled DOM Scanners & Shadow DOM Traversal
  // ---------------------------------------------------------------------------

  function isVisible(el) {
    if (!el) return false;
    try {
      const style = window.getComputedStyle(el);
      return (
        style.display !== 'none' &&
        style.visibility !== 'hidden' &&
        style.opacity !== '0'
      );
    } catch (_) {
      return false;
    }
  }

  function findPasswordInputs(root = document) {
    let inputs = Array.from(
      root.querySelectorAll('input[type="password"]:not([disabled]):not([readonly])')
    );
    const allEls = Array.from(root.querySelectorAll('*'));
    for (const el of allEls) {
      if (el.shadowRoot) {
        inputs = inputs.concat(findPasswordInputs(el.shadowRoot));
      }
    }
    return inputs.filter(isVisible);
  }

  function findOtpInputs(root = document) {
    const otpSelectors = [
      'input[autocomplete="one-time-code"]',
      'input[name*="otp" i]',
      'input[name*="totp" i]',
      'input[name*="2fa" i]',
      'input[name*="two_factor" i]',
      'input[name*="verification" i]',
      'input[name*="security_code" i]',
      'input[name*="auth_code" i]',
      'input[id*="otp" i]',
      'input[id*="totp" i]',
      'input[id*="2fa" i]',
      'input[id*="verification" i]',
      'input[inputmode="numeric"][maxlength="6"]',
      'input[inputmode="numeric"][maxlength="8"]',
      'input[pattern*="[0-9]"][maxlength="6"]',
    ];

    let inputs = Array.from(root.querySelectorAll(otpSelectors.join(',')));
    const allEls = Array.from(root.querySelectorAll('*'));
    for (const el of allEls) {
      if (el.shadowRoot) {
        inputs = inputs.concat(findOtpInputs(el.shadowRoot));
      }
    }

    return inputs.filter((el) => {
      if (!isVisible(el) || el.type === 'hidden' || el.type === 'password') return false;
      const name = (el.name || '').toLowerCase();
      const id = (el.id || '').toLowerCase();
      if (name.includes('search') || id.includes('search')) return false;
      return true;
    });
  }

  function findIdentityInputs(root = document) {
    const prioritySelectors = [
      'input[autocomplete="username"]',
      'input[autocomplete="email"]',
      'input[name="username" i]',
      'input[name="login" i]',
      'input[name="email" i]',
      'input[name="identifier" i]',
      'input[id="username" i]',
      'input[id="login" i]',
      'input[id="email" i]',
      'input[id="identifierId" i]',
      'input[type="email"]',
      'input[autocomplete*="username" i]',
      'input[name*="user" i]',
      'input[id*="user" i]',
      'input[name*="login" i]',
      'input[id*="login" i]',
      'input[name*="email" i]',
      'input[id*="email" i]',
      'input[type="tel"]',
    ];

    let inputs = Array.from(root.querySelectorAll(prioritySelectors.join(',')));
    const allEls = Array.from(root.querySelectorAll('*'));
    for (const el of allEls) {
      if (el.shadowRoot) {
        inputs = inputs.concat(findIdentityInputs(el.shadowRoot));
      }
    }

    return inputs.filter((el) => {
      if (!isVisible(el) || el.type === 'hidden' || el.type === 'password') return false;
      const name = (el.name || '').toLowerCase();
      const id = (el.id || '').toLowerCase();
      const role = (el.getAttribute('role') || '').toLowerCase();
      if (
        el.type === 'search' ||
        role === 'searchbox' ||
        name === 'q' ||
        name === 'search' ||
        id.includes('search')
      ) {
        return false;
      }
      return true;
    });
  }

  function findFormFields(options = { includeTracked: false }) {
    const includeTracked = options && options.includeTracked === true;
    const passwordInputs = findPasswordInputs(document);
    const otpInputs = findOtpInputs(document);
    const identityInputs = findIdentityInputs(document);

    const fieldSets = [];
    const processedInputs = new Set();

    // 1. Process password inputs (standard login or password_only Step 2)
    for (const pwdInput of passwordInputs) {
      if (!includeTracked && pwdInput.dataset.multipadTracked) continue;
      pwdInput.dataset.multipadTracked = 'true';
      processedInputs.add(pwdInput);

      const rootScope = pwdInput.getRootNode ? pwdInput.getRootNode() : document;
      const form = pwdInput.form || pwdInput.closest('form');
      let usernameInput = null;

      if (form) {
        usernameInput = identityInputs.find((i) => form.contains(i) && i !== pwdInput);
        if (!usernameInput) {
          const generalCandidates = Array.from(
            form.querySelectorAll('input[type="text"], input[type="tel"], input:not([type])')
          );
          usernameInput = generalCandidates.find(
            (c) => c !== pwdInput && isVisible(c) && !processedInputs.has(c)
          );
        }
      }

      if (!usernameInput) {
        usernameInput = identityInputs.find(
          (i) => rootScope.contains(i) && i !== pwdInput && !processedInputs.has(i)
        );
      }

      if (usernameInput) {
        usernameInput.dataset.multipadTracked = 'true';
        processedInputs.add(usernameInput);
      }

      fieldSets.push({
        form,
        type: usernameInput ? 'login' : 'password_only',
        usernameInput: usernameInput || null,
        pwdInput: pwdInput,
        otpInput: null,
        primaryInput: pwdInput,
      });
    }

    // 2. Process standalone OTP / 2FA inputs
    for (const otpInput of otpInputs) {
      if (processedInputs.has(otpInput)) continue;
      if (!includeTracked && otpInput.dataset.multipadTracked) continue;
      otpInput.dataset.multipadTracked = 'true';
      processedInputs.add(otpInput);

      const form = otpInput.form || otpInput.closest('form');
      fieldSets.push({
        form,
        type: 'otp_only',
        usernameInput: null,
        pwdInput: null,
        otpInput: otpInput,
        primaryInput: otpInput,
      });
    }

    // 3. Process standalone identity inputs (Step 1 of multi-step login)
    for (const idInput of identityInputs) {
      if (processedInputs.has(idInput)) continue;
      if (!includeTracked && idInput.dataset.multipadTracked) continue;
      idInput.dataset.multipadTracked = 'true';
      processedInputs.add(idInput);

      const form = idInput.form || idInput.closest('form');
      fieldSets.push({
        form,
        type: 'identity_only',
        usernameInput: idInput,
        pwdInput: null,
        otpInput: null,
        primaryInput: idInput,
      });
    }

    return fieldSets;
  }

  // ---------------------------------------------------------------------------
  // Feature 7: Reactive Framework Autofill Injection
  // ---------------------------------------------------------------------------

  function injectFieldValue(element, value) {
    if (!element || value == null) return;

    // 1. Check contenteditable elements
    if (element.isContentEditable) {
      try {
        element.focus({ preventScroll: true });
        document.execCommand('selectAll', false, null);
        document.execCommand('insertText', false, value);
        element.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        element.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
      } catch (_) {}
      return;
    }

    // 2. Focus element without scrolling viewport
    try {
      element.focus({ preventScroll: true });
    } catch (_) {}
    element.dispatchEvent(new FocusEvent('focus', { bubbles: true, composed: true }));

    // 3. Reset React 16+ _valueTracker to guarantee synthetic onChange fires
    if (element._valueTracker) {
      element._valueTracker.setValue('');
    }

    // 4. Invoke native prototype property descriptor value setter
    const proto =
      element instanceof HTMLTextAreaElement
        ? window.HTMLTextAreaElement.prototype
        : window.HTMLInputElement.prototype;

    const descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
    const nativeSetter = descriptor ? descriptor.set : null;

    if (nativeSetter) {
      nativeSetter.call(element, value);
    } else {
      element.value = value;
    }

    // 5. Dispatch synthetic InputEvent with composed: true
    let inputEvent;
    try {
      inputEvent = new InputEvent('input', {
        bubbles: true,
        cancelable: true,
        composed: true,
        inputType: 'insertReplacementText',
        data: value,
      });
    } catch (_) {
      inputEvent = new Event('input', { bubbles: true, cancelable: true, composed: true });
    }
    element.dispatchEvent(inputEvent);

    // 6. Dispatch synthetic change event
    element.dispatchEvent(
      new Event('change', { bubbles: true, cancelable: true, composed: true })
    );

    // 7. Dispatch keydown & keyup for legacy validation handlers
    try {
      element.dispatchEvent(
        new KeyboardEvent('keydown', {
          bubbles: true,
          cancelable: true,
          composed: true,
          key: 'Unidentified',
        })
      );
      element.dispatchEvent(
        new KeyboardEvent('keyup', {
          bubbles: true,
          cancelable: true,
          composed: true,
          key: 'Unidentified',
        })
      );
    } catch (_) {}

    // 8. Dispatch blur event to trigger Angular touched state (ng-touched)
    element.dispatchEvent(new FocusEvent('blur', { bubbles: true, composed: true }));
  }

  // ---------------------------------------------------------------------------
  // Feature 10: Automated TOTP Auto-Copy & Clipboard Notification Toast
  // ---------------------------------------------------------------------------

  async function copyTotpToClipboard(totpCode) {
    if (!totpCode) return false;
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(totpCode);
        return true;
      }
    } catch (err) {
      console.warn('MultiPad: clipboard copy failed', err);
    }
    return false;
  }

  function showTotpToast(totpCode) {
    if (!totpCode) return;
    const existing = document.getElementById('multipad-toast-host');
    if (existing) existing.remove();

    const toastHost = document.createElement('div');
    toastHost.id = 'multipad-toast-host';
    toastHost.style.cssText =
      'position: fixed; top: 20px; right: 20px; z-index: 2147483647; pointer-events: none;';

    const shadow = toastHost.attachShadow({ mode: 'closed' });
    const formattedCode =
      totpCode.length === 6 ? `${totpCode.slice(0, 3)} ${totpCode.slice(3)}` : totpCode;

    shadow.innerHTML = `
      <style>
        .toast {
          display: flex;
          align-items: center;
          gap: 12px;
          background: #1E293B;
          color: #F8FAFC;
          border: 1px solid #334155;
          border-radius: 8px;
          padding: 10px 16px;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          font-size: 13px;
          box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
          pointer-events: auto;
          animation: slideIn 0.25s cubic-bezier(0.16, 1, 0.3, 1) forwards;
        }
        @keyframes slideIn {
          from { transform: translateY(-16px); opacity: 0; }
          to { transform: translateY(0); opacity: 1; }
        }
        .icon {
          font-size: 18px;
        }
        .content {
          display: flex;
          flex-direction: column;
          gap: 2px;
        }
        .title {
          font-weight: 600;
          color: #818CF8;
          font-size: 11px;
          text-transform: uppercase;
          letter-spacing: 0.5px;
        }
        .code-row {
          display: flex;
          align-items: center;
          gap: 8px;
        }
        .code {
          font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
          font-weight: 700;
          font-size: 14px;
          color: #10B981;
          letter-spacing: 1px;
        }
        .badge {
          font-size: 11px;
          color: #94A3B8;
        }
      </style>
      <div class="toast">
        <div class="icon">🛡️</div>
        <div class="content">
          <div class="title">MultiPad 2FA</div>
          <div class="code-row">
            <span class="code">${formattedCode}</span>
            <span class="badge">Copied to clipboard</span>
          </div>
        </div>
      </div>
    `;

    document.body.appendChild(toastHost);
    setTimeout(() => {
      if (toastHost.parentNode) toastHost.parentNode.removeChild(toastHost);
    }, 3500);
  }

  function applyAutofill(fieldSetOrTarget, credential) {
    if (!credential) return;

    let usernameInput = null;
    let pwdInput = null;
    let otpInput = null;

    if (fieldSetOrTarget && fieldSetOrTarget.primaryInput) {
      usernameInput = fieldSetOrTarget.usernameInput;
      pwdInput = fieldSetOrTarget.pwdInput;
      otpInput = fieldSetOrTarget.otpInput;
    } else if (fieldSetOrTarget) {
      usernameInput = fieldSetOrTarget;
    }

    // Autofill username / identity
    if (usernameInput && credential.username) {
      injectFieldValue(usernameInput, credential.username);
      lastIdentifiedUsername = credential.username;
    }

    // Autofill password
    if (pwdInput && credential.password) {
      injectFieldValue(pwdInput, credential.password);
    }

    // Autofill OTP if an OTP field is identified
    if (otpInput && credential.totp) {
      injectFieldValue(otpInput, credential.totp);
    }

    // Copy live TOTP to clipboard and display toast notification
    if (credential.totp) {
      copyTotpToClipboard(credential.totp);
      showTotpToast(credential.totp);
    }

    hideSuggestions();
  }

  // ---------------------------------------------------------------------------
  // Feature 9: In-Field Shield Badge & Floating Fixed-Position Dropdown
  // ---------------------------------------------------------------------------

  function attachFieldBadge(input, fieldSet) {
    if (input.dataset.multipadBadgeAttached) return;
    input.dataset.multipadBadgeAttached = 'true';

    const badgeHost = document.createElement('div');
    badgeHost.className = 'multipad-field-badge-host';
    badgeHost.dataset.multipadBadge = 'true';
    badgeHost.style.cssText =
      'position: fixed; z-index: 2147483646; width: 22px; height: 22px; cursor: pointer; pointer-events: auto; display: flex; align-items: center; justify-content: center;';

    const shadow = badgeHost.attachShadow({ mode: 'closed' });
    shadow.innerHTML = `
      <style>
        :host {
          all: initial;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
        }
        .shield-btn {
          width: 18px;
          height: 18px;
          display: flex;
          align-items: center;
          justify-content: center;
          border-radius: 4px;
          transition: transform 0.15s ease, opacity 0.15s ease;
          opacity: 0.75;
          user-select: none;
        }
        .shield-btn:hover {
          opacity: 1.0;
          transform: scale(1.15);
        }
        svg {
          width: 16px;
          height: 16px;
          fill: #818CF8;
          filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));
        }
      </style>
      <div class="shield-btn" title="MultiPad Autofill">
        <svg viewBox="0 0 24 24">
          <path d="M12 2L4 5v6.09c0 5.05 3.41 9.76 8 10.91 4.59-1.15 8-5.86 8-10.91V5l-8-3zm0 2.18l6 2.25v4.66c0 4.12-2.73 7.96-6 8.98-3.27-1.02-6-4.86-6-8.98V6.43l6-2.25z"/>
          <path d="M12 6.5a2.5 2.5 0 0 0-2.5 2.5c0 1.05.65 1.95 1.57 2.31v3.19a.93.93 0 0 0 1.86 0v-3.19c.92-.36 1.57-1.26 1.57-2.31a2.5 2.5 0 0 0-2.5-2.5z"/>
        </svg>
      </div>
    `;

    function updateBadgePos() {
      if (!input.isConnected || !isVisible(input)) {
        badgeHost.style.display = 'none';
        return;
      }
      const rect = input.getBoundingClientRect();
      badgeHost.style.display = 'flex';
      badgeHost.style.top = `${rect.top + (rect.height - 22) / 2}px`;
      badgeHost.style.left = `${rect.right - 26}px`;
    }

    badgeHost.addEventListener('mousedown', (e) => {
      e.preventDefault();
      e.stopPropagation();
      input.focus();
      if (overlayHost) {
        hideSuggestions();
      } else {
        showSuggestions(input, fieldSet);
      }
    });

    document.body.appendChild(badgeHost);
    updateBadgePos();

    window.addEventListener('scroll', updateBadgePos, { capture: true, passive: true });
    window.addEventListener('resize', updateBadgePos, { passive: true });
  }

  function updateDropdownPosition() {
    if (!activeTargetInput || !autofillDropdownEl || !overlayHost) return;

    if (!activeTargetInput.isConnected || !isVisible(activeTargetInput)) {
      hideSuggestions();
      return;
    }

    const rect = activeTargetInput.getBoundingClientRect();
    const innerW = window.innerWidth || 1024;
    const innerH = window.innerHeight || 768;

    // Only close if element is scrolled far offscreen in a real browser with non-zero dimensions
    if (
      (rect.width > 0 || rect.height > 0) &&
      (rect.bottom < -100 ||
        rect.top > innerH + 100 ||
        rect.right < -100 ||
        rect.left > innerW + 100)
    ) {
      hideSuggestions();
      return;
    }

    const dropdownWidth = 260;
    const dropdownHeight = autofillDropdownEl.offsetHeight || 180;

    // Viewport-relative horizontal clamping
    let left = rect.left;
    if (left + dropdownWidth > innerW - 8) {
      left = Math.max(8, innerW - dropdownWidth - 8);
    }
    if (left < 8) left = 8;

    // Viewport-relative vertical collision detection (flip above input if bottom space < 220px)
    let top = rect.bottom + 4;
    const spaceBelow = innerH - rect.bottom;
    if (spaceBelow < 220 && rect.top > dropdownHeight + 8) {
      top = rect.top - dropdownHeight - 4;
    }

    autofillDropdownEl.style.top = `${top}px`;
    autofillDropdownEl.style.left = `${left}px`;
  }

  function schedulePositionUpdate() {
    if (rafPositionId) cancelAnimationFrame(rafPositionId);
    rafPositionId = requestAnimationFrame(updateDropdownPosition);
  }

  function highlightSelectedItem(items) {
    items.forEach((item, idx) => {
      if (idx === selectedDropdownIndex) {
        item.style.background = '#334155';
        item.style.outline = '1px solid #818CF8';
      } else {
        item.style.background = 'transparent';
        item.style.outline = 'none';
      }
    });
  }

  function handleInputKeydown(e) {
    if (!overlayHost || matchedCredentials.length === 0) return;

    const items = overlayHost._credentialItems || [];

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      selectedDropdownIndex = (selectedDropdownIndex + 1) % items.length;
      highlightSelectedItem(items);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      selectedDropdownIndex =
        selectedDropdownIndex <= 0 ? items.length - 1 : selectedDropdownIndex - 1;
      highlightSelectedItem(items);
    } else if (e.key === 'Enter') {
      if (selectedDropdownIndex >= 0 && selectedDropdownIndex < matchedCredentials.length) {
        e.preventDefault();
        applyAutofill(activeFieldSet, matchedCredentials[selectedDropdownIndex]);
      }
    } else if (e.key === 'Tab') {
      if (selectedDropdownIndex >= 0 && selectedDropdownIndex < matchedCredentials.length) {
        applyAutofill(activeFieldSet, matchedCredentials[selectedDropdownIndex]);
      } else {
        hideSuggestions();
      }
    } else if (e.key === 'Escape') {
      e.preventDefault();
      hideSuggestions();
    }
  }

  function showSuggestions(targetInput, fieldSet) {
    hideSuggestions();
    if (matchedCredentials.length === 0) return;

    activeTargetInput = targetInput;
    activeFieldSet = fieldSet;
    selectedDropdownIndex = -1;

    overlayHost = document.createElement('div');
    overlayHost.id = 'multipad-autofill-host';
    overlayHost.className = 'multipad-autofill-host multipad-autofill-dropdown';
    overlayHost.style.cssText =
      'position: fixed; top: 0; left: 0; width: 0; height: 0; z-index: 2147483647;';

    const shadowRoot = overlayHost.attachShadow({ mode: 'closed' });

    autofillDropdownEl = document.createElement('div');
    autofillDropdownEl.className = 'multipad-autofill-dropdown-inner';
    autofillDropdownEl.style.cssText = `
      position: fixed;
      z-index: 2147483647;
      background: #1E293B;
      color: #F8FAFC;
      border: 1px solid #334155;
      border-radius: 8px;
      box-shadow: 0 8px 24px rgba(0,0,0,0.5);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 13px;
      min-width: 240px;
      max-width: 320px;
      overflow: hidden;
    `;

    const header = document.createElement('div');
    header.style.cssText =
      'padding: 8px 12px; background: #0F172A; font-weight: 600; font-size: 11px; color: #818CF8; border-bottom: 1px solid #334155; display: flex; align-items: center; justify-content: space-between;';
    header.innerHTML = `<span>🛡️ MultiPad Logins</span><span style="font-size: 10px; color: #94A3B8;">${matchedCredentials.length} found</span>`;
    autofillDropdownEl.appendChild(header);

    const credentialItems = [];

    matchedCredentials.forEach((cred, index) => {
      const item = document.createElement('div');
      item.style.cssText =
        'padding: 8px 12px; cursor: pointer; border-bottom: 1px solid #334155; transition: background 0.15s;';
      item.onmouseover = () => {
        selectedDropdownIndex = index;
        highlightSelectedItem(credentialItems);
      };

      const titleRow = document.createElement('div');
      titleRow.style.cssText =
        'display: flex; align-items: center; justify-content: space-between;';

      const title = document.createElement('div');
      title.style.cssText =
        'font-weight: 600; color: #F8FAFC; font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;';
      title.innerText = cred.title || 'Credential';
      titleRow.appendChild(title);

      if (cred.totp) {
        const totpChip = document.createElement('span');
        totpChip.style.cssText =
          'font-family: monospace; font-size: 10px; font-weight: 700; color: #10B981; background: rgba(16, 185, 129, 0.15); padding: 1px 4px; border-radius: 4px;';
        totpChip.innerText = '2FA';
        titleRow.appendChild(totpChip);
      }

      const user = document.createElement('div');
      user.style.cssText =
        'font-size: 11px; color: #94A3B8; margin-top: 2px; font-family: monospace; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;';
      user.innerText = cred.username || '(No username)';

      item.appendChild(titleRow);
      item.appendChild(user);

      item.addEventListener('mousedown', (e) => {
        e.preventDefault();
        applyAutofill(fieldSet, cred);
      });

      autofillDropdownEl.appendChild(item);
      credentialItems.push(item);
    });

    overlayHost._credentialItems = credentialItems;
    shadowRoot.appendChild(autofillDropdownEl);
    document.body.appendChild(overlayHost);

    updateDropdownPosition();

    // Attach tracking listeners
    window.addEventListener('scroll', schedulePositionUpdate, { capture: true, passive: true });
    window.addEventListener('resize', schedulePositionUpdate, { passive: true });
    targetInput.addEventListener('keydown', handleInputKeydown);
  }

  function hideSuggestions() {
    if (rafPositionId) {
      cancelAnimationFrame(rafPositionId);
      rafPositionId = null;
    }
    if (activeTargetInput) {
      activeTargetInput.removeEventListener('keydown', handleInputKeydown);
      activeTargetInput = null;
    }
    activeFieldSet = null;
    selectedDropdownIndex = -1;

    window.removeEventListener('scroll', schedulePositionUpdate, { capture: true });
    window.removeEventListener('resize', schedulePositionUpdate);

    if (overlayHost && overlayHost.parentNode) {
      overlayHost.parentNode.removeChild(overlayHost);
      overlayHost = null;
      autofillDropdownEl = null;
    }
  }

  function fetchCredentials(onSuccess) {
    chrome.runtime.sendMessage(
      { action: 'QUERY_CREDENTIALS', url: window.location.href },
      (response) => {
        if (chrome.runtime.lastError || !response || !response.success) {
          return;
        }
        matchedCredentials = response.matches || [];
        if (onSuccess) {
          onSuccess(matchedCredentials);
        }
      }
    );
  }

  function setupFormListeners(fieldSet) {
    const { form, usernameInput, pwdInput, otpInput, primaryInput } = fieldSet;

    // Attach in-field shield badge to inputs
    if (primaryInput) attachFieldBadge(primaryInput, fieldSet);
    if (usernameInput && usernameInput !== primaryInput) attachFieldBadge(usernameInput, fieldSet);
    if (otpInput && otpInput !== primaryInput) attachFieldBadge(otpInput, fieldSet);

    const handleFocus = (input) => {
      input.addEventListener('focus', () => {
        if (matchedCredentials.length > 0) {
          showSuggestions(input, fieldSet);
        } else {
          fetchCredentials((creds) => {
            if (creds && creds.length > 0) {
              showSuggestions(input, fieldSet);
            }
          });
        }
      });
      input.addEventListener('blur', () => {
        setTimeout(hideSuggestions, 200);
      });
    };

    if (usernameInput) handleFocus(usernameInput);
    if (pwdInput) handleFocus(pwdInput);
    if (otpInput) handleFocus(otpInput);

    // Submission capture with debouncing
    let lastCaptureTime = 0;
    let lastCapturedKey = '';

    const captureSubmission = () => {
      let username = usernameInput ? usernameInput.value.trim() : '';
      if (!username && lastIdentifiedUsername) {
        username = lastIdentifiedUsername;
      }
      const password = pwdInput ? pwdInput.value : '';

      if (!password || (!username && password.length < 6)) {
        return;
      }

      const now = Date.now();
      const captureKey = `${username}:${password}:${window.location.origin}`;
      if (now - lastCaptureTime < 2000 && lastCapturedKey === captureKey) {
        return;
      }
      lastCaptureTime = now;
      lastCapturedKey = captureKey;

      chrome.runtime.sendMessage({
        action: 'CAPTURE_CREDENTIAL',
        url: window.location.origin,
        username: username,
        password: password,
      });
    };

    if (form) {
      form.addEventListener('submit', captureSubmission);
    }

    const submitBtns = form
      ? Array.from(form.querySelectorAll('button[type="submit"], input[type="submit"]'))
      : [];
    for (const btn of submitBtns) {
      btn.addEventListener('click', () => {
        setTimeout(captureSubmission, 50);
      });
    }

    const handleKeyDown = (e) => {
      if (e.key === 'Enter' || e.keyCode === 13) {
        // If suggestion dropdown is open, dropdown key handler controls Enter
        if (overlayHost && selectedDropdownIndex >= 0) {
          return;
        }
        captureSubmission();
      }
    };
    if (pwdInput) pwdInput.addEventListener('keydown', handleKeyDown);
    if (usernameInput) usernameInput.addEventListener('keydown', handleKeyDown);
  }

  async function init() {
    fetchCredentials();

    const fieldSets = findFormFields();
    for (const fieldSet of fieldSets) {
      setupFormListeners(fieldSet);
    }
  }

  // Handle messages from extension popup
  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (msg.action === 'AUTOFILL_CREDENTIAL' && msg.credential) {
      const fieldSets = findFormFields({ includeTracked: true });
      if (fieldSets.length > 0) {
        applyAutofill(fieldSets[0], msg.credential);
        sendResponse({ success: true });
      } else {
        sendResponse({ success: false, error: 'No login fields found on page' });
      }
    } else if (msg.action === 'FILL_GENERATED_PASSWORD' && msg.password) {
      const active = document.activeElement;
      if (active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable)) {
        injectFieldValue(active, msg.password);
        sendResponse({ success: true });
      } else {
        const passwordInputs = findPasswordInputs(document);
        if (passwordInputs.length > 0) {
          injectFieldValue(passwordInputs[0], msg.password);
          sendResponse({ success: true });
        } else {
          const identityInputs = findIdentityInputs(document);
          if (identityInputs.length > 0) {
            injectFieldValue(identityInputs[0], msg.password);
            sendResponse({ success: true });
          } else {
            sendResponse({ success: false, error: 'No suitable input field found to fill password' });
          }
        }
      }
    }
    return true;
  });

  // Run on page load
  init();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  }

  // Observe dynamically loaded SPAs
  const observer = new MutationObserver(() => {
    const fieldSets = findFormFields();
    if (fieldSets.length > 0) {
      for (const fieldSet of fieldSets) {
        setupFormListeners(fieldSet);
      }
      if (matchedCredentials.length === 0) {
        fetchCredentials();
      }
    }
  });

  if (document.body) {
    observer.observe(document.body, { childList: true, subtree: true });
  } else {
    document.addEventListener('DOMContentLoaded', () => {
      if (document.body) {
        observer.observe(document.body, { childList: true, subtree: true });
      }
    });
  }
})();
