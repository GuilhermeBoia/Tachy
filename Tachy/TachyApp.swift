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

// MARK: - Floating Panel (non-activating, compact pill)

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(hostingView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 50),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )

        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 25
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
    }

    func resizePanel(to size: NSSize, cornerRadius: CGFloat, animate: Bool, centerOnScreen: Bool = false) {
        let newFrame: NSRect
        if centerOnScreen || !isVisible {
            guard let screen = NSScreen.main else { return }
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - size.width / 2
            let y = screenFrame.minY + 40
            newFrame = NSRect(x: x, y: y, width: size.width, height: size.height)
        } else {
            // Keep current position, just resize anchored at bottom-left
            let current = frame
            let x = current.origin.x + (current.width - size.width) / 2
            let y = current.origin.y
            newFrame = NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.contentView?.layer?.cornerRadius = cornerRadius
            }
        } else {
            setFrame(newFrame, display: true)
            contentView?.layer?.cornerRadius = cornerRadius
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
    var historyWindow: NSWindow?

    // Double-tap Control detection (toggle recording)
    private var lastCtrlReleaseTime: Date?
    private var ctrlPressedAlone = true

    // Double-tap Shift detection (pause/resume)
    private var lastShiftReleaseTime: Date?
    private var shiftPressedAlone = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Tachy")
            button.action = #selector(showMenu)
            button.target = self
        }

        setupFloatingPanel()
        registerDoubleTapCtrl()
        registerEscapeMonitor()

        // Listen for result height changes from SwiftUI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResultHeightChange(_:)),
            name: Notification.Name("TachyResultHeightChanged"),
            object: nil
        )

        dictationManager.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.updateIcon(for: state)
                self.handlePanelVisibility(for: state)
            }
        }
    }

    // MARK: - Panel Visibility Logic

    private func handlePanelVisibility(for state: DictationState) {
        switch state {
        case .recording, .liveTranscribing, .paused:
            // Show pill
            floatingPanel.resizePanel(to: NSSize(width: 300, height: 50), cornerRadius: 25, animate: floatingPanel.isVisible)
            if !floatingPanel.isVisible {
                floatingPanel.orderFront(nil)
            }

        case .transcribing, .refining:
            // Keep pill visible
            floatingPanel.resizePanel(to: NSSize(width: 300, height: 50), cornerRadius: 25, animate: true)
            if !floatingPanel.isVisible {
                floatingPanel.orderFront(nil)
            }

        case .idle:
            if dictationManager.showingResult {
                // Expand to result view
                floatingPanel.resizePanel(to: NSSize(width: 380, height: 150), cornerRadius: 16, animate: true)
                if !floatingPanel.isVisible {
                    floatingPanel.orderFront(nil)
                }
            } else {
                // Hide panel
                floatingPanel.orderOut(nil)
            }
        }
    }

    @objc private func handleResultHeightChange(_ notification: Notification) {
        guard let height = notification.userInfo?["height"] as? CGFloat else { return }
        let clampedHeight = min(max(height + 20, 80), 350) // padding + clamp
        if dictationManager.state == .idle && dictationManager.showingResult {
            floatingPanel.resizePanel(to: NSSize(width: 380, height: clampedHeight), cornerRadius: 16, animate: true)
        }
    }

    // MARK: - Floating Panel Setup

    private func setupFloatingPanel() {
        let hostingView = NSHostingView(
            rootView: TachyPanelView()
                .environmentObject(dictationManager)
        )

        floatingPanel = FloatingPanel(hostingView: hostingView)
        // Start hidden
        floatingPanel.orderOut(nil)
    }

    // MARK: - NSMenu on Status Item

    @objc func showMenu() {
        let menu = NSMenu()

        let historyItem = NSMenuItem(title: "Histórico", action: #selector(openHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Ajustes", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Sair", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu so the next click triggers action again
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    @objc private func openHistory() {
        if let window = historyWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = TachyHistoryView()
            .environmentObject(dictationManager)
            .frame(minWidth: 380, minHeight: 400)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Histórico — Tachy"
        window.contentView = NSHostingView(rootView: historyView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = window
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() {
        _ = AXIsProcessTrusted()
    }

    // MARK: - Icon State

    func updateIcon(for state: DictationState) {
        guard let button = statusItem.button else { return }

        let color: NSColor
        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Ready")
            button.image?.isTemplate = true
            button.contentTintColor = nil
            return
        case .recording, .liveTranscribing:
            color = .systemRed
        case .paused:
            color = .systemYellow
        case .transcribing:
            color = .systemOrange
        case .refining:
            color = .systemPurple
        }

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
            self?.shiftPressedAlone = false
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.ctrlPressedAlone = false
            self?.shiftPressedAlone = false
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

        let ctrl = event.modifierFlags.contains(.control)
        let opt = event.modifierFlags.contains(.option)
        let shift = event.modifierFlags.contains(.shift)
        let cmd = event.modifierFlags.contains(.command)
        let capsLock = event.modifierFlags.contains(.capsLock)

        // --- Double-tap Control (toggle recording) ---
        let ctrlOthers = [opt, shift, cmd, capsLock].contains(true)
        if ctrl {
            ctrlPressedAlone = !ctrlOthers
        } else if ctrlPressedAlone && !ctrlOthers {
            let now = Date()
            if let last = lastCtrlReleaseTime, now.timeIntervalSince(last) < 0.4 {
                lastCtrlReleaseTime = nil
                DispatchQueue.main.async { [weak self] in
                    self?.dictationManager.toggleRecording()
                }
            } else {
                lastCtrlReleaseTime = now
            }
            ctrlPressedAlone = false
        } else if !ctrl {
            ctrlPressedAlone = false
        }

        // --- Double-tap Shift (pause/resume) ---
        let shiftOthers = [ctrl, opt, cmd, capsLock].contains(true)
        if shift {
            shiftPressedAlone = !shiftOthers
        } else if shiftPressedAlone && !shiftOthers {
            let now = Date()
            if let last = lastShiftReleaseTime, now.timeIntervalSince(last) < 0.4 {
                lastShiftReleaseTime = nil
                DispatchQueue.main.async { [weak self] in
                    self?.dictationManager.togglePause()
                }
            } else {
                lastShiftReleaseTime = now
            }
            shiftPressedAlone = false
        } else if !shift {
            shiftPressedAlone = false
        }
    }

    func registerEscapeMonitor() {
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.handleEscape()
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.handleEscape()
                return nil
            }
            return event
        }
    }

    private func handleEscape() {
        if dictationManager.state == .idle && dictationManager.showingResult {
            dictationManager.dismissResult()
        } else {
            dictationManager.cancelRecording()
        }
    }
}
