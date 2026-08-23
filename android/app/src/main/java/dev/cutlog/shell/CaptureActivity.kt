package dev.cutlog.shell

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraMetadata
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.core.Camera
import androidx.camera.core.CameraInfo
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import dev.cutlog.shell.databinding.ActivityCaptureBinding
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.concurrent.Executors

/**
 * 撮影だけを担う画面。横向き固定。
 *
 * 撮り終えたらこの画面のままサーバへ上げ、成否だけを MainActivity に返す。
 * 動画そのものを Activity 間や JS 橋に渡さないのは、大きさの割に得が無いため。
 */
class CaptureActivity : AppCompatActivity() {

    private lateinit var binding: ActivityCaptureBinding
    private lateinit var request: CaptureRequest

    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var outputFile: File? = null
    private var startedAt: Instant? = null

    /** いま向いている面。Web の facing と同じ言葉でサーバへ送る。 */
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    private var camera: Camera? = null

    /** 位置は「取れていれば付ける」だけの添え物。撮影の流れは止めない。 */
    @Volatile
    private var lastLocation: Location? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val autoStop = Runnable { stopRecording() }

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        // カメラとマイクは必須。無ければ撮れないので、理由を付けて帰る。
        if (grants[Manifest.permission.CAMERA] == true &&
            grants[Manifest.permission.RECORD_AUDIO] == true
        ) {
            startCamera()
            requestLocationIfAllowed()
        } else {
            finishWithError("カメラまたはマイクの許可がありません")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityCaptureBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val parsed = intent.getStringExtra(EXTRA_REQUEST)?.let { CaptureRequest.parse(it) }
        if (parsed == null) {
            finishWithError("撮影の指示を読めませんでした")
            return
        }
        request = parsed

        binding.destText.text =
            if (request.logName.isBlank()) "" else "記録先 ${request.logName}"
        binding.hintText.setText(R.string.capture_preparing)
        binding.shutter.isEnabled = false
        binding.flipButton.isEnabled = false
        binding.shutter.setOnClickListener { startRecording() }
        binding.closeButton.setOnClickListener { finishWithError("撮影を取りやめました") }
        binding.flipButton.setOnClickListener { flipCamera() }
        applyBarInsets()

        // 位置は任意なので、必須の 2 つと一緒に頼んで、断られてもそのまま進む。
        permissionLauncher.launch(
            arrayOf(
                Manifest.permission.CAMERA,
                Manifest.permission.RECORD_AUDIO,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ),
        )
    }

    /**
     * 上下の帯の中身を、端末のバーや切り欠きの内側に収める。
     * ★targetSdk 35 以降は画面の端まで描くのが既定なので、
     *   入れないと閉じるボタンが切り欠きの下に潜って押せなくなる。
     */
    private fun applyBarInsets() {
        val topPadTop = binding.topBar.paddingTop
        val topPadStart = binding.topBar.paddingStart
        val topPadEnd = binding.topBar.paddingEnd
        val bottomPadBottom = binding.bottomBar.paddingBottom
        val bottomPadStart = binding.bottomBar.paddingStart
        val bottomPadEnd = binding.bottomBar.paddingEnd
        ViewCompat.setOnApplyWindowInsetsListener(binding.captureRoot) { _, insets ->
            val bars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            binding.topBar.setPaddingRelative(
                topPadStart + bars.left, topPadTop + bars.top,
                topPadEnd + bars.right, binding.topBar.paddingBottom,
            )
            binding.bottomBar.setPaddingRelative(
                bottomPadStart + bars.left, binding.bottomBar.paddingTop,
                bottomPadEnd + bars.right, bottomPadBottom + bars.bottom,
            )
            insets
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        mainHandler.removeCallbacks(autoStop)
        ioExecutor.shutdown()
    }

    // ── カメラ ──────────────────────────────────────────

    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            val provider = runCatching { future.get() }.getOrNull()
                ?: return@addListener finishWithError("カメラを開けませんでした")

            val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()
            // 端末が手ぶれ補正に対応しているかは、束ねる前に CameraInfo から見ておく。
            // 非対応の端末で有効にすると bind 時に落ちるため。
            val info = runCatching { selector.filter(provider.availableCameraInfos).firstOrNull() }
                .getOrNull()
            val videoStabilization = info != null && supportsVideoStabilization(info)
            val previewStabilization = info != null && supportsPreviewStabilization(info)

            val recorder = Recorder.Builder()
                // FHD を狙いつつ、出せない相手には順に落ちる。
                // 一段しか譲らないと、対応画質の少ない端末やエミュレータで
                // 「Unable to find supported quality」になって撮影自体ができなくなる。
                .setQualitySelector(
                    QualitySelector.fromOrderedList(
                        listOf(Quality.FHD, Quality.HD, Quality.SD),
                        FallbackStrategy.higherQualityOrLowerThan(Quality.SD),
                    ),
                )
                .build()

            val capture = VideoCapture.Builder(recorder)
                // ここが「ブラウザではできないこと」の本体。
                // 端末側の電子式手ぶれ補正（EIS）を録画に効かせる。
                // 対応可否は端末次第で、非対応なら false のまま素通しになる。
                // （実機で実際にどれだけ効くかは、この殻からは確かめられない）
                .setVideoStabilizationEnabled(videoStabilization)
                .build()

            val preview = Preview.Builder()
                // プレビューの手ぶれ補正は録画側と別枠。両方対応している端末でだけ入れる。
                .setPreviewStabilizationEnabled(previewStabilization && videoStabilization)
                .build()
                .also { it.surfaceProvider = binding.preview.surfaceProvider }

            val bound = runCatching {
                provider.unbindAll()
                provider.bindToLifecycle(this, selector, preview, capture)
            }.getOrElse {
                Log.w(TAG, "bind に失敗", it)
                return@addListener finishWithError("カメラを使えませんでした: ${it.message}")
            }

            camera = bound
            videoCapture = capture
            binding.shutter.isEnabled = true
            binding.flipButton.isEnabled = hasBothLenses(provider)
            // 端末の補正を使うことがこのアプリの目的なので、効いているかを画面に出す。
            binding.stabilizationText.text =
                "手ぶれ補正\n" + if (videoStabilization) "あり" else "この端末では使えない"
            binding.hintText.setText(R.string.capture_hint_landscape)
            buildZoomStops(bound)
        }, ContextCompat.getMainExecutor(this))
    }

    /** 前と後ろの両方があるときだけ、切り替えのボタンを効かせる。 */
    private fun hasBothLenses(provider: ProcessCameraProvider): Boolean = runCatching {
        provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) &&
            provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
    }.getOrDefault(false)

    /** Web のカメラ画面と同じく、前後を切り替えられるようにする。 */
    private fun flipCamera() {
        if (recording != null) return
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        binding.shutter.isEnabled = false
        binding.flipButton.isEnabled = false
        startCamera()
    }

    /**
     * 倍率の目印。Web の .zoom-stops と同じく、押すとその倍率に飛ぶ粒を並べる。
     * 端末が出せる範囲の中から、切りのいいところだけを拾う。
     */
    private fun buildZoomStops(bound: Camera) {
        binding.zoomRow.removeAllViews()
        val state = bound.cameraInfo.zoomState.value ?: return
        val stops = listOf(0.5f, 1f, 2f, 3f, 5f)
            .filter { it >= state.minZoomRatio && it <= state.maxZoomRatio }
        if (stops.size < 2) return
        // ★既定の画角（等倍）に合わせてから見せる。
        //   端末によっては始まりが 0.5× や中途半端な倍率になっていて、
        //   どれも選ばれていない見た目になってしまう。
        val base = if (stops.contains(1f)) 1f else stops.first()
        bound.cameraControl.setZoomRatio(base)
        val density = resources.displayMetrics.density
        for (stop in stops) {
            val button = TextView(this).apply {
                text = if (stop < 1f) "%.1f×".format(stop) else "%.0f×".format(stop)
                textSize = 11f
                gravity = Gravity.CENTER
                setBackgroundResource(R.drawable.zoom_stop_bg)
                setTextColor(ContextCompat.getColorStateList(context, R.color.zoom_stop_text))
                minWidth = (40 * density).toInt()
                setPadding((8 * density).toInt(), (5 * density).toInt(),
                    (8 * density).toInt(), (5 * density).toInt())
                isSelected = stop == base
                setOnClickListener {
                    camera?.cameraControl?.setZoomRatio(stop)
                    for (i in 0 until binding.zoomRow.childCount) {
                        binding.zoomRow.getChildAt(i).isSelected = false
                    }
                    isSelected = true
                }
            }
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                (28 * density).toInt(),
            ).apply { marginEnd = (6 * density).toInt() }
            binding.zoomRow.addView(button, lp)
        }
    }

    /**
     * 手ぶれ補正に端末が対応しているかを見る。
     *
     * CameraX 1.4 の CameraInfo にはまだ問い合わせ口が無い（1.5 で入る）ので、
     * Camera2 の特性を直接読んでいる。compileSdk を 35 に留めている都合で、
     * 新しい CameraX には上げていない。
     */
    private fun videoStabilizationModes(info: CameraInfo): IntArray =
        runCatching {
            Camera2CameraInfo.from(info)
                .getCameraCharacteristic(
                    CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES,
                )
        }.getOrNull() ?: IntArray(0)

    /** 録画そのものへの手ぶれ補正（EIS）。多くの実機で使えるが、エミュレータでは使えない。 */
    private fun supportsVideoStabilization(info: CameraInfo): Boolean =
        videoStabilizationModes(info).contains(CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_ON)

    /**
     * プレビュー側の手ぶれ補正。Android 13 (API 33) 以降かつ端末が対応している場合のみ。
     * 録画側とは別枠なので、別々に見る必要がある。
     */
    private fun supportsPreviewStabilization(info: CameraInfo): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            videoStabilizationModes(info).contains(
                CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_PREVIEW_STABILIZATION,
            )

    // ── 録画 ────────────────────────────────────────────

    @SuppressLint("MissingPermission") // 直前の permissionLauncher で確認済み
    private fun startRecording() {
        val capture = videoCapture ?: return
        if (recording != null) return

        val file = File(cacheDir, "cut_${System.currentTimeMillis()}.mp4")
        outputFile = file
        binding.shutter.isEnabled = false
        binding.closeButton.visibility = View.GONE
        binding.flipButton.visibility = View.GONE
        binding.hintText.visibility = View.GONE

        recording = capture.output
            .prepareRecording(this, FileOutputOptions.Builder(file).build())
            .withAudioEnabled()
            .start(ContextCompat.getMainExecutor(this)) { event ->
                when (event) {
                    is VideoRecordEvent.Start -> {
                        startedAt = Instant.now()
                        // 指定の秒数で自分から止める。Web 側の「◯秒のカット」に合わせるため。
                        mainHandler.postDelayed(autoStop, request.seconds * 1000L)
                        // 残り時間は輪が一周することで伝わるので、数字は出さない。
                        binding.shutter.startRecording(request.seconds.toLong())
                    }

                    is VideoRecordEvent.Finalize -> {
                        mainHandler.removeCallbacks(autoStop)
                        binding.shutter.stopRecording()
                        if (event.hasError()) {
                            file.delete()
                            finishWithError("録画に失敗しました (${event.error})")
                        } else {
                            val ms = event.recordingStats.recordedDurationNanos / 1_000_000
                            binding.shutter.visibility = View.GONE
                            binding.hintText.visibility = View.VISIBLE
                            binding.hintText.setText(R.string.capture_sending)
                            binding.busy.visibility = View.VISIBLE
                            upload(file, ms)
                        }
                    }

                    else -> Unit
                }
            }
    }

    private fun stopRecording() {
        recording?.stop()
        recording = null
    }

    // ── 送信 ────────────────────────────────────────────

    private fun upload(file: File, durationMs: Long) {
        val meta = JSONObject().apply {
            put("kind", "video")
            put("durationMs", durationMs)
            put("takenAt", DateTimeFormatter.ISO_INSTANT.format(startedAt ?: Instant.now()))
            put("tzOffset", request.tzOffset)
            // Web 側と同じ言い方に揃える（'environment' / 'user'）
            put(
                "facing",
                if (lensFacing == CameraSelector.LENS_FACING_FRONT) "user" else "environment",
            )
            put("source", "camera")
            lastLocation?.let {
                put("lat", it.latitude)
                put("lon", it.longitude)
                put("accuracy", it.accuracy.toDouble())
            }
        }.toString()

        ioExecutor.execute {
            val res = Uploader.uploadCut(request.baseUrl, request.logId, file, meta)
            file.delete()
            mainHandler.post {
                when (res) {
                    is Uploader.Result.Ok -> {
                        // 撮った日の画面を開けるよう、作られたカットの素性を持ち帰る
                        setResult(
                            RESULT_OK,
                            Intent()
                                .putExtra(EXTRA_CUT_ID, res.cutId)
                                .putExtra(EXTRA_LOG_ID, res.logId)
                                .putExtra(EXTRA_LOCAL_DATE, res.localDate),
                        )
                        finishAfterPortrait()
                    }
                    is Uploader.Result.Failed -> finishWithError(res.message)
                }
            }
        }
    }

    // ── 位置 ────────────────────────────────────────────

    @SuppressLint("MissingPermission")
    private fun requestLocationIfAllowed() {
        val granted = ContextCompat.checkSelfPermission(
            this, Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) return

        val lm = getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        // まず直近の値で埋めておく。撮り終わりまでに新しいのが来たら差し替わる。
        lastLocation = runCatching {
            lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
        }.getOrNull()

        // Play サービスに頼らず、素の LocationManager だけで済ませている
        // （セルフホスト前提のアプリに Google の依存を増やしたくないため）。
        val provider = when {
            lm.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            else -> return
        }
        // Consumer は androidx 版・java.util.function 版の両方に当たりうるので、型を明示する
        val consumer = androidx.core.util.Consumer<Location?> { loc ->
            if (loc != null) lastLocation = loc
        }
        runCatching {
            LocationManagerCompat.getCurrentLocation(
                lm, provider, null as android.os.CancellationSignal?, ioExecutor, consumer,
            )
        }
    }

    // ── 終わり方 ────────────────────────────────────────

    private fun finishWithError(message: String) {
        setResult(RESULT_CANCELED, Intent().putExtra(EXTRA_ERROR, message))
        finishAfterPortrait()
    }

    /**
     * 先に画面を縦へ戻してから閉じる。
     *
     * ★そのまま閉じると、下の Web が横のまま一瞬見えて、そのあと縦に直る。
     *   撮影画面がまだ覆っているうちに戻しておけば、その切り替わりは目に入らない。
     */
    private fun finishAfterPortrait() {
        if (requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_PORTRAIT) return
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        // 向きが変わりきるのを待つ。待たずに閉じると、戻す前の絵が見えてしまう。
        mainHandler.postDelayed({ finish() }, 250)
    }

    companion object {
        private const val TAG = "CaptureActivity"
        private const val EXTRA_REQUEST = "request"
        const val EXTRA_ERROR = "error"
        const val EXTRA_CUT_ID = "cutId"
        const val EXTRA_LOG_ID = "logId"
        const val EXTRA_LOCAL_DATE = "localDate"

        fun intentFor(context: Context, req: CaptureRequest): Intent =
            Intent(context, CaptureActivity::class.java).putExtra(
                EXTRA_REQUEST,
                JSONObject().apply {
                    put("baseUrl", req.baseUrl)
                    put("logId", req.logId)
                    put("seconds", req.seconds)
                    put("tzOffset", req.tzOffset)
                }.toString(),
            )
    }
}
