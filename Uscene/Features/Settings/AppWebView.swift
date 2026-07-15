import SwiftUI
import WebKit

struct AppWebView: View {
    let title: String
    let url: URL

    var body: some View {
        WebViewRepresentable(url: url)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
