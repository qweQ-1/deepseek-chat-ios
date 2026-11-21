import SafariServices
import SwiftUI
import UIKit
import WebKit

extension Notification.Name {
    /// 桌面图标快捷菜单 / 页面内按钮触发的原生设置
    static let deepSeekOpenSettings = Notification.Name("deepseekchat.openSettings")
}

/// 主界面：一块全屏 WKWebView，加载 App 内置的 DeepSeek 官方前端。
final class RootViewController: UIViewController {

    // MARK: - 子视图

    private let container = UIView()
    private var webView: WKWebView!
    private var bottomConstraint: NSLayoutConstraint!
    private var splashView: UIView?
    private var errorView: UIView?

    private var server: LocalStaticServer?
    private var didPresentSettingsForFirstRun = false
    private var isLoaded = false

    private var theme: AppTheme { AppSettings.theme }

    /// 当前实际是深色还是浅色（跟随系统时看真实 trait）
    private var resolvedDark: Bool { Theme.isDarkResolved(theme, traits: traitCollection) }

    private func applyNativeTheme() {
        let background = Theme.nativeBackground(theme, isDark: resolvedDark)
        view.backgroundColor = background
        overrideUserInterfaceStyle = Theme.userInterfaceStyle(theme)
        webView?.backgroundColor = .clear
        webView?.underPageBackgroundColor = background
        setNeedsStatusBarAppearanceUpdate()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        resolvedDark ? .lightContent : .darkContent
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if theme.mode == .system {
            applyNativeTheme()
        }
    }

    /// 设置页里调整外观后立刻生效，不用整页重载
    private func applyThemeLive(_ newTheme: AppTheme) {
        webView?.evaluateJavaScript(Theme.liveScript(newTheme), completionHandler: nil)
        applyNativeTheme()
    }

    // MARK: - 生命周期

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyNativeTheme()

        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        bottomConstraint = container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        // 顶部让开刘海 / 状态栏：官方前端只处理了 safe-area-bottom，
        // 全屏铺满时它自己的顶栏会压在状态栏下面，新建聊天、菜单那几个按钮就点不到了。
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,
        ])

        buildWebView()
        startServerAndLoad()

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenSettingsNotification),
            name: .deepSeekOpenSettings, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if AppDelegate.pendingOpenSettings {
            AppDelegate.pendingOpenSettings = false
            presentSettings(firstRun: false)
            return
        }
        if !AppSettings.isConfigured && !didPresentSettingsForFirstRun {
            didPresentSettingsForFirstRun = true
            presentSettings(firstRun: true)
        }
    }

    // MARK: - WebView

    private func buildWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.suppressesIncrementalRendering = false
        configuration.userContentController.addUserScript(
            PageInjector.userScript(apiKey: AppSettings.apiKey, model: AppSettings.model, theme: AppSettings.theme))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = true
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.underPageBackgroundColor = .systemBackground
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.webView = webView

        showSplash()
    }

    private func startServerAndLoad() {
        do {
            let server = try LocalStaticServer.start()
            self.server = server
            guard let origin = server.origin else {
                throw LocalStaticServer.ServerError.cannotStart("没有可用端口")
            }
            webView.load(URLRequest(url: origin))
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// 原生设置保存后：更新注入脚本并刷新，让新 Key / 模型立刻生效
    private func applySettingsAndReload() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            PageInjector.userScript(apiKey: AppSettings.apiKey, model: AppSettings.model, theme: AppSettings.theme))
        isLoaded = false
        showSplash()
        if let origin = server?.origin {
            webView.load(URLRequest(url: origin))
        } else {
            startServerAndLoad()
        }
    }

    // MARK: - 启动图 / 错误页

    private func showSplash() {
        errorView?.removeFromSuperview()
        errorView = nil
        guard splashView == nil else { return }

        let splash = UIView()
        splash.translatesAutoresizingMaskIntoConstraints = false
        splash.backgroundColor = AppSettings.theme.accentColor

        let icon = UIImageView(image: UIImage(named: "SplashMark") ?? UIImage(systemName: "bubble.left.and.text.bubble.right.fill"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 22
        icon.layer.cornerCurve = .continuous
        icon.clipsToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "DeepSeek"
        label.textColor = .white
        label.font = .systemFont(ofSize: 26, weight: .semibold)

        splash.addSubview(icon)
        splash.addSubview(label)
        view.addSubview(splash)
        NSLayoutConstraint.activate([
            splash.topAnchor.constraint(equalTo: view.topAnchor),
            splash.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splash.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splash.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            icon.centerXAnchor.constraint(equalTo: splash.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: splash.centerYAnchor, constant: -28),
            icon.widthAnchor.constraint(equalToConstant: 96),
            icon.heightAnchor.constraint(equalToConstant: 96),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 18),
            label.centerXAnchor.constraint(equalTo: splash.centerXAnchor),
        ])
        splashView = splash
    }

    private func hideSplash() {
        guard let splash = splashView else { return }
        splashView = nil
        UIView.animate(withDuration: 0.25, animations: { splash.alpha = 0 }) { _ in
            splash.removeFromSuperview()
        }
    }

    private func showError(_ message: String) {
        hideSplash()
        errorView?.removeFromSuperview()

        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.backgroundColor = .systemBackground

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .callout)
        label.text = "页面加载失败\n\(message)"

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("重试", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)

        wrapper.addSubview(label)
        wrapper.addSubview(button)
        view.addSubview(wrapper)
        NSLayoutConstraint.activate([
            wrapper.topAnchor.constraint(equalTo: view.topAnchor),
            wrapper.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            wrapper.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wrapper.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -32),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 20),
            button.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
        ])
        errorView = wrapper
    }

    @objc private func retryLoading() {
        errorView?.removeFromSuperview()
        errorView = nil
        showSplash()
        startServerAndLoad()
    }

    // MARK: - 键盘

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        bottomConstraint.constant = -overlap
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide() {
        bottomConstraint.constant = 0
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - 原生设置

    @objc private func handleOpenSettingsNotification() {
        presentSettings(firstRun: false)
    }

    private func presentSettings(firstRun: Bool) {
        let root = SettingsView(
            apiKey: AppSettings.apiKey ?? "",
            model: AppSettings.model,
            models: AppSettings.knownModels,
            theme: AppSettings.theme,
            firstRun: firstRun,
            onThemeChange: { [weak self] theme in
                AppSettings.theme = theme
                self?.applyThemeLive(theme)
            },
            onImport: { [weak self] in
                guard let self else { return }
                self.dismiss(animated: true) { self.presentImport() }
            },
            onSave: { [weak self] key, model in
                guard let self else { return }
                AppSettings.apiKey = key
                AppSettings.model = model
                AppSettings.onboarded = true
                self.dismiss(animated: true) {
                    self.applySettingsAndReload()
                }
            },
            onCancel: { [weak self] in
                guard let self else { return }
                AppSettings.onboarded = true
                self.dismiss(animated: true)
            },
            onModelsLoaded: { models in
                AppSettings.knownModels = models
            })

        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        if #available(iOS 15.0, *) {
            if let sheet = host.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 20
            }
        }
        host.isModalInPresentation = firstRun
        present(host, animated: true)
    }

    // MARK: - 从官网导入

    private func presentImport() {
        let controller = ImportViewController()
        controller.configure { [weak self] payload in
            self?.handleImportPayload(payload)
        }
        let navigation = UINavigationController(rootViewController: controller)
        present(navigation, animated: true)
    }

    private func handleImportPayload(_ payload: String) {
        showSplash()
        webView.evaluateJavaScript(DeepSeekImport.writeScript(payload: payload)) { [weak self] result, error in
            guard let self else { return }
            var message = "导入完成"
            if let text = result as? String,
               let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if (json["ok"] as? Bool) == true {
                    let count = json["count"] as? Int ?? 0
                    message = count > 0 ? "已导入 \(count) 个会话" : "官网没有可导入的会话"
                } else {
                    message = (json["error"] as? String) ?? "写入本地数据库失败"
                }
            } else if let error {
                message = error.localizedDescription
            }
            self.applySettingsAndReload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let alert = UIAlertController(title: "导入结果", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    // MARK: - 打开链接

    private func openExternally(_ url: URL) {
        guard let scheme = url.scheme?.lowercased() else { return }
        if scheme == "http" || scheme == "https" {
            let safari = SFSafariViewController(url: url)
            safari.preferredControlTintColor = AppSettings.theme.accentColor
            present(safari, animated: true)
        } else if scheme != "about" && scheme != "javascript" {
            UIApplication.shared.open(url)
        }
    }

    private func isInternal(_ url: URL) -> Bool {
        if url.scheme == "about" { return true }
        guard let port = server?.port else { return false }
        return url.host == "127.0.0.1" && url.port == Int(port)
    }
}

// MARK: - WKNavigationDelegate

extension RootViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        hideSplash()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        showError(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        showError(error.localizedDescription)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if isInternal(url) {
            decisionHandler(.allow)
            return
        }
        // 语音录音、麦克风等权限弹窗由页面内的浏览器授权流程处理，这里不拦截
        if url.scheme == "http" || url.scheme == "https" {
            decisionHandler(.cancel)
            openExternally(url)
            return
        }
        if url.scheme == "blob" || url.scheme == "data" || url.scheme == "about" || url.scheme == "javascript" {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        openExternally(url)
    }
}

// MARK: - WKUIDelegate

extension RootViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if isInternal(url) {
                webView.load(navigationAction.request)
            } else {
                openExternally(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // 语音输入只有麦克风；这里一并放行摄像头（拍照上传场景）
        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}
