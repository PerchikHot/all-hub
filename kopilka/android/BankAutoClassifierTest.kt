package com.veyrion.kopilka_app

import org.junit.Assert.*
import org.junit.Test

class BankAutoClassifierTest {
    private val now = 1793541600000L
    private fun parse(body: String, bank: String = "Т-Банк") =
        BankAutoClassifier.classify(bank, "Операция", body,
            "com.bank:1:1793541540000", now - 60000, now)

    @Test fun inboxStyleBankBodyFallbackIsBoundedAndPreservesPrivacyGate() {
        assertEquals("Покупка 250 ₽\nМагазин: Пятёрочка",
            BankNotificationBody.select("", "",
                listOf("Покупка 250 ₽", "Магазин: Пятёрочка")))
        assertNotNull(parse(BankNotificationBody.select("", "",
            listOf("Покупка 250 ₽", "Магазин: Пятёрочка"))))
        assertEquals("expanded", BankNotificationBody.select(
            "ordinary", "expanded", listOf("stale")))
        assertEquals("ordinary", BankNotificationBody.select(
            "ordinary", "", listOf("stale")))
        assertEquals("", BankNotificationBody.select("", "",
            List(9) { "Покупка 250 ₽" }))
        assertEquals("", BankNotificationBody.select("", "",
            listOf("x".repeat(2049))))
        assertNull(parse(BankNotificationBody.select("", "",
            listOf("Код подтверждения оплаты 250 ₽", "Магазин: Пятёрочка"))))
    }

    @Test fun acceptsExplicitMerchantLabelsAndIncome() {
        for (label in listOf("Магазин: Пятёрочка", "Торговая точка — Пятёрочка",
                "Продавец: Пятёрочка", "Merchant: Grocery")) {
            val result = parse("Покупка 250,50 ₽\n$label")
            assertNotNull(label, result)
            assertEquals("expense", result!!["kind"])
            assertEquals(250.5, result["amount"])
        }
        // Real alerts often put the merchant after the amount on one line.
        for (body in listOf(
            "Покупка 250,50 ₽. Магазин: Пятёрочка",
            "Оплата 250,50 ₽; Продавец: Пятёрочка",
            "Payment 250,50 RUB. Merchant: Grocery"
        )) {
            val result = parse(body)
            assertNotNull(body, result)
            assertEquals(250.5, result!!["amount"])
        }
        // An unlabelled store mention is not evidence of a completed purchase.
        // Explicit in-store locations are safe to import; free-form locations
        // and merchant text containing possible card digits remain in review.
        assertEquals("Пятёрочка", parse("Покупка 250 ₽ в магазине Пятёрочка")?.get("note"))
        assertEquals("Аптека", parse("Оплата 90 ₽ в торговой точке Аптека")?.get("note"))
        assertNull(parse("Покупка 250 ₽ в Пятёрочке"))
        assertNull(parse("Покупка 250 ₽ в магазине Карта 1234"))
        assertNull(parse("Покупка 250 ₽. Магазин: A"))
        assertEquals("income", parse("Зарплата поступила 20 000 ₽",
            "Газпромбанк")?.get("kind"))
        assertEquals("income", parse("Возврат покупки 350 ₽",
            "Ozon Банк")?.get("kind"))
    }

    @Test fun repeatedAndroidTitleAndExpandedBodyAreOnePayment() {
        // Expanded notifications often repeat the exact short title.
        val result = BankAutoClassifier.classify(
            "Т-Банк", "Покупка 250 ₽",
            "Покупка 250 ₽. Магазин: Пятёрочка",
            "bank:repeated:1", now - 60000, now)
        assertNotNull(result)
        assertEquals(250.0, result!!["amount"])
        assertEquals("Пятёрочка", result["note"])
        // Different amounts, multiple body amounts, transfers and OTPs
        // must still go to review, never to automatic SQLite import.
        for (body in listOf(
            "Покупка 350 ₽. Магазин: Пятёрочка",
            "Покупка 250 ₽. Ещё 250 ₽. Магазин: Пятёрочка",
            "Покупка 250 ₽. Перевод. Магазин: Пятёрочка",
            "Покупка 250 ₽. Код подтверждения 1234. Магазин: Пятёрочка"
        )) {
            assertNull(body, BankAutoClassifier.classify(
                "Т-Банк", "Покупка 250 ₽", body,
                "bank:repeated:2", now - 60000, now))
        }
    }

    @Test fun refusesTransfersMultipleAmountsAndUncertainMessages() {
        for (body in listOf(
            "Перевод 200 ₽\nМагазин: Пятёрочка",
            "Покупка 250 ₽. Остаток 4 000 ₽\nМагазин: Пятёрочка",
            "Оплата 250 ₽ не прошла\nМагазин: Пятёрочка",
            "Код подтверждения оплаты 250 ₽: 1234",
            "Покупка 250 ₽",
            "Оплата 250 ₽ в обработке. Магазин: Пятёрочка",
            "Покупка 250 ₽ ожидает подтверждения. Магазин: Пятёрочка",
            "Покупка 250 ₽ ожидается завтра. Магазин: Пятёрочка",
            "Оплата 250 ₽ требует подтверждения. Магазин: Пятёрочка",
            "Payment 250 RUB pending. Merchant: Grocery",
            "Payment 250 RUB declined. Merchant: Grocery",
            "Payment 250 RUB requires confirmation. Merchant: Grocery",
            "Покупка 250 ₽\nМагазин: A",
        )) assertNull(body, parse(body))
        assertNull(parse("Покупка 250 ₽\nМагазин: Пятёрочка", "Другой банк"))
    }

    @Test fun rejectsFutureAndOldOrReusedKeys() {
        assertNull(BankAutoClassifier.classify("Т-Банк", "Операция",
            "Покупка 250 ₽\nМагазин: Пятёрочка", "", now, now))
        assertNull(BankAutoClassifier.classify("Т-Банк", "Операция",
            "Покупка 250 ₽\nМагазин: Пятёрочка", "id", now + 600000, now))
        assertNull(BankAutoClassifier.classify("Т-Банк", "Операция",
            "Покупка 250 ₽\nМагазин: Пятёрочка", "id",
            now - 25L * 60L * 60L * 1000L, now))
    }
    @Test fun sqliteStagedPaymentsNeverRetainRawBankText() {
        for (queued in listOf(0, 499, 500, 1000)) {
            val decision = BankStoragePolicy.decide(
                nativeSaved = true, queued = queued, capacity = 500)
            assertFalse(decision.retainRawForReview)
            assertFalse(decision.queueRejected)
        }
    }

    @Test fun reviewOnlyAndSqliteFailuresKeepRawTextUntilReviewed() {
        val available = BankStoragePolicy.decide(
            nativeSaved = false, queued = 499, capacity = 500)
        assertTrue(available.retainRawForReview)
        assertFalse(available.queueRejected)
        val full = BankStoragePolicy.decide(
            nativeSaved = false, queued = 500, capacity = 500)
        assertTrue(full.retainRawForReview)
        assertTrue(full.queueRejected)
    }


    @Test fun damagedReviewQueueNeverBlocksDurableSqlitePayments() {
        // The raw queue is deliberately unreadable. Do not clear or replace
        // its bytes, but keep processing independently stored transactions.
        val saved = BankStoragePolicy.decide(
            nativeSaved = true, queued = 0, capacity = 500, queueReadable = false)
        assertFalse(saved.retainRawForReview)
        assertFalse(saved.queueRejected)
        // An ambiguous alert cannot be retained safely until the user repairs
        // the review queue. Never report it as a successful automatic import.
        val uncertain = BankStoragePolicy.decide(
            nativeSaved = false, queued = 0, capacity = 500, queueReadable = false)
        assertTrue(uncertain.retainRawForReview)
        assertTrue(uncertain.queueRejected)
    }

    @Test fun acknowledgedLegacyRowsCannotReplayAfterPartialCommit() {
        assertTrue(BankLedgerPolicy.includeLegacy("bank:1:123", false, false))
        assertFalse(BankLedgerPolicy.includeLegacy("bank:1:123", true, false))
        assertFalse(BankLedgerPolicy.includeLegacy("bank:1:123", false, true))
        assertFalse(BankLedgerPolicy.includeLegacy("", false, false))
        assertFalse(BankLedgerPolicy.includeLegacy("x".repeat(257), false, false))
    }
}
