import subprocess, re, threading, json, urllib.request, os, signal, time
from http.server import HTTPServer, BaseHTTPRequestHandler

TUNNEL_URL = ""
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama:11434")
EVO_URL = os.environ.get("EVO_URL", "http://evolution-api:8080")
PORT = int(os.environ.get("PORT", "9876"))
SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://pnijzmqygibhwbcnkklm.supabase.co")
RELAY_SECRET = os.environ.get("RELAY_SECRET", "relay-atendia-sk-7f3d")

class Handler(BaseHTTPRequestHandler):
    def cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS, PATCH")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization, apiKey, apikey, ApiKey, x-api-key, x-api-key-woowa, X-Api-Key")
        self.send_header("Access-Control-Allow-Credentials", "true")
        self.send_header("Access-Control-Max-Age", "86400")

    def do_OPTIONS(self):
        self.send_response(204)
        self.cors_headers()
        self.end_headers()

    def _proxy_path(self, prefix: str) -> str:
        return self.path.replace(prefix, "/") if self.path == prefix else "/" + self.path.removeprefix(prefix)

    def do_GET(self):
        if self.path == "/info":
            self.json_resp({"tunnel_url": TUNNEL_URL, "status": "active" if TUNNEL_URL else "starting"})
        elif self.path.startswith("/ollama/"):
            self.proxy(OLLAMA_URL, self._proxy_path("/ollama/"))
        elif self.path.startswith("/evolution/"):
            self.proxy(EVO_URL, self._proxy_path("/evolution/"))
        else:
            self.json_resp({"error": "not_found"}, 404)

    def do_POST(self):
        cl = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(cl) if cl else b""
        if self.path.startswith("/ollama/"):
            self.proxy(OLLAMA_URL, self._proxy_path("/ollama/"), "POST", body)
        elif self.path.startswith("/evolution/"):
            self.proxy(EVO_URL, self._proxy_path("/evolution/"), "POST", body)
        else:
            self.json_resp({"error": "not_found"}, 404)

    def do_DELETE(self):
        cl = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(cl) if cl else b""
        if self.path.startswith("/ollama/"):
            self.proxy(OLLAMA_URL, self._proxy_path("/ollama/"), "DELETE", body)
        elif self.path.startswith("/evolution/"):
            self.proxy(EVO_URL, self._proxy_path("/evolution/"), "DELETE", body)
        else:
            self.json_resp({"error": "not_found"}, 404)

    def proxy(self, base, path, method="GET", body=None):
        try:
            req = urllib.request.Request(f"{base}{path}", data=body, method=method)
            for k, v in self.headers.items():
                if k.lower() not in ("host", "connection", "content-length", "origin"):
                    req.add_header(k, v)
            req.add_header("Origin", "http://localhost")
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
                self.send_response(r.status)
                self.cors_headers()
                for k, v in r.headers.items():
                    if k.lower() not in ("transfer-encoding", "connection", "access-control-allow-origin", "access-control-allow-methods", "access-control-allow-headers", "access-control-allow-credentials", "access-control-max-age"):
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.cors_headers()
            self.end_headers()
            self.wfile.write(e.read())
        except Exception as e:
            self.json_resp({"error": str(e)}, 502)

    def json_resp(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.cors_headers()
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, fmt, *args):
        pass

def sync_tunnel(url):
    # Sincroniza a URL do tunel com o banco (mesmos endpoints que o assistente usa no [5/5]).
    # Assim, depois de reiniciar o PC, o AtendIA volta a funcionar SOZINHO - a URL nova
    # do trycloudflare substitui a antiga e ninguem precisa rodar nada de novo.
    ok = True
    for path, key, val in [
        ("/functions/v1/webhook-whatsapp/relay/update-tunnel", "tunnel_url", url),
        ("/functions/v1/webhook-whatsapp/relay/update-evolution", "server_url", url + "/evolution"),
    ]:
        try:
            req = urllib.request.Request(
                SUPABASE_URL + path,
                data=json.dumps({key: val}).encode(),
                headers={"Content-Type": "application/json", "Authorization": "Bearer " + RELAY_SECRET},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=15) as r:
                r.read()
            print(f"[sync] {key} -> {val}", flush=True)
        except Exception as e:
            print(f"[sync] {key} falhou (tento de novo): {e}", flush=True)
            ok = False
    return ok

def sync_loop():
    last = None
    while True:
        time.sleep(10)
        if TUNNEL_URL and TUNNEL_URL != last:
            if sync_tunnel(TUNNEL_URL):
                last = TUNNEL_URL

def start_cloudflared():
    global TUNNEL_URL
    while True:
        try:
            proc = subprocess.Popen(
                ["cloudflared", "tunnel", "--url", f"http://localhost:{PORT}"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1
            )
            for line in proc.stdout:
                m = re.search(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com', line)
                if m:
                    TUNNEL_URL = m.group()
                    print(f"[tunnel] URL: {TUNNEL_URL}", flush=True)
                    break
            proc.wait()  # cloudflared caiu -> reinicia sozinho (URL nova -> sync_loop atualiza o banco)
        except Exception as e:
            print(f"[tunnel] error: {e}", flush=True)
        time.sleep(5)

if __name__ == "__main__":
    print(f"[tunnel-info] listening on {PORT}", flush=True)
    threading.Thread(target=start_cloudflared, daemon=True).start()
    threading.Thread(target=sync_loop, daemon=True).start()
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
