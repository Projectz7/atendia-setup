# ============================================================
# relay-whatsapp.ps1 — Bridge para Docker Local (Opcional)
# ============================================================
# SO e necessario se voce usa:
#   - Evolution API via Docker Local + tunnel Cloudflare
#   - IA Ollama local (a edge function nao consegue chamar localhost)
#
# NAO e necessario se voce usa:
#   - Evolution API no Railway (URL fixa HTTPS)
#   - IA cloud (DeepSeek, OpenAI, Gemini) — a edge function faz tudo
#
# O relay faz 2 coisas:
#   1. Envia mensagens da fila de saida via Evolution API local
#   2. Gera respostas IA via Ollama local (se a IA for Ollama)
# ============================================================

param(
  [string]$SupabaseUrl = "https://pnijzmqygibhwbcnkklm.supabase.co",
  [string]$RelaySecret = "relay-atendia-sk-7f3d",
  [int]$PollInterval = 5
)

$pendingUrl = "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/pending"
$markSentUrl = "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/mark-sent"
$updateTunnelUrl = "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-tunnel"
$pendingAiUrl = "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/pending-ai"
$submitResponseUrl = "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/submit-response"
$authHeader = @{ Authorization = "Bearer $RelaySecret" }

$OllamaEndpoint = "http://localhost:9876/ollama"
# Defaults — usados apenas se o webhook NAO incluir config no payload
$DefaultAiModel = "qwen3.5:4b"
$DefaultSystemPrompt = "Voce e um atendente virtual de uma vidracaria. Responda de forma educada e profissional, em portugues. Seja breve e direto."
$MaxRetries = 2

try {
  $info = Invoke-WebRequest -Uri "http://localhost:9876/info" -UseBasicParsing -TimeoutSec 3
  $data = $info.Content | ConvertFrom-Json
  if ($data.status -eq "active" -and $data.tunnel_url) {
    Write-Host "[Relay] Tunnel detectado: $($data.tunnel_url)" -ForegroundColor Cyan
    $updateBody = @{ tunnel_url = $data.tunnel_url } | ConvertTo-Json -Depth 3
    Invoke-WebRequest -Uri $updateTunnelUrl -Method POST -Headers $authHeader -Body $updateBody -TimeoutSec 10 | Out-Null
    Write-Host "[Relay] Integracao Ollama atualizada com tunnel URL" -ForegroundColor Green

    $evoUpdateUrl = "$SupabaseUrl/functions/v1/webhook-whatsapp/relay/update-evolution"
    $evoBody = @{ server_url = "$($data.tunnel_url)/evolution" } | ConvertTo-Json -Depth 3
    try {
      Invoke-WebRequest -Uri $evoUpdateUrl -Method POST -Headers $authHeader -Body $evoBody -TimeoutSec 10 | Out-Null
      Write-Host "[Relay] Evolution Config atualizada com tunnel URL" -ForegroundColor Green
    } catch {
      Write-Host "[Relay] [!] Falha ao atualizar Evolution Config: $_" -ForegroundColor Red
    }
  } else {
    Write-Host "[Relay] Tunnel sem URL ativa - usando Ollama local diretamente" -ForegroundColor Yellow
  }
} catch {
  Write-Host "[Relay] Tunnel nao disponivel - usando Ollama local diretamente" -ForegroundColor Yellow
}

# ============================================================
# Invoke-Ollama — chama Ollama com retry, encoding UTF-8
# ============================================================
function Invoke-Ollama {
  param(
    [string]$Endpoint,
    [string]$Model,
    [string]$System,
    [array]$Messages,
    [int]$Attempt = 1
  )
  $timeout = if ($Attempt -eq 1) { 60 } else { 120 }
  $bodyObj = @{
    model = $Model
    stream = $false
    messages = @(@{ role = "system"; content = $System }) + $Messages
  }
  $bodyJson = $bodyObj | ConvertTo-Json -Depth 5
  $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

  try {
    $res = Invoke-WebRequest -Uri "$Endpoint/api/chat" -Method POST `
      -ContentType "application/json; charset=utf-8" `
      -Body $bodyBytes -UseBasicParsing -TimeoutSec $timeout
    if ($res.StatusCode -eq 200) {
      $data = $res.Content | ConvertFrom-Json
      if ($data.message.content) {
        return @{ ok = $true; content = $data.message.content }
      }
      return @{ ok = $false; error = "resposta vazia do Ollama" }
    }
    return @{ ok = $false; error = "HTTP $($res.StatusCode)" }
  } catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "timed out|timeout") {
      return @{ ok = $false; error = "timeout ${timeout}s" }
    }
    if ($errMsg -match "refused|connect") {
      return @{ ok = $false; error = "conexao recusada" }
    }
    return @{ ok = $false; error = $errMsg }
  }
}

Write-Host "[Relay WhatsApp] Iniciado - polling a cada ${PollInterval}s"

while ($true) {
  try {
    $resp = Invoke-WebRequest -Uri $pendingUrl -Method GET -Headers $authHeader -TimeoutSec 10
    $pending = $resp.Content | ConvertFrom-Json

    if ($pending.Count -gt 0) {
      $ts = Get-Date -Format "HH:mm:ss"
      Write-Host "[Relay] $ts - $($pending.Count) mensagens pendentes"

      $sentIds = @()
      foreach ($msg in $pending) {
        $evo = $msg.evolution
        if (-not $evo -or -not $evo.server_url -or -not $evo.instance_name) {
          Write-Host "[Relay]  ! msg $($msg.id): sem config evolution"
          $sentIds += $msg.id
          continue
        }

        $localEvo = "http://localhost:8080"
        $sendUrl = "$localEvo/message/sendText/$($evo.instance_name)"
        $evoAuth = @{ "Content-Type" = "application/json; charset=utf-8"; apiKey = $evo.api_key }
        $body = @{
          number  = $msg.whatsapp_numero
          text    = $msg.conteudo
          options = @{ delay = 1200 }
        } | ConvertTo-Json -Depth 3
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

        try {
          $sendResp = Invoke-WebRequest -Uri $sendUrl -Method POST -Headers $evoAuth -Body $bodyBytes -TimeoutSec 15
          $ok = $sendResp.StatusCode -eq 200 -or $sendResp.StatusCode -eq 201
          if ($ok) {
            Write-Host "[Relay] [+] msg $($msg.id) enviada para $($msg.whatsapp_numero)"
          } else {
            Write-Host "[Relay] [X] msg $($msg.id) erro $($sendResp.StatusCode)"
          }
        } catch {
          Write-Host "[Relay] [X] msg $($msg.id) falha: $_"
        }
        $sentIds += $msg.id
      }

      if ($sentIds.Count -gt 0) {
        $markBody = @{ ids = @($sentIds) } | ConvertTo-Json -Depth 3
        Invoke-WebRequest -Uri $markSentUrl -Method POST -Headers $authHeader -Body $markBody -TimeoutSec 10 | Out-Null
        Write-Host "[Relay] [v] $($sentIds.Count) mensagens marcadas como enviadas"
      }
    }

    # ============================================================
    # Processamento IA — 1 conversa por vez, 2 retries
    # ============================================================
    try {
      $aiResp = Invoke-WebRequest -Uri $pendingAiUrl -Method GET -Headers $authHeader -TimeoutSec 10
      $pendingAi = $aiResp.Content | ConvertFrom-Json
      foreach ($item in $pendingAi) {
        $nome = if ($item.cliente_nome) { $item.cliente_nome } else { $item.whatsapp_numero }
        $msgPreview = if ($item.mensagem) { $item.mensagem.Substring(0, [Math]::Min(60, $item.mensagem.Length)) } else { "?" }
        Write-Host "[Relay] [AI] Processando: $nome - $msgPreview" -ForegroundColor Magenta

        $itemEndpoint = $OllamaEndpoint
        $itemModel = if ($item.modelo) { $item.modelo } else { $DefaultAiModel }
        $itemSystem = if ($item.system_prompt) { $item.system_prompt } else { $DefaultSystemPrompt }

        # Limitar historico a ultimas 5 mensagens — prioriza mensagem atual
        $histLimited = if ($item.historico.Count -gt 5) { $item.historico[-5..-1] } else { $item.historico }

        $resposta = $null
        $lastError = ""
        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
          $result = Invoke-Ollama -Endpoint $itemEndpoint -Model $itemModel -System $itemSystem -Messages $histLimited -Attempt $attempt
          if ($result.ok) {
            $resposta = $result.content
            break
          }
          $lastError = $result.error
          Write-Host "[Relay] [AI] Tentativa $attempt/$MaxRetries falhou ($lastError) - $nome" -ForegroundColor Yellow
          if ($attempt -lt $MaxRetries) {
            Start-Sleep -Seconds 3
          }
        }

        if ($resposta) {
          $submitBody = @{
            conversa_id = $item.conversa_id
            empresa_id = $item.empresa_id
            resposta = $resposta
            whatsapp_numero = $item.whatsapp_numero
            trace_id = $item.trace_id
          } | ConvertTo-Json -Depth 3
          $submitBytes = [System.Text.Encoding]::UTF8.GetBytes($submitBody)
          Invoke-WebRequest -Uri $submitResponseUrl -Method POST -Headers $authHeader -Body $submitBytes -TimeoutSec 10 | Out-Null
          $preview = $resposta.Substring(0, [Math]::Min(80, $resposta.Length))
          Write-Host "[Relay] [AI] Resposta salva (trace=$($item.trace_id)): $preview" -ForegroundColor Green

          $transferir = $false
          $palavrasTransferencia = @("atendente humano", "transferir para", "vamos transferir", "Samuel", "encaminhar para", "dar continuidade")
          foreach ($p in $palavrasTransferencia) {
            if ($resposta -like "*$p*") { $transferir = $true; break }
          }
          if ($transferir) {
            $updateBody = @{ status = "humano" } | ConvertTo-Json -Depth 3
            $updateBytes = [System.Text.Encoding]::UTF8.GetBytes($updateBody)
            try {
              $updateUrl = "$SupabaseUrl/rest/v1/conversas?id=eq.$($item.conversa_id)"
              $updateHeaders = @{ "Content-Type" = "application/json"; "Authorization" = "Bearer $RelaySecret"; "apikey" = "$RelaySecret" }
              Invoke-WebRequest -Uri $updateUrl -Method PATCH -Headers $updateHeaders -Body $updateBytes -TimeoutSec 10 | Out-Null
              Write-Host "[Relay] [AI] Conversa transferida para HUMANO (intensao de compra detectada)" -ForegroundColor Yellow
            } catch {
              Write-Host "[Relay] [AI] Aviso: nao foi possivel mudar status para humano: $_" -ForegroundColor Yellow
            }
          }
        } else {
          Write-Host "[Relay] [AI] FALHA FINAL apos $MaxRetries tentativas para $nome ($lastError)" -ForegroundColor Red
          Write-Host "[Relay] [AI] Conversa $($item.conversa_id) sera processada manualmente" -ForegroundColor Red
        }
      }
    } catch {
      Write-Host "[Relay] [!] erro AI: $_" -ForegroundColor Red
    }
  } catch {
    Write-Host "[Relay] [!] erro polling: $_"
  }

  Start-Sleep -Seconds $PollInterval
}
