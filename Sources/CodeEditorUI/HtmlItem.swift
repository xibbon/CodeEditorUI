//
//  HtmlItem.swift
//
//
//  Created by Miguel de Icaza on 5/11/24.
//

import Foundation
import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#endif

/// An HTML page that can be embedeed into the CodeEditorShell in a tab
public class HtmlItem: HostedItem {
    let _title: String
    public var anchor: String? {
        didSet {
            if let view, let anchor {
                view.scrollTo(anchor)
            }
        }
    }
    public override var title: String { _title }
    weak var view: WKWebView? = nil

    /// Creates an HTML Item that can be shown in the CodeEditorUI
    /// - Parameters:
    ///   - title: Title to show on the tab
    ///   - path: Path of the item to browse, not visible, used to check if the document is opened
    ///   - content: The full HTML content to display
    ///   - anchor: An optional anchor to navigate to
    public init (title: String, path: String, content: String, anchor: String? = nil) {
        _title = title
        self.anchor = anchor
        super.init (path: path, content: content)
    }
}

#if os(macOS)
typealias UIViewRepresentable = NSViewRepresentable
#endif

struct WebView: UIViewRepresentable {
    var text: String
    var anchor: String?
    let obj: HtmlItem

    let loadUrl: (URL) -> String?

    init(text: String, anchor: String?, obj: HtmlItem, load: @escaping (URL) -> String?) {
        self.text = text
        self.anchor = anchor
        self.obj = obj
        self.loadUrl = load
    }

#if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: CGRect.zero, configuration: context.coordinator.configuration)
        view.isInspectable = true
        view.navigationDelegate = context.coordinator
        obj.view = view
        return view
    }
#else
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: CGRect.zero, configuration: context.coordinator.configuration)
        view.isInspectable = true
        view.isFindInteractionEnabled = true
        view.navigationDelegate = context.coordinator
        obj.view = view
        return view
    }
#endif

    func makeCoordinator() -> WebViewCoordinator {
        return WebViewCoordinator (parent: self, loadUrl: loadUrl)
    }

    class WebViewCoordinator: NSObject, WKNavigationDelegate, WKURLSchemeHandler {
        let configuration: WKWebViewConfiguration
        var parent: WebView?
        let loadUrl: (URL) -> String?

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            let request = urlSchemeTask.request

            // Extract information from the request
            guard let url = request.url else { return }
            if url.scheme == "open-external" {
                guard let externalUrl = URL (string: String (url.description.dropFirst(14))) else {
                    return
                }
#if os(macOS)
                NSWorkspace.shared.open(externalUrl)
#else
                UIApplication.shared.open(externalUrl, options: [:], completionHandler: nil)
#endif
                return
            }
            if let anchor = loadUrl (url) {
                webView.scrollTo (anchor)
            }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            //print ("End: \(urlSchemeTask)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let scrollY = parent?.savedScrollY {
                let js = "window.scrollTo(0, \(scrollY));"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        init (parent: WebView, loadUrl: @escaping (URL)->String?) {
            self.parent = parent
            configuration = WKWebViewConfiguration()
            self.loadUrl = loadUrl
            super.init ()
            configuration.setURLSchemeHandler(self, forURLScheme: "godot")
            configuration.setURLSchemeHandler(self, forURLScheme: "open-external")
        }
    }
    @State var savedScrollY: CGFloat?

#if os(macOS)
    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.evaluateJavaScript("window.scrollY") { result, error in
            if let scrollY = result as? CGFloat {
                if scrollY != 0 {
                    self.savedScrollY = scrollY
                }
            }
        }

        webView.loadHTMLString(text, baseURL: nil)
        if let anchor {
            webView.scrollTo (anchor)
        }
    }
#else
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.evaluateJavaScript("window.scrollY") { result, error in
            if let scrollY = result as? CGFloat {
                if scrollY != 0 {
                    self.savedScrollY = scrollY
                }
            }
        }

        webView.loadHTMLString(text, baseURL: nil)
        if let anchor {
            webView.scrollTo (anchor)
        }
    }
#endif
}

extension WKWebView {
    func scrollTo (_ anchor: String) {
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(1000))) {
            let str = "(function(){var el=document.getElementById('\(anchor)'); if(!el){return false;} el.scrollIntoView(); return true; })()"
            self.evaluateJavaScript(str) { ret, error in
                print ("ScrollRet: \(String(describing: ret))")
                print ("ScrollError: \(String(describing: error))")
            }
        }
    }
}
