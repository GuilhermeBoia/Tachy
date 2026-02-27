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
    private let edgeThickness: CGFloat = 6

    override func resetCursorRects() {
        super.resetCursorRects()
        let b = bounds

        // Corners (8x8)
        let cs: CGFloat = 8
        // Bottom-left
        addCursorRect(NSRect(x: 0, y: 0, width: cs, height: cs), cursor: .crosshair)
        // Bottom-right
        addCursorRect(NSRect(x: b.maxX - cs, y: 0, width: cs, height: cs), cursor: .crosshair)
        // Top-left
        addCursorRect(NSRect(x: 0, y: b.maxY - cs, width: cs, height: cs), cursor: .crosshair)
        // Top-right
        addCursorRect(NSRect(x: b.maxX - cs, y: b.maxY - cs, width: cs, height: cs), cursor: .crosshair)

        // Left edge
        addCursorRect(NSRect(x: 0, y: cs, width: edgeThickness, height: b.height - 2 * cs), cursor: .resizeLeftRight)
        // Right edge
        addCursorRect(NSRect(x: b.maxX - edgeThickness, y: cs, width: edgeThickness, height: b.height - 2 * cs), cursor: .resizeLeftRight)
        // Bottom edge
        addCursorRect(NSRect(x: cs, y: 0, width: b.width - 2 * cs, height: edgeThickness), cursor: .resizeUpDown)
        // Top edge
        addCursorRect(NSRect(x: cs, y: b.maxY - edgeThickness, width: b.width - 2 * cs, height: edgeThickness), cursor: .resizeUpDown)
    }
}

class FloatingPanel: NSPanel {
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
        checkAccessibilityPermission()
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

        // Close when clicking outside (unless recording)
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self, self.floatingPanel.isVisible else { return }
            let isRecording = self.dictationManager.state == .recording ||
                              self.dictationManager.state == .liveTranscribing
            if !isRecording {
                self.floatingPanel.orderOut(nil)
            }
        }
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
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.showAccessibilityAlert()
            }
        }
    }

    private func showAccessibilityAlert() {
        guard !AXIsProcessTrusted() else { return }
        let alert = NSAlert()
        alert.messageText = "Permissão de Acessibilidade Necessária"
        alert.informativeText = "Tachy precisa de permissão de Acessibilidade para capturar atalhos globais e colar texto. Adicione o app em Ajustes do Sistema > Privacidade e Segurança > Acessibilidade."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Depois")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
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
