#!/usr/bin/env bash
set -euo pipefail

# AtendIA / P7Store — WhatsApp (Evolution API) em VM Linux na nuvem, GRATUITA, sempre ligada e SEM DOCKER.
# Recomendado: Oracle Cloud Always Free (VM.Standard.A1.Flex ARM 2-4GB, Ubuntu 22.04+).
# Tambem funciona: AWS t3.micro, GCP e2-micro, qualquer VPS Ubuntu/Debian (x86_64 ou ARM).
# Instala nativo: Node.js + PostgreSQL + Redis + Evolution API (build direto do codigo) + tunnel Cloudflare.
# Nao precisa deixar o PC ligado. Sessao do WhatsApp persiste no PostgreSQL da VM.

SupabaseUrl="https://pnijzmqygibhwbcnkklm.supabase.co"
RelaySecret="relay-atendia-sk-7f3d"
BaseDir="/opt/atendia"
EvoDir="$BaseDir/evolution-api"
EvoTag="${EVO_TAG:-2.3.7}"
EvoRepo="https://github.com/evolution-foundation/evolution-api.git"

say()  { echo -e "\e[36m[AtendIA]\e[0m $1"; }
warn() { echo -e "\e[33m[AtendIA] [AVISO]\e[0m $1"; }
fail() { echo -e "\e[31m[AtendIA] [ERRO]\e[0m $1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Rode como root: curl ... | sudo bash"
command -v apt-get >/dev/null 2>&1 || fail "Este script suporta Ubuntu/Debian (apt). Use Ubuntu 22.04+."

echo ""
echo "====================================================="
echo "  AtendIA - WhatsApp na nuvem (VM gratis, SEM Docker)"
echo "====================================================="
echo ""

say "Arquitetura: $(uname -m)  |  Tag Evolution API: $EvoTag"

# 0) Swap em VMs de 1GB (build TypeScript exige memoria)
MemMB="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
if [ -n "$MemMB" ] && [ "$MemMB" -lt 1400 ] && ! swapon --show 2>/dev/null | grep -q .; then
  say "RAM baixa (${MemMB}MB) - criando swap de 2GB..."
  {
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  } || warn "Nao consegui criar swap."
fi

# 1) Limpa instalacao Docker antiga (se existir) para nao brigar pelas portas
if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
  if ss -ltn 2>/dev/null | grep -Eq ':(8080|9876)[[:space:]]'; then
    warn "Portas 8080/9876 em uso - parando stack Docker antiga..."
    for d in /root/atendia-vm "$HOME/atendia-vm"; do
      [ -f "$d/docker-compose.vm.yml" ] && docker compose -f "$d/docker-compose.vm.yml" down --remove-orphans >/dev/null 2>&1 || true
    done
  fi
fi
( crontab -l 2>/dev/null | grep -v 'setup-linux.sh' ) | crontab - 2>/dev/null || true

# 2) Pacotes base (nativos, sem Docker)
say "Instalando pacotes: git, curl, ffmpeg, openssl, python3, postgresql, redis..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y git curl ca-certificates openssl ffmpeg python3 postgresql redis-server >/dev/null \
  || fail "Falha ao instalar pacotes (apt)."
systemctl enable --now postgresql >/dev/null 2>&1 || true
systemctl enable --now redis-server >/dev/null 2>&1 || true

# 3) Node.js 24 (mesma versao usada pelo build oficial da Evolution API)
NodeMajor="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$NodeMajor" -lt 20 ] 2>/dev/null; then
  say "Instalando Node.js 24 (NodeSource)..."
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash - >/dev/null || fail "Falha no setup NodeSource."
  apt-get install -y nodejs >/dev/null || fail "Falha ao instalar Node.js."
fi
say "Node.js $(node -v) | npm $(npm -v)"

# 4) cloudflared (tunnel HTTPS gratuito, binario unico)
if [ ! -x /usr/local/bin/cloudflared ]; then
  case "$(uname -m)" in
    aarch64|arm64) CfArch="arm64" ;;
    x86_64|amd64)  CfArch="amd64" ;;
    *) fail "Arquitetura nao suportada: $(uname -m)" ;;
  esac
  say "Baixando cloudflared ($CfArch)..."
  curl -fsSL -o /usr/local/bin/cloudflared "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$CfArch" \
    || fail "Falha ao baixar cloudflared."
  chmod +x /usr/local/bin/cloudflared
fi

# 5) PostgreSQL: banco + usuario (idempotente)
say "Configurando PostgreSQL..."
pg_isready -q 2>/dev/null || fail "PostgreSQL nao subiu."
run_pg() {
  if command -v sudo >/dev/null 2>&1; then
    sudo -u postgres psql "$@"
  else
    local args="" a
    for a in "$@"; do args="$args '$a'"; done
    su -l postgres -c "psql $args"
  fi
}
run_pg -tAc "SELECT 1 FROM pg_roles WHERE rolname=\$\$evolution\$\$" 2>/dev/null | grep -q 1 \
  || run_pg -qc "CREATE ROLE evolution LOGIN PASSWORD \$\$evolution123\$\$" >/dev/null
run_pg -tAc "SELECT 1 FROM pg_database WHERE datname=\$\$evolution\$\$" 2>/dev/null | grep -q 1 \
  || run_pg -qc "CREATE DATABASE evolution OWNER evolution;" >/dev/null
redis-cli ping >/dev/null 2>&1 || fail "Redis nao respondeu."

# 6) Codigo-fonte da Evolution API (tag estavel, idempotente)
mkdir -p "$BaseDir" && cd "$BaseDir"
if [ -d "$EvoDir/.git" ]; then
  say "Atualizando codigo da Evolution API (tag $EvoTag)..."
  git -C "$EvoDir" fetch --depth 1 origin "refs/tags/$EvoTag" >/dev/null 2>&1 \
    && git -C "$EvoDir" checkout -q FETCH_HEAD >/dev/null 2>&1 \
    || warn "Nao consegui atualizar o repositorio - seguindo com o codigo atual."
else
  say "Clonando Evolution API (tag $EvoTag)... (pode demorar alguns minutos)"
  git clone --depth 1 --branch "$EvoTag" "$EvoRepo" "$EvoDir" >/dev/null 2>&1 \
    || fail "Falha ao clonar $EvoRepo (verifique internet/DNS)."
fi
cd "$EvoDir"

# 7) .env (mesma base do .env.example oficial, com nossos valores)
if [ ! -f .env ]; then cp .env.example .env; fi
set_env() {
  if grep -q "^$1=" .env; then sed -i "s|^$1=.*|$1=$2|" .env; else echo "$1=$2" >> .env; fi
}
set_env AUTHENTICATION_API_KEY "atendia123"
set_env DATABASE_PROVIDER "postgresql"
set_env DATABASE_CONNECTION_URI "postgresql://evolution:evolution123@127.0.0.1:5432/evolution?schema=evolution_api"
set_env DATABASE_URL "postgresql://evolution:evolution123@127.0.0.1:5432/evolution?schema=evolution_api"
set_env CACHE_REDIS_ENABLED "true"
set_env CACHE_REDIS_URI "redis://127.0.0.1:6379/6"
set_env CORS_ORIGIN '*'
set_env SERVER_PORT "8080"
set_env LOG_LEVEL "ERROR,WARN,HTTP,LOG"
say ".env configurado (API Key atendia123, Postgres + Redis locais)."

# 8) Dependencias + build (pulados se ja prontos - reexecutar e seguro)
if [ ! -d node_modules ]; then
  say "npm ci (dependencias)... (5-10 min na primeira vez)"
  npm ci --no-audit --no-fund || fail "npm ci falhou (veja as mensagens acima). Manual: cd $EvoDir && npm ci"
fi
export DATABASE_PROVIDER=postgresql
if [ ! -d node_modules/.prisma ] || [ ! -f node_modules/@prisma/client/index.js ]; then
  say "Gerando cliente Prisma..."
  bash Docker/scripts/generate_database.sh >/dev/null 2>&1 || fail "Prisma generate falhou. Manual: cd $EvoDir && bash Docker/scripts/generate_database.sh"
fi
if [ ! -f dist/main.js ] || [ -n "$(find src -newer dist/main.js -name '*.ts' 2>/dev/null | head -n1)" ]; then
  say "Compilando Evolution API (tsc + tsup)... (pode demorar)"
  npm run build || fail "Build falhou (veja as mensagens acima). Manual: cd $EvoDir && npm run build"
fi
[ -f dist/main.js ] || fail "dist/main.js nao encontrado apos o build."
say "Aplicando migrations no PostgreSQL..."
bash Docker/scripts/deploy_database.sh >/dev/null 2>&1 || fail "Migrations falharam (veja: cd $EvoDir && bash Docker/scripts/deploy_database.sh)."

# 9) Ponte do tunnel (python puro: /info + proxy /evolution com CORS + auto-sync com o app)
say "Instalando ponte do tunnel Cloudflare..."
mkdir -p "$BaseDir"
cat > "$BaseDir/atendia-tunnel.py" <<'PYEOF'
import subprocess, re, threading, json, urllib.request, os, time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

PORT = int(os.environ.get("PORT", "9876"))
EVO_URL = os.environ.get("EVO_URL", "http://127.0.0.1:8080")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
RELAY_SECRET = os.environ.get("RELAY_SECRET", "")
CF = os.environ.get("CLOUDFLARED_BIN", "/usr/local/bin/cloudflared")
TUNNEL_URL = ""

def notify_supabase(tunnel_url):
    if not SUPABASE_URL or not RELAY_SECRET:
        return
    evo = tunnel_url + "/evolution"
    for path, payload in (
        ("/functions/v1/webhook-whatsapp/relay/update-tunnel", {"tunnel_url": tunnel_url}),
        ("/functions/v1/webhook-whatsapp/relay/update-evolution", {"server_url": evo}),
    ):
        try:
            req = urllib.request.Request(SUPABASE_URL + path,
                data=json.dumps(payload).encode(), method="POST",
                headers={"Authorization": "Bearer " + RELAY_SECRET, "Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=30).read()
            print("[relay] sincronizado " + path, flush=True)
        except Exception as e:
            print("[relay] falhou %s: %s" % (path, e), flush=True)

def tunnel_loop():
    global TUNNEL_URL
    while True:
        try:
            proc = subprocess.Popen(
                [CF, "tunnel", "--url", "http://127.0.0.1:%d" % PORT, "--no-autoupdate"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
            for line in proc.stdout:
                m = re.search(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com', line)
                if m and m.group() != TUNNEL_URL:
                    TUNNEL_URL = m.group()
                    print("[tunnel] URL: " + TUNNEL_URL, flush=True)
                    notify_supabase(TUNNEL_URL)
        except Exception as e:
            print("[tunnel] erro: %s" % e, flush=True)
        TUNNEL_URL = ""
        print("[tunnel] caiu, reiniciando em 10s...", flush=True)
        time.sleep(10)

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

    def _proxy_path(self, prefix):
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
        if self.path.startswith("/evolution/"):
            self.proxy(EVO_URL, self._proxy_path("/evolution/"), "DELETE", body)
        else:
            self.json_resp({"error": "not_found"}, 404)

    def proxy(self, base, path, method="GET", body=None):
        try:
            req = urllib.request.Request(base + path, data=body, method=method)
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

if __name__ == "__main__":
    print("[atendia-tunnel] ouvindo na porta %d" % PORT, flush=True)
    threading.Thread(target=tunnel_loop, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
PYEOF

# 10) systemd: servicos sempre ligados (auto-start pos-reboot, sem cron)
say "Criando servicos systemd (evolution + tunnel)..."
cat > /etc/systemd/system/evolution.service <<'EOF'
[Unit]
Description=AtendIA - Evolution API (WhatsApp)
After=network.target postgresql.service redis-server.service
Wants=postgresql.service redis-server.service

[Service]
Type=simple
WorkingDirectory=/opt/atendia/evolution-api
EnvironmentFile=/opt/atendia/evolution-api/.env
ExecStartPre=/bin/bash -c 'cd /opt/atendia/evolution-api && bash Docker/scripts/deploy_database.sh'
ExecStart=/usr/bin/npm run start:prod
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/atendia-tunnel.service <<EOF
[Unit]
Description=AtendIA - Tunnel Cloudflare (WhatsApp)
After=network.target

[Service]
Type=simple
Environment=SUPABASE_URL=$SupabaseUrl
Environment=RELAY_SECRET=$RelaySecret
ExecStart=/usr/bin/python3 /opt/atendia/atendia-tunnel.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload >/dev/null 2>&1
systemctl enable evolution atendia-tunnel >/dev/null 2>&1 || warn "Nao consegui habilitar auto-start."
systemctl restart evolution >/dev/null 2>&1 || true

# 11) Espera a Evolution subir (porta 8080)
say "Aguardando Evolution API subir..."
Up=""
for i in $(seq 1 60); do
  Code="$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/ 2>/dev/null || true)"
  [ -n "$Code" ] && [ "$Code" != "000" ] && Up="1" && break
  sleep 3
done
[ -n "$Up" ] || fail "Evolution nao subiu. Veja: journalctl -u evolution -n 50 --no-pager"

# 12) Tunnel: espera URL https
systemctl restart atendia-tunnel >/dev/null 2>&1 || true
say "Aguardando tunnel Cloudflare..."
TunnelUrl=""
for i in $(seq 1 36); do
  sleep 5
  Info="$(curl -fsS http://127.0.0.1:9876/info 2>/dev/null || true)"
  if echo "$Info" | grep -q '"status": "active"'; then
    TunnelUrl="$(echo "$Info" | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | head -n1)"
    [ -n "$TunnelUrl" ] && break
  fi
done
[ -n "$TunnelUrl" ] || fail "Tunnel nao subiu. Veja: journalctl -u atendia-tunnel -n 50 --no-pager"

EvoUrl="$TunnelUrl/evolution"
say "Tunnel ativo: $TunnelUrl"
say "Evolution API: $EvoUrl"

# 13) Sincroniza a URL com o app (a ponte tambem re-sincroniza sozinha apos reboot)
if curl -fsS -X POST "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-tunnel" \
     -H "Authorization: Bearer $RelaySecret" -H "Content-Type: application/json" \
     -d "{\"tunnel_url\": \"$TunnelUrl\"}" >/dev/null 2>&1; then
  say "Endpoint base registrado no app."
else
  warn "update-tunnel falhou (nao critico - a ponte tentara de novo)."
fi
if curl -fsS -X POST "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-evolution" \
     -H "Authorization: Bearer $RelaySecret" -H "Content-Type: application/json" \
     -d "{\"server_url\": \"$EvoUrl\"}" >/dev/null 2>&1; then
  say "URL da Evolution sincronizada com o P7Store/AtendIA!"
else
  warn "update-evolution falhou - a ponte re-sincroniza sozinha; se nao aparecer, cole a URL manualmente no app."
fi

echo ""
echo "====================================================="
echo "  Pronto! WhatsApp na nuvem - PC pode desligar."
echo "====================================================="
echo ""
echo "  Evolution URL: $EvoUrl"
echo "  API Key:       atendia123"
echo ""
echo "  1. Abra https://p7store.vercel.app -> Configuracoes -> WhatsApp"
echo "     (ou https://atend7ia.vercel.app -> Config WhatsApp)"
echo "  2. A URL acima ja foi sincronizada com o app."
echo "  3. Conectar WhatsApp -> escaneie o QR Code uma unica vez."
echo ""
echo "  IA: P7Store -> Configuracoes -> IA (cloud: NVIDIA, Gemini, OpenAI...)."
echo "  Sem Docker: Node + Postgres + Redis + Evolution nativos (systemd)."
echo "  Sessao WhatsApp fica salva no PostgreSQL da VM - nao re-escaneia apos reboot."
echo "  Reboot? Tudo se auto-inicia e o tunnel re-sincroniza a URL sozinho."
echo ""
echo "  Logs: journalctl -u evolution -f   |   journalctl -u atendia-tunnel -f"
echo "  Reinstalar/atualizar: rode este mesmo comando de novo (seguro)."
echo "====================================================="
