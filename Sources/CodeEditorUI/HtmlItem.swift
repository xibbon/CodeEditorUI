//
//  HtmlItem.swift
//
//
//  Created by Miguel de Icaza on 5/11/24.
//

import Foundation
import SwiftUI
import WebKit

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

struct WebView: UIViewRepresentable {
    @Binding var text: String
    @Binding var anchor: String?
    let obj: HtmlItem

    let loadUrl: (URL) -> String?

    init(text: Binding<String>, anchor: Binding<String?>, obj: HtmlItem, load: @escaping (URL) -> String?) {
        _text = text
        _anchor = anchor
        self.obj = obj
        self.loadUrl = load
    }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: CGRect.zero, configuration: context.coordinator.configuration)
        view.isInspectable = true
        view.navigationDelegate = context.coordinator
        obj.view = view
        return view
    }

    func makeCoordinator() -> WebViewCoordinator {
        return WebViewCoordinator (loadUrl: loadUrl)
    }

    class WebViewCoordinator: NSObject, WKNavigationDelegate, WKURLSchemeHandler {
        let configuration: WKWebViewConfiguration
        let loadUrl: (URL) -> String?

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            guard let request = urlSchemeTask.request as? URLRequest else {
                urlSchemeTask.didFailWithError(NSError(domain: "Godot", code: -1, userInfo: nil))
                return
            }

            // Extract information from the request
            guard let url = urlSchemeTask.request.url else { return }
            if url.scheme == "open-external" {
                guard let externalUrl = URL (string: String (url.description.dropFirst(14))) else {
                    return
                }
                UIApplication.shared.open(externalUrl, options: [:], completionHandler: nil)
                return
            }
            if let anchor = loadUrl (url) {
                webView.scrollTo (anchor)
            }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            //print ("End: \(urlSchemeTask)")
        }

        init (loadUrl: @escaping (URL)->String?) {
            configuration = WKWebViewConfiguration()
            self.loadUrl = loadUrl
            super.init ()
            configuration.setURLSchemeHandler(self, forURLScheme: "godot")
            configuration.setURLSchemeHandler(self, forURLScheme: "open-external")
        }
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(text, baseURL: nil)
        if let anchor {
            webView.scrollTo (anchor)
        }
    }
}

extension WKWebView {
    func scrollTo (_ anchor: String) {
        DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(1000))) {
            let str = "document.getElementById ('\(anchor)').scrollIntoView()"
            self.evaluateJavaScript(str) { ret, error in
                print ("ScrollRet: \(ret)")
                print ("ScrollError: \(error)")
            }
        }
    }
}
