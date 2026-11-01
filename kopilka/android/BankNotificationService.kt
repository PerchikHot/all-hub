package com.veyrion.kopilka_app
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.app.Notification
import android.content.ComponentName
import org.json.JSONArray
import org.json.JSONObject

class BankNotificationService : NotificationListenerService() {
    companion object {
        // The Flutter UI and listener share a process and must not lose
        // newly posted payments while the user dismisses an older alert.
        val queueLock = Any()
        // Retain more payments while the Flutter dashboard is closed. This
        // remains bounded to avoid unlimited private notification storage.
        const val MAX_PENDING = 500
    }
    override fun onListenerConnected() {
        super.onListenerConnected()
        getSharedPreferences("kopilka_notifications", MODE_PRIVATE).edit()
            .putBoolean("listener_connected", true)
            .putLong("last_connected", System.currentTimeMillis()).apply()
        // Android can reconnect the listener after process death. Recover only
        // currently visible, recent bank alerts; the normal privacy gate and
        // durable queue deduplication are reused for every recovered event.
        // This cannot recover notifications already dismissed by the user.
        val now = System.currentTimeMillis()
        val active = try {
            activeNotifications?.asList().orEmpty()
        } catch (_: SecurityException) {
            emptyList()
        } catch (_: RuntimeException) {
            emptyList()
        }
        val candidates = active.asSequence()
            .filter { it.packageName == "com.idamob.tinkoff.android" ||
                it.packageName == "ru.gazprombank.android.mobilebank.app" ||
                it.packageName == "ru.ozon.fintech.finance" }
            .filter { it.postTime in (now - 24L * 60L * 60L * 1000L)..(now + 5L * 60L * 1000L) }
            .take(100).toList()
        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
        prefs.edit().putLong("last_recovery_scan", now)
            .putInt("recovery_candidates", candidates.size).apply()
        candidates.forEach { onNotificationPosted(it) }
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val lastRequest = prefs.getLong("last_rebind_request", 0L)
        prefs.edit().putBoolean("listener_connected", false)
            .putLong("last_disconnected", now).apply()
        // Official Android rebind request only. It never grants notification
        // access or bypasses the user's system permission. Throttle requests
        // to avoid loops when the service is deliberately disabled.
        if (now >= lastRequest && now - lastRequest >= 60_000L) {
            prefs.edit().putLong("last_rebind_request", now)
                .putInt("rebind_requests",
                    (prefs.getInt("rebind_requests", 0) + 1)
                        .coerceAtMost(100000000)).apply()
            try {
                NotificationListenerService.requestRebind(
                    ComponentName(this, BankNotificationService::class.java))
            } catch (_: SecurityException) {
                // The user may have revoked access. Keep diagnostics only.
            }
        }
    }

    // Diagnostics are counters only. Filtered notifications, including
    // one-time codes, never enter the import queue or diagnostic logs.
    private fun markFiltered(bankId: String, reason: String) {
        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
        prefs.edit()
            .putInt("filtered_count",
                (prefs.getInt("filtered_count", 0) + 1).coerceAtMost(100000000))
            .putInt("bank_filtered_" + bankId,
                (prefs.getInt("bank_filtered_" + bankId, 0) + 1)
                    .coerceAtMost(100000000))
            // Only a fixed diagnostic category, never the notification body.
            .putString("last_skip_reason", reason)
            .putLong("last_skipped", System.currentTimeMillis())
            .apply()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val (bank, bankId) = when (sbn.packageName) {
            "com.idamob.tinkoff.android" -> Pair("Т-Банк", "tbank")
            "ru.gazprombank.android.mobilebank.app" -> Pair("Газпромбанк", "gazprom")
            "ru.ozon.fintech.finance" -> Pair("Ozon Банк", "ozon")
            else -> return
        }
        // Record only metadata for the diagnostic screen, not the
        // notification text or login codes.
        val listenerPrefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
        // Count all observed supported-bank events without saving
        // their text. These diagnostics work even for OTP or balance
        // notifications that are intentionally excluded from import.
        val now = System.currentTimeMillis()
        listenerPrefs.edit().putLong("last_seen", now)
            .putString("last_bank", bank)
            .putLong("bank_last_" + bankId, now)
            .putInt("bank_count_" + bankId,
                (listenerPrefs.getInt("bank_count_" + bankId, 0) + 1)
                    .coerceAtMost(100000000)).apply()
        // Group summaries are duplicates, not individual payments.
        if ((sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) {
            markFiltered(bankId, "group_summary")
            return
        }
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val normalText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val expandedText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val body = if (expandedText.isNotBlank()) expandedText else normalText
        // Never persist oversized or malformed notification payloads.
        if (body.isBlank() || body.length > 2048 || title.length > 200) {
            markFiltered(bankId, "invalid_payload")
            return
        }
        // Store transaction alerts only. Never retain OTP/login codes,
        // promotions or balance-only notifications in the local queue.
        val combined = title + " " + body
        val transaction = Regex(
            """покупк|оплат|оплач|плат[её]ж|списан|перевод|поступ|зачисл|пополн|возврат|кэшбэк|кешбэк|сняти|выдач|purchase|payment|transfer|refund|credited|deposit|withdraw""",
            RegexOption.IGNORE_CASE)
        val currency = Regex("""₽|руб(?:\.|ль|ля|лей)?|\bRUB\b""", RegexOption.IGNORE_CASE)
        val sensitive = Regex(
            """код\s+(?:подтверждения|входа|для\s+(?:входа|подтверждения)|операции|из\s+смс)|(?:sms|смс)[-\s]*код|одноразов(?:ый|ого)\s+код|никому\s+не\s+сообщайте|verification\s+code|one[- ]time\s+(?:password|code)|\bOTP\b""",
            RegexOption.IGNORE_CASE)
        // The native queue must reject unposted payments and
        // credential alerts BEFORE storing their text on disk.
        val notPosted = Regex(
            """отклон[её]н|не\s+(?:выполнен|прошл[ао]|провед[её]н|подтвержд[её]н|заверш[её]н)|неуспешн|отмен[её]н|недостаточн[а-яё]*\s+средств|ожида[её]т\s+подтверждени|в\s+обработк|запланирован[а-яё]*|ожидается\s+(?:завтра|послезавтра)|будет\s+списан|declined|rejected|failed|cancelled|canceled|pending|processing|scheduled|upcoming|insufficient\s+funds|\bblocked\b|\bsuspended\b|требует\s+подтверждени|подтвердите\s+(?:операцию|плат[её]ж|перевод|оплату)|requires\s+confirmation|authorization\s+required|\bwill\s+be\s+(?:charged|debited|paid)\b""",
            RegexOption.IGNORE_CASE)
        // Keep the native privacy filter aligned with the Dart
        // review gate: never persist text of unposted payments.
        val additionalUnposted = Regex(
            """не\s+(?:одобрен[а-яё]*|состоял[а-яё]*)|отказан[а-яё]*|ошибка\s+(?:оплаты|перевода)|заблокирован[а-яё]*|приостановлен[а-яё]*|заморожен[а-яё]*|планиру[ею]тся|будет\s+(?:оплат[а-яё]*|провед[её]н[а-яё]*)|ожида[её]т\s+подтверждени|\bawaiting\s+approval\b|\bon\s+hold\b|\bnot\s+(?:completed|processed|approved|confirmed)\b""",
            RegexOption.IGNORE_CASE)
        // Block OTP and payment confirmation alerts before saving text.
        val credentials = Regex(
            """парол[ья]|password|passcode|\bpin\b|\bcvv\b|\bcvc\b|код\s*[:№]|код\s+безопасности|(?:ваш|your)\s+(?:код|code)""",
            RegexOption.IGNORE_CASE)
        // Mirror the Dart import gate: a currency word alone is
        // not evidence of a posted transaction amount.
        val additionalCredentials = Regex(
            """(?:код|code)\s*(?:для\s+)?(?:операции|перевода|оплаты|payment|transfer)|\b(?:security|confirmation|verification)\s+code\b|(?:sms|смс)[-\s]*(?:парол[ья]|password)""",
            RegexOption.IGNORE_CASE)
        val amount = Regex(
            """(?:\d{1,3}(?:[ \u00a0\u202f]\d{3})+|\d+)(?:[.,]\d{1,2})?\s*(?:₽|руб(?:\.|ль|ля|лей)?|\bRUB\b)""",
            RegexOption.IGNORE_CASE)
        // Record the first rejection reason as a fixed category only.
        // Never persist the rejected notification text or credentials.
        val skipReason = when {
            sensitive.containsMatchIn(combined) ||
                credentials.containsMatchIn(combined) ||
                additionalCredentials.containsMatchIn(combined) -> "credentials"
            notPosted.containsMatchIn(combined) ||
                additionalUnposted.containsMatchIn(combined) -> "not_completed"
            !transaction.containsMatchIn(combined) -> "not_transaction"
            !currency.containsMatchIn(combined) ||
                !amount.containsMatchIn(combined) -> "no_amount"
            else -> null
        }
        if (skipReason != null) {
            markFiltered(bankId, skipReason)
            return
        }
        synchronized(queueLock) {
        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
        // A damaged queue may contain payments not yet saved in the journal.
        // Preserve the original bytes rather than replacing them with [].
        val current = try {
            JSONArray(prefs.getString("queue", "[]"))
        } catch (ignored: org.json.JSONException) {
            prefs.edit().putBoolean("queue_corrupt", true)
                .putInt("queue_recoveries",
                (prefs.getInt("queue_recoveries", 0) + 1).coerceAtMost(100000000))
                .putString("last_skip_reason", "queue_corrupt")
                .putLong("last_skipped", System.currentTimeMillis()).commit()
            return
        }
        val key = "${sbn.packageName}:${sbn.id}:${sbn.postTime}"
        // A previously acknowledged alert may still be visible in the
        // Android notification shade after reconnect. Never queue it again.
        // A corrupt acknowledgement ledger is a stop condition, not an
        // excuse to silently forget processed transaction IDs.
        val acknowledged = try {
            JSONArray(prefs.getString("acknowledged", "[]"))
        } catch (_: org.json.JSONException) {
            prefs.edit().putString("last_skip_reason", "acknowledgements_corrupt")
                .putLong("last_skipped", System.currentTimeMillis()).commit()
            return
        }
        for (i in 0 until acknowledged.length()) {
            if (acknowledged.optString(i) == key) return
        }
        for (i in 0 until current.length()) {
            val existingKey = current.optJSONObject(i)?.optString("key").orEmpty()
            // Old builds appended a body hash. Treat them as the same
            // notification to avoid duplicate pending transactions.
            if (existingKey == key || existingKey.startsWith("$key:")) return
        }
        // Never silently evict older, unprocessed payments while Flutter
        // is closed. Reject new events and expose queue pressure instead.
        if (current.length() >= MAX_PENDING) {
            prefs.edit().putInt("queue_full_rejections",
                (prefs.getInt("queue_full_rejections", 0) + 1).coerceAtMost(100000000))
                .putString("last_skip_reason", "queue_full")
                .putLong("last_skipped", System.currentTimeMillis()).commit()
            return
        }
        current.put(JSONObject().put("key", key).put("bank", bank)
            .put("title", title).put("body", body).put("time", sbn.postTime))
        val editor = prefs.edit().putString("queue", current.toString())
            .putBoolean("queue_corrupt", false)
        editor
            .putLong("last_accepted", System.currentTimeMillis())
            .putString("last_accepted_bank", bank)
            .putInt("accepted_count", (prefs.getInt("accepted_count", 0) + 1)
                .coerceAtMost(100000000))
            .putInt("bank_accepted_" + bankId,
                (prefs.getInt("bank_accepted_" + bankId, 0) + 1)
                    .coerceAtMost(100000000))
        // A notification is an irreplaceable event: synchronously commit
        // the pending queue before treating it as accepted. apply() could
        // lose it if Android kills the process immediately after callback.
        if (!editor.commit()) {
            prefs.edit().putLong("last_queue_write_failed", System.currentTimeMillis())
                .commit()
        }
        } // queueLock
    }
}
