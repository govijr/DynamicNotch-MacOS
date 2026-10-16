import AVFoundation
import Foundation

/// A tiny synthetic clip makes frame capture testable without downloads,
/// third-party accounts, FFmpeg, or a committed binary media file.
@MainActor
func writeMediaFixture(to url: URL) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: 64, AVVideoHeightKey: 64
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
        sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                      kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)
    var buffer: CVPixelBuffer?
    guard CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess,
          let buffer else { throw CocoaError(.fileWriteUnknown) }
    CVPixelBufferLockBaseAddress(buffer, [])
    if let pixels = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
        for row in 0..<64 {
            for column in 0..<64 {
                let offset = row * CVPixelBufferGetBytesPerRow(buffer) + column * 4
                pixels[offset] = 255; pixels[offset + 1] = 40
                pixels[offset + 2] = 100; pixels[offset + 3] = 220
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    for index in 0..<4 {
        let deadline = Date().addingTimeInterval(5)
        while !input.isReadyForMoreMediaData {
            guard Date() < deadline, writer.status == .writing else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 2)) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
    }
    input.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
}
