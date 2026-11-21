# DeepSeek Chat iOS

把 DeepSeek 官方开源的前端 [deepseek-ai/chat-demo](https://github.com/deepseek-ai/chat-demo)（MIT）
封装成 iOS App，聊天请求由本机直连 `https://api.deepseek.com`，不经过任何中间服务器。

- 前端产物：官方 Release `v0.1.3`（`Web/` 目录，未改动一行代码）
- 原生外壳：Swift + WKWebView，内置回环静态服务器
- 首次启动在原生页面填自己的 API Key，之后也可在页面内「设置」里改

## 为什么要有原生外壳

| 问题 | 处理 |
| --- | --- |
| `file://` 源下 WebKit 限制 localStorage / IndexedDB，官方前端把会话存在 IndexedDB | App 内起 `127.0.0.1:47823` 静态服务，origin 固定，历史记录不会丢 |
| 官方前端的 `viewport` 没带 `viewport-fit=cover` | 注入脚本补上，`env(safe-area-inset-*)` 才能在全面屏生效 |
| 页面把模型名 `deepseek-flash` 编译进产物 | 拦截 `fetch` 改写 `body.model`，原生设置里可切 `deepseek-v4-pro` |
| 键盘弹出时 WKWebView 不自动让位 | 原生监听键盘、收缩 WebView 高度，页面按 `visualViewport` 自行排版 |
| 语音输入 | 实现 `WKUIDelegate` 的媒体采集授权，放行麦克风 |

## 结构

```
DeepSeekChat/            原生外壳
  LocalStaticServer.swift  回环静态文件服务器（含 Range / SPA 回落）
  PageInjector.swift       注入 API Key、模型名、viewport
  RootViewController.swift WKWebView + 键盘 + 外链 + 原生设置入口
  SettingsView.swift       SwiftUI 设置页（Key / 模型 / 校验）
  ApiClient.swift          GET /models 校验 Key
Web/                     官方前端产物（v0.1.3）
Tools/make_icons.py      图标生成（只在 CI 跑）
```

## 构建

`xcodegen generate` 后 `xcodebuild archive`，CI 见 `.github/workflows/unsigned-ipa.yml`。
产物为未签名 IPA，需要 AltStore / Sideloadly / 轻松签 等工具用免费 Apple ID 自签。

## 许可

原生外壳代码 MIT。内置前端来自 deepseek-ai/chat-demo，同样 MIT，许可证随包附带（`Web/LICENSE`）。
本项目与 DeepSeek 官方无隶属关系。
