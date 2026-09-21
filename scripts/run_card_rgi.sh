#!/bin/bash
set -euo pipefail

# Ensure per-project config.sh exists
CONFIG_FILE="${1:-${CONFIG:-./config.sh}}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config.sh not found at: $CONFIG_FILE" >&2
  echo "Usage: $0 /path/to/project/config.sh" >&2
  exit 1
fi

source "$CONFIG_FILE"

# Ensure per-project log directory exists
LOG_DIR="${LOG_DIR:-$BASE/logs}"
mkdir -p "$LOG_DIR"


# --- Paths from config.sh ---
USABLE_DIR="$USABLE_MAG_DIR"
CARD_RGI_DIR="$CARD_RGI_DIR"
LOG="$LOG_DIR/card_rgi_log.txt"
ENV_NAME="${RGI_ENV_NAME:-rgi_env}"

mkdir -p "$CARD_RGI_DIR"
: > "$LOG"

# --- Determine whether to use shared or named micromamba env ---
SHARED_ENV_PATH="$TOOLS_ROOT/envs/$ENV_NAME"

if [[ -d "$SHARED_ENV_PATH" ]]; then
  echo "Using shared CARD env at: $SHARED_ENV_PATH" | tee -a "$LOG"
  MAMBA_RUN=(micromamba run -p "$SHARED_ENV_PATH")
else
  echo "Using per-user CARD env: $ENV_NAME" | tee -a "$LOG"
  MAMBA_RUN=(micromamba run -n "$ENV_NAME")
fi

echo "=== CARD/RGI starting ===" | tee -a "$LOG"
echo "Config:       $CONFIG_FILE" | tee -a "$LOG"
echo "MAG dir:     $USABLE_DIR" | tee -a "$LOG"
echo "CARD dir: $CARD_RGI_DIR" | tee -a "$LOG"
echo "Log file:     $LOG" | tee -a "$LOG"
echo "Env:     $ENV_NAME"     | tee -a "$LOG"
echo "===============================" | tee -a "$LOG"

# === Loop over MAG FASTA files ===
for MAG in "$USABLE_DIR"/*.fa "$USABLE_DIR"/*.fasta; do
  [ -e "$MAG" ] || continue
  BASENAME=$(basename "$MAG")
  SAMPLE="${BASENAME%.*}"
  OUT_PREFIX="$CARD_RGI_DIR/${SAMPLE}_rgi"

  echo "Running RGI on $BASENAME..." | tee -a "$LOG"

  "${MAMBA_RUN[@]}" rgi main \
      --input_sequence "$MAG" \
      --output_file "$OUT_PREFIX" \
      --input_type contig \
      --clean \
      --include_loose \
      --num_threads 4 \
      --alignment_tool DIAMOND \
      >> "$LOG" 2>&1

if [[ -s "${OUT_PREFIX}.txt" ]]; then
    echo "Finished $BASENAME" | tee -a "$LOG"
else
    echo "RGI may have failed for $BASENAME (no table output found)" | tee -a "$LOG"
fi
done

echo "All done. Results in: $CARD_RGI_DIR" | tee -a "$LOG"