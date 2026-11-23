// MultiPad Extension Popup Generator Adversarial Challenge Suite
// Challenger: m2_challenger_2
// MultiPad v1.4.0 — Feature 11 (Extension Popup Generator)

const { JSDOM } = require('/tmp/dom_test/node_modules/jsdom');
const fs = require('fs');
const path = require('path');

const popupHtml = fs.readFileSync(path.resolve(__dirname, '../extension/popup.html'), 'utf8');
const popupJsCode = fs.readFileSync(path.resolve(__dirname, '../extension/popup.js'), 'utf8');

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;

function assert(condition, message) {
  totalTests++;
  if (!condition) {
    console.error(`❌ FAIL: ${message}`);
    failedTests++;
  } else {
    console.log(`✅ PASS: ${message}`);
    passedTests++;
  }
}

console.log('===============================================================');
console.log('CHALLENGER 2: EMPIRICAL STRESS-TEST OF POPUP GENERATOR (FEATURE 11)');
console.log('===============================================================\n');

const dom = new JSDOM(popupHtml, {
  url: 'chrome-extension://multipad-id/popup.html',
  runScripts: 'outside-only',
  pretendToBeVisual: true,
});

const { window } = dom;
const { document } = window;

// Cryptographically secure mock using Node.js crypto
const nodeCrypto = require('crypto');
window.crypto = {
  getRandomValues: (buffer) => {
    const bytes = nodeCrypto.randomBytes(buffer.byteLength);
    const typed = new Uint8Array(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    typed.set(bytes);
    return buffer;
  },
};

window.navigator.clipboard = {
  writeText: async (t) => true,
};

window.chrome = {
  tabs: {
    query: async () => [{ id: 99, url: 'https://vault.test.com' }],
    sendMessage: async (id, msg) => ({ success: true }),
  },
  runtime: {
    sendMessage: (msg, cb) => cb({ success: true, status: 'unlocked' }),
    lastError: null,
  },
};

// Execute script
window.eval(popupJsCode);
document.dispatchEvent(new window.Event('DOMContentLoaded'));

setTimeout(() => {
  try {
    // Switch to generator tab
    document.getElementById('tabBtnGenerator').click();

    const lengthSlider = document.getElementById('lengthSlider');
    const chkUpper = document.getElementById('chkUpper');
    const chkLower = document.getElementById('chkLower');
    const chkNumbers = document.getElementById('chkNumbers');
    const chkSymbols = document.getElementById('chkSymbols');
    const chkAmbiguous = document.getElementById('chkAmbiguous');
    const generatedSecretText = document.getElementById('generatedSecretText');
    const entropyScoreLabel = document.getElementById('entropyScoreLabel');
    const entropyCrackLabel = document.getElementById('entropyCrackLabel');
    const entSeg1 = document.getElementById('entSeg1');
    const entSeg2 = document.getElementById('entSeg2');
    const entSeg3 = document.getElementById('entSeg3');
    const entSeg4 = document.getElementById('entSeg4');
    const regenSecretBtn = document.getElementById('regenSecretBtn');

    // -------------------------------------------------------------------------
    // TEST SUITE 1: Ambiguous Character Filtering
    // -------------------------------------------------------------------------
    console.log('--- TEST SUITE 1: Ambiguous Character Filtering ([0Ol1I]) ---');

    chkUpper.checked = true;
    chkLower.checked = true;
    chkNumbers.checked = true;
    chkSymbols.checked = true;
    chkAmbiguous.checked = true;

    const ambiguousRegex = /[0Ol1I]/;
    let ambiguousFound = 0;
    const sampleSize = 500;

    for (let i = 0; i < sampleSize; i++) {
      // Vary length from 8 to 64
      const testLen = 8 + (i % 57);
      lengthSlider.value = testLen;
      lengthSlider.dispatchEvent(new window.Event('input'));

      const pwd = generatedSecretText.innerText;
      if (pwd.length !== testLen) {
        assert(false, `Expected password length ${testLen}, got ${pwd.length}`);
      }
      if (ambiguousRegex.test(pwd)) {
        ambiguousFound++;
      }
    }

    assert(
      ambiguousFound === 0,
      `0 of ${sampleSize} generated passwords contained ambiguous characters with filter ON`
    );

    // Verify when ambiguous filter is OFF, ambiguous characters CAN appear
    chkAmbiguous.checked = false;
    let ambiguousCountOff = 0;
    for (let i = 0; i < 200; i++) {
      lengthSlider.value = 32;
      lengthSlider.dispatchEvent(new window.Event('input'));
      if (ambiguousRegex.test(generatedSecretText.innerText)) {
        ambiguousCountOff++;
      }
    }
    assert(
      ambiguousCountOff > 0,
      `Ambiguous characters naturally appear when filter is OFF (${ambiguousCountOff}/200 sampled)`
    );

    // -------------------------------------------------------------------------
    // TEST SUITE 2: Entropy Calculations Across Lengths and Pools
    // -------------------------------------------------------------------------
    console.log('\n--- TEST SUITE 2: Entropy Calculations Across Character Sets and Lengths ---');

    // 1. Lowercase only (pool: 26)
    chkUpper.checked = false;
    chkLower.checked = true;
    chkNumbers.checked = false;
    chkSymbols.checked = false;
    chkAmbiguous.checked = false;

    lengthSlider.value = 8; // 8 * log2(26) = 8 * 4.7004 = 37.60 bits -> Weak
    lengthSlider.dispatchEvent(new window.Event('input'));
    let scoreText = entropyScoreLabel.innerText;
    assert(scoreText.includes('Weak') && scoreText.includes('37.6 bits'), `Lowercase 8 chars: ${scoreText}`);
    assert(entSeg1.classList.contains('weak') && !entSeg2.classList.contains('fair'), 'Weak has 1 segment');

    lengthSlider.value = 12; // 12 * 4.7004 = 56.41 bits -> Fair
    lengthSlider.dispatchEvent(new window.Event('input'));
    scoreText = entropyScoreLabel.innerText;
    assert(scoreText.includes('Fair') && scoreText.includes('56.4 bits'), `Lowercase 12 chars: ${scoreText}`);
    assert(entSeg2.classList.contains('fair') && !entSeg3.classList.contains('strong'), 'Fair has 2 segments');

    lengthSlider.value = 16; // 16 * 4.7004 = 75.21 bits -> Strong
    lengthSlider.dispatchEvent(new window.Event('input'));
    scoreText = entropyScoreLabel.innerText;
    assert(scoreText.includes('Strong') && scoreText.includes('75.2 bits'), `Lowercase 16 chars: ${scoreText}`);
    assert(entSeg3.classList.contains('strong') && !entSeg4.classList.contains('very-strong'), 'Strong has 3 segments');

    lengthSlider.value = 24; // 24 * 4.7004 = 112.81 bits -> Very Strong
    lengthSlider.dispatchEvent(new window.Event('input'));
    scoreText = entropyScoreLabel.innerText;
    assert(scoreText.includes('Very Strong') && scoreText.includes('112.8 bits'), `Lowercase 24 chars: ${scoreText}`);
    assert(entSeg4.classList.contains('very-strong'), 'Very Strong has 4 segments');

    // 2. All character sets with Ambiguous Excluded: pool = 83
    // pool = 24 (upper) + 25 (lower) + 8 (num) + 26 (sym) = 83
    // log2(83) = 6.375039 bits/char
    chkUpper.checked = true;
    chkLower.checked = true;
    chkNumbers.checked = true;
    chkSymbols.checked = true;
    chkAmbiguous.checked = true;

    lengthSlider.value = 8; // 8 * 6.3750 = 51.0 bits -> Fair
    lengthSlider.dispatchEvent(new window.Event('input'));
    scoreText = entropyScoreLabel.innerText;
    assert(scoreText.includes('Fair') && scoreText.includes('51.0 bits'), `Pool 83, 8 chars: ${scoreText}`);

    lengthSlider.value = 64; // 64 * 6.3750 = 408.0 bits -> Very Strong
    lengthSlider.dispatchEvent(new window.Event('input'));
    scoreText = entropyScoreLabel.innerText;
    assert(scoreText.includes('Very Strong') && scoreText.includes('408.0 bits'), `Pool 83, 64 chars: ${scoreText}`);

    // -------------------------------------------------------------------------
    // TEST SUITE 3: Guaranteed Required Character Sets
    // -------------------------------------------------------------------------
    console.log('\n--- TEST SUITE 3: Guaranteed Required Set Representation ---');

    chkUpper.checked = true;
    chkLower.checked = true;
    chkNumbers.checked = true;
    chkSymbols.checked = true;
    chkAmbiguous.checked = false;

    const upperRegex = /[A-Z]/;
    const lowerRegex = /[a-z]/;
    const numRegex = /[0-9]/;
    const symRegex = /[!@#$%^&*()_+\-=\[\]{}|;:,.<>?]/;

    let allSetsPresent = true;
    for (let i = 0; i < 200; i++) {
      lengthSlider.value = 10;
      lengthSlider.dispatchEvent(new window.Event('input'));
      const pwd = generatedSecretText.innerText;
      if (!upperRegex.test(pwd) || !lowerRegex.test(pwd) || !numRegex.test(pwd) || !symRegex.test(pwd)) {
        allSetsPresent = false;
        console.error(`Missing required set in password: ${pwd}`);
        break;
      }
    }
    assert(allSetsPresent, 'All 200 passwords of length 10 contain Upper, Lower, Number, and Symbol');

    // -------------------------------------------------------------------------
    // TEST SUITE 4: Passphrase Mode Stress-Testing
    // -------------------------------------------------------------------------
    console.log('\n--- TEST SUITE 4: Passphrase Mode Stress-Testing ---');

    const modeBtnPassphrase = document.getElementById('modeBtnPassphrase');
    modeBtnPassphrase.click();

    const wordCountSlider = document.getElementById('wordCountSlider');
    const separatorSelect = document.getElementById('separatorSelect');
    const chkCapitalize = document.getElementById('chkCapitalize');
    const chkAddNumber = document.getElementById('chkAddNumber');

    // Test word count 3 to 10
    const testSeparators = ['-', '_', '.', ' '];
    for (const sep of testSeparators) {
      separatorSelect.value = sep;
      for (let count = 3; count <= 10; count++) {
        wordCountSlider.value = count;
        chkCapitalize.checked = false;
        chkAddNumber.checked = false;
        wordCountSlider.dispatchEvent(new window.Event('input'));

        const phrase = generatedSecretText.innerText;
        const words = phrase.split(sep);
        assert(
          words.length === count,
          `Word count ${count} with separator "${sep}": yielded ${words.length} words`
        );
      }
    }

    // Test Capitalization
    chkCapitalize.checked = true;
    chkAddNumber.checked = false;
    separatorSelect.value = '-';
    wordCountSlider.value = 5;
    wordCountSlider.dispatchEvent(new window.Event('input'));

    const capPhrase = generatedSecretText.innerText;
    const capWords = capPhrase.split('-');
    const allCapitalized = capWords.every((w) => w[0] === w[0].toUpperCase() && w[0] !== w[0].toLowerCase());
    assert(allCapitalized, `All words capitalized when chkCapitalize is ON: "${capPhrase}"`);

    // Test Add Number
    chkAddNumber.checked = true;
    let validNumberAttached = 0;
    const numRegex2 = /\d{2}$/;

    for (let i = 0; i < 100; i++) {
      wordCountSlider.dispatchEvent(new window.Event('input'));
      const p = generatedSecretText.innerText;
      const wList = p.split('-');
      // Exactly one word should have a 2-digit number attached (10 to 99)
      const matches = wList.filter((w) => /\d+/.test(w));
      if (matches.length === 1 && numRegex2.test(matches[0])) {
        const numVal = parseInt(matches[0].match(/\d+/)[0], 10);
        if (numVal >= 10 && numVal <= 99) {
          validNumberAttached++;
        }
      }
    }
    assert(
      validNumberAttached === 100,
      `100 of 100 passphrases have exactly one 2-digit number (10-99) attached`
    );

    // Test Passphrase Entropy calculation
    // EFF wordlist length in popup.js is 2012 words. log2(2012) = 10.9744 bits per word.
    // 5 words: 5 * 10.9744 = 54.87 bits -> Fair
    // With addNumber: + log2(90) = + 6.4919 bits -> 61.36 bits
    wordCountSlider.value = 5;
    chkAddNumber.checked = false;
    wordCountSlider.dispatchEvent(new window.Event('input'));
    scoreText = entropyScoreLabel.innerText;
    assert(scoreText.includes('54.9 bits') && scoreText.includes('Fair'), `Passphrase 5 words without number: ${scoreText}`);

    chkAddNumber.checked = true;
    chkAddNumber.dispatchEvent(new window.Event('change'));
    scoreText = entropyScoreLabel.innerText;
    assert(scoreText.includes('61.4 bits') && scoreText.includes('Fair'), `Passphrase 5 words WITH number (+log2(90)): ${scoreText}`);

    // 10 words with number: 10 * 10.9744 + 6.4919 = 116.2 bits -> Very Strong
    wordCountSlider.value = 10;
    wordCountSlider.dispatchEvent(new window.Event('input'));
    scoreText = entropyScoreLabel.innerText;
    assert(scoreText.includes('Very Strong') && scoreText.includes('116.2 bits'), `Passphrase 10 words: ${scoreText}`);

    // -------------------------------------------------------------------------
    // TEST SUITE 5: Zero Character Pool Edge Case
    // -------------------------------------------------------------------------
    console.log('\n--- TEST SUITE 5: Edge Cases (Empty Pool, Rapid Regeneration) ---');

    document.getElementById('modeBtnPassword').click();
    chkUpper.checked = false;
    chkLower.checked = false;
    chkNumbers.checked = false;
    chkSymbols.checked = false;
    chkUpper.dispatchEvent(new window.Event('change'));

    assert(
      generatedSecretText.innerText === '(Select character set)',
      'Empty pool displays "(Select character set)"'
    );
    assert(
      entSeg1.classList.contains('weak') && !entSeg2.classList.contains('fair'),
      'Empty pool (0 bits) categorizes as Weak with 1 segment (< 45 bits tier)'
    );

    // Rapid regeneration produces distinct passwords
    chkUpper.checked = true;
    chkLower.checked = true;
    chkNumbers.checked = true;
    chkUpper.dispatchEvent(new window.Event('change'));

    const distinctPasswords = new Set();
    for (let i = 0; i < 50; i++) {
      regenSecretBtn.click();
      distinctPasswords.add(generatedSecretText.innerText);
    }
    assert(distinctPasswords.size === 50, `50 rapid regenerations produced 50 unique passwords`);

    console.log('\n===============================================================');
    console.log(`TOTAL TESTS: ${totalTests} | PASSED: ${passedTests} | FAILED: ${failedTests}`);
    if (failedTests === 0) {
      console.log('🎉 ALL CHALLENGER GENERATOR STRESS TESTS PASSED!');
      process.exit(0);
    } else {
      console.error('❌ SOME CHALLENGER GENERATOR STRESS TESTS FAILED!');
      process.exit(1);
    }
  } catch (err) {
    console.error('Unexpected error during challenger test execution:', err);
    process.exit(1);
  }
}, 100);
