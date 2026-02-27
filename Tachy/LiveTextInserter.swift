import Foundation
import AppKit
import ApplicationServices

class LiveTextInserter {
    private var committedText: String = ""
    private var pendingText: String = ""

    // Batching: accumulate deltas and flush every 80ms
    private var batchBuffer: String = ""
    private var batchTimer: DispatchSourceTimer?
    private let batchQueue = DispatchQueue(label: "com.tachy.textinserter", qos: .userInteractive)
    private static let batchInterval: TimeInterval = 0.080 // 80ms

    // Clipboard restore debounce
    private var clipboardRestoreWork: DispatchWorkItem?
    private static let clipboardRestoreDelay: TimeInterval = 1.0

    /// Append new delta text — batched before inserting.
    func appendDelta(_ delta: String) {
        pendingText += delta
        batchQueue.async { [weak self] in
            self?.enqueueDelta(delta)
        }
    }

    /// Commit current turn — text stays, start tracking a new turn.
    func commitTurn() {
        flushBatch()
        committedText += pendingText
        pendingText = ""
    }

    /// Delete all inserted text (both committed and pending).
    func deleteAllInserted() {
        flushBatch()
        let total = committedText.count + pendingText.count
        if total > 0 {
            sendBackspaces(count: total)
        }
        committedText = ""
        pendingText = ""
    }

    /// Get all text inserted so far.
    var allText: String {
        committedText + pendingText
    }

    /// Reset state without deleting text on screen.
    func reset() {
        cancelBatch()
        committedText = ""
        pendingText = ""
    }

    // MARK: - Batching

    private func enqueueDelta(_ delta: String) {
        batchBuffer += delta

        if batchTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: batchQueue)
            timer.schedule(deadline: .now() + Self.batchInterval)
            timer.setEventHandler { [weak self] in
                self?.flushBatch()
            }
            timer.resume()
            batchTimer = timer
        }
    }

    private func flushBatch() {
        batchQueue.async { [weak self] in
            self?._flushBatchSync()
        }
    }

    private func _flushBatchSync() {
        guard !batchBuffer.isEmpty else { return }
        let text = batchBuffer
        batchBuffer = ""
        batchTimer?.cancel()
        batchTimer = nil
        insertText(text)
    }

    private func cancelBatch() {
        batchQueue.async { [weak self] in
            self?.batchBuffer = ""
            self?.batchTimer?.cancel()
            self?.batchTimer = nil
        }
    }

    // MARK: - Hybrid text insertion

    private func insertText(_ text: String) {
        // Try AXUIElement first (works in native Cocoa apps)
        if insertViaAccessibility(text) {
            return
        }
        // Fallback: clipboard + Cmd+V (works everywhere)
        insertViaClipboard(text)
    }

    /// Attempt 1: Insert text via Accessibility API (AXUIElement).
    /// Sets the focused element's selected text range, then replaces selection.
    private func insertViaAccessibility(_ text: String) -> Bool {
        guard let focusedElement = getFocusedTextElement() else { return false }

        // Try setting the value by inserting at the current insertion point
        // Use kAXSelectedTextAttribute to replace the current selection (which is empty = insert)
        let result = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        return result == .success
    }

    /// Get the focused text element via Accessibility API.
    private func getFocusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let app = focusedApp else {
            return nil
        }

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
              let element = focusedElement else {
            return nil
        }

        // Verify it supports text by checking for kAXValueAttribute
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)

        let axElement = element as! AXUIElement

        // Check that the element has the selectedText attribute (i.e., it's a text field)
        var selectedText: AnyObject?
        let check = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &selectedText)
        guard check == .success || check == .attributeUnsupported else {
            return nil
        }

        // If attributeUnsupported, it's not a text field
        if check == .attributeUnsupported {
            return nil
        }

        return axElement
    }

    /// Attempt 2 (fallback): Insert text via clipboard + Cmd+V.
    private func insertViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard content
        let previousContent = pasteboard.string(forType: .string)

        // Cancel any pending clipboard restore
        clipboardRestoreWork?.cancel()

        // Set text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Send Cmd+V with privateState source to avoid picking up physical modifiers
        let source = CGEventSource(stateID: .privateState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                            state: .eventSuppressionStateSuppressionInterval)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 0x09 = 'V'
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)

        // Restore clipboard after 1s debounce
        let restoreWork = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            if let previous = previousContent {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
        clipboardRestoreWork = restoreWork
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clipboardRestoreDelay, execute: restoreWork)
    }

    // MARK: - Backspaces

    private func sendBackspaces(count: Int) {
        let source = CGEventSource(stateID: .privateState)
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                            state: .eventSuppressionStateSuppressionInterval)

        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
            keyDown?.flags = [] // Empty flags — no modifiers
            keyDown?.post(tap: .cgAnnotatedSessionEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
            keyUp?.flags = []
            keyUp?.post(tap: .cgAnnotatedSessionEventTap)

            usleep(500) // 0.5ms between each backspace for reliability
        }
    }
}
