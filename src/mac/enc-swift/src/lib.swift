import AVFoundation
import Foundation
import ScreenCaptureKit
import SwiftRs
import VideoToolbox

// TODO: handle errors better
class Encoder: NSObject {
    var width: Int
    var height: Int
    var assetWriter: AVAssetWriter
    var assetWriterInput: AVAssetWriterInput
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

    init(_ width: Int, _ height: Int, _ outFile: URL) {
        self.width = width
        self.height = height

        // Setup AVAssetWriter
        // Create AVAssetWriter for a mp4 file
        self.assetWriter = try! AVAssetWriter(url: outFile, fileType: .mp4)

        // Prepare the AVAssetWriterInputPixelBufferAdaptor
        let outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]

        self.assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        self.assetWriterInput.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: self.assetWriterInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if self.assetWriter.canAdd(self.assetWriterInput) {
            self.assetWriter.add(self.assetWriterInput)
        }

        self.assetWriter.startWriting()
        self.assetWriter.startSession(atSourceTime: CMTime.zero)
    }
}

@_cdecl("encoder_init")
func encoderInit(_ width: Int, _ height: Int, _ outFile: SRString) -> Encoder {
    return Encoder(
        width,
        height,
        URL(fileURLWithPath: outFile.toString())
    )
}

// NOTE: make any timestamp adjustments in Rust before passing here

@_cdecl("encoder_ingest_yuv_frame")
func encoderIngestYuvFrame(
    _ enc: Encoder,
    _ width: Int,
    _ height: Int,
    _ displayTime: Int,
    _ luminanceStride: Int,
    _ luminanceBytesRaw: SRData,
    _ chrominanceStride: Int,
    _ chrominanceBytesRaw: SRData
) {
    let luminanceBytes = luminanceBytesRaw.toArray()
    let chrominanceBytes = chrominanceBytesRaw.toArray()

    // Create a CVPixelBuffer from YUV data
    var pixelBuffer = createCvPixelBufferFromYuvFrameData(
        width,
        height,
        displayTime,
        luminanceStride,
        luminanceBytes,
        chrominanceStride,
        chrominanceBytes
    )

    // Append the CVPixelBuffer to the AVAssetWriter
    if enc.assetWriterInput.isReadyForMoreMediaData {
        let frameTime = CMTimeMake(value: Int64(displayTime), timescale: 1_000_000_000)
        let success = enc.pixelBufferAdaptor.append(pixelBuffer!, withPresentationTime: frameTime)
        if !success {
            print("AVAssetWriter: \(enc.assetWriter.error?.localizedDescription ?? "Unknown error")")
        }
    } else {
        print("AVAssetWriter: not ready for more data")
    }
}

@_cdecl("encoder_ingest_bgra_frame")
func encoderIngestBgraFrame(
    _ enc: Encoder,
    _ width: Int,
    _ height: Int,
    _ displayTime: Int,
    _ bytesPerRow: Int,
    _ bgraBytesRaw: SRData
) {
    let bgraBytes = bgraBytesRaw.toArray()

    // Create a CVPixelBuffer from BGRA data
    var pixelBuffer = createCvPixelBufferFromBgraFrameData(
        width,
        height,
        displayTime,
        bytesPerRow,
        bgraBytes
    )

    // Append the CVPixelBuffer to the AVAssetWriter
    if enc.assetWriterInput.isReadyForMoreMediaData {
        let frameTime = CMTimeMake(value: Int64(displayTime), timescale: 1_000_000_000)
        let success = enc.pixelBufferAdaptor.append(pixelBuffer!, withPresentationTime: frameTime)
        if !success {
            print("AVAssetWriter: \(enc.assetWriter.error?.localizedDescription ?? "Unknown error")")
        }
    } else {
        print("AVAssetWriter: not ready for more data")
    }
}

@_cdecl("encoder_finish")
func encoderFinish(_ enc: Encoder) {

    // TODO: figure out how to gracefully end session
    // enc.assetWriter.endSession(atSourceTime: CMTime)

    enc.assetWriterInput.markAsFinished()
    enc.assetWriter.finishWriting {}

    while enc.assetWriter.status == .writing {
        print("AVAssetWriter: still writing...")
        usleep(500000)
    }

    print("AVAssetWriter: finished writing!")
}

class WindowManager: NSObject, SCStreamDelegate, SCStreamOutput {
    static let shared = WindowManager()

    private override init() {
        super.init()
    }

    var windowThumbnails = [SCDisplay:[WindowThumbnail]]()
    var allWindows = [SCWindow]()
    private var streams = [SCStream]()

    func getWindows(filter: Bool = true, capture: Bool = true, completion: @escaping () -> Void) {
        SCContext.updateAvailableContent {
            Task {
                do {
                    self.streams.removeAll()
                    self.windowThumbnails.removeAll()
                    self.allWindows = SCContext.getWindows().filter({
                        !($0.title == "" && $0.owningApplication?.bundleIdentifier == "com.apple.finder")
                        && $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
                        && $0.owningApplication?.applicationName != ""
                    })
                    if filter { self.allWindows = self.allWindows.filter({ $0.title != "" }) }
                    if capture {
                        try await self.captureWindowThumbnails()
                    } else {
                        self.createDummyThumbnails()
                    }
                    completion()
                } catch {
                    print("Get windowshot error：\(error)")
                    completion()
                }
            }
        }
    }

    private func captureWindowThumbnails() async throws {
        let contentFilters = self.allWindows.map { SCContentFilter(desktopIndependentWindow: $0) }
        for (index, contentFilter) in contentFilters.enumerated() {
            let streamConfiguration = SCStreamConfiguration()
            let width = self.allWindows[index].frame.width
            let height = self.allWindows[index].frame.height
            var factor = 0.5
            if width < 200 && height < 200 { factor = 1.0 }
            streamConfiguration.width = Int(width * factor)
            streamConfiguration.height = Int(height * factor)
            streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(1))
            streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
            if #available(macOS 13, *) { streamConfiguration.capturesAudio = false }
            streamConfiguration.showsCursor = false
            streamConfiguration.scalesToFit = true
            streamConfiguration.queueDepth = 3
            let stream = SCStream(filter: contentFilter, configuration: streamConfiguration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            try await stream.startCapture()
            self.streams.append(stream)
        }
    }

    private func createDummyThumbnails() {
        for w in self.allWindows {
            let thumbnail = WindowThumbnail(image: NSImage(), window: w)
            guard let displays = SCContext.availableContent?.displays.filter({ NSIntersectsRect(w.frame, $0.frame) }) else { break }
            for d in displays {
                if self.windowThumbnails[d] != nil {
                    if !self.windowThumbnails[d]!.contains(where: { $0.window == w }) {
                        self.windowThumbnails[d]!.append(thumbnail)
                    }
                } else {
                    self.windowThumbnails[d] = [thumbnail]
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ciContext = CIContext()
        let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        let nsImage = cgImage.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) } ?? NSImage()

        if let index = self.streams.firstIndex(of: stream), index < self.allWindows.count {
            let currentWindow = self.allWindows[index]
            let thumbnail = WindowThumbnail(image: nsImage, window: currentWindow)
            guard let displays = SCContext.availableContent?.displays.filter({ NSIntersectsRect(currentWindow.frame, $0.frame) }) else {
                self.streams[index].stopCapture()
                return
            }
            for d in displays {
                if self.windowThumbnails[d] != nil {
                    if !self.windowThumbnails[d]!.contains(where: { $0.window == currentWindow }) {
                        self.windowThumbnails[d]!.append(thumbnail)
                    }
                } else {
                    self.windowThumbnails[d] = [thumbnail]
                }
            }
            self.streams[index].stopCapture()
        }
    }

    func captureWindowScreen(windowID: CGWindowID) async throws -> Data {
        guard let window = allWindows.first(where: { $0.windowID == windowID }) else {
            throw NSError(domain: "WindowManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Window not found"])
        }

        let contentFilter = SCContentFilter(desktopIndependentWindow: window)
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = Int(window.frame.width)
        streamConfiguration.height = Int(window.frame.height)
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(1))
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        if #available(macOS 13, *) { streamConfiguration.capturesAudio = false }
        streamConfiguration.showsCursor = false
        streamConfiguration.scalesToFit = true
        streamConfiguration.queueDepth = 1

        let stream = SCStream(filter: contentFilter, configuration: streamConfiguration, delegate: nil)

        let captureDelegate = SingleFrameCaptureDelegate()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            captureDelegate.onFrame = { sampleBuffer in
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                    continuation.resume(throwing: NSError(domain: "WindowManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get pixel buffer"]))
                    return
                }

                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                let ciContext = CIContext()
                guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
                    continuation.resume(throwing: NSError(domain: "WindowManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"]))
                    return
                }

                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                guard let tiffData = nsImage.tiffRepresentation else {
                    continuation.resume(throwing: NSError(domain: "WindowManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to get TIFF representation"]))
                    return
                }

                continuation.resume(returning: tiffData)
                stream.stopCapture()
            }

            do {
                try stream.addStreamOutput(captureDelegate, type: .screen, sampleHandlerQueue: .main)
                stream.startCapture()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

class SingleFrameCaptureDelegate: NSObject, SCStreamOutput {
    var onFrame: ((CMSampleBuffer) -> Void)?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        onFrame?(sampleBuffer)
    }
}

actor CaptureState {
    var capturedData: Data?
    var captureError: Error?

    func setCapturedData(_ data: Data) {
        capturedData = data
    }

    func setCaptureError(_ error: Error) {
        captureError = error
    }
}

struct WindowThumbnail {
    let image: NSImage
    let window: SCWindow
}

class WindowInfo: NSObject {
    let title: SRString
    let app_name: SRString
    let bundle_id: SRString
    let is_on_screen: Bool
    let id: Int
    let thumbnail_data: Data

    init(title: SRString, app_name: SRString, bundle_id: SRString, is_on_screen: Bool, id: Int, thumbnail_data: Data) {
        self.title = title
        self.app_name = app_name
        self.bundle_id = bundle_id
        self.is_on_screen = is_on_screen
        self.id = id
        self.thumbnail_data = thumbnail_data
    }
}

@_cdecl("get_windows_info")
func getWindowsInfo(_ filter: Bool, _ capture: Bool) -> SRObjectArray {
    let windowManager = WindowManager.shared
    let semaphore = DispatchSemaphore(value: 0)

    windowManager.getWindows(filter: filter, capture: capture) {
        semaphore.signal()
    }

    semaphore.wait()

    var result: [WindowInfo] = []
    print("windows len", windowManager.windowThumbnails.count, windowManager.allWindows.count)
    print(windowManager.allWindows[0].windowID)

    for window in windowManager.allWindows {
        let windowInfo = WindowInfo(
            title: SRString(window.title ?? ""),
            app_name: SRString(window.owningApplication?.applicationName ?? ""),
            bundle_id: SRString(window.owningApplication?.bundleIdentifier ?? ""),
            is_on_screen: window.isOnScreen,
            id: Int(window.windowID),
            thumbnail_data: Data()
        )
        result.append(windowInfo)
    }

    return SRObjectArray(result)
}

@_cdecl("get_app_icon")
func getAppIcon(_ bundleId: SRString) -> SRString {
    let appIcon = SCContext.getAppIconPath(bundleId.toString());
    return SRString(appIcon ?? "")
}
