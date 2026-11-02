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
        // Process-local state, unlike SharedPreferences which may retain a stale
        // connected=true after Android kills the process without a callback.
        @Volatile var connectedInProcess: Boolean = false
            private set
        // Retain more payments while the Flutter dashboard is closed. This
        // remains bounded to avoid unlimited private notification storage.
        const val MAX_PENDING = 500
    }
    override fun onListenerConnected() {
        super.onListenerConnected()
        connectedInProcess = true
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
        connectedInProcess = false
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

    override fun onDestroy() {
        connectedInProcess = false
        super.onDestroy()
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
        // OEM notification extras may be malformed or throw while being read.
        // One broken bank alert must not crash the listener and stop all
        // subsequent autonomous transactions. Never log the raw payload.
        try {
            processBankNotification(sbn)
        } catch (_: RuntimeException) {
            try {
                getSharedPreferences("kopilka_notifications", MODE_PRIVATE).edit()
                    .putString("last_skip_reason", "notification_exception")
                    .putLong("last_skipped", System.currentTimeMillis()).apply()
            } catch (_: RuntimeException) {
                // The Android process may be shutting down; do not crash it.
            }
        }
    }

    private fun processBankNotification(sbn: StatusBarNotification) {
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
        // InboxStyle alerts can contain only EXTRA_TEXT_LINES. Treat the
        // bounded lines as one message so ordinary classification, OTP
        // filtering and SQLite deduplication still apply.
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.take(9)?.map { it.toString().take(2049) }.orEmpty()
        val body = BankNotificationBody.select(normalText, expandedText, lines)
        // Some bank apps send a complete transaction only in EXTRA_TITLE.
        // Do not drop it when EXTRA_TEXT is empty: the conservative native
        // classifier can still require an explicit merchant and amount.
        // Never persist oversized or malformed notification payloads.
        if ((body.isBlank() && title.isBlank()) ||
            body.length > 2048 || title.length > 200) {
            markFiltered(bankId, "invalid_payload")
            return
        }
        // Store transaction alerts only. Never retain OTP/login codes,
        // promotions or balance-only notifications in the local queue.
        val combined = title + " " + body
        // Scan ALL visible representations for OTPs and failed payments.
        // Choosing the richest purchase body must never hide a credential or
        // cancellation present in a shorter notification preview.
        val allVisible = listOf(title, normalText, expandedText)
            .plus(lines).joinToString(" ")
        val currency = Regex("""₽|руб(?:\.|ль|ля|лей)?|\bRUB\b""", RegexOption.IGNORE_CASE)
        val sensitive = Regex(
            """код\s+(?:подтверждения|входа|для\s+(?:входа|подтверждения)|операции|из\s+смс)|(?:sms|смс)[-\s]*код|одноразов(?:ый|ого)\s+код|никому\s+не\s+сообщайте|verification\s+code|one[- ]time\s+(?:password|code)|\bOTP\b""",
            RegexOption.IGNORE_CASE)
        // The native queue must reject unposted payments and
        // credential alerts BEFORE storing their text on disk.
        val notPosted = Regex(
            """отклон[её]н|не\s+(?:выполнен|прошл[ао]|провед[её]н|подтвержд[её]н|заверш[её]н)|неуспешн|отмен[её]н|недостаточн[а-яё]*\s+средств|ожида[её]т\s+подтверждени|в\s+обработк|запланирован[а-яё]*|ожидается\s+(?:завтра|послезавтра)|будет\s+(?:списан[а-яё]*|зачислен[а-яё]*|поступ[а-яё]*|выплачен[а-яё]*)|declined|rejected|failed|cancelled|canceled|pending|processing|scheduled|upcoming|insufficient\s+funds|\bblocked\b|\bsuspended\b|требует\s+подтверждени|подтвердите\s+(?:операцию|плат[её]ж|перевод|оплату)|requires\s+confirmation|authorization\s+required|\bwill\s+be\s+(?:charged|debited|credited|deposited|paid)\b""",
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
            sensitive.containsMatchIn(allVisible) ||
                credentials.containsMatchIn(allVisible) ||
                additionalCredentials.containsMatchIn(allVisible) -> "credentials"
            notPosted.containsMatchIn(allVisible) ||
                additionalUnposted.containsMatchIn(allVisible) -> "not_completed"
            !BankNotificationGate.hasTransactionMarker(combined) -> "not_transaction"
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
        // A corrupt legacy review queue must remain untouched, but must not
        // prevent a *structured* high-confidence event from reaching SQLite.
        // Previously this early return disabled autonomous accounting entirely.
        val current: JSONArray? = try {
            JSONArray(prefs.getString("queue", "[]"))
        } catch (ignored: org.json.JSONException) {
            prefs.edit().putBoolean("queue_corrupt", true)
                .putInt("queue_recoveries",
                    (prefs.getInt("queue_recoveries", 0) + 1).coerceAtMost(100000000))
                .putString("last_skip_reason", "queue_corrupt")
                .putLong("last_skipped", System.currentTimeMillis()).commit()
            null
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
        // The bounded legacy acknowledgement ring can forget old keys.
        // Durable SQLite tombstones suppress replay after listener reconnect.
        try {
            if (BankNativeJournal(this).use { it.wasAcknowledged(key) }) return
        } catch (_: Exception) {
            // A broken database must not silently discard a new payment.
            // Continue through the conservative legacy review path.
        }
        if (current != null) for (i in 0 until current.length()) {
            val existingKey = current.optJSONObject(i)?.optString("key").orEmpty()
            // Old builds appended a body hash. Treat them as the same
            // notification to avoid duplicate pending transactions.
            if (existingKey == key || existingKey.startsWith("$key:")) return
        }
        // Persist unambiguous events to an independent SQLite journal even
        // when Flutter is closed or the raw notification review queue is full.
        // No raw notification text is copied into the SQLite database.
        val candidate = if (BankNotificationBody.hasConflictingAmounts(
                listOf(title, normalText, expandedText).plus(lines))) null
            else BankAutoClassifier.classify(
                bank, title, body, key, sbn.postTime, System.currentTimeMillis())
        val nativeSaved = candidate != null && try {
            BankNativeJournal(this).use { it.stage(candidate) }
        } catch (_: Exception) {
            false // Database open failures must preserve the review fallback.
        }
        if (current == null) {
            val recovery = BankStoragePolicy.decide(
                nativeSaved, 0, MAX_PENDING, queueReadable = false)
            // Never overwrite corrupt queue bytes with an empty JSON array.
            // SQLite is independently durable, so confirmed transactions
            // remain available for Flutter reconciliation after recovery.
            if (!recovery.queueRejected) {
                val acceptedAt = System.currentTimeMillis()
                // Keep diagnostics truthful even when only the independent
                // SQLite path can accept a payment. Do not clear the corrupt
                // review queue or report its raw contents as recovered.
                prefs.edit()
                    .putLong("last_native_auto_stage", acceptedAt)
                    .putLong("last_accepted", acceptedAt)
                    .putString("last_accepted_bank", bank)
                    .putInt("accepted_count",
                        (prefs.getInt("accepted_count", 0) + 1)
                            .coerceAtMost(100000000))
                    .putInt("bank_accepted_" + bankId,
                        (prefs.getInt("bank_accepted_" + bankId, 0) + 1)
                            .coerceAtMost(100000000))
                    .putInt("native_auto_staged_count",
                        (prefs.getInt("native_auto_staged_count", 0) + 1)
                            .coerceAtMost(100000000))
                    .remove("last_native_stage_error").commit()
            }
            return
        }
        // Never silently evict older, unprocessed payments while Flutter
        // is closed. Review-only events still require available queue space.
        // A high-confidence event is already durable in SQLite. Do not
        // reject it just because the legacy review queue is full.
        val storage = BankStoragePolicy.decide(nativeSaved, current.length(), MAX_PENDING)
        if (storage.queueRejected) {
            prefs.edit().putInt("queue_full_rejections",
                (prefs.getInt("queue_full_rejections", 0) + 1).coerceAtMost(100000000))
                .putString("last_skip_reason", "queue_full")
                .putLong("last_skipped", System.currentTimeMillis()).commit()
            return
        }
        // Keep raw text only for review-only alerts and SQLite failures.
        // Confirmed events are already stored as minimal structured records,
        // so persisting the original bank notification would be unnecessary.
        if (storage.retainRawForReview) {
            current.put(JSONObject().put("key", key).put("bank", bank)
                .put("title", title).put("body", body).put("time", sbn.postTime))
        }
        // Record strictly classified transactions in a separate durable
        // native ledger while Flutter is not running. The UI reconciles this
        // ledger with its journal on resume; uncertain alerts remain review-only.
        // Never replace a corrupted ledger or evict unimported transactions.
        val staged = try {
            JSONArray(prefs.getString("auto_entries", "[]"))
        } catch (_: org.json.JSONException) {
            null
        }
        // Older APKs used SharedPreferences as the staging ledger. Keep it
        // only as a fallback if SQLite cannot persist this event.
        val canStage = candidate != null && !nativeSaved && staged != null &&
            staged.length() < MAX_PENDING
        if (canStage) {
            staged!!.put(JSONObject(candidate!!))
        }
        val editor = prefs.edit().putString("queue", current.toString())
            .putBoolean("queue_corrupt", false)
        // Distinguish conservative review-only alerts from durable automatic
        // candidates without retaining any additional private message text.
        if (candidate == null) {
            // The bank event passed the privacy gate but was too ambiguous
            // for automatic accounting. Report only a fixed reason, not text.
            editor.putString("last_skip_reason", "review_required")
                .putLong("last_skipped", System.currentTimeMillis())
            editor.putInt("native_review_only_count",
                (prefs.getInt("native_review_only_count", 0) + 1)
                    .coerceAtMost(100000000))
        } else if (canStage || nativeSaved) {
            editor.putInt("native_auto_staged_count",
                (prefs.getInt("native_auto_staged_count", 0) + 1)
                    .coerceAtMost(100000000))
        }
        if (canStage) {
            editor.putString("auto_entries", staged!!.toString())
                .putLong("last_native_auto_stage", System.currentTimeMillis())
                .remove("last_native_stage_error")
        } else if (nativeSaved) {
            editor.putLong("last_native_auto_stage", System.currentTimeMillis())
                .remove("last_native_stage_error")
        } else if (candidate != null) {
            editor.putString("last_native_stage_error",
                if (staged == null) "ledger_corrupt" else "ledger_full")
        }
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
