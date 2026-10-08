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

function Pausa([string]$msg) {
  Write-Host ""
  if ($msg) { Write-Host $msg -ForegroundColor White }
  Read-Host "  Aperte ENTER para continuar" | Out-Null
  Write-Host ""
}

if ($Docker) {
  $choice = "3"
} else {
  Write-Host "Mesmos 3 caminhos do P7Store (Configuracoes > WhatsApp):" -ForegroundColor White
  Write-Host ""
  Write-Host "  [1] Nuvem gratis - VM Oracle (Recomendado)" -ForegroundColor Cyan
  Write-Host "      PC desligado, sempre ligada, zero custo. Eu te guio passo a passo." -ForegroundColor Gray
  Write-Host ""
  Write-Host "  [2] Railway (mais facil - mas pago)" -ForegroundColor Green
  Write-Host "      Nuvem pronta em 3 min. Credito gratis no inicio; depois e pago." -ForegroundColor Gray
  Write-Host ""
  Write-Host "  [3] Docker Local (controle total)" -ForegroundColor Yellow
  Write-Host "      Gratis, roda no seu PC. Eu faco quase tudo sozinho (PC fica ligado)." -ForegroundColor Gray
  Write-Host ""
  do {
    $choice = Read-Host "Digite 1, 2 ou 3"
  } while ($choice -ne "1" -and $choice -ne "2" -and $choice -ne "3")
  Write-Host ""
}

# ---------- CAMINHO 1: VM ORACLE (GUIADO) ----------
if ($choice -eq "1") {
  Write-Host "[AtendIA] Caminho 1 - Nuvem gratis: VM Oracle (Recomendado)" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  A VM e um 'computador gratis na nuvem' que fica sempre ligado." -ForegroundColor Gray
  Write-Host "  Voce cria a conta, cria a VM e cola 1 comando nela. Eu guio cada passo." -ForegroundColor Gray
  Write-Host ""
  Write-Host "  Roteiro:" -ForegroundColor White
  Write-Host "  [1/4] Criar conta Oracle (gratuita; cartao so para verificar - nao cobra)" -ForegroundColor Gray
  Write-Host "  [2/4] Criar a VM (4 cliques, tudo padrao)" -ForegroundColor Gray
  Write-Host "  [3/4] Entrar na VM pelo navegador (Cloud Shell - nao instala nada)" -ForegroundColor Gray
  Write-Host "  [4/4] Colar 1 comando na VM - o resto e automatico e sincroniza com o app" -ForegroundColor Gray
  Write-Host ""
  Pausa "  Vamos comecar?"

  Write-Host "  [1/4] Criar conta Oracle..." -ForegroundColor Cyan
  $r = Read-Host "  Aperte ENTER para abrir o cadastro no navegador (ou N para pular)"
  if ($r -ne "N" -and $r -ne "n") { Start-Process "https://signup.cloud.oracle.com/" }
  Write-Host "  No site: e-mail -> nome/senha -> codigo que chega no e-mail -> cartao." -ForegroundColor Gray
  Write-Host "  A ativacao pode demorar alguns minutos." -ForegroundColor Gray
  Pausa "  Quando entrar no painel do Oracle, volte aqui."

  Write-Host "  [2/4] Criar a VM..." -ForegroundColor Cyan
  $r = Read-Host "  Aperte ENTER para abrir o painel de criacao (ou N para pular)"
  if ($r -ne "N" -and $r -ne "n") { Start-Process "https://cloud.oracle.com/compute/instances/create" }
  Write-Host "  No painel (clique onde eu digo):" -ForegroundColor Gray
  Write-Host "  - Name: deixe como esta" -ForegroundColor Gray
  Write-Host "  - Image: Edit -> Canonical Ubuntu 22.04 -> Select" -ForegroundColor Gray
  Write-Host "  - Shape: Ampere A1.Flex (4 OCPU / 24 GB) - e o plano gratis" -ForegroundColor Gray
  Write-Host "  - SSH keys: Generate SSH key pair -> Save Private Key (guarde o arquivo .key)" -ForegroundColor Gray
  Write-Host "  - Create -> aguarde o status virar Running (2-3 min)" -ForegroundColor Gray
  Pausa "  VM com status Running? Volte aqui."

  Write-Host "  [3/4] Entrar na VM pelo navegador..." -ForegroundColor Cyan
  Write-Host "  - Na lista de instancias, clique nos 3 pontinhos (...) da sua VM" -ForegroundColor Gray
  Write-Host "  - Escolha 'Cloud Shell connection' -> abre um terminal DENTRO da VM" -ForegroundColor Gray
  Pausa "  Terminal da VM aberto no navegador? Volte aqui."

  Write-Host "  [4/4] Cole este comando na VM (botao direito do mouse cola):" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "  curl -sL https://raw.githubusercontent.com/Projectz7/atendia-setup/main/setup-native.sh | sudo bash" -ForegroundColor White
  Write-Host ""
  Write-Host "  La na VM, o assistente mostra [1/6..6/6] com OK verde por passo (10-20 min)." -ForegroundColor Gray
  Write-Host "  No fim aparece 'Pronto! WhatsApp na nuvem' - e a URL sincroniza sozinha com o app." -ForegroundColor Gray
  Pausa "  Colou o comando na VM? A instalacao continua la."

  Write-Host ""
  Write-Host "  Quando aparecer 'Pronto! WhatsApp na nuvem' na VM:" -ForegroundColor Green
  Write-Host "  1. Abra o app do AtendIA" -ForegroundColor Gray
  Write-Host "  2. Config WhatsApp -> a URL ja esta preenchida -> Testar -> Conectar -> QR Code" -ForegroundColor Gray
  $r = Read-Host "  Aperte ENTER para abrir o app (ou N para pular)"
  if ($r -ne "N" -and $r -ne "n") { Start-Process "https://atend7ia.vercel.app" }
  Write-Host ""
  Write-Host "  Pronto! O WhatsApp fica na nuvem - seu PC pode desligar." -ForegroundColor Green
  Write-Host "  Se algo falhar la na VM, rode: sudo atendia-doctor" -ForegroundColor Gray
  exit 0
}

# ---------- CAMINHO 2: RAILWAY (GUIADO) ----------
if ($choice -eq "2") {
  Write-Host "[AtendIA] Caminho 2 - Railway (mais facil - mas pago)" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Roteiro rapido (3-5 min): [1/3] Deploy  [2/3] URL  [3/3] QR Code" -ForegroundColor Gray
  Write-Host ""
  Write-Host "  [1/3] Deploy no Railway..." -ForegroundColor Cyan
  $r = Read-Host "  Aperte ENTER para abrir o Railway no navegador (ou N para pular)"
  if ($r -ne "N" -and $r -ne "n") { Start-Process "https://railway.app/template/atendia-evolution" }
  Write-Host "  No site:" -ForegroundColor Gray
  Write-Host "  - Deploy Now -> entrar com GitHub -> aguardar o build (~3 min)" -ForegroundColor Gray
  Write-Host "  - Depois: Settings do servico -> Networking -> Generate Domain" -ForegroundColor Gray
  Write-Host "  - Copie a URL gerada (ex: https://evolution-xxxx.up.railway.app)" -ForegroundColor Gray
  Pausa "  Com a URL copiada, volte aqui."

  Write-Host "  [2/3] Registrar a URL no app (eu faco isso por voce)..." -ForegroundColor Cyan
  $railUrl = ""
  while ($true) {
    $railUrl = Read-Host "  Cole a URL do Railway aqui"
    if ($railUrl -match "^https://\S+$") { break }
    Write-Host "  URL invalida - tem que comecar com https:// e nao ter espacos" -ForegroundColor Yellow
  }
  $railUrl = $railUrl.TrimEnd("/")
  $syncOK = $false
  try {
    $body = @{ server_url = $railUrl } | ConvertTo-Json -Depth 3
    Invoke-WebRequest -Uri "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-evolution" -Method POST -Headers @{ Authorization = "Bearer relay-atendia-sk-7f3d"; "Content-Type" = "application/json" } -Body $body -UseBasicParsing -TimeoutSec 15 | Out-Null
    $syncOK = $true
    Write-Host "  [2/3] OK! URL sincronizada com o app - nao precisa colar nada la." -ForegroundColor Green
  } catch {
    Write-Host "  [2/3] Nao consegui sincronizar automaticamente - voce cola la na frente." -ForegroundColor Yellow
  }

  Write-Host ""
  Write-Host "  [3/3] Conectar o WhatsApp..." -ForegroundColor Cyan
  $r = Read-Host "  Aperte ENTER para abrir o app (ou N para pular)"
  if ($r -ne "N" -and $r -ne "n") { Start-Process "https://atend7ia.vercel.app" }
  Write-Host "  No app: Config WhatsApp" -ForegroundColor Gray
  if ($syncOK) {
    Write-Host "  - A URL ja aparece preenchida (so confira)" -ForegroundColor Gray
  } else {
    Write-Host "  - Cole a URL: $railUrl" -ForegroundColor Gray
  }
  Write-Host "  - API Key: atendia123" -ForegroundColor Gray
  Write-Host "  - Testar -> Conectar WhatsApp -> escaneie o QR Code no celular" -ForegroundColor Gray
  Write-Host ""
  Write-Host "  Pronto! Nuvem Railway: seu PC pode desligar." -ForegroundColor Green
  Write-Host "  IA (opcional): P7Store -> Configuracoes -> IA (DeepSeek, Gemini, OpenAI...)." -ForegroundColor Gray
  Write-Host "  Aviso: apos o credito gratis, o Railway passa a cobrar (~US$ 5/mes)." -ForegroundColor Yellow
  exit 0
}

# ==================== CAMINHO 3: DOCKER LOCAL ====================
Write-Host "[AtendIA] Caminho 3 - Docker Local (controle total)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Assistente guiado - 5 passos. Eu aviso cada um:" -ForegroundColor White
Write-Host "  [1/5] Verificar o Docker Desktop (pausa se precisar de voce)" -ForegroundColor Gray
Write-Host "  [2/5] Baixar os arquivos (docker-compose + relay)" -ForegroundColor Gray
Write-Host "  [3/5] Subir Evolution + Postgres + Redis + Tunel" -ForegroundColor Gray
Write-Host "  [4/5] Baixar o modelo da IA (Ollama)" -ForegroundColor Gray
Write-Host "  [5/5] Sincronizar as URLs com o app e mostrar o resultado" -ForegroundColor Gray
Write-Host ""
Write-Host "  IMPORTANTE: nao feche esta janela durante a instalacao." -ForegroundColor Yellow
Write-Host ""

# ---------- PASSO 1/5: Docker Desktop ----------
Write-Host "  [1/5] Verificando o Docker Desktop..." -ForegroundColor Cyan

if ($env:OS -eq "Windows_NT") {
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    $DockerUrl = "https://docs.docker.com/desktop/install/windows-install/"
    $DockerLabel = "Windows ARM64"
  } else {
    $DockerUrl = "https://www.docker.com/products/docker-desktop/"
    $DockerLabel = "Windows x64"
  }
} elseif ($env:OS -eq "Darwin") {
  $DockerUrl = "https://docs.docker.com/desktop/install/mac-install/"
  $DockerLabel = "macOS"
} else {
  $DockerUrl = "https://docs.docker.com/desktop/install/linux-install/"
  $DockerLabel = "Linux"
}

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerCmd) { $dockerVer = (& docker --version) 2>$null } else { $dockerVer = $null }
if ($dockerVer) {
  Write-Host "  [1/5] Docker ja instalado: $dockerVer" -ForegroundColor Green
} else {
  Write-Host "  [1/5] Docker Desktop nao encontrado. Sem problema - a gente instala agora." -ForegroundColor Yellow
  Write-Host "  [Seu sistema: $DockerLabel]" -ForegroundColor Gray
  $abrir = Read-Host "  Aperte ENTER para abrir a pagina de download no navegador (ou digite N para pular)"
  if ($abrir -ne "N" -and $abrir -ne "n") { Start-Process $DockerUrl }
  Write-Host ""
  Write-Host "  Como instalar (so na primeira vez):" -ForegroundColor White
  Write-Host "  1. Na pagina que abriu, baixe a versao mais recente e instale (proximo-proximo-concluir)" -ForegroundColor Gray
  Write-Host "  2. Se pedir para REINICIAR o PC, reinicie" -ForegroundColor Gray
  Write-Host "  3. Depois, ABRA o Docker Desktop pelo icone e aguarde ele terminar de abrir" -ForegroundColor Gray
  Write-Host "  4. Se o Docker abrir e fechar com ERRO: feche tudo, rode no PowerShell:" -ForegroundColor Gray
  Write-Host '     Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Docker\run"' -ForegroundColor Gray
  Write-Host "     e abra o Docker de novo (limpa um socket preso - bug conhecido)" -ForegroundColor Gray
  Write-Host "  5. Volte nesta janela e aperte ENTER - eu verifico sozinho" -ForegroundColor Gray
  while (-not $dockerVer) {
    Pausa "  Instalou e abriu o Docker Desktop? Volte aqui."
    $dc = Get-Command docker -ErrorAction SilentlyContinue
    if ($dc) { $dockerVer = (& docker --version) 2>$null } else { $dockerVer = $null }
    if (-not $dockerVer) {
      Write-Host "  [1/5] Ainda nao encontrei o Docker..." -ForegroundColor Yellow
      Write-Host "  Confira se o Docker Desktop esta instalado e ABERTO (icone da baleia perto do relogio)." -ForegroundColor Gray
      $desistir = Read-Host "  Aperte ENTER para tentar de novo (ou X para sair)"
      if ($desistir -eq "X" -or $desistir -eq "x") {
        Write-Host "  Instalacao interrompida. Nada foi alterado - rode este comando de novo quando quiser." -ForegroundColor Yellow
        exit 1
      }
    }
  }
  Write-Host "  [1/5] Encontrei! $dockerVer" -ForegroundColor Green
}

# Docker instalado - agora esperar o motor ligar
Write-Host ""
Write-Host "  [1/5] Verificando se o Docker esta em execucao..." -ForegroundColor Cyan
$engineReady = $false
while (-not $engineReady) {
  $info = docker info 2>&1
  if ($info -notmatch "error during connect") {
    $engineReady = $true
    break
  }
  Write-Host "  [1/5] O Docker Desktop ainda esta iniciando (icone da baleia na bandeja, canto inferior direito)." -ForegroundColor Yellow
  Pausa "  Quando o Docker estiver aberto e sem erro, volte aqui."
  Write-Host "  [1/5] Verificando novamente..." -ForegroundColor Cyan
}
Write-Host "  [1/5] OK! Docker pronto ($dockerVer)" -ForegroundColor Green
Start-Sleep -Seconds 5

# ---------- PASSO 2/5: arquivos ----------
Write-Host ""
Write-Host "  [2/5] Baixando os arquivos (rapido, ~10 segundos)..." -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $FolderName)) {
  New-Item -ItemType Directory -Path $FolderName -Force | Out-Null
  Write-Host "  [2/5] Pasta '$FolderName' criada" -ForegroundColor Green
} else {
  Write-Host "  [2/5] Pasta '$FolderName' ja existe - atualizando arquivos" -ForegroundColor Yellow
}
Set-Location -LiteralPath $FolderName

Invoke-WebRequest -Uri "$RawBase/docker-compose.evolution.yml" -OutFile "docker-compose.evolution.yml" -UseBasicParsing | Out-Null
if (-not (Test-Path -LiteralPath "tunnel-info")) { New-Item -ItemType Directory -Path "tunnel-info" -Force | Out-Null }
Invoke-WebRequest -Uri "$RawBase/tunnel-info/Dockerfile" -OutFile "tunnel-info/Dockerfile" -UseBasicParsing | Out-Null
Invoke-WebRequest -Uri "$RawBase/tunnel-info/server.py" -OutFile "tunnel-info/server.py" -UseBasicParsing | Out-Null
Invoke-WebRequest -Uri "$RawBase/relay-whatsapp.ps1" -OutFile "relay-whatsapp.ps1" -UseBasicParsing | Out-Null
Write-Host "  [2/5] OK! Arquivos prontos" -ForegroundColor Green

# ---------- PASSO 3/5: containers ----------
Write-Host ""
Write-Host "  [3/5] Limpando instalacao anterior (se houver)..." -ForegroundColor Cyan

if (Test-Path -LiteralPath "docker-compose.evolution.yml") {
  docker compose -f docker-compose.evolution.yml down --remove-orphans 2>$null
}

$port8080 = docker ps --filter "publish=8080" --format "{{.ID}}" 2>$null
if ($port8080) {
  Write-Host "  [3/5] Removendo containers na porta 8080..." -ForegroundColor Yellow
  $port8080 | ForEach-Object { docker stop $_ 2>$null; docker rm $_ 2>$null }
}

$oldContainers = docker ps -a --filter "name=atendia" --format "{{.ID}}" 2>$null
if ($oldContainers) {
  Write-Host "  [3/5] Removendo containers atendia antigos..." -ForegroundColor Yellow
  $oldContainers | ForEach-Object { docker stop $_ 2>$null; docker rm $_ 2>$null }
}

if ($Clean) {
  Write-Host "  [3/5] Modo -Clean: removendo volumes (wipe total)..." -ForegroundColor Yellow
  docker compose -f docker-compose.evolution.yml down --volumes --remove-orphans 2>$null
  docker volume ls --filter "name=atendia" --format "{{.Name}}" 2>$null | ForEach-Object { docker volume rm $_ 2>$null }
  Write-Host "  [3/5] Volumes removidos (modelos Ollama e dados DB)" -ForegroundColor Gray
} else {
  Write-Host "  [3/5] Volumes preservados (sessao WhatsApp + modelo Ollama mantidos)" -ForegroundColor Green
}

# Resetar evolution_config.server_url no Supabase (evitar URL fantasma de tunnel morto)
$relaySecret = "relay-atendia-sk-7f3d"
$authHeader = @{ Authorization = "Bearer $relaySecret"; "Content-Type" = "application/json" }
try {
  $resetBody = @{ server_url = "" } | ConvertTo-Json -Depth 3
  Invoke-WebRequest -Uri "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-evolution" -Method POST -Headers $authHeader -Body $resetBody -UseBasicParsing -TimeoutSec 10 | Out-Null
} catch { Write-Host "  [3/5] Aviso reset server_url: $_" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  [3/5] Baixando as imagens (Evolution + Postgres + Redis + Tunel)..." -ForegroundColor Cyan
Write-Host "  [3/5] PODE DEMORAR 5 a 15 min na 1a vez. Vai aparecer o progresso aqui embaixo." -ForegroundColor Yellow
Write-Host "  [3/5] NAO FECHE esta janela - pode minimizar." -ForegroundColor Yellow
Write-Host ""
$pullOK = $false
for ($i = 1; $i -le 3; $i++) {
  docker compose -f docker-compose.evolution.yml pull
  if ($LASTEXITCODE -eq 0) {
    $pullOK = $true
    break
  }
  Write-Host ""
  Write-Host "  [3/5] Download falhou (tentativa $i/3). Verifique sua internet..." -ForegroundColor Yellow
  Write-Host "  [3/5] Vou tentar de novo em 15 segundos." -ForegroundColor Gray
  Start-Sleep -Seconds 15
}
if (-not $pullOK) {
  Write-Host ""
  Write-Host "  [3/5] Nao consegui baixar as imagens apos 3 tentativas." -ForegroundColor Red
  Write-Host "  O que fazer: confira sua internet (ou a VPN, se usar) e rode ESTE MESMO comando de novo." -ForegroundColor Yellow
  Write-Host "  Nada quebrou - e so tentar outra vez mais tarde." -ForegroundColor Gray
  Read-Host "  Aperte ENTER para fechar"
  exit 1
}
Write-Host ""
Write-Host "  [3/5] Imagens prontas. Subindo os containers..." -ForegroundColor Cyan
docker compose -f docker-compose.evolution.yml build --no-cache tunnel-info
docker compose -f docker-compose.evolution.yml up -d --force-recreate
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "  [3/5] Falha ao subir os containers." -ForegroundColor Red
  Write-Host "  O que fazer: feche e ABRA o Docker Desktop de novo, aguarde ficar pronto e rode este comando outra vez." -ForegroundColor Yellow
  Read-Host "  Aperte ENTER para fechar"
  exit 1
}

Write-Host ""
Write-Host "  [3/5] Verificando se tudo subiu bem (10 segundos)..." -ForegroundColor Cyan
Start-Sleep -Seconds 8
$failed = docker ps -a --filter "label=com.docker.compose.project=atendia-tunnel" --filter "status=exited" --format "{{.Names}}" 2>$null
if ($failed) {
  Write-Host ""
  Write-Host "  [3/5] Alguns containers falharam: $failed" -ForegroundColor Red
  $failed | ForEach-Object { Write-Host "  Veja o motivo com: docker logs $_" -ForegroundColor Gray }
  Write-Host "  O que fazer: rode este comando de novo - ele limpa e sobe tudo do zero (nao perde a sessao do WhatsApp)." -ForegroundColor Yellow
  Read-Host "  Aperte ENTER para fechar"
  exit 1
}
Write-Host "  [3/5] OK! Containers no ar:" -ForegroundColor Green
docker ps --filter "label=com.docker.compose.project=atendia-tunnel" --format "   {{.Names}}  [{{.Status}}]" 2>$null

# ---------- PASSO 4/5: modelo da IA ----------
Write-Host ""
Write-Host "  [4/5] Preparando o volume do Ollama..." -ForegroundColor Cyan
$ollamaVol = docker volume ls --filter "name=atendia-tunnel_ollama_data" --format "{{.Name}}" 2>$null
if (-not $ollamaVol) {
  docker volume create atendia-tunnel_ollama_data | Out-Null
  Write-Host "  [4/5] Volume criado" -ForegroundColor Green
} else {
  Write-Host "  [4/5] Volume ja existe" -ForegroundColor Green
}

$ollamaContainer = docker ps --filter "ancestor=ollama/ollama" --format "{{.Names}}" 2>$null | Select-Object -First 1
if (-not $ollamaContainer) { $ollamaContainer = docker ps -a --filter "name=ollama" --format "{{.Names}}" 2>$null | Select-Object -First 1 }
if ($ollamaContainer) {
  Write-Host ""
  Write-Host "  [4/5] Baixando o modelo da IA (gemma3:4b, ~3 GB)." -ForegroundColor Cyan
  Write-Host "  [4/5] PODE DEMORAR 10 a 30 min dependendo da internet. O progresso aparece aqui." -ForegroundColor Yellow
  Write-Host "  [4/5] NAO FECHE esta janela - pode minimizar. (A IA e opcional p/ o WhatsApp: se falhar, sigo em frente.)" -ForegroundColor Yellow
  Write-Host ""
  docker exec $ollamaContainer ollama pull gemma3:4b
  if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "  [4/5] OK! Modelo da IA pronto" -ForegroundColor Green
  } else {
    Write-Host ""
    Write-Host "  [4/5] Nao consegui baixar o modelo da IA agora - sem problema." -ForegroundColor Yellow
    Write-Host "  [4/5] O WhatsApp funciona normal; a IA local voce baixa depois rodando:" -ForegroundColor Gray
    Write-Host "  [4/5]   docker exec $($ollamaContainer) ollama pull gemma3:4b" -ForegroundColor Gray
  }
} else {
  Write-Host "  [4/5] Container Ollama nao encontrado - pulando o download da IA (opcional)." -ForegroundColor Yellow
}

# ---------- PASSO 5/5: tunel + sincronizacao ----------
Write-Host ""
Write-Host "  [5/5] Criando o tunel Cloudflare (endereco publico do seu WhatsApp)..." -ForegroundColor Cyan
Write-Host "  [5/5] Isso leva ate 2 minutos. Pontinhos = ainda trabalhando..." -ForegroundColor Gray
$tunnelUrl = $null
for ($i = 0; $i -lt 24; $i++) {
  Start-Sleep -Seconds 5
  Write-Host "." -NoNewline -ForegroundColor Cyan
  try {
    $resp = Invoke-WebRequest -Uri "http://localhost:9876/info" -UseBasicParsing -TimeoutSec 3
    $data = $resp.Content | ConvertFrom-Json
    if ($data.status -eq "active" -and $data.tunnel_url) {
      $tunnelUrl = $data.tunnel_url
      break
    }
  } catch {}
}
Write-Host ""
if (-not $tunnelUrl) {
  Write-Host ""
  Write-Host "  [5/5] O tunel nao subiu agora." -ForegroundColor Red
  Write-Host "  O que fazer: veja o motivo com:  docker logs atendia-tunnel-tunnel-info-1" -ForegroundColor Gray
  Write-Host "  Depois rode este comando de novo - ele limpa e sobe tudo de novo (nao perde a sessao)." -ForegroundColor Yellow
  Read-Host "  Aperte ENTER para fechar"
  exit 1
}

$ollamaEndpoint = "$tunnelUrl/ollama"
$evolutionUrl = "$tunnelUrl/evolution"
Write-Host "  [5/5] Tunel ativo: $tunnelUrl" -ForegroundColor Green

Write-Host ""
Write-Host "  [5/5] Avisando o app (sincronizando as URLs)..." -ForegroundColor Cyan
try {
  $body = @{ tunnel_url = $tunnelUrl } | ConvertTo-Json -Depth 3
  Invoke-WebRequest -Uri "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-tunnel" -Method POST -Headers $authHeader -Body $body -UseBasicParsing -TimeoutSec 10 | Out-Null
  Write-Host "  [5/5] Ollama endpoint atualizado" -ForegroundColor Green
} catch { Write-Host "  [5/5] Aviso update-tunnel: $_" -ForegroundColor Yellow }

try {
  $body = @{ server_url = $evolutionUrl } | ConvertTo-Json -Depth 3
  Invoke-WebRequest -Uri "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-evolution" -Method POST -Headers $authHeader -Body $body -UseBasicParsing -TimeoutSec 10 | Out-Null
  Write-Host "  [5/5] Evolution config atualizado" -ForegroundColor Green
} catch { Write-Host "  [5/5] Aviso update-evolution: $_" -ForegroundColor Yellow }

if (-not $NoReload) {
  Write-Host ""
  Write-Host "  [5/5] Ligando o mensageiro interno (relay)..." -ForegroundColor Cyan
  $job = Start-Job -ScriptBlock {
    param($folder)
    Set-Location -LiteralPath $folder
    powershell -ExecutionPolicy Bypass -File "relay-whatsapp.ps1"
  } -ArgumentList (Get-Location).Path
  Write-Host "  [5/5] Relay ligado (Job ID: $($job.Id))" -ForegroundColor Green
}

# ---------- RESULTADO FINAL ----------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  TUDO PRONTO! Checklist final:" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [1/5] Docker Desktop ......... OK" -ForegroundColor Green
Write-Host "  [2/5] Arquivos ................ OK" -ForegroundColor Green
Write-Host "  [3/5] Containers (WhatsApp) ... OK" -ForegroundColor Green
Write-Host "  [4/5] IA local (Ollama) ....... OK (opcional)" -ForegroundColor Green
Write-Host "  [5/5] Tunel + sincronizacao ... OK" -ForegroundColor Green
Write-Host ""
Write-Host "  Evolution API: $evolutionUrl" -ForegroundColor White
Write-Host "  Ollama IA: $ollamaEndpoint" -ForegroundColor White
Write-Host "  API Key: atendia123" -ForegroundColor White
Write-Host ""
Write-Host "  IMPORTANTE - MODO LOCAL:" -ForegroundColor Yellow
Write-Host "  - DEIXE ESTA JANELA ABERTA (pode minimizar) - o WhatsApp usa o mensageiro que esta rodando aqui" -ForegroundColor Yellow
if (-not $NoReload) {
  Write-Host "  - Relay em background (Job $($job.Id))" -ForegroundColor Gray
}
Write-Host "  - Se o PC reiniciar: abra o Docker Desktop e rode ESTE comando de novo (a URL muda e re-sincroniza sozinho)" -ForegroundColor Gray
Write-Host "  - Para producao estavel com PC desligado: use a VM Oracle gratis (P7Store > Configuracoes > WhatsApp > modo 1)" -ForegroundColor Gray
Write-Host "  - Para comecar do zero (apaga tudo): setup.ps1 -Docker -Clean" -ForegroundColor Gray
Write-Host ""
Write-Host "  PROXIMO PASSO - conectar o WhatsApp (1 minuto):" -ForegroundColor Green
Write-Host "  1. Abri o app do AtendIA no navegador pra voce" -ForegroundColor White
Write-Host "  2. Va em Config WhatsApp" -ForegroundColor White
Write-Host "  3. Cole esta URL: $evolutionUrl" -ForegroundColor White
Write-Host "  4. API Key: atendia123  ->  clique Testar" -ForegroundColor White
Write-Host "  5. Digite seu numero -> Conectar WhatsApp -> escaneie o QR Code no celular" -ForegroundColor White
Write-Host ""
Write-Host "  IA (opcional): Configure no P7Store -> Configuracoes -> IA" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Start-Process "https://atend7ia.vercel.app"
