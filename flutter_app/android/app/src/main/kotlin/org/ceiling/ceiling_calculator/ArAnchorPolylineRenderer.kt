package org.ceiling.ceiling_calculator

import android.opengl.GLES20
import android.opengl.Matrix
import com.google.ar.core.Anchor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/** Draws corner markers and closing polygon preview for AR floor scan. */
class ArAnchorPolylineRenderer {
    private var program = 0
    private var positionAttrib = 0
    private var mvpUniform = 0
    private var colorUniform = 0
    private val modelMatrix = FloatArray(16)
    private val mvpMatrix = FloatArray(16)

    fun createOnGlThread() {
        Matrix.setIdentityM(modelMatrix, 0)
        program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionAttrib = GLES20.glGetAttribLocation(program, "a_Position")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_MvpMatrix")
        colorUniform = GLES20.glGetUniformLocation(program, "u_Color")
    }

    fun draw(
        viewMatrix: FloatArray,
        projectionMatrix: FloatArray,
        anchors: List<Anchor>,
    ) {
        if (anchors.isEmpty()) return

        val positions = anchors.map { it.pose.translation }
        val lineVerts = mutableListOf<Float>()
        for (i in positions.indices) {
            val a = positions[i]
            val b = positions[(i + 1) % positions.size]
            if (i == positions.lastIndex && positions.size < 3) break
            lineVerts.add(a[0]); lineVerts.add(a[1] + 0.01f); lineVerts.add(a[2])
            lineVerts.add(b[0]); lineVerts.add(b[1] + 0.01f); lineVerts.add(b[2])
        }

        val markerVerts = mutableListOf<Float>()
        for (p in positions) {
            markerVerts.add(p[0]); markerVerts.add(p[1] + 0.01f); markerVerts.add(p[2])
            markerVerts.add(p[0]); markerVerts.add(p[1] + 0.15f); markerVerts.add(p[2])
        }

        val viewProjection = FloatArray(16)
        Matrix.multiplyMM(viewProjection, 0, projectionMatrix, 0, viewMatrix, 0)
        Matrix.multiplyMM(mvpMatrix, 0, viewProjection, 0, modelMatrix, 0)

        GLES20.glUseProgram(program)
        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, mvpMatrix, 0)
        GLES20.glLineWidth(6f)

        if (lineVerts.isNotEmpty()) {
            drawLines(lineVerts, 1f, 0.85f, 0.2f, 0.95f)
        }
        if (markerVerts.isNotEmpty()) {
            drawLines(markerVerts, 0.2f, 0.95f, 0.4f, 1f)
        }
    }

    private fun drawLines(
        verts: List<Float>,
        r: Float,
        g: Float,
        b: Float,
        a: Float,
    ) {
        val buffer = floatBuffer(verts.toFloatArray())
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glUniform4f(colorUniform, r, g, b, a)
        GLES20.glEnableVertexAttribArray(positionAttrib)
        GLES20.glVertexAttribPointer(positionAttrib, 3, GLES20.GL_FLOAT, false, 0, buffer)
        GLES20.glDrawArrays(GLES20.GL_LINES, 0, verts.size / 3)
        GLES20.glDisableVertexAttribArray(positionAttrib)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    companion object {
        private const val VERTEX_SHADER = """
            uniform mat4 u_MvpMatrix;
            attribute vec4 a_Position;
            void main() {
                gl_Position = u_MvpMatrix * a_Position;
            }
        """

        private const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 u_Color;
            void main() {
                gl_FragColor = u_Color;
            }
        """

        private fun floatBuffer(data: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(data.size * 4)
                .order(ByteOrder.nativeOrder())
                .asFloatBuffer()
                .put(data)
                .apply { position(0) }

        private fun createProgram(vertexSource: String, fragmentSource: String): Int {
            val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexSource)
            val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
            val prog = GLES20.glCreateProgram()
            GLES20.glAttachShader(prog, vertexShader)
            GLES20.glAttachShader(prog, fragmentShader)
            GLES20.glLinkProgram(prog)
            return prog
        }

        private fun loadShader(type: Int, code: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, code)
            GLES20.glCompileShader(shader)
            return shader
        }
    }
}
