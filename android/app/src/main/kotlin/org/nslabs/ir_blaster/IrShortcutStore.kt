package org.nslabs.ir_blaster

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Persistent store for "remote-key" shortcuts created through ACTION_CREATE_SHORTCUT.
 *
 * Mirrors [IrButtonWidgetStore]: a payload is resolved to raw IR (frequency + pattern)
 * at creation time and persisted under a stable token. The token travels inside the
 * launch intent that external key-remapper tools store, so firing the shortcut never
 * needs the Flutter engine — the IR can be transmitted natively and silently.
 */
object IrShortcutStore {
    private const val PREFS_NAME = "ir_key_shortcuts"
    private const val KEY_PAYLOADS = "payloads_v1"

    fun save(context: Context, token: String, payload: IrShortcutPayload) {
        if (token.isBlank()) return
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val root = readObject(prefs.getString(KEY_PAYLOADS, null))
        root.put(token, payload.toJson())
        prefs.edit().putString(KEY_PAYLOADS, root.toString()).apply()
    }

    fun load(context: Context, token: String): IrShortcutPayload? {
        if (token.isBlank()) return null
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val root = readObject(prefs.getString(KEY_PAYLOADS, null))
        return root.optJSONObject(token)?.let { IrShortcutPayload.fromJson(it) }
    }

    fun delete(context: Context, token: String) {
        if (token.isBlank()) return
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val root = readObject(prefs.getString(KEY_PAYLOADS, null))
        root.remove(token)
        prefs.edit().putString(KEY_PAYLOADS, root.toString()).apply()
    }

    private fun readObject(raw: String?): JSONObject {
        if (raw.isNullOrBlank()) return JSONObject()
        return try {
            JSONObject(raw)
        } catch (_: Throwable) {
            JSONObject()
        }
    }
}

/** A single IR burst within a shortcut, plus how long to wait after sending it. */
data class IrShortcutStep(
    val frequencyHz: Int,
    val pattern: IntArray,
    val delayAfterMs: Int,
)

/**
 * A resolved shortcut: one or more ordered IR steps (a single button is just one step,
 * a macro is several) together with display metadata and a fallback button id used when
 * no internal IR emitter is present (USB/audio transmitters live in Flutter).
 */
data class IrShortcutPayload(
    val title: String,
    val subtitle: String,
    val fallbackButtonId: String,
    val steps: List<IrShortcutStep>,
) {
    fun toJson(): JSONObject {
        val stepsArr = JSONArray()
        steps.forEach { step ->
            val pattern = JSONArray()
            step.pattern.forEach { pattern.put(it) }
            stepsArr.put(
                JSONObject()
                    .put("frequencyHz", step.frequencyHz)
                    .put("pattern", pattern)
                    .put("delayAfterMs", step.delayAfterMs),
            )
        }
        return JSONObject()
            .put("title", title)
            .put("subtitle", subtitle)
            .put("fallbackButtonId", fallbackButtonId)
            .put("steps", stepsArr)
    }

    companion object {
        fun fromJson(obj: JSONObject): IrShortcutPayload? {
            val stepsArr = obj.optJSONArray("steps") ?: return null
            val steps = ArrayList<IrShortcutStep>(stepsArr.length())
            for (i in 0 until stepsArr.length()) {
                val stepObj = stepsArr.optJSONObject(i) ?: continue
                val freq = stepObj.optInt("frequencyHz", 0)
                val patternArr = stepObj.optJSONArray("pattern") ?: continue
                if (freq <= 0 || patternArr.length() == 0) continue
                val pattern = IntArray(patternArr.length()) { idx -> patternArr.optInt(idx, 0) }
                if (pattern.any { it <= 0 }) continue
                val delay = stepObj.optInt("delayAfterMs", 0).coerceAtLeast(0)
                steps.add(IrShortcutStep(freq, pattern, delay))
            }
            if (steps.isEmpty()) return null
            return IrShortcutPayload(
                title = obj.optString("title", "IR Button"),
                subtitle = obj.optString("subtitle", ""),
                fallbackButtonId = obj.optString("fallbackButtonId", ""),
                steps = steps,
            )
        }

        fun fromMap(map: Map<*, *>?): IrShortcutPayload? {
            if (map == null) return null
            val rawSteps = map["steps"] as? List<*> ?: return null
            val steps = ArrayList<IrShortcutStep>(rawSteps.size)
            for (raw in rawSteps) {
                val stepMap = raw as? Map<*, *> ?: continue
                val freq = (stepMap["frequencyHz"] as? Number)?.toInt()
                    ?: stepMap["frequencyHz"]?.toString()?.toIntOrNull()
                    ?: 0
                val rawPattern = stepMap["pattern"] as? List<*> ?: continue
                val pattern = rawPattern.mapNotNull {
                    when (it) {
                        is Number -> it.toInt()
                        is String -> it.toIntOrNull()
                        else -> null
                    }
                }.filter { it > 0 }.toIntArray()
                if (freq <= 0 || pattern.isEmpty()) continue
                val delay = ((stepMap["delayAfterMs"] as? Number)?.toInt()
                    ?: stepMap["delayAfterMs"]?.toString()?.toIntOrNull()
                    ?: 0).coerceAtLeast(0)
                steps.add(IrShortcutStep(freq, pattern, delay))
            }
            if (steps.isEmpty()) return null
            return IrShortcutPayload(
                title = (map["title"] as? String)?.trim().orEmpty().ifBlank { "IR Button" },
                subtitle = (map["subtitle"] as? String)?.trim().orEmpty(),
                fallbackButtonId = (map["fallbackButtonId"] as? String)?.trim().orEmpty(),
                steps = steps,
            )
        }
    }
}
