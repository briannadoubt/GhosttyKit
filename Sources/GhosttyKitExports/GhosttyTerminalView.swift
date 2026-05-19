import AppKit

public enum GhosttyTerminalMouseButton: Equatable {
    case left
    case right
    case middle
    case other(Int)
}

@MainActor
public struct GhosttyTerminalViewConfiguration: Equatable {
    public var wantsLayer: Bool
    public var allowsFirstMouse: Bool
    public var trackingOptions: NSTrackingArea.Options

    public init(
        wantsLayer: Bool = true,
        allowsFirstMouse: Bool = true,
        trackingOptions: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .inVisibleRect,
            .mouseEnteredAndExited,
            .mouseMoved,
        ]
    ) {
        self.wantsLayer = wantsLayer
        self.allowsFirstMouse = allowsFirstMouse
        self.trackingOptions = trackingOptions
    }

    public static let `default` = GhosttyTerminalViewConfiguration()
}

@MainActor
public struct GhosttyTerminalViewHandlers {
    public var attach: (GhosttyTerminalView) -> Void
    public var resize: (CGSize) -> Void
    public var updateContentScale: () -> Void
    public var render: () -> Void
    public var focusChanged: (Bool) -> Void
    public var occlusionChanged: (Bool) -> Void
    public var displayChanged: (CGDirectDisplayID?) -> Void
    public var appearanceChanged: (NSAppearance) -> Void
    public var keyboardLayoutChanged: () -> Void
    public var primaryInteraction: () -> Void
    public var keyDown: (NSEvent, String?) -> Void
    public var keyUp: (NSEvent) -> Void
    public var insertText: (String) -> Void
    public var markedTextChanged: (String?) -> Void
    public var mouseButton: (GhosttyTerminalMouseButton, Bool, NSEvent) -> Bool
    public var mousePosition: (NSEvent) -> Void
    public var mouseExit: (NSEvent.ModifierFlags) -> Void
    public var scrollWheel: (NSEvent) -> Void
    public var copySelection: () -> String?
    public var paste: (String) -> Void
    public var selectAll: () -> Void
    public var hasSelection: () -> Bool
    public var openHoveredLink: () -> Void
    public var copyHoveredLink: () -> String?
    public var hasHoveredLink: () -> Bool
    public var openConfig: () -> Void
    public var performCommand: (Selector) -> Bool

    public init(
        attach: @escaping (GhosttyTerminalView) -> Void,
        resize: @escaping (CGSize) -> Void,
        updateContentScale: @escaping () -> Void,
        render: @escaping () -> Void,
        focusChanged: @escaping (Bool) -> Void,
        occlusionChanged: @escaping (Bool) -> Void,
        displayChanged: @escaping (CGDirectDisplayID?) -> Void,
        appearanceChanged: @escaping (NSAppearance) -> Void,
        keyboardLayoutChanged: @escaping () -> Void,
        primaryInteraction: @escaping () -> Void,
        keyDown: @escaping (NSEvent, String?) -> Void,
        keyUp: @escaping (NSEvent) -> Void,
        insertText: @escaping (String) -> Void,
        markedTextChanged: @escaping (String?) -> Void,
        mouseButton: @escaping (GhosttyTerminalMouseButton, Bool, NSEvent) -> Bool,
        mousePosition: @escaping (NSEvent) -> Void,
        mouseExit: @escaping (NSEvent.ModifierFlags) -> Void,
        scrollWheel: @escaping (NSEvent) -> Void,
        copySelection: @escaping () -> String?,
        paste: @escaping (String) -> Void,
        selectAll: @escaping () -> Void,
        hasSelection: @escaping () -> Bool,
        openHoveredLink: @escaping () -> Void = {},
        copyHoveredLink: @escaping () -> String? = { nil },
        hasHoveredLink: @escaping () -> Bool = { false },
        openConfig: @escaping () -> Void = {},
        performCommand: @escaping (Selector) -> Bool
    ) {
        self.attach = attach
        self.resize = resize
        self.updateContentScale = updateContentScale
        self.render = render
        self.focusChanged = focusChanged
        self.occlusionChanged = occlusionChanged
        self.displayChanged = displayChanged
        self.appearanceChanged = appearanceChanged
        self.keyboardLayoutChanged = keyboardLayoutChanged
        self.primaryInteraction = primaryInteraction
        self.keyDown = keyDown
        self.keyUp = keyUp
        self.insertText = insertText
        self.markedTextChanged = markedTextChanged
        self.mouseButton = mouseButton
        self.mousePosition = mousePosition
        self.mouseExit = mouseExit
        self.scrollWheel = scrollWheel
        self.copySelection = copySelection
        self.paste = paste
        self.selectAll = selectAll
        self.hasSelection = hasSelection
        self.openHoveredLink = openHoveredLink
        self.copyHoveredLink = copyHoveredLink
        self.hasHoveredLink = hasHoveredLink
        self.openConfig = openConfig
        self.performCommand = performCommand
    }
}

@MainActor
public final class GhosttyTerminalView: NSView, @preconcurrency NSTextInputClient {
    public var handlers: GhosttyTerminalViewHandlers? {
        didSet {
            attachHandlersIfReady()
            handlers?.displayChanged(currentDisplayID())
            handlers?.occlusionChanged(window?.occlusionState.contains(.visible) == false)
            requestRender()
        }
    }

    public private(set) var configuration: GhosttyTerminalViewConfiguration
    private var trackingArea: NSTrackingArea?
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var pendingRenderRequest = false
    private var isRendering = false
    private var observedWindow: NSWindow?
    private var cursorHidden = false
    nonisolated(unsafe) private var windowObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var globalObservers: [NSObjectProtocol] = []

    public init(
        frame frameRect: NSRect = NSRect(x: 0, y: 0, width: 800, height: 500),
        configuration: GhosttyTerminalViewConfiguration = .default
    ) {
        self.configuration = configuration
        super.init(frame: frameRect)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        apply(configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        let notificationCenter = NotificationCenter.default
        for observer in windowObservers + globalObservers {
            notificationCenter.removeObserver(observer)
        }
    }

    public override var acceptsFirstResponder: Bool { true }
    public override var wantsUpdateLayer: Bool { true }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        configuration.allowsFirstMouse
    }

    public func apply(configuration: GhosttyTerminalViewConfiguration) {
        let configurationChanged = self.configuration != configuration
        self.configuration = configuration
        wantsLayer = configuration.wantsLayer
        layer?.backgroundColor = GhosttyDefaultTheme.fallbackBackgroundColor(
            effectiveAppearance: effectiveAppearance,
            applicationAppearance: NSApp?.effectiveAppearance
        ).cgColor
        if configurationChanged {
            needsLayout = true
            updateTrackingAreas()
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateObservers()
        attachHandlersIfReady()
        layer?.backgroundColor = GhosttyDefaultTheme.fallbackBackgroundColor(
            effectiveAppearance: effectiveAppearance,
            applicationAppearance: NSApp?.effectiveAppearance
        ).cgColor
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: configuration.trackingOptions, owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        handlers?.updateContentScale()
        handlers?.displayChanged(currentDisplayID())
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = GhosttyDefaultTheme.fallbackBackgroundColor(
            effectiveAppearance: effectiveAppearance,
            applicationAppearance: NSApp?.effectiveAppearance
        ).cgColor
        handlers?.appearanceChanged(effectiveAppearance)
    }

    public override func updateLayer() {
        requestRender()
    }

    public override func layout() {
        super.layout()
        handlers?.resize(bounds.size)
    }

    public override func becomeFirstResponder() -> Bool {
        handlers?.primaryInteraction()
        handlers?.focusChanged(true)
        return true
    }

    public override func resignFirstResponder() -> Bool {
        handlers?.focusChanged(false)
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        handlers?.primaryInteraction()
        requestWindowFirstResponder()
        handlers?.mousePosition(event)
        _ = handlers?.mouseButton(.left, true, event)
    }

    public override func mouseUp(with event: NSEvent) {
        handlers?.mousePosition(event)
        _ = handlers?.mouseButton(.left, false, event)
    }

    public override func rightMouseDown(with event: NSEvent) {
        handlers?.primaryInteraction()
        requestWindowFirstResponder()
        handlers?.mousePosition(event)
        if handlers?.mouseButton(.right, true, event) != true {
            presentContextMenu(with: event)
        }
    }

    public override func rightMouseUp(with event: NSEvent) {
        handlers?.mousePosition(event)
        _ = handlers?.mouseButton(.right, false, event)
    }

    public override func otherMouseDown(with event: NSEvent) {
        handlers?.primaryInteraction()
        requestWindowFirstResponder()
        handlers?.mousePosition(event)
        _ = handlers?.mouseButton(.other(Int(event.buttonNumber)), true, event)
    }

    public override func otherMouseUp(with event: NSEvent) {
        handlers?.mousePosition(event)
        _ = handlers?.mouseButton(.other(Int(event.buttonNumber)), false, event)
    }

    public override func mouseEntered(with event: NSEvent) { handlers?.mousePosition(event) }
    public override func mouseExited(with event: NSEvent) { handlers?.mouseExit(event.modifierFlags) }
    public override func mouseMoved(with event: NSEvent) { handlers?.mousePosition(event) }
    public override func mouseDragged(with event: NSEvent) { handlers?.mousePosition(event) }
    public override func rightMouseDragged(with event: NSEvent) { handlers?.mousePosition(event) }
    public override func otherMouseDragged(with event: NSEvent) { handlers?.mousePosition(event) }
    public override func scrollWheel(with event: NSEvent) { handlers?.scrollWheel(event) }

    public override func keyDown(with event: NSEvent) {
        keyTextAccumulator = []
        interpretKeyEvents([event])
        let text = keyTextAccumulator?.joined()
        keyTextAccumulator = nil
        handlers?.keyDown(event, text?.isEmpty == true ? nil : text)
    }

    public override func keyUp(with event: NSEvent) {
        handlers?.keyUp(event)
    }

    public override func flagsChanged(with event: NSEvent) {
        handlers?.mousePosition(event)
        super.flagsChanged(with: event)
    }

    @objc public func copy(_ sender: Any?) {
        guard let text = handlers?.copySelection(), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc public func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        handlers?.paste(text)
    }

    public override func selectAll(_ sender: Any?) {
        handlers?.selectAll()
    }

    @objc public func openHoveredLink(_ sender: Any?) {
        handlers?.openHoveredLink()
    }

    @objc public func copyHoveredLink(_ sender: Any?) {
        guard let url = handlers?.copyHoveredLink(), !url.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    @objc public func openTerminalConfig(_ sender: Any?) {
        handlers?.openConfig()
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isMenuActionEnabled(menuItem.action)
    }

    public override func doCommand(by selector: Selector) {
        if handlers?.performCommand(selector) == true {
            return
        }
        if Self.shouldSuppressSystemTextInputCommand(selector) {
            return
        }
        super.doCommand(by: selector)
    }

    public func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    public func markedRange() -> NSRange {
        hasMarkedText() ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0)
    }

    public func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text = Self.plainString(from: string) ?? ""
        markedText = NSMutableAttributedString(string: text)
        handlers?.markedTextChanged(text.isEmpty ? nil : text)
    }

    public func unmarkText() {
        markedText = NSMutableAttributedString()
        handlers?.markedTextChanged(nil)
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    public func characterIndex(for point: NSPoint) -> Int { 0 }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(bounds, to: nil))
    }

    public func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = Self.plainString(from: string) else { return }
        unmarkText()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
        } else {
            handlers?.insertText(text)
        }
    }

    public func requestFocus() {
        requestWindowFirstResponder()
    }

    public func requestRender() {
        pendingRenderRequest = true
        needsDisplay = true
        layer?.setNeedsDisplay()
        renderIfNeeded()
    }

    public func applyCursor(for shape: ghostty_action_mouse_shape_e) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_TEXT,
             GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT:
            NSCursor.iBeam.set()
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            NSCursor.pointingHand.set()
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
            NSCursor.crosshair.set()
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED,
             GHOSTTY_MOUSE_SHAPE_NO_DROP:
            NSCursor.operationNotAllowed.set()
        case GHOSTTY_MOUSE_SHAPE_COL_RESIZE,
             GHOSTTY_MOUSE_SHAPE_EW_RESIZE:
            NSCursor.resizeLeftRight.set()
        case GHOSTTY_MOUSE_SHAPE_ROW_RESIZE,
             GHOSTTY_MOUSE_SHAPE_NS_RESIZE:
            NSCursor.resizeUpDown.set()
        case GHOSTTY_MOUSE_SHAPE_GRAB,
             GHOSTTY_MOUSE_SHAPE_GRABBING:
            NSCursor.openHand.set()
        default:
            NSCursor.arrow.set()
        }
    }

    public func setCursorHidden(_ hidden: Bool) {
        guard cursorHidden != hidden else { return }
        cursorHidden = hidden
        NSCursor.setHiddenUntilMouseMoves(hidden)
    }

    public static func shouldSuppressSystemTextInputCommand(_ selector: Selector) -> Bool {
        selector == #selector(NSResponder.insertNewline(_:))
            || selector == #selector(NSResponder.insertLineBreak(_:))
            || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            || selector == #selector(NSResponder.insertTab(_:))
            || selector == #selector(NSResponder.insertBacktab(_:))
            || selector == #selector(NSResponder.deleteBackward(_:))
            || selector == #selector(NSResponder.deleteForward(_:))
            || selector == #selector(NSResponder.deleteWordBackward(_:))
            || selector == #selector(NSResponder.deleteWordForward(_:))
            || selector == #selector(NSResponder.deleteToBeginningOfLine(_:))
            || selector == #selector(NSResponder.deleteToEndOfLine(_:))
            || selector == #selector(NSResponder.moveUp(_:))
            || selector == #selector(NSResponder.moveDown(_:))
            || selector == #selector(NSResponder.moveLeft(_:))
            || selector == #selector(NSResponder.moveRight(_:))
            || selector == #selector(NSResponder.moveWordLeft(_:))
            || selector == #selector(NSResponder.moveWordRight(_:))
            || selector == #selector(NSResponder.moveToBeginningOfLine(_:))
            || selector == #selector(NSResponder.moveToEndOfLine(_:))
            || selector == #selector(NSResponder.pageUp(_:))
            || selector == #selector(NSResponder.pageDown(_:))
            || selector == #selector(NSResponder.cancelOperation(_:))
    }

    private func attachHandlersIfReady() {
        guard window != nil else { return }
        handlers?.attach(self)
        renderIfNeeded()
    }

    private func renderIfNeeded() {
        guard handlers != nil, !isRendering else { return }
        while pendingRenderRequest {
            pendingRenderRequest = false
            isRendering = true
            handlers?.render()
            isRendering = false
        }
    }

    private func updateObservers() {
        let notificationCenter = NotificationCenter.default
        if observedWindow !== window {
            for observer in windowObservers {
                notificationCenter.removeObserver(observer)
            }
            windowObservers.removeAll()
            observedWindow = window

            if let window {
                windowObservers.append(
                    notificationCenter.addObserver(
                        forName: NSWindow.didChangeOcclusionStateNotification,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.handlers?.occlusionChanged(window.occlusionState.contains(.visible) == false)
                        }
                    }
                )
                windowObservers.append(
                    notificationCenter.addObserver(
                        forName: NSWindow.didChangeScreenNotification,
                        object: window,
                        queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.handlers?.displayChanged(self?.currentDisplayID())
                        }
                    }
                )
            }
        }

        if globalObservers.isEmpty {
            globalObservers.append(
                notificationCenter.addObserver(
                    forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.handlers?.keyboardLayoutChanged()
                    }
                }
            )
        }
    }

    private func requestWindowFirstResponder() {
        guard let window else { return }
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
        if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
    }

    private func currentDisplayID() -> CGDirectDisplayID? {
        guard let screenNumber = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func presentContextMenu(with event: NSEvent) {
        guard let menu = makeContextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    public func makeContextMenu() -> NSMenu? {
        guard handlers != nil else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuItem(title: "Copy", action: #selector(copy(_:))))
        menu.addItem(menuItem(title: "Paste", action: #selector(paste(_:))))
        menu.addItem(menuItem(title: "Select All", action: #selector(selectAll(_:))))

        if handlers?.hasHoveredLink() == true {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(menuItem(title: "Open Hovered Link", action: #selector(openHoveredLink(_:))))
            menu.addItem(menuItem(title: "Copy Hovered Link", action: #selector(copyHoveredLink(_:))))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem(title: "Open Terminal Config", action: #selector(openTerminalConfig(_:))))
        return menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isMenuActionEnabled(action)
        return item
    }

    private func isMenuActionEnabled(_ action: Selector?) -> Bool {
        switch action {
        case #selector(copy(_:)):
            return handlers?.hasSelection() == true
        case #selector(paste(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        case #selector(selectAll(_:)):
            return handlers != nil
        case #selector(openHoveredLink(_:)),
             #selector(copyHoveredLink(_:)):
            return handlers?.hasHoveredLink() == true
        case #selector(openTerminalConfig(_:)):
            return handlers != nil
        default:
            return false
        }
    }

    private static func plainString(from string: Any) -> String? {
        switch string {
        case let string as String:
            return string
        case let attributed as NSAttributedString:
            return attributed.string
        default:
            return nil
        }
    }
}
