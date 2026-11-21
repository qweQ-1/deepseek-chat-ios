import Foundation

/// 把 DeepSeek 官网（chat.deepseek.com）的历史会话导入本机前端。
///
/// 两个阶段，都跑在 WebView 里：
/// 1. `harvestScript`：在**已登录官网**的页面里带 cookie + Bearer 调 web 接口，
///    翻页取会话列表，再逐个取消息，最后返回一段 JSON。
/// 2. `writeScript`：在主页面（本地前端）里把 JSON 写进它自己的 IndexedDB
///    （库 `chat-demo`，表 `sessions` / `sessionSummaries`），刷新后就能看到。
///
/// 这样不依赖官方 API 的 PoW 签名实现：请求由官网页面自己发出，签名/风控都由页面所在环境处理。
enum DeepSeekImport {

    /// 单次导入的会话上限，避免一次拉太多把内存顶爆
    static let sessionLimit = 200

    static func harvestScript() -> String {
        """
        (async function () {
          var post = function (text) {
            try { window.webkit.messageHandlers.dsProgress.postMessage(text); } catch (e) {}
          };
          var toMs = function (value) {
            var n = Number(value);
            if (!n || isNaN(n)) { return Date.now(); }
            return n > 1e12 ? Math.round(n) : Math.round(n * 1000);
          };
          var readToken = function () {
            var keys = ['userToken', 'user_token', 'token'];
            for (var i = 0; i < keys.length; i++) {
              try {
                var raw = localStorage.getItem(keys[i]);
                if (!raw) { continue; }
                try {
                  var parsed = JSON.parse(raw);
                  var value = parsed && (parsed.value || parsed.token || parsed.access_token);
                  if (value) { return value; }
                } catch (e) {}
                if (raw.length > 10) { return raw; }
              } catch (e) {}
            }
            return null;
          };

          var token = readToken();
          if (!token) {
            return JSON.stringify({ ok: false, error: '还没登录：请先在这个页面里登录 DeepSeek 官网' });
          }

          var headers = { 'authorization': 'Bearer ' + token, 'accept': '*/*' };
          var get = async function (path) {
            var response = await fetch(path, { headers: headers, credentials: 'include' });
            var text = await response.text();
            var json = null;
            try { json = JSON.parse(text); } catch (e) {}
            return { status: response.status, json: json, snippet: text.slice(0, 200) };
          };

          var sessions = [];
          var cursor = null;
          var hasMore = true;
          var page = 0;
          while (hasMore && page < 40 && sessions.length < \(sessionLimit)) {
            page++;
            var url = '/api/v0/chat_session/fetch_page?count=100' +
              (cursor === null ? '' : '&lte_cursor=' + encodeURIComponent(cursor));
            var res = await get(url);
            var json = res.json;
            if (!json || json.code !== 0) {
              var detail = json ? ('code=' + json.code + ' ' + (json.msg || '')) : res.snippet;
              return JSON.stringify({
                ok: false,
                error: '读取会话列表失败（HTTP ' + res.status + '）：' + detail
              });
            }
            var biz = (json.data && (json.data.biz_data || json.data)) || {};
            var list = biz.chat_sessions || biz.sessions || [];
            for (var i = 0; i < list.length; i++) {
              var item = list[i];
              sessions.push({
                id: item.id,
                title: item.title || '未命名对话',
                createdAt: toMs(item.created_at),
                updatedAt: toMs(item.updated_at || item.created_at)
              });
            }
            hasMore = !!biz.has_more;
            if (!list.length) { break; }
            cursor = list[list.length - 1].created_at;
            post('已找到 ' + sessions.length + ' 个会话…');
          }

          var output = [];
          for (var index = 0; index < sessions.length; index++) {
            var session = sessions[index];
            post('读取 ' + (index + 1) + '/' + sessions.length + '：' + session.title);
            var history = await get('/api/v0/chat/history_messages?chat_session_id=' +
              encodeURIComponent(session.id));
            var payload = history.json;
            if (!payload || payload.code !== 0) { continue; }
            var body = (payload.data && (payload.data.biz_data || payload.data)) || {};
            var rawMessages = body.chat_messages || body.messages || [];
            var messages = [];
            for (var j = 0; j < rawMessages.length; j++) {
              var message = rawMessages[j];
              var isUser = String(message.role || '').toLowerCase() === 'user';
              var content = typeof message.content === 'string' ? message.content : '';
              var thinking = typeof message.thinking_content === 'string' ? message.thinking_content : '';
              if (!content && !thinking) { continue; }
              messages.push({
                role: isUser ? 'user' : 'assistant',
                content: content,
                thinking: thinking,
                createdAt: toMs(message.inserted_at)
              });
            }
            output.push({
              id: 'ds-' + session.id,
              title: session.title,
              createdAt: session.createdAt,
              updatedAt: session.updatedAt,
              messages: messages
            });
            await new Promise(function (resolve) { setTimeout(resolve, 120); });
          }

          post('完成，共 ' + output.length + ' 个会话');
          return JSON.stringify({ ok: true, sessions: output });
        })()
        """
    }

    /// 在主页面里写库。payload 是 harvest 返回的那段 JSON 原文。
    static func writeScript(payload: String) -> String {
        let literal = Theme.jsString(payload)
        return """
        (async function () {
          try {
            var data = JSON.parse(\(literal));
            var list = (data && data.sessions) || [];
            if (!data.ok) { return JSON.stringify({ ok: false, error: data.error || '导入失败' }); }
            if (!list.length) { return JSON.stringify({ ok: true, count: 0 }); }

            var db = await new Promise(function (resolve, reject) {
              var request = indexedDB.open('chat-demo');
              request.onsuccess = function () { resolve(request.result); };
              request.onerror = function () { reject(request.error); };
            });
            if (!db.objectStoreNames.contains('sessions') || !db.objectStoreNames.contains('sessionSummaries')) {
              return JSON.stringify({ ok: false, error: '页面数据库还没初始化，请先重新打开 App 再试' });
            }

            var tx = db.transaction(['sessions', 'sessionSummaries'], 'readwrite');
            var store = tx.objectStore('sessions');
            var summaries = tx.objectStore('sessionSummaries');
            var stamp = Date.now().toString(36);

            for (var i = 0; i < list.length; i++) {
              var session = list[i];
              var messages = [];
              for (var k = 0; k < session.messages.length; k++) {
                var message = session.messages[k];
                var mid = session.id + '-' + k + '-' + stamp;
                if (message.role === 'user') {
                  messages.push({
                    id: mid, role: 'user', content: message.content,
                    files: [], createdAt: message.createdAt
                  });
                } else {
                  var blocks = [];
                  if (message.thinking) { blocks.push({ type: 'thinking', thinking: message.thinking }); }
                  if (message.content) { blocks.push({ type: 'text', text: message.content }); }
                  if (!blocks.length) { continue; }
                  messages.push({
                    id: mid, role: 'assistant', createdAt: message.createdAt,
                    model: null, prefix: false, status: 'done', blocks: blocks
                  });
                }
              }
              store.put({
                id: session.id, title: session.title,
                createdAt: session.createdAt, updatedAt: session.updatedAt,
                messages: messages, rootMessageId: null
              });
              summaries.put({
                id: session.id, title: session.title,
                createdAt: session.createdAt, updatedAt: session.updatedAt,
                fileIds: []
              });
            }

            await new Promise(function (resolve, reject) {
              tx.oncomplete = function () { resolve(); };
              tx.onerror = function () { reject(tx.error); };
              tx.onabort = function () { reject(tx.error); };
            });
            db.close();
            return JSON.stringify({ ok: true, count: list.length });
          } catch (error) {
            return JSON.stringify({ ok: false, error: String(error && error.message ? error.message : error) });
          }
        })()
        """
    }

    /// 官网里判断有没有登录
    static let loginCheckScript = """
    (function () {
      try {
        var raw = localStorage.getItem('userToken');
        return !!(raw && raw.length > 10);
      } catch (e) { return false; }
    })()
    """
}
