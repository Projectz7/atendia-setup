# atendia-setup
AtendIA installation scripts

## Assistente de configuração (Windows) — menu dos 3 caminhos
```powershell
curl.exe -sL -o setup.ps1 https://raw.githubusercontent.com/Projectz7/atendia-setup/main/setup.ps1
powershell -ExecutionPolicy Bypass -File setup.ps1
```
Mostra o mesmo menu do P7Store (Configurações > WhatsApp):
- `[1] Nuvem grátis — VM Oracle (Recomendado)`: guia a criação da conta, da VM e do acesso via Cloud Shell, com confirmação em cada etapa;
- `[2] Railway (mais fácil — mas pago)`: guia o deploy e **sincroniza a URL colada com o app sozinho**;
- `[3] Docker Local (controle total)`: assistente automático — roteiro [1/5..5/5], progresso e checklist final.

`-Docker` pula o menu e vai direto ao caminho 3.

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

## Docker Local no seu PC (Windows/Mac/Linux) — assistente guiado
```powershell
curl.exe -sL -o setup.ps1 https://raw.githubusercontent.com/Projectz7/atendia-setup/main/setup.ps1
powershell -ExecutionPolicy Bypass -File setup.ps1 -Docker
```
Sobe a stack local (Postgres + Redis + Evolution + Ollama CPU + túnel Cloudflare) direto no PC,
com assistente passo a passo no terminal: mostra o roteiro [1/5..5/5], verifica o Docker Desktop
(pausa esperando você), baixa os arquivos, sobe os containers, testa o túnel pela internet e
sincroniza as URLs com o app sozinho. Sessão do WhatsApp salva em volumes: re-rodar é seguro;
`-Clean` apaga tudo (sessão + modelos). Precisa de Docker Desktop e PC ligado enquanto usar.


