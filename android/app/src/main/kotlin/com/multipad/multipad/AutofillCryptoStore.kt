package com.multipad.multipad

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.util.ArrayList
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

data class AutofillCredentialEntry(
    val id: String,
    val title: String,
    val website: String,
    val username: String,
    val password: String,
    val totpSecret: String,
)

data class PendingCredentialEntry(
    val id: String,
    val title: String,
    val website: String,
    val username: String,
    val password: String,
    val packageName: String,
    val timestamp: Long = System.currentTimeMillis(),
)

/**
 * Thread-safe encrypted storage for Android Autofill cached index and pending credentials
 * captured during onSaveRequest, secured using Android Keystore AES-256-GCM.
 */
object AutofillCryptoStore {
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "multipad_autofill_ks_key_v1"
    private const val PREFS_NAME = "multipad_autofill_store"
    private const val PREF_CIPHERTEXT = "encrypted_index_v1"
    private const val PREF_IV = "encrypted_index_iv_v1"
    private const val PREF_PENDING_CIPHERTEXT = "encrypted_pending_v1"
    private const val PREF_PENDING_IV = "encrypted_pending_iv_v1"

    private val lock = Any()
    private val inMemoryEntries = ArrayList<AutofillCredentialEntry>()
    private val inMemoryPending = ArrayList<PendingCredentialEntry>()

    private fun getOrCreateKey(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        val existing = ks.getKey(KEY_ALIAS, null) as? SecretKey
        if (existing != null) return existing

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER,
        )
        val specBuilder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setRandomizedEncryptionRequired(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            specBuilder.setInvalidatedByBiometricEnrollment(false)
        }

        keyGenerator.init(specBuilder.build())
        return keyGenerator.generateKey()
    }

    fun saveEntries(context: Context, entries: List<Map<String, Any?>>) = synchronized(lock) {
        val array = JSONArray()
        inMemoryEntries.clear()
        for (raw in entries) {
            val id = raw["id"]?.toString() ?: ""
            val title = raw["title"]?.toString() ?: ""
            val website = raw["website"]?.toString() ?: ""
            val username = raw["username"]?.toString() ?: ""
            val password = raw["password"]?.toString() ?: ""
            val totpSecret = raw["totpSecret"]?.toString() ?: ""

            val obj = JSONObject().apply {
                put("id", id)
                put("title", title)
                put("website", website)
                put("username", username)
                put("password", password)
                put("totpSecret", totpSecret)
            }
            array.put(obj)
            inMemoryEntries.add(
                AutofillCredentialEntry(
                    id = id,
                    title = title,
                    website = website,
                    username = username,
                    password = password,
                    totpSecret = totpSecret,
                )
            )
        }

        try {
            val plaintext = array.toString().toByteArray(StandardCharsets.UTF_8)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            val encryptedBytes = cipher.doFinal(plaintext)
            val iv = cipher.iv

            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_CIPHERTEXT, Base64.encodeToString(encryptedBytes, Base64.NO_WRAP))
                .putString(PREF_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
                .apply()
        } catch (e: Exception) {
            android.util.Log.e("AutofillCryptoStore", "Error in keystore/storage operation", e)
        }
    }

    fun addEntry(context: Context, entry: AutofillCredentialEntry) = synchronized(lock) {
        val current = ArrayList(loadEntries(context))
        current.removeAll { it.id == entry.id }
        current.add(entry)
        val mapped = current.map {
            mapOf<String, Any?>(
                "id" to it.id,
                "title" to it.title,
                "website" to it.website,
                "username" to it.username,
                "password" to it.password,
                "totpSecret" to it.totpSecret,
            )
        }
        saveEntries(context, mapped)
    }

    fun clearEntries(context: Context) = synchronized(lock) {
        inMemoryEntries.clear()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(PREF_CIPHERTEXT)
            .remove(PREF_IV)
            .apply()
    }

    fun loadEntries(context: Context): List<AutofillCredentialEntry> = synchronized(lock) {
        if (inMemoryEntries.isNotEmpty()) {
            return ArrayList(inMemoryEntries)
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val ctB64 = prefs.getString(PREF_CIPHERTEXT, null) ?: return emptyList()
        val ivB64 = prefs.getString(PREF_IV, null) ?: return emptyList()

        return try {
            val ct = Base64.decode(ctB64, Base64.DEFAULT)
            val iv = Base64.decode(ivB64, Base64.DEFAULT)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
            val plainBytes = cipher.doFinal(ct)
            val json = JSONArray(String(plainBytes, StandardCharsets.UTF_8))

            val result = ArrayList<AutofillCredentialEntry>(json.length())
            for (i in 0 until json.length()) {
                val obj = json.getJSONObject(i)
                result.add(
                    AutofillCredentialEntry(
                        id = obj.optString("id"),
                        title = obj.optString("title"),
                        website = obj.optString("website"),
                        username = obj.optString("username"),
                        password = obj.optString("password"),
                        totpSecret = obj.optString("totpSecret"),
                    ),
                )
            }
            inMemoryEntries.clear()
            inMemoryEntries.addAll(result)
            ArrayList(result)
        } catch (e: Exception) {
            android.util.Log.e("AutofillCryptoStore", "Error loading entries from keystore/storage", e)
            emptyList()
        }
    }

    // --- Pending Credentials from Autofill Save ---

    fun savePendingCredential(context: Context, pending: PendingCredentialEntry) = synchronized(lock) {
        val list = ArrayList(getPendingCredentials(context))
        list.removeAll { it.username == pending.username && (it.website == pending.website || it.packageName == pending.packageName) }
        list.add(0, pending)
        if (list.size > 20) {
            list.subList(20, list.size).clear()
        }
        inMemoryPending.clear()
        inMemoryPending.addAll(list)

        val array = JSONArray()
        for (item in list) {
            array.put(JSONObject().apply {
                put("id", item.id)
                put("title", item.title)
                put("website", item.website)
                put("username", item.username)
                put("password", item.password)
                put("packageName", item.packageName)
                put("timestamp", item.timestamp)
            })
        }

        try {
            val plaintext = array.toString().toByteArray(StandardCharsets.UTF_8)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            val encryptedBytes = cipher.doFinal(plaintext)
            val iv = cipher.iv

            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(PREF_PENDING_CIPHERTEXT, Base64.encodeToString(encryptedBytes, Base64.NO_WRAP))
                .putString(PREF_PENDING_IV, Base64.encodeToString(iv, Base64.NO_WRAP))
                .apply()
        } catch (e: Exception) {
            android.util.Log.e("AutofillCryptoStore", "Error in keystore/storage operation", e)
        }
    }

    fun getPendingCredentials(context: Context): List<PendingCredentialEntry> = synchronized(lock) {
        if (inMemoryPending.isNotEmpty()) {
            return ArrayList(inMemoryPending)
        }

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val ctB64 = prefs.getString(PREF_PENDING_CIPHERTEXT, null) ?: return emptyList()
        val ivB64 = prefs.getString(PREF_PENDING_IV, null) ?: return emptyList()

        return try {
            val ct = Base64.decode(ctB64, Base64.DEFAULT)
            val iv = Base64.decode(ivB64, Base64.DEFAULT)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
            val plainBytes = cipher.doFinal(ct)
            val json = JSONArray(String(plainBytes, StandardCharsets.UTF_8))

            val result = ArrayList<PendingCredentialEntry>(json.length())
            for (i in 0 until json.length()) {
                val obj = json.getJSONObject(i)
                result.add(
                    PendingCredentialEntry(
                        id = obj.optString("id"),
                        title = obj.optString("title"),
                        website = obj.optString("website"),
                        username = obj.optString("username"),
                        password = obj.optString("password"),
                        packageName = obj.optString("packageName"),
                        timestamp = obj.optLong("timestamp", System.currentTimeMillis()),
                    ),
                )
            }
            inMemoryPending.clear()
            inMemoryPending.addAll(result)
            ArrayList(result)
        } catch (e: Exception) {
            android.util.Log.e("AutofillCryptoStore", "Error loading pending credentials from keystore/storage", e)
            emptyList()
        }
    }

    fun clearPendingCredentials(context: Context) = synchronized(lock) {
        inMemoryPending.clear()
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(PREF_PENDING_CIPHERTEXT)
            .remove(PREF_PENDING_IV)
            .apply()
    }
}
