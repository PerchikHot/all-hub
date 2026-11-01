package com.veyrion.kopilka_app
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // A user-controlled Android permission, not proof that the service is
    // currently connected or that any bank has posted a notification.
    private fun isListenerPermissionGranted(): Boolean {
        val listeners = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners") ?: ""
        return listeners.split(':').any { entry ->
            val component = ComponentName.unflattenFromString(entry.trim())
            component != null &&
                component.packageName == packageName &&
                component.className == BankNotificationService::class.java.name
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kopilka/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "enabled" -> result.success(isListenerPermissionGranted())
                    "pending" -> {
                        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
                        synchronized(BankNotificationService.queueLock) {
                            result.success(prefs.getString("queue", "[]"))
                        }
                    }
                    "diagnostics" -> {
                        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
                        val count = try {
                            org.json.JSONArray(prefs.getString("queue", "[]")).length()
                        } catch (_: Exception) { 0 }
                        result.success(mapOf(
                            "queued" to count,
                            "queueCapacity" to BankNotificationService.MAX_PENDING,
                            "queueRemaining" to (BankNotificationService.MAX_PENDING - count).coerceAtLeast(0),
                            "accepted" to prefs.getInt("accepted_count", 0),
                            "filtered" to prefs.getInt("filtered_count", 0),
                            "lastSeen" to prefs.getLong("last_seen", 0L),
                            "lastBank" to (prefs.getString("last_bank", "") ?: ""),
                            "permissionGranted" to isListenerPermissionGranted(),
                            "connected" to prefs.getBoolean("listener_connected", false),
                            "lastAccepted" to prefs.getLong("last_accepted", 0L),
                            "lastAcceptedBank" to (prefs.getString("last_accepted_bank", "") ?: ""),
                            "lastSkipped" to prefs.getLong("last_skipped", 0L),
                            // Fixed category only. Never expose rejected notification text.
                            "lastSkipReason" to (prefs.getString("last_skip_reason", "") ?: ""),
                            "lastConnected" to prefs.getLong("last_connected", 0L),
                            "lastDisconnected" to prefs.getLong("last_disconnected", 0L),
                            "lastRecoveryScan" to prefs.getLong("last_recovery_scan", 0L),
                            "recoveryCandidates" to prefs.getInt("recovery_candidates", 0),
                            "rebindRequests" to prefs.getInt("rebind_requests", 0),
                            "queueRecoveries" to prefs.getInt("queue_recoveries", 0),
                            "queueCorrupt" to prefs.getBoolean("queue_corrupt", false),
                            "queueDropped" to prefs.getInt("queue_dropped", 0),
                            "queueFullRejections" to prefs.getInt("queue_full_rejections", 0),
                            "lastQueueDrop" to prefs.getLong("last_queue_drop", 0L),
                            "lastQueueWriteFailed" to prefs.getLong("last_queue_write_failed", 0L),
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
                            synchronized(BankNotificationService.queueLock) {
                            try {
                                val current = org.json.JSONArray(prefs.getString("queue", "[]"))
                                val remaining = org.json.JSONArray()
                                for (i in 0 until current.length()) {
                                    val item = current.getJSONObject(i)
                                    if (item.optString("key") != key) remaining.put(item)
                                }
                                // Persist both the removal and a bounded replay
                                // tombstone atomically. Active Android notifications
                                // can be delivered again after a listener reconnect.
                                val previous = org.json.JSONArray(
                                    prefs.getString("acknowledged", "[]"))
                                val acknowledgements = org.json.JSONArray()
                                for (i in maxOf(0, previous.length() - 999) until previous.length()) {
                                    val oldKey = previous.optString(i)
                                    if (oldKey.isNotBlank() && oldKey != key) {
                                        acknowledgements.put(oldKey)
                                    }
                                }
                                acknowledgements.put(key)
                                if (prefs.edit().putString("queue", remaining.toString())
                                        .putString("acknowledged", acknowledgements.toString())
                                        .commit()) {
                                    result.success(null)
                                } else {
                                    result.error("QUEUE", "Cannot persist notification acknowledgement", null)
                                }
                            } catch (_: Exception) {
                                result.error("QUEUE", "Cannot update local notification queue", null)
                            }
                            }
                        }
                    }
                    "clear" -> {
                        synchronized(BankNotificationService.queueLock) {
                            val cleared = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
                                .edit().remove("queue").putBoolean("queue_corrupt", false).commit()
                            if (cleared) result.success(null)
                            else result.error("QUEUE", "Cannot clear local notification queue", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
