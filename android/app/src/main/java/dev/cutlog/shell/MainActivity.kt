package dev.cutlog.shell

import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.View
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import dev.cutlog.shell.databinding.ActivityMainBinding
import org.json.JSONObject

/**
 * cutlog の殻。画面は WebView 一枚で、Web 本体をそのまま映す。
 * ネイティブが引き受けるのは撮影だけ（端末の手ぶれ補正や画づくりを通したいため）。
 *
 * つなぐ先はビルドのときに BuildConfig.BASE_URL へ埋め込まれる
 * （リポジトリのルートの native.env が元）。アプリの中では設定させない。
 */
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding

    private val captureLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        // 撮影画面は「上げ終わったかどうか」だけを返す。動画そのものは橋に通さない。
        if (result.resultCode == Activity.RESULT_OK) {
            sendResultToWeb(
                ok = true,
                error = null,
                cutId = result.data?.getStringExtra(CaptureActivity.EXTRA_CUT_ID),
                logId = result.data?.getStringExtra(CaptureActivity.EXTRA_LOG_ID),
                localDate = result.data?.getStringExtra(CaptureActivity.EXTRA_LOCAL_DATE),
            )
        } else {
            val err = result.data?.getStringExtra(CaptureActivity.EXTRA_ERROR)
            sendResultToWeb(false, err ?: "撮影を取りやめました")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setUpWebView()
        binding.errorTarget.text = BuildConfig.BASE_URL
        binding.retryButton.setOnClickListener { loadSite() }

        // 端末の「戻る」は、まず Web の履歴を戻す。Web に戻り先が無いときだけアプリを閉じる。
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (binding.errorPanel.visibility != View.VISIBLE && binding.webView.canGoBack()) {
                    binding.webView.goBack()
                } else {
                    isEnabled = false
                    onBackPressedDispatcher.onBackPressed()
                }
            }
        })

        // 端末のバーや切り欠きの寸法を Web に伝える。下の「切り欠きの逃げ」を参照。
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { _, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            val d = resources.displayMetrics.density
            safeAreaTopPx = (bars.top / d).toInt()
            safeAreaBottomPx = (bars.bottom / d).toInt()
            sendSafeAreaInsets()
            insets
        }

        loadSite()
    }

    // ── 切り欠きの逃げ ──────────────────────────────────
    //
    // ★targetSdk 35 以降、画面は端まで使う作りが既定になり、
    //   WebView がステータスバーや切り欠きの下にも描かれる。
    //   Web の CSS の env(safe-area-inset-*) は Android の WebView では当てにならないので、
    //   本当の寸法をこちらから CSS 変数として入れ直す。
    //   Web 側は env() を直に読まず --sa-top / --sa-bottom を見るようにしてある。
    private var safeAreaTopPx = 0
    private var safeAreaBottomPx = 0

    private fun sendSafeAreaInsets() {
        val js = "(function(){var r=document.documentElement; if(!r){return false;}" +
            "r.style.setProperty('--sa-top','${safeAreaTopPx}px');" +
            "r.style.setProperty('--sa-bottom','${safeAreaBottomPx}px'); return true;})();"
        binding.webView.evaluateJavascript(js, null)
    }

    // ── WebView まわり ──────────────────────────────────

    @SuppressLint("SetJavaScriptEnabled")
    private fun setUpWebView() {
        val wv = binding.webView
        wv.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            // 撮影プレビューや再生を、いちいち画面を触らせずに始められるようにする
            mediaPlaybackRequiresUserGesture = false
            // Web 側が固有のレイアウトを持つので、勝手な拡大縮小はさせない
            useWideViewPort = true
            loadWithOverviewMode = true
        }
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(wv, true)

        // 開発中だけ、外から WebView の中を覗けるようにする。
        // これが無いと chrome://inspect も CDP も繋がらず、
        // 画面の中で何が起きているのかを確かめる手立てが無くなる。
        // 配布するビルドでは付かない。
        if (BuildConfig.DEBUG) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        // Web 側は window.CutlogNative.capture(jsonString) を呼ぶ約束
        wv.addJavascriptInterface(Bridge(), "CutlogNative")

        wv.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
                // 読んでいる間はぐるぐるを出す（まっさらな画面で待たせない）
                binding.loading.visibility = View.VISIBLE
            }

            override fun onPageFinished(view: WebView, url: String) {
                binding.loading.visibility = View.GONE
                // 開けたら覆いは外す（再試行で戻ってきた場合のため）
                binding.errorPanel.visibility = View.GONE
                // 読み込みのたびに入れ直す。新しい document には前の指定が残らないため。
                sendSafeAreaInsets()
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceError,
            ) {
                // 主フレームが開けないときだけ知らせる。画像 1 枚の失敗で画面を奪わない。
                if (request.isForMainFrame) {
                    binding.loading.visibility = View.GONE
                    showError(error.description?.toString())
                }
            }
        }

        wv.webChromeClient = object : WebChromeClient() {
            // Web 側が（殻が居ないと思って）getUserMedia に落ちたときのための保険。
            // すでに端末の許可がある場合だけ通す。無い状態でここから要求はしない。
            override fun onPermissionRequest(request: PermissionRequest) {
                val granted = request.resources.filter { res ->
                    when (res) {
                        PermissionRequest.RESOURCE_VIDEO_CAPTURE ->
                            hasPermission(android.Manifest.permission.CAMERA)
                        PermissionRequest.RESOURCE_AUDIO_CAPTURE ->
                            hasPermission(android.Manifest.permission.RECORD_AUDIO)
                        else -> false
                    }
                }
                if (granted.isEmpty()) request.deny() else request.grant(granted.toTypedArray())
            }
        }
    }

    private fun hasPermission(name: String) =
        ContextCompat.checkSelfPermission(this, name) == PackageManager.PERMISSION_GRANTED

    private fun loadSite() {
        binding.errorPanel.visibility = View.GONE
        binding.webView.loadUrl(BuildConfig.BASE_URL)
    }

    private fun showError(detail: String?) {
        binding.errorDetail.text = detail.orEmpty()
        binding.errorPanel.visibility = View.VISIBLE
    }

    // ── JS 橋 ────────────────────────────────────────────

    inner class Bridge {
        /**
         * web → native の入口。
         * json: { type:"capture", baseUrl, logId, seconds, tzOffset }
         *
         * この呼び出しは WebView の別スレッドから来るので、UI 操作は必ず主スレッドへ移す。
         */
        @JavascriptInterface
        fun capture(json: String) {
            val req = CaptureRequest.parse(json)
            runOnUiThread {
                if (req == null) {
                    sendResultToWeb(false, "撮影の指示を読めませんでした")
                    return@runOnUiThread
                }
                captureLauncher.launch(CaptureActivity.intentFor(this@MainActivity, req))
            }
        }
    }

    /**
     * native → web。window.cutlogNative.onResult({ ok, error, cutId, logId, localDate }) を呼ぶ。
     *
     * うまくいったときにカットの素性まで返すのは、Web 側が
     * 「撮った日の画面を開いて、いま撮ったところから流す」ところまで進めるようにするためである。
     */
    private fun sendResultToWeb(
        ok: Boolean,
        error: String?,
        cutId: String? = null,
        logId: String? = null,
        localDate: String? = null,
    ) {
        val payload = JSONObject().apply {
            put("ok", ok)
            if (error != null) put("error", error)
            if (cutId != null) put("cutId", cutId)
            if (logId != null) put("logId", logId)
            if (localDate != null) put("localDate", localDate)
        }
        // Web 側が古くて窓口が無いこともあるので、存在を見てから呼ぶ
        val js = "if (window.cutlogNative && window.cutlogNative.onResult)" +
            " { window.cutlogNative.onResult($payload); }"
        binding.webView.evaluateJavascript(js, null)
    }
}
