#!/usr/bin/env bash
# atendia-doctor — diagnostico rapido do WhatsApp na nuvem (AtendIA / P7Store)
# Rode NA VM (recomendado com sudo):  sudo atendia-doctor
# Ou direto do GitHub:
#   curl -fsSL https://raw.githubusercontent.com/Projectz7/atendia-setup/main/atendia-doctor.sh | sudo bash
# Checa: systemd, Evolution local, tunnel, URL publica e ultima sincronizacao com o app.
# Cada item com problema vem com o proximo passo (comando) para resolver.

set -u

FAILS=0
SECTION() { echo ""; echo "== $1 =="; }
OK()      { echo "  [✅] $1"; }
BAD()     { echo "  [❌] $1"; FAILS=$((FAILS+1)); }
TIP()     { echo "        → $1"; }

echo "====================================================="
echo "  atendia-doctor — saude do WhatsApp na nuvem"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
echo "====================================================="

# 1) Servicos systemd
SECTION "1. Servicos systemd"
for u in evolution atendia-tunnel; do
  if systemctl is-active --quiet "$u" 2>/dev/null; then
    OK "servico '$u' ativo"
  else
    BAD "servico '$u' NAO esta ativo"
    TIP "systemctl restart $u"
    TIP "journalctl -u $u -n 50 --no-pager"
  fi
done

# 2) Evolution API local
SECTION "2. Evolution API local (127.0.0.1:8080)"
Code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:8080/ 2>/dev/null || echo 000)"
if [ "$Code" != "000" ]; then
  OK "respondendo (HTTP $Code)"
else
  BAD "sem resposta na porta 8080"
  TIP "systemctl restart evolution"
  TIP "journalctl -u evolution -n 50 --no-pager"
fi

# 3) Tunnel: a ponte conhece uma URL?
SECTION "3. Tunnel Cloudflare (ponte local 127.0.0.1:9876)"
Info="$(curl -fsS --max-time 10 http://127.0.0.1:9876/info 2>/dev/null || true)"
TunnelUrl="$(echo "$Info" | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | head -n1)"
if [ -n "$TunnelUrl" ]; then
  OK "URL conhecida: $TunnelUrl"
else
  BAD "ponte sem URL de tunnel (status: ${Info:-sem resposta})"
  TIP "systemctl restart atendia-tunnel   # sobe um tunnel novo"
  TIP "journalctl -u atendia-tunnel -n 50 --no-pager"
fi

# 4) URL publica responde pela internet?
SECTION "4. Tunnel pela internet (URL publica /info)"
if [ -n "$TunnelUrl" ]; then
  Code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$TunnelUrl/info" 2>/dev/null || echo 000)"
  if [ "$Code" = "200" ]; then
    OK "/info respondeu pela internet (HTTP 200)"
  else
    BAD "/info NAO respondeu pela internet (HTTP $Code)"
    TIP "systemctl restart atendia-tunnel   # tunnel travado: sobe URL nova (re-notifica o app)"
    TIP "journalctl -u atendia-tunnel -n 50 --no-pager"
  fi
else
  BAD "nao da para testar sem URL (resolva o item 3 primeiro)"
fi

# 5) Ultima sincronizacao com o app (Supabase/P7Store)
SECTION "5. Ultima sincronizacao com o app (P7Store/AtendIA)"
SyncFile="/var/lib/atendia/last-sync"
if [ -r "$SyncFile" ]; then
  Ts="$(grep -m1 '^ts=' "$SyncFile" | cut -d= -f2)"
  Quando="$(grep -m1 '^quando=' "$SyncFile" | cut -d= -f2-)"
  UrlSync="$(grep -m1 '^url=' "$SyncFile" | cut -d= -f2-)"
  Ep="$(grep -m1 '^endpoint=' "$SyncFile" | cut -d= -f2-)"
  echo "        quando:   $Quando"
  echo "        url:      $UrlSync"
  echo "        endpoint: $Ep"
  if [ -n "$Ts" ] && [ "$Ts" -gt 0 ] 2>/dev/null; then
    AgeMin=$(( ( $(date +%s) - Ts ) / 60 ))
    if [ "$AgeMin" -le 40 ]; then
      OK "sincronizado ha ${AgeMin} min (saudavel - re-sync automatica a cada ~30min)"
    else
      BAD "ultima sincronizacao ha ${AgeMin} min (esperado: no maximo ~35 min)"
      TIP "systemctl restart atendia-tunnel   # forca nova sincronizacao"
      TIP "journalctl -u atendia-tunnel -n 50 --no-pager"
    fi
  else
    BAD "arquivo de sincronizacao invalido (sem ts=)"
    TIP "reinstale a versao nova: curl -fsSL https://raw.githubusercontent.com/Projectz7/atendia-setup/main/setup-native.sh | sudo bash"
  fi
else
  BAD "sem registro de sincronizacao (${SyncFile} inacessivel ou inexistente)"
  TIP "rode com sudo: sudo atendia-doctor"
  TIP "versao antiga do setup? atualize: curl -fsSL https://raw.githubusercontent.com/Projectz7/atendia-setup/main/setup-native.sh | sudo bash"
fi

# Resumo
echo ""
echo "====================================================="
if [ "$FAILS" -eq 0 ]; then
  echo "  Tudo certo! WhatsApp na nuvem saudavel ✅"
else
  echo "  $FAILS problema(s) encontrado(s) ❌"
  echo "  Cada item acima ja mostra o proximo passo (→)."
  echo "  Persistindo? Reinstale (seguro, idempotente):"
  echo "  curl -fsSL https://raw.githubusercontent.com/Projectz7/atendia-setup/main/setup-native.sh | sudo bash"
fi
echo "====================================================="
