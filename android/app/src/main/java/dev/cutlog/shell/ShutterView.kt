package dev.cutlog.shell

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator

/**
 * Web の撮影ボタン（.shutter）と同じ見た目のボタン。
 *
 * 白い輪の中に赤い丸があり、録っているあいだは丸が角丸の四角に縮み、
 * 外側の輪が 1 カットぶんの長さでちょうど一周する。
 * 残り時間をこの輪だけで伝えるので、数字は出さない。
 *
 * 殻の中と外で当たりを変えたくないので、Web の寸法（78dp / 内側 58dp / 線 5dp）に合わせている。
 */
class ShutterView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0,
) : View(context, attrs, defStyleAttr) {

    private val density = resources.displayMetrics.density
    private val ringWidth = 5f * density
    private val dotIdle = 58f * density
    private val dotRecording = 26f * density
    private val cornerIdle = dotIdle / 2f
    private val cornerRecording = 6f * density

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = ringWidth
        strokeCap = Paint.Cap.ROUND
        color = Color.argb(82, 255, 255, 255)   // rgba(255,255,255,.32)
    }
    private val runPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = ringWidth
        strokeCap = Paint.Cap.ROUND
        color = Color.WHITE
    }
    private val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#e5484d")
    }

    private val ringRect = RectF()
    private val dotRect = RectF()

    private var progress = 0f
    private var dotSize = dotIdle
    private var dotCorner = cornerIdle

    private var ringAnimator: ValueAnimator? = null
    private var dotAnimator: ValueAnimator? = null

    init {
        isClickable = true
        contentDescription = context.getString(R.string.capture_start)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val size = (78f * density).toInt()
        setMeasuredDimension(
            resolveSize(size, widthMeasureSpec),
            resolveSize(size, heightMeasureSpec),
        )
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        val inset = ringWidth / 2f
        ringRect.set(inset, inset, w - inset, h - inset)
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawArc(ringRect, -90f, 360f, false, trackPaint)
        if (progress > 0f) {
            canvas.drawArc(ringRect, -90f, 360f * progress, false, runPaint)
        }
        val cx = width / 2f
        val cy = height / 2f
        dotRect.set(cx - dotSize / 2f, cy - dotSize / 2f, cx + dotSize / 2f, cy + dotSize / 2f)
        canvas.drawRoundRect(dotRect, dotCorner, dotCorner, dotPaint)
    }

    /** 録り始める。[seconds] かけて外周が一周する。 */
    fun startRecording(seconds: Long) {
        ringAnimator?.cancel()
        ringAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = seconds * 1000L
            interpolator = LinearInterpolator()
            addUpdateListener { progress = it.animatedValue as Float; invalidate() }
            start()
        }
        animateDot(dotRecording, cornerRecording)
    }

    /** 止める。輪は消し、丸は元の大きさに戻す。 */
    fun stopRecording() {
        ringAnimator?.cancel()
        ringAnimator = null
        progress = 0f
        animateDot(dotIdle, cornerIdle)
        invalidate()
    }

    private fun animateDot(toSize: Float, toCorner: Float) {
        val fromSize = dotSize
        val fromCorner = dotCorner
        dotAnimator?.cancel()
        dotAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 160
            addUpdateListener {
                val t = it.animatedValue as Float
                dotSize = fromSize + (toSize - fromSize) * t
                dotCorner = fromCorner + (toCorner - fromCorner) * t
                invalidate()
            }
            start()
        }
    }

    override fun setEnabled(enabled: Boolean) {
        super.setEnabled(enabled)
        alpha = if (enabled) 1f else 0.4f
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        ringAnimator?.cancel()
        dotAnimator?.cancel()
    }
}
