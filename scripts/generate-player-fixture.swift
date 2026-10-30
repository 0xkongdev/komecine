import AVFoundation
import AppKit

let destination = URL(fileURLWithPath:CommandLine.arguments[1])
try? FileManager.default.removeItem(at:destination)
let writer = try AVAssetWriter(outputURL:destination, fileType:.mp4)
let settings: [String:Any] = [AVVideoCodecKey:AVVideoCodecType.h264, AVVideoWidthKey:640, AVVideoHeightKey:360]
let input = AVAssetWriterInput(mediaType:.video, outputSettings:settings)
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input, sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String:640, kCVPixelBufferHeightKey as String:360])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime:.zero)
for frame in 0..<60 {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval:0.005) }
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault,640,360,kCVPixelFormatType_32ARGB,nil,&buffer)
    let pixel = buffer!
    CVPixelBufferLockBaseAddress(pixel,[])
    let context = CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:640,height:360,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
    context.setFillColor(CGColor(red:0.04,green:0.07,blue:0.12,alpha:1)); context.fill(CGRect(x:0,y:0,width:640,height:360))
    context.setFillColor(CGColor(red:0.1,green:0.5,blue:0.65,alpha:1)); context.fillEllipse(in:CGRect(x:180+frame,y:80,width:200,height:200))
    CVPixelBufferUnlockBaseAddress(pixel,[])
    adaptor.append(pixel,withPresentationTime:CMTime(seconds:Double(frame),preferredTimescale:600))
}
input.markAsFinished()
let finished = DispatchSemaphore(value:0)
writer.finishWriting { finished.signal() }; finished.wait()
guard writer.status == .completed else { fatalError("\(String(describing:writer.error))") }
