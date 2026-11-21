import UIKit
import WebKit

/// 登录 DeepSeek 官网 → 一键把历史会话导入本机前端。
///
/// 之所以专门开一个 WebView，而不是纯 HTTP 请求：
/// 官方 web 接口的风控（PoW、cookie、同源校验）都绑在页面环境里，
/// 让请求从页面自己发出去最稳，也不需要我们自己复刻签名算法。
final class ImportViewController: UIViewController {

    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WKScriptMessageHandler?

        init(target: WKScriptMessageHandler) {
            self.target = target
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            target?.userContentController(controller, didReceive: message)
        }
    }

    private let webView: WKWebView
    private let statusLabel = UILabel()
    private lazy var importItem = UIBarButtonItem(
        title: "导入", style: .done, target: self, action: #selector(startImport))

    private var loginTimer: Timer?
    private var isImporting = false
    private var onFinished: ((String) -> Void)?

    /// 导入完成回调，参数是 harvest 返回的 JSON 原文
    func configure(onFinished: @escaping (String) -> Void) {
        self.onFinished = onFinished
    }

    init() {
        let controller = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        controller.add(WeakHandler(target: self), name: "dsProgress")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loginTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        title = "登录 DeepSeek 官网"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = importItem
        importItem.isEnabled = false

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 2
        statusLabel.text = "在这里登录（短信 / 扫码都行），登录后点右上角「导入」"

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        view.addSubview(statusLabel)
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        if let url = URL(string: "https://chat.deepseek.com/sign_in") {
            webView.load(URLRequest(url: url))
        }

        loginTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshLoginState()
        }
    }

    // MARK: - 登录探测

    private func refreshLoginState() {
        guard !isImporting else { return }
        webView.evaluateJavaScript(DeepSeekImport.loginCheckScript) { [weak self] result, _ in
            guard let self else { return }
            let loggedIn = (result as? Bool) ?? (result as? NSNumber)?.boolValue ?? false
            if loggedIn {
                self.loginTimer?.invalidate()
                self.loginTimer = nil
                self.importItem.isEnabled = true
                if self.statusLabel.text?.hasPrefix("在这里登录") == true {
                    self.statusLabel.text = "已登录，可以点右上角「导入」了（只导入会话，不改动官网数据）"
                }
            }
        }
    }

    // MARK: - 导入

    @objc private func startImport() {
        guard !isImporting else { return }
        isImporting = true
        importItem.isEnabled = false
        statusLabel.text = "正在读取官网会话…"

        webView.evaluateJavaScript(DeepSeekImport.harvestScript()) { [weak self] result, error in
            guard let self else { return }
            self.isImporting = false
            if let error {
                self.fail("读取失败：\(error.localizedDescription)")
                return
            }
            guard let payload = result as? String else {
                self.fail("官网没有返回可识别的数据")
                return
            }
            let parsed = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any]
            let ok = parsed?["ok"] as? Bool ?? false
            if ok {
                let count = (parsed?["sessions"] as? [Any])?.count ?? 0
                self.statusLabel.text = "读取到 \(count) 个会话，正在写入…"
                self.onFinished?(payload)
                self.dismiss(animated: true)
            } else {
                let message = parsed?["error"] as? String ?? "读取失败"
                self.fail(message)
            }
        }
    }

    private func fail(_ message: String) {
        importItem.isEnabled = true
        statusLabel.text = message
        let alert = UIAlertController(title: "没能导入", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }
}

extension ImportViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshLoginState()
    }
}

extension ImportViewController: WKScriptMessageHandler {

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        statusLabel.text = text
    }
}
