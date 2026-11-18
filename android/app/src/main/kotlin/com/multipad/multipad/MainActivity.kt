package com.multipad.multipad

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "com.multipad.multipad/native"
        const val EXTRA_MULTIPAD_ACTION = "multipad_action"
        const val ACTION_QUICK_SEARCH = "quick_search"
    }

    private var multicastLock: WifiManager.MulticastLock? = null
    private var methodChannel: MethodChannel? = null
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isFlagSecureEnabled = prefs.getBoolean("flutter.multipad_flag_secure_enabled", true)
        if (isFlagSecureEnabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        captureLaunchAction(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) {
            intent.removeExtra(EXTRA_MULTIPAD_ACTION)
            return
        }
        val action = intent.getStringExtra(EXTRA_MULTIPAD_ACTION)
        if (action == ACTION_QUICK_SEARCH) {
            intent.removeExtra(EXTRA_MULTIPAD_ACTION)
            val channel = methodChannel
            if (channel != null) {
                channel.invokeMethod(
                    "onQuickSearchRequested",
                    null,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {}
                        override fun error(
                            errorCode: String,
                            errorMessage: String?,
                            errorDetails: Any?,
                        ) {}
                        override fun notImplemented() {
                            pendingAction = action
                        }
                    },
                )
            } else {
                pendingAction = action
            }
        }
    }

    private fun captureLaunchAction(launchIntent: Intent?) {
        if (launchIntent == null) return
        if ((launchIntent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) {
            launchIntent.removeExtra(EXTRA_MULTIPAD_ACTION)
            return
        }
        val action = launchIntent.getStringExtra(EXTRA_MULTIPAD_ACTION)
        if (action == ACTION_QUICK_SEARCH) {
            pendingAction = action
            launchIntent.removeExtra(EXTRA_MULTIPAD_ACTION)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureLaunchAction(intent)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumePendingLaunchAction" -> {
                        val action = pendingAction
                        pendingAction = null
                        result.success(action)
                    }

                    "setFlagSecure" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        runOnUiThread {
                            if (enabled) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(true)
                    }

                    "copyConfidential" -> {
                        val text = call.argument<String>("text") ?: ""
                        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val clip = ClipData.newPlainText("MultiPad", text)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            clip.description.extras = PersistableBundle().apply {
                                putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                            }
                        }
                        clipboard.setPrimaryClip(clip)
                        result.success(true)
                    }

                    "setMulticastLock" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        try {
                            if (enabled) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                                if (multicastLock == null && wifi != null) {
                                    multicastLock = wifi.createMulticastLock("MultiPadPairingLock").apply {
                                        setReferenceCounted(false)
                                    }
                                }
                                if (multicastLock?.isHeld == false) {
                                    multicastLock?.acquire()
                                }
                            } else {
                                if (multicastLock?.isHeld == true) {
                                    multicastLock?.release()
                                }
                            }
                        } catch (_: Exception) {
                            // Ignore device-specific multicast lock restrictions
                        }
                        result.success(true)
                    }

                    "updateAutofillIndex" -> {
                        val entries = call.argument<List<Map<String, Any?>>>("entries") ?: emptyList()
                        AutofillCryptoStore.saveEntries(applicationContext, entries)
                        result.success(true)
                    }

                    "clearAutofillIndex" -> {
                        AutofillCryptoStore.clearEntries(applicationContext)
                        result.success(true)
                    }

                    "getPendingAutofillCredentials" -> {
                        try {
                            val list = AutofillCryptoStore.getPendingCredentials(this)
                            val mapped = list.map { entry ->
                                mapOf(
                                    "id" to entry.id,
                                    "title" to entry.title,
                                    "website" to entry.website,
                                    "username" to entry.username,
                                    "password" to entry.password,
                                    "packageName" to entry.packageName,
                                    "timestamp" to entry.timestamp,
                                )
                            }
                            result.success(mapped)
                        } catch (e: Exception) {
                            result.error("GET_PENDING_ERROR", e.localizedMessage ?: e.toString(), null)
                        }
                    }

                    "clearPendingAutofillCredentials" -> {
                        try {
                            AutofillCryptoStore.clearPendingCredentials(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CLEAR_PENDING_ERROR", e.localizedMessage ?: e.toString(), null)
                        }
                    }

                    "openAutofillSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            try {
                                val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                                    data = Uri.parse("package:$packageName")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                            } catch (_: Exception) {
                                startActivity(
                                    Intent(Settings.ACTION_SETTINGS).apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    },
                                )
                            }
                        }
                        result.success(true)
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK dosya yolu boş.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(path)
                            if (!file.exists()) {
                                result.error("NOT_FOUND", "APK dosyası bulunamadı.", null)
                                return@setMethodCallHandler
                            }

                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()
                            ) {
                                val permIntent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                    data = Uri.parse("package:$packageName")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(permIntent)
                                result.error(
                                    "PERMISSION_REQUIRED",
                                    "Bilinmeyen kaynaklardan uygulama yükleme izni gerekli; izin verdikten sonra tekrar dokunun.",
                                    null,
                                )
                                return@setMethodCallHandler
                            }

                            val uri = FileProvider.getUriForFile(
                                applicationContext,
                                "$packageName.fileprovider",
                                file,
                            )
                            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(installIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.localizedMessage ?: e.toString(), null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
