import AppKit
import CryptoKit
import Foundation
import TVRemoteKit

enum UpdateInstallError: LocalizedError {
    case missingAsset
    case notWritable
    case downloadFailed
    case checksumMismatch
    case installFailed

    var errorDescription: String? {
        switch self {
        case .missingAsset:
            return "The release does not include a downloadable DMG."
        case .notWritable:
            return "MacDroid TV cannot update itself because its Applications folder is not writable. Move it to ~/Applications or update manually."
        case .downloadFailed:
            return "The update could not be downloaded."
        case .checksumMismatch:
            return "The downloaded update failed its checksum check and was not installed."
        case .installFailed:
            return "The update could not be installed."
        }
    }
}

/// Downloads a release DMG, verifies its SHA-256, and hands the replacement to
/// a short shell script that runs after the app quits. The app is relaunched by
/// the script.
enum UpdateInstaller {
    static func install(_ update: AvailableUpdate) async throws {
        guard let downloadURL = update.downloadURL,
              let expected = update.sha256,
              !expected.isEmpty
        else { throw UpdateInstallError.missingAsset }

        let appURL = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: appURL.path) else {
            throw UpdateInstallError.notWritable
        }

        let (data, response) = try await URLSession.shared.data(from: downloadURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
            throw UpdateInstallError.downloadFailed
        }

        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else {
            throw UpdateInstallError.checksumMismatch
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacDroidTVUpdate", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dmgURL = directory.appendingPathComponent("MacDroidTV-\(update.version).dmg")
        try data.write(to: dmgURL)

        let scriptURL = directory.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/sh
        sleep 2
        MOUNT="$(mktemp -d)"
        if ! hdiutil attach "\(dmgURL.path)" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null 2>&1; then
            exit 1
        fi
        if [ ! -d "$MOUNT/MacDroid TV.app" ]; then
            hdiutil detach "$MOUNT" >/dev/null 2>&1
            exit 1
        fi
        /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$MOUNT/MacDroid TV.app/Contents/Info.plist" 2>/dev/null | grep -q 'com.franktriolo.macdroidtv' || {
            hdiutil detach "$MOUNT" >/dev/null 2>&1
            exit 1
        }
        codesign --verify --deep --strict "$MOUNT/MacDroid TV.app" >/dev/null 2>&1 || {
            hdiutil detach "$MOUNT" >/dev/null 2>&1
            exit 1
        }
        codesign -dv --verbose=4 "$MOUNT/MacDroid TV.app" 2>&1 | grep -q 'TeamIdentifier=BJB8XCZ8X9' || {
            hdiutil detach "$MOUNT" >/dev/null 2>&1
            exit 1
        }
        rm -rf "\(appURL.path)"
        if ! ditto "$MOUNT/MacDroid TV.app" "\(appURL.path)"; then
            hdiutil detach "$MOUNT" >/dev/null 2>&1
            exit 1
        fi
        hdiutil detach "$MOUNT" >/dev/null 2>&1
        open "\(appURL.path)"
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        do {
            try process.run()
        } catch {
            throw UpdateInstallError.installFailed
        }
        NSApp.terminate(nil)
    }
}
