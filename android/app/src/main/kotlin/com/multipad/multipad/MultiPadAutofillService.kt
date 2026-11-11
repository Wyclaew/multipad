package com.multipad.multipad

import android.app.assist.AssistStructure
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import java.nio.ByteBuffer
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.math.pow

@RequiresApi(Build.VERSION_CODES.O)
class MultiPadAutofillService : AutofillService() {

    private data class ParsedFields(
        val usernameIds: MutableList<AutofillId> = mutableListOf(),
        val passwordIds: MutableList<AutofillId> = mutableListOf(),
        val otpIds: MutableList<AutofillId> = mutableListOf(),
        val webDomains: MutableSet<String> = mutableSetOf(),
    )

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val contexts = request.fillContexts
        if (contexts.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val structure = contexts.last().structure
        val parsed = ParsedFields()
        traverseStructure(structure, parsed)

        if (parsed.usernameIds.isEmpty() &&
            parsed.passwordIds.isEmpty() &&
            parsed.otpIds.isEmpty()
        ) {
            callback.onSuccess(null)
            return
        }

        val allEntries = AutofillCryptoStore.loadEntries(applicationContext)
        if (allEntries.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val pkgName = structure.activityComponent?.packageName?.lowercase(Locale.US) ?: ""
        val ranked = rankEntries(allEntries, parsed.webDomains, pkgName)

        val responseBuilder = FillResponse.Builder()
        var addedDatasets = 0

        for (entry in ranked.take(10)) {
            val totpCode = generateTotpIfPresent(entry.totpSecret)
            val subtitle = buildString {
                if (entry.username.isNotEmpty()) append(entry.username)
                if (totpCode != null) {
                    if (isNotEmpty()) append(" • ")
                    append("2FA: $totpCode")
                }
                if (isEmpty() && entry.website.isNotEmpty()) append(entry.website)
            }.ifEmpty { "MultiPad" }

            val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_2).apply {
                setTextViewText(
                    android.R.id.text1,
                    entry.title.ifEmpty { entry.website.ifEmpty { "MultiPad" } },
                )
                setTextViewText(android.R.id.text2, subtitle)
            }

            val datasetBuilder = Dataset.Builder(presentation)
            var hasValue = false

            if (entry.username.isNotEmpty()) {
                for (id in parsed.usernameIds) {
                    datasetBuilder.setValue(id, AutofillValue.forText(entry.username))
                    hasValue = true
                }
            }
            if (entry.password.isNotEmpty()) {
                for (id in parsed.passwordIds) {
                    datasetBuilder.setValue(id, AutofillValue.forText(entry.password))
                    hasValue = true
                }
            }
            if (totpCode != null) {
                for (id in parsed.otpIds) {
                    datasetBuilder.setValue(id, AutofillValue.forText(totpCode))
                    hasValue = true
                }
            }

            if (hasValue) {
                responseBuilder.addDataset(datasetBuilder.build())
                addedDatasets++
            }
        }

        if (addedDatasets == 0) {
            callback.onSuccess(null)
        } else {
            callback.onSuccess(responseBuilder.build())
        }
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // MultiPad encrypts entries only inside the unlocked master-key vault.
        callback.onSuccess()
    }

    private fun traverseStructure(structure: AssistStructure, out: ParsedFields) {
        for (i in 0 until structure.windowNodeCount) {
            val root = structure.getWindowNodeAt(i).rootViewNode ?: continue
            traverseNode(root, out)
        }
    }

    private fun traverseNode(node: AssistStructure.ViewNode, out: ParsedFields) {
        val domain = node.webDomain
        if (!domain.isNullOrBlank()) {
            out.webDomains.add(domain.lowercase(Locale.US).removePrefix("www."))
        }

        val autofillId = node.autofillId
        if (autofillId != null && node.autofillType != View.AUTOFILL_TYPE_NONE) {
            classifyNode(node, autofillId, out)
        }

        for (i in 0 until node.childCount) {
            traverseNode(node.getChildAt(i), out)
        }
    }

    private fun classifyNode(
        node: AssistStructure.ViewNode,
        id: AutofillId,
        out: ParsedFields,
    ) {
        val hints = node.autofillHints?.map { it.lowercase(Locale.US) } ?: emptyList()
        val idEntry = (node.idEntry ?: "").lowercase(Locale.US)
        val hintText = (node.hint ?: "").lowercase(Locale.US)
        val htmlAttrs = node.htmlInfo?.attributes
            ?.map { "${it.first.lowercase(Locale.US)}=${it.second.lowercase(Locale.US)}" }
            ?: emptyList()
        val htmlTag = (node.htmlInfo?.tag ?: "").lowercase(Locale.US)
        val htmlAttrsText = htmlAttrs.joinToString(" ")
        val combinedMeta = "$idEntry $hintText ${hints.joinToString(" ")} $htmlAttrsText"

        val inputType = node.inputType
        val inputClass = inputType and InputType.TYPE_MASK_CLASS
        val inputVariation = inputType and InputType.TYPE_MASK_VARIATION

        val isPasswordVariation =
            (inputClass == InputType.TYPE_CLASS_TEXT && (
                inputVariation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                    inputVariation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                    inputVariation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
                )) ||
                (inputClass == InputType.TYPE_CLASS_NUMBER &&
                    inputVariation == InputType.TYPE_NUMBER_VARIATION_PASSWORD)

        val isBrowserUrlBar =
            idEntry == "url_bar" ||
                idEntry.contains("omnibox") ||
                idEntry.contains("location_bar") ||
                idEntry.contains("search_box") ||
                idEntry.contains("address_bar")

        if (isBrowserUrlBar && !isPasswordVariation && hints.isEmpty()) {
            return
        }

        val isOtpHint = hints.any { it.contains("otp") || it.contains("2fa") || it.contains("one_time_code") || it == "one-time-code" } ||
            htmlAttrs.any { it.contains("autocomplete=one-time-code") } ||
            combinedMeta.contains("totp") ||
            combinedMeta.contains("2fa") ||
            combinedMeta.contains("one-time") ||
            combinedMeta.contains("doğrulama") ||
            combinedMeta.contains("auth_code")

        if (isOtpHint) {
            out.otpIds.add(id)
            return
        }

        val isHtmlPassword = htmlTag == "input" &&
            (htmlAttrs.any { it == "type=password" || it.contains("autocomplete=current-password") || it.contains("autocomplete=new-password") })

        val isPasswordHint = hints.any {
            it == View.AUTOFILL_HINT_PASSWORD || it.contains("password")
        } || isPasswordVariation ||
            isHtmlPassword ||
            combinedMeta.contains("password") ||
            combinedMeta.contains("parola") ||
            combinedMeta.contains("sifre") ||
            combinedMeta.contains("şifre") ||
            combinedMeta.contains("passcode")

        if (isPasswordHint) {
            out.passwordIds.add(id)
            return
        }

        val isEmailVariation = inputClass == InputType.TYPE_CLASS_TEXT && (
            inputVariation == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS ||
                inputVariation == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS
            )

        val isHtmlUsername = htmlTag == "input" &&
            (htmlAttrs.any {
                it == "type=email" ||
                    it.contains("autocomplete=username") ||
                    it.contains("autocomplete=email")
            })

        val isUsernameHint = hints.any {
            it == View.AUTOFILL_HINT_USERNAME ||
                it == View.AUTOFILL_HINT_EMAIL_ADDRESS ||
                it.contains("user") ||
                it.contains("email")
        } || isEmailVariation ||
            isHtmlUsername ||
            combinedMeta.contains("user") ||
            combinedMeta.contains("login") ||
            combinedMeta.contains("email") ||
            combinedMeta.contains("e-posta") ||
            combinedMeta.contains("kullanıcı") ||
            combinedMeta.contains("account")

        if (isUsernameHint) {
            out.usernameIds.add(id)
        }
    }

    private fun rankEntries(
        entries: List<AutofillCredentialEntry>,
        webDomains: Set<String>,
        packageName: String,
    ): List<AutofillCredentialEntry> {
        val pkgTokens = packageName.split('.').filter {
            it.length >= 3 && it != "com" && it != "org" && it != "net" && it != "app" && it != "android"
        }

        fun score(e: AutofillCredentialEntry): Int {
            var s = 0
            val host = extractHost(e.website)
            if (host.isNotEmpty()) {
                for (wd in webDomains) {
                    if (host == wd) {
                        s += 100
                    } else if (host.endsWith(".$wd") || wd.endsWith(".$host")) {
                        s += 80
                    }
                }
            }
            val combinedTitle = "${e.title} $host".lowercase(Locale.US)
            for (tok in pkgTokens) {
                if (combinedTitle.contains(tok)) {
                    s += 30
                }
            }
            return s
        }

        return entries
            .map { it to score(it) }
            .sortedByDescending { it.second }
            .map { it.first }
    }

    private fun extractHost(rawUrl: String): String {
        val clean = rawUrl.trim().lowercase(Locale.US)
        if (clean.isEmpty()) return ""
        val withScheme = if (clean.contains("://")) clean else "https://$clean"
        return try {
            (Uri.parse(withScheme).host ?: clean).removePrefix("www.")
        } catch (_: Exception) {
            clean
        }
    }

    private fun generateTotpIfPresent(rawSecret: String): String? {
        val trimmed = rawSecret.trim()
        if (trimmed.isEmpty()) return null

        var base32 = trimmed
        if (trimmed.lowercase(Locale.US).startsWith("otpauth://")) {
            base32 = Uri.parse(trimmed).getQueryParameter("secret") ?: return null
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
            val otp = binary % 10.0.pow(6).toInt()
            otp.toString().padStart(6, '0')
        } catch (_: Exception) {
            null
        }
    }

    private fun decodeBase32(input: String): ByteArray {
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        val out = ArrayList<Byte>()
        var buffer = 0
        var bitsLeft = 0
        for (ch in input) {
            val value = alphabet.indexOf(ch)
            if (value < 0) continue
            buffer = (buffer shl 5) or value
            bitsLeft += 5
            if (bitsLeft >= 8) {
                out.add(((buffer shr (bitsLeft - 8)) and 0xff).toByte())
                bitsLeft -= 8
            }
        }
        return out.toByteArray()
    }
}
