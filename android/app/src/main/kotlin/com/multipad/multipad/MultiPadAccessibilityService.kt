package com.multipad.multipad

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast
import java.nio.ByteBuffer
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class MultiPadAccessibilityService : AccessibilityService() {

    companion object {
        var instance: MultiPadAccessibilityService? = null
            private set

        val isRunning: Boolean
            get() = instance != null

        private val URL_BAR_ID_PATTERNS = listOf(
            "url_bar",
            "mozac_browser_toolbar_url_view",
            "mozac_browser_toolbar_edit_url_view",
            "toolbar_url",
            "url_view",
            "omnibox",
            "location_bar",
            "address_bar",
            "url_field",
            "search_box",
            "display_url",
        )
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Active event handling
    }

    override fun onInterrupt() {
        // Required callback
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }

    /**
     * Triggered by Quick Settings Tile to scan the active screen, identify login/2FA fields,
     * and automatically fill username, password, and TOTP.
     */
    fun performQuickFill() {
        val rootNode = rootInActiveWindow
        if (rootNode == null) {
            showToast("MultiPad: Ekran algılanamadı.")
            return
        }

        val pkgName = rootNode.packageName?.toString()?.lowercase(Locale.US) ?: ""
        val detectedDomains = mutableSetOf<String>()
        var extractedUsernameField: AccessibilityNodeInfo? = null
        var extractedPasswordField: AccessibilityNodeInfo? = null
        var extractedOtpField: AccessibilityNodeInfo? = null

        fun traverse(node: AccessibilityNodeInfo?) {
            if (node == null) return

            val viewId = node.viewIdResourceName?.lowercase(Locale.US) ?: ""
            val text = node.text?.toString() ?: ""
            val contentDesc = node.contentDescription?.toString()?.lowercase(Locale.US) ?: ""
            val combined = "$viewId $contentDesc".lowercase(Locale.US)

            // 1. Detect browser URL bar
            if (URL_BAR_ID_PATTERNS.any { viewId.contains(it) } && text.isNotBlank()) {
                val cleanHost = MultiPadAutofillService.DomainExtractor.extractCleanHost(text)
                if (!cleanHost.isNullOrBlank()) {
                    detectedDomains.add(cleanHost)
                }
            }

            // 2. Identify input fields
            if (node.isEditable) {
                val isOtp = combined.contains("otp") ||
                    combined.contains("2fa") ||
                    combined.contains("one_time") ||
                    combined.contains("doğrulama") ||
                    combined.contains("code") ||
                    combined.contains("token")

                if (isOtp) {
                    extractedOtpField = node
                } else if (node.isPassword) {
                    extractedPasswordField = node
                } else if (extractedUsernameField == null) {
                    val isUsernameOrEmail = combined.contains("user") ||
                        combined.contains("email") ||
                        combined.contains("eposta") ||
                        combined.contains("login") ||
                        combined.contains("kullanici") ||
                        combined.contains("phone") ||
                        !node.isPassword

                    if (isUsernameOrEmail) {
                        extractedUsernameField = node
                    }
                }
            }

            for (i in 0 until node.childCount) {
                traverse(node.getChild(i))
            }
        }

        traverse(rootNode)

        val allEntries = AutofillCryptoStore.loadEntries(applicationContext)
        if (allEntries.isEmpty()) {
            showToast("MultiPad: Kayıtlı parola bulunamadı. Lütfen önce MultiPad'e giriş yapın.")
            return
        }

        // Rank entries matching the active app or domain
        val aliasDomains = MultiPadAutofillService.PackageAliasMap.getDomainsForPackage(pkgName)
        val searchDomains = (detectedDomains + aliasDomains).toSet()

        val matchedEntries = allEntries.filter { entry ->
            val host = MultiPadAutofillService.DomainExtractor.extractCleanHost(entry.website) ?: ""
            val titleMatches = entry.title.lowercase(Locale.US).contains(pkgName.substringAfterLast('.'))
            val domainMatches = searchDomains.any { sd ->
                host == sd || host.endsWith(".$sd") || sd.endsWith(".$host")
            }
            domainMatches || titleMatches
        }

        if (matchedEntries.isEmpty()) {
            // No direct match for this app/domain -> launch QuickFill picker
            launchQuickFillPicker(pkgName, detectedDomains.firstOrNull())
            return
        }

        if (matchedEntries.size == 1) {
            val entry = matchedEntries.first()
            injectCredentials(
                entry = entry,
                usernameNode = extractedUsernameField,
                passwordNode = extractedPasswordField,
                otpNode = extractedOtpField,
            )
        } else {
            // Multiple matching accounts -> open picker
            launchQuickFillPicker(pkgName, detectedDomains.firstOrNull())
        }
    }

    private fun injectCredentials(
        entry: AutofillCredentialEntry,
        usernameNode: AccessibilityNodeInfo?,
        passwordNode: AccessibilityNodeInfo?,
        otpNode: AccessibilityNodeInfo?,
    ) {
        var filledAny = false

        if (usernameNode != null && entry.username.isNotEmpty()) {
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, entry.username)
            }
            usernameNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            filledAny = true
        }

        if (passwordNode != null && entry.password.isNotEmpty()) {
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, entry.password)
            }
            passwordNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            filledAny = true
        }

        val totpCode = generateTotp(entry.totpSecret)

        if (otpNode != null && totpCode != null) {
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, totpCode)
            }
            otpNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            filledAny = true
        }

        // Feature: If TOTP is present, ALWAYS copy it to the clipboard as well
        // so if the site requires a 2-step second page, it's already ready to paste!
        if (totpCode != null) {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            val clip = ClipData.newPlainText("2FA Token", totpCode)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                clip.description.extras = Bundle().apply {
                    putBoolean("android.content.extra.IS_SENSITIVE", true)
                }
            }
            clipboard?.setPrimaryClip(clip)

            if (filledAny) {
                showToast("MultiPad: Bilgiler dolduruldu. 2FA Kodu ($totpCode) panoya kopyalandı!")
            } else {
                showToast("MultiPad: 2FA Kodu ($totpCode) panoya kopyalandı!")
            }
        } else if (filledAny) {
            showToast("MultiPad: Giriş bilgileri dolduruldu!")
        }
    }

    private fun launchQuickFillPicker(pkgName: String, domain: String?) {
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_MULTIPAD_ACTION, MainActivity.ACTION_QUICK_SEARCH)
            putExtra("EXTRA_FILTER_PACKAGE", pkgName)
            if (domain != null) putExtra("EXTRA_FILTER_DOMAIN", domain)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    private fun showToast(msg: String) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(applicationContext, msg, Toast.LENGTH_SHORT).show()
        }
    }

    private fun generateTotp(rawSecret: String): String? {
        val trimmed = rawSecret.trim()
        if (trimmed.isEmpty()) return null

        var base32 = trimmed
        var digits = 6
        if (trimmed.lowercase(Locale.US).startsWith("otpauth://")) {
            val uri = Uri.parse(trimmed)
            base32 = uri.getQueryParameter("secret") ?: return null
            digits = uri.getQueryParameter("digits")?.toIntOrNull()?.coerceIn(4, 8) ?: 6
        }

        val cleaned = base32.uppercase(Locale.US).replace(Regex("[^A-Z2-7]"), "")
        if (cleaned.isEmpty()) return null

        return try {
            val keyBytes = decodeBase32(cleaned)
            val counter = System.currentTimeMillis() / 1000L / 30L
            val counterBytes = ByteBuffer.allocate(8).putLong(counter).array()
            val mac = Mac.getInstance("HmacSHA1")
            mac.init(SecretKeySpec(keyBytes, "HmacSHA1"))
            val hash = mac.doFinal(counterBytes)
            val offset = hash[hash.size - 1].toInt() and 0x0f
            val binary =
                ((hash[offset].toInt() and 0x7f) shl 24) or
                    ((hash[offset + 1].toInt() and 0xff) shl 16) or
                    ((hash[offset + 2].toInt() and 0xff) shl 8) or
                    (hash[offset + 3].toInt() and 0xff)

            val modulus = Math.pow(10.0, digits.toDouble()).toInt()
            val otp = binary % modulus
            String.format(Locale.US, "%0${digits}d", otp)
        } catch (_: Exception) {
            null
        }
    }

    private fun decodeBase32(encoded: String): ByteArray {
        val base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var buffer = 0
        var bitsLeft = 0
        val out = mutableListOf<Byte>()

        for (c in encoded) {
            val valIndex = base32Chars.indexOf(c)
            if (valIndex < 0) continue
            buffer = (buffer shl 5) or valIndex
            bitsLeft += 5
            if (bitsLeft >= 8) {
                bitsLeft -= 8
                out.add(((buffer shr bitsLeft) and 0xff).toByte())
            }
        }
        return out.toByteArray()
    }
}
