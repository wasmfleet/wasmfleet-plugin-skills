# 运行约定细节

## 环境变量

中控启动插件时会设置下面这些变量，其余环境变量继承自中控：

| 变量 | 含义 |
|---|---|
| `PORT` | 中控分配的端口（20000～29999，每个插件固定一个；被别的程序占用时会自动换一个）。`WASMFLEET_PLUGIN_PORT` 是同一个值 |
| `WASMFLEET_BASE_PATH` | 反向代理前缀，如 `/p/hello`，没有结尾斜杠 |
| `WASMFLEET_PLUGIN_ID` | 插件编号，如 `plg-xxxxxxxxxx` |
| `WASMFLEET_PLUGIN_DATA` | 插件工作目录的绝对路径，也是进程的当前目录 |
| `WASMFLEET_CONTROL_URL` | 中控地址，如 `http://127.0.0.1:18080` |

- 启动参数可以在中控里填写，按空白分隔（不支持引号），其中的 `{port}` 会被替换成端口。
- stdin 是 `/dev/null`。

Rust（clap）示例：同时支持 `PORT`、`--port`、`-p`，默认只监听本机。

```rust
#[derive(clap::Parser)]
#[command(version = VERSION)]
struct Args {
    #[arg(long, short = 'p', env = "PORT")]   // clap 需要开启 "env" 特性
    port: u16,
    #[arg(long, default_value = "127.0.0.1")] // 脱离中控单独部署时可用 --host 0.0.0.0
    host: String,
}
```

启动失败时（缺少端口、端口被占用），把原因写到 stderr，然后以非 0 退出码退出，方便在中控日志里排查。

## 插件类型

中控会定期检查插件进程组监听了哪些 TCP 端口：

- 监听了端口：识别为 **HTTP 服务**，请求转发到 `PORT`。如果端口写死在程序里，就转发到它实际监听的第一个端口。仍然建议使用 `PORT`。
- 启动 10 秒后仍没有监听端口：识别为**后台任务**。后台任务没有页面，访问代理地址会返回 502。

类型也可以在中控里手动指定。

## 生命周期

- **在前台一直运行，不要自己转到后台**：不要 daemonize、fork 后让父进程退出、`setsid`、`nohup ... &`。中控管理的是它启动的那个进程组，识别监听端口、停止时发信号、判断进程是否退出，都依据这个进程组。程序一旦脱离进程组，中控会以为它已经退出（并按策略重启），停止时也杀不掉它，还会造成端口冲突。
- 没有健康检查接口，也没有启动超时。「在运行」只表示进程还活着。HTTP 服务以端口被监听为准，页面上会显示监听的端口。
- **停止**：中控给整个进程组发 SIGTERM，5 秒后还没退出就发 SIGKILL。插件是自己进程组的组长，它启动的子进程会一起结束。
- **重启策略**（在中控里设置）：
  - 失败时重启（默认）：退出码非 0，或者被信号结束（中控主动停止的除外）时重启。等待间隔依次为 1、2、4、8……秒，最长 60 秒；连续稳定运行 60 秒以上后，重新从 1 秒算。
  - 总是重启。
  - 不重启。
- 退出码 0 在默认策略下表示正常结束，不会重启。后台任务想常驻，就不要以 0 退出，或者改成「总是重启」。
- 在中控里手动点「启动」或「重启」时，自动重启的计数会清零，等待间隔重新从 1 秒算。插件在等待自动重启期间被手动停止，就不会再重启。
- 中控退出时会停止所有插件；中控启动时，会启动设置了「随中控启动」（默认开启）的插件。

Rust（tokio + axum）处理 SIGTERM 的写法：

```rust
axum::serve(listener, app)
    .with_graceful_shutdown(shutdown_signal())
    .await?;

async fn shutdown_signal() {
    let ctrl_c = async { let _ = tokio::signal::ctrl_c().await; };
    #[cfg(unix)]
    let term = async {
        if let Ok(mut s) = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            s.recv().await;
        }
    };
    #[cfg(not(unix))]
    let term = std::future::pending::<()>();
    tokio::select! { _ = ctrl_c => {}, _ = term => {} }
}
```

tokio 需要开启 `signal` 特性。收到信号后停止接受新连接，等进行中的请求处理完再返回。数据库连接随程序结束而关闭。

## 日志

- stdout 和 stderr 都按行采集，stderr 在页面上标红。中控在内存里保留最近 2000 行，同时写进插件目录下的 `plugin.log`。这个文件不在工作目录里，超过 5 MiB 时轮转一次。
- 一行一条日志，不要输出终端颜色控制码。stdout 不是终端时，很多语言默认会缓冲输出，记得及时 flush（例如 Python 用 `-u` 或 `flush=True`）。

## 工作目录与数据

- 当前目录就是 `WASMFLEET_PLUGIN_DATA`，数据文件用相对路径（如 `data.db`）即可。
- 更新、回退、修改设置、重启时都会保留；只有在中控里删除插件时才会删除。
- 修改数据库表结构时，启动时检测并迁移。用户可能跨多个版本升级，也可能回退；不能直接丢弃的数据先备份到另一张表。

## 反向代理行为

- `http://<中控>:18080/p/<路径名>/xxx` 转发为 `http://127.0.0.1:$PORT/xxx`，也就是去掉前缀。访问 `/p/<路径名>`（没有结尾斜杠）会被重定向到 `/p/<路径名>/`。
- 转发时请求头的变化：
  - `Host` 改成 `127.0.0.1:<端口>`，原来的值放在 `X-Forwarded-Host`；
  - 另外加上 `X-Forwarded-Proto: http` 和 `X-Forwarded-Prefix: /p/<路径名>`。
  - **没有 `X-Forwarded-For`**：插件拿不到访问者的 IP，所有请求看起来都来自 127.0.0.1。需要按来源限制访问的插件不能依赖对方 IP。
- 支持流式响应，以及 WebSocket 等协议升级。
- 插件返回的重定向会这样改写 `Location`：
  - `/xxx` 改成 `/p/<路径名>/xxx`；
  - `http://127.0.0.1:<端口>/xxx` 和 `http://localhost:<端口>/xxx` 也改成 `/p/<路径名>/xxx`；
  - 相对地址（如 `Location: target`）和其他域名的地址不改。
- `Set-Cookie` 的 `Path` 也会改到前缀下面。
- 页面里写死的绝对路径（如 `/static/app.js`）会按 `Referer` 转发回插件；但如果和中控自己的路径冲突（`/`、`/api/...`），中控优先。**所以不要依赖这个兜底，一律用相对路径。**
- 插件没有运行时返回 503。返回 502（页面显示「连不上插件」）有两种情况：插件是后台任务；或者插件是 HTTP 服务，但还没有监听端口、连接被拒绝。

## 前缀下的前端写法

| 错误 | 正确 |
|---|---|
| `<link href="/static/style.css">` | `<link href="static/style.css">` |
| `fetch('/api/items')` | `fetch('api/items')` |
| `<a href="/">首页</a>` | `<a href="./">首页</a>` |
| `<a href="/data?x=1">` | `<a href="data?x=1">` |

要点：

- `history.replaceState` 用 `location.pathname` 拼接，不要写死路径。
- 导航高亮时比较解析后的完整路径：`new URL(a.href).pathname === location.pathname`，不要比较 `getAttribute('href')`。
- 在页面上显示「对外接口地址」时，协议、端口和前缀都从浏览器地址栏取，只把主机部分替换成用户选择的内网 IP：

```js
const BASE_PATH = new URL('.', location.href).pathname;   // "/" 或 "/p/hello/"
const host = selectedLanIp || location.hostname;
const base = `${location.protocol}//${host}${location.port ? ':' + location.port : ''}${BASE_PATH}`;
```

- 插件可以提供一个 `api/info` 接口，返回本机的内网 IP 列表供页面选择。枚举网卡时排除回环地址、`198.18.0.0/15`（代理和 VPN 的虚拟网卡常用）和 `100.64.0.0/10`，优先用 `192.168/16`、`10/8`、`172.16/12`。插件只监听 127.0.0.1，不影响它列出本机的内网 IP。

## 本地模拟前缀代理

用一个不做根路径兜底的极简代理来测试，它比中控更严格：凡是以 `/` 开头的路径都会直接 404。

```python
# python3 proxy.py 28700 <插件端口>，然后打开 http://127.0.0.1:28700/p/hello/
import http.server, urllib.request, sys
LISTEN, UP, PREFIX = int(sys.argv[1]), int(sys.argv[2]), "/p/hello"
class H(http.server.BaseHTTPRequestHandler):
    def _go(self):
        if not self.path.startswith(PREFIX + "/"):
            self.send_response(404); self.end_headers(); return
        n = int(self.headers.get("Content-Length") or 0)
        req = urllib.request.Request(f"http://127.0.0.1:{UP}{self.path[len(PREFIX):]}",
                                     data=self.rfile.read(n) if n else None, method=self.command)
        if self.headers.get("Content-Type"): req.add_header("Content-Type", self.headers["Content-Type"])
        try: r = urllib.request.urlopen(req)
        except urllib.error.HTTPError as e: r = e
        body = r.read(); self.send_response(r.status)
        self.send_header("Content-Type", r.headers.get("Content-Type", "text/plain"))
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    do_GET = do_POST = do_PUT = do_DELETE = _go
http.server.ThreadingHTTPServer(("127.0.0.1", LISTEN), H).serve_forever()
```

验证清单：

- 页面之间可以互相跳转；
- 样式、脚本、接口请求都带前缀；
- 页面上显示的对外地址可以用 curl 调通；
- `kill -TERM <pid>` 后，程序在 5 秒内退出。
