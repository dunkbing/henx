import AVFoundation
import ScreenCaptureKit
import UserNotifications

class SCContext {
    static var autoStop = 0
    static var recordCam = ""
    static var recordDevice = ""
    static var captureSession: AVCaptureSession!
    static var previewSession: AVCaptureSession!
    static var frameCache: CMSampleBuffer?
    static var filter: SCContentFilter?
    static var audioSettings: [String : Any]!
    static var isMagnifierEnabled = false
    static var saveFrame = false
    static var isPaused = false
    static var isResume = false
    static var isSkipFrame = false
    static var lastPTS: CMTime?
    static var timeOffset = CMTimeMake(
        value: 0,
        timescale: 0
    )
    static var screenArea: NSRect?
    static let audioEngine = AVAudioEngine()
    static var backgroundColor: CGColor = CGColor.black
    static var filePath: String!
    static var filePath1: String!
    static var filePath2: String!
    static var audioFile: AVAudioFile?
    static var audioFile2: AVAudioFile?
    static var vW: AVAssetWriter!
    static var vwInput, awInput, micInput: AVAssetWriterInput!
    static var startTime: Date?
    static var timePassed: TimeInterval = 0
    static var stream: SCStream!
    static var screen: SCDisplay?
    static var window: [SCWindow]?
    static var application: [SCRunningApplication]?
    static var streamType: StreamType?
    static var availableContent: SCShareableContent?
    static let excludedApps = [
        "",
        "com.apple.dock",
        "com.apple.screencaptureui",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "dev.mnpn.Azayaka",
        "com.gaosun.eul",
        "com.pointum.hazeover",
        "net.matthewpalmer.Vanilla",
        "com.dwarvesv.minimalbar",
        "com.bjango.istatmenus.status"
    ]
    
    static func updateAvailableContent(
        completion: @escaping () -> Void
    ) {
        SCShareableContent.getExcludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        ) {
            content,
            error in
            if let error = error {
                switch error {
                case SCStreamError.userDeclined: requestPermissions()
                default: print(
                    "Error: failed to fetch available content: ",
                    error.localizedDescription
                )
                }
                return
            }
            availableContent = content
            assert(
                availableContent?.displays.isEmpty != nil,
                "There needs to be at least one display connected!"
            )
            completion()
        }
    }
    
    static func getWindows(
        isOnScreen: Bool = true,
        hideSelf: Bool = true
    ) -> [SCWindow] {
        var windows = [SCWindow]()
        windows = availableContent!.windows.filter {
            guard let app =  $0.owningApplication,
                  let title = $0.title else {
                return false
            }
            return !excludedApps.contains(
                app.bundleIdentifier
            )
            && !title.contains(
                "Item-0"
            )
            && title != "Window"
            && $0.frame.width > 40
            && $0.frame.height > 40
        }
        if isOnScreen {
            windows = windows.filter({
                $0.isOnScreen == true
            })
        }
        if hideSelf && UserDefaults.standard.bool(
            forKey: "hideSelf"
        ) {
            windows = windows.filter({
                $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
            })
        }
        return windows
    }
    
    static func getAppIcon(
        _ app: SCRunningApplication
    ) -> NSImage? {
        if let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: app.bundleIdentifier
        ) {
            let icon = NSWorkspace.shared.icon(
                forFile: appURL.path
            )
            icon.size = NSSize(
                width: 69,
                height: 69
            )
            return icon
        }
        let icon = NSImage(
            systemSymbolName: "questionmark.app.dashed",
            accessibilityDescription: "blank icon"
        )
        icon!.size = NSSize(
            width: 69,
            height: 69
        )
        return icon
    }
    
    static func updateAudioSettings(
        format: String = UserDefaults.standard.string(
            forKey: "audioFormat"
        ) ?? ""
    ) {
        audioSettings = [
            AVSampleRateKey : 48000,
            AVNumberOfChannelsKey : 2
        ] // reset audioSettings
        switch format {
        case AudioFormat.aac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] = UserDefaults.standard.integer(
                forKey: "audioQuality"
            ) * 1000
        case AudioFormat.alac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatAppleLossless
            audioSettings[AVEncoderBitDepthHintKey] = 16
        case AudioFormat.flac.rawValue:
            audioSettings[AVFormatIDKey] = kAudioFormatFLAC
        case AudioFormat.opus.rawValue:
            audioSettings[AVFormatIDKey] = UserDefaults.standard.string(
                forKey: "videoFormat"
            ) != VideoFormat.mp4.rawValue ? kAudioFormatOpus : kAudioFormatMPEG4AAC
            audioSettings[AVEncoderBitRateKey] =  UserDefaults.standard.integer(
                forKey: "audioQuality"
            ) * 1000
        default:
            assertionFailure(
                "unknown audio format while setting audio settings: " + (
                    UserDefaults.standard.string(
                        forKey: "audioFormat"
                    ) ?? "[no defaults]"
                )
            )
        }
    }
    
    static func showNotification(
        title: String,
        body: String,
        id: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 1,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(
            request
        ) { error in
            if let error = error {
                print(
                    "Notification failed to send：\(error.localizedDescription)"
                )
            }
        }
    }
    
    private static func requestPermissions() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Required"
            alert.informativeText = "QuickRecorder needs screen recording permissions, even if you only intend on recording audio."
            alert.addButton(
                withTitle: "Open Settings"
            )
            alert.addButton(
                withTitle: "Quit"
            )
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                    )!
                )
            }
            NSApp.terminate(
                nil
            )
        }
    }
}
