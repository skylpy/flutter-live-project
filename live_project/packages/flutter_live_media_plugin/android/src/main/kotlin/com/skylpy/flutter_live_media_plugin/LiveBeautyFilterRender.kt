package com.skylpy.flutter_live_media_plugin

import android.content.Context
import android.opengl.GLES20
import android.opengl.Matrix
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import com.pedro.encoder.utils.gl.GlUtil
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * RootEncoder 的编码前 OpenGL 美颜滤镜。
 *
 * 这个 Filter 运行在 RootEncoder 的 GL 管线里，输出纹理同时交给预览 Surface 和
 * MediaCodec 编码器；因此不是只修改主播本地画面的 Flutter 遮罩，观众收到的 RTMP
 * 视频也会是同一份美颜后的画面。
 */
internal class LiveBeautyFilterRender : BaseFilterRender() {
    @Volatile
    private var smoothing = 0.38f

    @Volatile
    private var whitening = 0.10f

    @Volatile
    private var rosiness = 0.08f

    @Volatile
    private var faceSlimming = 0.25f

    @Volatile
    private var filterStrength = 0.72f

    @Volatile
    private var faceCenterX = 0.5f

    @Volatile
    private var faceCenterY = 0.5f

    @Volatile
    private var faceRadiusX = 0f

    @Volatile
    private var faceRadiusY = 0f

    private var program = -1
    private var aPositionHandle = -1
    private var aTextureHandle = -1
    private var uMvpMatrixHandle = -1
    private var uStMatrixHandle = -1
    private var uSamplerHandle = -1
    private var uTexelStepHandle = -1
    private var uSmoothingHandle = -1
    private var uWhiteningHandle = -1
    private var uRosinessHandle = -1
    private var uFaceSlimmingHandle = -1
    private var uFaceCenterHandle = -1
    private var uFaceRadiusHandle = -1
    private var uFilterStrengthHandle = -1

    init {
        squareVertex = ByteBuffer
            .allocateDirect(SQUARE_VERTEX_DATA.size * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply {
                put(SQUARE_VERTEX_DATA)
                position(0)
            }
        Matrix.setIdentityM(MVPMatrix, 0)
        Matrix.setIdentityM(STMatrix, 0)
    }

    fun update(
        smoothing: Float,
        whitening: Float,
        rosiness: Float,
        faceSlimming: Float,
        filterStrength: Float,
    ) {
        // Pigeon 入参已在 Flutter 侧规整；原生层再收敛一次，避免任何调用方把
        // NaN、负数或过高参数写入 fragment shader。
        this.smoothing = smoothing.safeUnitInterval()
        this.whitening = whitening.safeUnitInterval()
        this.rosiness = rosiness.safeUnitInterval()
        this.faceSlimming = faceSlimming.safeUnitInterval()
        this.filterStrength = filterStrength.safeUnitInterval()
    }

    fun updateFaceRegion(centerX: Float, centerY: Float, radiusX: Float, radiusY: Float) {
        faceCenterX = centerX.safeUnitInterval()
        faceCenterY = centerY.safeUnitInterval()
        faceRadiusX = radiusX.coerceIn(0.08f, 0.46f)
        faceRadiusY = radiusY.coerceIn(0.08f, 0.46f)
    }

    fun clearFaceRegion() {
        faceRadiusX = 0f
        faceRadiusY = 0f
    }

    override fun initGlFilter(context: Context) {
        program = GlUtil.createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        aPositionHandle = GLES20.glGetAttribLocation(program, "aPosition")
        aTextureHandle = GLES20.glGetAttribLocation(program, "aTextureCoord")
        uMvpMatrixHandle = GLES20.glGetUniformLocation(program, "uMVPMatrix")
        uStMatrixHandle = GLES20.glGetUniformLocation(program, "uSTMatrix")
        uSamplerHandle = GLES20.glGetUniformLocation(program, "uSampler")
        uTexelStepHandle = GLES20.glGetUniformLocation(program, "uTexelStep")
        uSmoothingHandle = GLES20.glGetUniformLocation(program, "uSmoothing")
        uWhiteningHandle = GLES20.glGetUniformLocation(program, "uWhitening")
        uRosinessHandle = GLES20.glGetUniformLocation(program, "uRosiness")
        uFaceSlimmingHandle = GLES20.glGetUniformLocation(program, "uFaceSlimming")
        uFaceCenterHandle = GLES20.glGetUniformLocation(program, "uFaceCenter")
        uFaceRadiusHandle = GLES20.glGetUniformLocation(program, "uFaceRadius")
        uFilterStrengthHandle = GLES20.glGetUniformLocation(program, "uFilterStrength")
    }

    override fun drawFilter() {
        GLES20.glUseProgram(program)
        squareVertex.position(0)
        GLES20.glVertexAttribPointer(
            aPositionHandle,
            3,
            GLES20.GL_FLOAT,
            false,
            SQUARE_VERTEX_DATA_STRIDE_BYTES,
            squareVertex,
        )
        GLES20.glEnableVertexAttribArray(aPositionHandle)

        squareVertex.position(3)
        GLES20.glVertexAttribPointer(
            aTextureHandle,
            2,
            GLES20.GL_FLOAT,
            false,
            SQUARE_VERTEX_DATA_STRIDE_BYTES,
            squareVertex,
        )
        GLES20.glEnableVertexAttribArray(aTextureHandle)

        GLES20.glUniformMatrix4fv(uMvpMatrixHandle, 1, false, MVPMatrix, 0)
        GLES20.glUniformMatrix4fv(uStMatrixHandle, 1, false, STMatrix, 0)
        GLES20.glUniform2f(
            uTexelStepHandle,
            1f / getWidth().coerceAtLeast(1),
            1f / getHeight().coerceAtLeast(1),
        )
        GLES20.glUniform1f(uSmoothingHandle, smoothing)
        GLES20.glUniform1f(uWhiteningHandle, whitening)
        GLES20.glUniform1f(uRosinessHandle, rosiness)
        GLES20.glUniform1f(uFaceSlimmingHandle, faceSlimming)
        GLES20.glUniform2f(uFaceCenterHandle, faceCenterX, faceCenterY)
        GLES20.glUniform2f(uFaceRadiusHandle, faceRadiusX, faceRadiusY)
        GLES20.glUniform1f(uFilterStrengthHandle, filterStrength)
        GLES20.glUniform1i(uSamplerHandle, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, previousTexId)
    }

    override fun disableResources() {
        GlUtil.disableResources(*intArrayOf(aTextureHandle, aPositionHandle))
    }

    override fun release() {
        if (program != -1) GLES20.glDeleteProgram(program)
        program = -1
    }

    private fun Float.safeUnitInterval(): Float =
        if (!isFinite()) 0f else coerceIn(0f, 1f)

    private companion object {
        val SQUARE_VERTEX_DATA = floatArrayOf(
            -1f, -1f, 0f, 0f, 0f,
            1f, -1f, 0f, 1f, 0f,
            -1f, 1f, 0f, 0f, 1f,
            1f, 1f, 0f, 1f, 1f,
        )

        const val VERTEX_SHADER = """
            attribute vec4 aPosition;
            attribute vec4 aTextureCoord;
            uniform mat4 uMVPMatrix;
            uniform mat4 uSTMatrix;
            varying vec2 vTextureCoord;
            void main() {
              gl_Position = uMVPMatrix * aPosition;
              vTextureCoord = (uSTMatrix * aTextureCoord).xy;
            }
        """

        // 轻量双边平滑：通过颜色差保留边缘，再叠加美白和暖红色调。使用 GLES2
        // 兼容语法，RootEncoder 的预览和编码 Surface 都可在 API 24+ 工作。
        const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform sampler2D uSampler;
            uniform vec2 uTexelStep;
            uniform float uSmoothing;
            uniform float uWhitening;
            uniform float uRosiness;
            uniform float uFaceSlimming;
            uniform vec2 uFaceCenter;
            uniform vec2 uFaceRadius;
            uniform float uFilterStrength;
            varying vec2 vTextureCoord;

            vec3 sampleAt(vec2 coordinate, vec2 offset) {
              return texture2D(uSampler, coordinate + offset * uTexelStep).rgb;
            }

            void main() {
              vec2 sampleCoordinate = vTextureCoord;
              float faceMask = 0.0;
              // 人脸检测为空时 radius 是 0，不进入形变分支，绝不把背景拉扯成
              // “假瘦脸”。检测到脸后仅在椭圆区域内向中心反向采样，压缩两颊。
              if (uFaceRadius.x > 0.001 && uFaceRadius.y > 0.001) {
                vec2 local = (vTextureCoord - uFaceCenter) / uFaceRadius;
                float distance = length(local);
                if (distance < 1.0) {
                  // 蒙版在脸部中心饱和、边缘渐隐。美白、红润和磨皮都只作用于
                  // 此区域，背景与发丝始终保持原始清晰度。
                  faceMask = 1.0 - smoothstep(0.62, 1.0, distance);
                  float influence = (1.0 - smoothstep(0.15, 1.0, distance));
                  if (uFaceSlimming > 0.001) {
                    sampleCoordinate = uFaceCenter + (vTextureCoord - uFaceCenter)
                      * (1.0 + uFaceSlimming * 0.23 * influence);
                  }
                }
              }
              vec4 source = texture2D(uSampler, sampleCoordinate);
              vec3 center = source.rgb;
              vec3 blur = center * 0.28;
              blur += sampleAt(sampleCoordinate, vec2(-2.0, 0.0)) * 0.10;
              blur += sampleAt(sampleCoordinate, vec2(2.0, 0.0)) * 0.10;
              blur += sampleAt(sampleCoordinate, vec2(0.0, -2.0)) * 0.10;
              blur += sampleAt(sampleCoordinate, vec2(0.0, 2.0)) * 0.10;
              blur += sampleAt(sampleCoordinate, vec2(-1.4, -1.4)) * 0.08;
              blur += sampleAt(sampleCoordinate, vec2(1.4, -1.4)) * 0.08;
              blur += sampleAt(sampleCoordinate, vec2(-1.4, 1.4)) * 0.08;
              blur += sampleAt(sampleCoordinate, vec2(1.4, 1.4)) * 0.08;

              // 边缘与纹理差异越大，平滑权重越小，避免五官轮廓被直接糊掉。
              float edge = length(center - blur);
              float preserveDetail = smoothstep(0.035, 0.19, edge);
              float softAmount = uSmoothing * (1.0 - preserveDetail);
              vec3 softened = mix(center, blur, softAmount);

              vec3 whitened = softened + (vec3(1.0) - softened) * (0.18 * uWhitening);
              vec3 rosy = whitened + vec3(0.085, 0.0, 0.035) * uRosiness;
              vec3 beautified = clamp(rosy, 0.0, 1.0);

              gl_FragColor = vec4(
                mix(center, beautified, uFilterStrength * faceMask),
                source.a
              );
            }
        """
    }
}
