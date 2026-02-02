package com.example.insta360link_android_test

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.Image
import org.tensorflow.lite.Interpreter
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import kotlin.math.max
import kotlin.math.min

class YoloV8FaceTracker private constructor(
    modelBuffer: ByteBuffer,
    private val inputSize: Int,
    threads: Int,
) {
    data class Detection(
        val x: Float,
        val y: Float,
        val w: Float,
        val h: Float,
        val score: Float,
        val cx: Float,
        val cy: Float,
    )

    private val interpreter =
        Interpreter(
            modelBuffer,
            Interpreter.Options().apply {
                setNumThreads(threads.coerceIn(1, 8))
                setUseXNNPACK(true)
            },
        )

    private val inputBuffer =
        ByteBuffer
            .allocateDirect(1 * inputSize * inputSize * 3 * 4)
            .order(ByteOrder.nativeOrder())

    private fun yuvToRgb(y: Int, u: Int, v: Int): Triple<Float, Float, Float> {
        val yf = y.toFloat()
        val uf = (u - 128).toFloat()
        val vf = (v - 128).toFloat()
        val r = (yf + 1.402f * vf).coerceIn(0f, 255f) / 255f
        val g = (yf - 0.344136f * uf - 0.714136f * vf).coerceIn(0f, 255f) / 255f
        val b = (yf + 1.772f * uf).coerceIn(0f, 255f) / 255f
        return Triple(r, g, b)
    }

    fun detectLargest(
        image: Image,
        scoreThreshold: Float = 0.02f,
        iouThreshold: Float = 0.45f,
    ): Detection? {
        inputBuffer.rewind()
        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        val yData = ByteArray(yPlane.buffer.remaining()).also { yPlane.buffer.get(it) }
        val uData = ByteArray(uPlane.buffer.remaining()).also { uPlane.buffer.get(it) }
        val vData = ByteArray(vPlane.buffer.remaining()).also { vPlane.buffer.get(it) }

        val srcW = image.width
        val srcH = image.height

        for (iy in 0 until inputSize) {
            val sy = (iy * srcH) / inputSize
            val yRow = sy * yPlane.rowStride
            val uvRow = (sy / 2) * uPlane.rowStride
            val vRow = (sy / 2) * vPlane.rowStride
            for (ix in 0 until inputSize) {
                val sx = (ix * srcW) / inputSize
                val yIndex = yRow + sx * yPlane.pixelStride
                val uvIndex = uvRow + (sx / 2) * uPlane.pixelStride
                val vvIndex = vRow + (sx / 2) * vPlane.pixelStride
                val y = yData[yIndex].toInt() and 0xFF
                val u = uData[uvIndex].toInt() and 0xFF
                val v = vData[vvIndex].toInt() and 0xFF
                val (r, g, b) = yuvToRgb(y, u, v)
                inputBuffer.putFloat(r)
                inputBuffer.putFloat(g)
                inputBuffer.putFloat(b)
            }
        }

        val outTensor = interpreter.getOutputTensor(0)
        val shape = outTensor.shape()
        val outCount = shape.fold(1) { a, b -> a * b }
        val outBuffer = ByteBuffer.allocateDirect(outCount * 4).order(ByteOrder.nativeOrder())
        interpreter.run(inputBuffer, outBuffer)

        outBuffer.rewind()
        val out = FloatArray(outCount)
        outBuffer.asFloatBuffer().get(out)

        return parseDetections(out, shape, scoreThreshold, iouThreshold)
    }

    fun detectLargestYuyv(
        yuyv: ByteArray,
        srcW: Int,
        srcH: Int,
        scoreThreshold: Float = 0.02f,
        iouThreshold: Float = 0.45f,
    ): Detection? {
        if (srcW <= 1 || srcH <= 1) {
            return null
        }
        val expectedMin = srcW * srcH * 2
        if (yuyv.size < expectedMin) {
            return null
        }
        inputBuffer.rewind()
        for (iy in 0 until inputSize) {
            val sy = (iy * srcH) / inputSize
            val rowOff = sy * srcW * 2
            for (ix in 0 until inputSize) {
                val sx = (ix * srcW) / inputSize
                val pairX = sx and 0xFFFFFFFE.toInt()
                val base = rowOff + pairX * 2
                if (base + 3 >= yuyv.size) {
                    inputBuffer.putFloat(0f)
                    inputBuffer.putFloat(0f)
                    inputBuffer.putFloat(0f)
                    continue
                }
                val y0 = yuyv[base].toInt() and 0xFF
                val u = yuyv[base + 1].toInt() and 0xFF
                val y1 = yuyv[base + 2].toInt() and 0xFF
                val v = yuyv[base + 3].toInt() and 0xFF
                val y = if ((sx and 1) == 0) y0 else y1
                val (r, g, b) = yuvToRgb(y, u, v)
                inputBuffer.putFloat(r)
                inputBuffer.putFloat(g)
                inputBuffer.putFloat(b)
            }
        }
        return runModel(scoreThreshold, iouThreshold)
    }

    fun detectLargestMjpeg(
        jpegBytes: ByteArray,
        scoreThreshold: Float = 0.02f,
        iouThreshold: Float = 0.45f,
    ): Detection? {
        val bmp = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size) ?: return null
        val scaled = Bitmap.createScaledBitmap(bmp, inputSize, inputSize, true)
        val pixels = IntArray(inputSize * inputSize)
        scaled.getPixels(pixels, 0, inputSize, 0, 0, inputSize, inputSize)
        inputBuffer.rewind()
        for (p in pixels) {
            val r = ((p shr 16) and 0xFF) / 255f
            val g = ((p shr 8) and 0xFF) / 255f
            val b = (p and 0xFF) / 255f
            inputBuffer.putFloat(r)
            inputBuffer.putFloat(g)
            inputBuffer.putFloat(b)
        }
        if (scaled !== bmp) {
            scaled.recycle()
        }
        bmp.recycle()
        return runModel(scoreThreshold, iouThreshold)
    }

    private fun runModel(scoreThreshold: Float, iouThreshold: Float): Detection? {
        val outTensor = interpreter.getOutputTensor(0)
        val shape = outTensor.shape()
        val outCount = shape.fold(1) { a, b -> a * b }
        val outBuffer = ByteBuffer.allocateDirect(outCount * 4).order(ByteOrder.nativeOrder())
        interpreter.run(inputBuffer, outBuffer)
        outBuffer.rewind()
        val out = FloatArray(outCount)
        outBuffer.asFloatBuffer().get(out)
        return parseDetections(out, shape, scoreThreshold, iouThreshold)
    }

    private fun parseDetections(
        out: FloatArray,
        shape: IntArray,
        scoreThreshold: Float,
        iouThreshold: Float,
    ): Detection? {
        if (shape.size < 2) {
            return null
        }

        val layout = resolveLayout(shape)
        if (layout.attrs < 5 || layout.count <= 0) {
            return null
        }

        val candidates = ArrayList<Detection>(layout.count)
        val fallbackCandidates = ArrayList<Detection>(layout.count)

        fun valueAt(detIdx: Int, attrIdx: Int): Float {
            return if (layout.attrMajor) {
                out[attrIdx * layout.count + detIdx]
            } else {
                out[detIdx * layout.attrs + attrIdx]
            }
        }

        for (i in 0 until layout.count) {
            val rawX = valueAt(i, 0)
            val rawY = valueAt(i, 1)
            val rawW = valueAt(i, 2)
            val rawH = valueAt(i, 3)

            var score = valueAt(i, 4)
            if (score < 0f || score > 1f) {
                score = sigmoid(score)
            }
            val extraAttrs = layout.attrs - 5
            // Face heads commonly use [x,y,w,h,obj + landmarks] with no class logits.
            // Only treat extra attrs as class logits when their count looks like a small class set.
            if (extraAttrs in 1..8) {
                var clsMax = 0f
                for (c in 5 until layout.attrs) {
                    var cls = valueAt(i, c)
                    if (cls < 0f || cls > 1f) {
                        cls = sigmoid(cls)
                    }
                    clsMax = max(clsMax, cls)
                }
                score *= clsMax
            }
            if (score < scoreThreshold) {
                continue
            }

            val scale = if (max(max(rawX, rawY), max(rawW, rawH)) > 2f) inputSize.toFloat() else 1f
            val cx = (rawX / scale).coerceIn(0f, 1f)
            val cy = (rawY / scale).coerceIn(0f, 1f)
            val bw = (rawW / scale).coerceIn(0f, 1f)
            val bh = (rawH / scale).coerceIn(0f, 1f)

            val x1 = (cx - bw / 2f).coerceIn(0f, 1f)
            val y1 = (cy - bh / 2f).coerceIn(0f, 1f)
            val x2 = (cx + bw / 2f).coerceIn(0f, 1f)
            val y2 = (cy + bh / 2f).coerceIn(0f, 1f)
            val w = (x2 - x1).coerceAtLeast(0f)
            val h = (y2 - y1).coerceAtLeast(0f)
            if (w <= 0f || h <= 0f) {
                continue
            }
            val det =
                Detection(
                    x = x1,
                    y = y1,
                    w = w,
                    h = h,
                    score = score,
                    cx = x1 + w / 2f,
                    cy = y1 + h / 2f,
                )
            if (score >= scoreThreshold) {
                candidates.add(det)
            }
            if (w >= 0.03f && h >= 0.03f) {
                fallbackCandidates.add(det)
            }
        }

        if (candidates.isEmpty()) {
            return fallbackCandidates.maxByOrNull { it.w * it.h }
        }

        val sorted = candidates.sortedByDescending { it.score }
        val kept = ArrayList<Detection>(sorted.size)
        for (cand in sorted) {
            var keep = true
            for (picked in kept) {
                if (iou(cand, picked) > iouThreshold) {
                    keep = false
                    break
                }
            }
            if (keep) {
                kept.add(cand)
            }
        }

        return kept.maxByOrNull { it.w * it.h }
    }

    private fun iou(a: Detection, b: Detection): Float {
        val ax1 = a.x
        val ay1 = a.y
        val ax2 = a.x + a.w
        val ay2 = a.y + a.h

        val bx1 = b.x
        val by1 = b.y
        val bx2 = b.x + b.w
        val by2 = b.y + b.h

        val interW = (min(ax2, bx2) - max(ax1, bx1)).coerceAtLeast(0f)
        val interH = (min(ay2, by2) - max(ay1, by1)).coerceAtLeast(0f)
        val inter = interW * interH
        if (inter <= 0f) {
            return 0f
        }

        val areaA = a.w * a.h
        val areaB = b.w * b.h
        val denom = areaA + areaB - inter
        return if (denom > 0f) inter / denom else 0f
    }

    private data class Layout(val count: Int, val attrs: Int, val attrMajor: Boolean)

    private fun sigmoid(x: Float): Float {
        return (1f / (1f + kotlin.math.exp(-x)))
    }

    private fun resolveLayout(shape: IntArray): Layout {
        if (shape.size == 2) {
            return Layout(count = shape[0], attrs = shape[1], attrMajor = false)
        }

        val d1 = shape[1]
        val d2 = shape[2]

        if (d1 in 5..64 && d2 > d1) {
            return Layout(count = d2, attrs = d1, attrMajor = true)
        }
        if (d2 in 5..64 && d1 > d2) {
            return Layout(count = d1, attrs = d2, attrMajor = false)
        }

        return Layout(count = d1, attrs = d2, attrMajor = false)
    }

    fun close() {
        interpreter.close()
    }

    companion object {
        private fun mapAsset(assetManager: AssetManager, assetPath: String): MappedByteBuffer {
            val afd = assetManager.openFd(assetPath)
            FileInputStream(afd.fileDescriptor).channel.use { channel ->
                return channel.map(
                    FileChannel.MapMode.READ_ONLY,
                    afd.startOffset,
                    afd.declaredLength,
                )
            }
        }

        private fun mapFile(path: String): MappedByteBuffer {
            FileInputStream(File(path)).channel.use { channel ->
                return channel.map(FileChannel.MapMode.READ_ONLY, 0, channel.size())
            }
        }

        fun create(
            assetManager: AssetManager,
            modelAssetCandidates: List<String>,
            modelFileCandidates: List<String> = emptyList(),
            inputSize: Int = 320,
            threads: Int = 4,
        ): YoloV8FaceTracker {
            var lastError: Throwable? = null
            for (candidate in modelAssetCandidates) {
                try {
                    return YoloV8FaceTracker(mapAsset(assetManager, candidate), inputSize, threads)
                } catch (t: Throwable) {
                    lastError = t
                }
            }
            for (candidate in modelFileCandidates) {
                try {
                    return YoloV8FaceTracker(mapFile(candidate), inputSize, threads)
                } catch (t: Throwable) {
                    lastError = t
                }
            }
            throw IllegalStateException("Unable to load YOLOv8n-face model.", lastError)
        }
    }
}
