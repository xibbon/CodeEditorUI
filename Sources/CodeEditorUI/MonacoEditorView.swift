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
        configuration.userContentController = contentController
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isInspectable = true
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
            let config = monacoConfiguration(for: context.environment)
            let html = Self.monacoHTML(contents: contents, configuration: config)
            view.loadHTMLString(html, baseURL: baseURL)
            context.coordinator.lastKnownText = contents
            context.coordinator.lastConfiguration = config
            context.coordinator.lastBreakpoints = breakpoints
            context.coordinator.setBreakpoints(breakpoints)
        } else {
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
}

extension MonacoEditorView {
    @MainActor
    public final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let textChangedHandler = "monacoTextChanged"
        static let selectionChangedHandler = "monacoSelectionChanged"
        static let gutterTappedHandler = "monacoGutterTapped"
        static let readyHandler = "monacoReady"

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
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
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

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
            theme: theme
        )
    }

    private func normalizedFontFamily(_ family: String) -> String {
        if family.isEmpty || family == "System font" {
            return "monospace"
        }
        return family
    }

    private static func optionsJSON(for configuration: MonacoConfiguration) -> String {
        let options: [String: Any] = [
            "lineNumbers": configuration.showLineNumbers ? "on" : "off",
            "wordWrap": configuration.wordWrap ? "on" : "off",
            "renderWhitespace": configuration.renderWhitespace ? "all" : "none",
            "fontFamily": configuration.fontFamily,
            "fontSize": configuration.fontSize,
            "lineHeight": configuration.lineHeight,
            "minimap": ["enabled": false],
            "automaticLayout": true,
            "glyphMargin": true,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: options, options: []),
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
        return json
    }

    private static func jsIntArrayLiteral(_ values: [Int]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func monacoHTML(contents: String, configuration: MonacoConfiguration) -> String {
        let initialValue = jsStringLiteral(contents)
        let optionsJSON = optionsJSON(for: configuration)
        let language = jsStringLiteral(configuration.language)
        let theme = jsStringLiteral(configuration.theme)
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
            <script>
              var editor = null;
              var pendingValue = \(initialValue);
              var pendingOptions = \(optionsJSON);
              var pendingLanguage = \(language);
              var pendingTheme = \(theme);
              var pendingBreakpoints = [];
              var breakpointDecorations = [];

              function applyPending() {
                if (!editor) { return; }
                if (pendingOptions) {
                  editor.updateOptions(pendingOptions);
                }
                if (pendingLanguage) {
                  monaco.editor.setModelLanguage(editor.getModel(), pendingLanguage);
                }
                if (pendingTheme) {
                  monaco.editor.setTheme(pendingTheme);
                }
                if (typeof pendingValue === "string" && editor.getValue() !== pendingValue) {
                  editor.setValue(pendingValue);
                }
                applyBreakpoints();
              }

              function applyBreakpoints() {
                if (!editor) { return; }
                if (!pendingBreakpoints) { return; }
                var decorations = pendingBreakpoints.map(function(lineNumber) {
                  return {
                    range: new monaco.Range(lineNumber, 1, lineNumber, 1),
                    options: {
                      isWholeLine: true,
                      glyphMarginClassName: "monaco-breakpoint"
                    }
                  };
                });
                breakpointDecorations = editor.deltaDecorations(breakpointDecorations, decorations);
              }

              window.setEditorValue = function(value) {
                pendingValue = value;
                applyPending();
              };

              window.configureEditor = function(options, language, theme) {
                pendingOptions = options || pendingOptions;
                pendingLanguage = language || pendingLanguage;
                pendingTheme = theme || pendingTheme;
                applyPending();
              };

              window.setBreakpoints = function(lines) {
                if (!Array.isArray(lines)) {
                  pendingBreakpoints = [];
                } else {
                  pendingBreakpoints = lines;
                }
                applyBreakpoints();
              };

              window.focusEditor = function() {
                if (editor) { editor.focus(); }
              };

              window.gotoLine = function(lineNumber) {
                if (!editor) { return; }
                editor.revealLineInCenter(lineNumber);
                editor.setPosition({ lineNumber: lineNumber, column: 1 });
                editor.focus();
              };

              window.runEditorAction = function(actionId) {
                if (!editor) { return; }
                var action = editor.getAction(actionId);
                if (action) { action.run(); }
              };

              window.undoEditor = function() {
                if (!editor) { return; }
                editor.trigger("keyboard", "undo", null);
              };

              window.redoEditor = function() {
                if (!editor) { return; }
                editor.trigger("keyboard", "redo", null);
              };

              function startEditor() {
                require.config({ paths: { vs: "min/vs" } });
                require(["vs/editor/editor.main"], function() {
                  var createOptions = Object.assign({}, pendingOptions || {}, {
                    value: pendingValue || "",
                    language: pendingLanguage || "plaintext",
                    theme: pendingTheme || "vs"
                  });
                  editor = monaco.editor.create(document.getElementById("container"), createOptions);
                  applyPending();

                  editor.onDidChangeModelContent(function() {
                    window.webkit.messageHandlers.\(Coordinator.textChangedHandler).postMessage(editor.getValue());
                  });

                  editor.onDidChangeCursorSelection(function(e) {
                    var model = editor.getModel();
                    if (!model) { return; }
                    var selection = e.selection;
                    var startOffset = model.getOffsetAt({ lineNumber: selection.startLineNumber, column: selection.startColumn });
                    var endOffset = model.getOffsetAt({ lineNumber: selection.endLineNumber, column: selection.endColumn });
                    window.webkit.messageHandlers.\(Coordinator.selectionChangedHandler).postMessage({ start: startOffset, end: endOffset });
                  });

                  editor.onMouseDown(function(e) {
                    if (!e || !e.target || !e.target.position) { return; }
                    var targetType = e.target.type;
                    if (targetType === monaco.editor.MouseTargetType.GUTTER_GLYPH_MARGIN ||
                        targetType === monaco.editor.MouseTargetType.GUTTER_LINE_NUMBERS ||
                        targetType === monaco.editor.MouseTargetType.GUTTER_LINE_DECORATIONS) {
                      window.webkit.messageHandlers.\(Coordinator.gutterTappedHandler).postMessage(e.target.position.lineNumber);
                    }
                  });

                  window.webkit.messageHandlers.\(Coordinator.readyHandler).postMessage(true);
                });
              }

              window.addEventListener("load", startEditor);
            </script>
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
