package com.veyrion.kopilka_app

import org.junit.Assert.*
import org.junit.Test

class BankAutoClassifierTest {
    private val now = 1793541600000L
    private fun parse(body: String, bank: String = "Т-Банк") =
        BankAutoClassifier.classify(bank, "Операция", body,
            "com.bank:1:1793541540000", now - 60000, now)

    @Test fun acceptsExplicitMerchantLabelsAndIncome() {
        for (label in listOf("Магазин: Пятёрочка", "Торговая точка — Пятёрочка",
                "Продавец: Пятёрочка", "Merchant: Grocery")) {
            val result = parse("Покупка 250,50 ₽\\n$label")
            assertNotNull(label, result)
            assertEquals("expense", result!!["kind"])
            assertEquals(250.5, result["amount"])
        }
        assertEquals("income", parse("Зарплата поступила 20 000 ₽",
            "Газпромбанк")?.get("kind"))
        assertEquals("income", parse("Возврат покупки 350 ₽",
            "Ozon Банк")?.get("kind"))
    }

    @Test fun refusesTransfersMultipleAmountsAndUncertainMessages() {
        for (body in listOf(
            "Перевод 200 ₽\\nМагазин: Пятёрочка",
            "Покупка 250 ₽. Остаток 4 000 ₽\\nМагазин: Пятёрочка",
            "Оплата 250 ₽ не прошла\\nМагазин: Пятёрочка",
            "Код подтверждения оплаты 250 ₽: 1234",
            "Покупка 250 ₽",
            "Покупка 250 ₽\\nМагазин: A",
        )) assertNull(body, parse(body))
        assertNull(parse("Покупка 250 ₽\\nМагазин: Пятёрочка", "Другой банк"))
    }

    @Test fun rejectsFutureAndOldOrReusedKeys() {
        assertNull(BankAutoClassifier.classify("Т-Банк", "Операция",
            "Покупка 250 ₽\\nМагазин: Пятёрочка", "", now, now))
        assertNull(BankAutoClassifier.classify("Т-Банк", "Операция",
            "Покупка 250 ₽\\nМагазин: Пятёрочка", "id", now + 600000, now))
        assertNull(BankAutoClassifier.classify("Т-Банк", "Операция",
            "Покупка 250 ₽\\nМагазин: Пятёрочка", "id",
            now - 25L * 60L * 60L * 1000L, now))
    }
}
