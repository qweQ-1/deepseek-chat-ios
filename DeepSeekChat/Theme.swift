import SwiftUI
import UIKit

/// 用户可自定义的外观：明暗模式、主题色、字号、背景着色。
///
/// 页面（官方 chat-demo）用一整套 CSS 变量描述颜色，所以「换肤」不需要改产物，
/// 只要在页面里覆盖几个 `--dsw-alias-*` 变量即可，刷新也不会丢。
struct AppTheme: Codable, Equatable {

    enum Mode: String, Codable, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }

        var isDark: Bool { self == .dark }
    }

    var mode: Mode = .system
    var accentHex: String = AppTheme.palette[0]
    /// 100 = 原尺寸；90/110/120 为缩放百分比
    var fontScale: Int = 100
    /// 把主题色淡淡地混进页面底色
    var tintBackground: Bool = false

    static let palette: [String] = [
        "#4D6BFE", // DeepSeek 蓝
        "#7C5CFF", // 紫
        "#00A5A5", // 青
        "#12A150", // 绿
        "#E8791E", // 橙
        "#E0407B", // 粉
    ]

    static let fontScales: [Int] = [90, 100, 110, 120]
    static let `default` = AppTheme()

    var accentColor: UIColor {
        Theme.color(hex: accentHex) ?? Theme.color(hex: AppTheme.palette[0]) ?? .systemBlue
    }
}

/// 颜色工具 + 注入页面的 CSS/JS 生成
enum Theme {

    // MARK: - 颜色

    static func color(hex: String) -> UIColor? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: 1)
    }

    static func hex(from color: Color) -> String {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return AppTheme.palette[0]
        }
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }

    private static func components(_ hex: String) -> (CGFloat, CGFloat, CGFloat)? {
        guard let c = color(hex: hex) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard c.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (r, g, b)
    }

    private static func toHex(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> String {
        String(format: "#%02X%02X%02X",
               Int(round(min(max(r, 0), 1) * 255)),
               Int(round(min(max(g, 0), 1) * 255)),
               Int(round(min(max(b, 0), 1) * 255)))
    }

    /// 把 hex 按比例混到另一个底色上
    static func blend(_ hex: String, over base: String, ratio: CGFloat) -> String {
        guard let fg = components(hex), let bg = components(base) else { return base }
        let k = min(max(ratio, 0), 1)
        return toHex(fg.0 * k + bg.0 * (1 - k),
                     fg.1 * k + bg.1 * (1 - k),
                     fg.2 * k + bg.2 * (1 - k))
    }

    /// 向白色靠拢
    static func lighten(_ hex: String, _ amount: CGFloat) -> String {
        blend("#FFFFFF", over: hex, ratio: min(max(amount, 0), 1))
    }

    /// 向黑色靠拢
    static func darken(_ hex: String, _ amount: CGFloat) -> String {
        blend("#000000", over: hex, ratio: min(max(amount, 0), 1))
    }

    // MARK: - 原生侧配色

    /// 页面外那圈底色（状态栏区域、键盘弹起时的空白）
    static func nativeBackground(_ theme: AppTheme, isDark dark: Bool) -> UIColor {
        if theme.tintBackground {
            let hex = dark
                ? blend(theme.accentHex, over: "#0E0F12", ratio: 0.16)
                : blend(theme.accentHex, over: "#FFFFFF", ratio: 0.055)
            return color(hex: hex) ?? (dark ? .black : .white)
        }
        return dark ? color(hex: "#0E0F12") ?? .black : .white
    }

    /// 跟随系统时按当前系统外观判断
    static func isDarkResolved(_ theme: AppTheme, traits: UITraitCollection) -> Bool {
        switch theme.mode {
        case .dark: return true
        case .light: return false
        case .system:
            return traits.userInterfaceStyle == .dark
        }
    }

    static func userInterfaceStyle(_ theme: AppTheme) -> UIUserInterfaceStyle {
        switch theme.mode {
        case .dark: return .dark
        case .light: return .light
        case .system: return .unspecified
        }
    }

    // MARK: - CSS

    /// 覆盖官方页面的设计变量。用 `!important` 保证压过产物里的同名声明。
    static func css(_ theme: AppTheme) -> String {
        let accent = theme.accentHex
        // 文字用的主题色：浅色底上压深一点、深色底上提亮一点，保证可读
        let textOnLight = darken(accent, 0.12)
        let textOnDark = lighten(accent, 0.32)

        var rules: [String] = []
        rules.append("""
        :root, [data-ds-dark-theme] {
          --dsw-alias-brand-primary: \(accent) !important;
          --dsw-alias-button-primary-fill: \(accent) !important;
        }
        """)
        rules.append(":root { --dsw-alias-brand-text: \(textOnLight) !important; }")
        rules.append("[data-ds-dark-theme] { --dsw-alias-brand-text: \(textOnDark) !important; }")

        if theme.tintBackground {
            let light = blend(accent, over: "#FFFFFF", ratio: 0.055)
            let dark = blend(accent, over: "#0E0F12", ratio: 0.16)
            rules.append("""
            :root { --dsw-alias-bg-base: \(light) !important; }
            [data-ds-dark-theme] { --dsw-alias-bg-base: \(dark) !important; }
            """)
        }

        if theme.fontScale != 100 {
            rules.append("html, body { -webkit-text-size-adjust: \(theme.fontScale)% !important; }")
        }

        return rules.joined(separator: "\n")
    }

    // MARK: - 注入脚本

    /// 页面加载前执行：接管 `prefers-color-scheme`，并准备好样式容器。
    /// 必须在页面脚本之前跑，否则 React 首帧会按系统外观渲染。
    static func bootstrapScript(_ theme: AppTheme) -> String {
        let cssLiteral = jsString(css(theme))
        let modeLiteral = jsString(theme.mode.rawValue)
        return """
        (function () {
          try {
            if (!window.__dsTheme) {
              var state = { scheme: 'system' };
              var subscribers = [];
              var original = window.matchMedia ? window.matchMedia.bind(window) : null;

              window.__dsTheme = {
                apply: function (css, scheme) {
                  var id = 'ds-native-theme';
                  var el = document.getElementById(id);
                  if (!el) {
                    el = document.createElement('style');
                    el.id = id;
                  }
                  el.textContent = css;
                  (document.head || document.documentElement).appendChild(el);

                  state.scheme = scheme || 'system';
                  var root = document.documentElement;
                  if (state.scheme === 'dark') {
                    root.setAttribute('data-ds-dark-theme', 'dark');
                  } else if (state.scheme === 'light') {
                    root.removeAttribute('data-ds-dark-theme');
                  }
                  // 通知页面自己挂的监听，让它重新取色
                  for (var i = 0; i < subscribers.length; i++) {
                    try {
                      var wantDark = subscribers[i].wantDark;
                      var isDark = state.scheme === 'dark';
                      if (state.scheme === 'system' && original) {
                        isDark = original('(prefers-color-scheme: dark)').matches;
                      }
                      subscribers[i].fn({ matches: wantDark ? isDark : !isDark, media: subscribers[i].media });
                    } catch (e) {}
                  }
                }
              };

              if (original) {
                window.matchMedia = function (query) {
                  if (typeof query !== 'string' || query.indexOf('prefers-color-scheme') === -1) {
                    return original(query);
                  }
                  var wantDark = query.indexOf('dark') !== -1;
                  var real = original(query);
                  var fake = {
                    media: query,
                    onchange: null,
                    addEventListener: function (type, fn) {
                      if (type === 'change' && typeof fn === 'function') {
                        subscribers.push({ fn: fn, wantDark: wantDark, media: query });
                      }
                    },
                    removeEventListener: function (type, fn) {
                      subscribers = subscribers.filter(function (item) { return item.fn !== fn; });
                    },
                    addListener: function (fn) {
                      if (typeof fn === 'function') {
                        subscribers.push({ fn: fn, wantDark: wantDark, media: query });
                      }
                    },
                    removeListener: function (fn) {
                      subscribers = subscribers.filter(function (item) { return item.fn !== fn; });
                    },
                    dispatchEvent: function () { return false; }
                  };
                  Object.defineProperty(fake, 'matches', {
                    get: function () {
                      if (state.scheme === 'dark') { return wantDark; }
                      if (state.scheme === 'light') { return !wantDark; }
                      return real.matches;
                    }
                  });
                  return fake;
                };
              }
            }

            function paint() {
              window.__dsTheme.apply(\(cssLiteral), \(modeLiteral));
            }
            paint();
            document.addEventListener('DOMContentLoaded', paint);
            window.addEventListener('load', paint);
          } catch (e) {}
        })();
        """
    }

    /// 设置页里改一下就立刻生效，不用整页重载
    static func liveScript(_ theme: AppTheme) -> String {
        "(function(){try{window.__dsTheme.apply(\(jsString(css(theme))), \(jsString(theme.mode.rawValue)));}catch(e){} return true;})()"
    }

    /// 把 Swift 字符串变成合法的 JS 字符串字面量
    static func jsString(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value])) ?? Data()
        guard var text = String(data: data, encoding: .utf8), text.count >= 2 else { return "\"\"" }
        text.removeFirst()
        text.removeLast()
        return text.isEmpty ? "\"\"" : text
    }
}
