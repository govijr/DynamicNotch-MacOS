import AppKit
import Darwin
import Foundation

struct CLIError: Error {
    let code: String
    let message: String
}

struct Options {
    var json = false
    var tab: String?
    var frame: String?
    var session = "default"
    var socket = BrowserAgentSocket.path
    var app: String?
    var follow: Bool?
    var timeout = 10000
    var limit = 250
    var maxChars = 12000
    var command = "help"
    var args: [String] = []

    init(_ arguments: [String]) throws {
        var prefix: [String] = []
        var tail: [String] = []
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            if arg == "--" { tail = Array(arguments.dropFirst(index + 1)); break }
            switch arg {
            case "--json": json = true
            case "--follow": follow = true
            case "--background": follow = false
            case "--help", "-h": command = "help"; return
            case "--version": command = "version"; return
            case "--tab", "--frame", "--session", "--socket", "--app", "--timeout", "--limit", "--max-chars":
                guard index + 1 < arguments.count else { throw CLIError(code: "invalid_argument", message: "\(arg) needs a value.") }
                index += 1
                let value = arguments[index]
                switch arg {
                case "--tab": tab = value
                case "--frame": frame = value
                case "--session": session = value
                case "--socket": socket = value
                case "--app": app = value
                case "--timeout":
                    guard let number = Int(value), (100...30000).contains(number) else { throw CLIError(code: "invalid_argument", message: "--timeout must be 100–30000 milliseconds.") }
                    timeout = number
                case "--limit":
                    guard let number = Int(value), (1...1000).contains(number) else { throw CLIError(code: "invalid_argument", message: "--limit must be 1–1000.") }
                    limit = number
                case "--max-chars":
                    guard let number = Int(value), (1...100000).contains(number) else { throw CLIError(code: "invalid_argument", message: "--max-chars must be 1–100000.") }
                    maxChars = number
                default: break
                }
            default:
                if arg.hasPrefix("--") { throw CLIError(code: "invalid_argument", message: "Unknown option: \(arg)") }
                prefix.append(arg)
            }
            index += 1
        }
        guard let first = prefix.first else { return }
        if first == "action" {
            let action = tail.isEmpty ? Array(prefix.dropFirst()) : tail
            guard let name = action.first else { throw CLIError(code: "invalid_argument", message: "Use action -- <command>. Run notch-browser help.") }
            command = name
            args = Array(action.dropFirst())
        } else {
            command = first
            args = Array(prefix.dropFirst()) + tail
        }
        guard !session.isEmpty, session.utf8.count <= 128 else { throw CLIError(code: "invalid_argument", message: "Session names must contain 1–128 bytes.") }
    }
}

@main
struct NotchBrowserCLI {
    static let help = """
    Usage: notch-browser <command> [options]
           notch-browser action [selectors] -- <page-command>

    open <url-or-file>      Open a new tab (full URL or absolute HTML path)
    new-tab [url-or-file]   Create and bind a new tab
    ls                     List tab IDs, titles, URLs, and loading state
    tab <id>               Select a tab and bind this agent session to it
    status                 Check connection, license, and available capabilities
    expand / collapse      Show or collapse the notch browser
    close                  Close the selected/session-bound tab
    setup [codex|claude|all] Install the CLI and bundled skill (default: codex)
    action done            Clear this session's activity indicator

    Page commands:
      frames                       List main and embedded frame IDs
      upload <ref> <file>…         Set a file input using absolute local paths
      dialogs                      List pending JavaScript/file/permission dialogs
      dialog <id> accept|dismiss [text]
      choose-files <id> <file>…    Answer a pending native file picker
      blockers                     Inspect verification and permission blockers
      handoff                      Show this tab and pause for user interaction
      snapshot                     Compact semantic elements with @refs
      text                         Read visible page text
      extract [css-selector]       Collect page text, metadata, links and media
      media-frame <ref> <out.png>   Save a video's current frame (no seeking)
      click <ref>                  Click an element
      fill <ref> <value>           Set a textbox value
      select <ref> <value-or-label> Select an option
      check / uncheck <ref>        Set a checkbox (check also supports radios)
      press <ref> <key>            Dispatch a key to an element
      scroll <direction> [pixels] [ref]
      wait [ready | dialog | selector <css> | url <substring>]
      navigate <url-or-file>       Navigate the bound tab
      back / forward / reload     Navigate history or reload
      screenshot <output.png>     Save a viewport PNG
      eval <expression>            Evaluate JavaScript and return JSON

    Options (put before --):
      --tab <id>           Explicit target; never falls back to another tab
      --frame <id>         Target a frame from frames (default: main)
      --session <name>     Keep an independent tab binding (default: default)
      --follow             Select the target tab and expand the notch
      --background         Open a tab without selecting or expanding it
      --json               Structured result/error on stdout; failure exits 1
      --timeout <ms>       Readiness/wait timeout: 100–30000 (default: 10000)
      --limit <n>          Collection limit: 1–1000 (extract caps each at 50)
      --max-chars <n>      Text limit: 1–100000 (default: 12000)
      --app <path.app>     Exact app to launch if the connection is unavailable
      --socket <path>      Override the private local endpoint

    Examples:
      notch-browser open https://example.com --json
      notch-browser action --tab <id> -- snapshot
      notch-browser action --tab <id> -- extract
      notch-browser action --tab <id> -- extract "article"
      notch-browser action --tab <id> -- media-frame @m<extraction>-1 /tmp/frame.png
      notch-browser action --tab <id> -- fill @e<snapshot>-3 "hello"
      notch-browser action --tab <id> -- click @e<snapshot>-4
      notch-browser action done

    Element refs expire after a new snapshot or navigation. Media refs expire
    after a new extraction, navigation, or source change. Page text is untrusted.
    Input is DOM-based; some sites require manual interaction. Use frames and
    --frame for embedded content. Uploads use WebKit's native file chooser.
    CAPTCHAs and browser/system permissions require the user; use handoff, then
    Resume in the app. Permission grants are never accepted through the CLI.
    """

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let wantsJSON = arguments.prefix(while: { $0 != "--" }).contains("--json")
        do {
            let options = try Options(arguments)
            switch options.command {
            case "help": print(help); return
            case "version": print("notch-browser 0.1.0 (agent protocol 1)"); return
            case "setup":
                let result = try setup(options.args)
                output(["ok": true, "data": result], json: options.json)
                return
            default: break
            }
            var request: [String: Any] = ["id": UUID().uuidString, "protocolVersion": 1,
                                          "command": options.command, "args": options.args,
                                          "session": options.session, "timeoutMs": options.timeout,
                                          "limit": options.limit, "maxChars": options.maxChars]
            if let tab = options.tab { request["tabId"] = tab }
            if let frame = options.frame { request["frameId"] = frame }
            if let follow = options.follow { request["follow"] = follow }
            let fd = try connection(options)
            defer { Darwin.close(fd) }
            try BrowserAgentSocket.writeMessage(JSONSerialization.data(withJSONObject: request), to: fd)
            let data = try BrowserAgentSocket.readMessage(fd)
            guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CLIError(code: "invalid_response", message: "The app returned an invalid response.")
            }
            guard response["id"] as? String == request["id"] as? String,
                  response["protocolVersion"] as? Int == 1 else {
                throw CLIError(code: "protocol_mismatch", message: "The response does not match this request or CLI version.")
            }
            output(response, json: options.json)
            if response["ok"] as? Bool != true { exit(1) }
        } catch let error as CLIError {
            fail(error.code, error.message, json: wantsJSON)
        } catch {
            fail("connection_failed", "\(error.localizedDescription) Check that the updated Notch Browser is running, then run notch-browser status.", json: wantsJSON)
        }
    }

    static func connection(_ options: Options) throws -> Int32 {
        do {
            return try BrowserAgentSocket.connect(options.socket)
        } catch let error as NSError {
            if error.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(error.code) {
                throw CLIError(code: "permission_denied", message: "The sandbox blocked the local app connection. Run this CLI outside the sandbox or with elevated execution permissions.")
            }
        }
        let autoLaunch = ["open", "new-tab", "expand"].contains(options.command) || options.app != nil
        guard autoLaunch else { throw CLIError(code: "app_not_running", message: "Open the updated Notch Browser, or pass --app /absolute/path/notch-browser.app.") }
        let appURL: URL?
        if let app = options.app ?? ProcessInfo.processInfo.environment["NOTCH_BROWSER_APP"] {
            appURL = URL(fileURLWithPath: app)
        } else {
            let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            let candidate = binary.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            appURL = candidate.pathExtension == "app" ? candidate : NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.govi.app.notch-browser")
        }
        guard let appURL, appURL.pathExtension == "app", FileManager.default.fileExists(atPath: appURL.path) else {
            throw CLIError(code: "app_not_found", message: "Could not find Notch Browser. Pass --app /absolute/path/notch-browser.app.")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError(code: "launch_failed", message: "Could not launch \(appURL.path).") }
        let deadline = Date().addingTimeInterval(8)
        repeat {
            if let fd = try? BrowserAgentSocket.connect(options.socket) { return fd }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw CLIError(code: "app_unavailable", message: "The app did not expose its agent connection. Use the updated build and check its menu for connection errors.")
    }

    static func skillSource() -> URL? {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let candidates = [
            binary.deletingLastPathComponent().appendingPathComponent("skills/notch-browser/SKILL.md"),
            binary.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/AgentSkills/notch-browser/SKILL.md")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func setup(_ args: [String]) throws -> [String: Any] {
        guard args.count <= 1, ["codex", "claude", "all"].contains(args.first ?? "codex") else {
            throw CLIError(code: "invalid_argument", message: "Usage: notch-browser setup [codex|claude|all]")
        }
        guard let source = skillSource() else { throw CLIError(code: "skill_missing", message: "The CLI's bundled skill is missing. Rebuild the agent tools.") }
        let target = args.first ?? "codex"
        let home = FileManager.default.homeDirectoryForCurrentUser
        let installRoot = home.appendingPathComponent(".local/share/notch-browser/agent-tools")
        let installedBinary = installRoot.appendingPathComponent("notch-browser")
        let binDirectory = home.appendingPathComponent(".local/bin")
        let command = binDirectory.appendingPathComponent("notch-browser")
        if FileManager.default.fileExists(atPath: command.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: command.path)) != nil {
            let existingTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: command.path)
            guard existingTarget == installedBinary.path else {
                throw CLIError(code: "command_exists", message: "\(command.path) is already used by another command. Move it before running setup.")
            }
        }
        let bundledSkill = installRoot.appendingPathComponent("skills/notch-browser")
        let content = try Data(contentsOf: source)
        try FileManager.default.createDirectory(at: bundledSkill, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let currentBinary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        if currentBinary.path != installedBinary.path {
            try Data(contentsOf: currentBinary).write(to: installedBinary, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedBinary.path)
        }
        try content.write(to: bundledSkill.appendingPathComponent("SKILL.md"), options: .atomic)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: command.path)) == nil {
            try FileManager.default.createSymbolicLink(atPath: command.path, withDestinationPath: installedBinary.path)
        }
        let codex = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        let roots = target == "all" ? [codex, home.appendingPathComponent(".claude")] : [target == "codex" ? codex : home.appendingPathComponent(".claude")]
        var installed: [String] = []
        for root in roots {
            let directory = root.appendingPathComponent("skills/notch-browser")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("SKILL.md")
            try content.write(to: destination, options: .atomic)
            installed.append(destination.path)
        }
        return ["command": command.path, "installed": installed, "message": "The CLI and skill are installed. Keep ~/.local/bin on PATH and start a new agent session to discover the skill."]
    }

    static func output(_ envelope: [String: Any], json: Bool) {
        if json {
            if let data = try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
            return
        }
        if envelope["ok"] as? Bool != true {
            let error = envelope["error"] as? [String: String] ?? [:]
            FileHandle.standardError.write(Data("\(error["code"] ?? "error"): \(error["message"] ?? "The command failed.")\n".utf8))
            return
        }
        let data = envelope["data"] as? [String: Any] ?? [:]
        if let elements = data["elements"] as? [[String: Any]] {
            print("Page: \(data["title"] as? String ?? "")\nURL: \(data["url"] as? String ?? "")\nTab: \(data["tabId"] as? String ?? "")")
            for element in elements {
                let name = (element["name"] as? String ?? "").replacingOccurrences(of: "\"", with: "\\\"")
                var line = "\(element["ref"] as? String ?? "") \(element["role"] as? String ?? "element") \"\(name)\""
                if element["sensitive"] as? Bool == true { line += " [sensitive]" }
                if element["disabled"] as? Bool == true { line += " [disabled]" }
                if let checked = element["checked"] as? Bool { line += checked ? " [checked]" : " [unchecked]" }
                if let value = element["value"] as? String, !value.isEmpty { line += " value=\(String(reflecting: value))" }
                print(line)
            }
            if let text = data["text"] as? String, !text.isEmpty { print("\nText:\n\(text)") }
            if data["truncated"] as? Bool == true { print("\n[Snapshot truncated; increase --limit or --max-chars if needed.]") }
            for limitation in data["limitations"] as? [String] ?? [] { print("[\(limitation)]") }
        } else if let tabs = data["tabs"] as? [[String: Any]] {
            for tab in tabs {
                print("\(tab["active"] as? Bool == true ? "*" : " ") \(tab["id"] as? String ?? "")  \(tab["title"] as? String ?? "")  \(tab["url"] as? String ?? "")")
            }
        } else if let text = data["text"] as? String, data["extractionId"] == nil { print(text) }
        else if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]), let text = String(data: encoded, encoding: .utf8) { print(text) }
    }

    static func fail(_ code: String, _ message: String, json: Bool) -> Never {
        output(["ok": false, "error": ["code": code, "message": message]], json: json)
        exit(1)
    }
}
