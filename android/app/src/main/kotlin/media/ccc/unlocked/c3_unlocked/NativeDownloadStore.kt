package media.ccc.unlocked.c3_unlocked

import android.content.Context
import org.json.JSONObject

object NativeDownloadStore {
    private const val prefsName = "native_downloads_v1"
    private const val recordsKey = "records"

    @Synchronized
    fun save(context: Context, snapshot: Map<String, Any?>) {
        val id = snapshot["id"]?.toString() ?: return
        val records = read(context)
        records.put(id, JSONObject(snapshot))
        write(context, records)
    }

    @Synchronized
    fun get(context: Context, id: String): Map<String, Any?>? {
        val raw = read(context).optJSONObject(id) ?: return null
        return raw.toMap()
    }

    @Synchronized
    fun getAll(context: Context, ids: List<String>): List<Map<String, Any?>> {
        val records = read(context)
        return ids.mapNotNull { id -> records.optJSONObject(id)?.toMap() }
    }

    @Synchronized
    fun remove(context: Context, id: String) {
        val records = read(context)
        records.remove(id)
        write(context, records)
    }

    private fun read(context: Context): JSONObject {
        val raw = context
            .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(recordsKey, "{}")
        return try {
            JSONObject(raw ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun write(context: Context, records: JSONObject) {
        context
            .getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(recordsKey, records.toString())
            .apply()
    }
}

private fun JSONObject.toMap(): Map<String, Any?> {
    val map = mutableMapOf<String, Any?>()
    val keys = keys()
    while (keys.hasNext()) {
        val key = keys.next()
        map[key] = if (isNull(key)) null else get(key)
    }
    return map
}
