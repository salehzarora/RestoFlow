package com.restoflow.pos

import android.content.Context
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Separate status-only capability. Never reads pairing/PIN or FlutterSecureStorage. */
internal class BackgroundOrderAlertVault(private val context: Context) {
    private val preferences = context.getSharedPreferences("bizbot_order_alert_status_v1", Context.MODE_PRIVATE)
    private val alias = "bizbot_pos_order_alert_status_v1"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
        }.generateKey()
    }

    fun bootCount(): Int = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)

    fun read(): JSONObject? = try {
        val raw = preferences.getString("sealed", null)
        if (raw == null) null else {
            val envelope = JSONObject(raw)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(envelope.getString("iv"), Base64.NO_WRAP)))
            JSONObject(String(cipher.doFinal(Base64.decode(envelope.getString("body"), Base64.NO_WRAP)), Charsets.UTF_8))
        }
    } catch (_: Exception) { null }

    fun write(value: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val envelope = JSONObject()
            .put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("body", Base64.encodeToString(cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8)), Base64.NO_WRAP))
        check(preferences.edit().putString("sealed", envelope.toString()).commit())
    }

    fun clear() {
        // Destroy this independent status-only key first: stale ciphertext cannot regain authority after logout.
        KeyStore.getInstance("AndroidKeyStore").apply { load(null); if (containsAlias(alias)) deleteEntry(alias) }
        if (!preferences.edit().clear().commit()) check(context.deleteSharedPreferences("bizbot_order_alert_status_v1"))
    }
}
