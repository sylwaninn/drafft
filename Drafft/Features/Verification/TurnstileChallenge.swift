import SwiftUI
import WebKit

/// Cloudflare Turnstile for the support form sent signed out: the widget runs in a web view the person
/// never sees, and hands back a single-use token the backend `support` verifies. Only when Cloudflare
/// wants an interaction does the web view show, in its own sheet. The page is loaded as getdrafft.com,
/// the domain the site key allows.
@MainActor @Observable
final class TurnstileChallenge {
    /// Ready to send; nil while the widget works, after a send, or once it expired.
    private(set) var token: String?
    /// Cloudflare wants the person to tick the box: the web view shows in a sheet.
    var needsInteraction = false
    /// The widget itself failed (no network, blocked): the form says so.
    private(set) var failed = false

    let webView: WKWebView
    private var started = false

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 80), configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
    }

    /// Loads the widget once; later calls do nothing.
    func start() {
        guard !started else { return }
        started = true
        webView.configuration.userContentController.add(WeakMessageHandler(self), name: "turnstile")
        webView.loadHTMLString(Self.page(siteKey: BackendConfig.turnstileSiteKey),
                               baseURL: URL(string: "https://getdrafft.com"))
    }

    /// A token works once: drop it and ask for a new one (after each send, or when the server refused it).
    func renew() {
        token = nil
        failed = false
        guard started else { return start() }
        webView.evaluateJavaScript("window.renew && window.renew()")
    }

    /// Frees the web view: no handler left to keep this object alive.
    func stop() {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "turnstile")
        webView.loadHTMLString("", baseURL: nil)
        token = nil
        started = false
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        if let value = message["token"] as? String, !value.isEmpty {
            // Turnstile retries on its own after an error: a token means it recovered.
            token = value
            failed = false
            needsInteraction = false
        } else if message["expired"] != nil {
            token = nil
        } else if message["interactive"] != nil {
            needsInteraction = true
        } else if message["interactiveDone"] != nil {
            needsInteraction = false
        } else if message["error"] != nil {
            token = nil
            failed = true
            needsInteraction = false
        }
    }

    private static func page(siteKey: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:transparent}#w{display:flex;justify-content:center}</style>
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit&onload=ready" async defer></script>
        </head><body><div id="w"></div><script>
        function post(m){window.webkit.messageHandlers.turnstile.postMessage(m)}
        var id=null;
        function ready(){id=turnstile.render('#w',{sitekey:'\(siteKey)',appearance:'interaction-only',
          'refresh-expired':'auto',
          callback:function(t){post({token:t})},
          'expired-callback':function(){post({expired:true})},
          'error-callback':function(c){post({error:String(c)})},
          'before-interactive-callback':function(){post({interactive:true})},
          'after-interactive-callback':function(){post({interactiveDone:true})}})}
        window.renew=function(){if(id!==null){turnstile.reset(id)}};
        </script></body></html>
        """
    }
}

/// WKUserContentController keeps its handlers strongly: this one only points back weakly.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: TurnstileChallenge?
    init(_ target: TurnstileChallenge) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated { target?.receive(body) }
    }
}

/// The widget's web view, placed in SwiftUI (hidden in the form, visible in the check sheet).
struct TurnstileView: UIViewRepresentable {
    let challenge: TurnstileChallenge
    func makeUIView(context: Context) -> WKWebView { challenge.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

/// The rare interactive check, in its own sheet.
struct TurnstileSheet: View {
    let challenge: TurnstileChallenge

    var body: some View {
        SheetBlock(title: L("Quick security check")) {
            TurnstileView(challenge: challenge)
                .frame(height: 80)
                .frame(maxWidth: .infinity)
        }
        .padding(DS.Space.lg)
        .presentationDetents([.height(220)])
    }
}
