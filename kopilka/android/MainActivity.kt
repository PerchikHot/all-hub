package com.veyrion.kopilka_app
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kopilka/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "enabled" -> {
                        val listeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
                        // Match the exact listener component, not a substring of
                        // another application's package name.
                        val enabled = listeners.split(':').any { entry ->
                            val component = ComponentName.unflattenFromString(entry.trim())
                            component != null &&
                                component.packageName == packageName &&
                                component.className == BankNotificationService::class.java.name
                        }
                        result.success(enabled)
                    }
                    "pending" -> {
                        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
                        result.success(prefs.getString("queue", "[]"))
                    }
                    "diagnostics" -> {
                        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
                        val count = try {
                            org.json.JSONArray(prefs.getString("queue", "[]")).length()
                        } catch (_: Exception) { 0 }
                        result.success(mapOf(
                            "queued" to count,
                            "accepted" to prefs.getInt("accepted_count", 0),
                            "filtered" to prefs.getInt("filtered_count", 0),
                            "lastSeen" to prefs.getLong("last_seen", 0L),
                            "lastBank" to (prefs.getString("last_bank", "") ?: ""),
                            "connected" to prefs.getBoolean("listener_connected", false),
                            "lastConnected" to prefs.getLong("last_connected", 0L),
                            "bankEvents" to mapOf(
                                "Т-Банк" to prefs.getInt("bank_count_tbank", 0),
                                "Газпромбанк" to prefs.getInt("bank_count_gazprom", 0),
                                "Ozon Банк" to prefs.getInt("bank_count_ozon", 0)
                            ),
                            "bankAccepted" to mapOf(
                                "Т-Банк" to prefs.getInt("bank_accepted_tbank", 0),
                                "Газпромбанк" to prefs.getInt("bank_accepted_gazprom", 0),
                                "Ozon Банк" to prefs.getInt("bank_accepted_ozon", 0)
                            ),
                            "bankFiltered" to mapOf(
                                "Т-Банк" to prefs.getInt("bank_filtered_tbank", 0),
                                "Газпромбанк" to prefs.getInt("bank_filtered_gazprom", 0),
                                "Ozon Банк" to prefs.getInt("bank_filtered_ozon", 0)
                            ),
                            "bankLastSeen" to mapOf(
                                "Т-Банк" to prefs.getLong("bank_last_tbank", 0L),
                                "Газпромбанк" to prefs.getLong("bank_last_gazprom", 0L),
                                "Ozon Банк" to prefs.getLong("bank_last_ozon", 0L)
                            )
                        ))
                    }
                    "dismiss" -> {
                        val key = call.argument<String>("key")
                        if (key.isNullOrBlank()) {
                            result.error("ARGUMENT", "Missing notification key", null)
                        } else {
                            val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
                            try {
                                val current = org.json.JSONArray(prefs.getString("queue", "[]"))
                                val remaining = org.json.JSONArray()
                                for (i in 0 until current.length()) {
                                    val item = current.getJSONObject(i)
                                    if (item.optString("key") != key) remaining.put(item)
                                }
                                prefs.edit().putString("queue", remaining.toString()).apply()
                                result.success(null)
                            } catch (_: Exception) {
                                result.error("QUEUE", "Cannot update local notification queue", null)
                            }
                        }
                    }
                    "clear" -> {
                        getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
                            .edit().remove("queue").apply()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
