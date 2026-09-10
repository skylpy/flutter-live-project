import AVFoundation
import CoreImage
import Foundation
import HaishinKit
import MetalKit
import Vision

/// 接收编码前处理结果的预览出口。
///
/// HaishinKit 默认的 MTHKView 接到的是原始 `CMSampleBuffer`；这里把同一个
/// [VideoEffect] 返回给编码器的 `CIImage` 交给自定义预览，保证主播与观众一致。
protocol LiveBeautyPreviewSink: AnyObject {
  func enqueueProcessedImage(_ image: CIImage)
}

/// iOS 采集 → Core Image GPU 处理 → HaishinKit 编码器的实时美颜效果。
///
/// `execute` 的返回值由 HaishinKit 渲染到待编码 PixelBuffer。预览也直接消费该
/// 返回值，而不是消费 AVCapture 的原图，因此美颜参数对主播预览和观众 RTMP 流
/// 同步生效。
final class LiveBeautyVideoEffect: VideoEffect {
  private let settingsLock = NSLock()
  private var settings = Settings.natural

  // 不把 Vision 放到采集/编码队列执行：人脸检测只需每秒约 3 次即可跟随正常
  // 的直播镜头移动，真正的美颜和形变仍在每一帧的 Core Image GPU 管线内完成。
  private let faceLock = NSLock()
  private let faceDetectionQueue = DispatchQueue(
    label: "com.skylpy.flutterLive.faceDetection",
    qos: .userInitiated
  )
  private var frameIndex = 0
  private var faceDetectionInFlight = false
  private var detectedFace: FaceRegion?

  private let noiseReduction = CIFilter(name: "CINoiseReduction")
  private let colorControls = CIFilter(name: "CIColorControls")
  private let colorMatrix = CIFilter(name: "CIColorMatrix")
  private let faceBlendWithMask = CIFilter(name: "CIBlendWithMask")
  private let strengthBlendWithMask = CIFilter(name: "CIBlendWithMask")
  private let faceMaskGradient = CIFilter(name: "CIRadialGradient")
  private let faceSlimmingFilter = CIFilter(name: "CIBumpDistortion")

  weak var previewSink: LiveBeautyPreviewSink?

  func update(with configuration: LiveBeautyConfiguration) {
    settingsLock.lock()
    settings = Settings(configuration: configuration)
    settingsLock.unlock()
  }

  override func execute(_ image: CIImage, info: CMSampleBuffer?) -> CIImage {
    let settings = currentSettings
    scheduleFaceDetection(for: image)

    // 只有真正检测到人脸时才处理。旧实现把降噪套在整幅画面上，既会把背景和
    // 五官一起糊掉，又根本无法进行局部瘦脸；这里宁可在人脸离开镜头时显示原图。
    guard let face = currentFace else {
      previewSink?.enqueueProcessedImage(image)
      return image
    }

    var result = image

    // 采用偏保守的降噪参数，肤色会柔和但眼睛、头发和背景不会有明显涂抹感。
    // 处理结果随后只通过人脸蒙版混回原图，五官边缘仍由原图主导。
    if settings.smoothing > 0.001, let noiseReduction {
      noiseReduction.setValue(result, forKey: kCIInputImageKey)
      noiseReduction.setValue(0.003 + settings.smoothing * 0.022, forKey: "inputNoiseLevel")
      noiseReduction.setValue(0.68 - settings.smoothing * 0.18, forKey: "inputSharpness")
      result = noiseReduction.outputImage ?? result
    }

    if settings.whitening > 0.001, let colorControls {
      colorControls.setValue(result, forKey: kCIInputImageKey)
      colorControls.setValue(settings.whitening * 0.13, forKey: kCIInputBrightnessKey)
      colorControls.setValue(1.0 + settings.whitening * 0.045, forKey: kCIInputSaturationKey)
      colorControls.setValue(1.0, forKey: kCIInputContrastKey)
      result = colorControls.outputImage ?? result
    }

    if settings.rosiness > 0.001, let colorMatrix {
      colorMatrix.setValue(result, forKey: kCIInputImageKey)
      colorMatrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
      colorMatrix.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
      colorMatrix.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
      colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
      colorMatrix.setValue(
        CIVector(
          x: settings.rosiness * 0.075,
          y: 0,
          z: settings.rosiness * 0.028,
          w: 0
        ),
        forKey: "inputBiasVector"
      )
      result = colorMatrix.outputImage ?? result
    }

    // CIBumpDistortion 的负值是向中心的轻微收缩。仅取人脸中心附近的椭圆区域，
    // 强度被限制在自然范围，避免把额头、下巴或背景边缘扭曲成“哈哈镜”。
    if settings.faceSlimming > 0.001, let faceSlimmingFilter {
      let radius = min(face.bounds.width, face.bounds.height) * 0.58
      faceSlimmingFilter.setValue(result, forKey: kCIInputImageKey)
      faceSlimmingFilter.setValue(CIVector(cgPoint: face.center), forKey: kCIInputCenterKey)
      faceSlimmingFilter.setValue(radius, forKey: kCIInputRadiusKey)
      faceSlimmingFilter.setValue(-settings.faceSlimming * 0.24, forKey: kCIInputScaleKey)
      result = (faceSlimmingFilter.outputImage ?? result).cropped(to: image.extent)
    }

    // 用羽化人脸蒙版把“已美颜”画面混回原始帧，背景、头发边缘和衣物维持清晰。
    if let mask = faceMask(for: face, in: image.extent), let faceBlendWithMask {
      faceBlendWithMask.setValue(result, forKey: kCIInputImageKey)
      faceBlendWithMask.setValue(image, forKey: kCIInputBackgroundImageKey)
      faceBlendWithMask.setValue(mask, forKey: kCIInputMaskImageKey)
      result = faceBlendWithMask.outputImage ?? image
    } else {
      result = image
    }

    // 滤镜强度仍是最终处理画面与原图的 GPU 混合，便于用户一键降低所有效果。
    if settings.filterStrength < 0.999, let strengthBlendWithMask {
      let mask = CIImage(
        color: CIColor(
          red: settings.filterStrength,
          green: settings.filterStrength,
          blue: settings.filterStrength,
          alpha: 1
        )
      ).cropped(to: image.extent)
      strengthBlendWithMask.setValue(result, forKey: kCIInputImageKey)
      strengthBlendWithMask.setValue(image, forKey: kCIInputBackgroundImageKey)
      strengthBlendWithMask.setValue(mask, forKey: kCIInputMaskImageKey)
      result = strengthBlendWithMask.outputImage ?? result
    }

    previewSink?.enqueueProcessedImage(result)
    return result
  }

  private var currentSettings: Settings {
    settingsLock.lock()
    defer { settingsLock.unlock() }
    return settings
  }

  private var currentFace: FaceRegion? {
    faceLock.lock()
    defer { faceLock.unlock() }
    // 检测线程可能因系统调度短暂停顿；过期结果不能继续套用到新一帧上。
    guard let detectedFace, Date().timeIntervalSince(detectedFace.updatedAt) < 0.9 else {
      return nil
    }
    return detectedFace
  }

  private func scheduleFaceDetection(for image: CIImage) {
    faceLock.lock()
    frameIndex += 1
    let shouldDetect = frameIndex == 1 || frameIndex.isMultiple(of: 10)
    guard shouldDetect, !faceDetectionInFlight else {
      faceLock.unlock()
      return
    }
    faceDetectionInFlight = true
    faceLock.unlock()

    let extent = image.extent
    faceDetectionQueue.async { [weak self] in
      let request = VNDetectFaceRectanglesRequest()
      let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
      let observations: [VNFaceObservation]
      do {
        try handler.perform([request])
        observations = request.results ?? []
      } catch {
        observations = []
      }

      let primaryFace = observations.max { lhs, rhs in
        lhs.boundingBox.width * lhs.boundingBox.height < rhs.boundingBox.width * rhs.boundingBox.height
      }

      self?.faceLock.lock()
      defer { self?.faceLock.unlock() }
      guard let self else { return }
      self.faceDetectionInFlight = false
      guard let primaryFace, extent.width > 0, extent.height > 0 else {
        self.detectedFace = nil
        return
      }

      let normalized = primaryFace.boundingBox
      let bounds = CGRect(
        x: extent.minX + normalized.minX * extent.width,
        y: extent.minY + normalized.minY * extent.height,
        width: normalized.width * extent.width,
        height: normalized.height * extent.height
      ).insetBy(dx: -normalized.width * extent.width * 0.10, dy: -normalized.height * extent.height * 0.08)
      self.detectedFace = FaceRegion(bounds: bounds, updatedAt: Date())
    }
  }

  private func faceMask(for face: FaceRegion, in extent: CGRect) -> CIImage? {
    guard let faceMaskGradient else { return nil }
    let radius = min(face.bounds.width, face.bounds.height) * 0.70
    guard radius > 0 else { return nil }
    faceMaskGradient.setValue(CIVector(cgPoint: face.center), forKey: "inputCenter")
    faceMaskGradient.setValue(radius * 0.55, forKey: "inputRadius0")
    faceMaskGradient.setValue(radius, forKey: "inputRadius1")
    faceMaskGradient.setValue(CIColor.white, forKey: "inputColor0")
    faceMaskGradient.setValue(CIColor.clear, forKey: "inputColor1")
    return faceMaskGradient.outputImage?.cropped(to: extent)
  }

  private struct FaceRegion {
    let bounds: CGRect
    let updatedAt: Date

    var center: CGPoint {
      CGPoint(x: bounds.midX, y: bounds.midY)
    }
  }

  private struct Settings {
    let smoothing: CGFloat
    let whitening: CGFloat
    let rosiness: CGFloat
    let faceSlimming: CGFloat
    let filterStrength: CGFloat

    init(
      smoothing: CGFloat,
      whitening: CGFloat,
      rosiness: CGFloat,
      faceSlimming: CGFloat,
      filterStrength: CGFloat
    ) {
      self.smoothing = smoothing
      self.whitening = whitening
      self.rosiness = rosiness
      self.faceSlimming = faceSlimming
      self.filterStrength = filterStrength
    }

    static let natural = Settings(
      smoothing: 0.38,
      whitening: 0.10,
      rosiness: 0.08,
      faceSlimming: 0.25,
      filterStrength: 0.72
    )

    init(configuration: LiveBeautyConfiguration) {
      smoothing = Self.unit(configuration.smoothing)
      whitening = Self.unit(configuration.whitening)
      rosiness = Self.unit(configuration.rosiness)
      faceSlimming = Self.unit(configuration.faceSlimming)
      filterStrength = Self.unit(configuration.filterStrength)
    }

    private static func unit(_ value: Double) -> CGFloat {
      guard value.isFinite else { return 0 }
      return CGFloat(min(max(value, 0), 1))
    }
  }
}

/// 使用 Metal 渲染已美颜 `CIImage` 的主播预览视图。
///
/// 与 HaishinKit 的隐形 MTHKView 共用 Metal 上下文，后者负责让视频 I/O 走 GPU，
/// 本视图只显示 [LiveBeautyVideoEffect] 的最终输出，避免原图覆盖美颜后的画面。
final class LiveBeautyPreviewMetalView: MTKView, LiveBeautyPreviewSink, MTKViewDelegate {
  private let ciContext: CIContext
  private let colorSpace = CGColorSpaceCreateDeviceRGB()
  private var currentImage: CIImage?
  private lazy var commandQueue: MTLCommandQueue? = device?.makeCommandQueue()

  init(frame: CGRect) {
    guard let device = MTLCreateSystemDefaultDevice() else {
      fatalError("当前设备不支持 Metal 摄像头预览")
    }
    ciContext = CIContext(mtlDevice: device)
    super.init(frame: frame, device: device)
    framebufferOnly = false
    enableSetNeedsDisplay = true
    isPaused = true
    delegate = self
    backgroundColor = .black
    contentMode = .scaleAspectFill
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func enqueueProcessedImage(_ image: CIImage) {
    // AVFoundation 在采集队列调用 effect；MTKView 的状态和重绘必须留在主线程。
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.currentImage = image
      self.setNeedsDisplay()
    }
  }

  func clear() {
    currentImage = nil
    setNeedsDisplay()
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    guard
      let drawable = currentDrawable,
      let commandBuffer = commandQueue?.makeCommandBuffer(),
      let image = currentImage
    else { return }

    let imageExtent = image.extent
    guard imageExtent.width > 0, imageExtent.height > 0 else {
      commandBuffer.present(drawable)
      commandBuffer.commit()
      return
    }

    let scale = max(drawableSize.width / imageExtent.width, drawableSize.height / imageExtent.height)
    let translatedX = (drawableSize.width / scale - imageExtent.width) / 2
    let translatedY = (drawableSize.height / scale - imageExtent.height) / 2
    let displayImage = image
      .transformed(by: CGAffineTransform(translationX: translatedX, y: translatedY))
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let bounds = CGRect(origin: .zero, size: drawableSize)
    ciContext.render(
      displayImage,
      to: drawable.texture,
      commandBuffer: commandBuffer,
      bounds: bounds,
      colorSpace: colorSpace
    )
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }
}
