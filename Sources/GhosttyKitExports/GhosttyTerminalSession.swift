import AppKit
import Carbon

public enum GhosttyTerminalColorScheme: Sendable {
    case light
    case dark
    case system
}

public enum GhosttyTerminalProgressState: Equatable, Sendable {
    case none
    case active
    case error
    case indeterminate
    case paused
}

public enum GhosttyTerminalSecureInputState: Equatable, Sendable {
    case inactive
    case active
}

public enum GhosttyTerminalSplitDirection: Equatable, Sendable {
    case left
    case right
    case up
    case down
}

public enum GhosttyTerminalRequest: Equatable, Sendable {
    case newWindow
    case closeWindow
    case newTab
    case closeTab
    case newSplit(GhosttyTerminalSplitDirection)
    case equalizeSplits
    case toggleSplitZoom
    case toggleCommandPalette
}

public struct GhosttyTerminalNotification: Equatable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public struct GhosttyTerminalGridSize: Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct GhosttyTerminalSizeLimits: Equatable, Sendable {
    public var minimumWidth: Int
    public var minimumHeight: Int
    public var maximumWidth: Int?
    public var maximumHeight: Int?

    public init(minimumWidth: Int, minimumHeight: Int, maximumWidth: Int?, maximumHeight: Int?) {
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
        self.maximumWidth = maximumWidth
        self.maximumHeight = maximumHeight
    }
}

public struct GhosttyTerminalConfigDiagnostic: Equatable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

public enum GhosttyTerminalAction: Equatable, Sendable {
    case setTitle(String?)
    case setTabTitle(String?)
    case workingDirectory(String?)
    case hoveredLink(String?)
    case openURL(String?)
    case desktopNotification(title: String, body: String)
    case rendererHealth(Bool)
    case readonly(Bool)
    case render
    case openConfig
    case reloadConfig
    case ringBell
    case copyTitleToClipboard
    case startSearch(String)
    case endSearch
    case searchTotal(Int)
    case searchSelected(Int?)
    case progress(state: GhosttyTerminalProgressState, percent: Int?)
    case childExited(exitCode: Int)
    case commandFinished(exitCode: Int?, durationNanoseconds: UInt64)
    case secureInput(GhosttyTerminalSecureInputState)
    case request(GhosttyTerminalRequest)
    case sizeLimit(GhosttyTerminalSizeLimits)
    case initialSize(GhosttyTerminalGridSize)
    case cellSize(GhosttyTerminalGridSize)
    case mouseShape(ghostty_action_mouse_shape_e)
    case mouseVisibility(hidden: Bool)
    case unsupported(String)
}

@MainActor
public final class GhosttyTerminalState {
    public internal(set) var title: String?
    public internal(set) var tabTitle: String?
    public internal(set) var workingDirectory: String?
    public internal(set) var hoveredLinkURL: String?
    public internal(set) var rendererHealthy = true
    public internal(set) var isReadonly = false
    public internal(set) var isMouseHidden = false
    public internal(set) var secureInputState: GhosttyTerminalSecureInputState = .inactive
    public internal(set) var lastNotification: GhosttyTerminalNotification?
    public internal(set) var searchQuery = ""
    public internal(set) var searchTotal = 0
    public internal(set) var searchSelected: Int?
    public internal(set) var progressState: GhosttyTerminalProgressState = .none
    public internal(set) var progressPercent: Int?
    public internal(set) var childExitCode: Int?
    public internal(set) var lastCommandExitCode: Int?
    public internal(set) var lastCommandDurationNanoseconds: UInt64?
    public internal(set) var sizeLimits: GhosttyTerminalSizeLimits?
    public internal(set) var initialSize: GhosttyTerminalGridSize?
    public internal(set) var cellSize: GhosttyTerminalGridSize?
    public internal(set) var configDiagnostics: [GhosttyTerminalConfigDiagnostic] = []
    public internal(set) var lastAction: GhosttyTerminalAction?

    public init() {}
}

public struct GhosttyTerminalLaunchConfiguration: Sendable {
    public var command: String?
    public var workingDirectory: String?
    public var environment: [String: String]
    public var fontSize: Float
    public var colorScheme: GhosttyTerminalColorScheme
    public var bridgeSecureInput: Bool

    public init(
        command: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        fontSize: Float = 0,
        colorScheme: GhosttyTerminalColorScheme = .system,
        bridgeSecureInput: Bool = true
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.fontSize = fontSize
        self.colorScheme = colorScheme
        self.bridgeSecureInput = bridgeSecureInput
    }
}

@MainActor
public protocol GhosttyTerminalHostProtocol: AnyObject {
    var app: ghostty_app_t? { get }
    var config: ghostty_config_t? { get }
    var configDiagnostics: [GhosttyTerminalConfigDiagnostic] { get }

    func register(_ session: GhosttyTerminalSession)
    func unregister(_ session: GhosttyTerminalSession)
    func tick()
    func reloadConfig()
    func openConfig()
    func setColorScheme(_ colorScheme: GhosttyTerminalColorScheme, appearance: NSAppearance?)
}

public enum GhosttyTerminalHostError: Error, LocalizedError {
    case initializationFailed
    case configurationFailed
    case appCreationFailed

    public var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "ghostty_init failed"
        case .configurationFailed:
            return "ghostty_config_new failed"
        case .appCreationFailed:
            return "ghostty_app_new failed"
        }
    }
}

@MainActor
public final class GhosttyTerminalHost: GhosttyTerminalHostProtocol {
    public static let shared = try? GhosttyTerminalHost()

    nonisolated(unsafe) public private(set) var app: ghostty_app_t?
    nonisolated(unsafe) public private(set) var config: ghostty_config_t?
    public private(set) var configDiagnostics: [GhosttyTerminalConfigDiagnostic] = []

    private var sessions: [ObjectIdentifier: WeakGhosttyTerminalSession] = [:]
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    public init(loadDefaultTheme: Bool = true) throws {
        let argc = UInt(CommandLine.argc)
        let argv = CommandLine.unsafeArgv
        guard ghostty_init(argc, argv) == 0 else {
            throw GhosttyTerminalHostError.initializationFailed
        }

        guard let config = Self.loadConfig(loadDefaultTheme: loadDefaultTheme) else {
            throw GhosttyTerminalHostError.configurationFailed
        }

        var runtime = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: ghosttyKitWakeup,
            action_cb: ghosttyKitAction,
            read_clipboard_cb: ghosttyKitReadClipboard,
            confirm_read_clipboard_cb: ghosttyKitConfirmReadClipboard,
            write_clipboard_cb: ghosttyKitWriteClipboard,
            close_surface_cb: ghosttyKitCloseSurface
        )

        guard let app = ghostty_app_new(&runtime, config) else {
            ghostty_config_free(config)
            throw GhosttyTerminalHostError.appCreationFailed
        }

        self.config = config
        self.app = app
        self.configDiagnostics = Self.collectDiagnostics(from: config)
        beginObservingApplicationFocus()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
    }

    public func makeSession(configuration: GhosttyTerminalLaunchConfiguration = GhosttyTerminalLaunchConfiguration()) -> GhosttyTerminalSession {
        GhosttyTerminalSession(host: self, configuration: configuration)
    }

    public func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    public func setColorScheme(_ colorScheme: GhosttyTerminalColorScheme, appearance: NSAppearance? = nil) {
        guard let app, let scheme = resolvedColorScheme(colorScheme, appearance: appearance) else { return }
        ghostty_app_set_color_scheme(app, scheme)
        for session in liveSessions() {
            session.applyColorScheme(colorScheme, appearance: appearance)
        }
    }

    public func register(_ session: GhosttyTerminalSession) {
        sessions[ObjectIdentifier(session)] = WeakGhosttyTerminalSession(value: session)
    }

    public func unregister(_ session: GhosttyTerminalSession) {
        sessions.removeValue(forKey: ObjectIdentifier(session))
    }

    public func reloadConfig() {
        guard let newConfig = Self.loadConfig(loadDefaultTheme: true) else { return }
        let oldConfig = config
        config = newConfig
        configDiagnostics = Self.collectDiagnostics(from: newConfig)
        if let app {
            ghostty_app_update_config(app, newConfig)
        }
        for session in liveSessions() {
            session.updateConfig(newConfig)
        }
        if let oldConfig {
            ghostty_config_free(oldConfig)
        }
    }

    public func openConfig() {
        let path = ghostty_config_open_path()
        defer { ghostty_string_free(path) }
        guard let pointer = path.ptr, path.len > 0 else { return }
        let value = String(decoding: UnsafeBufferPointer(start: pointer, count: Int(path.len)).map(UInt8.init(bitPattern:)), as: UTF8.self)
        NSWorkspace.shared.open(URL(fileURLWithPath: value))
    }

    private func liveSessions() -> [GhosttyTerminalSession] {
        sessions = sessions.filter { $0.value.value != nil }
        return sessions.values.compactMap(\.value)
    }

    private func beginObservingApplicationFocus() {
        guard observers.isEmpty else { return }
        let notificationCenter = NotificationCenter.default
        observers.append(
            notificationCenter.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.setAppFocused(true)
                }
            }
        )
        observers.append(
            notificationCenter.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.setAppFocused(false)
                }
            }
        )
        setAppFocused(NSApp?.isActive == true)
    }

    private func setAppFocused(_ focused: Bool) {
        guard let app else { return }
        ghostty_app_set_focus(app, focused)
    }

    private static func loadConfig(loadDefaultTheme: Bool) -> ghostty_config_t? {
        guard let config = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(config)
        ghostty_config_load_recursive_files(config)
        if loadDefaultTheme, ghosttyConfigDeclaresTheme() == false, let overrideURL = try? GhosttyDefaultTheme.ensureOverride() {
            overrideURL.path.withCString { path in
                ghostty_config_load_file(config, path)
            }
        }
        ghostty_config_finalize(config)
        return config
    }

    private static func collectDiagnostics(from config: ghostty_config_t?) -> [GhosttyTerminalConfigDiagnostic] {
        guard let config else { return [] }
        let count = ghostty_config_diagnostics_count(config)
        return (0..<count).compactMap { index in
            let diagnostic = ghostty_config_get_diagnostic(config, index)
            guard let message = diagnostic.message else { return nil }
            return GhosttyTerminalConfigDiagnostic(message: String(cString: message))
        }
    }
}

@MainActor
public final class GhosttyTerminalSession {
    public let host: any GhosttyTerminalHostProtocol
    public let state = GhosttyTerminalState()
    public private(set) var configuration: GhosttyTerminalLaunchConfiguration
    nonisolated(unsafe) public private(set) var surface: ghostty_surface_t?
    public weak var view: GhosttyTerminalView?
    public var closeHandler: ((Bool) -> Void)?
    public var actionHandler: ((GhosttyTerminalAction) -> Void)?
    public var notificationHandler: ((GhosttyTerminalNotification) -> Void)?
    public var requestHandler: ((GhosttyTerminalRequest) -> Void)?
    nonisolated(unsafe) private var secureEventInputEnabled = false

    public init(
        host: any GhosttyTerminalHostProtocol = GhosttyTerminalHost.shared ?? (try! GhosttyTerminalHost()),
        configuration: GhosttyTerminalLaunchConfiguration = GhosttyTerminalLaunchConfiguration()
    ) {
        self.host = host
        self.configuration = configuration
        host.register(self)
        state.configDiagnostics = host.configDiagnostics
    }

    deinit {
        if secureEventInputEnabled {
            DisableSecureEventInput()
        }
        if let surface {
            ghostty_surface_free(surface)
        }
    }

    public func makeView(configuration viewConfiguration: GhosttyTerminalViewConfiguration = .default) -> GhosttyTerminalView {
        let view = GhosttyTerminalView(configuration: viewConfiguration)
        view.handlers = makeViewHandlers()
        attach(to: view)
        return view
    }

    public func attach(to view: GhosttyTerminalView) {
        self.view = view
        if view.handlers == nil {
            view.handlers = makeViewHandlers()
        }
        if surface == nil {
            createSurface(in: view)
        }
        updateContentScale()
        resize(to: view.bounds.size)
        setDisplayID(currentDisplayID(in: view))
        setFocused(view.window?.firstResponder === view)
        applyColorScheme(configuration.colorScheme, appearance: view.effectiveAppearance)
    }

    public func makeViewHandlers() -> GhosttyTerminalViewHandlers {
        GhosttyTerminalViewHandlers(
            attach: { [weak self] view in self?.attach(to: view) },
            resize: { [weak self] size in self?.resize(to: size) },
            updateContentScale: { [weak self] in self?.updateContentScale() },
            render: { [weak self] in self?.render() },
            focusChanged: { [weak self] focused in self?.setFocused(focused) },
            occlusionChanged: { [weak self] occluded in self?.setOccluded(occluded) },
            displayChanged: { [weak self] displayID in self?.setDisplayID(displayID) },
            appearanceChanged: { [weak self] appearance in
                guard let self else { return }
                self.applyColorScheme(self.configuration.colorScheme, appearance: appearance)
            },
            keyboardLayoutChanged: { [weak self] in self?.keyboardLayoutChanged() },
            primaryInteraction: {},
            keyDown: { [weak self] event, text in self?.sendKeyDown(event, text: text) },
            keyUp: { [weak self] event in self?.sendKeyUp(event) },
            insertText: { [weak self] text in self?.insertText(text) },
            markedTextChanged: { [weak self] text in self?.setMarkedText(text) },
            mouseButton: { [weak self] button, pressed, event in
                self?.sendMouseButton(button, pressed: pressed, event: event) ?? false
            },
            mousePosition: { [weak self] event in self?.sendMousePosition(event) },
            mouseExit: { [weak self] modifiers in self?.sendMouseExit(modifiers: modifiers) },
            scrollWheel: { [weak self] event in self?.sendScrollWheel(event) },
            copySelection: { [weak self] in self?.copySelection() },
            paste: { [weak self] text in self?.paste(text) },
            selectAll: { [weak self] in _ = self?.perform(action: "select_all") },
            hasSelection: { [weak self] in self?.hasSelection() == true },
            openHoveredLink: { [weak self] in self?.openHoveredLink() },
            copyHoveredLink: { [weak self] in self?.state.hoveredLinkURL },
            hasHoveredLink: { [weak self] in self?.state.hoveredLinkURL?.isEmpty == false },
            openConfig: { [weak self] in self?.host.openConfig() },
            performCommand: { [weak self] selector in self?.performCommand(selector) == true }
        )
    }

    public func resize(to size: CGSize) {
        guard let surface else { return }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        let scale = view?.window?.backingScaleFactor ?? view?.window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        ghostty_surface_set_size(surface, UInt32(ceil(size.width * scale)), UInt32(ceil(size.height * scale)))
        ghostty_surface_refresh(surface)
    }

    public func updateContentScale() {
        guard let surface else { return }
        let scale = Double(view?.window?.backingScaleFactor ?? view?.window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        guard scale.isFinite, scale > 0 else { return }
        ghostty_surface_set_content_scale(surface, scale, scale)
    }

    public func render() {
        guard let surface else { return }
        ghostty_surface_draw(surface)
    }

    public func requestRender() {
        if let view {
            view.requestRender()
        } else {
            render()
        }
    }

    public func setFocused(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    public func setOccluded(_ occluded: Bool) {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, !occluded)
    }

    public func setDisplayID(_ displayID: CGDirectDisplayID?) {
        guard let surface, let displayID else { return }
        ghostty_surface_set_display_id(surface, displayID)
    }

    public func keyboardLayoutChanged() {
        guard let app = host.app else { return }
        ghostty_app_keyboard_changed(app)
    }

    public func sendKeyDown(_ event: NSEvent, text: String?) {
        sendKeyEvent(event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS, text: text)
        ghostty_surface_refresh(surface)
    }

    public func sendKeyUp(_ event: NSEvent) {
        sendKeyEvent(event, action: GHOSTTY_ACTION_RELEASE, text: nil)
        ghostty_surface_refresh(surface)
    }

    public func insertText(_ text: String) {
        guard let surface, !text.isEmpty else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(text.utf8.count))
        }
        ghostty_surface_refresh(surface)
    }

    public func setMarkedText(_ text: String?) {
        guard let surface else { return }
        guard let text else {
            ghostty_surface_preedit(surface, nil, 0)
            ghostty_surface_refresh(surface)
            return
        }
        text.withCString { ptr in
            ghostty_surface_preedit(surface, ptr, UInt(text.utf8.count))
        }
        ghostty_surface_refresh(surface)
    }

    public func sendMouseButton(_ button: GhosttyTerminalMouseButton, pressed: Bool, event: NSEvent) -> Bool {
        guard let surface else { return false }
        let state: ghostty_input_mouse_state_e = pressed ? GHOSTTY_MOUSE_PRESS : GHOSTTY_MOUSE_RELEASE
        return ghostty_surface_mouse_button(surface, state, translate(button), translateModifiers(event.modifierFlags))
    }

    public func sendMousePosition(_ event: NSEvent) {
        guard let surface, let view else { return }
        let position = view.convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(
            surface,
            position.x,
            view.bounds.height - position.y,
            translateModifiers(event.modifierFlags)
        )
    }

    public func sendMouseExit(modifiers: NSEvent.ModifierFlags) {
        guard let surface else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, translateModifiers(modifiers))
    }

    public func sendScrollWheel(_ event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, translateScrollModifiers(event))
    }

    public func copySelection() -> String? {
        guard let surface else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }

    public func hasSelection() -> Bool {
        guard let surface else { return false }
        return ghostty_surface_has_selection(surface)
    }

    public func paste(_ text: String) {
        insertText(text)
    }

    public func openHoveredLink() {
        guard let url = state.hoveredLinkURL, let value = URL(string: url) else { return }
        NSWorkspace.shared.open(value)
    }

    public func perform(action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    public func applyColorScheme(_ colorScheme: GhosttyTerminalColorScheme, appearance: NSAppearance? = nil) {
        configuration.colorScheme = colorScheme
        guard let surface, let scheme = resolvedColorScheme(colorScheme, appearance: appearance ?? view?.effectiveAppearance) else { return }
        ghostty_surface_set_color_scheme(surface, scheme)
        ghostty_surface_refresh(surface)
    }

    public func updateConfig(_ config: ghostty_config_t) {
        guard let surface else { return }
        ghostty_surface_update_config(surface, config)
        state.configDiagnostics = host.configDiagnostics
        applyColorScheme(configuration.colorScheme, appearance: view?.effectiveAppearance)
    }

    @discardableResult
    public func handle(action: GhosttyTerminalAction) -> Bool {
        state.lastAction = action
        let handled: Bool
        switch action {
        case .setTitle(let title):
            state.title = title
            handled = true
        case .setTabTitle(let title):
            state.tabTitle = title
            handled = true
        case .workingDirectory(let workingDirectory):
            state.workingDirectory = workingDirectory
            handled = true
        case .hoveredLink(let url):
            state.hoveredLinkURL = url
            handled = true
        case .rendererHealth(let healthy):
            state.rendererHealthy = healthy
            handled = true
        case .readonly(let enabled):
            state.isReadonly = enabled
            handled = true
        case .render:
            requestRender()
            handled = true
        case .openConfig:
            host.openConfig()
            handled = true
        case .reloadConfig:
            host.reloadConfig()
            handled = true
        case .ringBell:
            NSSound.beep()
            handled = true
        case .copyTitleToClipboard:
            let title = (state.title ?? state.tabTitle)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title, !title.isEmpty {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(title, forType: .string)
                handled = true
            } else {
                handled = false
            }
        case .mouseShape(let shape):
            view?.applyCursor(for: shape)
            handled = true
        case .mouseVisibility(let hidden):
            state.isMouseHidden = hidden
            view?.setCursorHidden(hidden)
            handled = true
        case .startSearch(let query):
            state.searchQuery = query
            handled = true
        case .endSearch:
            state.searchQuery = ""
            state.searchTotal = 0
            state.searchSelected = nil
            handled = true
        case .searchTotal(let total):
            state.searchTotal = total
            handled = true
        case .searchSelected(let selected):
            state.searchSelected = selected
            handled = true
        case .progress(let progressState, let percent):
            state.progressState = progressState
            state.progressPercent = percent
            handled = true
        case .childExited(let exitCode):
            state.childExitCode = exitCode
            handled = true
        case .commandFinished(let exitCode, let durationNanoseconds):
            state.lastCommandExitCode = exitCode
            state.lastCommandDurationNanoseconds = durationNanoseconds
            handled = true
        case .secureInput(let secureInputState):
            state.secureInputState = secureInputState
            if configuration.bridgeSecureInput {
                switch secureInputState {
                case .active:
                    EnableSecureEventInput()
                    secureEventInputEnabled = true
                case .inactive:
                    DisableSecureEventInput()
                    secureEventInputEnabled = false
                }
            }
            handled = true
        case .request(let request):
            requestHandler?(request)
            handled = true
        case .sizeLimit(let limits):
            state.sizeLimits = limits
            handled = true
        case .initialSize(let size):
            state.initialSize = size
            handled = true
        case .cellSize(let size):
            state.cellSize = size
            handled = true
        case .openURL(let url):
            if let url, let value = URL(string: url) {
                NSWorkspace.shared.open(value)
                handled = true
            } else {
                handled = false
            }
        case .desktopNotification:
            if case let .desktopNotification(title, body) = action {
                let notification = GhosttyTerminalNotification(title: title, body: body)
                state.lastNotification = notification
                notificationHandler?(notification)
            }
            handled = true
        case .unsupported:
            handled = false
        }
        actionHandler?(action)
        return handled
    }

    fileprivate func handleCloseRequest(processAlive: Bool) {
        closeHandler?(processAlive)
    }

    private func createSurface(in view: NSView) {
        guard let app = host.app else { return }
        if let scheme = resolvedColorScheme(configuration.colorScheme, appearance: view.effectiveAppearance) {
            ghostty_app_set_color_scheme(app, scheme)
        }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(view).toOpaque()))
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        config.font_size = configuration.fontSize
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        configuration.workingDirectory.withOptionalCString { workingDirectory in
            config.working_directory = workingDirectory
            configuration.command.withOptionalCString { command in
                config.command = command
                surface = withEnvironmentVariables(configuration.environment, config: config) { configured in
                    var configured = configured
                    return ghostty_surface_new(app, &configured)
                }
            }
        }

        if let surface, let scheme = resolvedColorScheme(configuration.colorScheme, appearance: view.effectiveAppearance) {
            ghostty_surface_set_color_scheme(surface, scheme)
        }
    }

    private func performCommand(_ selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveToBeginningOfDocument(_:)):
            return perform(action: "scroll_to_top")
        case #selector(NSResponder.moveToEndOfDocument(_:)):
            return perform(action: "scroll_to_bottom")
        default:
            return false
        }
    }

    private func sendKeyEvent(_ event: NSEvent, action: ghostty_input_action_e, text: String?) {
        guard let surface else { return }
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(event.keyCode)
        key.mods = translateModifiers(event.modifierFlags)
        key.consumed_mods = ghostty_surface_key_translation_mods(surface, key.mods)
        key.composing = false
        key.unshifted_codepoint = unshiftedCodepoint(for: event.charactersIgnoringModifiers)

        if let text, !text.isEmpty {
            text.withCString { ptr in
                key.text = ptr
                _ = ghostty_surface_key(surface, key)
            }
        } else {
            key.text = nil
            _ = ghostty_surface_key(surface, key)
        }
    }

    private func withEnvironmentVariables<T>(
        _ variables: [String: String],
        config: ghostty_surface_config_s,
        body: (ghostty_surface_config_s) -> T
    ) -> T {
        let keys = Array(variables.keys)
        let values = keys.map { variables[$0] ?? "" }
        return keys.withCStrings { keyPointers in
            values.withCStrings { valuePointers in
                var envVars: [ghostty_env_var_s] = []
                envVars.reserveCapacity(keys.count)
                for index in keys.indices {
                    envVars.append(.init(key: keyPointers[index], value: valuePointers[index]))
                }
                let envVarCount = envVars.count
                return envVars.withUnsafeMutableBufferPointer { buffer in
                    var configured = config
                    configured.env_vars = buffer.baseAddress
                    configured.env_var_count = envVarCount
                    return body(configured)
                }
            }
        }
    }

    private func translate(_ button: GhosttyTerminalMouseButton) -> ghostty_input_mouse_button_e {
        switch button {
        case .left:
            return GHOSTTY_MOUSE_LEFT
        case .right:
            return GHOSTTY_MOUSE_RIGHT
        case .middle:
            return GHOSTTY_MOUSE_MIDDLE
        case .other(let number):
            switch number {
            case 3: return GHOSTTY_MOUSE_FOUR
            case 4: return GHOSTTY_MOUSE_FIVE
            case 5: return GHOSTTY_MOUSE_SIX
            case 6: return GHOSTTY_MOUSE_SEVEN
            case 7: return GHOSTTY_MOUSE_EIGHT
            case 8: return GHOSTTY_MOUSE_NINE
            case 9: return GHOSTTY_MOUSE_TEN
            case 10: return GHOSTTY_MOUSE_ELEVEN
            default: return GHOSTTY_MOUSE_UNKNOWN
            }
        }
    }

    private func translateModifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var raw = UInt32(GHOSTTY_MODS_NONE.rawValue)
        if flags.contains(.shift) { raw |= UInt32(GHOSTTY_MODS_SHIFT.rawValue) }
        if flags.contains(.control) { raw |= UInt32(GHOSTTY_MODS_CTRL.rawValue) }
        if flags.contains(.option) { raw |= UInt32(GHOSTTY_MODS_ALT.rawValue) }
        if flags.contains(.command) { raw |= UInt32(GHOSTTY_MODS_SUPER.rawValue) }
        if flags.contains(.capsLock) { raw |= UInt32(GHOSTTY_MODS_CAPS.rawValue) }
        return ghostty_input_mods_e(raw)
    }

    private func translateScrollModifiers(_ event: NSEvent) -> ghostty_input_scroll_mods_t {
        var value = ghostty_input_scroll_mods_t(translateModifiers(event.modifierFlags).rawValue)
        switch event.momentumPhase {
        case .began:
            value |= ghostty_input_scroll_mods_t(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue << 16)
        case .changed:
            value |= ghostty_input_scroll_mods_t(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue << 16)
        case .ended:
            value |= ghostty_input_scroll_mods_t(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue << 16)
        case .cancelled:
            value |= ghostty_input_scroll_mods_t(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue << 16)
        case .mayBegin:
            value |= ghostty_input_scroll_mods_t(GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN.rawValue << 16)
        default:
            break
        }
        if event.hasPreciseScrollingDeltas {
            value |= 1 << 24
        }
        return value
    }

    private func currentDisplayID(in view: NSView) -> CGDirectDisplayID? {
        guard let screenNumber = view.window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}

private struct WeakGhosttyTerminalSession {
    weak var value: GhosttyTerminalSession?
}

@MainActor
private func resolvedColorScheme(_ colorScheme: GhosttyTerminalColorScheme, appearance: NSAppearance?) -> ghostty_color_scheme_e? {
    switch colorScheme {
    case .light:
        return GHOSTTY_COLOR_SCHEME_LIGHT
    case .dark:
        return GHOSTTY_COLOR_SCHEME_DARK
    case .system:
        let match = (appearance ?? NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua))?.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
    }
}

private func unshiftedCodepoint(for characters: String?) -> UInt32 {
    guard let scalar = characters?.unicodeScalars.first else { return 0 }
    return scalar.value
}

private func ghosttyConfigDeclaresTheme() -> Bool {
    let path = ghostty_config_open_path()
    defer { ghostty_string_free(path) }
    guard let pointer = path.ptr, path.len > 0 else { return false }
    let configURL = URL(fileURLWithPath: String(decoding: UnsafeBufferPointer(start: pointer, count: Int(path.len)).map(UInt8.init(bitPattern:)), as: UTF8.self))
    return ghosttyConfigDirectoryDeclaresTheme(configURL: configURL)
}

private func ghosttyConfigDirectoryDeclaresTheme(configURL: URL, fileManager: FileManager = .default) -> Bool {
    let directoryURL = configURL.deletingLastPathComponent()
    guard let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey]) else {
        return false
    }

    for case let fileURL as URL in enumerator {
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { continue }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
        if ghosttyConfigTextDeclaresTheme(text) {
            return true
        }
    }
    return false
}

private func ghosttyConfigTextDeclaresTheme(_ text: String) -> Bool {
    text.split(whereSeparator: \.isNewline).contains { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("theme") && trimmed.dropFirst("theme".count).trimmingCharacters(in: .whitespaces).hasPrefix("=")
    }
}

private extension Optional where Wrapped == String {
    func withOptionalCString<T>(_ body: (UnsafePointer<CChar>?) -> T) -> T {
        switch self {
        case .none:
            return body(nil)
        case .some(let value):
            return value.withCString(body)
        }
    }
}

private extension Collection where Element == String {
    func withCStrings<T>(_ body: ([UnsafePointer<CChar>?]) -> T) -> T {
        var strings = Array(self)
        return strings.withUnsafeMutableBufferPointer { buffer in
            var pointers: [UnsafePointer<CChar>?] = []
            pointers.reserveCapacity(buffer.count)
            func appendPointer(at index: Int) -> T {
                if index == buffer.count {
                    return body(pointers)
                }
                return buffer[index].withCString { pointer in
                    pointers.append(pointer)
                    return appendPointer(at: index + 1)
                }
            }
            return appendPointer(at: 0)
        }
    }
}

private func ghosttyKitWakeup(_ userdata: UnsafeMutableRawPointer?) {
    guard let host = ghosttyKitHost(from: userdata) else { return }
    Task { @MainActor in
        host.tick()
    }
}

private func ghosttyKitAction(_ app: ghostty_app_t?, _ target: ghostty_target_s, _ action: ghostty_action_s) -> Bool {
    guard let app else { return false }
    guard let host = ghosttyKitHost(from: ghostty_app_userdata(app)) else { return false }
    let terminalAction = ghosttyTerminalAction(from: action)
    Task { @MainActor in
        switch target.tag {
        case GHOSTTY_TARGET_SURFACE:
            if let session = ghosttyKitSession(for: target.target.surface) {
                _ = session.handle(action: terminalAction)
            }
        case GHOSTTY_TARGET_APP:
            _ = host.handle(action: terminalAction)
        default:
            host.tick()
        }
    }
    return true
}

private func ghosttyKitReadClipboard(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) -> Bool {
    guard location != GHOSTTY_CLIPBOARD_SELECTION else { return false }
    guard let runtime = ghosttyKitSession(from: userdata), let surface = runtime.surface else { return false }
    guard let text = NSPasteboard.general.string(forType: .string) else { return false }
    text.withCString { ptr in
        ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
    }
    return true
}

private func ghosttyKitConfirmReadClipboard(
    _ userdata: UnsafeMutableRawPointer?,
    _ string: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
}

private func ghosttyKitWriteClipboard(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ len: Int,
    _ confirm: Bool
) {
    guard location != GHOSTTY_CLIPBOARD_SELECTION else { return }
    guard let content, len > 0 else { return }
    let items = UnsafeBufferPointer(start: content, count: len)
    let joined = items.compactMap { item -> String? in
        guard
            let mime = item.mime,
            String(cString: mime) == "text/plain",
            let value = item.data
        else {
            return nil
        }
        return String(cString: value)
    }.joined(separator: "\n")
    guard !joined.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(joined, forType: .string)
}

private func ghosttyKitCloseSurface(_ userdata: UnsafeMutableRawPointer?, _ processAlive: Bool) {
    guard let runtime = ghosttyKitSession(from: userdata) else { return }
    Task { @MainActor in
        runtime.handleCloseRequest(processAlive: processAlive)
    }
}

private func ghosttyKitHost(from pointer: UnsafeMutableRawPointer?) -> GhosttyTerminalHost? {
    guard let pointer else { return nil }
    return Unmanaged<GhosttyTerminalHost>.fromOpaque(pointer).takeUnretainedValue()
}

private func ghosttyKitSession(for surface: ghostty_surface_t?) -> GhosttyTerminalSession? {
    guard let surface, let userdata = ghostty_surface_userdata(surface) else { return nil }
    return ghosttyKitSession(from: userdata)
}

private func ghosttyKitSession(from pointer: UnsafeMutableRawPointer?) -> GhosttyTerminalSession? {
    guard let pointer else { return nil }
    return Unmanaged<GhosttyTerminalSession>.fromOpaque(pointer).takeUnretainedValue()
}

@MainActor
private extension GhosttyTerminalHost {
    @discardableResult
    func handle(action: GhosttyTerminalAction) -> Bool {
        switch action {
        case .render:
            for session in liveSessions() {
                session.requestRender()
            }
            return true
        case .openConfig:
            openConfig()
            return true
        case .reloadConfig:
            reloadConfig()
            return true
        case .ringBell:
            NSSound.beep()
            return true
        default:
            return false
        }
    }
}

private func ghosttyTerminalAction(from action: ghostty_action_s) -> GhosttyTerminalAction {
    switch action.tag {
    case GHOSTTY_ACTION_SET_TITLE:
        return .setTitle(string(from: action.action.set_title.title))
    case GHOSTTY_ACTION_SET_TAB_TITLE:
        return .setTabTitle(string(from: action.action.set_tab_title.title))
    case GHOSTTY_ACTION_PWD:
        return .workingDirectory(string(from: action.action.pwd.pwd))
    case GHOSTTY_ACTION_MOUSE_OVER_LINK:
        return .hoveredLink(string(from: action.action.mouse_over_link.url, length: Int(action.action.mouse_over_link.len)))
    case GHOSTTY_ACTION_OPEN_URL:
        return .openURL(string(from: action.action.open_url.url, length: Int(action.action.open_url.len)))
    case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
        return .desktopNotification(
            title: string(from: action.action.desktop_notification.title) ?? "Ghostty",
            body: string(from: action.action.desktop_notification.body) ?? ""
        )
    case GHOSTTY_ACTION_RENDERER_HEALTH:
        return .rendererHealth(action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_HEALTHY)
    case GHOSTTY_ACTION_READONLY:
        return .readonly(action.action.readonly == GHOSTTY_READONLY_ON)
    case GHOSTTY_ACTION_RENDER:
        return .render
    case GHOSTTY_ACTION_OPEN_CONFIG:
        return .openConfig
    case GHOSTTY_ACTION_RELOAD_CONFIG:
        return .reloadConfig
    case GHOSTTY_ACTION_RING_BELL:
        return .ringBell
    case GHOSTTY_ACTION_START_SEARCH:
        return .startSearch(string(from: action.action.start_search.needle) ?? "")
    case GHOSTTY_ACTION_END_SEARCH:
        return .endSearch
    case GHOSTTY_ACTION_SEARCH_TOTAL:
        return .searchTotal(Int(action.action.search_total.total))
    case GHOSTTY_ACTION_SEARCH_SELECTED:
        return .searchSelected(action.action.search_selected.selected >= 0 ? Int(action.action.search_selected.selected) : nil)
    case GHOSTTY_ACTION_PROGRESS_REPORT:
        let progressState: GhosttyTerminalProgressState = switch action.action.progress_report.state {
        case GHOSTTY_PROGRESS_STATE_SET:
            .active
        case GHOSTTY_PROGRESS_STATE_ERROR:
            .error
        case GHOSTTY_PROGRESS_STATE_INDETERMINATE:
            .indeterminate
        case GHOSTTY_PROGRESS_STATE_PAUSE:
            .paused
        default:
            .none
        }
        return .progress(
            state: progressState,
            percent: action.action.progress_report.progress >= 0 ? Int(action.action.progress_report.progress) : nil
        )
    case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
        return .childExited(exitCode: Int(action.action.child_exited.exit_code))
    case GHOSTTY_ACTION_COMMAND_FINISHED:
        return .commandFinished(
            exitCode: action.action.command_finished.exit_code >= 0 ? Int(action.action.command_finished.exit_code) : nil,
            durationNanoseconds: action.action.command_finished.duration
        )
    case GHOSTTY_ACTION_SECURE_INPUT:
        switch action.action.secure_input {
        case GHOSTTY_SECURE_INPUT_ON:
            return .secureInput(.active)
        case GHOSTTY_SECURE_INPUT_OFF:
            return .secureInput(.inactive)
        case GHOSTTY_SECURE_INPUT_TOGGLE:
            return .unsupported("secure_input_toggle")
        default:
            return .unsupported("secure_input")
        }
    case GHOSTTY_ACTION_NEW_WINDOW:
        return .request(.newWindow)
    case GHOSTTY_ACTION_CLOSE_WINDOW:
        return .request(.closeWindow)
    case GHOSTTY_ACTION_NEW_TAB:
        return .request(.newTab)
    case GHOSTTY_ACTION_CLOSE_TAB:
        return .request(.closeTab)
    case GHOSTTY_ACTION_NEW_SPLIT:
        return .request(.newSplit(splitDirection(from: action.action.new_split)))
    case GHOSTTY_ACTION_EQUALIZE_SPLITS:
        return .request(.equalizeSplits)
    case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
        return .request(.toggleSplitZoom)
    case GHOSTTY_ACTION_TOGGLE_COMMAND_PALETTE:
        return .request(.toggleCommandPalette)
    case GHOSTTY_ACTION_SIZE_LIMIT:
        return .sizeLimit(.init(
            minimumWidth: Int(action.action.size_limit.min_width),
            minimumHeight: Int(action.action.size_limit.min_height),
            maximumWidth: action.action.size_limit.max_width > 0 ? Int(action.action.size_limit.max_width) : nil,
            maximumHeight: action.action.size_limit.max_height > 0 ? Int(action.action.size_limit.max_height) : nil
        ))
    case GHOSTTY_ACTION_INITIAL_SIZE:
        return .initialSize(.init(
            width: Int(action.action.initial_size.width),
            height: Int(action.action.initial_size.height)
        ))
    case GHOSTTY_ACTION_CELL_SIZE:
        return .cellSize(.init(
            width: Int(action.action.cell_size.width),
            height: Int(action.action.cell_size.height)
        ))
    case GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD:
        return .copyTitleToClipboard
    case GHOSTTY_ACTION_MOUSE_SHAPE:
        return .mouseShape(action.action.mouse_shape)
    case GHOSTTY_ACTION_MOUSE_VISIBILITY:
        return .mouseVisibility(hidden: action.action.mouse_visibility == GHOSTTY_MOUSE_HIDDEN)
    default:
        return .unsupported(ghosttyActionName(action.tag))
    }
}

private func string(from pointer: UnsafePointer<CChar>?) -> String? {
    guard let pointer else { return nil }
    return String(cString: pointer)
}

private func string(from pointer: UnsafePointer<CChar>?, length: Int) -> String? {
    guard let pointer, length > 0 else { return nil }
    let buffer = UnsafeBufferPointer(start: pointer, count: length)
    return String(decoding: buffer.map(UInt8.init(bitPattern:)), as: UTF8.self)
}

private func splitDirection(from direction: ghostty_action_split_direction_e) -> GhosttyTerminalSplitDirection {
    switch direction {
    case GHOSTTY_SPLIT_DIRECTION_LEFT:
        return .left
    case GHOSTTY_SPLIT_DIRECTION_UP:
        return .up
    case GHOSTTY_SPLIT_DIRECTION_DOWN:
        return .down
    default:
        return .right
    }
}

private func ghosttyActionName(_ tag: ghostty_action_tag_e) -> String {
    switch tag {
    case GHOSTTY_ACTION_NEW_WINDOW: return "new_window"
    case GHOSTTY_ACTION_NEW_TAB: return "new_tab"
    case GHOSTTY_ACTION_CLOSE_TAB: return "close_tab"
    case GHOSTTY_ACTION_NEW_SPLIT: return "new_split"
    case GHOSTTY_ACTION_RENDER: return "render"
    case GHOSTTY_ACTION_DESKTOP_NOTIFICATION: return "desktop_notification"
    case GHOSTTY_ACTION_SET_TITLE: return "set_title"
    case GHOSTTY_ACTION_SET_TAB_TITLE: return "set_tab_title"
    case GHOSTTY_ACTION_PWD: return "pwd"
    case GHOSTTY_ACTION_MOUSE_SHAPE: return "mouse_shape"
    case GHOSTTY_ACTION_MOUSE_VISIBILITY: return "mouse_visibility"
    case GHOSTTY_ACTION_MOUSE_OVER_LINK: return "mouse_over_link"
    case GHOSTTY_ACTION_OPEN_CONFIG: return "open_config"
    case GHOSTTY_ACTION_RELOAD_CONFIG: return "reload_config"
    case GHOSTTY_ACTION_RING_BELL: return "ring_bell"
    case GHOSTTY_ACTION_OPEN_URL: return "open_url"
    case GHOSTTY_ACTION_READONLY: return "readonly"
    case GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD: return "copy_title_to_clipboard"
    default: return "unknown"
    }
}
