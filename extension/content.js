// MultiPad Content Script (Form Detection, Autofill & Submission Capture)

(() => {
  let matchedCredentials = [];
  let autofillOverlay = null;

  function findPasswordInputs(root = document) {
    let inputs = Array.from(root.querySelectorAll('input[type="password"]'));
    const allEls = Array.from(root.querySelectorAll('*'));
    for (const el of allEls) {
      if (el.shadowRoot) {
        inputs = inputs.concat(findPasswordInputs(el.shadowRoot));
      }
    }
    return inputs;
  }

  function findFormFields(options = { includeTracked: false }) {
    const includeTracked = options && options.includeTracked === true;
    const passwordInputs = findPasswordInputs(document);
    if (passwordInputs.length === 0) return [];

    const fieldPairs = [];

    // Prioritized selectors for genuine username/login/email fields to avoid preceding search inputs
    const prioritySelectors = [
      'input[autocomplete="username"]',
      'input[autocomplete="email"]',
      'input[name="username" i]',
      'input[name="login" i]',
      'input[name="email" i]',
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

    for (const pwdInput of passwordInputs) {
      if (!includeTracked && pwdInput.dataset.multipadTracked) continue;
      pwdInput.dataset.multipadTracked = 'true';

      const rootScope = pwdInput.getRootNode ? pwdInput.getRootNode() : document;
      const form = pwdInput.form || pwdInput.closest('form');
      let usernameInput = null;

      if (form) {
        // Prioritize explicit username/email/identity inputs before generic text fields
        for (const selector of prioritySelectors) {
          const match = Array.from(form.querySelectorAll(selector)).find(c => c !== pwdInput && isVisible(c));
          if (match) {
            usernameInput = match;
            break;
          }
        }
        if (!usernameInput) {
          const generalCandidates = Array.from(form.querySelectorAll('input[type="text"], input[type="tel"], input:not([type])'));
          usernameInput = generalCandidates.find(c => c !== pwdInput && isVisible(c));
        }
      }

      if (!usernameInput) {
        // Fallback: look in rootScope (document or shadow root)
        for (const selector of prioritySelectors) {
          const match = Array.from(rootScope.querySelectorAll(selector)).find(c => c !== pwdInput && isVisible(c));
          if (match) {
            usernameInput = match;
            break;
          }
        }
        if (!usernameInput) {
          const allInputs = Array.from(rootScope.querySelectorAll('input[type="text"], input[type="tel"], input[type="email"], input:not([type])'));
          usernameInput = allInputs.find(c => isVisible(c) && c !== pwdInput);
        }
      }

      fieldPairs.push({ form, usernameInput, pwdInput });
    }

    return fieldPairs;
  }

  function isVisible(el) {
    if (!el) return false;
    const style = window.getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
  }

  function applyAutofill(usernameInput, pwdInput, credential) {
    if (usernameInput && credential.username) {
      usernameInput.value = credential.username;
      usernameInput.dispatchEvent(new Event('input', { bubbles: true }));
      usernameInput.dispatchEvent(new Event('change', { bubbles: true }));
    }
    if (pwdInput && credential.password) {
      pwdInput.value = credential.password;
      pwdInput.dispatchEvent(new Event('input', { bubbles: true }));
      pwdInput.dispatchEvent(new Event('change', { bubbles: true }));
    }
    hideSuggestions();
  }

  function showSuggestions(targetInput, usernameInput, pwdInput) {
    hideSuggestions();
    if (matchedCredentials.length === 0) return;

    const rect = targetInput.getBoundingClientRect();
    autofillOverlay = document.createElement('div');
    autofillOverlay.className = 'multipad-autofill-dropdown';
    autofillOverlay.style.cssText = `
      position: absolute;
      top: ${rect.bottom + window.scrollY + 4}px;
      left: ${rect.left + window.scrollX}px;
      z-index: 2147483647;
      background: #1E1E2E;
      color: #CDD6F4;
      border: 1px solid #45475A;
      border-radius: 8px;
      box-shadow: 0 4px 16px rgba(0,0,0,0.4);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 13px;
      min-width: 220px;
      overflow: hidden;
    `;

    const header = document.createElement('div');
    header.style.cssText = 'padding: 8px 12px; background: #181825; font-weight: 600; font-size: 11px; color: #89B4FA; border-bottom: 1px solid #313244;';
    header.innerText = 'MultiPad Logins';
    autofillOverlay.appendChild(header);

    for (const cred of matchedCredentials) {
      const item = document.createElement('div');
      item.style.cssText = 'padding: 8px 12px; cursor: pointer; border-bottom: 1px solid #313244; transition: background 0.15s;';
      item.onmouseover = () => item.style.background = '#313244';
      item.onmouseout = () => item.style.background = 'transparent';

      const title = document.createElement('div');
      title.style.cssText = 'font-weight: 500; color: #CDD6F4;';
      title.innerText = cred.title || 'Credential';

      const user = document.createElement('div');
      user.style.cssText = 'font-size: 11px; color: #A6ADC8;';
      user.innerText = cred.username || '(No username)';

      item.appendChild(title);
      item.appendChild(user);

      item.addEventListener('mousedown', (e) => {
        e.preventDefault();
        applyAutofill(usernameInput, pwdInput, cred);
      });

      autofillOverlay.appendChild(item);
    }

    document.body.appendChild(autofillOverlay);
  }

  function hideSuggestions() {
    if (autofillOverlay && autofillOverlay.parentNode) {
      autofillOverlay.parentNode.removeChild(autofillOverlay);
      autofillOverlay = null;
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

  function setupFormListeners(pair) {
    const { form, usernameInput, pwdInput } = pair;

    const handleFocus = (input) => {
      input.addEventListener('focus', () => {
        if (matchedCredentials.length > 0) {
          showSuggestions(input, usernameInput, pwdInput);
        } else {
          fetchCredentials((creds) => {
            if (creds && creds.length > 0) {
              showSuggestions(input, usernameInput, pwdInput);
            }
          });
        }
      });
      input.addEventListener('blur', () => {
        // Small delay to allow click on dropdown
        setTimeout(hideSuggestions, 200);
      });
    };

    if (usernameInput) handleFocus(usernameInput);
    if (pwdInput) handleFocus(pwdInput);

    // Submission capture
    const captureSubmission = () => {
      const username = usernameInput ? usernameInput.value.trim() : '';
      const password = pwdInput ? pwdInput.value : '';

      if (password && (username || password.length >= 6)) {
        chrome.runtime.sendMessage({
          action: 'CAPTURE_CREDENTIAL',
          url: window.location.origin,
          username: username,
          password: password,
        });
      }
    };

    if (form) {
      form.addEventListener('submit', captureSubmission);
    }

    // Also attach to submit buttons
    const submitBtns = form
      ? Array.from(form.querySelectorAll('button[type="submit"], input[type="submit"]'))
      : [];
    for (const btn of submitBtns) {
      btn.addEventListener('click', () => {
        setTimeout(captureSubmission, 50);
      });
    }

    // Enter key capture (for AJAX / formless logins)
    const handleKeyDown = (e) => {
      if (e.key === 'Enter' || e.keyCode === 13) {
        captureSubmission();
      }
    };
    if (pwdInput) pwdInput.addEventListener('keydown', handleKeyDown);
    if (usernameInput) usernameInput.addEventListener('keydown', handleKeyDown);
  }

  async function init() {
    // Always dispatch QUERY_CREDENTIALS for window.location.href even if forms haven't rendered yet
    fetchCredentials();

    // If forms already present, attach listeners
    const pairs = findFormFields();
    for (const pair of pairs) {
      setupFormListeners(pair);
    }
  }

  // Handle messages from extension popup
  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (msg.action === 'AUTOFILL_CREDENTIAL' && msg.credential) {
      const pairs = findFormFields({ includeTracked: true });
      if (pairs.length > 0) {
        applyAutofill(pairs[0].usernameInput, pairs[0].pwdInput, msg.credential);
        sendResponse({ success: true });
      } else {
        sendResponse({ success: false, error: 'No login fields found on page' });
      }
    }
    return true;
  });

  // Run on page load (immediately as well as on DOMContentLoaded if still loading)
  init();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  }

  // Observe dynamically loaded SPAs
  const observer = new MutationObserver(() => {
    const pairs = findFormFields();
    if (pairs.length > 0) {
      for (const pair of pairs) {
        setupFormListeners(pair);
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
