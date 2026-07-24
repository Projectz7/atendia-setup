param(
  [string]$FolderName = "atendia-tunnel",
  [switch]$Docker,
  [switch]$NoReload,
  [switch]$Clean
)

$SupabaseUrl = "https://pnijzmqygibhwbcnkklm.supabase.co"
$RawBase = "https://raw.githubusercontent.com/Projectz7/atendia-setup/main"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  AtendIA - Configuracao WhatsApp + IA" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($Docker) {
  Write-Host "[Modo Docker Local]" -ForegroundColor Yellow
  $choice = "docker"
} else {
  Write-Host "Escolha como conectar o WhatsApp:" -ForegroundColor White
  Write-Host ""
  Write-Host "  [1] Railway (Recomendado) -Deploy na nuvem, 1 click, URL fixa HTTPS" -ForegroundColor Green
  Write-Host "      Facil, nao precisa deixar PC ligado, funciona no Vercel" -ForegroundColor Gray
  Write-Host ""
  Write-Host "  [2] Docker Local - Roda Evolution no seu PC (controle total)" -ForegroundColor Yellow
  Write-Host "      Precisa Docker + PC ligado + tunnel Cloudflare" -ForegroundColor Gray
  Write-Host ""
  do {
    $choice = Read-Host "Digite 1 ou 2"
  } while ($choice -ne "1" -and $choice -ne "2")
  Write-Host ""
}

if ($choice -eq "1") {
  Write-Host "[AtendIA] Modo Railway (Nuvem)" -ForegroundColor Green
  Write-Host ""
  Write-Host "  PASSO 1: Deploy no Railway (1 click)" -ForegroundColor White
  Write-Host "  -----------------------------------------------" -ForegroundColor Gray
  Write-Host "  Abra no navegador:" -ForegroundColor White
  Write-Host "  https://railway.app/template/atendia-evolution" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  - Clique em Deploy Now" -ForegroundColor Gray
  Write-Host "  - Autentique com GitHub" -ForegroundColor Gray
  Write-Host "  - Aguarde o build terminar (~3 min)" -ForegroundColor Gray
  Write-Host "  - Copie a URL gerada (ex: https://evolution-xxx.up.railway.app)" -ForegroundColor Gray
  Write-Host ""
  Write-Host "  PASSO 2: Configure no AtendIA" -ForegroundColor White
  Write-Host "  -----------------------------------------------" -ForegroundColor Gray
  Write-Host "  1. Abra https://atend7ia.vercel.app" -ForegroundColor White
  Write-Host "  2. Va em Config WhatsApp" -ForegroundColor White
  Write-Host "  3. Cole a URL do Railway + API Key (atendia123)" -ForegroundColor White
  Write-Host "  4. Clique em Testar -> deve aparecer.Conectado!" -ForegroundColor Green
  Write-Host "  5. Digite seu numero -> Conectar WhatsApp -> escaneie QR Code" -ForegroundColor White
  Write-Host ""
  Write-Host "  PASSO 3: Configure a IA (opcional mas recomendado)" -ForegroundColor White
  Write-Host "  -----------------------------------------------" -ForegroundColor Gray
  Write-Host "  No P7Store -> Configuracoes -> IA:" -ForegroundColor White
  Write-Host "  - Adicione uma IA cloud (DeepSeek, OpenAI ou Gemini)" -ForegroundColor Gray
  Write-Host "  - DeepSeek: https://platform.deepseek.com (mais barata)" -ForegroundColor Gray
  Write-Host "  - Gere uma API Key e cole la" -ForegroundColor Gray
  Write-Host "  - Teste e ative" -ForegroundColor Gray
  Write-Host "  - Depois no AtendIA -> Config IA -> selecione a IA criada" -ForegroundColor Gray
  Write-Host ""
  Write-Host "  Pronto! O AtendIA responde mensagens automaticamente." -ForegroundColor Green
  Write-Host "  Mensagem recebida -> IA cloud responde -> enviada via Railway." -ForegroundColor Gray
  Write-Host "  Nao precisa de relay, tunnel, ou PC ligado." -ForegroundColor Gray
  Write-Host ""
  Write-Host "============================================" -ForegroundColor Cyan
  Write-Host "  Abrindo Railway no navegador..." -ForegroundColor Cyan
  Write-Host "============================================" -ForegroundColor Cyan
  Start-Process "https://railway.app/template/atendia-evolution"
  Start-Process "https://atend7ia.vercel.app"
  exit 0
}

# ==================== MODO DOCKER LOCAL ====================
Write-Host "[AtendIA] Modo Docker Local" -ForegroundColor Yellow
Write-Host ""
Write-Host "  ANTES DE CONTINUAR:" -ForegroundColor White
Write-Host "  -----------------------------------------------" -ForegroundColor Gray
Write-Host "  Esse modo precisa do Docker Desktop instalado." -ForegroundColor White
Write-Host "  Se ainda nao tem, baixe e instale:" -ForegroundColor White

if ($env:OS -eq "Windows_NT") {
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    $DockerUrl = "https://desktop.docker.com/win/main/arm64/Docker%20Desktop%20Installer-arm64.exe"
    $DockerLabel = "Windows ARM64"
  } else {
    $DockerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    $DockerLabel = "Windows x64"
  }
} elseif ($env:OS -eq "Darwin") {
  $DockerUrl = "https://docs.docker.com/desktop/install/mac-install/"
  $DockerLabel = "macOS"
} else {
  $DockerUrl = "https://docs.docker.com/desktop/install/linux-install/"
  $DockerLabel = "Linux"
}
Write-Host "  [Seu sistema: $DockerLabel]" -ForegroundColor Gray
Write-Host "  $DockerUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Apos instalar:" -ForegroundColor White
Write-Host "  1. Abra o Docker Desktop (inicie pelo atalho)" -ForegroundColor Gray
Write-Host "  2. Aceite os termos e aguarde ele iniciar" -ForegroundColor Gray
Write-Host "  3. Volte aqui e pressione ENTER para continuar" -ForegroundColor Gray
Write-Host "  4. Se preferir o modo nuvem, feche e execute de novo escolhendo [1]" -ForegroundColor Gray
Write-Host "  -----------------------------------------------" -ForegroundColor Gray
Write-Host ""
pause
Write-Host ""

if (-not (Test-Path -LiteralPath $FolderName)) {
  New-Item -ItemType Directory -Path $FolderName -Force | Out-Null
  Write-Host "[AtendIA] Pasta '$FolderName' criada" -ForegroundColor Green
} else {
  Write-Host "[AtendIA] Pasta '$FolderName' existe - atualizando arquivos" -ForegroundColor Yellow
}
Set-Location -LiteralPath $FolderName

Write-Host "[AtendIA] Baixando arquivos do GitHub..." -ForegroundColor Cyan
Invoke-WebRequest -Uri "$RawBase/docker-compose.evolution.yml" -OutFile "docker-compose.evolution.yml" -UseBasicParsing | Out-Null
if (-not (Test-Path -LiteralPath "tunnel-info")) { New-Item -ItemType Directory -Path "tunnel-info" -Force | Out-Null }
Invoke-WebRequest -Uri "$RawBase/tunnel-info/Dockerfile" -OutFile "tunnel-info/Dockerfile" -UseBasicParsing | Out-Null
Invoke-WebRequest -Uri "$RawBase/tunnel-info/server.py" -OutFile "tunnel-info/server.py" -UseBasicParsing | Out-Null
Invoke-WebRequest -Uri "$RawBase/relay-whatsapp.ps1" -OutFile "relay-whatsapp.ps1" -UseBasicParsing | Out-Null
Write-Host "[AtendIA] Arquivos atualizados" -ForegroundColor Green

$dockerVer = docker --version 2>$null
if (-not $dockerVer) {
  Write-Host "[AtendIA] [ERRO] Docker nao encontrado." -ForegroundColor Red
  Write-Host "[AtendIA] Baixe e instale o Docker Desktop:" -ForegroundColor Yellow
  Write-Host "[AtendIA] [Seu sistema: $DockerLabel] $DockerUrl" -ForegroundColor Cyan
  Write-Host "[AtendIA] Apos instalar, reinicie o PC, abra o Docker Desktop e aguarde ele iniciar." -ForegroundColor Yellow
  Write-Host "[AtendIA] Depois volte aqui e pressione ENTER." -ForegroundColor Yellow
  Write-Host "[AtendIA] Ou use o modo Railway (opcao 1) que nao precisa de Docker." -ForegroundColor Yellow
  pause
  exit 1
}
Write-Host "[AtendIA] Docker: $dockerVer" -ForegroundColor Gray

Write-Host "[AtendIA] Verificando Docker Desktop..." -ForegroundColor Cyan
$engineReady = $false
while (-not $engineReady) {
  $info = docker info 2>&1
  if ($info -notmatch "error during connect") {
    $engineReady = $true
    break
  }
  Write-Host ""
  Write-Host "[AtendIA] Docker Desktop ainda esta iniciando..." -ForegroundColor Yellow
  Write-Host "[AtendIA] Aguarde o icone verde na bandeja do sistema (canto inferior direito)." -ForegroundColor White
  Write-Host "[AtendIA] Quando o Docker estiver verde, pressione ENTER." -ForegroundColor White
  Write-Host ""
  pause
  Write-Host ""
  Write-Host "[AtendIA] Verificando novamente..." -ForegroundColor Cyan
}
Write-Host "[AtendIA] Docker engine pronto! Aguardando estabilizar..." -ForegroundColor Green
Start-Sleep -Seconds 5

# === LIMPEZA DE CONFIGURACAO ANTERIOR ===
Write-Host "[AtendIA] Limpando containers antigos..." -ForegroundColor Cyan

# Para e remove containers antigos do compose (se existir)
if (Test-Path -LiteralPath "docker-compose.evolution.yml") {
  docker compose -f docker-compose.evolution.yml down --remove-orphans 2>$null
  Write-Host "[AtendIA] Containers antigos removidos" -ForegroundColor Gray
}

# Matar qualquer container ocupando porta 8080 (Evolution antiga de outro projeto)
$port8080 = docker ps --filter "publish=8080" --format "{{.ID}}" 2>$null
if ($port8080) {
  Write-Host "[AtendIA] Removendo containers na porta 8080..." -ForegroundColor Yellow
  $port8080 | ForEach-Object { docker stop $_ 2>$null; docker rm $_ 2>$null }
}

# Tambem remover containers com nome atendia (de instalacoes anteriores)
$oldContainers = docker ps -a --filter "name=atendia" --format "{{.ID}}" 2>$null
if ($oldContainers) {
  Write-Host "[AtendIA] Removendo containers atendia antigos..." -ForegroundColor Yellow
  $oldContainers | ForEach-Object { docker stop $_ 2>$null; docker rm $_ 2>$null }
}

if ($Clean) {
  Write-Host "[AtendIA] Modo -Clean: removendo volumes (wipe total)..." -ForegroundColor Yellow
  docker compose -f docker-compose.evolution.yml down --volumes --remove-orphans 2>$null
  docker volume ls --filter "name=atendia" --format "{{.Name}}" 2>$null | ForEach-Object { docker volume rm $_ 2>$null }
  Write-Host "[AtendIA] Volumes removidos (modelos Ollama e dados DB)" -ForegroundColor Gray
} else {
  Write-Host "[AtendIA] Volumes preservados (sessao WhatsApp + modelo Ollama mantidos)" -ForegroundColor Green
}

# Resetar evolution_config.server_url no Supabase (evitar URL fantasma de tunnel morto)
$relaySecret = "relay-atendia-sk-7f3d"
$authHeader = @{ Authorization = "Bearer $relaySecret"; "Content-Type" = "application/json" }
try {
  $resetBody = @{ server_url = "" } | ConvertTo-Json -Depth 3
  Invoke-WebRequest -Uri "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-evolution" -Method POST -Headers $authHeader -Body $resetBody -UseBasicParsing -TimeoutSec 10 | Out-Null
  Write-Host "[AtendIA] evolution_config.server_url resetado (URL fantasma limpa)" -ForegroundColor Green
} catch { Write-Host "[AtendIA] Aviso reset server_url: $_" -ForegroundColor Yellow }

Write-Host "[AtendIA] Verificando volume do Ollama..." -ForegroundColor Cyan
$ollamaVol = docker volume ls --filter "name=atendia-tunnel_ollama_data" --format "{{.Name}}" 2>$null
if (-not $ollamaVol) {
  Write-Host "[AtendIA] Criando volume atendia-tunnel_ollama_data..." -ForegroundColor Yellow
  docker volume create atendia-tunnel_ollama_data | Out-Null
  Write-Host "[AtendIA] Volume criado" -ForegroundColor Green
}

Write-Host "[AtendIA] Baixando imagens Docker..." -ForegroundColor Cyan
$pullOK = $false
for ($i = 1; $i -le 3; $i++) {
  docker compose -f docker-compose.evolution.yml pull 2>$null
  if ($LASTEXITCODE -eq 0) {
    $pullOK = $true
    break
  }
  Write-Host "[AtendIA] Pull falhou (tentativa $i/3), aguardando 15s..." -ForegroundColor Yellow
  Start-Sleep -Seconds 15
}
if (-not $pullOK) {
  Write-Host "[AtendIA] [ERRO] Falha ao baixar imagens Docker apos 3 tentativas." -ForegroundColor Red
  Write-Host "[AtendIA] Verifique sua conexao com a internet e tente novamente." -ForegroundColor Yellow
  Write-Host "[AtendIA] Se o Docker Desktop acabou de iniciar, aguarde 1 minuto e tente novamente." -ForegroundColor Yellow
  exit 1
}

Write-Host "[AtendIA] Subindo containers..." -ForegroundColor Cyan
docker compose -f docker-compose.evolution.yml build --no-cache tunnel-info
docker compose -f docker-compose.evolution.yml up -d --force-recreate
if ($LASTEXITCODE -ne 0) {
  Write-Host "[AtendIA] [ERRO] Falha ao subir os containers" -ForegroundColor Red
  exit 1
}

Write-Host "[AtendIA] Verificando saude dos containers..." -ForegroundColor Cyan
Start-Sleep -Seconds 8
$failed = docker ps -a --filter "label=com.docker.compose.project=atendia-tunnel" --filter "status=exited" --format "{{.Names}}" 2>$null
if ($failed) {
  Write-Host "[AtendIA] [ERRO] Containers falharam ao subir: $failed" -ForegroundColor Red
  $failed | ForEach-Object { Write-Host "[AtendIA] Veja os logs: docker logs $_" -ForegroundColor Gray }
  exit 1
}
Write-Host "[AtendIA] Containers ativos" -ForegroundColor Green

Write-Host "[AtendIA] Baixando modelo Ollama (gemma3:4b)..." -ForegroundColor Cyan
$ollamaContainer = docker ps --filter "ancestor=ollama/ollama" --format "{{.Names}}" 2>$null | Select-Object -First 1
if (-not $ollamaContainer) { $ollamaContainer = docker ps -a --filter "name=ollama" --format "{{.Names}}" 2>$null | Select-Object -First 1 }
if ($ollamaContainer) {
  docker exec $ollamaContainer ollama pull gemma3:4b 2>$null
  Write-Host "[AtendIA] Modelo Ollama pronto" -ForegroundColor Green
} else {
  Write-Host "[AtendIA] [!] Container Ollama nao encontrado" -ForegroundColor Yellow
}

Write-Host "[AtendIA] Aguardando tunnel Cloudflare..." -ForegroundColor Cyan
$tunnelUrl = $null
for ($i = 0; $i -lt 24; $i++) {
  Start-Sleep -Seconds 5
  try {
    $resp = Invoke-WebRequest -Uri "http://localhost:9876/info" -UseBasicParsing -TimeoutSec 3
    $data = $resp.Content | ConvertFrom-Json
    if ($data.status -eq "active" -and $data.tunnel_url) {
      $tunnelUrl = $data.tunnel_url
      break
    }
  } catch {}
}
if (-not $tunnelUrl) {
  Write-Host "[AtendIA] [ERRO] Tunnel nao subiu - verifique: docker logs atendia-tunnel-tunnel-info-1" -ForegroundColor Red
  exit 1
}

$ollamaEndpoint = "$tunnelUrl/ollama"
$evolutionUrl = "$tunnelUrl/evolution"
Write-Host "[AtendIA] Tunnel ativo: $tunnelUrl" -ForegroundColor Green
Write-Host "[AtendIA] Evolution API: $evolutionUrl" -ForegroundColor Green
Write-Host "[AtendIA] Ollama IA: $ollamaEndpoint" -ForegroundColor Green

Write-Host "[AtendIA] Atualizando endpoints no Supabase..." -ForegroundColor Cyan

try {
  $body = @{ tunnel_url = $tunnelUrl } | ConvertTo-Json -Depth 3
  Invoke-WebRequest -Uri "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-tunnel" -Method POST -Headers $authHeader -Body $body -UseBasicParsing -TimeoutSec 10 | Out-Null
  Write-Host "[AtendIA] Ollama endpoint atualizado" -ForegroundColor Green
} catch { Write-Host "[AtendIA] Aviso update-tunnel: $_" -ForegroundColor Yellow }

try {
  $body = @{ server_url = $evolutionUrl } | ConvertTo-Json -Depth 3
  Invoke-WebRequest -Uri "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-evolution" -Method POST -Headers $authHeader -Body $body -UseBasicParsing -TimeoutSec 10 | Out-Null
  Write-Host "[AtendIA] Evolution config atualizado" -ForegroundColor Green
} catch { Write-Host "[AtendIA] Aviso update-evolution: $_" -ForegroundColor Yellow }

if (-not $NoReload) {
  Write-Host "[AtendIA] Iniciando relay em background..." -ForegroundColor Cyan
  $job = Start-Job -ScriptBlock {
    param($folder)
    Set-Location -LiteralPath $folder
    powershell -ExecutionPolicy Bypass -File "relay-whatsapp.ps1"
  } -ArgumentList (Get-Location).Path
  Write-Host "[AtendIA] Relay rodando (Job ID: $($job.Id))" -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  AtendIA Docker Local pronto!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Tunnel URL: $tunnelUrl" -ForegroundColor White
Write-Host "  Evolution API: $evolutionUrl" -ForegroundColor White
Write-Host "  Ollama IA: $ollamaEndpoint" -ForegroundColor White
Write-Host ""
Write-Host "  [!] MODO LOCAL:" -ForegroundColor Yellow
Write-Host "  - O PC precisa ficar ligado enquanto usar" -ForegroundColor Gray
Write-Host "  - Se reiniciar, rode setup.ps1 novamente (URL muda)" -ForegroundColor Gray
Write-Host "  - Para producao estavel, use Railway (opcao 1)" -ForegroundColor Gray
Write-Host "  - Para wipe total (remover modelos Ollama + dados DB): setup.ps1 -Clean" -ForegroundColor Gray
Write-Host ""
if (-not $NoReload) {
  Write-Host "  Relay em background (Job $($job.Id))" -ForegroundColor Yellow
  Write-Host "  Logs: Receive-Job $($job.Id) | Parar: Stop-Job $($job.Id)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  PROXIMO PASSO:" -ForegroundColor Green
Write-Host "  1. Abra https://atend7ia.vercel.app -> Config WhatsApp" -ForegroundColor White
Write-Host "  2. Cole esta URL: $evolutionUrl" -ForegroundColor White
Write-Host "  3. API Key: atendia123 (ou a que voce configurou)" -ForegroundColor White
Write-Host "  4. Clique Testar -> Conectar WhatsApp -> escaneie QR Code" -ForegroundColor White
Write-Host ""
Write-Host "  IA (opcional): Configure no P7Store -> Configuracoes -> IA" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
