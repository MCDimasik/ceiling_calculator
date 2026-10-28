package org.ceiling.ceiling_calculator

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Bundle
import android.view.MotionEvent
import android.view.Gravity
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableException
import java.util.ArrayList
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.atan2

/**
 * Tap floor corners in AR → closed polygon → walls in cm (same format as RoomPlan import).
 */
class ArCornerScanActivity : AppCompatActivity(), GLSurfaceView.Renderer {
    private lateinit var surfaceView: GLSurfaceView
    private lateinit var statusText: TextView
    private var session: Session? = null
    private var installRequested = false
    private val anchors = mutableListOf<Anchor>()
    private val viewMatrix = FloatArray(16)
    private val projectionMatrix = FloatArray(16)
    private val backgroundRenderer = ArBackgroundRenderer()
    private val polylineRenderer = ArAnchorPolylineRenderer()
    private var backgroundReady = false
    private var previousUncaught: Thread.UncaughtExceptionHandler? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Never let an AR/native failure take down the whole Flutter process.
        previousUncaught = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                abortWithMessage("AR сбой: ${e.message ?: e.javaClass.simpleName}")
            } catch (_: Exception) {
                previousUncaught?.uncaughtException(t, e)
            }
        }

        val root = FrameLayout(this)
        surfaceView = GLSurfaceView(this).apply {
            preserveEGLContextOnPause = true
            setEGLContextClientVersion(2)
            setRenderer(this@ArCornerScanActivity)
            setOnTouchListener { _, event ->
                if (event.action == MotionEvent.ACTION_UP) {
                    handleTap(event.x, event.y)
                }
                true
            }
        }
        root.addView(surfaceView, FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)

        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 24, 24, 48)
        }
        statusText = TextView(this).apply {
            setTextColor(0xFFFFFFFF.toInt())
            textSize = 16f
            text = "Наведите на пол и тапайте углы (мин. 3)"
        }
        panel.addView(statusText)

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val undoBtn = Button(this).apply {
            text = "Отменить угол"
            setOnClickListener { undoLastCorner() }
        }
        row.addView(undoBtn)
        val doneBtn = Button(this).apply {
            text = "Готово"
            setOnClickListener { finishWithWalls() }
        }
        row.addView(doneBtn)
        panel.addView(row)

        val cancelBtn = Button(this).apply {
            text = "Отмена"
            setOnClickListener {
                setResult(RESULT_CANCELED)
                finish()
            }
        }
        panel.addView(cancelBtn)

        val panelLp = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
        ).apply { gravity = Gravity.BOTTOM }
        root.addView(panel, panelLp)
        setContentView(root)

        if (!hasCameraPermission()) {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    private val cameraPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (!granted) {
                Toast.makeText(this, "Нужна камера для AR", Toast.LENGTH_LONG).show()
                setResult(RESULT_CANCELED)
                finish()
            }
        }

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    override fun onResume() {
        super.onResume()
        if (!hasCameraPermission()) return
        if (session == null) {
            try {
                when (ArCoreApk.getInstance().requestInstall(this, !installRequested)) {
                    ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                        installRequested = true
                        return
                    }
                    ArCoreApk.InstallStatus.INSTALLED -> {}
                }
                session = Session(this).apply {
                    configure(Config(this).apply {
                        focusMode = Config.FocusMode.AUTO
                        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                    })
                }
            } catch (e: UnavailableException) {
                openArCorePlayStore()
                abortWithMessage(
                    "Нужен Google Play Services for AR — откройте установку в Маркете",
                )
                return
            } catch (e: Exception) {
                openArCorePlayStore()
                abortWithMessage(
                    "ARCore: ${e.message ?: "установите Google Play Services for AR"}",
                )
                return
            }
        }
        try {
            session?.resume()
            surfaceView.onResume()
        } catch (e: CameraNotAvailableException) {
            abortWithMessage("Камера недоступна")
        } catch (e: Exception) {
            abortWithMessage("AR: ${e.message ?: "ошибка камеры"}")
        }
    }

    private fun abortWithMessage(message: String) {
        try {
            Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        } catch (_: Exception) {
        }
        try {
            setResult(RESULT_CANCELED)
            finish()
        } catch (_: Exception) {
        }
    }

    private fun openArCorePlayStore() {
        val market = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("market://details?id=com.google.ar.core"),
        )
        val web = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://play.google.com/store/apps/details?id=com.google.ar.core"),
        )
        try {
            startActivity(market)
        } catch (_: ActivityNotFoundException) {
            try {
                startActivity(web)
            } catch (_: Exception) {
            }
        } catch (_: Exception) {
            try {
                startActivity(web)
            } catch (_: Exception) {
            }
        }
    }

    override fun onPause() {
        super.onPause()
        surfaceView.onPause()
        session?.pause()
    }

    override fun onDestroy() {
        anchors.forEach { it.detach() }
        anchors.clear()
        session?.close()
        session = null
        Thread.setDefaultUncaughtExceptionHandler(previousUncaught)
        previousUncaught = null
        super.onDestroy()
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1f)
        backgroundRenderer.createOnGlThread()
        polylineRenderer.createOnGlThread()
        backgroundReady = true
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        session?.setDisplayGeometry(display.rotation, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val s = session ?: return
        if (!backgroundReady) return
        try {
            s.setCameraTextureName(backgroundRenderer.cameraTextureId)
            val frame = s.update()
            if (frame.camera.trackingState != TrackingState.TRACKING) return
            backgroundRenderer.draw(frame)
            frame.camera.getViewMatrix(viewMatrix, 0)
            frame.camera.getProjectionMatrix(projectionMatrix, 0, 0.1f, 100f)
            synchronized(anchors) {
                polylineRenderer.draw(viewMatrix, projectionMatrix, anchors)
            }
        } catch (_: Exception) {
        }
    }

    private fun handleTap(x: Float, y: Float) {
        val s = session ?: return
        val frame: Frame = try {
            s.update()
        } catch (_: Exception) {
            return
        }
        if (frame.camera.trackingState != TrackingState.TRACKING) {
            runOnUiThread {
                Toast.makeText(this, "Дождитесь трекинга AR", Toast.LENGTH_SHORT).show()
            }
            return
        }
        val hits = frame.hitTest(x, y)
        for (hit: HitResult in hits) {
            val trackable = hit.trackable
            if (trackable is Plane && trackable.isPoseInPolygon(hit.hitPose)) {
                synchronized(anchors) {
                    anchors.add(hit.createAnchor())
                }
                runOnUiThread { updateStatus() }
                return
            }
        }
        runOnUiThread {
            Toast.makeText(this, "Тап по полу не найден", Toast.LENGTH_SHORT).show()
        }
    }

    private fun undoLastCorner() {
        synchronized(anchors) {
            if (anchors.isEmpty()) {
                Toast.makeText(this, "Нет углов для отмены", Toast.LENGTH_SHORT).show()
                return
            }
            anchors.removeLast().detach()
        }
        updateStatus()
    }

    private fun updateStatus() {
        val n = synchronized(anchors) { anchors.size }
        statusText.text = if (n >= 3) {
            "Углов: $n — можно «Готово»"
        } else {
            "Углов: $n (мин. 3, затем «Готово»)"
        }
    }

    private fun finishWithWalls() {
        val count = synchronized(anchors) { anchors.size }
        if (count < 3) {
            Toast.makeText(this, "Нужно минимум 3 угла", Toast.LENGTH_SHORT).show()
            return
        }
        val points = synchronized(anchors) {
            anchors.map {
                val t = it.pose.translation
                Pair(t[0].toDouble(), t[2].toDouble())
            }
        }
        val walls = cornersToWalls(points)
        val arr = org.json.JSONArray()
        for (wall in walls) {
            val w = org.json.JSONArray()
            for (v in wall) w.put(v)
            arr.put(w)
        }
        val data = Intent().apply {
            putExtra(EXTRA_WALLS_JSON, arr.toString())
        }
        setResult(RESULT_OK, data)
        finish()
    }

    companion object {
        const val EXTRA_WALLS_JSON = "walls_json"

        fun cornersToWalls(corners: List<Pair<Double, Double>>): ArrayList<ArrayList<Double>> {
            if (corners.size < 3) return arrayListOf()
            val cx = corners.map { it.first }.average()
            val cy = corners.map { it.second }.average()
            val sorted = corners.sortedBy { atan2(it.second - cy, it.first - cx) }
            val cm = sorted.map { Pair(it.first * 100.0, it.second * 100.0) }
            val minX = cm.minOf { it.first }
            val minY = cm.minOf { it.second }
            val norm = cm.map { Pair(it.first - minX, it.second - minY) }
            val out = arrayListOf<ArrayList<Double>>()
            for (i in norm.indices) {
                val p1 = norm[i]
                val p2 = norm[(i + 1) % norm.size]
                out.add(arrayListOf(p1.first, p1.second, p2.first, p2.second))
            }
            return out
        }
    }
}
