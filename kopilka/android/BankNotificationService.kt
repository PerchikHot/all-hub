package com.veyrion.kopilka_app
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.app.Notification
import org.json.JSONArray
import org.json.JSONObject

class BankNotificationService : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        getSharedPreferences("kopilka_notifications", MODE_PRIVATE).edit()
            .putBoolean("listener_connected", true)
            .putLong("last_connected", System.currentTimeMillis()).apply()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        getSharedPreferences("kopilka_notifications", MODE_PRIVATE).edit()
            .putBoolean("listener_connected", false).apply()
    }

    // Diagnostics are counters only. Filtered notifications, including
    // one-time codes, never enter the import queue or diagnostic logs.
    private fun markFiltered(bankId: String) {
        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
        prefs.edit()
            .putInt("filtered_count",
                (prefs.getInt("filtered_count", 0) + 1).coerceAtMost(100000000))
            .putInt("bank_filtered_" + bankId,
                (prefs.getInt("bank_filtered_" + bankId, 0) + 1)
                    .coerceAtMost(100000000)).apply()
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
            markFiltered(bankId)
            return
        }
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val normalText = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val expandedText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""
        val body = if (expandedText.isNotBlank()) expandedText else normalText
        // Never persist oversized or malformed notification payloads.
        if (body.isBlank() || body.length > 2048 || title.length > 200) {
            markFiltered(bankId)
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
        if (!transaction.containsMatchIn(combined) ||
            !currency.containsMatchIn(combined) ||
            !amount.containsMatchIn(combined) ||
            sensitive.containsMatchIn(combined) ||
            credentials.containsMatchIn(combined) ||
            additionalCredentials.containsMatchIn(combined) ||
            notPosted.containsMatchIn(combined) ||
            additionalUnposted.containsMatchIn(combined)) {
            markFiltered(bankId)
            return
        }
        val prefs = getSharedPreferences("kopilka_notifications", MODE_PRIVATE)
        // A damaged local queue must not crash NotificationListenerService.
        // Recover the pending queue without touching saved transactions.
        val current = try {
            JSONArray(prefs.getString("queue", "[]"))
        } catch (ignored: org.json.JSONException) {
            JSONArray()
        }
        val key = "${sbn.packageName}:${sbn.id}:${sbn.postTime}"
        for (i in 0 until current.length()) {
            val existingKey = current.optJSONObject(i)?.optString("key").orEmpty()
            // Old builds appended a body hash. Treat them as the same
            // notification to avoid duplicate pending transactions.
            if (existingKey == key || existingKey.startsWith("$key:")) return
        }
        current.put(JSONObject().put("key", key).put("bank", bank)
            .put("title", title).put("body", body).put("time", sbn.postTime))
        while (current.length() > 100) current.remove(0)
        prefs.edit().putString("queue", current.toString())
            .putInt("accepted_count", (prefs.getInt("accepted_count", 0) + 1)
                .coerceAtMost(100000000))
            .putInt("bank_accepted_" + bankId,
                (prefs.getInt("bank_accepted_" + bankId, 0) + 1)
                    .coerceAtMost(100000000)).apply()
    }
}
