#!/usr/bin/env bash
# Stop hook ROBUSTO: roda `go test` e bloqueia o encerramento (exit 2) se falhar,
# mas no máximo HOOK_MAX_RETRIES vezes por turno. Isso evita loop infinito.
#
# Como funciona:
#   - stop_hook_active=false -> começo de um turno novo -> zera o contador
#   - testes passaram        -> zera o contador, exit 0
#   - testes falharam:
#       tentativas < MAX     -> contador++, exit 2 (o Claude volta para corrigir)
#       tentativas >= MAX    -> desiste, exit 1 (avisa você, o Claude encerra)
#
# Env:
#   HOOK_FAIL_EXIT    liga o hook (qualquer valor). Vazia -> desligado.
#   HOOK_MAX_RETRIES  máximo de bloqueios por turno (padrão 3).
#
# Debug: tail -f .claude/hooks/hook.log

HOOKS_DIR="$CLAUDE_PROJECT_DIR/.claude/hooks"
LOG="$HOOKS_DIR/hook.log"
STATE_DIR="$HOOKS_DIR/state"
MAX="${HOOK_MAX_RETRIES:-3}"
log() { echo "[$(date '+%H:%M:%S')] [robust] $*" >> "$LOG"; }

log "================ Stop hook disparado ================"

# [1] Kill switch.
if [ -z "$HOOK_FAIL_EXIT" ]; then
  log "HOOK_FAIL_EXIT vazio -> desligado -> exit 0"
  exit 0
fi

# [2] Dependências. Se faltar algo, NÃO bloqueia (exit 1 = só avisa).
for dep in jq go; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    log "dependência '$dep' ausente -> exit 1"
    echo "Stop hook: '$dep' não encontrado, pulando testes." >&2
    exit 1
  fi
done

# [3] Lê o JSON do evento.
INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "sem-sessao"')
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
log "session_id=$SESSION stop_hook_active=$ACTIVE max=$MAX"

# [4] Contador por sessão (sessões paralelas não se misturam).
mkdir -p "$STATE_DIR"
COUNTER_FILE="$STATE_DIR/$SESSION.count"

if [ "$ACTIVE" != "true" ]; then
  # Primeira tentativa de encerrar neste turno -> zera.
  echo 0 > "$COUNTER_FILE"
  log "turno novo -> contador zerado"
fi
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
log "contador atual = $COUNT"

# [5] Roda os testes.
cd "$CLAUDE_PROJECT_DIR" || { log "cd falhou -> exit 1"; exit 1; }
OUT=$(go test ./... 2>&1)
RC=$?
log "go test rc = $RC"
echo "$OUT" | sed 's/^/    | /' >> "$LOG"

# [6] Passou -> libera.
if [ $RC -eq 0 ]; then
  rm -f "$COUNTER_FILE"
  log "testes PASSARAM -> exit 0"
  exit 0
fi

# [7] Falhou e já estourou o limite -> desiste sem bloquear.
if [ "$COUNT" -ge "$MAX" ]; then
  rm -f "$COUNTER_FILE"
  log "falhou, limite $MAX atingido -> desistindo -> exit 1"
  echo "Stop hook: testes ainda falhando após $MAX tentativas. Liberando o encerramento; revise manualmente." >&2
  exit 1
fi

# [8] Falhou e ainda tem tentativas -> bloqueia e manda o erro para o Claude.
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
log "falhou -> tentativa $COUNT/$MAX -> exit 2"
{
  echo "Testes falharam (tentativa $COUNT de $MAX). Corrija o código antes de encerrar."
  echo "Se não for possível corrigir, explique o motivo ao usuário."
  echo
  echo "$OUT"
} >&2
exit 2
