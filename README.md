# atendia-setup
AtendIA installation scripts

## VM Linux na nuvem — SEM Docker (recomendado)
```bash
curl -sL https://raw.githubusercontent.com/Projectz7/atendia-setup/main/setup-native.sh | sudo bash
```
Instala nativo (Node.js 24 + PostgreSQL + Redis + Evolution API 2.3.7 + cloudflared) via systemd.
Grátis na Oracle Always Free (VM.Standard.A1.Flex ARM 2-4GB, Ubuntu 22.04+). Idempotente:
rodar de novo é seguro. Após reboot, os serviços sobem sozinhos e o túnel ressincroniza a URL
com o app (relay `update-tunnel`/`update-evolution`). API Key: `atendia123`.

## VM Linux na nuvem — com Docker (alternativa)
```bash
curl -sL https://raw.githubusercontent.com/Projectz7/atendia-setup/main/setup-linux.sh | sudo bash
```
Sobe a mesma stack via docker-compose (Postgres + Redis + Evolution + tunnel-info).

