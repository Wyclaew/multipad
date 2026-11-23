package com.multipad.multipad

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.InlinePresentation
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.view.inputmethod.InlineSuggestionsRequest
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import androidx.autofill.inline.v1.InlineSuggestionUi
import java.nio.ByteBuffer
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlin.math.pow

@RequiresApi(Build.VERSION_CODES.O)
class MultiPadAutofillService : AutofillService() {

    data class SplitOtpBox(
        val id: AutofillId,
        val index: Int,
    )

    private data class ParsedFields(
        val usernameIds: MutableList<AutofillId> = mutableListOf(),
        val passwordIds: MutableList<AutofillId> = mutableListOf(),
        val singleOtpIds: MutableList<AutofillId> = mutableListOf(),
        val splitOtpBoxes: MutableList<SplitOtpBox> = mutableListOf(),
        val webDomains: MutableSet<String> = mutableSetOf(),
        val fallbackDomains: MutableSet<String> = mutableSetOf(),
    )

    // Feature 18: Safe URL Bar Extraction & Domain Sanitizer
    object DomainExtractor {
        private val DOMAIN_REGEX = Regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$")
        private val IPV4_REGEX = Regex("^(\\d{1,3}\\.){3}\\d{1,3}$")

        val PUBLIC_SUFFIXES: Set<String> = setOf(
            // United Kingdom (.uk)
            "co.uk", "org.uk", "me.uk", "net.uk", "ltd.uk", "plc.uk", "ac.uk", "sch.uk", "gov.uk", "nhs.uk", "police.uk",
            // Australia (.au)
            "com.au", "net.au", "org.au", "edu.au", "gov.au", "asn.au", "id.au",
            // New Zealand (.nz)
            "co.nz", "net.nz", "org.nz", "govt.nz", "ac.nz", "school.nz", "geek.nz",
            // Japan (.jp)
            "co.jp", "ne.jp", "or.jp", "ac.jp", "ed.jp", "go.jp", "gr.jp", "lg.jp",
            // Brazil (.br)
            "com.br", "net.br", "org.br", "gov.br", "edu.br", "mil.br", "art.br",
            // Turkey (.tr)
            "com.tr", "net.tr", "org.tr", "edu.tr", "gov.tr", "bel.tr", "gen.tr", "biz.tr", "info.tr", "av.tr", "dr.tr", "pol.tr",
            // India (.in)
            "co.in", "net.in", "org.in", "gen.in", "firm.in", "ind.in", "ac.in", "edu.in", "res.in", "gov.in", "mil.in",
            // South Africa (.za)
            "co.za", "org.za", "net.za", "web.za", "gov.za", "ac.za", "edu.za",
            // Canada (.ca)
            "gc.ca", "ab.ca", "bc.ca", "mb.ca", "nb.ca", "nl.ca", "ns.ca", "nt.ca", "nu.ca", "on.ca", "pe.ca", "qc.ca", "sk.ca", "yk.ca",
            // United States (.us)
            "fed.us", "dni.us",
            // Europe & Russia
            "com.es", "nom.es", "org.es", "gob.es", "edu.es",
            "com.pt", "org.pt", "gov.pt", "edu.pt",
            "com.pl", "net.pl", "org.pl",
            "com.ru", "net.ru", "org.ru", "pp.ru",
            // Israel (.il)
            "co.il", "org.il", "net.il", "ac.il", "gov.il", "muni.il", "idf.il",
            // South Korea (.kr)
            "co.kr", "ne.kr", "or.kr", "re.kr", "pe.kr", "go.kr", "mil.kr", "ac.kr",
            // Singapore (.sg)
            "com.sg", "net.sg", "org.sg", "gov.sg", "edu.sg", "per.sg",
            // Hong Kong (.hk)
            "com.hk", "net.hk", "org.hk", "gov.hk", "edu.hk", "idv.hk",
            // Taiwan (.tw)
            "com.tw", "org.tw", "net.tw", "gov.tw", "edu.tw", "idv.tw",
            // Malaysia (.my)
            "com.my", "net.my", "org.my", "gov.my", "edu.my", "mil.my",
            // Mexico (.mx)
            "com.mx", "net.mx", "org.mx", "edu.mx", "gob.mx",
            // Argentina (.ar)
            "com.ar", "net.ar", "org.ar", "gob.ar", "edu.ar",
            // Colombia (.co)
            "com.co", "net.co", "nom.co", "org.co", "gov.co", "edu.co",
            // Philippines (.ph)
            "com.ph", "net.ph", "org.ph", "gov.ph", "edu.ph",
            // China (.cn)
            "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
            // Shared Developer & Multi-Tenant Platforms (PSL Private Domains)
            "github.io", "gitlab.io", "pages.dev", "workers.dev", "vercel.app", "now.sh",
            "netlify.app", "web.app", "firebaseapp.com", "herokuapp.com", "azurewebsites.net",
            "azurestaticapps.net", "cloudfront.net", "s3.amazonaws.com", "appspot.com",
            "myshopify.com", "wordpress.com", "blogspot.com", "fastly.net", "fly.dev",
            "onrender.com", "render.com", "glitch.me", "supabase.co"
        )

        fun isPublicSuffix(host: String): Boolean {
            return PUBLIC_SUFFIXES.contains(host.lowercase(Locale.US))
        }

        fun extractETldPlusOne(rawUrlOrHost: String?): String? {
            val host = extractCleanHost(rawUrlOrHost) ?: return null
            if (host == "localhost" || IPV4_REGEX.matches(host)) return host

            val labels = host.split('.')
            if (labels.size <= 1) return null

            var suffixLength = 1
            if (labels.size >= 3) {
                val candidate3 = labels.takeLast(3).joinToString(".")
                if (PUBLIC_SUFFIXES.contains(candidate3)) {
                    suffixLength = 3
                }
            }
            if (suffixLength == 1 && labels.size >= 2) {
                val candidate2 = labels.takeLast(2).joinToString(".")
                if (PUBLIC_SUFFIXES.contains(candidate2)) {
                    suffixLength = 2
                }
            }

            if (labels.size < suffixLength + 1) {
                return null // Bare suffix
            }

            return labels.takeLast(suffixLength + 1).joinToString(".")
        }

        fun extractCleanHost(rawInput: String?): String? {
            if (rawInput.isNullOrBlank()) return null
            val raw = rawInput.trim()

            // 1. Reject search queries containing whitespace
            if (raw.contains(" ") || raw.contains("\t") || raw.contains("\n")) return null

            // 2. Reject internal browser schemes
            val lower = raw.lowercase(Locale.US)
            if (lower.startsWith("about:") ||
                lower.startsWith("chrome://") ||
                lower.startsWith("edge://") ||
                lower.startsWith("firefox://") ||
                lower.startsWith("file://") ||
                lower.startsWith("content://") ||
                lower.startsWith("javascript:")
            ) {
                return null
            }

            // 3. Extract host via URI parser or string split fallback
            val withScheme = if (raw.contains("://")) raw else "https://$raw"
            val host = try {
                Uri.parse(withScheme).host?.lowercase(Locale.US)?.takeIf { it.isNotBlank() }
            } catch (_: Exception) {
                null
            } ?: run {
                val cleanRaw = if (raw.contains("://")) raw.substringAfter("://") else raw
                val authority = cleanRaw.substringBefore('#').substringBefore('?').substringBefore('/')
                val hostPort = authority.substringAfterLast('@')
                val rawHost = if (hostPort.startsWith('[')) {
                    hostPort.substringAfter('[').substringBefore(']')
                } else {
                    hostPort.substringBefore(':')
                }.trim().lowercase(Locale.US)
                rawHost
            }

            if (host.isNullOrBlank()) return null

            // 4. Strip www. and leading/trailing dots
            val cleanHost = host.removePrefix("www.").trim('.')

            // 5. Validate syntax
            if (cleanHost == "localhost") return "localhost"
            if (IPV4_REGEX.matches(cleanHost)) return cleanHost

            if (DOMAIN_REGEX.matches(cleanHost)) {
                val tld = cleanHost.substringAfterLast('.')
                if (tld.length >= 2 && tld.all { it in 'a'..'z' }) {
                    // Reject bare public suffixes (e.g. "co.uk", "github.io")
                    if (isPublicSuffix(cleanHost)) {
                        return null
                    }
                    return cleanHost
                }
            }

            return null
        }
    }

    // Feature 20: Package Alias Mapping Dictionary (50+ major apps)
    object PackageAliasMap {
        private val ALIASES: Map<String, List<String>> = mapOf(
            // Social, Chat & Streaming
            "com.twitter.android" to listOf("twitter.com", "x.com"),
            "com.twitter.android.lite" to listOf("twitter.com", "x.com"),
            "com.instagram.android" to listOf("instagram.com"),
            "com.facebook.katana" to listOf("facebook.com"),
            "com.facebook.lite" to listOf("facebook.com"),
            "com.facebook.orca" to listOf("messenger.com", "facebook.com"),
            "com.zhiliaoapp.musically" to listOf("tiktok.com"),
            "com.zhiliaoapp.musically.go" to listOf("tiktok.com"),
            "com.ss.android.ugc.trill" to listOf("tiktok.com"),
            "com.snapchat.android" to listOf("snapchat.com"),
            "com.reddit.frontpage" to listOf("reddit.com"),
            "com.linkedin.android" to listOf("linkedin.com"),
            "com.pinterest" to listOf("pinterest.com"),
            "org.telegram.messenger" to listOf("telegram.org"),
            "org.telegram.messenger.web" to listOf("telegram.org"),
            "org.thunderdog.challegram" to listOf("telegram.org"),
            "com.whatsapp" to listOf("whatsapp.com"),
            "com.whatsapp.w4b" to listOf("whatsapp.com"),
            "com.discord" to listOf("discord.com"),
            "tv.twitch.android.app" to listOf("twitch.tv"),
            "com.spotify.music" to listOf("spotify.com"),
            "com.spotify.music.lite" to listOf("spotify.com"),
            "com.netflix.mediaclient" to listOf("netflix.com"),
            "com.google.android.youtube" to listOf("youtube.com", "google.com"),
            "com.disney.disneyplus" to listOf("disneyplus.com"),
            "com.amazon.avod.thirdpartyclient" to listOf("primevideo.com", "amazon.com"),
            "com.hulu.plus" to listOf("hulu.com"),

            // Mobility, Delivery & Travel
            "com.ubercab" to listOf("uber.com"),
            "com.ubercab.eats" to listOf("ubereats.com", "uber.com"),
            "com.ubercab.driver" to listOf("uber.com"),
            "me.lyft.android" to listOf("lyft.com"),
            "com.dd.doordash" to listOf("doordash.com"),
            "com.dd.driver" to listOf("doordash.com"),
            "com.deliveroo.orderapp" to listOf("deliveroo.com"),
            "com.grubhub.android" to listOf("grubhub.com"),
            "com.airbnb.android" to listOf("airbnb.com"),
            "com.booking" to listOf("booking.com"),
            "com.tripadvisor.tripadvisor" to listOf("tripadvisor.com"),

            // E-Commerce & Payments
            "com.amazon.mshop.android.shopping" to listOf("amazon.com"),
            "com.amazon.kindle" to listOf("amazon.com"),
            "com.ebay.mobile" to listOf("ebay.com"),
            "com.alibaba.aliexpresshd" to listOf("aliexpress.com"),
            "com.paypal.android.p2pmobile" to listOf("paypal.com"),
            "com.stripe.android" to listOf("stripe.com"),
            "com.squareup.cash" to listOf("cash.app"),
            "com.coinbase.android" to listOf("coinbase.com"),
            "com.binance.dev" to listOf("binance.com"),

            // Productivity, Developer & Gaming
            "com.github.android" to listOf("github.com"),
            "com.valvesoftware.android.steam.community" to listOf("steampowered.com", "steamcommunity.com"),
            "com.epicgames.portal" to listOf("epicgames.com"),
            "com.scee.psxandroid" to listOf("playstation.com", "sony.com"),
            "com.microsoft.xboxone.smartglass" to listOf("xbox.com"),
            "us.zoom.videomeetings" to listOf("zoom.us"),
            "com.slack" to listOf("slack.com"),
            "com.trello" to listOf("trello.com"),
            "notion.id" to listOf("notion.so"),
            "com.asana.app" to listOf("asana.com"),
            "com.dropbox.android" to listOf("dropbox.com"),
            "com.microsoft.office.outlook" to listOf("outlook.com", "live.com", "office.com"),
            "com.microsoft.teams" to listOf("teams.microsoft.com"),
            "com.microsoft.skydrive" to listOf("onedrive.live.com"),
            "ch.protonmail.android" to listOf("proton.me", "protonmail.com"),
            "ch.protonvpn.android" to listOf("proton.me"),
            "com.fastmail.app" to listOf("fastmail.com"),
            "com.duolingo" to listOf("duolingo.com"),
            "com.google.android.apps.docs" to listOf("drive.google.com"),
            "com.google.android.gm" to listOf("gmail.com", "google.com"),
        ).mapKeys { it.key.lowercase(Locale.US) }

        fun getDomainsForPackage(packageName: String): List<String> {
            val cleanPkg = packageName.trim().lowercase(Locale.US)
            return ALIASES[cleanPkg] ?: emptyList()
        }
    }

    companion object {
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

        fun isUrlBarNode(idEntry: String?): Boolean {
            if (idEntry == null) return false
            val cleanId = idEntry.lowercase(Locale.US)
            return URL_BAR_ID_PATTERNS.any { cleanId.contains(it) }
        }
    }

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

        // Active context (current visible step)
        val structure = contexts.last().structure
        val parsed = ParsedFields()
        traverseStructure(structure, parsed)

        // Feature 18: Fallback to URL bar extracted domains if node.webDomain was not present
        if (parsed.webDomains.isEmpty() && parsed.fallbackDomains.isNotEmpty()) {
            parsed.webDomains.addAll(parsed.fallbackDomains)
        }

        if (parsed.usernameIds.isEmpty() &&
            parsed.passwordIds.isEmpty() &&
            parsed.singleOtpIds.isEmpty() &&
            parsed.splitOtpBoxes.isEmpty()
        ) {
            callback.onSuccess(null)
            return
        }

        val allEntries = AutofillCryptoStore.loadEntries(applicationContext)
        val pkgName = structure.activityComponent?.packageName?.lowercase(Locale.US) ?: ""

        // Feature 16: Multi-step context aggregation in onFillRequest
        // If current step is password-only (Step 2), look backwards across prior contexts for Step 1 username
        var step1Username: String? = null
        if (parsed.usernameIds.isEmpty() && contexts.size > 1) {
            for (i in contexts.size - 2 downTo 0) {
                step1Username = extractEnteredUsername(contexts[i].structure)
                if (!step1Username.isNullOrBlank()) break
            }
        }

        val ranked = if (allEntries.isNotEmpty()) {
            rankEntries(allEntries, parsed.webDomains, pkgName, step1Username)
        } else {
            emptyList()
        }

        val responseBuilder = FillResponse.Builder()
        var addedDatasets = 0

        // Feature 14: Inspect Android 11+ InlineSuggestionsRequest
        val inlineRequest: InlineSuggestionsRequest? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                request.inlineSuggestionsRequest
            } else {
                null
            }

        val inlineSpecs = inlineRequest?.inlinePresentationSpecs ?: emptyList()
        val maxInlineCount = inlineRequest?.maxSuggestionCount ?: 0
        val supportsInline = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            inlineRequest != null &&
            inlineSpecs.isNotEmpty() &&
            maxInlineCount > 0

        for ((index, entry) in ranked.take(10).withIndex()) {
            val totpCode = generateTotpIfPresent(entry.totpSecret)
            val titleText = entry.title.ifEmpty { entry.website.ifEmpty { "MultiPad" } }
            val subtitle = buildString {
                if (entry.username.isNotEmpty()) append(entry.username)
                if (totpCode != null) {
                    if (isNotEmpty()) append(" • ")
                    append("2FA: $totpCode")
                }
                if (isEmpty() && entry.website.isNotEmpty()) append(entry.website)
            }.ifEmpty { "MultiPad" }

            // Feature 15: Custom branded RemoteViews matching Material 3 slate/indigo tokens
            val presentation = RemoteViews(packageName, R.layout.autofill_dataset_item).apply {
                setImageViewResource(R.id.autofill_item_icon, R.mipmap.ic_launcher)
                setTextViewText(R.id.autofill_item_title, titleText)
                setTextViewText(R.id.autofill_item_subtitle, subtitle)
                if (totpCode != null) {
                    setViewVisibility(R.id.autofill_item_badge, View.VISIBLE)
                    setTextViewText(R.id.autofill_item_badge, "2FA: $totpCode")
                } else {
                    setViewVisibility(R.id.autofill_item_badge, View.GONE)
                }
            }

            val datasetBuilder = Dataset.Builder(presentation)

            // Feature 14: Build InlinePresentation if supported and within max suggestion capacity
            if (supportsInline && index < maxInlineCount) {
                val specIndex = minOf(index, inlineSpecs.size - 1)
                val spec = inlineSpecs[specIndex]

                val attributionIntent = PendingIntent.getActivity(
                    applicationContext,
                    0,
                    Intent(),
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0,
                )

                val contentBuilder = InlineSuggestionUi.newContentBuilder(attributionIntent)
                    .setTitle(titleText)

                if (entry.username.isNotEmpty()) {
                    contentBuilder.setSubtitle(entry.username)
                }

                val brandIcon = Icon.createWithResource(applicationContext, R.mipmap.ic_launcher)
                contentBuilder.setStartIcon(brandIcon)

                val slice = contentBuilder.build().slice
                val inlinePresentation = InlinePresentation(slice, spec, false)
                datasetBuilder.setInlinePresentation(inlinePresentation)
            }

            var hasValue = false

            // Set username fields
            if (entry.username.isNotEmpty()) {
                for (id in parsed.usernameIds) {
                    datasetBuilder.setValue(id, AutofillValue.forText(entry.username))
                    hasValue = true
                }
            }

            // Set password fields
            if (entry.password.isNotEmpty()) {
                for (id in parsed.passwordIds) {
                    datasetBuilder.setValue(id, AutofillValue.forText(entry.password))
                    hasValue = true
                }
            }

            // Feature 17: Split-field multi-box OTP distribution vs single OTP field
            if (totpCode != null) {
                // A. Split Multi-Box OTP fields: distribute 1 character per box
                if (parsed.splitOtpBoxes.isNotEmpty()) {
                    val sortedBoxes = parsed.splitOtpBoxes.distinctBy { it.id }.sortedBy { it.index }
                    val fillCount = minOf(sortedBoxes.size, totpCode.length)
                    for (i in 0 until fillCount) {
                        datasetBuilder.setValue(sortedBoxes[i].id, AutofillValue.forText(totpCode[i].toString()))
                        hasValue = true
                    }
                }

                // B. Single OTP field: fill full 6-digit TOTP string
                for (id in parsed.singleOtpIds) {
                    datasetBuilder.setValue(id, AutofillValue.forText(totpCode))
                    hasValue = true
                }
            }

            if (hasValue) {
                responseBuilder.addDataset(datasetBuilder.build())
                addedDatasets++
            }
        }

        // Feature 19: SaveInfo Configuration & SPA Flags
        // Build SaveInfo ONLY when password fields exist (prevent premature prompts on Step 1)
        if (parsed.passwordIds.isNotEmpty()) {
            val saveInfoBuilder = SaveInfo.Builder(
                SaveInfo.SAVE_DATA_TYPE_PASSWORD or SaveInfo.SAVE_DATA_TYPE_USERNAME,
                parsed.passwordIds.toTypedArray(),
            )
            if (parsed.usernameIds.isNotEmpty()) {
                saveInfoBuilder.setOptionalIds(parsed.usernameIds.toTypedArray())
            }
            // Enable SPA (Single Page Application) form transition capture on Android 9+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                saveInfoBuilder.setFlags(SaveInfo.FLAG_SAVE_ON_ALL_VIEWS_INVISIBLE)
            }
            responseBuilder.setSaveInfo(saveInfoBuilder.build())
        }

        // Return FillResponse if we added datasets OR if we configured SaveInfo for a new site login
        if (addedDatasets > 0 || parsed.passwordIds.isNotEmpty()) {
            callback.onSuccess(responseBuilder.build())
        } else {
            callback.onSuccess(null)
        }
    }

    private data class ExtractedSaveData(
        var username: String = "",
        var password: String = "",
        val webDomains: MutableSet<String> = mutableSetOf(),
        val fallbackDomains: MutableSet<String> = mutableSetOf(),
    )

    // Feature 16: Multi-step backward context aggregation in onSaveRequest
    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val contexts = request.fillContexts
        if (contexts.isEmpty()) {
            callback.onSuccess()
            return
        }

        val extracted = ExtractedSaveData()
        val latestStructure = contexts.last().structure
        val pkgName = latestStructure.activityComponent?.packageName?.lowercase(Locale.US) ?: ""

        // Iterate backwards across all contexts so Step 1 username is recovered if Step 2 only had password
        for (context in contexts.reversed()) {
            traverseStructureForSave(context.structure, extracted)
            if (extracted.password.isNotBlank() && extracted.username.isNotBlank()) {
                break
            }
        }

        if (extracted.webDomains.isEmpty() && extracted.fallbackDomains.isNotEmpty()) {
            extracted.webDomains.addAll(extracted.fallbackDomains)
        }

        if (extracted.password.isNotBlank() && (extracted.username.isNotBlank() || extracted.webDomains.isNotEmpty())) {
            // Feature 20: Use package alias mapping on save
            val aliasDomains = PackageAliasMap.getDomainsForPackage(pkgName)
            val effectiveDomains = if (extracted.webDomains.isNotEmpty()) {
                extracted.webDomains
            } else {
                aliasDomains.toSet()
            }

            val domain = effectiveDomains.firstOrNull() ?: pkgName
            val title = if (effectiveDomains.isNotEmpty()) {
                domain.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.US) else it.toString() }
            } else {
                pkgName
            }

            val pending = PendingCredentialEntry(
                id = java.util.UUID.randomUUID().toString(),
                title = title,
                website = domain,
                username = extracted.username,
                password = extracted.password,
                packageName = pkgName,
                timestamp = System.currentTimeMillis(),
            )
            AutofillCryptoStore.savePendingCredential(applicationContext, pending)
        }
        callback.onSuccess()
    }

    private fun extractEnteredUsername(structure: AssistStructure): String? {
        for (i in 0 until structure.windowNodeCount) {
            val root = structure.getWindowNodeAt(i).rootViewNode ?: continue
            val found = findUsernameValue(root)
            if (!found.isNullOrBlank()) return found
        }
        return null
    }

    private fun findUsernameValue(node: AssistStructure.ViewNode): String? {
        val autofillId = node.autofillId
        if (autofillId != null && node.autofillType != View.AUTOFILL_TYPE_NONE) {
            val parsed = ParsedFields()
            classifyNode(node, autofillId, parsed)
            if (parsed.usernameIds.contains(autofillId)) {
                val textVal = node.autofillValue?.textValue?.toString()
                    ?: node.text?.toString()
                if (!textVal.isNullOrBlank()) {
                    return textVal.trim()
                }
            }
        }
        for (i in 0 until node.childCount) {
            val res = findUsernameValue(node.getChildAt(i))
            if (!res.isNullOrBlank()) return res
        }
        return null
    }

    private fun traverseStructureForSave(structure: AssistStructure, out: ExtractedSaveData) {
        for (i in 0 until structure.windowNodeCount) {
            val root = structure.getWindowNodeAt(i).rootViewNode ?: continue
            traverseNodeForSave(root, out)
        }
    }

    private fun traverseNodeForSave(node: AssistStructure.ViewNode, out: ExtractedSaveData) {
        val domain = node.webDomain
        if (!domain.isNullOrBlank()) {
            val clean = DomainExtractor.extractCleanHost(domain)
            if (clean != null) {
                out.webDomains.add(clean)
            }
        }

        // Feature 18: Fallback URL bar host extraction for save
        val idEntry = node.idEntry
        if (isUrlBarNode(idEntry)) {
            val rawText = node.text?.toString() ?: node.autofillValue?.textValue?.toString()
            val host = DomainExtractor.extractCleanHost(rawText)
            if (host != null) {
                out.fallbackDomains.add(host)
            }
        }

        val autofillId = node.autofillId
        if (autofillId != null && node.autofillType != View.AUTOFILL_TYPE_NONE) {
            val parsed = ParsedFields()
            classifyNode(node, autofillId, parsed)
            val textVal = node.autofillValue?.textValue?.toString()
                ?: node.text?.toString()
                ?: ""

            if (textVal.isNotBlank()) {
                if (parsed.passwordIds.contains(autofillId) && out.password.isBlank()) {
                    out.password = textVal
                } else if (parsed.usernameIds.contains(autofillId) && out.username.isBlank()) {
                    out.username = textVal
                }
            }
        }

        for (i in 0 until node.childCount) {
            traverseNodeForSave(node.getChildAt(i), out)
        }
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
            val clean = DomainExtractor.extractCleanHost(domain)
            if (clean != null) {
                out.webDomains.add(clean)
            }
        }

        // Feature 18: Fallback URL bar host extraction
        val idEntry = node.idEntry
        if (isUrlBarNode(idEntry)) {
            val rawText = node.text?.toString() ?: node.autofillValue?.textValue?.toString()
            val host = DomainExtractor.extractCleanHost(rawText)
            if (host != null) {
                out.fallbackDomains.add(host)
            }
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

        // Feature 18: URL bar nodes must NEVER be classified as username, password, or OTP
        if (isUrlBarNode(idEntry) && !isPasswordVariation && hints.isEmpty()) {
            return
        }

        // Feature 17: Split-Field Multi-Box OTP vs Single OTP Detection
        val isSingleCharBox = htmlAttrs.any { it == "maxlength=1" || it == "size=1" } ||
            htmlAttrs.any { it.contains("maxlength=1") }

        val indexedMatch = Regex(".*(?:otp|pin|digit|code|box|char)[-_.\\[]?([0-9]+)\\]?$", RegexOption.IGNORE_CASE)
            .find(idEntry)

        val smsOtpPosHint = hints.firstOrNull { it.startsWith("smsotpcode:") || it.startsWith("otp:") }
            ?.substringAfter(":")
            ?.toIntOrNull()

        val isSplitOtpCandidate = (indexedMatch != null || smsOtpPosHint != null) &&
            (isSingleCharBox || inputClass == InputType.TYPE_CLASS_NUMBER || inputClass == InputType.TYPE_CLASS_PHONE)

        if (isSplitOtpCandidate) {
            val detectedIndex = smsOtpPosHint
                ?: (indexedMatch?.groupValues?.getOrNull(1)?.toIntOrNull() ?: out.splitOtpBoxes.size)
            out.splitOtpBoxes.add(SplitOtpBox(id, detectedIndex))
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
            if (isSingleCharBox) {
                out.splitOtpBoxes.add(SplitOtpBox(id, out.splitOtpBoxes.size))
            } else {
                out.singleOtpIds.add(id)
            }
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
        step1Username: String? = null,
    ): List<AutofillCredentialEntry> {
        // Feature 20: Package alias mapping integration & noise token filtering
        val aliasDomains = PackageAliasMap.getDomainsForPackage(packageName)
        val effectiveDomains = (webDomains + aliasDomains).toSet()

        val noiseTokens = setOf("com", "org", "net", "app", "android", "client", "mobile", "shopping", "music", "media", "apps", "free", "lite")
        val pkgTokens = packageName.split('.').filter {
            it.length >= 3 && it !in noiseTokens
        }

        fun score(e: AutofillCredentialEntry): Int {
            var s = 0
            val host = extractHost(e.website)
            if (host.isNotEmpty()) {
                for (wd in effectiveDomains) {
                    if (host == wd) {
                        s += 100
                    } else if (!DomainExtractor.isPublicSuffix(host) && !DomainExtractor.isPublicSuffix(wd)) {
                        if (host.endsWith(".$wd") || wd.endsWith(".$host")) {
                            s += 80
                        } else {
                            val hostRoot = DomainExtractor.extractETldPlusOne(host)
                            val wdRoot = DomainExtractor.extractETldPlusOne(wd)
                            if (hostRoot != null && hostRoot == wdRoot) {
                                s += 60
                            }
                        }
                    }
                }
            }
            val combinedTitle = "${e.title} $host".lowercase(Locale.US)
            for (tok in pkgTokens) {
                if (combinedTitle.contains(tok)) {
                    s += 30
                }
            }

            // Feature 16: Boost matching account username from Step 1
            if (!step1Username.isNullOrBlank() && e.username.equals(step1Username, ignoreCase = true)) {
                s += 500
            }

            return s
        }

        return entries
            .map { it to score(it) }
            .filter { it.second > 0 }
            .sortedByDescending { it.second }
            .map { it.first }
    }

    private fun extractHost(rawUrl: String): String {
        return DomainExtractor.extractCleanHost(rawUrl) ?: ""
    }

    private fun generateTotpIfPresent(rawSecret: String): String? {
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
            val modulo = 10.0.pow(digits.toDouble()).toLong()
            val otp = (binary % modulo).toInt()
            otp.toString().padStart(digits, '0')
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
