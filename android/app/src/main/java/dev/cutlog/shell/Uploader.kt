package dev.cutlog.shell

import android.webkit.CookieManager
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * 撮ったものを、そのままサーバへ上げる。
 *
 * ネイティブから直接上げているのは、動画のバイト列を JS 橋（addJavascriptInterface）に
 * 通すと文字列化で数倍に膨れて実用にならないため。Web 側には結果だけ返す。
 *
 * 認証は WebView が持っている Cookie をそのまま借りる。
 * 殻の側にログインの仕組みを持たせない（Web 側の認証が唯一の正）ため。
 */
object Uploader {

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            // 動画のアップロードは時間がかかる。書き込みだけ長めに取る。
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(5, TimeUnit.MINUTES)
            .build()
    }

    sealed class Result {
        object Ok : Result()
        data class Failed(val message: String) : Result()
    }

    /**
     * POST {baseUrl}/api/logs/{logId}/cuts
     * multipart/form-data、フィールド名は file（動画）と meta（JSON 文字列）。
     */
    fun uploadCut(baseUrl: String, logId: String, file: File, metaJson: String): Result {
        val url = "$baseUrl/api/logs/$logId/cuts"

        val body = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("file", file.name, file.asRequestBody("video/mp4".toMediaType()))
            .addFormDataPart("meta", metaJson)
            .build()

        val builder = Request.Builder().url(url).post(body)

        // WebView のセッションを流用する。無ければ付けない（サーバが 401 を返して Web 側に伝わる）。
        val cookie = runCatching { CookieManager.getInstance().getCookie(baseUrl) }.getOrNull()
        if (!cookie.isNullOrBlank()) builder.header("Cookie", cookie)

        return runCatching {
            client.newCall(builder.build()).execute().use { res ->
                if (res.isSuccessful) {
                    Result.Ok
                } else {
                    // 本文は長くなりうるので頭だけ拾う
                    val detail = res.body?.string()?.take(200).orEmpty()
                    Result.Failed("サーバが ${res.code} を返しました ${detail}".trim())
                }
            }
        }.getOrElse { e ->
            Result.Failed(e.message ?: e.javaClass.simpleName)
        }
    }
}
