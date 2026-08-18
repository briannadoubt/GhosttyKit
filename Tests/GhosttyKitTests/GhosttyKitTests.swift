import XCTest
import GhosttyKit
import AppKit

final class GhosttyKitTests: XCTestCase {
    func testGhosttyInfoExposesAVersion() {
        let info = ghostty_info()

        XCTAssertNotNil(info.version)
        XCTAssertGreaterThan(info.version_len, 0)

        guard let versionPointer = info.version else {
            return XCTFail("ghostty_info() returned a nil version pointer")
        }

        let versionBytes = UnsafeBufferPointer(start: versionPointer, count: Int(info.version_len))
        let version = String(decoding: versionBytes.map(UInt8.init(bitPattern:)), as: UTF8.self)

        XCTAssertFalse(version.isEmpty)
    }

    @MainActor
    func testTerminalViewSuppressesAppKitTextCommandsHandledByGhosttyKeyEvents() {
        XCTAssertTrue(GhosttyTerminalView.shouldSuppressSystemTextInputCommand(#selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(GhosttyTerminalView.shouldSuppressSystemTextInputCommand(#selector(NSResponder.deleteBackward(_:))))
        XCTAssertTrue(GhosttyTerminalView.shouldSuppressSystemTextInputCommand(#selector(NSResponder.deleteForward(_:))))
        XCTAssertTrue(GhosttyTerminalView.shouldSuppressSystemTextInputCommand(#selector(NSResponder.moveLeft(_:))))
        XCTAssertTrue(GhosttyTerminalView.shouldSuppressSystemTextInputCommand(#selector(NSResponder.pageDown(_:))))

        XCTAssertFalse(GhosttyTerminalView.shouldSuppressSystemTextInputCommand(#selector(NSResponder.selectAll(_:))))
    }

    @MainActor
    func testTerminalViewForwardsCopyAndPasteThroughResponderChain() {
        let view = GhosttyTerminalView()
        let handlers = RecordingTerminalViewHandlers()
        handlers.selectionText = "selected text"
        view.handlers = handlers.makeHandlers()

        NSPasteboard.general.clearContents()
        XCTAssertTrue(view.tryToPerform(#selector(GhosttyTerminalView.copy(_:)), with: nil))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "selected text")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("pasted text", forType: .string)
        XCTAssertTrue(view.tryToPerform(#selector(GhosttyTerminalView.paste(_:)), with: nil))
        XCTAssertEqual(handlers.pastedText, "pasted text")
    }

    @MainActor
    func testTerminalViewContextMenuIncludesHoveredLinkAndConfigActions() {
        let view = GhosttyTerminalView()
        let handlers = RecordingTerminalViewHandlers()
        handlers.hoveredLinkURL = "https://example.com"
        view.handlers = handlers.makeHandlers()

        let titles = view.makeContextMenu()?.items.map(\.title) ?? []

        XCTAssertEqual(
            titles,
            ["Copy", "Paste", "Select All", "", "Open Hovered Link", "Copy Hovered Link", "", "Open Terminal Config"]
        )
    }

    @MainActor
    func testTerminalViewHoveredLinkActionsUseHandlersAndPasteboard() {
        let view = GhosttyTerminalView()
        let handlers = RecordingTerminalViewHandlers()
        handlers.hoveredLinkURL = "https://example.com"
        view.handlers = handlers.makeHandlers()

        XCTAssertTrue(view.tryToPerform(#selector(GhosttyTerminalView.openHoveredLink(_:)), with: nil))
        XCTAssertEqual(handlers.openedHoveredLinkCount, 1)

        NSPasteboard.general.clearContents()
        XCTAssertTrue(view.tryToPerform(#selector(GhosttyTerminalView.copyHoveredLink(_:)), with: nil))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "https://example.com")
    }

    @MainActor
    func testTerminalSessionRecordsStateFromGhosttyActions() {
        let session = GhosttyTerminalSession(host: RecordingGhosttyHost(), configuration: .init())

        session.handle(action: .setTitle("Project Shell"))
        session.handle(action: .workingDirectory("/tmp/project"))
        session.handle(action: .hoveredLink("https://example.com"))
        session.handle(action: .readonly(true))

        XCTAssertEqual(session.state.title, "Project Shell")
        XCTAssertEqual(session.state.workingDirectory, "/tmp/project")
        XCTAssertEqual(session.state.hoveredLinkURL, "https://example.com")
        XCTAssertTrue(session.state.isReadonly)
    }

    @MainActor
    func testTerminalSessionRecordsSearchProgressAndProcessActions() {
        let session = GhosttyTerminalSession(host: RecordingGhosttyHost(), configuration: .init())

        session.handle(action: .startSearch("needle"))
        session.handle(action: .searchTotal(4))
        session.handle(action: .searchSelected(2))
        session.handle(action: .progress(state: .active, percent: 42))
        session.handle(action: .commandFinished(exitCode: 0, durationNanoseconds: 1_500))
        session.handle(action: .childExited(exitCode: 9))

        XCTAssertEqual(session.state.searchQuery, "needle")
        XCTAssertEqual(session.state.searchTotal, 4)
        XCTAssertEqual(session.state.searchSelected, 2)
        XCTAssertEqual(session.state.progressState, .active)
        XCTAssertEqual(session.state.progressPercent, 42)
        XCTAssertEqual(session.state.lastCommandExitCode, 0)
        XCTAssertEqual(session.state.lastCommandDurationNanoseconds, 1_500)
        XCTAssertEqual(session.state.childExitCode, 9)
    }

    @MainActor
    func testTerminalSessionBridgesNotificationsSecureInputAndRequests() {
        let session = GhosttyTerminalSession(host: RecordingGhosttyHost(), configuration: .init(bridgeSecureInput: false))
        var notifications: [GhosttyTerminalNotification] = []
        var requests: [GhosttyTerminalRequest] = []
        session.notificationHandler = { notifications.append($0) }
        session.requestHandler = { requests.append($0) }

        session.handle(action: .desktopNotification(title: "Build", body: "Done"))
        session.handle(action: .secureInput(.active))
        session.handle(action: .request(.newSplit(.right)))
        session.handle(action: .request(.newTab))

        XCTAssertEqual(notifications, [GhosttyTerminalNotification(title: "Build", body: "Done")])
        XCTAssertEqual(session.state.lastNotification, GhosttyTerminalNotification(title: "Build", body: "Done"))
        XCTAssertEqual(session.state.secureInputState, .active)
        XCTAssertEqual(requests, [.newSplit(.right), .newTab])
    }

    @MainActor
    func testTerminalSessionRecordsSizingHints() {
        let session = GhosttyTerminalSession(host: RecordingGhosttyHost(), configuration: .init())

        session.handle(action: .sizeLimit(.init(minimumWidth: 20, minimumHeight: 10, maximumWidth: 200, maximumHeight: nil)))
        session.handle(action: .initialSize(.init(width: 120, height: 40)))
        session.handle(action: .cellSize(.init(width: 11, height: 22)))

        XCTAssertEqual(session.state.sizeLimits?.minimumWidth, 20)
        XCTAssertEqual(session.state.sizeLimits?.maximumHeight, nil)
        XCTAssertEqual(session.state.initialSize, GhosttyTerminalGridSize(width: 120, height: 40))
        XCTAssertEqual(session.state.cellSize, GhosttyTerminalGridSize(width: 11, height: 22))
    }

    @MainActor
    func testTerminalSessionCopiesHostConfigDiagnostics() {
        let host = RecordingGhosttyHost()
        host.configDiagnostics = [GhosttyTerminalConfigDiagnostic(message: "bad config")]
        let session = GhosttyTerminalSession(host: host, configuration: .init())

        XCTAssertEqual(session.state.configDiagnostics, [GhosttyTerminalConfigDiagnostic(message: "bad config")])
    }

    @MainActor
    func testTerminalSessionDisposalIsExplicitAndIdempotent() {
        let host = RecordingGhosttyHost()
        let session = GhosttyTerminalSession(host: host, configuration: .init())
        let view = session.makeView()

        XCTAssertEqual(host.registerCount, 1)
        XCTAssertNotNil(view.handlers)

        session.dispose()
        session.dispose()

        XCTAssertNil(session.surface)
        XCTAssertNil(session.view)
        XCTAssertNil(view.handlers)
        XCTAssertEqual(host.unregisterCount, 1)
    }

    func testDefaultThemeOverrideWritesLightDarkThemePair() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghosttykit-theme-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let overrideURL = try GhosttyDefaultTheme.ensureOverride(
            baseDirectoryURL: directoryURL,
            applicationName: "TestApp"
        )

        let override = try String(contentsOf: overrideURL, encoding: .utf8)
        XCTAssertTrue(override.contains("theme = \"light:"))
        XCTAssertTrue(override.contains("ghosttykit-default-light.ghostty"))
        XCTAssertTrue(override.contains("ghosttykit-default-dark.ghostty"))

        let lightTheme = try String(
            contentsOf: overrideURL.deletingLastPathComponent().appendingPathComponent("ghosttykit-default-light.ghostty"),
            encoding: .utf8
        )
        let darkTheme = try String(
            contentsOf: overrideURL.deletingLastPathComponent().appendingPathComponent("ghosttykit-default-dark.ghostty"),
            encoding: .utf8
        )
        XCTAssertTrue(lightTheme.contains("background = faf4ed"))
        XCTAssertTrue(darkTheme.contains("background = 191724"))
    }
}

@MainActor
private final class RecordingTerminalViewHandlers {
    var selectionText: String?
    var pastedText: String?
    var hoveredLinkURL: String?
    var openedHoveredLinkCount = 0

    func makeHandlers() -> GhosttyTerminalViewHandlers {
        GhosttyTerminalViewHandlers(
            attach: { _ in },
            resize: { _ in },
            updateContentScale: {},
            render: {},
            focusChanged: { _ in },
            occlusionChanged: { _ in },
            displayChanged: { _ in },
            appearanceChanged: { _ in },
            keyboardLayoutChanged: {},
            primaryInteraction: {},
            keyDown: { _, _ in },
            keyUp: { _ in },
            insertText: { _ in },
            markedTextChanged: { _ in },
            mouseButton: { _, _, _ in false },
            mousePosition: { _ in },
            mouseExit: { _ in },
            scrollWheel: { _ in },
            copySelection: { self.selectionText },
            paste: { self.pastedText = $0 },
            selectAll: {},
            hasSelection: { self.selectionText?.isEmpty == false },
            openHoveredLink: { self.openedHoveredLinkCount += 1 },
            copyHoveredLink: { self.hoveredLinkURL },
            hasHoveredLink: { self.hoveredLinkURL?.isEmpty == false },
            openConfig: {},
            performCommand: { _ in false }
        )
    }
}

@MainActor
private final class RecordingGhosttyHost: GhosttyTerminalHostProtocol {
    var app: ghostty_app_t? { nil }
    var config: ghostty_config_t? { nil }
    var configDiagnostics: [GhosttyTerminalConfigDiagnostic] = []
    var registerCount = 0
    var unregisterCount = 0

    func register(_ session: GhosttyTerminalSession) { registerCount += 1 }
    func unregister(_ session: GhosttyTerminalSession) { unregisterCount += 1 }
    func tick() {}
    func reloadConfig() {}
    func openConfig() {}
    func setColorScheme(_ colorScheme: GhosttyTerminalColorScheme, appearance: NSAppearance?) {}
}
