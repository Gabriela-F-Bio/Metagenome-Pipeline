#!/bin/bash
set -euo pipefail

# Ensure per-project config.sh exists
CONFIG_FILE="${1:-${CONFIG:-./config.sh}}"
FORCE="${2:-}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config.sh not found at: $CONFIG_FILE" >&2
  echo "Usage: $0 /path/to/project/config.sh [--force]" >&2
  exit 1
fi

if [[ -n "$FORCE" && "$FORCE" != "--force" ]]; then
  echo "ERROR: Unknown option: $FORCE" >&2
  echo "Usage: $0 /path/to/project/config.sh [--force]" >&2
  exit 1
fi

source "$CONFIG_FILE"

# Ensure per-project log directory exists
LOG_DIR="${LOG_DIR:-$BASE/logs}"
mkdir -p "$LOG_DIR"

# --- Paths from config.sh ---
TRIMMED_DIR="$TRIMMED_DIR"
ASSEMBLY_DIR="$MEGAHIT_DIR"
LOG_FILE="$LOG_DIR/megahit_log.txt"

mkdir -p "$ASSEMBLY_DIR"
: > "$LOG_FILE"

echo "=== MEGAHIT assembly starting ===" | tee -a "$LOG_FILE"
echo "Config:       $CONFIG_FILE" | tee -a "$LOG_FILE"
echo "Trimmed dir:  $TRIMMED_DIR" | tee -a "$LOG_FILE"
echo "Assembly dir: $ASSEMBLY_DIR" | tee -a "$LOG_FILE"
echo "Log file:     $LOG_FILE" | tee -a "$LOG_FILE"
echo "Force mode:   $([[ "$FORCE" == "--force" ]] && echo YES || echo NO)" | tee -a "$LOG_FILE"
echo "===============================" | tee -a "$LOG_FILE"

if [[ ! -d "$TRIMMED_DIR" ]]; then
  echo "ERROR: TRIMMED_DIR does not exist: $TRIMMED_DIR" >&2
  exit 1
fi

shopt -s nullglob
R1_FILES=("$TRIMMED_DIR"/clean_*_R1.fastq.gz)
shopt -u nullglob

if [[ ${#R1_FILES[@]} -eq 0 ]]; then
  echo "ERROR: No clean_*_R1.fastq.gz files in $TRIMMED_DIR" >&2
  exit 1
fi

for R1 in "${R1_FILES[@]}"; do
  R2="${R1/_R1.fastq.gz/_R2.fastq.gz}"
  BASENAME=$(basename "$R1" _R1.fastq.gz)
  SAMPLE_ID="${BASENAME#clean_}"
  OUTDIR="$ASSEMBLY_DIR/$SAMPLE_ID"
  FINAL_CONTIGS="$OUTDIR/final.contigs.fa"

  if [[ ! -f "$R2" ]]; then
    echo " Skipping $SAMPLE_ID – missing R2 file ($R2)" | tee -a "$LOG_FILE"
    continue
  fi
  
  # If output dir exists but final contigs are missing/empty, it's a partial run — clean it.
  if [[ -d "$OUTDIR" && ! -s "$FINAL_CONTIGS" ]]; then
    echo "Found partial output for $SAMPLE_ID (no final.contigs.fa). Removing $OUTDIR and restarting..." | tee -a "$LOG_FILE"
    rm -rf "$OUTDIR"
  fi

  # Skip logic (default behavior)
  if [[ "$FORCE" != "--force" && -s "$FINAL_CONTIGS" ]]; then
    echo "Skipping $SAMPLE_ID – already assembled ($FINAL_CONTIGS exists)" | tee -a "$LOG_FILE"
    continue
  fi
  
    # Force mode: clean output dir
  if [[ "$FORCE" == "--force" ]]; then
    echo "FORCE: removing existing output dir for $SAMPLE_ID ($OUTDIR)" | tee -a "$LOG_FILE"
    rm -rf "$OUTDIR"
  fi
  
  echo "Running MEGAHIT on $SAMPLE_ID..." | tee -a "$LOG_FILE"

    if megahit \
    -1 "$R1" -2 "$R2" \
    -o "$OUTDIR" \
    -t 2 \
    --memory 0.5 \
    --min-contig-len 1000 --presets meta-sensitive \
    >> "$LOG_FILE" 2>&1
  then
    if [[ -s "$FINAL_CONTIGS" ]]; then
      echo "MEGAHIT succeeded for $SAMPLE_ID" | tee -a "$LOG_FILE"
    else
      echo "MEGAHIT finished but no final.contigs.fa was produced for $SAMPLE_ID" | tee -a "$LOG_FILE"
    fi
  else
    echo "MEGAHIT failed for $SAMPLE_ID; continuing to next sample" | tee -a "$LOG_FILE"
    continue
  fi

  echo "Finished $SAMPLE_ID" | tee -a "$LOG_FILE"
done

echo "=== MEGAHIT assembly finished ==="