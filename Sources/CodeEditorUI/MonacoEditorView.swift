import Foundation
import SwiftUI
import WebKit

#if os(macOS)
import AppKit
#endif

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

public struct MonacoEditorView: PlatformViewRepresentable {
    @Binding var contents: String
    let item: EditedItem
    let state: CodeEditorState
    let breakpoints: Set<Int>

    public init(state: CodeEditorState, item: EditedItem, contents: Binding<String>, breakpoints: Set<Int> = []) {
        self.state = state
        self.item = item
        self._contents = contents
        self.breakpoints = breakpoints
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

#if os(macOS)
    public func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView: webView, context: context)
    }
#else
    public func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        update(webView: webView, context: context)
    }
#endif

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.textChangedHandler)
        contentController.add(context.coordinator, name: Coordinator.selectionChangedHandler)
        contentController.add(context.coordinator, name: Coordinator.gutterTappedHandler)
        contentController.add(context.coordinator, name: Coordinator.readyHandler)
        contentController.add(context.coordinator, name: Coordinator.contextMenuHandler)
        contentController.add(context.coordinator, name: Coordinator.commandPaletteHandler)
        if state.monacoDebugLogging {
            contentController.add(context.coordinator, name: Coordinator.logHandler)
        }
        injectMonacoScripts(into: contentController, environment: context.environment)
        configuration.userContentController = contentController
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isInspectable = state.monacoDebugLogging
#if os(macOS)
        if state.monacoDebugLogging {
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }
#endif
#if !os(macOS)
        view.isFindInteractionEnabled = true
#endif
        let monacoTextView = MonacoTextView(webView: view, text: contents)
        let commands = MonacoEditorCommands(webView: view, textView: monacoTextView)
        item.commands = commands

        context.coordinator.webView = view
        context.coordinator.parent = self
        context.coordinator.monacoTextView = monacoTextView
        context.coordinator.commands = commands

        if let baseURL = monacoBaseURL() {
            if state.monacoDebugLogging {
                print("[Monaco] Using base URL: \(baseURL.path)")
            }
            let config = monacoConfiguration(for: context.environment)
            let html = Self.monacoHTML(contents: contents, configuration: config)
            view.loadHTMLString(html, baseURL: baseURL)
            context.coordinator.lastKnownText = contents
            context.coordinator.lastConfiguration = config
            context.coordinator.lastBreakpoints = breakpoints
            context.coordinator.setContents(contents)
            context.coordinator.setBreakpoints(breakpoints)
        } else {
            if state.monacoDebugLogging {
                print("[Monaco] Base URL not found for assets.")
            }
            view.loadHTMLString(Self.missingMonacoHTML, baseURL: nil)
        }

        return view
    }

    private func update(webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.commands?.attach(webView: webView, textView: context.coordinator.monacoTextView)

        let config = monacoConfiguration(for: context.environment)
        if config != context.coordinator.lastConfiguration {
            context.coordinator.lastConfiguration = config
            context.coordinator.setConfiguration(config)
        }

        if contents != context.coordinator.lastKnownText {
            context.coordinator.lastKnownText = contents
            context.coordinator.setContents(contents)
        }

        if breakpoints != context.coordinator.lastBreakpoints {
            context.coordinator.lastBreakpoints = breakpoints
            context.coordinator.setBreakpoints(breakpoints)
        }
    }

    private func injectMonacoScripts(into controller: WKUserContentController, environment: EnvironmentValues) {
        let config = monacoConfiguration(for: environment)
        let configObject: [String: Any] = [
            "options": Self.optionsDictionary(for: config),
            "language": config.language,
            "theme": config.theme,
            "debugLoggingEnabled": config.debugLoggingEnabled,
            "initialValue": contents,
            "lspWebSocketURL": state.lspWebSocketURL,
            "lspWorkspaceRoot": state.lspWorkspaceRoot as Any,
            "documentPath": item.path
        ]
        let configJSON = Self.jsonStringLiteral(configObject)
        let configScript = "window.monacoConfig = \(configJSON);"
        let configUserScript = WKUserScript(source: configScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(configUserScript)

        if let bridgeSource = monacoBridgeSource() {
            let bridgeScript = WKUserScript(source: bridgeSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            controller.addUserScript(bridgeScript)
        } else if state.monacoDebugLogging {
            print("[Monaco] monaco-bridge.js not found in bundle resources.")
        }
    }

    private func monacoBridgeSource() -> String? {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: "monaco-bridge", withExtension: "js"),
            Bundle.main.url(forResource: "monaco-bridge", withExtension: "js")
        ]
        for url in candidates {
            if let url, let source = try? String(contentsOf: url, encoding: .utf8) {
                return source
            }
        }
        return nil
    }
}

struct MonacoConfiguration: Equatable {
    let language: String
    let fontFamily: String
    let fontSize: Int
    let lineHeight: Int
    let showLineNumbers: Bool
    let wordWrap: Bool
    let renderWhitespace: Bool
    let theme: String
    let debugLoggingEnabled: Bool
}

extension MonacoEditorView {
    @MainActor
    public final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let textChangedHandler = "monacoTextChanged"
        static let selectionChangedHandler = "monacoSelectionChanged"
        static let gutterTappedHandler = "monacoGutterTapped"
        static let readyHandler = "monacoReady"
        static let contextMenuHandler = "monacoContextMenu"
        static let commandPaletteHandler = "monacoCommandPalette"
        static let logHandler = "monacoLog"

        var parent: MonacoEditorView
        weak var webView: WKWebView?
        var monacoTextView: MonacoTextView?
        var commands: MonacoEditorCommands?
        var lastKnownText: String = ""
        var lastConfiguration: MonacoConfiguration?
        var lastBreakpoints: Set<Int> = []
        private var pendingText: String?
        private var pendingConfiguration: MonacoConfiguration?
        private var pendingBreakpoints: Set<Int>?
        private var isReady = false
        private var hasStarted = false

        init(parent: MonacoEditorView) {
            self.parent = parent
        }

        deinit {
            let controller = webView?.configuration.userContentController
            controller?.removeScriptMessageHandler(forName: Self.textChangedHandler)
            controller?.removeScriptMessageHandler(forName: Self.selectionChangedHandler)
            controller?.removeScriptMessageHandler(forName: Self.gutterTappedHandler)
            controller?.removeScriptMessageHandler(forName: Self.readyHandler)
            controller?.removeScriptMessageHandler(forName: Self.contextMenuHandler)
            controller?.removeScriptMessageHandler(forName: Self.commandPaletteHandler)
            controller?.removeScriptMessageHandler(forName: Self.logHandler)
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case Self.logHandler:
                log(message.body)
            case Self.textChangedHandler:
                guard let text = message.body as? String else { return }
                guard text != lastKnownText else { return }
                lastKnownText = text
                monacoTextView?.text = text
                parent.contents = text
                parent.item.content = text
                if let monacoTextView {
                    parent.item.editedTextChanged(on: monacoTextView)
                }
            case Self.selectionChangedHandler:
                guard let payload = message.body as? [String: Any] else { return }
                guard let start = (payload["start"] as? NSNumber)?.intValue,
                      let end = (payload["end"] as? NSNumber)?.intValue else { return }
                monacoTextView?.updateSelection(start: start, end: end)
                if let monacoTextView {
                    parent.item.editedTextSelectionChanged(on: monacoTextView)
                }
            case Self.gutterTappedHandler:
                guard let lineNumber = (message.body as? NSNumber)?.intValue else { return }
                let lineIndex = max(0, lineNumber - 1)
                if let monacoTextView {
                    parent.item.gutterTapped(on: monacoTextView, line: lineIndex)
                }
            case Self.contextMenuHandler:
                guard let payload = message.body as? [String: Any] else { return }
                guard let monacoTextView else { return }
                let actions = parseMenuItems(from: payload["actions"])
                let selectedText = payload["selectedText"] as? String ?? ""
                let word = payload["word"] as? String
                let location = parseTextLocation(from: payload["position"])
                let selection = parseSelection(from: payload["selection"])
                let point = parsePoint(from: payload["point"])
                let request = MonacoContextMenuRequest(
                    location: location,
                    selection: selection,
                    selectedText: selectedText,
                    word: word,
                    actions: actions,
                    viewPoint: point
                )
                parent.item.contextMenuRequested(on: monacoTextView, request: request)
            case Self.commandPaletteHandler:
                guard let payload = message.body as? [String: Any] else { return }
                guard let monacoTextView else { return }
                let actions = parseActionItems(from: payload["actions"])
                let request = MonacoCommandPaletteRequest(actions: actions)
                parent.item.commandPaletteRequested(on: monacoTextView, request: request)
            case Self.readyHandler:
                isReady = true
                flushPendingUpdates()
                if !hasStarted, let monacoTextView {
                    hasStarted = true
                    parent.item.started(on: monacoTextView)
                }
            default:
                break
            }
        }

        private func parseActionItems(from value: Any?) -> [MonacoActionItem] {
            guard let entries = value as? [[String: Any]] else { return [] }
            return entries.compactMap { entry in
                guard let id = entry["id"] as? String else { return nil }
                let label = entry["label"] as? String ?? id
                let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? true
                return MonacoActionItem(id: id, label: label, enabled: enabled)
            }
        }

        private func parseMenuItems(from value: Any?) -> [MonacoMenuItem] {
            guard let entries = value as? [[String: Any]] else { return [] }
            return entries.compactMap { entry in
                let kindRaw = entry["kind"] as? String ?? "action"
                let kind = MonacoMenuItem.Kind(rawValue: kindRaw) ?? .action
                let id = entry["id"] as? String
                let label = entry["label"] as? String
                let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? true
                let keybinding = entry["keybinding"] as? String
                let children = parseMenuItems(from: entry["children"])
                return MonacoMenuItem(kind: kind, id: id, label: label, enabled: enabled, keybinding: keybinding, children: children)
            }
        }

        private func parseTextLocation(from value: Any?) -> TextLocation? {
            guard let entry = value as? [String: Any] else { return nil }
            guard let lineNumber = (entry["lineNumber"] as? NSNumber)?.intValue else { return nil }
            let column = (entry["column"] as? NSNumber)?.intValue ?? 1
            return TextLocation(lineNumber: max(0, lineNumber - 1), column: max(0, column - 1))
        }

        private func parseSelection(from value: Any?) -> MonacoSelectionRange? {
            guard let entry = value as? [String: Any] else { return nil }
            guard let startLine = (entry["startLineNumber"] as? NSNumber)?.intValue,
                  let startColumn = (entry["startColumn"] as? NSNumber)?.intValue,
                  let endLine = (entry["endLineNumber"] as? NSNumber)?.intValue,
                  let endColumn = (entry["endColumn"] as? NSNumber)?.intValue else { return nil }
            return MonacoSelectionRange(
                startLine: max(0, startLine - 1),
                startColumn: max(0, startColumn - 1),
                endLine: max(0, endLine - 1),
                endColumn: max(0, endColumn - 1)
            )
        }

        private func parsePoint(from value: Any?) -> CGPoint? {
            guard let entry = value as? [String: Any] else { return nil }
            guard let x = (entry["x"] as? NSNumber)?.doubleValue,
                  let y = (entry["y"] as? NSNumber)?.doubleValue else { return nil }
            return CGPoint(x: x, y: y)
        }

        private func log(_ body: Any) {
            let enabled = parent.state.monacoDebugLogging
            guard enabled else { return }
            if let payload = body as? [String: Any] {
                let level = payload["level"] as? String ?? "log"
                let message = payload["message"] as? String ?? "\(payload)"
                print("[Monaco][\(level)] \(message)")
            } else if let message = body as? String {
                print("[Monaco] \(message)")
            } else {
                print("[Monaco] \(body)")
            }
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if parent.state.monacoDebugLogging {
                print("[Monaco] WebView didFinish navigation")
                runDebugProbe(in: webView)
            }
            if let pendingText {
                setContents(pendingText)
                self.pendingText = nil
            }
            if let pendingConfiguration {
                setConfiguration(pendingConfiguration)
                self.pendingConfiguration = nil
            }
            if let pendingBreakpoints {
                setBreakpoints(pendingBreakpoints)
                self.pendingBreakpoints = nil
            }
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if parent.state.monacoDebugLogging {
                print("[Monaco] WebView didFail navigation: \(error.localizedDescription)")
            }
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if parent.state.monacoDebugLogging {
                print("[Monaco] WebView didFailProvisionalNavigation: \(error.localizedDescription)")
            }
        }

        private func runDebugProbe(in webView: WKWebView) {
            let probes: [(String, String)] = [
                ("readyState", "document.readyState"),
                ("scriptCount", "document.getElementsByTagName('script').length"),
                ("hasSetEditorValue", "typeof window.setEditorValue"),
                ("hasConfigureEditor", "typeof window.configureEditor"),
                ("hasReplaceTextAt", "typeof window.replaceTextAt"),
                ("hasMonacoLog", "typeof window.monacoLog"),
                ("hasRequire", "typeof require")
            ]
            for (label, script) in probes {
                webView.evaluateJavaScript(script) { result, error in
                    if let error {
                        print("[Monaco][probe] \(label) error: \(error.localizedDescription)")
                    } else if let result {
                        print("[Monaco][probe] \(label): \(result)")
                    } else {
                        print("[Monaco][probe] \(label): nil")
                    }
                }
            }
        }

        func setContents(_ text: String) {
            guard let webView else {
                pendingText = text
                return
            }
            if !isReady {
                pendingText = text
                return
            }
            monacoTextView?.text = text
            let js = "window.setEditorValue(\(MonacoEditorView.jsStringLiteral(text)));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func setConfiguration(_ config: MonacoConfiguration) {
            guard let webView else {
                pendingConfiguration = config
                return
            }
            if !isReady {
                pendingConfiguration = config
                return
            }
            let options = MonacoEditorView.optionsJSON(for: config)
            let language = MonacoEditorView.jsStringLiteral(config.language)
            let theme = MonacoEditorView.jsStringLiteral(config.theme)
            let js = "window.configureEditor(\(options), \(language), \(theme));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func setBreakpoints(_ breakpoints: Set<Int>) {
            let sorted = breakpoints.filter { $0 >= 0 }.sorted()
            let lineNumbers = sorted.map { $0 + 1 }
            guard let webView else {
                pendingBreakpoints = breakpoints
                return
            }
            if !isReady {
                pendingBreakpoints = breakpoints
                return
            }
            let jsArray = MonacoEditorView.jsIntArrayLiteral(lineNumbers)
            let js = "window.setBreakpoints(\(jsArray));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func flushPendingUpdates() {
            if let pendingText {
                setContents(pendingText)
                self.pendingText = nil
            }
            if let pendingConfiguration {
                setConfiguration(pendingConfiguration)
                self.pendingConfiguration = nil
            }
            if let pendingBreakpoints {
                setBreakpoints(pendingBreakpoints)
                self.pendingBreakpoints = nil
            }
        }
    }

    private func monacoBaseURL() -> URL? {
        var candidates: [URL] = []
        if let resourceURL = Bundle.module.resourceURL {
            candidates.append(resourceURL)
            candidates.append(resourceURL.appendingPathComponent("monaco", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("monaco.bundle", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("package", isDirectory: true))
        }
        if let bundleURL = Bundle.module.url(forResource: "monaco", withExtension: "bundle") {
            candidates.append(bundleURL)
            if let bundle = Bundle(url: bundleURL), let bundleResourceURL = bundle.resourceURL {
                candidates.append(bundleResourceURL)
            }
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL)
            candidates.append(resourceURL.appendingPathComponent("monaco", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("monaco.bundle", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("package", isDirectory: true))
        }
        if let bundleURL = Bundle.main.url(forResource: "monaco", withExtension: "bundle") {
            candidates.append(bundleURL)
            if let bundle = Bundle(url: bundleURL), let bundleResourceURL = bundle.resourceURL {
                candidates.append(bundleResourceURL)
            }
        }

        for baseURL in candidates {
            let loaderURL = baseURL.appendingPathComponent("min/vs/loader.js")
            if FileManager.default.fileExists(atPath: loaderURL.path) {
                return baseURL
            }
        }
        return nil
    }

    private func monacoConfiguration(for environment: EnvironmentValues) -> MonacoConfiguration {
        let fontFamily = normalizedFontFamily(state.fontFamily)
        let fontSize = max(1, Int(state.fontSize.rounded()))
        let lineHeight = max(1, Int((state.fontSize * state.lineHeightMultiplier).rounded()))
        let language = MonacoLanguageResolver.language(for: item.path)
        let theme = environment.colorScheme == .dark ? "vs-dark" : "vs"
        return MonacoConfiguration(
            language: language,
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineHeight: lineHeight,
            showLineNumbers: state.showLines,
            wordWrap: state.lineWrapping,
            renderWhitespace: state.showSpaces || state.showTabs,
            theme: theme,
            debugLoggingEnabled: state.monacoDebugLogging
        )
    }

    private func normalizedFontFamily(_ family: String) -> String {
        if family.isEmpty || family == "System Font" {
            return "monospace"
        }
        return family
    }

    private static func optionsDictionary(for configuration: MonacoConfiguration) -> [String: Any] {
        [
            "lineNumbers": configuration.showLineNumbers ? "on" : "off",
            "wordWrap": configuration.wordWrap ? "on" : "off",
            "renderWhitespace": configuration.renderWhitespace ? "all" : "none",
            "fontFamily": configuration.fontFamily,
            "fontSize": configuration.fontSize,
            "lineHeight": configuration.lineHeight,
            "minimap": ["enabled": false],
            "automaticLayout": true,
            "glyphMargin": true,
            "contextmenu": false
        ]
    }

    private static func optionsJSON(for configuration: MonacoConfiguration) -> String {
        jsonStringLiteral(optionsDictionary(for: configuration))
    }

    private static func jsonStringLiteral(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json.replacingOccurrences(of: "</", with: "<\\/")
    }

    private static func jsIntArrayLiteral(_ values: [Int]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func monacoHTML(contents: String, configuration: MonacoConfiguration) -> String {
        _ = contents
        _ = configuration
        return """
        <!doctype html>
        <html>
          <head>
            <meta name=\"viewport\" content=\"initial-scale=1.0, maximum-scale=1.0\">
            <style>
              html, body, #container {
                margin: 0;
                padding: 0;
                height: 100%;
                width: 100%;
                overflow: hidden;
                background: transparent;
              }
              .monaco-breakpoint {
                background: #e05a50;
                border-radius: 6px;
                width: 10px;
                height: 10px;
                margin-left: 4px;
                margin-top: 4px;
              }
            </style>
            <script src=\"min/vs/loader.js\"></script>
          </head>
          <body>
            <div id=\"container\"></div>
          </body>
        </html>
        """
    }

    private static let missingMonacoHTML = """
    <!doctype html>
    <html>
      <head>
        <meta name=\"viewport\" content=\"initial-scale=1.0, maximum-scale=1.0\">
        <style>
          html, body {
            margin: 0;
            padding: 0;
            height: 100%;
            width: 100%;
            font-family: -apple-system, Helvetica, Arial, sans-serif;
            background: #f8f8f8;
            color: #444;
            display: flex;
            align-items: center;
            justify-content: center;
            text-align: center;
          }
        </style>
      </head>
      <body>
        <div>Monaco assets not found in the bundled package resources.</div>
      </body>
    </html>
    """
}

private enum MonacoLanguageResolver {
    static func language(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "gd", "gdscript":
            return "gdscript"
        case "swift":
            return "swift"
        case "js":
            return "javascript"
        case "ts":
            return "typescript"
        case "json":
            return "json"
        case "md":
            return "markdown"
        case "html", "htm":
            return "html"
        case "css":
            return "css"
        case "py":
            return "python"
        case "sh":
            return "shell"
        case "yml", "yaml":
            return "yaml"
        default:
            return "plaintext"
        }
    }
}
