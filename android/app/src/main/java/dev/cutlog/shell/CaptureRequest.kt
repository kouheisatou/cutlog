package dev.cutlog.shell

import org.json.JSONObject

/**
 * Web から降りてくる撮影の注文。
 * 契約（web/app.js の nativeShell と合わせてある）:
 *   { type:"capture", baseUrl, logId, logName, seconds, tzOffset }
 */
data class CaptureRequest(
    val baseUrl: String,
    val logId: String,
    /** 記録先の名前。撮影画面の上に出すためだけに使う（空でも撮影はできる）。 */
    val logName: String,
    val seconds: Int,
    val tzOffset: Int,
) {
    companion object {
        /** 壊れた JSON や欠けた項目は、その場で例外にせず null にして呼び手に返させる。 */
        fun parse(json: String): CaptureRequest? = runCatching {
            val o = JSONObject(json)
            // baseUrl は Web が location.origin を入れてくる。
            // 万一空でも、埋め込み済みの行き先で代用する（撮影を落とさないため）。
            val baseUrl = o.optString("baseUrl").trimEnd('/')
                .ifEmpty { BuildConfig.BASE_URL }
            val logId = o.optString("logId")
            if (logId.isEmpty()) return null
            CaptureRequest(
                baseUrl = baseUrl,
                logId = logId,
                logName = o.optString("logName"),
                // 秒数は Web 側の設定次第。極端な値でも端末が固まらないよう挟んでおく。
                seconds = o.optInt("seconds", 5).coerceIn(1, 120),
                tzOffset = o.optInt("tzOffset", 0),
            )
        }.getOrNull()
    }
}
