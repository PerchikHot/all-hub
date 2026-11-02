package com.veyrion.kopilka_app

// Conservative, pure Kotlin classifier used by the Android background
// notification listener. No model, network, bank API or Flutter engine needed.
// Only explicit posted purchases with a named merchant and explicit income
// qualify. Transfers, balance alerts, and multiple amounts remain in review.
/**
 * Inbox-style bank notifications sometimes expose only EXTRA_TEXT_LINES.
 * Prefer the expanded/ordinary body; never concatenate duplicate previews.
 * A bounded fallback keeps the existing classifier and privacy filters in
 * charge of deciding whether a payment can be persisted.
 */
internal object BankNotificationBody {
    fun select(normal: String, expanded: String, lines: List<String>): String {
        // Some InboxStyle notifications show only a generic preview in
        // EXTRA_TEXT, with the actual purchase in EXTRA_TEXT_LINES. Prefer
        // a bounded field containing a currency amount over a generic one.
        val joined = if (lines.size <= 8) lines.joinToString("\n").trim() else ""
        val options = listOf(expanded, normal, joined)
            .filter { it.isNotBlank() && it.length <= 2048 }
        val amount = Regex(
            """(?:\d{1,3}(?:[ \u00a0\u202f]\d{3})+|\d+)(?:[.,]\d{1,2})?\s*(?:₽|руб(?:\.|ль|ля|лей)?|\bRUB\b)""",
            RegexOption.IGNORE_CASE)
        // Expanded previews may contain the amount but omit the merchant.
        // Prefer a complete InboxStyle body when it includes both the amount
        // and an explicitly labelled merchant. The listener still scans ALL
        // representations for OTPs, failed payments and conflicting amounts.
        val merchant = Regex(
            """(?:^|[\n.;])\s*(?:магазин|торговая точка|продавец|merchant)\s*[:：—-]\s*[^\r\n,;]{2,80}|(?:^|[\s.;])в\s+(?:магазине|торговой\s+точке)\s+[^\r\n,;.!?]{2,80}""",
            RegexOption.IGNORE_CASE)
        return options.firstOrNull {
            amount.containsMatchIn(it) && merchant.containsMatchIn(it)
        } ?: options.firstOrNull { amount.containsMatchIn(it) }
            ?: options.firstOrNull() ?: ""
    }

    /** Different visible amounts must be reviewed, even when the selected
     * preview contains only one. Repeated previews of the SAME amount are OK. */
    fun hasConflictingAmounts(parts: List<String>): Boolean {
        val amount = Regex(
            """(?:\d{1,3}(?:[ \u00a0\u202f]\d{3})+|\d+)(?:[.,]\d{1,2})?\s*(?:₽|руб(?:\.|ль|ля|лей)?|\bRUB\b)""",
            RegexOption.IGNORE_CASE)
        val unique = mutableSetOf<String>()
        for (part in parts) for (match in amount.findAll(part)) {
            // The same amount can appear as "250 ₽", "250 руб." and
            // "250,00 RUB" across title, expanded text and InboxStyle lines.
            // Compare numeric ruble values, not the display unit. A distinct
            // balance or second purchase must still force manual review.
            val digits = Regex("""\d[\d \u00a0\u202f]*(?:[.,]\d{1,2})?""")
                .find(match.value)?.value ?: return true
            val normalized = digits.replace(Regex("""[ \u00a0\u202f]"""), "")
                .replace(',', '.').toBigDecimalOrNull()
                ?.stripTrailingZeros()?.toPlainString() ?: return true
            unique.add(normalized)
            if (unique.size > 1) return true
        }
        return false
    }
}

/** Native pre-filter must not drop salaries that the classifier accepts.
 * Keep this testable without Android runtime or access to bank notifications.
 */
internal object BankNotificationGate {
    private val transaction = Regex(
        """покупк|оплат|оплач|плат[её]ж|списан|перевод|поступ|зачисл|пополн|возврат|кэшбэк|кешбэк|сняти|выдач|зарплат|purchase|payment|transfer|refund|credited|deposit|withdraw|salary""",
        RegexOption.IGNORE_CASE)
    fun hasTransactionMarker(text: String): Boolean = transaction.containsMatchIn(text)
}

internal object BankAutoClassifier {
    fun classify(bank: String, title: String, body: String, key: String,
                 postedAt: Long, now: Long): Map<String, Any>? {
        if (bank !in setOf("Т-Банк", "Газпромбанк", "Ozon Банк") ||
            key.isBlank() || key.length > 256 || body.length > 2048 ||
            postedAt < 946684800000L || postedAt > now + 300000L ||
            postedAt < now - 24L * 60L * 60L * 1000L) return null
        val text = "$title\n$body"
        val reject = Regex(
            """перевод|transfer|пополнени[ея]|снятие|withdraw|остаток|баланс|доступно|available|balance|код|password|парол|pin|cvv|cvc|отклон|не прош|не выполн|не провед|не подтвержд|отмен|неуспеш|недостаточн|ожида[её]т|ожидается|в\s+обработк|требует\s+подтверждени|подтверждени[ея]\s+(?:операции|плат[её]жа|оплаты|покупки)|авторизаци[яюие]\s+(?:операции|оплаты|плат[её]жа)|резервировани[ея]\s+(?:средств|суммы)|подтвердите|заблокирован|будет\s+(?:списан[а-яё]*|зачислен[а-яё]*|поступ[а-яё]*|выплачен[а-яё]*)|выполнится|pending|processing|declined|rejected|failed|cancelled|canceled|scheduled|upcoming|запланирован|планиру[ею]тся|начислен[а-яё]*|заявк[а-яё]*\s+на\s+возврат|оформлен[а-яё]*\s+возврат|не\s+одобрен[а-яё]*|не\s+состоял[а-яё]*|отказан[а-яё]*|приостановлен[а-яё]*|requires\s+confirmation|authorization|will\s+be\s+(?:charged|credited|deposited|paid)""",
            RegexOption.IGNORE_CASE)
        if (reject.containsMatchIn(text)) return null
        val amountPattern = Regex(
            """(?:\d{1,3}(?:[ \u00a0\u202f]\d{3})+|\d+)(?:[.,]\d{1,2})?\s*(?:₽|руб(?:\.|ль|ля|лей)?|\bRUB\b)""",
            RegexOption.IGNORE_CASE)
        // Android may render the SAME payment as differently worded title
        // and expanded body ("Покупка 250 ₽" / "Оплата 250,00 руб.").
        // One amount in EACH field is safe to collapse only when both
        // represent exactly the same ruble value. Never collapse two amounts
        // within one field, even if they happen to be equal: those may be
        // separate transactions. Security/rejection keywords remain checked
        // across BOTH fields before this point.
        val titleAmounts = amountPattern.findAll(title).toList()
        val bodyAmounts = amountPattern.findAll(body).toList()
        val repeatedPreview = titleAmounts.size == 1 && bodyAmounts.size == 1 &&
            !BankNotificationBody.hasConflictingAmounts(listOf(title, body))
        val amountSource = if (repeatedPreview) body else text
        val matches = amountPattern.findAll(amountSource).toList()
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
        // Android may put the entire completed purchase in EXTRA_TITLE
        // with an empty EXTRA_TEXT. The listener still scans every visible
        // field for OTPs, rejected payments and conflicting amounts.
        val labelledMerchant = Regex("""(?:^|[\n.;])\s*(?:магазин|торговая точка|продавец|merchant)\s*[:：—-]\s*([^\r\n,;]{2,80})""",
            RegexOption.IGNORE_CASE).let { pattern ->
            (pattern.find(body) ?: pattern.find(title))?.groupValues?.get(1)?.trim()
        }
        // Some bank notifications use an explicit location phrase rather than
        // "Магазин:". Only "в магазине/торговой точке" is unambiguous enough
        // for background import; a free-form "в <name>" stays in review.
        val locationMerchant = Regex("""(?:^|[\s.;])в\s+(?:магазине|торговой\s+точке)\s+([^\r\n,;.!?]{2,80})""",
            RegexOption.IGNORE_CASE).let { pattern ->
            (pattern.find(body) ?: pattern.find(title))?.groupValues?.get(1)?.trim()
        }
        // A complete single-line bank purchase can explicitly say
        // "Покупка 250 ₽ в Пятёрочке" without a separate "Магазин:" label.
        // Require the amount, transaction verb, preposition and a terminal
        // merchant on the SAME line. Generic locations such as "в приложении"
        // are not reliable merchant names and must stay in manual review.
        val directMerchant = Regex(
            """(?:^|[\n])\s*(?:покупка|оплата)\s+(?:на\s+сумму\s+)?(?:\d{1,3}(?:[ \u00a0\u202f]\d{3})+|\d+)(?:[.,]\d{1,2})?\s*(?:₽|руб(?:\.|ль|ля|лей)?|\bRUB\b)\s+в\s+([^\r\n,;.!?]{2,60})\s*$""",
            RegexOption.IGNORE_CASE
        ).let { pattern ->
            (pattern.find(body) ?: pattern.find(title))?.groupValues?.get(1)?.trim()
        }?.takeUnless {
            it.lowercase() in setOf("приложении", "интернете", "онлайне",
                "банке", "рассрочку", "обработке", "ожидании")
        }
        val merchant = labelledMerchant ?: locationMerchant ?: directMerchant
        // A merchant containing digits could include a card suffix or code.
        // Never copy it into the minimal SQLite financial journal.
        if (purchase && !income && (merchant.isNullOrBlank() ||
                merchant.length < 2 || merchant.any { it.isDigit() } ||
                merchant.none { it.isLetter() })) return null
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
