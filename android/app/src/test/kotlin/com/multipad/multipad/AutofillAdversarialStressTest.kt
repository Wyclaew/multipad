package com.multipad.multipad

import org.junit.Assert.*
import org.junit.Test

class AutofillAdversarialStressTest {

    // =========================================================================
    // 1. Challenge PackageAliasMap
    // =========================================================================

    @Test
    fun testPackageAliasMap_coverage() {
        val verifiedPackages = listOf(
            // Social, Chat & Streaming
            "com.twitter.android",
            "com.twitter.android.lite",
            "com.instagram.android",
            "com.facebook.katana",
            "com.facebook.lite",
            "com.facebook.orca",
            "com.zhiliaoapp.musically",
            "com.zhiliaoapp.musically.go",
            "com.ss.android.ugc.trill",
            "com.snapchat.android",
            "com.reddit.frontpage",
            "com.linkedin.android",
            "com.pinterest",
            "org.telegram.messenger",
            "org.telegram.messenger.web",
            "org.thunderdog.challegram",
            "com.whatsapp",
            "com.whatsapp.w4b",
            "com.discord",
            "tv.twitch.android.app",
            "com.spotify.music",
            "com.spotify.music.lite",
            "com.netflix.mediaclient",
            "com.google.android.youtube",
            "com.disney.disneyplus",
            "com.amazon.avod.thirdpartyclient",
            "com.hulu.plus",
            // Mobility, Delivery & Travel
            "com.ubercab",
            "com.ubercab.eats",
            "com.ubercab.driver",
            "me.lyft.android",
            "com.dd.doordash",
            "com.dd.driver",
            "com.deliveroo.orderapp",
            "com.grubhub.android",
            "com.airbnb.android",
            "com.booking",
            "com.tripadvisor.tripadvisor",
            // E-Commerce & Payments
            "com.amazon.mShop.android.shopping",
            "com.amazon.mshop.android.shopping",
            "com.amazon.kindle",
            "com.ebay.mobile",
            "com.alibaba.aliexpresshd",
            "com.paypal.android.p2pmobile",
            "com.stripe.android",
            "com.squareup.cash",
            "com.coinbase.android",
            "com.binance.dev",
            // Productivity, Developer & Gaming
            "com.github.android",
            "com.valvesoftware.android.steam.community",
            "com.epicgames.portal",
            "com.scee.psxandroid",
            "com.microsoft.xboxone.smartglass",
            "us.zoom.videomeetings",
            "com.Slack",
            "com.slack",
            "com.trello",
            "notion.id",
            "com.asana.app",
            "com.dropbox.android",
            "com.microsoft.office.outlook",
            "com.microsoft.teams",
            "com.microsoft.skydrive",
            "ch.protonmail.android",
            "ch.protonvpn.android",
            "com.fastmail.app",
            "com.duolingo",
            "com.google.android.apps.docs",
            "com.google.android.gm"
        )
        assertTrue("Expected 50+ packages, found ${verifiedPackages.size}", verifiedPackages.size >= 50)
        for (pkg in verifiedPackages) {
            val domains = MultiPadAutofillService.PackageAliasMap.getDomainsForPackage(pkg)
            assertFalse("Package $pkg should have mapped domains", domains.isEmpty())
        }
    }

    @Test
    fun testPackageAliasMap_casingResolution() {
        val amazonMixed = MultiPadAutofillService.PackageAliasMap.getDomainsForPackage("com.amazon.mShop.android.shopping")
        val amazonLower = MultiPadAutofillService.PackageAliasMap.getDomainsForPackage("com.amazon.mshop.android.shopping")
        val slackMixed = MultiPadAutofillService.PackageAliasMap.getDomainsForPackage("com.Slack")
        val slackLower = MultiPadAutofillService.PackageAliasMap.getDomainsForPackage("com.slack")

        assertEquals(listOf("amazon.com"), amazonMixed)
        assertEquals(listOf("amazon.com"), amazonLower)
        assertEquals(listOf("slack.com"), slackMixed)
        assertEquals(listOf("slack.com"), slackLower)
    }

    @Test
    fun testPackageAliasMap_strictPrefixOverlapProtection() {
        // com.uber must NOT match com.ubercab
        assertTrue("Prefix overlap com.uber should not map to uber.com",
            MultiPadAutofillService.PackageAliasMap.getDomainsForPackage("com.uber").isEmpty())
        // com.facebook must NOT match com.facebook.katana
        assertTrue("Prefix overlap com.facebook should not map",
            MultiPadAutofillService.PackageAliasMap.getDomainsForPackage("com.facebook").isEmpty())
        // com.google must NOT match com.google.android.youtube
        assertTrue("Prefix com.google should not map",
            MultiPadAutofillService.PackageAliasMap.getDomainsForPackage("com.google").isEmpty())
    }

    // =========================================================================
    // 2. Challenge UrlBar Node Detection
    // =========================================================================

    @Test
    fun testIsUrlBarNode_detectsFirefoxMozacAndStandardBars() {
        val positiveIds = listOf(
            "mozac_browser_toolbar_url_view",
            "mozac_browser_toolbar_edit_url_view",
            "org.mozilla.fenix:id/mozac_browser_toolbar_url_view",
            "url_bar",
            "com.android.chrome:id/url_bar",
            "toolbar_url",
            "url_view",
            "omnibox",
            "location_bar",
            "address_bar",
            "url_field",
            "search_box",
            "display_url"
        )
        for (id in positiveIds) {
            assertTrue("ID '$id' should be detected as url bar node", MultiPadAutofillService.isUrlBarNode(id))
        }

        val negativeIds = listOf(
            "username",
            "password",
            "user_id",
            "login_email",
            "pin_box",
            "otp_field",
            "submit_button",
            null
        )
        for (id in negativeIds) {
            assertFalse("ID '$id' should NOT be detected as url bar node", MultiPadAutofillService.isUrlBarNode(id))
        }
    }

    // =========================================================================
    // 3. Challenge DomainExtractor
    // =========================================================================

    @Test
    fun testDomainExtractor_rejectsInternalSchemesAndWhitespace() {
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("about:blank"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("chrome://flags"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("firefox://settings"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("edge://settings"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("file:///storage/emulated/0/passwords.txt"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("content://downloads/my_passwords"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("javascript:alert(1)"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("google search for bank.com"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("bank.com \t login"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost("   "))
        assertNull(MultiPadAutofillService.DomainExtractor.extractCleanHost(null))
    }

    @Test
    fun testDomainExtractor_parsesHostWithoutScheme() {
        assertEquals("bank.com", MultiPadAutofillService.DomainExtractor.extractCleanHost("bank.com"))
        assertEquals("bank.com", MultiPadAutofillService.DomainExtractor.extractCleanHost("www.bank.com"))
        assertEquals("auth.bank.com", MultiPadAutofillService.DomainExtractor.extractCleanHost("auth.bank.com:8443/login?q=test#hash"))
        assertEquals("localhost", MultiPadAutofillService.DomainExtractor.extractCleanHost("localhost:3000/app"))
        assertEquals("192.168.1.1", MultiPadAutofillService.DomainExtractor.extractCleanHost("192.168.1.1:8080/admin"))
    }

    @Test
    fun testDomainExtractor_rejectsBarePublicSuffixes() {
        // Bare public suffixes like co.uk and github.io must be rejected by DomainExtractor
        // to prevent cross-tenant matching and namespace-wide autofill exposure.
        val coUk = MultiPadAutofillService.DomainExtractor.extractCleanHost("co.uk")
        val githubIo = MultiPadAutofillService.DomainExtractor.extractCleanHost("github.io")
        val comTr = MultiPadAutofillService.DomainExtractor.extractCleanHost("com.tr")
        val pagesDev = MultiPadAutofillService.DomainExtractor.extractCleanHost("pages.dev")
        val vercelApp = MultiPadAutofillService.DomainExtractor.extractCleanHost("vercel.app")

        assertNull("Bare public suffix co.uk should be rejected", coUk)
        assertNull("Bare public suffix github.io should be rejected", githubIo)
        assertNull("Bare public suffix com.tr should be rejected", comTr)
        assertNull("Bare public suffix pages.dev should be rejected", pagesDev)
        assertNull("Bare public suffix vercel.app should be rejected", vercelApp)

        // Valid hosts under public suffixes must be preserved
        assertEquals("amazon.co.uk", MultiPadAutofillService.DomainExtractor.extractCleanHost("amazon.co.uk"))
        assertEquals("amazon.co.uk", MultiPadAutofillService.DomainExtractor.extractCleanHost("https://amazon.co.uk/path"))
        assertEquals("login.amazon.co.uk", MultiPadAutofillService.DomainExtractor.extractCleanHost("https://login.amazon.co.uk/path"))
        assertEquals("user1.github.io", MultiPadAutofillService.DomainExtractor.extractCleanHost("user1.github.io"))
        assertEquals("user1.github.io", MultiPadAutofillService.DomainExtractor.extractCleanHost("https://user1.github.io:8080/demo"))
        assertEquals("mybrand.com.tr", MultiPadAutofillService.DomainExtractor.extractCleanHost("https://mybrand.com.tr"))
    }

    @Test
    fun testDomainExtractor_searchQueryString() {
        // "google.com/search?q=bank.com" extracts the host of the search engine
        val host = MultiPadAutofillService.DomainExtractor.extractCleanHost("google.com/search?q=bank.com")
        assertEquals("google.com", host)
    }

    @Test
    fun testDomainExtractor_jvmFallbackWithScheme() {
        val res = MultiPadAutofillService.DomainExtractor.extractCleanHost("https://auth.bank.com:8443/login?q=test#hash")
        assertEquals("auth.bank.com", res)
        assertEquals("bank.com", MultiPadAutofillService.DomainExtractor.extractCleanHost("https://bank.com"))
        assertEquals("bank.com", MultiPadAutofillService.DomainExtractor.extractCleanHost("http://bank.com/path?foo=1"))
        assertEquals("192.168.1.1", MultiPadAutofillService.DomainExtractor.extractCleanHost("http://192.168.1.1:8080/admin"))
        assertEquals("localhost", MultiPadAutofillService.DomainExtractor.extractCleanHost("http://localhost:3000/app"))
        assertEquals("auth.bank.com", MultiPadAutofillService.DomainExtractor.extractCleanHost("https://user:pass@auth.bank.com:8443/login"))
    }

    @Test
    fun testDomainExtractor_extractETldPlusOne() {
        assertEquals("bank.com", MultiPadAutofillService.DomainExtractor.extractETldPlusOne("auth.bank.com"))
        assertEquals("amazon.co.uk", MultiPadAutofillService.DomainExtractor.extractETldPlusOne("login.amazon.co.uk"))
        assertEquals("user1.github.io", MultiPadAutofillService.DomainExtractor.extractETldPlusOne("api.user1.github.io"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractETldPlusOne("co.uk"))
        assertNull(MultiPadAutofillService.DomainExtractor.extractETldPlusOne("github.io"))
        assertEquals("192.168.1.1", MultiPadAutofillService.DomainExtractor.extractETldPlusOne("192.168.1.1:8080"))
        assertEquals("localhost", MultiPadAutofillService.DomainExtractor.extractETldPlusOne("localhost:3000"))
    }

    // =========================================================================
    // 4. Challenge Split-Field OTP Indexing Math
    // =========================================================================

    @Test
    fun testSplitOtpIndexing_maintainsMonotonicOrderWithoutCollision() {
        fun calculateIndex(idEntry: String, existingSize: Int = 0): Int {
            val indexedMatch = Regex(".*(?:otp|pin|digit|code|box|char)[-_.\\[]?([0-9]+)\\]?$", RegexOption.IGNORE_CASE)
                .find(idEntry)
            return indexedMatch?.groupValues?.getOrNull(1)?.toIntOrNull() ?: existingSize
        }

        // Test standard 0-based field sequence: [otp_0, otp_1, otp_2, otp_3, otp_4, otp_5]
        val zeroBased = listOf("otp_0", "otp_1", "otp_2", "otp_3", "otp_4", "otp_5")
        val zeroBasedIndices = zeroBased.map { calculateIndex(it) }
        assertEquals(listOf(0, 1, 2, 3, 4, 5), zeroBasedIndices)

        // Test standard 1-based field sequence: [otp_1, otp_2, otp_3, otp_4, otp_5, otp_6]
        val oneBased = listOf("otp_1", "otp_2", "otp_3", "otp_4", "otp_5", "otp_6")
        val oneBasedIndices = oneBased.map { calculateIndex(it) }
        assertEquals(listOf(1, 2, 3, 4, 5, 6), oneBasedIndices)

        // Bracketed and dotted format: otp[0]..otp[5], digit.1..digit.6
        val bracketed = listOf("otp[0]", "otp[1]", "otp[2]", "otp[3]", "otp[4]", "otp[5]")
        val bracketedIndices = bracketed.map { calculateIndex(it) }
        assertEquals(listOf(0, 1, 2, 3, 4, 5), bracketedIndices)

        val dotted = listOf("digit.1", "digit.2", "digit.3", "digit.4", "digit.5", "digit.6")
        val dottedIndices = dotted.map { calculateIndex(it) }
        assertEquals(listOf(1, 2, 3, 4, 5, 6), dottedIndices)

        // Out-of-order traversal sorting:
        data class Box(val id: String, val index: Int)
        val outOfOrder = listOf(
            Box("id_3", calculateIndex("otp_3")),
            Box("id_0", calculateIndex("otp_0")),
            Box("id_5", calculateIndex("otp_5")),
            Box("id_1", calculateIndex("otp_1")),
            Box("id_4", calculateIndex("otp_4")),
            Box("id_2", calculateIndex("otp_2"))
        )
        val sorted = outOfOrder.distinctBy { it.id }.sortedBy { it.index }
        assertEquals(listOf("id_0", "id_1", "id_2", "id_3", "id_4", "id_5"), sorted.map { it.id })
    }

    // =========================================================================
    // 5. Challenge Multi-Box OTP Distribution Count Logic
    // =========================================================================

    @Test
    fun testSplitOtpDistribution_sequentialCharacterAssignment() {
        val totp6 = "948201"
        data class MockBox(val id: Int, val index: Int)

        // 6-box form (1-based indices 1..6)
        val boxes1Based = listOf(
            MockBox(101, 1), MockBox(102, 2), MockBox(103, 3),
            MockBox(104, 4), MockBox(105, 5), MockBox(106, 6)
        )
        val sorted6 = boxes1Based.distinctBy { it.id }.sortedBy { it.index }
        val fillCount6 = minOf(sorted6.size, totp6.length)
        val assigned6 = (0 until fillCount6).associate { sorted6[it].id to totp6[it].toString() }
        assertEquals(mapOf(
            101 to "9", 102 to "4", 103 to "8",
            104 to "2", 105 to "0", 106 to "1"
        ), assigned6)

        // 4-box form: fills first 4 characters
        val boxes4 = listOf(MockBox(1, 0), MockBox(2, 1), MockBox(3, 2), MockBox(4, 3))
        val sorted4 = boxes4.distinctBy { it.id }.sortedBy { it.index }
        val fillCount4 = minOf(sorted4.size, totp6.length)
        val assigned4 = (0 until fillCount4).associate { sorted4[it].id to totp6[it].toString() }
        assertEquals(mapOf(1 to "9", 2 to "4", 3 to "8", 4 to "2"), assigned4)

        // 8-box form with 6-digit TOTP: fills first 6 boxes, leaves boxes 6 and 7 unfilled
        val boxes8 = (0 until 8).map { MockBox(it, it) }
        val sorted8 = boxes8.distinctBy { it.id }.sortedBy { it.index }
        val fillCount8 = minOf(sorted8.size, totp6.length)
        assertEquals(6, fillCount8)

        // Duplicate box IDs handled cleanly via distinctBy
        val dupes = listOf(MockBox(1, 0), MockBox(1, 0), MockBox(2, 1), MockBox(3, 2))
        val deduplicated = dupes.distinctBy { it.id }.sortedBy { it.index }
        assertEquals(3, deduplicated.size)
    }
}
