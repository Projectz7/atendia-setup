# TODO — setup.ps1 à prova de cenário (micro-tarefas)

- [x] M1. setup.ps1: TLS 1.2 no topo + base fixa %USERPROFILE%\atendia-tunnel (anti-system32) + detecção `docker compose` ausente
- [x] M2. setup.ps1: engine wait com $LASTEXITCODE + padrões ampliados + OSType Linux + dicas direcionadas (wsl --update)
- [x] M3. setup.ps1: função `Varrer-Lixo` (cozinhas moby/buildkit paradas + dangling) — usada no fluxo default e entre tentativas
- [x] M4. setup.ps1: função `Limpar-Instalacao($Tudo)` unificada (down + containers + volumes menos ollama + imagens da stack + cache + conferência)
- [x] M5. setup.ps1: -Limpar/-Reset/-Clean reescritos sobre as funções novas (mesma UX/promessa)
- [x] M6. setup.ps1: conflito de portas 8080/9876 via parse {{.Ports}} + aviso de processo nativo
- [x] M7. setup.ps1: pull 3x com varredura entre tentativas + rm de imagens da stack na última
- [x] M8. setup.ps1: up até 3 tentativas com Limpar-Instalacao no meio; sucesso = 0 exited + total==running (2 checks); log inline
- [x] M9. setup.ps1: túnel 3 min + log do tunnel-info na falha; Ollama por label do projeto + espera running + pull
- [x] M10. setup.ps1: Dump-Erro rico (wsl, compose version, system df, portas, compose logs)
- [x] M11. README.md: -Reset/default varrem lixo; mantém IA em -Reset/-Clean definido
- [x] M12. project-store WhatsAppConfig.tsx: dica -Limpar na seção "Resolver problemas"
- [x] M13. Validação: PSParser sem erro + revisão de diff
- [ ] M14. Commit + push origin/main
