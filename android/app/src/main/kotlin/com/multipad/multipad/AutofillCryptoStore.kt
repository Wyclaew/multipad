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

/**
 * Encrypts the cached Android Autofill index using an Android Keystore AES-256-GCM key
 * so plaintext credentials are never persisted on disk.
 */
object AutofillCryptoStore {
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "multipad_autofill_ks_key_v1"
    private const val PREFS_NAME = "multipad_autofill_store"
    private const val PREF_CIPHERTEXT = "encrypted_index_v1"
    private const val PREF_IV = "encrypted_index_iv_v1"

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

    fun saveEntries(context: Context, entries: List<Map<String, Any?>>) {
        val array = JSONArray()
        for (raw in entries) {
            val obj = JSONObject()
            obj.put("id", raw["id"]?.toString() ?: "")
            obj.put("title", raw["title"]?.toString() ?: "")
            obj.put("website", raw["website"]?.toString() ?: "")
            obj.put("username", raw["username"]?.toString() ?: "")
            obj.put("password", raw["password"]?.toString() ?: "")
            obj.put("totpSecret", raw["totpSecret"]?.toString() ?: "")
            array.put(obj)
        }

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
    }

    fun clearEntries(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }

    fun loadEntries(context: Context): List<AutofillCredentialEntry> {
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
            result
        } catch (_: Exception) {
            emptyList()
        }
    }
}
