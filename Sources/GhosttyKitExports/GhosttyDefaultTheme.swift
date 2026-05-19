import AppKit

public enum GhosttyDefaultTheme {
    @MainActor
    public static func fallbackBackgroundColor(
        effectiveAppearance: NSAppearance?,
        applicationAppearance: NSAppearance?
    ) -> NSColor {
        let appearance = effectiveAppearance
            ?? applicationAppearance
            ?? NSAppearance(named: .aqua)
        let match = appearance?.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua {
            return NSColor(
                calibratedRed: 0x19 / 255,
                green: 0x17 / 255,
                blue: 0x24 / 255,
                alpha: 1
            )
        }
        return NSColor(
            calibratedRed: 0xfa / 255,
            green: 0xf4 / 255,
            blue: 0xed / 255,
            alpha: 1
        )
    }

    public static func ensureOverride(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        applicationName: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
    ) throws -> URL {
        guard let baseDirectoryURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        let folderName = sanitizedFolderName(applicationName) ?? "GhosttyKit"
        let directoryURL = baseDirectoryURL.appendingPathComponent(folderName, isDirectory: true)
        let lightThemeURL = directoryURL.appendingPathComponent("ghosttykit-default-light.ghostty")
        let darkThemeURL = directoryURL.appendingPathComponent("ghosttykit-default-dark.ghostty")
        let fileURL = directoryURL.appendingPathComponent("ghosttykit-default-theme.ghostty")

        let contents = """
        # Managed by GhosttyKit so embedded terminals have a readable default theme.
        theme = "light:\(quotedConfigPath(lightThemeURL)),dark:\(quotedConfigPath(darkThemeURL))"
        """

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try writeManagedConfigFile(lightThemeContents, to: lightThemeURL, fileManager: fileManager)
        try writeManagedConfigFile(darkThemeContents, to: darkThemeURL, fileManager: fileManager)
        try writeManagedConfigFile(contents, to: fileURL, fileManager: fileManager)
        return fileURL
    }

    static let lightThemeContents = """
    # Managed by GhosttyKit. This file provides the built-in light terminal palette.
    background = faf4ed
    background-opacity = 0.88
    background-blur = macos-glass-regular
    foreground = 575279
    cursor-color = 907aa9
    cursor-text = faf4ed
    selection-background = dfdad9
    selection-foreground = 575279
    palette = 0=#f2e9e1
    palette = 1=#b4637a
    palette = 2=#286983
    palette = 3=#ea9d34
    palette = 4=#56949f
    palette = 5=#907aa9
    palette = 6=#d7827e
    palette = 7=#575279
    palette = 8=#9893a5
    palette = 9=#b4637a
    palette = 10=#286983
    palette = 11=#ea9d34
    palette = 12=#56949f
    palette = 13=#907aa9
    palette = 14=#d7827e
    palette = 15=#575279
    palette-generate = true
    palette-harmonious = true
    """

    static let darkThemeContents = """
    # Managed by GhosttyKit. This file provides the built-in dark terminal palette.
    background = 191724
    background-opacity = 0.88
    background-blur = macos-glass-regular
    foreground = e0def4
    cursor-color = c4a7e7
    cursor-text = 191724
    selection-background = 403d52
    selection-foreground = e0def4
    palette = 0=#26233a
    palette = 1=#eb6f92
    palette = 2=#31748f
    palette = 3=#f6c177
    palette = 4=#9ccfd8
    palette = 5=#c4a7e7
    palette = 6=#ebbcba
    palette = 7=#e0def4
    palette = 8=#6e6a86
    palette = 9=#eb6f92
    palette = 10=#31748f
    palette = 11=#f6c177
    palette = 12=#9ccfd8
    palette = 13=#c4a7e7
    palette = 14=#ebbcba
    palette = 15=#e0def4
    palette-generate = true
    palette-harmonious = true
    """

    private static func writeManagedConfigFile(_ contents: String, to fileURL: URL, fileManager: FileManager) throws {
        if
            fileManager.fileExists(atPath: fileURL.path) == false
                || (try? String(contentsOf: fileURL, encoding: .utf8)) != contents
        {
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private static func quotedConfigPath(_ url: URL) -> String {
        url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func sanitizedFolderName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        let invalid = CharacterSet(charactersIn: "/:")
        return trimmed.components(separatedBy: invalid).joined(separator: "-")
    }
}
