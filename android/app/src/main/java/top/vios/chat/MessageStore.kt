package top.vios.chat

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * MessageStore —— 消息与会话本地持久化（SQLite，零依赖）
 *
 * 表结构：
 *   conversations(id, type, name, lastText, lastTime, unread)
 *   messages(id, convId, role, text, reasoning, senderName, senderId, isError, mediaPath, mediaMime, mediaSize, createdAt, ttlAt)
 *
 * 说明：
 * - convId：peer 会话=对方 deviceId；AI 会话="ai"
 * - ttlAt：自动删除到期时间戳（0=永不过期）
 * - 消息 id 复用 UiMessage.id（主键，重复插入自动忽略 → 幂等）
 */
class MessageStore(context: Context) : SQLiteOpenHelper(context, "everett_chat.db", null, 1) {

    companion object {
        const val CONV_AI_ID = "ai"
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS conversations (" +
                "id TEXT PRIMARY KEY, type TEXT NOT NULL, name TEXT NOT NULL, " +
                "lastText TEXT DEFAULT '', lastTime INTEGER DEFAULT 0, unread INTEGER DEFAULT 0)"
        )
        db.execSQL(
            "CREATE TABLE IF NOT EXISTS messages (" +
                "id TEXT PRIMARY KEY, convId TEXT NOT NULL, role TEXT NOT NULL, " +
                "text TEXT DEFAULT '', reasoning TEXT DEFAULT '', senderName TEXT DEFAULT '', senderId TEXT DEFAULT '', " +
                "isError INTEGER DEFAULT 0, mediaPath TEXT DEFAULT '', mediaMime TEXT DEFAULT '', mediaSize INTEGER DEFAULT 0, " +
                "createdAt INTEGER DEFAULT 0, ttlAt INTEGER DEFAULT 0)"
        )
        db.execSQL("CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(convId, createdAt)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    // ================= 会话 =================

    fun upsertConversation(id: String, type: String, name: String, lastText: String, lastTime: Long, unread: Int) {
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("id", id); put("type", type); put("name", name)
            put("lastText", lastText); put("lastTime", lastTime); put("unread", unread)
        }
        db.insertWithOnConflict("conversations", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    /** 加载全部会话（按最后时间倒序） */
    fun loadConversations(): List<Conversation> {
        val out = mutableListOf<Conversation>()
        readableDatabase.rawQuery(
            "SELECT id, type, name, lastText, lastTime, unread FROM conversations ORDER BY lastTime DESC",
            null
        ).use { c ->
            while (c.moveToNext()) {
                out.add(
                    Conversation(
                        id = c.getString(0), type = c.getString(1), name = c.getString(2),
                        lastText = c.getString(3), lastTime = c.getLong(4), unread = c.getInt(5)
                    )
                )
            }
        }
        return out
    }

    fun deleteConversation(convId: String) {
        writableDatabase.delete("conversations", "id=?", arrayOf(convId))
        writableDatabase.delete("messages", "convId=?", arrayOf(convId))
    }

    // ================= 消息 =================

    fun insertMessage(
        id: String, convId: String, role: String, text: String, reasoning: String = "",
        senderName: String = "", senderId: String = "", isError: Boolean = false,
        mediaPath: String = "", mediaMime: String = "", mediaSize: Long = 0,
        createdAt: Long = System.currentTimeMillis(), ttlAt: Long = 0
    ) {
        val db = writableDatabase
        val cv = ContentValues().apply {
            put("id", id); put("convId", convId); put("role", role)
            put("text", text); put("reasoning", reasoning)
            put("senderName", senderName); put("senderId", senderId)
            put("isError", if (isError) 1 else 0)
            put("mediaPath", mediaPath); put("mediaMime", mediaMime); put("mediaSize", mediaSize)
            put("createdAt", createdAt); put("ttlAt", ttlAt)
        }
        db.insertWithOnConflict("messages", null, cv, SQLiteDatabase.CONFLICT_IGNORE)
    }

    /** 加载会话消息（倒序，limit 最近 N 条，返回正序列表） */
    fun loadMessages(convId: String, limit: Int = 200): List<PersistedMessage> {
        val out = mutableListOf<PersistedMessage>()
        readableDatabase.rawQuery(
            "SELECT id, role, text, reasoning, senderName, senderId, isError, mediaPath, mediaMime, mediaSize, createdAt " +
                "FROM messages WHERE convId=? ORDER BY createdAt DESC LIMIT ?",
            arrayOf(convId, limit.toString())
        ).use { c ->
            while (c.moveToNext()) {
                out.add(
                    PersistedMessage(
                        id = c.getString(0), role = c.getString(1), text = c.getString(2),
                        reasoning = c.getString(3), senderName = c.getString(4), senderId = c.getString(5),
                        isError = c.getInt(6) == 1, mediaPath = c.getString(7), mediaMime = c.getString(8),
                        mediaSize = c.getLong(9), createdAt = c.getLong(10)
                    )
                )
            }
        }
        return out.reversed()
    }

    fun deleteMessage(msgId: String) {
        writableDatabase.delete("messages", "id=?", arrayOf(msgId))
    }

    fun clearMessages(convId: String) {
        writableDatabase.delete("messages", "convId=?", arrayOf(convId))
    }

    // ================= 自动删除（TTL） =================

    /** 清理所有已到期的消息，返回删除条数 */
    fun cleanupExpired(now: Long = System.currentTimeMillis()): Int {
        return writableDatabase.delete("messages", "ttlAt > 0 AND ttlAt < ?", arrayOf(now.toString()))
    }

    /** 为某会话的全部历史消息设置 ttl（开启自动删除时调用；ttl=0 表示取消） */
    fun setTtlForConversation(convId: String, ttlMs: Long, now: Long = System.currentTimeMillis()) {
        val db = writableDatabase
        val ttlAt = if (ttlMs <= 0) 0L else now + ttlMs
        db.execSQL("UPDATE messages SET ttlAt=? WHERE convId=? AND ttlAt=0", arrayOf(ttlAt.toString(), convId))
    }

    fun getTotalMessageCount(): Long {
        readableDatabase.rawQuery("SELECT COUNT(*) FROM messages", null).use {
            return if (it.moveToFirst()) it.getLong(0) else 0
        }
    }
}

/** 持久化消息模型（DB 行 → 可转 UiMessage） */
data class PersistedMessage(
    val id: String,
    val role: String,
    val text: String,
    val reasoning: String = "",
    val senderName: String = "",
    val senderId: String = "",
    val isError: Boolean = false,
    val mediaPath: String = "",
    val mediaMime: String = "",
    val mediaSize: Long = 0,
    val createdAt: Long = 0
) {
    /** 转成 UiMessage（媒体文件需按路径重建 UiFile） */
    fun toUiMessage(): UiMessage {
        var file: UiFile? = null
        if (mediaPath.isNotEmpty()) {
            val data = try { java.io.File(mediaPath).readBytes() } catch (_: Exception) { null }
            if (data != null) {
                file = UiFile(
                    name = java.io.File(mediaPath).name,
                    size = mediaSize,
                    mime = mediaMime.ifEmpty { "application/octet-stream" },
                    data = data,
                    isIncoming = role == "peer"
                )
            }
        }
        return UiMessage(
            id = id, role = role, text = text, reasoning = reasoning,
            isError = isError, senderName = senderName, senderId = senderId,
            file = file
        )
    }
}
