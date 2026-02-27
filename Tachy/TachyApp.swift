import SwiftUI

@main
struct TachyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.dictationManager)
        }
    }
}

// MARK: - Floating Panel (non-activating, resizable, stays on top)

/// Wrapper view that adds resize cursor rects at the edges of a borderless window.
class ResizableContentView: NSView {
}

class FloatingPanel: NSPanel {
    private let edgeThickness: CGFloat = 6

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(hostingView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
            styleMask: [.nonactivatingPanel, .resizable, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        // Wrap in ResizableContentView for cursor rects
        let wrapper = ResizableContentView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 12
        wrapper.layer?.masksToBounds = true
        hostingView.frame = wrapper.bounds
        hostingView.autoresizingMask = [.width, .height]
        wrapper.addSubview(hostingView)
        self.contentView = wrapper

        acceptsMouseMovedEvents = true
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        minSize = NSSize(width: 320, height: 280)
        maxSize = NSSize(width: 800, height: 1200)
    }

    override func sendEvent(_ event: NSEvent) {
        var shouldUpdateCursor = false
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .cursorUpdate:
            shouldUpdateCursor = true
        default:
            break
        }
        super.sendEvent(event)
        if shouldUpdateCursor {
            updateResizeCursor(at: event.locationInWindow)
        }
    }

    private func updateResizeCursor(at point: NSPoint) {
        let rect = NSRect(origin: .zero, size: frame.size)
        guard rect.contains(point) else { return }

        let left = point.x <= edgeThickness
        let right = point.x >= rect.maxX - edgeThickness
        let bottom = point.y <= edgeThickness
        let top = point.y >= rect.maxY - edgeThickness

        if left || right {
            NSCursor.resizeLeftRight.set()
        } else if top || bottom {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var floatingPanel: FloatingPanel!
    let dictationManager = DictationManager()
    var globalFlagsMonitor: Any?
    var localFlagsMonitor: Any?
    var escapeMonitor: Any?
    var settingsWindow: NSWindow?

    // Double-tap Control detection
    private var lastCtrlReleaseTime: Date?
    private var ctrlPressedAlone = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Tachy")
            button.action = #selector(togglePanel)
            button.target = self
        }

        setupFloatingPanel()
        registerDoubleTapCtrl()
        registerEscapeMonitor()

        dictationManager.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.updateIcon(for: state)
            }
        }
    }

    // MARK: - Floating Panel Setup

    private func setupFloatingPanel() {
        let hostingView = NSHostingView(
            rootView: TachyPanelView()
                .environmentObject(dictationManager)
        )

        floatingPanel = FloatingPanel(hostingView: hostingView)
        positionPanel()
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = floatingPanel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height - 20
        floatingPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() {
        // Silent check on launch: do not interrupt the user with permission prompts/alerts.
        _ = AXIsProcessTrusted()
    }

    // MARK: - Icon State

    func updateIcon(for state: DictationState) {
        guard let button = statusItem.button else { return }

        let color: NSColor
        switch state {
        case .idle:
            // Default template image (follows menu bar appearance)
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Ready")
            button.image?.isTemplate = true
            button.contentTintColor = nil
            return
        case .recording, .liveTranscribing:
            color = .systemRed
        case .transcribing:
            color = .systemOrange
        case .refining:
            color = .systemPurple
        }

        // Non-template colored image for active states
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        if let img = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let coloredImg = NSImage(size: img.size, flipped: false) { rect in
                color.set()
                img.draw(in: rect)
                return true
            }
            coloredImg.isTemplate = false
            button.image = coloredImg
        }
        button.contentTintColor = nil
    }

    // MARK: - Hotkeys

    func registerDoubleTapCtrl() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.ctrlPressedAlone = false
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.ctrlPressedAlone = false
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        if event.keyCode == 57 { return }

        if event.modifierFlags.contains(.capsLock) &&
           !event.modifierFlags.contains(.control) &&
           !event.modifierFlags.contains(.shift) &&
           !event.modifierFlags.contains(.option) &&
           !event.modifierFlags.contains(.command) {
            return
        }

        let ctrlPressed = event.modifierFlags.contains(.control)
        let otherModifiers = event.modifierFlags.intersection([.shift, .option, .command, .capsLock])

        if ctrlPressed {
            if otherModifiers.isEmpty {
                ctrlPressedAlone = true
            } else {
                ctrlPressedAlone = false
            }
        } else if ctrlPressedAlone && otherModifiers.isEmpty {
            let now = Date()
            if let lastRelease = lastCtrlReleaseTime,
               now.timeIntervalSince(lastRelease) < 0.4 {
                lastCtrlReleaseTime = nil
                DispatchQueue.main.async { [weak self] in
                    self?.dictationManager.toggleRecording()
                }
            } else {
                lastCtrlReleaseTime = now
            }
        } else {
            ctrlPressedAlone = false
        }
    }

    func registerEscapeMonitor() {
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dictationManager.cancelRecording()
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dictationManager.cancelRecording()
                return nil
            }
            return event
        }
    }

    // MARK: - Panel Toggle

    @objc func togglePanel() {
        if floatingPanel.isVisible {
            floatingPanel.orderOut(nil)
        } else {
            positionPanel()
            floatingPanel.orderFront(nil)
        }
    }
}
