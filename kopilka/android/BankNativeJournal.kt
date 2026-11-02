package com.veyrion.kopilka_app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONArray
import org.json.JSONObject

/**
 * Durable, app-private journal of high-confidence bank events.
 *
 * The Android notification listener writes here without launching Flutter.
 * Flutter reconciles these records with its existing financial journal and
 * acknowledges only after that journal has been persisted. No raw bank
 * notification text, account credentials, or network requests are stored.
 * The notification key is unique, so listener reconnections are idempotent.
 */
internal class BankNativeJournal(context: Context) :
    SQLiteOpenHelper(context.applicationContext, "kopilka_native_journal.db", null, 2) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE native_entries (" +
                "notification_key TEXT PRIMARY KEY NOT NULL, " +
                "payload TEXT NOT NULL, posted_at INTEGER NOT NULL)"
        )
        db.execSQL(CREATE_ACK_TABLE)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Keep every unimported v1 payment during migration.
        if (oldVersion == 1 && newVersion == 2) db.execSQL(CREATE_ACK_TABLE)
        else throw IllegalStateException("Unsupported native journal migration")
    }

    companion object {
        private const val CREATE_ACK_TABLE =
            "CREATE TABLE native_acknowledged (" +
                "notification_key TEXT PRIMARY KEY NOT NULL, ack_at INTEGER NOT NULL)"
    }

    /** A durable replay tombstone outlives the 1000-entry preferences ring. */
    fun wasAcknowledged(key: String): Boolean {
        if (key.isBlank() || key.length > 256) return false
        readableDatabase.query("native_acknowledged", arrayOf("notification_key"),
            "notification_key = ?", arrayOf(key), null, null, null, "1").use {
            return it.moveToFirst()
        }
    }

    fun stage(candidate: Map<String, Any>): Boolean {
        val key = candidate["key"] as? String ?: return false
        val timestamp = candidate["dateMillis"] as? Long ?: return false
        if (key.isBlank() || key.length > 256 ||
            candidate["nativeClassifier"] != 1 || timestamp <= 0) return false
        return try {
            val values = ContentValues().apply {
                put("notification_key", key)
                put("payload", JSONObject(candidate).toString())
                put("posted_at", timestamp)
            }
            // Serialize staging with acknowledgement: a listener reconnect
            // must never recreate a payment that Flutter already imported.
            val db = writableDatabase
            db.beginTransaction()
            try {
                val done = db.query("native_acknowledged",
                    arrayOf("notification_key"), "notification_key = ?",
                    arrayOf(key), null, null, null, "1").use { it.moveToFirst() }
                if (done) {
                    db.setTransactionSuccessful()
                    true // Idempotent: no new record and no raw-text fallback.
                } else {
                    val inserted = db.insertWithOnConflict(
                        "native_entries", null, values, SQLiteDatabase.CONFLICT_IGNORE)
                    val durable = inserted != -1L || db.query(
                        "native_entries", arrayOf("notification_key"),
                        "notification_key = ?", arrayOf(key), null, null, null, "1"
                    ).use { it.moveToFirst() }
                    if (durable) db.setTransactionSuccessful()
                    durable
                }
            } finally {
                db.endTransaction()
            }
        } catch (_: Exception) {
            false
        }
    }

    fun pending(): JSONArray {
        val result = JSONArray()
        readableDatabase.query(
            "native_entries", arrayOf("payload"), null, null, null, null,
            "posted_at ASC, notification_key ASC"
        ).use { cursor ->
            while (cursor.moveToNext()) {
                // Corruption is a hard failure: never silently discard a row.
                result.put(JSONObject(cursor.getString(0)))
            }
        }
        return result
    }

    fun count(): Int {
        readableDatabase.rawQuery("SELECT COUNT(*) FROM native_entries", null).use {
            if (!it.moveToFirst()) error("Cannot count native journal")
            return it.getInt(0)
        }
    }

    fun acknowledge(key: String): Boolean {
        if (key.isBlank() || key.length > 256) return false
        return try {
            val db = writableDatabase
            db.beginTransaction()
            try {
                val values = ContentValues().apply {
                    put("notification_key", key)
                    put("ack_at", System.currentTimeMillis())
                }
                // Tombstone and removal must commit together, never separately.
                db.insertWithOnConflict("native_acknowledged", null, values,
                    SQLiteDatabase.CONFLICT_IGNORE)
                db.delete("native_entries", "notification_key = ?", arrayOf(key))
                db.setTransactionSuccessful()
                true
            } finally {
                db.endTransaction()
            }
        } catch (_: Exception) {
            false
        }
    }
}
