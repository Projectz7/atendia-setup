#!/usr/bin/env bash
set -euo pipefail

# AtendIA / P7Store — WhatsApp (Evolution API) em VM Linux na nuvem, GRATUITA e sempre ligada.
# Recomendado: Oracle Cloud Always Free (VM.Standard.A1.Flex ARM 2-4GB, Ubuntu 22.04+).
# Tambem funciona: AWS t3.micro, GCP e2-micro, qualquer VPS x86_64.
# Nao precisa deixar o PC ligado. Sessao do WhatsApp persiste no banco (volume Docker).

SupabaseUrl="https://pnijzmqygibhwbcnkklm.supabase.co"
RawBase="https://raw.githubusercontent.com/Projectz7/atendia-setup/main"
RelaySecret="relay-atendia-sk-7f3d"
BaseDir="$HOME/atendia-vm"

say() { echo -e "\e[36m[AtendIA]\e[0m $1"; }
warn() { echo -e "\e[33m[AtendIA] [AVISO]\e[0m $1"; }
fail() { echo -e "\e[31m[AtendIA] [ERRO]\e[0m $1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Rode como root: sudo bash setup-linux.sh"

echo ""
echo "============================================"
echo "  AtendIA - WhatsApp na nuvem (VM gratis)"
echo "============================================"
echo ""

say "Arquitetura da VM: $(uname -m)"

# 1) Docker
if ! command -v docker >/dev/null 2>&1; then
  say "Instalando Docker..."
  curl -fsSL https://get.docker.com | sh || fail "Falha ao instalar Docker"
fi
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 (plugin) nao encontrado."

# 2) Swap em VMs de 1GB (evita OOM do Postgres/Evolution)
MemMB="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
if [ -n "$MemMB" ] && [ "$MemMB" -lt 1400 ] && ! swapon --show 2>/dev/null | grep -q .; then
  say "RAM baixa (${MemMB}MB) - criando swap de 2GB..."
  {
    fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
    chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  } || warn "Nao consegui criar swap (siga se a VM tiver RAM suficiente)."
fi

# 3) Arquivos da stack
mkdir -p "$BaseDir" && cd "$BaseDir"
say "Baixando arquivos do GitHub..."
curl -fsSL -o docker-compose.vm.yml "$RawBase/docker-compose.vm.yml" || fail "Sem acesso ao GitHub (verifique internet/DNS)."
mkdir -p tunnel-info
curl -fsSL -o tunnel-info/Dockerfile "$RawBase/tunnel-info/Dockerfile" || fail "Falha ao baixar tunnel-info/Dockerfile"
curl -fsSL -o tunnel-info/server.py "$RawBase/tunnel-info/server.py" || fail "Falha ao baixar tunnel-info/server.py"

# 4) Sobe a stack (postgres + redis + evolution + tunnel Cloudflare)
say "Subindo containers (Evolution API + Postgres + Redis + Tunnel)..."
docker compose -f docker-compose.vm.yml down --remove-orphans >/dev/null 2>&1 || true
if ! docker compose -f docker-compose.vm.yml pull; then
  echo ""
  fail "Falha ao baixar as imagens. Se a VM for ARM e a Evolution nao tiver build ARM64, use uma VM AMD/x86_64 (ex.: Oracle VM.Standard.E2.1.Micro, AWS t3.micro) e rode de novo."
fi
docker compose -f docker-compose.vm.yml up -d --force-recreate >/dev/null || fail "Falha ao subir os containers"

# 5) Espera o tunnel Cloudflare expor a URL HTTPS
say "Aguardando tunnel Cloudflare..."
TunnelUrl=""
for i in $(seq 1 36); do
  sleep 5
  Info="$(curl -fsS http://localhost:9876/info 2>/dev/null || true)"
  if echo "$Info" | grep -q '"status": "active"'; then
    TunnelUrl="$(echo "$Info" | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | head -n1)"
    [ -n "$TunnelUrl" ] && break
  fi
done
[ -n "$TunnelUrl" ] || fail "Tunnel nao subiu. Veja os logs: docker compose -f docker-compose.vm.yml logs tunnel-info"

EvoUrl="$TunnelUrl/evolution"
say "Tunnel ativo: $TunnelUrl"
say "Evolution API: $EvoUrl"

# 6) Sincroniza a URL com o app (mesmos endpoints do setup Windows)
if curl -fsS -X POST "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-tunnel" \
     -H "Authorization: Bearer $RelaySecret" -H "Content-Type: application/json" \
     -d "{\"tunnel_url\": \"$TunnelUrl\"}" >/dev/null 2>&1; then
  say "Endpoint base registrado no app."
else
  warn "update-tunnel falhou (nao critico)."
fi
if curl -fsS -X POST "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-evolution" \
     -H "Authorization: Bearer $RelaySecret" -H "Content-Type: application/json" \
     -d "{\"server_url\": \"$EvoUrl\"}" >/dev/null 2>&1; then
  say "URL da Evolution sincronizada com o P7Store/AtendIA!"
else
  warn "update-evolution falhou - cole a URL manualmente no app."
fi

# 7) Auto-start pos-reboot (o tunnel gera URL nova; reexecutar o script resincroniza)
CronLine="@reboot root sleep 60 && bash $BaseDir/setup-linux.sh >> $BaseDir/reboot.log 2>&1"
cp "$0" "$BaseDir/setup-linux.sh" 2>/dev/null || true
( crontab -l 2>/dev/null | grep -v 'setup-linux.sh'; echo "$CronLine" ) | crontab - 2>/dev/null \
  && say "Auto-start pos-reboot agendado no cron." \
  || warn "Nao consegui agendar cron - se a VM reiniciar, rode o comando curl | sudo bash de novo."

echo ""
echo "============================================"
echo "  Pronto! WhatsApp na nuvem - PC pode desligar."
echo "============================================"
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
echo "  Sessao WhatsApp fica salva no banco da VM - nao re-escaneia apos reboot."
echo ""
echo "  Logs: cd $BaseDir && docker compose -f docker-compose.vm.yml logs -f"
echo "============================================"
