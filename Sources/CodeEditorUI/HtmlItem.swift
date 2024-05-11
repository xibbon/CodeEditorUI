//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 5/11/24.
//

import Foundation
import SwiftUI
import WebKit

public class HtmlItem: HostedItem {
    let _title: String
    public override var title: String { _title }
    
    public init (title: String, path: String, content: String) {
        _title = title
        super.init (path: path, content: content)
    }
}

struct WebView: UIViewRepresentable {
    @Binding var text: String
    let loadUrl: (URL) -> String?
    
    init(text: Binding<String>, load: @escaping (URL) -> String?) {
        _text = text
        self.loadUrl = load
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: CGRect.zero, configuration: context.coordinator.configuration)
        view.isInspectable = true
        view.navigationDelegate = context.coordinator
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
                DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .seconds(1))) {
                    let str = "document.getElementById ('a-\(anchor)').scrollIntoView()"
                    webView.evaluateJavaScript(str) { ret, error in
                        print ("ScrollRet: \(ret)")
                        print ("ScrollError: \(error)")
                    }
                }
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
    }
}
