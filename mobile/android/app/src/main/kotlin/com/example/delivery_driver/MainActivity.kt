package com.example.delivery_driver

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native Android entry point.
 *
 * Exposes two platform-specific actions over the `delivery.driver/native`
 * channel that are awkward to do from Dart alone:
 *
 *  - `openNavigation`: deep-links into the driver's turn-by-turn navigation app
 *    (Google Navigation intent, falling back to a Maps directions URL).
 *  - `shareText`: opens the system share sheet so the driver can hand a prepared
 *    message to WhatsApp/SMS/e-mail without copy-pasting.
 *
 * The Dart side degrades gracefully when a method is missing.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "delivery.driver/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> result.success(true)

                    "openNavigation" -> {
                        val lat = call.argument<Double>("lat")
                        val lng = call.argument<Double>("lng")
                        val label = call.argument<String>("label") ?: "Destination"

                        if (lat == null || lng == null) {
                            result.error("BAD_ARGS", "lat/lng are required", null)
                            return@setMethodCallHandler
                        }
                        result.success(openNavigation(lat, lng, label))
                    }

                    "shareText" -> {
                        val text = call.argument<String>("text")
                        if (text.isNullOrBlank()) {
                            result.error("BAD_ARGS", "text is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(shareText(text))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** @return true when an external app was opened for the driver. */
    private fun openNavigation(lat: Double, lng: Double, label: String): Boolean {
        val navigationUri = Uri.parse("google.navigation:q=$lat,$lng")
        val fallbackUri = Uri.parse(
            "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving"
        )

        val primary = Intent(Intent.ACTION_VIEW, navigationUri).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            `package` = "com.google.android.apps.maps"
        }

        return try {
            startActivity(primary)
            true
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, fallbackUri).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                true
            } catch (_: ActivityNotFoundException) {
                false
            }
        } catch (_: SecurityException) {
            false
        }.also { opened ->
            if (opened) logLabel(label)
        }
    }

    /** @return true when the share sheet was presented. */
    private fun shareText(text: String): Boolean {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        return try {
            startActivity(Intent.createChooser(send, "Share message"))
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    private fun logLabel(label: String) {
        // Kept intentionally quiet in release builds; useful while developing.
        android.util.Log.d(TAG, "Navigation opened for $label")
    }

    private companion object {
        const val TAG = "DeliveryDriver"
    }
}
