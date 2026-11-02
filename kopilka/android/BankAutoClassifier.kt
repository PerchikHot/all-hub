package com.veyrion.kopilka_app

// Conservative, pure Kotlin classifier used by the Android background
// notification listener. No model, network, bank API or Flutter engine needed.
// Only explicit posted purchases with a named merchant and explicit income
// qualify. Transfers, balance alerts, and multiple amounts remain in review.
internal object BankAutoClassifier {
    fun classify(bank: String, title: String, body: String, key: String,
                 postedAt: Long, now: Long): Map<String, Any>? {
        if (bank !in setOf("Т-Банк", "Газпромбанк", "Ozon Банк") ||
            key.isBlank() || key.length > 256 || body.length > 2048 ||
            postedAt < 946684800000L || postedAt > now + 300000L ||
            postedAt < now - 24L * 60L * 60L * 1000L) return null
        val text = "$title\n$body"
        val reject = Regex(
            """перевод|transfer|пополнени[ея]|снятие|withdraw|остаток|баланс|доступно|available|balance|код|password|парол|pin|cvv|cvc|отклон|не прош|не выполн|не провед|не подтвержд|отмен|неуспеш|недостаточн|ожида[её]т|ожидается|в\s+обработк|требует\s+подтверждени|подтвердите|заблокирован|будет\s+списан|выполнится|pending|processing|declined|rejected|failed|cancelled|canceled|scheduled|upcoming|запланирован|requires\s+confirmation|authorization|will\s+be\s+charged""",
            RegexOption.IGNORE_CASE)
        if (reject.containsMatchIn(text)) return null
        val amountPattern = Regex(
            """(?:\d{1,3}(?:[ \u00a0\u202f]\d{3})+|\d+)(?:[.,]\d{1,2})?\s*(?:₽|руб(?:\.|ль|ля|лей)?|\bRUB\b)""",
            RegexOption.IGNORE_CASE)
        val matches = amountPattern.findAll(text).toList()
        if (matches.size != 1) return null
        val digits = Regex("""\d[\d \u00a0\u202f]*(?:[.,]\d{1,2})?""")
            .find(matches[0].value)?.value ?: return null
        val amount = digits.replace(" ", "").replace("\u00a0", "")
            .replace("\u202f", "").replace(',', '.').toDoubleOrNull()
            ?: return null
        if (!amount.isFinite() || amount <= 0.0 || amount > 1_000_000_000.0) return null
        val purchase = Regex("""покупк|оплат[ауы]|оплачено|списан|purchase|payment""",
            RegexOption.IGNORE_CASE).containsMatchIn(text)
        val refund = Regex("""возврат\s+(?:покупк|оплат)|refund""",
            RegexOption.IGNORE_CASE).containsMatchIn(text)
        val salary = Regex("""зарплат|salary""",
            RegexOption.IGNORE_CASE).containsMatchIn(text)
        val cashback = Regex("""кэшбэк|кешбэк|cashback""",
            RegexOption.IGNORE_CASE).containsMatchIn(text)
        val income = refund || salary || cashback
        if ((!purchase && !income) || (purchase && income && !refund)) return null
        // Banks may place the labelled merchant after a full stop or semicolon
        // on the same line as the amount. Require a real separator and a
        // labelled field: free-form text is never sufficient for auto-import.
        val labelledMerchant = Regex("""(?:^|[\n.;])\s*(?:магазин|торговая точка|продавец|merchant)\s*[:：—-]\s*([^\r\n,;]{2,80})""",
            RegexOption.IGNORE_CASE).find(body)?.groupValues?.get(1)?.trim()
        // Some bank notifications use an explicit location phrase rather than
        // "Магазин:". Only "в магазине/торговой точке" is unambiguous enough
        // for background import; a free-form "в <name>" stays in review.
        val locationMerchant = Regex("""(?:^|[\s.;])в\s+(?:магазине|торговой\s+точке)\s+([^\r\n,;.!?]{2,80})""",
            RegexOption.IGNORE_CASE).find(body)?.groupValues?.get(1)?.trim()
        val merchant = labelledMerchant ?: locationMerchant
        // A merchant containing digits could include a card suffix or code.
        // Never copy it into the minimal SQLite financial journal.
        if (purchase && !income && (merchant.isNullOrBlank() ||
                merchant.length < 2 || merchant.any { it.isDigit() })) return null
        val note = when {
            refund -> "Возврат покупки"
            salary -> "Зарплата"
            cashback -> "Кэшбэк"
            else -> merchant!!
        }
        val kind = if (income) "income" else "expense"
        val sourceType = when {
            refund -> "refund"
            salary -> "salary"
            cashback -> "cashback"
            else -> "purchase"
        }
        return mapOf(
            "key" to key, "notificationKey" to key, "bank" to bank,
            "from" to bank, "to" to "", "kind" to kind,
            "amount" to amount, "dateMillis" to postedAt,
            "note" to note, "sourceType" to sourceType,
            "autoImported" to true, "nativeClassifier" to 1)
    }
}

/**
 * Decide whether a bank notification still needs its raw text retained.
 * Successfully staged high-confidence events have a minimal durable SQLite
 * representation; review-only events and SQLite failures need the legacy
 * review queue. A full review queue must not reject a SQLite-staged payment.
 */
internal data class BankStorageDecision(
    val retainRawForReview: Boolean,
    val queueRejected: Boolean
)

internal object BankStoragePolicy {
    fun decide(nativeSaved: Boolean, queued: Int, capacity: Int,
               queueReadable: Boolean = true): BankStorageDecision {
        require(queued >= 0 && capacity > 0)
        val retainRaw = !nativeSaved
        // A broken review queue cannot be overwritten. Independently staged
        // SQLite payments are still safe; uncertain events must wait.
        return BankStorageDecision(
            retainRawForReview = retainRaw,
            queueRejected = retainRaw && (!queueReadable || queued >= capacity)
        )
    }
}

/** Pure replay policy shared by the Android ledger merge and its JVM tests. */
internal object BankLedgerPolicy {
    fun includeLegacy(key: String, alreadyPending: Boolean, acknowledged: Boolean): Boolean =
        key.isNotBlank() && key.length <= 256 && !alreadyPending && !acknowledged
}
