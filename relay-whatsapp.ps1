# ============================================================
# relay-whatsapp.ps1 — Bridge para Docker Local (Opcional)
# ============================================================
# SÓ e necessario se voce usa:
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
# Defaults — usados apenas se o webhook NÃO incluir config no payload
$DefaultAiModel = "gemma3:4b"
$DefaultSystemPrompt = "Voce e um atendente virtual de uma vidracaria. Responda de forma educada e profissional, em portugues. Seja breve e direto."

try {
  $info = Invoke-WebRequest -Uri "http://localhost:9876/info" -UseBasicParsing -TimeoutSec 3
  $data = $info.Content | ConvertFrom-Json
  if ($data.status -eq "active" -and $data.tunnel_url) {
    Write-Host "[Relay] Tunnel detectado: $($data.tunnel_url)" -ForegroundColor Cyan
    $updateBody = @{ tunnel_url = $data.tunnel_url } | ConvertTo-Json -Depth 3
    Invoke-WebRequest -Uri $updateTunnelUrl -Method POST -Headers $authHeader -Body $updateBody -TimeoutSec 10 | Out-Null
    Write-Host "[Relay] Integracao Ollama atualizada com tunnel URL" -ForegroundColor Green

    # Atualiza evolution_config.server_url
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

function Invoke-Ollama {
  param([string]$Endpoint, [string]$Model, [string]$System, [array]$Messages)
  $body = @{
    model = $Model
    stream = $false
    think = $false
    messages = @(@{ role = "system"; content = $System }) + $Messages
    options = @{ num_predict = 200; temperature = 0.7 }
  } | ConvertTo-Json -Depth 5
  try {
    $res = Invoke-WebRequest -Uri "$Endpoint/api/chat" -Method POST `
      -ContentType "application/json" -Body $body -UseBasicParsing -TimeoutSec 240
    if ($res.StatusCode -eq 200) {
      $data = $res.Content | ConvertFrom-Json
      return $data.message.content
    }
  } catch {
    Write-Host "[Relay] [!] Ollama erro: $_" -ForegroundColor Red
  }
  return $null
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
        $evoAuth = @{ "Content-Type" = "application/json"; apiKey = $evo.api_key }
        $body = @{
          number  = $msg.whatsapp_numero
          text    = $msg.conteudo
          options = @{ delay = 1200 }
        } | ConvertTo-Json -Depth 3

        try {
          $sendResp = Invoke-WebRequest -Uri $sendUrl -Method POST -Headers $evoAuth -Body $body -TimeoutSec 15
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

    try {
      $aiResp = Invoke-WebRequest -Uri $pendingAiUrl -Method GET -Headers $authHeader -TimeoutSec 10
      $pendingAi = $aiResp.Content | ConvertFrom-Json
      foreach ($item in $pendingAi) {
        Write-Host "[Relay] [AI] Processando: $($item.cliente_nome) - $($item.mensagem.Substring(0, [Math]::Min(60, $item.mensagem.Length)))" -ForegroundColor Magenta
        # Config por item — always use local Ollama endpoint (tunnel is unreliable from relay too)
        $itemEndpoint = $OllamaEndpoint
        $itemModel = if ($item.modelo) { $item.modelo } else { $DefaultAiModel }
        $itemSystem = if ($item.system_prompt) { $item.system_prompt } else { $DefaultSystemPrompt }
        $resposta = Invoke-Ollama -Endpoint $itemEndpoint -Model $itemModel -System $itemSystem -Messages $item.historico
        if ($resposta) {
          $submitBody = @{
            conversa_id = $item.conversa_id
            empresa_id = $item.empresa_id
            resposta = $resposta
            whatsapp_numero = $item.whatsapp_numero
            trace_id = $item.trace_id
          } | ConvertTo-Json -Depth 3
          Invoke-WebRequest -Uri $submitResponseUrl -Method POST -Headers $authHeader -Body $submitBody -TimeoutSec 10 | Out-Null
          Write-Host "[Relay] [AI] Resposta salva (trace=$($item.trace_id)): $($resposta.Substring(0, [Math]::Min(80, $resposta.Length)))" -ForegroundColor Green
        } else {
          Write-Host "[Relay] [AI] Falha ao gerar resposta para $($item.cliente_nome)" -ForegroundColor Red
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