#if canImport(AppKit)
import Foundation
import SwiftUI
import WebKit

public struct MonacoEditorView: NSViewRepresentable {
    @Binding var contents: String
    let item: EditedItem
    let state: CodeEditorState

    public init(state: CodeEditorState, item: EditedItem, contents: Binding<String>) {
        self.state = state
        self.item = item
        self._contents = contents
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        update(webView: webView, context: context)
    }

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.messageHandlerName)
        configuration.userContentController = contentController
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isInspectable = true
        context.coordinator.webView = view
        context.coordinator.parent = self

        if let baseURL = monacoBaseURL() {
            let config = monacoConfiguration(for: context.environment)
            let html = Self.monacoHTML(contents: contents, configuration: config)
            view.loadHTMLString(html, baseURL: baseURL)
            context.coordinator.lastKnownText = contents
            context.coordinator.lastConfiguration = config
        } else {
            view.loadHTMLString(Self.missingMonacoHTML, baseURL: nil)
        }

        return view
    }

    private func update(webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        let config = monacoConfiguration(for: context.environment)
        if config != context.coordinator.lastConfiguration {
            context.coordinator.lastConfiguration = config
            context.coordinator.setConfiguration(config)
        }

        if contents != context.coordinator.lastKnownText {
            context.coordinator.lastKnownText = contents
            context.coordinator.setContents(contents)
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
    public final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let messageHandlerName = "monacoTextChanged"

        var parent: MonacoEditorView
        weak var webView: WKWebView?
        var lastKnownText: String = ""
        var lastConfiguration: MonacoConfiguration?
        private var pendingText: String?
        private var pendingConfiguration: MonacoConfiguration?
        private var isReady = false

        init(parent: MonacoEditorView) {
            self.parent = parent
        }

        deinit {
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageHandlerName else { return }
            guard let text = message.body as? String else { return }
            guard text != lastKnownText else { return }
            lastKnownText = text
            parent.contents = text
            parent.item.content = text
            parent.item.dirty = true
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            if let pendingText {
                setContents(pendingText)
                self.pendingText = nil
            }
            if let pendingConfiguration {
                setConfiguration(pendingConfiguration)
                self.pendingConfiguration = nil
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
    }

    private func monacoBaseURL() -> URL? {
        var candidates: [URL] = []
        if let resourceURL = Bundle.module.resourceURL {
            candidates.append(resourceURL)
            candidates.append(resourceURL.appendingPathComponent("monaco", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("package", isDirectory: true))
        }
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL)
            candidates.append(resourceURL.appendingPathComponent("monaco", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("package", isDirectory: true))
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

    private static func monacoHTML(contents: String, configuration: MonacoConfiguration) -> String {
        let initialValue = jsStringLiteral(contents)
        let optionsJSON = optionsJSON(for: configuration)
        let language = jsStringLiteral(configuration.language)
        let theme = jsStringLiteral(configuration.theme)
        return """
        <!doctype html>
        <html>
          <head>
            <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0">
            <style>
              html, body, #container {
                margin: 0;
                padding: 0;
                height: 100%;
                width: 100%;
                overflow: hidden;
                background: transparent;
              }
            </style>
            <script src="min/vs/loader.js"></script>
            <script>
              var editor = null;
              var pendingValue = \(initialValue);
              var pendingOptions = \(optionsJSON);
              var pendingLanguage = \(language);
              var pendingTheme = \(theme);

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
                    window.webkit.messageHandlers.\(Coordinator.messageHandlerName).postMessage(editor.getValue());
                  });
                });
              }

              window.addEventListener("load", startEditor);
            </script>
          </head>
          <body>
            <div id="container"></div>
          </body>
        </html>
        """
    }

    private static let missingMonacoHTML = """
    <!doctype html>
    <html>
      <head>
        <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0">
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
#endif
