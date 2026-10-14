param(
  [string]$FolderName = "atendia-tunnel",
  [switch]$Docker,
  [switch]$NoReload,
  [switch]$Clean,
  [switch]$Reset,
  [switch]$Limpar
)

$SupabaseUrl = "https://pnijzmqygibhwbcnkklm.supabase.co"
$RawBase = "https://raw.githubusercontent.com/Projectz7/atendia-setup/main"

# TLS 1.2: PowerShell 5.1 nao usa por padrao e o GitHub exige - sem isso todo download falha com
# "Could not create SSL/TLS secure channel".
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# Pasta base FIXA no perfil do usuario: "Executar como administrador" abre o PowerShell no
# system32 (nao da pra escrever la) - com base fixa a instalacao sempre cai num lugar que funciona.
$BaseDir = Join-Path $env:USERPROFILE $FolderName

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

# Relatorio de erro na AREA DE TRABALHO (nunca em system32 quando roda como admin).
# O usuario anexa no WhatsApp do suporte - diagnostico completo sem esforco.
function Dump-Erro([string]$motivo) {
  try {
    $desk = [Environment]::GetFolderPath('Desktop')
    $file = Join-Path $desk "ATENDIA-ERRO.txt"
    $lines = @()
    $lines += "AtendIA - relatorio de erro automatico"
    $lines += "Quando: $(Get-Date -Format 'yyyy-MM-dd HH:mm')  |  Motivo: $motivo"
    $lines += ""
    $lines += "== TODOS os containers =="
    $lines += (docker ps -a --format "{{.Names}}  |  {{.Image}}  |  {{.Status}}") 2>$null
    $lines += ""
    $lines += "== Estado do compose (atendia-tunnel) =="
    $lines += (docker compose -f docker-compose.evolution.yml ps -a) 2>$null
    $lines += ""
    $lines += "== Espaco em disco C: =="
    $lines += "Livre: $([math]::Round((Get-PSDrive C).Free/1GB,1)) GB"
    $lines += ""
    $lines += "== Versoes do Docker =="
    $lines += (docker version --format "Client {{.Client.Version}} / Server {{.Server.Version}}") 2>$null
    $lines += (docker compose version) 2>$null
    $lines += "OSType: " + ((docker info --format "{{.OSType}}") 2>$null)
    $lines += ""
    $lines += "== WSL (base do Docker no Windows) =="
    $lines += (wsl --status) 2>$null
    $lines += (wsl -l -v) 2>$null
    $lines += ""
    $lines += "== Uso de disco do Docker (o 'lixo' mora aqui) =="
    $lines += (docker system df) 2>$null
    $lines += ""
    $lines += "== Portas 8080 / 9876 (quem esta escutando) =="
    $lines += (netstat -ano | Where-Object { $_ -match ":8080\s.*LISTENING|:9876\s.*LISTENING" })
    $lines += ""
    $lines += "== Logs de TODOS os servicos da stack (ultimas 30 linhas de cada) =="
    foreach ($s in @(docker compose -f docker-compose.evolution.yml ps -a --format "{{.Name}}" 2>$null)) { $lines += "--- $s ---"; $lines += (docker logs --tail 30 $s) 2>$null; $lines += "" }
    $lines += ""
    $lines += "== Logs dos containers parados (ultimas 60 linhas de cada) =="
    $bad = docker ps -a --filter "status=exited" --format "{{.Names}}" 2>$null
    foreach ($b in $bad) { $lines += "--- $b ---"; $lines += (docker logs --tail 60 $b) 2>$null; $lines += "" }
    $lines | Set-Content -Path $file -Encoding UTF8
    Write-Host "  Salvei um relatorio completo na AREA DE TRABALHO: ATENDIA-ERRO.txt" -ForegroundColor Yellow
    Write-Host "  Mande esse arquivo pro suporte (pode anexar no WhatsApp) - ele resolve com isso." -ForegroundColor Gray
  } catch { Write-Host "  (nao consegui salvar o relatorio: $_)" -ForegroundColor DarkGray }
}

# ---------- VARREDURA DE LIXO SEGURO (roda sempre, nao toca em nada util) ----------
# Remove os "restos de obra": cozinhas de build do Docker paradas (containers de nome
# aleatorio tipo beautiful_mestorf, imagem moby/buildkit) e imagens dangling (<none>).
# Nao remove: containers rodando, volumes, imagens com tag.
function Varrer-Lixo {
  $varridos = 0
  foreach ($anc in @("moby/buildkit:buildx-stable-1", "moby/buildkit:master")) {
    $cozinhas = @(docker ps -aq --filter "ancestor=$anc" --filter "status=exited" 2>$null)
    foreach ($c in $cozinhas) { docker rm -f $c 2>$null | Out-Null; $varridos++ }
  }
  $dan = docker image prune -f 2>$null
  if ($dan -match "Total reclaimed") { $varridos++ }
  if ($varridos -gt 0) {
    Write-Host "  (varri $varridos resto(s) de obra do Docker)" -ForegroundColor DarkGray
  }
}

# ---------- LIMPEZA COMPLETA DA INSTALACAO (unificada) ----------
# $Tudo = $false -> MANTER A IA: preserva o volume dos modelos (atendia-tunnel_ollama_data)
#                      e a imagem do Ollama. Apaga todo o resto da stack e o lixo.
# $Tudo = $true  -> WIPE TOTAL: apaga tambem o volume dos modelos (sessao + IA do zero).
# Usada por -Reset, -Clean, -Limpar e pela limpeza automatica quando containers falham.
function Limpar-Instalacao([bool]$Tudo) {
  # 1) Derruba o compose do projeto (se existir yml nesta pasta)
  if (Test-Path -LiteralPath "docker-compose.evolution.yml") {
    docker compose -f docker-compose.evolution.yml down --remove-orphans 2>$null
  }

  # 2) Containers: do projeto (label), qualquer "atendia" e as cozinhas de build paradas
  $ids = @()
  $ids += @(docker ps -aq --filter "label=com.docker.compose.project=$FolderName" 2>$null)
  $ids += @(docker ps -aq --filter "name=atendia" 2>$null)
  foreach ($anc in @("moby/buildkit:buildx-stable-1", "moby/buildkit:master")) {
    $ids += @(docker ps -aq --filter "ancestor=$anc" --filter "status=exited" 2>$null)
  }
  $ids = @($ids | Where-Object { $_ } | Sort-Object -Unique)
  if ($ids.Count -gt 0) { docker rm -f @($ids) 2>$null | Out-Null }

  # 3) Volumes atendia* (menos ollama, se mantendo a IA)
  $vols = @(docker volume ls --format "{{.Name}}" 2>$null | Where-Object { $_ -like "atendia*" })
  foreach ($v in $vols) {
    if (-not $Tudo -and $v -match "ollama") { continue }
    docker volume rm $v 2>$null | Out-Null
  }

  # 4) Imagens: da stack + built do projeto + dangling. Ollama so no wipe total.
  $refs = @("postgres:15", "redis:7-alpine", "evoapicloud/evolution-api:latest")
  if ($Tudo) { $refs += @(docker images --format "{{.Repository}}:{{.Tag}}" 2>$null | Where-Object { $_ -like "ollama/*" }) }
  foreach ($r in $refs) { docker image rm -f $r 2>$null | Out-Null }
  $labeled = @(docker images --filter "label=com.docker.compose.project=$FolderName" --format "{{.ID}}" 2>$null)
  foreach ($im in $labeled) { docker image rm -f $im 2>$null | Out-Null }
  docker image prune -f 2>$null | Out-Null

  # 5) Cache de build (o maior lixo invisivel - gigas de camadas velhas de tentativas)
  docker builder prune -a -f 2>$null | Out-Null

  # 6) Conferencia honesta
  $rC = @(docker ps -aq --filter "label=com.docker.compose.project=$FolderName" 2>$null).Count
  $rV = @((docker volume ls --format "{{.Name}}" 2>$null | Where-Object { $_ -like "atendia*" -and ($Tudo -or $_ -notmatch "ollama") })).Count
  $rI = @((docker images --format "{{.Repository}}:{{.Tag}}" 2>$null | Where-Object { $_ -in @("postgres:15", "redis:7-alpine", "evoapicloud/evolution-api:latest") })).Count
  if ($Tudo) { $rI += @((docker images --format "{{.Repository}}:{{.Tag}}" 2>$null | Where-Object { $_ -like "ollama/*" })).Count }
  Write-Host "  Sobrou da limpeza: $rC container(es) do projeto, $rV volume(ns), $rI imagem(ns) da stack." -ForegroundColor $(if ($rC -eq 0 -and $rV -eq 0 -and $rI -eq 0) { "Green" } else { "Yellow" })
}

if ($Limpar) {
  Write-Host ""
  Write-Host "  MODO LIMPEZA TOTAL DO DOCKER" -ForegroundColor Magenta
  Write-Host "  Apaga TUDO que o Docker tem neste PC: containers, volumes, imagens," -ForegroundColor White
  Write-Host "  redes, cache de build e instalacoes anteriores do AtendIA." -ForegroundColor White
  Write-Host ""
  Write-Host "  Sobre nomes estranhos tipo 'beautiful_mestorf' ou 'heuristic_blackwell':" -ForegroundColor Gray
  Write-Host "  sao COZINHAS TEMPORARIAS que o Docker monta na hora de construir as imagens" -ForegroundColor Gray
  Write-Host "  (build). Nao sao virus nem programas instalados - sao resto de obra." -ForegroundColor Gray
  Write-Host "  Este modo varre tudo isso tambem." -ForegroundColor Gray
  Write-Host ""
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "  Docker nao esta instalado - nao ha nada para limpar. Tudo certo!" -ForegroundColor Green
    Read-Host "  Aperte ENTER para fechar" | Out-Null
    exit 0
  }
  docker info *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  O Docker Desktop esta fechado. Abra-o (baleia na bandeja, espere o verde)" -ForegroundColor Yellow
    Write-Host "  e rode este comando de novo." -ForegroundColor Yellow
    Read-Host "  Aperte ENTER para fechar" | Out-Null
    exit 0
  }
  Write-Host ""
  Write-Host "  O QUE EXISTE AGORA (inventario completo, antes de apagar):" -ForegroundColor Cyan
  Write-Host ""
  $allC = docker ps -a --format "   {{.Names}}  |  {{.Image}}  |  {{.Status}}" 2>$null
  if ($allC) { Write-Host "   CONTAINERS:" -ForegroundColor White; $allC | ForEach-Object { Write-Host $_ } } else { Write-Host "   CONTAINERS: nenhum" -ForegroundColor Gray }
  Write-Host ""
  $allV = docker volume ls --format "   {{.Name}}" 2>$null
  if ($allV) { Write-Host "   VOLUMES (dados guardados):" -ForegroundColor White; $allV | ForEach-Object { Write-Host $_ } } else { Write-Host "   VOLUMES: nenhum" -ForegroundColor Gray }
  Write-Host ""
  $allI = docker images --format "   {{.Repository}}:{{.Tag}}  ({{.Size}})" 2>$null
  if ($allI) { Write-Host "   IMAGENS (programas baixados):" -ForegroundColor White; $allI | ForEach-Object { Write-Host $_ } } else { Write-Host "   IMAGENS: nenhuma" -ForegroundColor Gray }
  Write-Host ""
  Write-Host "  AVISO: o WhatsApp local desconecta e a IA local some ate reinstalar." -ForegroundColor Yellow
  Write-Host "  As conversas dos clientes FICAM salvas no app (sao guardadas na nuvem)." -ForegroundColor Gray
  Write-Host "  Depois da limpeza, rode a instalacao de novo (baixa tudo do zero, 15-30 min)" -ForegroundColor Gray
  Write-Host "  e o WhatsApp pede um novo QR Code." -ForegroundColor Gray
  Write-Host ""
  $conf = Read-Host "  Digite APAGAR (em maiusculas) para confirmar, ou ENTER para cancelar"
  if ($conf -ne "APAGAR") {
    Write-Host "  Cancelado - nada foi apagado." -ForegroundColor Green
    Read-Host "  Aperte ENTER para fechar" | Out-Null
    exit 0
  }
  Write-Host ""
  Write-Host "  Apagando containers..." -ForegroundColor Cyan
  $ids = docker ps -aq 2>$null
  if ($ids) { docker rm -f $ids 2>$null }
  Write-Host "  Apagando volumes..." -ForegroundColor Cyan
  $vols = docker volume ls -q 2>$null
  if ($vols) { docker volume rm $vols 2>$null }
  Write-Host "  Apagando imagens..." -ForegroundColor Cyan
  $imgs = docker images -aq 2>$null
  if ($imgs) { docker image rm -f $imgs 2>$null }
  Write-Host "  Apagando redes, cache de build e resto de obra..." -ForegroundColor Cyan
  docker network prune -f *> $null
  docker builder prune -a -f *> $null
  docker system prune -f *> $null
  Write-Host ""
  $leftC = @(docker ps -aq 2>$null); $leftV = @(docker volume ls -q 2>$null); $leftI = @(docker images -aq 2>$null)
  Write-Host "  RESULTADO FINAL: $($leftC.Count) containers, $($leftV.Count) volumes, $($leftI.Count) imagens." -ForegroundColor Green
  Write-Host ""
  Write-Host "  Tudo limpo! Agora instale do zero com as 2 linhas do assistente." -ForegroundColor White
  Read-Host "  Aperte ENTER para fechar" | Out-Null
  exit 0
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

# ---------- PRE-REQUISITOS Windows (WSL 2 + Plataforma de VM) ----------
if ($env:OS -eq "Windows_NT") {
  Write-Host ""
  Write-Host "  [1/5] Conferindo os pre-requisitos do Windows (WSL)..." -ForegroundColor Cyan
  $temVm  = [bool](Get-Service vmcompute -ErrorAction SilentlyContinue)
  $temWsl = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)

  if (-not $temVm) {
    $vtOn = $null
    try { $vtOn = (Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled } catch {}
    if ($vtOn -eq $false) {
      Write-Host ""
      Write-Host "  A VIRTUALIZACAO do processador esta DESLIGADA na BIOS - so voce pode ativar." -ForegroundColor Red
      Write-Host "  Como ativar: desligue o PC, ligue de novo e aperte a tecla da BIOS (DEL, F2 ou F12)." -ForegroundColor White
      Write-Host "  Procure Virtualization / VT-x / SVM Mode e mude para Enabled. Salve e ligue o PC." -ForegroundColor White
      Write-Host "  Depois rode este comando de novo que eu continuo daqui." -ForegroundColor White
      Read-Host "  Aperte ENTER para fechar"
      exit 1
    }
  }

  if (-not ($temWsl -and $temVm)) {
    Write-Host "  Faltam recursos do Windows (WSL 2 / Plataforma de Maquina Virtual)." -ForegroundColor Yellow
    Write-Host "  Vou instala-los agora. Vai abrir uma janela pedindo ADMINISTRADOR:" -ForegroundColor White
    Write-Host "  clique em SIM e espere terminar (alguns minutos)." -ForegroundColor White
    $fixPath = Join-Path $env:TEMP "atendia-wsl-fix.ps1"
    @'
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
netsh winsock reset
Write-Host ""
Write-Host "CONCLUIDO!" -ForegroundColor Green
Read-Host "Aperte ENTER para fechar esta janela"
'@ | Set-Content -Path $fixPath -Encoding UTF8
    try {
      Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$fixPath`""
    } catch {
      Write-Host ""
      Write-Host "  Voce cancelou a janela de administrador - sem ela nao consigo instalar o WSL." -ForegroundColor Red
      Write-Host "  Rode este comando de novo e clique em SIM quando a janela aparecer." -ForegroundColor Yellow
      Read-Host "  Aperte ENTER para fechar"
      exit 1
    }
    $temWsl2 = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)
    $temVm2  = [bool](Get-Service vmcompute -ErrorAction SilentlyContinue)
    if ($temWsl2 -and $temVm2) {
      Write-Host "  OK! Recursos do Windows instalados." -ForegroundColor Green
    } else {
      Write-Host ""
      Write-Host "  Recursos instalados! Agora e OBRIGATORIO reiniciar o PC (normal apos essa instalacao)." -ForegroundColor Yellow
      Write-Host "  Depois de reiniciar, abra o PowerShell e rode ESTE comando de novo - eu continuo daqui." -ForegroundColor White
      Read-Host "  Aperte ENTER para fechar"
      exit 0
    }
  } else {
    Write-Host "  [1/5] WSL 2 e virtualizacao OK." -ForegroundColor Green
  }

  $livreGB = [math]::Round((Get-PSDrive C).Free / 1GB)
  if ($livreGB -lt 15) {
    Write-Host ""
    Write-Host "  ATENCAO: pouco espaco no disco C: ($livreGB GB livres). A instalacao usa ~12 GB." -ForegroundColor Yellow
    Write-Host "  Se nao couber, libere espaco antes de continuar." -ForegroundColor Gray
  }
  Write-Host ""
}

# ---------- PASSO 1/5: Docker Desktop ----------
Write-Host "  [1/5] Verificando o Docker Desktop..." -ForegroundColor Cyan

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
  Write-Host "  1. O download do instalador comecou no navegador - ao terminar, abra o arquivo baixado e instale (proximo-proximo-concluir)" -ForegroundColor Gray
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
$tentEngine = 0
while (-not $engineReady) {
  $info = docker info 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0 -and $info -notmatch "error during connect|cannot connect|named pipe|timeout") {
    $engineReady = $true
    break
  }
  $tentEngine++
  Write-Host "  [1/5] O Docker Desktop ainda esta iniciando (icone da baleia na bandeja, canto inferior direito)." -ForegroundColor Yellow
  if ($tentEngine -ge 3) {
    Write-Host ""
    Write-Host "  Demorando mais que o normal. Se nao subir, tente na ordem:" -ForegroundColor White
    Write-Host "  1. Botao direito na baleia -> Restart (ou feche e abra o Docker Desktop)" -ForegroundColor Gray
    Write-Host "  2. Se puder, rode no PowerShell como admin:  wsl --update   (e reinicie o Docker)" -ForegroundColor Gray
    Write-Host "  3. Veja se a baleia nao esta no modo 'Windows containers' - tem que ser Linux (padrao)" -ForegroundColor Gray
    if ($info -match "not enough memory|WSL") {
      Write-Host "  O Docker reclamou de memoria/WSL: feche programas pesados e reinicie o PC." -ForegroundColor Gray
    }
    Write-Host ""
  }
  Pausa "  Quando o Docker estiver aberto e sem erro, volte aqui."
  Write-Host "  [1/5] Verificando novamente..." -ForegroundColor Cyan
}
Write-Host "  [1/5] OK! Docker pronto ($dockerVer)" -ForegroundColor Green
Start-Sleep -Seconds 5

# Docker Desktop muito antigo (sem "docker compose") nao funciona - avisa em vez de errar esquisito
docker compose version *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "  Este Docker Desktop e muito antigo (nao tem 'docker compose')." -ForegroundColor Red
  Write-Host "  Atualize o Docker Desktop (baleia -> Troubleshoot -> Update, ou baixe o novo em docker.com)" -ForegroundColor Yellow
  Read-Host "  Aperte ENTER para fechar"
  exit 1
}

# Engine tem que ser Linux (modo Windows containers nao roda esta stack)
$osType = (docker info --format "{{.OSType}}") 2>$null
if ($osType -eq "windows") {
  Write-Host ""
  Write-Host "  O Docker esta no modo WINDOWS containers - esta stack precisa do modo Linux." -ForegroundColor Red
  Write-Host "  Clique com o botao direito na baleia da bandeja e escolha 'Switch to Linux containers...'" -ForegroundColor Yellow
  Read-Host "  Depois de alternar, aperte ENTER para fechar e rode este comando de novo"
  exit 1
}

# ---------- PASSO 2/5: arquivos ----------
Write-Host ""
Write-Host "  [2/5] Baixando os arquivos (rapido, ~10 segundos)..." -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $BaseDir)) {
  New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
  Write-Host "  [2/5] Pasta '$FolderName' criada (em $BaseDir)" -ForegroundColor Green
} else {
  Write-Host "  [2/5] Pasta '$FolderName' ja existe - atualizando arquivos" -ForegroundColor Yellow
}
Set-Location -LiteralPath $BaseDir

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

# Conflito de portas: 8080 = Evolution, 9876 = tunel. O filtro "publish=" nao existe em
# Docker antigo (falha silenciosa) - aqui leio a coluna de portas que funciona em qualquer versao.
foreach ($porta in @(8080, 9876)) {
  $donos = docker ps --format "{{.ID}}  {{.Ports}}" 2>$null | Where-Object { $_ -match ":$porta->" }
  if ($donos) {
    Write-Host "  [3/5] Porta $porta ocupada por outro container - removendo..." -ForegroundColor Yellow
    $donos | ForEach-Object { $cid = ($_ -split "\s+")[0]; docker stop $cid 2>$null; docker rm -f $cid 2>$null }
  }
}

# Programa NATIVO do Windows (nao-Docker) segurando a porta? Aviso com o nome - nao mato sozinho.
foreach ($porta in @(8080, 9876)) {
  $linha = netstat -ano 2>$null | Where-Object { $_ -match ":$porta\s+.+LISTENING" } | Select-Object -First 1
  if ($linha) {
    $procId = ($linha.Trim() -split "\s+")[-1]
    if ($procId -and $procId -ne "0") {
      $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
      $nomeProc = if ($proc) { $proc.ProcessName } else { "PID $procId" }
      if ($nomeProc -notmatch "com\.docker|docker|wsl|vmmem") {
        Write-Host "  [3/5] ATENCAO: o programa '$nomeProc' do Windows esta usando a porta $porta." -ForegroundColor Yellow
        Write-Host "          Feche-o antes de continuar (ou a instalacao vai falhar nessa porta)." -ForegroundColor Gray
      }
    }
  }
}

$oldContainers = docker ps -a --filter "name=atendia" --format "{{.ID}}" 2>$null
if ($oldContainers) {
  Write-Host "  [3/5] Removendo containers atendia antigos..." -ForegroundColor Yellow
  $oldContainers | ForEach-Object { docker stop $_ 2>$null; docker rm $_ 2>$null }
}

if ($Clean) {
  Write-Host "  [3/5] Modo -Clean: limpando TUDO (containers, volumes, imagens, cache de build," -ForegroundColor Yellow
  Write-Host "          resto de obra - inclusive os modelos da IA)..." -ForegroundColor Yellow
  Limpar-Instalacao $true
  Write-Host "  [3/5] Limpo do zero absoluto - tudo sera baixado de novo (QR novo)." -ForegroundColor Green
} elseif ($Reset) {
  Write-Host "  [3/5] Modo -Reset: limpando containers, volumes de dados, imagens, cache de build" -ForegroundColor Yellow
  Write-Host "          e resto de obra (cozinhas de build de nome aleatorio)..." -ForegroundColor Yellow
  Limpar-Instalacao $false
  Write-Host "  [3/5] Limpo! So a IA (modelos Ollama) ficou salva - todo o resto foi reinstalado do zero." -ForegroundColor Green
} else {
  Write-Host "  [3/5] Volumes preservados (sessao WhatsApp + modelo Ollama mantidos)" -ForegroundColor Green
  Varrer-Lixo
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
  Varrer-Lixo
  if ($i -eq 2) {
    Write-Host "  [3/5] Antes da ultima tentativa: apagando imagens meio-baixadas (camada corrompida e causa comum)..." -ForegroundColor Gray
    foreach ($r in @("postgres:15", "redis:7-alpine", "evoapicloud/evolution-api:latest")) { docker image rm -f $r 2>$null }
  }
  Write-Host "  [3/5] Vou tentar de novo em 15 segundos." -ForegroundColor Gray
  Start-Sleep -Seconds 15
}
if (-not $pullOK) {
  Write-Host ""
  Write-Host "  [3/5] Nao consegui baixar as imagens apos 3 tentativas." -ForegroundColor Red
  Write-Host "  O que fazer: confira sua internet (ou a VPN, se usar) e rode ESTE MESMO comando de novo." -ForegroundColor Yellow
  Write-Host "  Nada quebrou - e so tentar outra vez mais tarde." -ForegroundColor Gray
  Varrer-Lixo
  Dump-Erro "download-imagens-falhou"
  Read-Host "  Aperte ENTER para fechar"
  exit 1
}
Write-Host ""
Write-Host "  [3/5] Imagens prontas. Subindo os containers..." -ForegroundColor Cyan
# O volume dos modelos (ollama) e declarado EXTERNO no yml - precisa existir ANTES do compose up.
# docker volume create e idempotente: se o volume ja existe, nao faz nada (modelos preservados).
docker volume create atendia-tunnel_ollama_data | Out-Null
$tentUp = 0
while ($true) {
  $exited = @()
  docker compose -f docker-compose.evolution.yml build --no-cache tunnel-info
  docker compose -f docker-compose.evolution.yml up -d --force-recreate
  $upOK = ($LASTEXITCODE -eq 0)
  if ($upOK) {
    Write-Host ""
    Write-Host "  [3/5] Verificando se tudo subiu e FICOU no ar (ate 20 segundos)..." -ForegroundColor Cyan
    $estavel = $false
    foreach ($cheque in @(1, 2)) {
      Start-Sleep -Seconds 8
      # Somente containers DE SERVICO do compose contam (restos de build tem nome aleatorio e nao sao falha)
      $exited = @(docker ps -a --filter "label=com.docker.compose.project=$FolderName" --filter "status=exited" --format "{{.Names}}" 2>$null)
      $totalC = @(docker ps -a --filter "label=com.docker.compose.project=$FolderName" --format "{{.ID}}" 2>$null).Count
      $runC   = @(docker ps    --filter "label=com.docker.compose.project=$FolderName" --format "{{.ID}}" 2>$null).Count
      if ($exited.Count -eq 0 -and $totalC -ge 4 -and $totalC -eq $runC) { $estavel = $true; break }
    }
    if ($estavel) { break }
  }

  $tentUp++
  Write-Host ""
  if ($upOK) {
    Write-Host "  [3/5] Alguns containers nao ficaram no ar (tentativa $tentUp/3)." -ForegroundColor Red
  } else {
    Write-Host "  [3/5] Falha ao subir os containers (tentativa $tentUp/3)." -ForegroundColor Red
  }
  $logTxt = @()
  if ($exited -and $exited.Count -gt 0) {
    $exited | ForEach-Object {
      Write-Host ""
      Write-Host "  === Ultimas linhas de $_ ===" -ForegroundColor Yellow
      $lin = docker logs --tail 10 $_ 2>$null
      if ($lin) { $lin | ForEach-Object { Write-Host "  $_" } }
      $logTxt += "=== $_ ==="
      $logTxt += $lin
    }
  }

  if ($tentUp -ge 3) {
    $logFile = Join-Path ([Environment]::GetFolderPath('Desktop')) "erro-atendia.txt"
    $logTxt | Out-File -FilePath $logFile -Encoding UTF8
    Write-Host ""
    Write-Host "  [3/5] Falhou mesmo apos 2 limpezas e reinstalacoes - nao e sujeira, e uma causa que preciso ver." -ForegroundColor Red
    Write-Host "  Salvei o motivo completo na AREA DE TRABALHO: erro-atendia.txt" -ForegroundColor Yellow
    Dump-Erro "containers-falharam-apos-limpeza"
    Write-Host "  O que fazer: mande este arquivo (ou a secao amarela acima) para o suporte - eles resolvem com isso." -ForegroundColor Yellow
    Read-Host "  Aperte ENTER para fechar"
    exit 1
  }

  if ($tentUp -eq 1) {
    Write-Host ""
    $resp = Read-Host "  Vou limpar e reinstalar tudo agora (so a IA fica salva). ENTER = eu faco / X = sair"
    if ($resp -eq "X" -or $resp -eq "x") {
      Write-Host "  Saindo sem alterar nada. Rode este comando de novo quando quiser." -ForegroundColor Yellow
      exit 1
    }
  }
  Write-Host ""
  Write-Host "  [3/5] Limpando tudo menos a IA: containers, volumes de dados, imagens, cache de build..." -ForegroundColor Yellow
  Limpar-Instalacao $false
  docker volume create atendia-tunnel_ollama_data | Out-Null
  if ($tentUp -eq 2) {
    Write-Host "  [3/5] Ultima tentativa: baixando as imagens de novo do zero..." -ForegroundColor Yellow
    docker compose -f docker-compose.evolution.yml pull 2>$null
  }
  Write-Host "  [3/5] Limpo! (a IA ficou salva). Subindo tudo de novo (tentativa $($tentUp + 1)/3)..." -ForegroundColor Green
}
Write-Host "  [3/5] OK! Containers no ar:" -ForegroundColor Green
docker compose -f docker-compose.evolution.yml ps --format "   {{.Name}}  [{{.State}}]" 2>$null

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

$ollamaContainer = docker ps -a --filter "label=com.docker.compose.project=$FolderName" --format "{{.Names}}" 2>$null | Where-Object { $_ -match "ollama" } | Select-Object -First 1
if (-not $ollamaContainer) { $ollamaContainer = docker ps -a --filter "name=ollama" --format "{{.Names}}" 2>$null | Select-Object -First 1 }
if ($ollamaContainer) {
  # Espera o container estar de fato running (ate 30 s) - o pull falha se ele ainda esta subindo
  $ollamaRun = $false
  foreach ($t in @(1, 2, 3, 4, 5, 6)) {
    $st = docker inspect --format "{{.State.Status}}" $ollamaContainer 2>$null
    if ($st -eq "running") { $ollamaRun = $true; break }
    Start-Sleep -Seconds 5
  }
  if (-not $ollamaRun) {
    Write-Host ""
    Write-Host "  [4/5] Container Ollama nao ficou rodando - pulando o download da IA (opcional)." -ForegroundColor Yellow
  } else {
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
  }
} else {
  Write-Host "  [4/5] Container Ollama nao encontrado - pulando o download da IA (opcional)." -ForegroundColor Yellow
}

# ---------- PASSO 5/5: tunel + sincronizacao ----------
Write-Host ""
Write-Host "  [5/5] Criando o tunel Cloudflare (endereco publico do seu WhatsApp)..." -ForegroundColor Cyan
Write-Host "  [5/5] Isso leva ate 2 minutos. Pontinhos = ainda trabalhando..." -ForegroundColor Gray
$tunnelUrl = $null
for ($i = 0; $i -lt 36; $i++) {
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
  Write-Host "  [5/5] O tunel nao subiu (esperei 3 minutos)." -ForegroundColor Red
  $tunContainer = docker ps -a --filter "label=com.docker.compose.project=$FolderName" --format "{{.Names}}" 2>$null | Where-Object { $_ -match "tunnel" } | Select-Object -First 1
  if ($tunContainer) {
    Write-Host ""
    Write-Host "  === Ultimas linhas do tunel ($tunContainer) ===" -ForegroundColor Yellow
    docker logs --tail 25 $tunContainer 2>$null | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
  }
  Write-Host "  O que fazer: veja o motivo com:  docker logs $($tunContainer)" -ForegroundColor Gray
  Write-Host "  Depois rode este comando de novo - ele limpa e sobe tudo de novo (nao perde a sessao)." -ForegroundColor Yellow
  Write-Host "  Persistiu? Rode: powershell -ExecutionPolicy Bypass -File setup.ps1 -Docker -Reset (mantem so a IA)" -ForegroundColor Yellow
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
Write-Host "  - NAO clique em 'Quit Docker Desktop' no icone da bandeja - isso PARA o atendimento" -ForegroundColor Yellow
Write-Host "    (fechar ou minimizar a janela pode: ele continua rodando escondido)" -ForegroundColor Gray
if (-not $NoReload) {
  Write-Host "  - Relay em background (Job $($job.Id))" -ForegroundColor Gray
}
Write-Host "  - Se o PC reiniciar: tudo volta SOZINHO - o Docker abre com o Windows (deixe a opcao" -ForegroundColor Gray
Write-Host "    'Start Docker Desktop when you sign in' LIGADA) e a URL nova sincroniza automatica." -ForegroundColor Gray
Write-Host "  - So rode este comando de novo se algo der errado de verdade." -ForegroundColor Gray
Write-Host "  - Para producao estavel com PC desligado: use a VM Oracle gratis (P7Store > Configuracoes > WhatsApp > modo 1)" -ForegroundColor Gray
Write-Host "  - Para limpar e reinstalar tudo (erro persistente - mantem so a IA): setup.ps1 -Docker -Reset" -ForegroundColor Gray
Write-Host "  - Para comecar do zero (apaga tudo): setup.ps1 -Docker -Clean" -ForegroundColor Gray
Write-Host "  - Para apagar TUDO do Docker (containers, volumes, imagens, resto de build):" -ForegroundColor Gray
Write-Host "    setup.ps1 -Limpar   (mostra inventario e pede confirmacao antes)" -ForegroundColor Gray
Write-Host ""
Write-Host "  O QUE ESTA RODANDO AGORA (transparencia total):" -ForegroundColor Cyan
Write-Host "   - postgres ....... banco de dados do sistema (conversas, config)" -ForegroundColor Gray
Write-Host "   - redis .......... fila rapida interna da Evolution" -ForegroundColor Gray
Write-Host "   - evolution ...... ponte do WhatsApp (gera o QR, envia e recebe mensagens)" -ForegroundColor Gray
Write-Host "   - ollama ......... IA local (responde os clientes)" -ForegroundColor Gray
Write-Host "   - tunnel-info .... tunel publico + auto-sync da URL + painel na porta 9876" -ForegroundColor Gray
Write-Host "   Nomes aleatorios tipo 'beautiful_mestorf' (parados) = temporarios de BUILD do Docker:" -ForegroundColor Gray
Write-Host "   nao sao virus nem programas - sao 'cozinhas' descartaveis usadas pra montar as imagens." -ForegroundColor Gray
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
