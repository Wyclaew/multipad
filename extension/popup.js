// MultiPad Extension Popup Controller
// MultiPad v1.4.0 — Features 10 & 11

document.addEventListener('DOMContentLoaded', async () => {
  // Elements - Header & Views
  const statusBadge = document.getElementById('statusBadge');
  const viewUnpaired = document.getElementById('viewUnpaired');
  const viewLocked = document.getElementById('viewLocked');
  const viewVault = document.getElementById('viewVault');
  const viewGenerator = document.getElementById('viewGenerator');

  // Elements - Tabs
  const tabBtnVault = document.getElementById('tabBtnVault');
  const tabBtnGenerator = document.getElementById('tabBtnGenerator');

  // Elements - Vault Tab
  const currentDomainEl = document.getElementById('currentDomain');
  const searchInput = document.getElementById('searchInput');
  const clearSearchBtn = document.getElementById('clearSearchBtn');
  const credentialsList = document.getElementById('credentialsList');
  const noMatchesState = document.getElementById('noMatchesState');
  const goToGeneratorBtn = document.getElementById('goToGeneratorBtn');
  const pairingCodeInput = document.getElementById('pairingCodeInput');
  const pairBtn = document.getElementById('pairBtn');
  const refreshLockBtn = document.getElementById('refreshLockBtn');

  // Elements - Generator Tab
  const generatedSecretText = document.getElementById('generatedSecretText');
  const regenSecretBtn = document.getElementById('regenSecretBtn');
  const copySecretBtn = document.getElementById('copySecretBtn');
  const fillSecretBtn = document.getElementById('fillSecretBtn');

  const entSeg1 = document.getElementById('entSeg1');
  const entSeg2 = document.getElementById('entSeg2');
  const entSeg3 = document.getElementById('entSeg3');
  const entSeg4 = document.getElementById('entSeg4');
  const entropyScoreLabel = document.getElementById('entropyScoreLabel');
  const entropyCrackLabel = document.getElementById('entropyCrackLabel');

  const modeBtnPassword = document.getElementById('modeBtnPassword');
  const modeBtnPassphrase = document.getElementById('modeBtnPassphrase');
  const passwordControls = document.getElementById('passwordControls');
  const passphraseControls = document.getElementById('passphraseControls');

  const lengthSlider = document.getElementById('lengthSlider');
  const lengthValueDisplay = document.getElementById('lengthValueDisplay');
  const chkUpper = document.getElementById('chkUpper');
  const chkLower = document.getElementById('chkLower');
  const chkNumbers = document.getElementById('chkNumbers');
  const chkSymbols = document.getElementById('chkSymbols');
  const chkAmbiguous = document.getElementById('chkAmbiguous');

  const wordCountSlider = document.getElementById('wordCountSlider');
  const wordCountValueDisplay = document.getElementById('wordCountValueDisplay');
  const separatorSelect = document.getElementById('separatorSelect');
  const chkCapitalize = document.getElementById('chkCapitalize');
  const chkAddNumber = document.getElementById('chkAddNumber');

  let currentTab = null;
  let allCredentials = [];
  let totpTickerInterval = null;
  let activeTabName = 'vault';
  let generatorMode = 'password';

  // ---------------------------------------------------------------------------
  // Tab Switching
  // ---------------------------------------------------------------------------
  function switchTab(tabName) {
    activeTabName = tabName;
    if (tabName === 'vault') {
      tabBtnVault.classList.add('active');
      tabBtnGenerator.classList.remove('active');
      viewGenerator.classList.add('hidden');
      checkState();
    } else {
      tabBtnGenerator.classList.add('active');
      tabBtnVault.classList.remove('active');
      viewUnpaired.classList.add('hidden');
      viewLocked.classList.add('hidden');
      viewVault.classList.add('hidden');
      viewGenerator.classList.remove('hidden');
      generateSecret();
    }
  }

  tabBtnVault.addEventListener('click', () => switchTab('vault'));
  tabBtnGenerator.addEventListener('click', () => switchTab('generator'));
  if (goToGeneratorBtn) {
    goToGeneratorBtn.addEventListener('click', () => switchTab('generator'));
  }

  // ---------------------------------------------------------------------------
  // Active Tab Context Detection
  // ---------------------------------------------------------------------------
  try {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs && tabs.length > 0) {
      currentTab = tabs[0];
      const url = new URL(currentTab.url || 'about:blank');
      currentDomainEl.innerText = url.hostname || 'Active Tab';
      currentDomainEl.title = url.hostname || '';
    }
  } catch (_) {
    currentDomainEl.innerText = 'Browser Tab';
  }

  // ---------------------------------------------------------------------------
  // Bridge State Management
  // ---------------------------------------------------------------------------
  function setBridgeState(state) {
    if (activeTabName !== 'vault') return;

    viewUnpaired.classList.add('hidden');
    viewLocked.classList.add('hidden');
    viewVault.classList.add('hidden');

    statusBadge.className = 'status-badge';

    if (state === 'unlocked') {
      viewVault.classList.remove('hidden');
      statusBadge.innerText = 'Unlocked';
      statusBadge.classList.add('status-unlocked');
    } else if (state === 'locked') {
      viewLocked.classList.remove('hidden');
      statusBadge.innerText = 'Locked';
      statusBadge.classList.add('status-locked');
    } else {
      viewUnpaired.classList.remove('hidden');
      statusBadge.innerText = 'Unpaired';
      statusBadge.classList.add('status-offline');
    }
  }

  async function checkState() {
    chrome.runtime.sendMessage({ action: 'CHECK_STATUS' }, async (res) => {
      if (chrome.runtime.lastError || !res || !res.success) {
        setBridgeState('unpaired');
        return;
      }

      if (res.status === 'locked') {
        setBridgeState('locked');
      } else if (res.status === 'unlocked') {
        setBridgeState('unlocked');
        await loadCredentials();
      } else {
        setBridgeState('unpaired');
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Vault Tab Credential Loading & Rendering
  // ---------------------------------------------------------------------------
  async function loadCredentials() {
    if (!currentTab || !currentTab.url) return;

    chrome.runtime.sendMessage(
      { action: 'QUERY_CREDENTIALS', url: currentTab.url },
      (res) => {
        if (chrome.runtime.lastError || !res || !res.success) {
          if (res && res.locked) {
            setBridgeState('locked');
            return;
          }
          renderCredentials([]);
          return;
        }

        allCredentials = res.matches || [];
        renderCredentials(allCredentials);
        startTotpTicker();
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

      // Card Header
      const header = document.createElement('div');
      header.className = 'card-title-row';

      const title = document.createElement('div');
      title.className = 'card-title';
      title.innerText = cred.title || 'Login';
      title.title = cred.title || '';
      header.appendChild(title);
      card.appendChild(header);

      // Username Row
      const userRow = document.createElement('div');
      userRow.className = 'card-info-row';

      const userText = document.createElement('span');
      userText.className = 'card-username';
      userText.innerText = cred.username || '(No username)';
      userText.title = cred.username || '';
      userRow.appendChild(userText);

      const copyUserBtn = document.createElement('button');
      copyUserBtn.className = 'btn-text-action';
      copyUserBtn.innerText = '📋 Copy User';
      copyUserBtn.title = 'Copy username to clipboard';
      copyUserBtn.onclick = (e) => {
        e.stopPropagation();
        copyText(cred.username, copyUserBtn, '📋 Copy User');
      };
      userRow.appendChild(copyUserBtn);
      card.appendChild(userRow);

      // Password Row (with Reveal Toggle)
      const passRow = document.createElement('div');
      passRow.className = 'card-info-row';

      const passText = document.createElement('span');
      passText.className = 'card-password';
      passText.innerText = '••••••••••••';
      passRow.appendChild(passText);

      const passActions = document.createElement('div');
      passActions.style.display = 'flex';
      passActions.style.gap = '4px';

      let isRevealed = false;
      const revealBtn = document.createElement('button');
      revealBtn.className = 'btn-text-action';
      revealBtn.innerText = '👁️';
      revealBtn.title = 'Reveal / Hide password';
      revealBtn.onclick = (e) => {
        e.stopPropagation();
        isRevealed = !isRevealed;
        if (isRevealed) {
          passText.innerText = cred.password || '';
          revealBtn.innerText = '🙈';
        } else {
          passText.innerText = '••••••••••••';
          revealBtn.innerText = '👁️';
        }
      };
      passActions.appendChild(revealBtn);

      const copyPassBtn = document.createElement('button');
      copyPassBtn.className = 'btn-text-action';
      copyPassBtn.innerText = '🔑 Copy';
      copyPassBtn.title = 'Copy password to clipboard';
      copyPassBtn.onclick = (e) => {
        e.stopPropagation();
        copyText(cred.password, copyPassBtn, '🔑 Copy');
      };
      passActions.appendChild(copyPassBtn);
      passRow.appendChild(passActions);
      card.appendChild(passRow);

      // Live TOTP Ticker Row (if TOTP token exists)
      if (cred.totp) {
        const totpBox = document.createElement('div');
        totpBox.className = 'totp-ticker-box';
        totpBox.title = 'Click to copy 2FA code';

        const totpHeader = document.createElement('div');
        totpHeader.className = 'totp-header';
        totpHeader.innerHTML = '<span>2FA Authenticator</span><span class="totp-seconds-label">...</span>';
        totpBox.appendChild(totpHeader);

        const totpCodeRow = document.createElement('div');
        totpCodeRow.className = 'totp-code-row';

        const totpCode = document.createElement('span');
        totpCode.className = 'totp-code';
        const formattedCode =
          cred.totp.length === 6
            ? `${cred.totp.slice(0, 3)} ${cred.totp.slice(3)}`
            : cred.totp;
        totpCode.innerText = formattedCode;
        totpCodeRow.appendChild(totpCode);

        const copyTotpBadge = document.createElement('span');
        copyTotpBadge.className = 'totp-seconds-badge';
        copyTotpBadge.innerText = 'Copy';
        totpCodeRow.appendChild(copyTotpBadge);
        totpBox.appendChild(totpCodeRow);

        const progressBg = document.createElement('div');
        progressBg.className = 'totp-progress-bar-bg';
        const progressFill = document.createElement('div');
        progressFill.className = 'totp-progress-bar-fill';
        progressBg.appendChild(progressFill);
        totpBox.appendChild(progressBg);

        totpBox.onclick = () => {
          copyText(cred.totp, copyTotpBadge, 'Copy');
        };

        totpBox.dataset.totpBox = 'true';
        card.appendChild(totpBox);
      }

      // Card Bottom Action Bar (Autofill)
      const bottomActions = document.createElement('div');
      bottomActions.className = 'card-bottom-actions';

      const autofillBtn = document.createElement('button');
      autofillBtn.className = 'btn-autofill-action';
      autofillBtn.innerText = '⚡ Autofill';
      autofillBtn.onclick = () => autofill(cred);
      bottomActions.appendChild(autofillBtn);
      card.appendChild(bottomActions);

      credentialsList.appendChild(card);
    }
  }

  // ---------------------------------------------------------------------------
  // Animated Live TOTP Countdown Ticker (RFC 6238 30s cycle)
  // ---------------------------------------------------------------------------
  function updateTotpVisuals() {
    const epochSeconds = Math.floor(Date.now() / 1000);
    const secondsRemaining = 30 - (epochSeconds % 30);
    const percentage = (secondsRemaining / 30) * 100;

    const totpBoxes = document.querySelectorAll('[data-totp-box="true"]');
    totpBoxes.forEach((box) => {
      const label = box.querySelector('.totp-seconds-label');
      if (label) label.innerText = `${secondsRemaining}s`;

      const fill = box.querySelector('.totp-progress-bar-fill');
      if (fill) fill.style.width = `${percentage}%`;
    });

    // Auto-rollover at 30s boundary
    if (secondsRemaining === 30) {
      loadCredentials();
    }
  }

  function startTotpTicker() {
    if (totpTickerInterval) clearInterval(totpTickerInterval);
    updateTotpVisuals();
    totpTickerInterval = setInterval(updateTotpVisuals, 1000);
  }

  // ---------------------------------------------------------------------------
  // Actions: Autofill, Copy Text
  // ---------------------------------------------------------------------------
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

  async function copyText(text, element, defaultText) {
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      element.innerText = '✓ Copied!';
      element.style.color = '#10B981';
      setTimeout(() => {
        element.innerText = defaultText;
        element.style.color = '';
      }, 1500);
    } catch (err) {
      console.warn('MultiPad: copy to clipboard failed', err);
    }
  }

  // ---------------------------------------------------------------------------
  // Search Filter with Clear
  // ---------------------------------------------------------------------------
  searchInput.addEventListener('input', (e) => {
    const q = e.target.value.toLowerCase().trim();
    if (q) {
      clearSearchBtn.classList.remove('hidden');
    } else {
      clearSearchBtn.classList.add('hidden');
    }

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

  clearSearchBtn.addEventListener('click', () => {
    searchInput.value = '';
    clearSearchBtn.classList.add('hidden');
    renderCredentials(allCredentials);
    searchInput.focus();
  });

  // ---------------------------------------------------------------------------
  // Pairing & Refresh Actions
  // ---------------------------------------------------------------------------
  pairBtn.addEventListener('click', () => {
    pairBtn.disabled = true;
    pairBtn.innerText = 'Pairing...';
    const code = pairingCodeInput ? pairingCodeInput.value.trim() : '';
    chrome.runtime.sendMessage({ action: 'PAIR', code: code }, (res) => {
      pairBtn.disabled = false;
      pairBtn.innerText = 'Pair with MultiPad';
      if (res && res.success) {
        checkState();
      } else {
        alert(
          res && res.error
            ? res.error
            : 'Pairing failed. Make sure MultiPad desktop is open and PIN is correct.'
        );
      }
    });
  });

  refreshLockBtn.addEventListener('click', () => {
    checkState();
  });

  // ---------------------------------------------------------------------------
  // Feature 11: Cryptographically Secure Password / Passphrase Generator
  // ---------------------------------------------------------------------------

  const EFF_WORDLIST = [
    'account', 'accurate', 'achieve', 'acoustic', 'acquire', 'action', 'active',
    'actor', 'adapt', 'addition', 'address', 'adjust', 'admit', 'adult', 'advance',
    'advice', 'aerobic', 'affair', 'afford', 'afraid', 'agent', 'agree', 'ahead',
    'airport', 'album', 'alert', 'alien', 'alligator', 'alpha', 'alpine', 'aluminum',
    'always', 'amazing', 'amber', 'ambition', 'amount', 'amuse', 'anchor', 'ancient',
    'angel', 'anger', 'animal', 'ankle', 'annual', 'answer', 'antenna', 'antique',
    'anxiety', 'anybody', 'apart', 'apology', 'appear', 'apple', 'approve', 'apron',
    'arcade', 'arch', 'arctic', 'area', 'arena', 'argue', 'armadillo', 'armor',
    'army', 'around', 'arrange', 'arrest', 'arrive', 'arrow', 'artist', 'artwork',
    'aspect', 'assault', 'asset', 'assist', 'assume', 'athlete', 'atlas', 'atom',
    'attack', 'attend', 'attitude', 'attract', 'auction', 'audit', 'august', 'aunt',
    'author', 'auto', 'autumn', 'average', 'avocado', 'avoid', 'awake', 'aware',
    'awesome', 'awful', 'awkward', 'axis', 'baby', 'bachelor', 'bacon', 'badge',
    'bagel', 'baggage', 'baker', 'balance', 'balcony', 'ball', 'bamboo', 'banana',
    'banner', 'barber', 'bargain', 'barrel', 'barrier', 'baseball', 'basic', 'basket',
    'battery', 'battle', 'beach', 'beacon', 'beak', 'beam', 'bean', 'beauty',
    'because', 'become', 'beef', 'before', 'begin', 'behave', 'behind', 'believe',
    'belong', 'bench', 'benefit', 'best', 'betray', 'better', 'between', 'beyond',
    'bicycle', 'bid', 'bike', 'bind', 'biology', 'bird', 'birth', 'bitter',
    'black', 'blade', 'blame', 'blanket', 'blast', 'bleak', 'bless', 'blind',
    'blood', 'blossom', 'blouse', 'blue', 'blur', 'blush', 'board', 'boat',
    'body', 'boil', 'bomb', 'bone', 'bonus', 'book', 'boost', 'border',
    'boring', 'borrow', 'boss', 'bottom', 'bounce', 'box', 'boy', 'bracket',
    'brain', 'brand', 'brass', 'brave', 'bread', 'breeze', 'brick', 'bridge',
    'brief', 'bright', 'bring', 'brisk', 'broccoli', 'broken', 'bronze', 'broom',
    'brother', 'brown', 'brush', 'bubble', 'buddy', 'budget', 'buffalo', 'build',
    'bulb', 'bulk', 'bullet', 'bundle', 'bunker', 'burden', 'burger', 'burst',
    'bus', 'business', 'busy', 'butter', 'buyer', 'buzz', 'cabbage', 'cabin',
    'cable', 'cactus', 'cage', 'cake', 'call', 'calm', 'camera', 'camp',
    'canal', 'cancel', 'candy', 'cannon', 'canoe', 'canvas', 'canyon', 'capable',
    'capital', 'captain', 'car', 'carbon', 'card', 'cargo', 'carpet', 'carry',
    'cart', 'case', 'cash', 'casino', 'castle', 'casual', 'cat', 'catalog',
    'catch', 'category', 'cattle', 'cause', 'caution', 'cave', 'ceiling', 'celery',
    'cement', 'census', 'century', 'cereal', 'certain', 'chair', 'chalk', 'champion',
    'change', 'chaos', 'chapter', 'charge', 'chase', 'chat', 'cheap', 'check',
    'cheese', 'chef', 'cherry', 'chest', 'chicken', 'chief', 'child', 'chimney',
    'choice', 'choose', 'chronic', 'chuckle', 'chunk', 'churn', 'cigar', 'cinnamon',
    'circle', 'citizen', 'city', 'civil', 'claim', 'clap', 'clarify', 'claw',
    'clay', 'clean', 'clerk', 'clever', 'click', 'client', 'cliff', 'climb',
    'clinic', 'clip', 'clock', 'clog', 'close', 'cloth', 'cloud', 'clown',
    'club', 'clump', 'cluster', 'clutch', 'coach', 'coast', 'coconut', 'code',
    'coffee', 'coil', 'coin', 'collect', 'color', 'column', 'combine', 'come',
    'comfort', 'comic', 'common', 'company', 'concert', 'conduct', 'confirm', 'congress',
    'connect', 'consider', 'control', 'convince', 'cook', 'cool', 'copper', 'copy',
    'coral', 'core', 'corn', 'correct', 'cost', 'cotton', 'couch', 'country',
    'couple', 'course', 'cousin', 'cover', 'coyote', 'crack', 'cradle', 'craft',
    'cram', 'crane', 'crash', 'crater', 'crawl', 'crazy', 'cream', 'credit',
    'creek', 'crew', 'cricket', 'crime', 'crisp', 'critic', 'crop', 'cross',
    'crouch', 'crowd', 'crucial', 'cruel', 'cruise', 'crumble', 'crunch', 'crush',
    'cry', 'crystal', 'cube', 'culture', 'cup', 'curious', 'curly', 'current',
    'curtain', 'curve', 'cushion', 'custom', 'cute', 'cycle', 'dad', 'damage',
    'damp', 'dance', 'danger', 'daring', 'dash', 'daughter', 'dawn', 'day',
    'deal', 'debate', 'debris', 'decade', 'december', 'decide', 'decline', 'decorate',
    'decrease', 'deer', 'defense', 'define', 'defy', 'degree', 'delay', 'deliver',
    'demand', 'demise', 'denial', 'dentist', 'deny', 'depart', 'depend', 'deposit',
    'depth', 'deputy', 'derive', 'describe', 'desert', 'design', 'desk', 'despair',
    'destroy', 'detail', 'detect', 'develop', 'device', 'devote', 'diagram', 'dial',
    'diamond', 'diary', 'dice', 'diesel', 'diet', 'differ', 'digital', 'dignity',
    'dilemma', 'dinner', 'dinosaur', 'direct', 'dirt', 'disagree', 'discover', 'disease',
    'dish', 'dismiss', 'disorder', 'display', 'distance', 'divert', 'divide', 'divorce',
    'dizzy', 'doctor', 'document', 'dog', 'doll', 'dolphin', 'domain', 'donate',
    'donkey', 'donor', 'door', 'dose', 'double', 'dove', 'draft', 'dragon',
    'drain', 'drama', 'drastic', 'draw', 'dream', 'dress', 'drift', 'drill',
    'drink', 'drip', 'drive', 'drop', 'drum', 'dry', 'duck', 'dumb',
    'dune', 'during', 'dust', 'dutch', 'duty', 'dwarf', 'dynamic', 'eager',
    'eagle', 'early', 'earn', 'earth', 'easily', 'east', 'easy', 'echo',
    'ecology', 'economy', 'edge', 'edit', 'educate', 'effort', 'egg', 'eight',
    'either', 'elbow', 'elder', 'electric', 'elegant', 'element', 'elephant', 'elevator',
    'elite', 'embark', 'embody', 'embrace', 'emerge', 'emotion', 'employ', 'empower',
    'empty', 'enable', 'enact', 'end', 'endless', 'endorse', 'enemy', 'energy',
    'enforce', 'engage', 'engine', 'enhance', 'enjoy', 'enlist', 'enough', 'enrich',
    'enroll', 'ensure', 'enter', 'entire', 'entry', 'envelope', 'episode', 'equal',
    'equip', 'era', 'erase', 'erode', 'erosion', 'error', 'erupt', 'escape',
    'essay', 'essence', 'estate', 'eternal', 'ethics', 'evidence', 'evil', 'evoke',
    'evolve', 'exact', 'example', 'excess', 'exchange', 'excite', 'exclude', 'excuse',
    'execute', 'exercise', 'exhaust', 'exhibit', 'exile', 'exist', 'exit', 'exotic',
    'expand', 'expect', 'expire', 'explain', 'expose', 'express', 'extend', 'extra',
    'eye', 'eyebrow', 'fabric', 'face', 'faculty', 'fade', 'faint', 'faith',
    'fall', 'false', 'fame', 'family', 'famous', 'fan', 'fancy', 'fantasy',
    'farm', 'fashion', 'fat', 'fatal', 'father', 'fatigue', 'fault', 'favorite',
    'feature', 'february', 'federal', 'fee', 'feed', 'feel', 'female', 'fence',
    'festival', 'fetch', 'fever', 'few', 'fiber', 'fiction', 'field', 'figure',
    'file', 'film', 'filter', 'final', 'find', 'fine', 'finger', 'finish',
    'fire', 'firm', 'first', 'fiscal', 'fish', 'fit', 'fitness', 'fix',
    'flag', 'flame', 'flash', 'flat', 'flavor', 'flee', 'flight', 'flip',
    'float', 'flock', 'floor', 'flower', 'fluid', 'flush', 'fly', 'foam',
    'focus', 'fog', 'foil', 'fold', 'follow', 'food', 'foot', 'force',
    'forest', 'forget', 'fork', 'fortune', 'forum', 'forward', 'fossil', 'foster',
    'found', 'fox', 'fragile', 'frame', 'frequent', 'fresh', 'friend', 'fringe',
    'frog', 'front', 'frost', 'frown', 'frozen', 'fruit', 'fuel', 'fun',
    'funny', 'furnace', 'fury', 'future', 'gadget', 'gain', 'galaxy', 'gallery',
    'game', 'gap', 'garage', 'garbage', 'garden', 'garlic', 'garment', 'gas',
    'gasp', 'gate', 'gather', 'gauge', 'gaze', 'general', 'genius', 'genre',
    'gentle', 'genuine', 'gesture', 'ghost', 'giant', 'gift', 'giggle', 'ginger',
    'giraffe', 'girl', 'give', 'glad', 'glance', 'glare', 'glass', 'glide',
    'glimpse', 'globe', 'gloom', 'glory', 'glove', 'glow', 'glue', 'goat',
    'goddess', 'gold', 'good', 'goose', 'gorilla', 'gospel', 'gossip', 'govern',
    'gown', 'grab', 'grace', 'grain', 'grant', 'grape', 'grass', 'gravity',
    'great', 'green', 'grid', 'grief', 'grit', 'grocery', 'group', 'grow',
    'grunt', 'guard', 'guess', 'guide', 'guilt', 'guitar', 'gun', 'gym',
    'habit', 'hair', 'half', 'hammer', 'hamster', 'hand', 'happy', 'harbor',
    'hard', 'harsh', 'harvest', 'hat', 'have', 'hawk', 'hazard', 'head',
    'health', 'heart', 'heavy', 'hedgehog', 'height', 'hello', 'helmet', 'help',
    'hen', 'hero', 'hidden', 'high', 'hill', 'hint', 'hip', 'hire',
    'history', 'hobby', 'hockey', 'hold', 'hole', 'holiday', 'hollow', 'home',
    'honey', 'hood', 'hope', 'horn', 'horror', 'horse', 'hospital', 'host',
    'hotel', 'hour', 'hover', 'hub', 'huge', 'human', 'humble', 'humor',
    'hundred', 'hungry', 'hunt', 'hurdle', 'hurry', 'hurt', 'husband', 'hybrid',
    'ice', 'icon', 'idea', 'identify', 'idle', 'ignore', 'illness', 'image',
    'imitate', 'immense', 'immune', 'impact', 'impose', 'improve', 'impulse', 'inch',
    'include', 'income', 'increase', 'index', 'indicate', 'indoor', 'industry', 'infant',
    'inflict', 'inform', 'initial', 'inject', 'injury', 'inmate', 'inner', 'innocent',
    'input', 'inquiry', 'insane', 'insect', 'inside', 'inspire', 'install', 'intact',
    'interest', 'into', 'invest', 'invite', 'involve', 'iron', 'island', 'isolate',
    'issue', 'item', 'ivory', 'jacket', 'jaguar', 'jar', 'jazz', 'jealous',
    'jeans', 'jelly', 'jewel', 'job', 'join', 'joke', 'journey', 'joy',
    'judge', 'juice', 'jump', 'jungle', 'junior', 'junk', 'just', 'kangaroo',
    'keen', 'keep', 'ketchup', 'key', 'kick', 'kid', 'kidney', 'kind',
    'kingdom', 'kiss', 'kit', 'kitchen', 'kite', 'kitten', 'kiwi', 'knee',
    'knife', 'knock', 'know', 'lab', 'label', 'labor', 'ladder', 'lady',
    'lake', 'lamp', 'language', 'laptop', 'large', 'later', 'latin', 'laugh',
    'laundry', 'lava', 'law', 'lawn', 'lawsuit', 'layer', 'lazy', 'leader',
    'leaf', 'learn', 'leave', 'lecture', 'left', 'leg', 'legal', 'legend',
    'leisure', 'lemon', 'lend', 'length', 'lens', 'leopard', 'lesson', 'letter',
    'level', 'liar', 'liberty', 'library', 'license', 'life', 'lift', 'light',
    'like', 'limb', 'limit', 'link', 'lion', 'liquid', 'list', 'little',
    'live', 'lizard', 'load', 'loan', 'lobster', 'local', 'lock', 'logic',
    'lonely', 'long', 'loop', 'lottery', 'loud', 'lounge', 'love', 'loyal',
    'lucky', 'luggage', 'lumber', 'lunar', 'lunch', 'luxury', 'lyrics', 'machine',
    'mad', 'magic', 'magnet', 'maid', 'mail', 'main', 'major', 'make',
    'mammal', 'man', 'manage', 'mandate', 'mango', 'mansion', 'manual', 'maple',
    'marble', 'march', 'margin', 'marine', 'market', 'marriage', 'mask', 'mass',
    'master', 'match', 'material', 'math', 'matrix', 'matter', 'maximum', 'maze',
    'meadow', 'mean', 'measure', 'meat', 'mechanic', 'medal', 'media', 'melody',
    'melt', 'member', 'memory', 'mention', 'menu', 'mercy', 'merge', 'merit',
    'merry', 'mesh', 'message', 'metal', 'method', 'middle', 'midnight', 'milk',
    'million', 'mimic', 'mind', 'minimum', 'minor', 'minute', 'miracle', 'mirror',
    'misery', 'miss', 'mistake', 'mix', 'mixed', 'mixture', 'mobile', 'model',
    'modify', 'mom', 'moment', 'monitor', 'monkey', 'monster', 'month', 'moon',
    'moral', 'more', 'morning', 'mosquito', 'mother', 'motion', 'motor', 'mountain',
    'mouse', 'move', 'movie', 'much', 'muffin', 'mule', 'multiply', 'muscle',
    'museum', 'mushroom', 'music', 'must', 'mutual', 'myself', 'mystery', 'myth',
    'naive', 'name', 'napkin', 'narrow', 'nasty', 'nation', 'nature', 'near',
    'neck', 'need', 'negative', 'neglect', 'neither', 'nephew', 'nerve', 'nest',
    'net', 'network', 'neutral', 'never', 'news', 'next', 'nice', 'night',
    'noble', 'noise', 'nominee', 'noodle', 'normal', 'north', 'nose', 'notable',
    'note', 'nothing', 'notice', 'novel', 'now', 'nuclear', 'number', 'nurse',
    'nut', 'oak', 'obey', 'object', 'oblige', 'obscure', 'observe', 'obtain',
    'obvious', 'occur', 'ocean', 'october', 'odor', 'off', 'offer', 'office',
    'often', 'oil', 'okay', 'old', 'olive', 'olympic', 'omit', 'once',
    'one', 'onion', 'online', 'only', 'open', 'opera', 'opinion', 'oppose',
    'option', 'orange', 'orbit', 'orchard', 'order', 'ordinary', 'organ', 'orient',
    'original', 'orphan', 'ostrich', 'other', 'outdoor', 'outer', 'output', 'outside',
    'oval', 'oven', 'over', 'own', 'owner', 'oxygen', 'oyster', 'ozone',
    'pact', 'paddle', 'page', 'pair', 'palace', 'palm', 'panda', 'panel',
    'panic', 'panther', 'paper', 'parade', 'parent', 'park', 'parrot', 'party',
    'pass', 'patch', 'path', 'patient', 'patrol', 'pattern', 'pause', 'pave',
    'payment', 'peace', 'peanut', 'pear', 'peasant', 'pelican', 'pen', 'penalty',
    'pencil', 'people', 'pepper', 'perfect', 'permit', 'person', 'pet', 'phone',
    'photo', 'phrase', 'physical', 'piano', 'picnic', 'picture', 'piece', 'pig',
    'pigeon', 'pill', 'pilot', 'pin', 'pine', 'pipe', 'pistol', 'pitch',
    'pizza', 'place', 'planet', 'plastic', 'plate', 'play', 'please', 'pledge',
    'pluck', 'plug', 'plunge', 'poem', 'poet', 'point', 'polar', 'pole',
    'police', 'pond', 'pony', 'pool', 'popular', 'portion', 'position', 'possible',
    'post', 'potato', 'pottery', 'poverty', 'powder', 'power', 'practice', 'praise',
    'predict', 'prefer', 'prepare', 'present', 'pretty', 'prevent', 'price', 'pride',
    'primary', 'print', 'priority', 'prison', 'private', 'prize', 'problem', 'process',
    'produce', 'profit', 'program', 'project', 'promote', 'proof', 'property', 'prosper',
    'protect', 'proud', 'provide', 'public', 'pudding', 'pull', 'pulp', 'pulse',
    'pumpkin', 'punch', 'pupil', 'puppy', 'purchase', 'purity', 'purpose', 'purse',
    'push', 'put', 'puzzle', 'pyramid', 'quality', 'quantum', 'quarter', 'question',
    'quick', 'quit', 'quiz', 'quote', 'rabbit', 'raccoon', 'race', 'rack',
    'radar', 'radio', 'rail', 'rain', 'raise', 'rally', 'ramp', 'ranch',
    'random', 'range', 'rapid', 'rare', 'rate', 'rather', 'raven', 'raw',
    'razor', 'ready', 'real', 'reason', 'rebel', 'rebuild', 'recall', 'receive',
    'recipe', 'record', 'recycle', 'reduce', 'reflect', 'reform', 'refuse', 'region',
    'regret', 'regular', 'reject', 'relax', 'release', 'relief', 'rely', 'remain',
    'remember', 'remind', 'remove', 'render', 'renew', 'rent', 'reopen', 'repair',
    'repeat', 'replace', 'report', 'require', 'rescue', 'resemble', 'resist', 'resource',
    'response', 'result', 'retire', 'retreat', 'return', 'reunion', 'reveal', 'review',
    'reward', 'rhythm', 'rib', 'ribbon', 'rice', 'rich', 'ride', 'ridge',
    'rifle', 'right', 'rigid', 'ring', 'riot', 'ripple', 'risk', 'ritual',
    'rival', 'river', 'road', 'roast', 'robot', 'robust', 'rocket', 'romance',
    'roof', 'rookie', 'room', 'rose', 'rotate', 'rough', 'round', 'route',
    'royal', 'rubber', 'rude', 'rug', 'rule', 'run', 'runway', 'rural',
    'sad', 'saddle', 'sadness', 'safe', 'sail', 'salad', 'salmon', 'salon',
    'salt', 'salute', 'same', 'sample', 'sand', 'satisfy', 'satoshi', 'sauce',
    'sausage', 'save', 'say', 'scale', 'scan', 'scare', 'scatter', 'scene',
    'scheme', 'school', 'science', 'scissors', 'scooter', 'scope', 'score', 'scramble',
    'scream', 'screen', 'script', 'scrub', 'sea', 'search', 'season', 'seat',
    'second', 'secret', 'section', 'security', 'seed', 'seek', 'segment', 'select',
    'sell', 'seminar', 'senior', 'sense', 'sentence', 'series', 'service', 'session',
    'settle', 'setup', 'seven', 'shadow', 'shaft', 'shallow', 'share', 'shed',
    'shell', 'sheriff', 'shield', 'shift', 'shine', 'ship', 'shiver', 'shock',
    'shoe', 'shoot', 'shop', 'short', 'shoulder', 'shove', 'shrimp', 'shrug',
    'shuffle', 'shy', 'sibling', 'sick', 'side', 'siege', 'sight', 'sign',
    'silent', 'silk', 'silly', 'silver', 'similar', 'simple', 'since', 'sing',
    'siren', 'sister', 'situate', 'six', 'size', 'skate', 'sketch', 'ski',
    'skill', 'skin', 'skirt', 'skull', 'slab', 'slam', 'sleep', 'slender',
    'slice', 'slide', 'slight', 'slim', 'slogan', 'slot', 'slow', 'slush',
    'small', 'smart', 'smile', 'smoke', 'smooth', 'snack', 'snake', 'snap',
    'sniff', 'snow', 'soap', 'soccer', 'social', 'sock', 'soda', 'soft',
    'solar', 'soldier', 'solid', 'solution', 'solve', 'someone', 'song', 'soon',
    'sorry', 'sort', 'soul', 'sound', 'soup', 'source', 'south', 'space',
    'spare', 'spatial', 'spawn', 'speak', 'special', 'speed', 'spell', 'spend',
    'sphere', 'spice', 'spider', 'spike', 'spin', 'spirit', 'split', 'spoil',
    'sponsor', 'spoon', 'sport', 'spot', 'spray', 'spread', 'spring', 'spy',
    'square', 'squeeze', 'squirrel', 'stable', 'stadium', 'staff', 'stage', 'stair',
    'stamp', 'stand', 'start', 'state', 'stay', 'steak', 'steel', 'stem',
    'step', 'stereo', 'stick', 'still', 'sting', 'stock', 'stomach', 'stone',
    'stool', 'story', 'stove', 'strategy', 'street', 'strike', 'strong', 'struggle',
    'student', 'stuff', 'stumble', 'style', 'subject', 'submit', 'subway', 'success',
    'such', 'sudden', 'suffer', 'sugar', 'suggest', 'suit', 'summer', 'sun',
    'sunny', 'sunset', 'super', 'supply', 'supreme', 'sure', 'surface', 'surge',
    'surprise', 'surround', 'survey', 'suspect', 'sustain', 'swallow', 'swamp', 'swap',
    'swarm', 'swear', 'sweet', 'swift', 'swim', 'swing', 'switch', 'sword',
    'symbol', 'symptom', 'syrup', 'system', 'table', 'tackle', 'tag', 'tail',
    'talent', 'talk', 'tank', 'tape', 'target', 'task', 'taste', 'tattoo',
    'taxi', 'teach', 'team', 'tell', 'ten', 'tenant', 'tennis', 'tent',
    'term', 'test', 'text', 'thank', 'that', 'theme', 'then', 'theory',
    'there', 'they', 'thing', 'this', 'thought', 'three', 'thrive', 'throw',
    'thumb', 'thunder', 'ticket', 'tide', 'tiger', 'tilt', 'timber', 'time',
    'tiny', 'tip', 'tired', 'tissue', 'title', 'toast', 'tobacco', 'today',
    'toddler', 'toe', 'together', 'toilet', 'token', 'tomato', 'tomorrow', 'tone',
    'tongue', 'tonight', 'tool', 'tooth', 'top', 'topic', 'topple', 'torch',
    'tornado', 'tortoise', 'toss', 'total', 'tourist', 'toward', 'tower', 'town',
    'toy', 'track', 'trade', 'traffic', 'tragic', 'train', 'transfer', 'trap',
    'trash', 'travel', 'tray', 'treat', 'tree', 'trend', 'trial', 'tribe',
    'trick', 'trigger', 'trim', 'trip', 'trophy', 'trouble', 'truck', 'true',
    'truly', 'trumpet', 'trust', 'truth', 'try', 'tube', 'tuition', 'tumble',
    'tuna', 'tunnel', 'turkey', 'turn', 'turtle', 'twelve', 'twenty', 'twice',
    'twin', 'twist', 'two', 'type', 'typical', 'ugly', 'umbrella', 'unable',
    'unaware', 'uncle', 'uncover', 'under', 'undo', 'unfair', 'unfold', 'unhappy',
    'uniform', 'unique', 'unit', 'universe', 'unknown', 'unlock', 'until', 'unusual',
    'unveil', 'update', 'upgrade', 'uphold', 'upon', 'upper', 'upset', 'urban',
    'urge', 'usage', 'use', 'used', 'useful', 'useless', 'usual', 'utility',
    'vacant', 'vacuum', 'vague', 'valid', 'valley', 'valve', 'van', 'vanish',
    'vapor', 'various', 'vast', 'vault', 'vehicle', 'velvet', 'vendor', 'venture',
    'venue', 'verb', 'verify', 'version', 'very', 'vessel', 'veteran', 'viable',
    'vibrant', 'vicious', 'victory', 'video', 'view', 'village', 'vintage', 'violin',
    'virtual', 'virus', 'visa', 'visit', 'visual', 'vital', 'vivid', 'vocal',
    'voice', 'void', 'volcano', 'volume', 'vote', 'voyage', 'wage', 'wagon',
    'wait', 'walk', 'wall', 'walnut', 'want', 'warfare', 'warm', 'warrior',
    'wash', 'wasp', 'waste', 'water', 'wave', 'way', 'wealth', 'weapon',
    'wear', 'weasel', 'weather', 'web', 'wedding', 'week', 'weird', 'welcome',
    'west', 'wet', 'whale', 'what', 'wheat', 'wheel', 'when', 'where',
    'whip', 'whisper', 'wide', 'width', 'wife', 'wild', 'will', 'win',
    'window', 'wine', 'wing', 'wink', 'winner', 'winter', 'wire', 'wisdom',
    'wise', 'wish', 'witness', 'wolf', 'woman', 'wonder', 'wood', 'wool',
    'word', 'work', 'world', 'worry', 'worth', 'wrap', 'wreck', 'wrestle',
    'wrist', 'write', 'wrong', 'yard', 'year', 'yellow', 'you', 'young',
    'youth', 'zebra', 'zero', 'zone', 'zoo'
  ];

  function getSecureRandomInt(max) {
    const array = new Uint32Array(1);
    crypto.getRandomValues(array);
    return array[0] % max;
  }

  function generatePasswordString(length, pool, requiredSets) {
    if (pool.length === 0) return '';
    const chars = [];

    // Ensure at least one character from each required set
    for (const set of requiredSets) {
      if (set.length > 0) {
        chars.push(set[getSecureRandomInt(set.length)]);
      }
    }

    const randomIndices = new Uint32Array(length);
    crypto.getRandomValues(randomIndices);
    while (chars.length < length) {
      chars.push(pool[randomIndices[chars.length] % pool.length]);
    }

    // Fisher-Yates shuffle
    for (let i = chars.length - 1; i > 0; i--) {
      const j = getSecureRandomInt(i + 1);
      const tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }

    return chars.join('');
  }

  function generatePassphraseString(wordCount, separator, capitalize, addNumber) {
    const chosenWords = [];
    for (let i = 0; i < wordCount; i++) {
      let word = EFF_WORDLIST[getSecureRandomInt(EFF_WORDLIST.length)];
      if (capitalize) {
        word = word.charAt(0).toUpperCase() + word.slice(1);
      }
      chosenWords.push(word);
    }

    if (addNumber) {
      const randNum = 10 + getSecureRandomInt(90);
      const targetWordIdx = getSecureRandomInt(chosenWords.length);
      chosenWords[targetWordIdx] = `${chosenWords[targetWordIdx]}${randNum}`;
    }

    return chosenWords.join(separator);
  }

  function updateEntropyMeter(entropyBits) {
    entSeg1.className = 'segment';
    entSeg2.className = 'segment';
    entSeg3.className = 'segment';
    entSeg4.className = 'segment';

    if (entropyBits < 45) {
      entSeg1.classList.add('weak');
      entropyScoreLabel.innerText = `Weak • ${entropyBits.toFixed(1)} bits`;
      entropyCrackLabel.innerText = 'Crackable in minutes';
    } else if (entropyBits < 65) {
      entSeg1.classList.add('fair');
      entSeg2.classList.add('fair');
      entropyScoreLabel.innerText = `Fair • ${entropyBits.toFixed(1)} bits`;
      entropyCrackLabel.innerText = 'Few weeks to crack';
    } else if (entropyBits < 90) {
      entSeg1.classList.add('strong');
      entSeg2.classList.add('strong');
      entSeg3.classList.add('strong');
      entropyScoreLabel.innerText = `Strong • ${entropyBits.toFixed(1)} bits`;
      entropyCrackLabel.innerText = 'Centuries to crack';
    } else {
      entSeg1.classList.add('very-strong');
      entSeg2.classList.add('very-strong');
      entSeg3.classList.add('very-strong');
      entSeg4.classList.add('very-strong');
      entropyScoreLabel.innerText = `Very Strong • ${entropyBits.toFixed(1)} bits`;
      entropyCrackLabel.innerText = 'Billions of years to crack';
    }
  }

  function generateSecret() {
    if (generatorMode === 'password') {
      const length = parseInt(lengthSlider.value, 10);
      lengthValueDisplay.innerText = length.toString();

      let pool = '';
      const requiredSets = [];

      const upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      const lower = 'abcdefghijklmnopqrstuvwxyz';
      const numbers = '0123456789';
      const symbols = '!@#$%^&*()_+-=[]{}|;:,.<>?';

      if (chkUpper.checked) {
        pool += upper;
        requiredSets.push(upper);
      }
      if (chkLower.checked) {
        pool += lower;
        requiredSets.push(lower);
      }
      if (chkNumbers.checked) {
        pool += numbers;
        requiredSets.push(numbers);
      }
      if (chkSymbols.checked) {
        pool += symbols;
        requiredSets.push(symbols);
      }

      if (chkAmbiguous.checked) {
        const ambiguous = /[0Ol1I]/g;
        pool = pool.replace(ambiguous, '');
        for (let i = 0; i < requiredSets.length; i++) {
          requiredSets[i] = requiredSets[i].replace(ambiguous, '');
        }
      }

      if (pool.length === 0) {
        generatedSecretText.innerText = '(Select character set)';
        updateEntropyMeter(0);
        return;
      }

      const password = generatePasswordString(length, pool, requiredSets);
      generatedSecretText.innerText = password;

      const entropy = length * (Math.log(pool.length) / Math.LN2);
      updateEntropyMeter(entropy);
    } else {
      const wordCount = parseInt(wordCountSlider.value, 10);
      wordCountValueDisplay.innerText = wordCount.toString();
      const separator = separatorSelect.value;
      const capitalize = chkCapitalize.checked;
      const addNumber = chkAddNumber.checked;

      const passphrase = generatePassphraseString(
        wordCount,
        separator,
        capitalize,
        addNumber
      );
      generatedSecretText.innerText = passphrase;

      let entropy = wordCount * (Math.log(EFF_WORDLIST.length) / Math.LN2);
      if (addNumber) entropy += Math.log2(90);
      updateEntropyMeter(entropy);
    }
  }

  // Mode Selection Listeners
  modeBtnPassword.addEventListener('click', () => {
    generatorMode = 'password';
    modeBtnPassword.classList.add('active');
    modeBtnPassphrase.classList.remove('active');
    passwordControls.classList.remove('hidden');
    passphraseControls.classList.add('hidden');
    generateSecret();
  });

  modeBtnPassphrase.addEventListener('click', () => {
    generatorMode = 'passphrase';
    modeBtnPassphrase.classList.add('active');
    modeBtnPassword.classList.remove('active');
    passphraseControls.classList.remove('hidden');
    passwordControls.classList.add('hidden');
    generateSecret();
  });

  // Generator Input Listeners
  lengthSlider.addEventListener('input', generateSecret);
  chkUpper.addEventListener('change', generateSecret);
  chkLower.addEventListener('change', generateSecret);
  chkNumbers.addEventListener('change', generateSecret);
  chkSymbols.addEventListener('change', generateSecret);
  chkAmbiguous.addEventListener('change', generateSecret);

  wordCountSlider.addEventListener('input', generateSecret);
  separatorSelect.addEventListener('change', generateSecret);
  chkCapitalize.addEventListener('change', generateSecret);
  chkAddNumber.addEventListener('change', generateSecret);

  regenSecretBtn.addEventListener('click', generateSecret);
  generatedSecretText.addEventListener('click', () => {
    copyText(generatedSecretText.innerText, copySecretBtn, '📋');
  });

  copySecretBtn.addEventListener('click', () => {
    copyText(generatedSecretText.innerText, copySecretBtn, '📋');
  });

  fillSecretBtn.addEventListener('click', async () => {
    const secret = generatedSecretText.innerText;
    if (!secret || !currentTab || !currentTab.id) return;

    try {
      await chrome.tabs.sendMessage(currentTab.id, {
        action: 'FILL_GENERATED_PASSWORD',
        password: secret,
      });
      window.close();
    } catch (err) {
      console.warn('MultiPad: fill generated password failed', err);
    }
  });

  // Initial Startup
  await checkState();
  generateSecret();
});
