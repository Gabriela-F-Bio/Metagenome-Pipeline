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
RAW_DIR="$RAW_DIR"           # from config.sh
OUT_DIR="$TRIMMED_DIR"       # from config.sh
LOG_FILE="$LOG_DIR/trim_log.txt"

mkdir -p "$OUT_DIR"

echo "=== BBDuk trimming starting ==="
echo "Config file:  $CONFIG_FILE"
echo "Raw dir:      $RAW_DIR"
echo "Trimmed dir:  $OUT_DIR"
echo "Log file:     $LOG_FILE"
echo "==============================="

# sanity checks
if [[ ! -d "$RAW_DIR" ]]; then
  echo "ERROR: RAW_DIR does not exist: $RAW_DIR" >&2
  exit 1
fi

shopt -s nullglob
READS=("$RAW_DIR"/*_R1.fastq.gz)
shopt -u nullglob

if [[ ${#READS[@]} -eq 0 ]]; then
  echo "ERROR: No *_R1.fastq.gz files found in $RAW_DIR" >&2
  exit 1
fi

# Clear or create log
: > "$LOG_FILE"

for R1 in "${READS[@]}"; do
  R2="${R1/_R1.fastq.gz/_R2.fastq.gz}"
  BASENAME=$(basename "$R1" _R1.fastq.gz)
  OUT1="$OUT_DIR/clean_${BASENAME}_R1.fastq.gz"
  OUT2="$OUT_DIR/clean_${BASENAME}_R2.fastq.gz"

  echo "Processing $BASENAME..." | tee -a "$LOG_FILE"
  if [[ ! -f "$R2" ]]; then
    echo "  WARNING: Missing mate file for $R1 (expected $R2). Skipping." | tee -a "$LOG_FILE"
    continue
  fi

  bbduk.sh in1="$R1" in2="$R2" out1="$OUT1" out2="$OUT2" \
    ref=adapters,phix ktrim=r k=23 mink=11 hdist=1 \
    tpe tbo qtrim=rl trimq=10 minlen=50 \
    >> "$LOG_FILE" 2>&1

  echo "Finished $BASENAME" | tee -a "$LOG_FILE"
done

echo "=== BBDuk trimming finished ==="