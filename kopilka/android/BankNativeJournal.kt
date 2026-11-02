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
    SQLiteOpenHelper(context.applicationContext, "kopilka_native_journal.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE native_entries (" +
                "notification_key TEXT PRIMARY KEY NOT NULL, " +
                "payload TEXT NOT NULL, posted_at INTEGER NOT NULL)"
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // Never drop financial records during a schema migration.
        throw IllegalStateException("Native finance journal requires migration")
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
            // Duplicate notifications do not replace existing records.
            val db = writableDatabase
            val inserted = db.insertWithOnConflict(
                "native_entries", null, values, SQLiteDatabase.CONFLICT_IGNORE)
            if (inserted != -1L) {
                true
            } else {
                // CONFLICT_IGNORE returns -1 for an existing key. Treat that
                // as idempotent success only after verifying the durable row.
                // Never claim an event was staged when SQLite did not write it.
                db.query(
                    "native_entries", arrayOf("notification_key"),
                    "notification_key = ?", arrayOf(key), null, null, null, "1"
                ).use { it.moveToFirst() }
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
            writableDatabase.delete(
                "native_entries", "notification_key = ?", arrayOf(key))
            true
        } catch (_: Exception) {
            false
        }
    }
}
