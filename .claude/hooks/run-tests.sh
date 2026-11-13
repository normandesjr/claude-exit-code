#!/usr/bin/env bash
# Stop hook: roda `go test` quando o Claude tenta encerrar o turno.
# O exit code em caso de falha vem da env HOOK_FAIL_EXIT (1 ou 2).
# Sem a env -> hook desligado (exit 0).
#
# Debug: tudo vai para .claude/hooks/hook.log.
# Acompanhe em outro terminal com:  tail -f .claude/hooks/hook.log

# [1] Arquivo de log. CLAUDE_PROJECT_DIR é injetada pelo Claude Code (raiz do projeto).
LOG="$CLAUDE_PROJECT_DIR/.claude/hooks/hook.log"
log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

log "================ Stop hook disparado ================"
log "CLAUDE_PROJECT_DIR = $CLAUDE_PROJECT_DIR"
log "HOOK_FAIL_EXIT     = '${HOOK_FAIL_EXIT}'"
log "PWD inicial        = $PWD"

# [2] O Claude Code manda um JSON com dados do evento via stdin.
INPUT=$(cat)
log "INPUT (stdin):"
echo "$INPUT" | jq . >> "$LOG" 2>/dev/null || echo "$INPUT" >> "$LOG"

# [3] stop_hook_active = true quando o Claude já está continuando por causa de um Stop hook
#     (ou seja, é a 2ª+ tentativa de encerrar no mesmo turno).
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active')
log "stop_hook_active   = $ACTIVE"

# [4] Kill switch: sem a env, não faz nada.
if [ -z "$HOOK_FAIL_EXIT" ]; then
  log "HOOK_FAIL_EXIT vazio -> hook desligado -> exit 0"
  exit 0
fi

# [5] Roda os testes na raiz do projeto, capturando stdout+stderr em OUT e o código em RC.
cd "$CLAUDE_PROJECT_DIR" || { log "cd falhou -> exit 0"; exit 0; }
OUT=$(go test ./... 2>&1)
RC=$?
log "go test rc         = $RC"
log "go test output:"
echo "$OUT" | sed 's/^/    | /' >> "$LOG"

# [6] Decide o exit code do hook.
if [ $RC -ne 0 ]; then
  # stderr: com exit 2 vira feedback para o Claude; com exit 1 só aparece para o usuário.
  log "testes FALHARAM -> escrevendo no stderr -> exit $HOOK_FAIL_EXIT"
  echo "Testes falharam. Corrija o código antes de encerrar:" >&2
  echo "$OUT" >&2
  exit "$HOOK_FAIL_EXIT"
fi

log "testes PASSARAM -> exit 0 (Claude pode encerrar)"
exit 0
