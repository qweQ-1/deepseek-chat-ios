import Foundation
import WebKit

/// 把原生设置注入到官方前端页面里。
///
/// 只做三件官方页面本身没提供的事：
/// 1. 预填 API Key（页面读的是 localStorage `chat-demo:api-key`）。
/// 2. 允许覆盖模型名（页面把 `deepseek-flash` 编译进了产物，拦截 fetch 改写 body.model）。
/// 3. 补上 `viewport-fit=cover`，让页面的 `env(safe-area-inset-*)` 在全面屏上生效。
enum PageInjector {

    static func userScript(apiKey: String?, model: String, theme: AppTheme) -> WKUserScript {
        let keyLiteral = jsString(apiKey)
        let modelLiteral = jsString(model)
        let source = """
        \(Theme.bootstrapScript(theme))
        (function () {
          try {
            var KEY = \(keyLiteral);
            var MODEL = \(modelLiteral);
            if (KEY) {
              localStorage.setItem('chat-demo:api-key', KEY);
            }
            if (!localStorage.getItem('chat-demo:locale')) {
              var lang = (navigator.language || 'zh').toLowerCase();
              localStorage.setItem('chat-demo:locale', lang.indexOf('zh') === 0 ? 'zh-CN' : 'en-US');
            }
            window.__DS_NATIVE__ = true;
            window.__DS_MODEL__ = MODEL || null;

            if (!window.__dsFetchPatched) {
              window.__dsFetchPatched = true;
              var originalFetch = window.fetch;
              window.fetch = function (input, init) {
                try {
                  var url = typeof input === 'string' ? input : (input && input.url) || '';
                  if (window.__DS_MODEL__ && url.indexOf('/anthropic/v1/messages') !== -1 &&
                      init && typeof init.body === 'string') {
                    var body = JSON.parse(init.body);
                    if (body && typeof body === 'object') {
                      body.model = window.__DS_MODEL__;
                      init = Object.assign({}, init, { body: JSON.stringify(body) });
                    }
                  }
                } catch (e) {}
                return originalFetch.call(window, input, init);
              };
            }

            function patchViewport() {
              var meta = document.querySelector('meta[name="viewport"]');
              if (meta) {
                meta.setAttribute('content', 'width=device-width,initial-scale=1,viewport-fit=cover');
              }
              document.documentElement.style.webkitTextSizeAdjust = '100%';
            }
            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', patchViewport);
            } else {
              patchViewport();
            }
          } catch (e) {}
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// 运行期切换模型（原生设置保存后调用）
    static func applyModelScript(model: String) -> String {
        "window.__DS_MODEL__ = \(jsString(model)); true;"
    }

    private static func jsString(_ value: String?) -> String {
        guard let value else { return "null" }
        let data = try? JSONSerialization.data(withJSONObject: [value])
        guard let data, var text = String(data: data, encoding: .utf8) else { return "null" }
        // JSONSerialization 产出 ["..."]，去掉外层方括号就是合法的 JS 字符串字面量
        text.removeFirst()
        text.removeLast()
        if text == "" { return "null" }
        return text
    }
}
