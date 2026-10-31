package org.ceiling.ceiling_calculator

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** FragmentActivity so [registerForActivityResult] is available for AR scan. */
class MainActivity : FlutterFragmentActivity() {
    private var pendingScanResult: MethodChannel.Result? = null

    private val arScanLauncher =
        registerForActivityResult(androidx.activity.result.contract.ActivityResultContracts.StartActivityForResult()) { activityResult ->
            val pending = pendingScanResult
            pendingScanResult = null
            if (pending == null) return@registerForActivityResult
            if (activityResult.resultCode == RESULT_OK) {
                val json = activityResult.data?.getStringExtra(ArCornerScanActivity.EXTRA_WALLS_JSON)
                val walls = parseWallsJson(json)
                if (walls != null && walls.size >= 3) {
                    pending.success(walls)
                } else {
                    pending.success(null)
                }
            } else {
                pending.success(null)
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.ceiling/app_update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "path required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        installApk(path)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.ceiling/geometry_capture",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isArCoreAvailable" -> {
                    result.success(isArCoreDeviceSupported())
                }
                "arCoreAvailability" -> {
                    result.success(arCoreAvailabilityCode())
                }
                "ensureArCoreInstalled" -> {
                    ensureArCoreInstalled(result)
                }
                "openArCorePlayStore" -> {
                    result.success(openArCorePlayStore())
                }
                "startArRoomScan" -> {
                    when (arCoreAvailabilityCode()) {
                        "unsupported" -> {
                            openArCorePlayStore()
                            result.error(
                                "unsupported",
                                "Устройство без ARCore или сервисы не установлены — открыт Play Маркет",
                                null,
                            )
                            return@setMethodCallHandler
                        }
                        "not_installed" -> {
                            // Launch scan activity — it will request install, or we open store.
                        }
                    }
                    if (pendingScanResult != null) {
                        result.error("busy", "Scan already in progress", null)
                        return@setMethodCallHandler
                    }
                    try {
                        pendingScanResult = result
                        arScanLauncher.launch(Intent(this, ArCornerScanActivity::class.java))
                    } catch (e: Exception) {
                        pendingScanResult = null
                        openArCorePlayStore()
                        result.error(
                            "launch_failed",
                            e.message ?: "Не удалось открыть AR — проверьте Play Services for AR",
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isArCoreDeviceSupported(): Boolean {
        return when (arCoreAvailabilityCode()) {
            "installed", "not_installed" -> true
            else -> false
        }
    }

    private fun arCoreAvailabilityCode(): String {
        return try {
            var availability = ArCoreApk.getInstance().checkAvailability(this)
            // First check can be transient while Play Services answers.
            if (availability.isTransient) {
                try {
                    Thread.sleep(250)
                } catch (_: InterruptedException) {
                }
                availability = ArCoreApk.getInstance().checkAvailability(this)
            }
            when (availability) {
                ArCoreApk.Availability.SUPPORTED_INSTALLED -> "installed"
                ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD,
                ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> "not_installed"
                // Unknown: prefer install/store path over hard-block (sideload / OEM lag).
                ArCoreApk.Availability.UNKNOWN_CHECKING,
                ArCoreApk.Availability.UNKNOWN_ERROR,
                ArCoreApk.Availability.UNKNOWN_TIMED_OUT -> "not_installed"
                else -> "unsupported"
            }
        } catch (_: Exception) {
            "not_installed"
        }
    }

    private fun ensureArCoreInstalled(result: MethodChannel.Result) {
        try {
            when (ArCoreApk.getInstance().requestInstall(this, true)) {
                ArCoreApk.InstallStatus.INSTALL_REQUESTED ->
                    result.success("installing")
                ArCoreApk.InstallStatus.INSTALLED ->
                    result.success("ready")
                else -> result.success("ready")
            }
        } catch (e: Exception) {
            openArCorePlayStore()
            result.success("error:${e.message}")
        }
    }

    /** Opens Google Play Services for AR; returns true if an intent was fired. */
    private fun openArCorePlayStore(): Boolean {
        val market = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("market://details?id=com.google.ar.core"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val web = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://play.google.com/store/apps/details?id=com.google.ar.core"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(market)
            true
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(web)
                true
            } catch (_: Exception) {
                false
            }
        } catch (_: Exception) {
            try {
                startActivity(web)
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalStateException("APK not found: $path")
        }
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // FileProvider URI already set
            }
        }
        startActivity(intent)
    }

    private fun parseWallsJson(json: String?): List<List<Double>>? {
        if (json.isNullOrBlank()) return null
        return try {
            val root = org.json.JSONArray(json)
            val out = mutableListOf<List<Double>>()
            for (i in 0 until root.length()) {
                val w = root.getJSONArray(i)
                if (w.length() < 4) continue
                out.add(listOf(w.getDouble(0), w.getDouble(1), w.getDouble(2), w.getDouble(3)))
            }
            if (out.size >= 3) out else null
        } catch (_: Exception) {
            null
        }
    }
}
