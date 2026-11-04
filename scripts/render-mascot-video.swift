import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

private let frameRate: Int32 = 30
private let duration = 7.0
private let videoWidth = 720
private let videoHeight = 240

private struct Keyframe {
    let time: Double
    let imageIndex: Int
}

private let keyframes = [
    Keyframe(time: 0.00, imageIndex: 0),
    Keyframe(time: 0.62, imageIndex: 0),
    Keyframe(time: 0.80, imageIndex: 1),
    Keyframe(time: 1.00, imageIndex: 1),
    Keyframe(time: 1.18, imageIndex: 2),
    Keyframe(time: 1.48, imageIndex: 2),
    Keyframe(time: 1.66, imageIndex: 3),
    Keyframe(time: 1.92, imageIndex: 3),
    Keyframe(time: 2.10, imageIndex: 4),
    Keyframe(time: 2.40, imageIndex: 4),
    Keyframe(time: 2.58, imageIndex: 5),
    Keyframe(time: 6.78, imageIndex: 5),
    Keyframe(time: 7.00, imageIndex: 0),
]

private func smoothstep(_ value: Double) -> CGFloat {
    let clamped = max(0, min(1, value))
    return CGFloat(clamped * clamped * (3 - 2 * clamped))
}

private func pose(at time: Double) -> (from: Int, to: Int, progress: CGFloat) {
    for index in 0..<(keyframes.count - 1) {
        let start = keyframes[index]
        let end = keyframes[index + 1]
        guard time >= start.time, time < end.time else { continue }
        if start.imageIndex == end.imageIndex {
            return (start.imageIndex, end.imageIndex, 0)
        }
        return (
            start.imageIndex,
            end.imageIndex,
            smoothstep((time - start.time) / (end.time - start.time))
        )
    }
    return (0, 0, 0)
}

private func loadFrames(from url: URL) throws -> [CGImage] {
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw NSError(domain: "MascotVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to load storyboard"])
    }

    let cellWidth = sheet.width / 3
    let cellHeight = sheet.height / 2
    return try (0..<6).map { index in
        let column = index % 3
        let row = index / 3
        let crop = CGRect(
            x: column * cellWidth,
            y: row * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
        guard let image = sheet.cropping(to: crop) else {
            throw NSError(domain: "MascotVideo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to crop storyboard frame \(index)"])
        }
        return try removeFaintBackdrop(from: image)
    }
}

private func removeFaintBackdrop(from image: CGImage) throws -> CGImage {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "MascotVideo", code: 10, userInfo: [NSLocalizedDescriptionKey: "Unable to clean storyboard background"])
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    for offset in stride(from: 0, to: pixels.count, by: 4) {
        let oldAlpha = Int(pixels[offset + 3])
        let newAlpha: Int
        if oldAlpha <= 96 {
            newAlpha = 0
        } else if oldAlpha < 224 {
            newAlpha = (oldAlpha - 96) * 255 / 128
        } else {
            newAlpha = 255
        }

        if newAlpha == 0 {
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
        } else {
            let scale = CGFloat(newAlpha) / CGFloat(max(oldAlpha, 1))
            pixels[offset] = UInt8(min(255, CGFloat(pixels[offset]) * scale))
            pixels[offset + 1] = UInt8(min(255, CGFloat(pixels[offset + 1]) * scale))
            pixels[offset + 2] = UInt8(min(255, CGFloat(pixels[offset + 2]) * scale))
            pixels[offset + 3] = UInt8(newAlpha)
        }
    }

    guard let cleaned = context.makeImage() else {
        throw NSError(domain: "MascotVideo", code: 11, userInfo: [NSLocalizedDescriptionKey: "Unable to create cleaned storyboard frame"])
    }
    return cleaned
}

private func render(
    images: [CGImage],
    at time: Double,
    into pixelBuffer: CVPixelBuffer
) throws {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
        let context = CGContext(
            data: baseAddress,
            width: videoWidth,
            height: videoHeight,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    else {
        throw NSError(domain: "MascotVideo", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to create frame context"])
    }

    context.setFillColor(CGColor(red: 0.035, green: 0.043, blue: 0.055, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: videoWidth, height: videoHeight))

    let current = pose(at: time)
    let breath = CGFloat(sin(time * .pi * 2 / 1.9))
    let scale = 1 + breath * 0.008
    let baseRect = CGRect(x: 180, y: 0, width: 360, height: 240)
    let drawRect = baseRect.insetBy(dx: -baseRect.width * (scale - 1) / 2, dy: -baseRect.height * (scale - 1) / 2)
        .offsetBy(dx: 0, dy: -breath * 1.2)

    context.setAlpha(1)
    context.draw(images[current.from], in: drawRect)
    if current.progress > 0 {
        context.setAlpha(current.progress)
        context.draw(images[current.to], in: drawRect)
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let storyboardURL = root.appendingPathComponent("docs/branding/KomeCineMascotVideoStoryboard.png")
let outputURL = root.appendingPathComponent("ios/KomeCine/KomeCine/KomeCineMascot.mp4")
let frames = try loadFrames(from: storyboardURL)

try? FileManager.default.removeItem(at: outputURL)
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let input = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: videoWidth,
        AVVideoHeightKey: videoHeight,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 900_000,
            AVVideoExpectedSourceFrameRateKey: frameRate,
            AVVideoMaxKeyFrameIntervalKey: frameRate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
    ]
)
input.expectsMediaDataInRealTime = false

let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: videoWidth,
        kCVPixelBufferHeightKey as String: videoHeight,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
)

guard writer.canAdd(input) else {
    throw NSError(domain: "MascotVideo", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unable to add video input"])
}
writer.add(input)
guard writer.startWriting() else {
    throw writer.error ?? NSError(domain: "MascotVideo", code: 5)
}
writer.startSession(atSourceTime: .zero)

let frameCount = Int(duration * Double(frameRate))
for frameNumber in 0..<frameCount {
    while !input.isReadyForMoreMediaData {
        Thread.sleep(forTimeInterval: 0.001)
    }
    guard let pool = adaptor.pixelBufferPool else {
        throw NSError(domain: "MascotVideo", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing pixel buffer pool"])
    }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
        throw NSError(domain: "MascotVideo", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate frame"])
    }

    let time = Double(frameNumber) / Double(frameRate)
    try render(images: frames, at: time, into: buffer)
    let presentationTime = CMTime(value: Int64(frameNumber), timescale: frameRate)
    guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
        throw writer.error ?? NSError(domain: "MascotVideo", code: 8)
    }
}

input.markAsFinished()
await writer.finishWriting()
guard writer.status == .completed else {
    throw writer.error ?? NSError(domain: "MascotVideo", code: 9)
}

print(outputURL.path)
