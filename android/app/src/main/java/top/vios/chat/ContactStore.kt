package top.vios.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * 通讯录管理（好友系统）
 * 好友关系持久化在 SharedPreferences，可长期通信。
 *
 * 好友状态:
 *   pending  - 已发送请求，等待对方同意
 *   approved - 已是好友（可长期通信）
 */
data class Contact(
    val deviceId: String,      // 对方设备唯一 ID
    val name: String,          // 对方名称
    val status: String = "approved",  // pending | approved
    val addedTime: Long = System.currentTimeMillis()
) {
    fun toJson(): JSONObject = JSONObject()
        .put("deviceId", deviceId)
        .put("name", name)
        .put("status", status)
        .put("addedTime", addedTime)

    companion object {
        fun fromJson(o: JSONObject) = Contact(
            deviceId = o.optString("deviceId", ""),
            name = o.optString("name", "未知设备"),
            status = o.optString("status", "approved"),
            addedTime = o.optLong("addedTime", System.currentTimeMillis())
        )
    }
}

/** 通讯录存储（SharedPreferences 持久化） */
object ContactStore {

    private const val PREF = "everett_contacts"
    private const val KEY_CONTACTS = "contacts"

    fun getContacts(context: Context): List<Contact> {
        return try {
            val json = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
                .getString(KEY_CONTACTS, "[]").orEmpty()
            val arr = JSONArray(json)
            (0 until arr.length()).map { Contact.fromJson(arr.getJSONObject(it)) }
        } catch (_: Exception) { emptyList() }
    }

    fun saveContacts(context: Context, contacts: List<Contact>) {
        val arr = JSONArray()
        contacts.forEach { arr.put(it.toJson()) }
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .edit().putString(KEY_CONTACTS, arr.toString()).apply()
    }

    /** 添加好友（或更新状态） */
    fun upsertContact(context: Context, contact: Contact) {
        val list = getContacts(context).toMutableList()
        val idx = list.indexOfFirst { it.deviceId == contact.deviceId }
        if (idx >= 0) {
            list[idx] = contact
        } else {
            list.add(contact)
        }
        saveContacts(context, list)
    }

    /** 按设备 ID 查找好友 */
    fun find(context: Context, deviceId: String): Contact? =
        getContacts(context).firstOrNull { it.deviceId == deviceId }

    /** 移除好友 */
    fun remove(context: Context, deviceId: String) {
        saveContacts(context, getContacts(context).filterNot { it.deviceId == deviceId })
    }

    /** 同意好友请求 */
    fun approve(context: Context, deviceId: String, name: String) {
        upsertContact(context, Contact(deviceId, name, "approved"))
    }
}
