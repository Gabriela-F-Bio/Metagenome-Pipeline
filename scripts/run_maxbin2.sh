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
MEGAHIT_DIR="$MEGAHIT_DIR"      # 3megahit
TRIMMED_DIR="$TRIMMED_DIR"      # 2trimmed
BINS_DIR="$MAXBIN_DIR"          # 4maxbin2
LOG_FILE="$LOG_DIR/maxbin2_log.txt"
ENV_NAME="${MAXBIN_ENV_NAME:-maxbin_env}"

# --- Determine whether to use shared or named micromamba env ---
SHARED_ENV_PATH="$TOOLS_ROOT/envs/$ENV_NAME"

if [[ -d "$SHARED_ENV_PATH" ]]; then
  echo "Using shared MaxBin2 env at: $SHARED_ENV_PATH" | tee -a "$LOG_FILE"
  MAMBA_RUN=(micromamba run -p "$SHARED_ENV_PATH")
else
  echo "Using per-user MaxBin2 env: $ENV_NAME" | tee -a "$LOG_FILE"
  MAMBA_RUN=(micromamba run -n "$ENV_NAME")
fi

# --- Setup ---
mkdir -p "$BINS_DIR"
: > "$LOG_FILE"

echo "=== MaxBin2 binning starting ===" | tee -a "$LOG_FILE"
echo "MEGAHIT_DIR:  $MEGAHIT_DIR"  | tee -a "$LOG_FILE"
echo "TRIMMED_DIR:  $TRIMMED_DIR"  | tee -a "$LOG_FILE"
echo "BINS_DIR:     $BINS_DIR"     | tee -a "$LOG_FILE"
echo "ENV_NAME:     $ENV_NAME"     | tee -a "$LOG_FILE"
echo "===============================" | tee -a "$LOG_FILE"

# --- Basic sanity checks ---
if [[ ! -d "$MEGAHIT_DIR" ]]; then
  echo "ERROR: MEGAHIT_DIR does not exist: $MEGAHIT_DIR" | tee -a "$LOG_FILE"
  exit 1
fi
if [[ ! -d "$TRIMMED_DIR" ]]; then
  echo "ERROR: TRIMMED_DIR does not exist: $TRIMMED_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

# --- Check Micromamba + MaxBin2 ---
if ! command -v micromamba &>/dev/null; then
  echo "ERROR: 'micromamba' not found in PATH. Check config.sh tool paths." | tee -a "$LOG_FILE"
  exit 1
fi

if ! "${MAMBA_RUN[@]}" run_MaxBin.pl -v &>/dev/null; then
  echo " MaxBin2 is not available in environment '$ENV_NAME'" | tee -a "$LOG_FILE"
  echo " Install it with:" | tee -a "$LOG_FILE"
  echo "   micromamba create -y -p $TOOLS_ROOT/envs/$ENV_NAME -c bioconda -c conda-forge maxbin2 perl" | tee -a "$LOG_FILE"
  exit 1
fi

# --- Loop through each MEGAHIT output ---
shopt -s nullglob
sample_dirs=("$MEGAHIT_DIR"/*)
shopt -u nullglob

if [[ ${#sample_dirs[@]} -eq 0 ]]; then
  echo "No sample directories found under $MEGAHIT_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

for sample_dir in "${sample_dirs[@]}"; do
  sample_id=$(basename "$sample_dir")
  contigs="$sample_dir/final.contigs.fa"
  r1="$TRIMMED_DIR/clean_${sample_id}_R1.fastq.gz"
  r2="$TRIMMED_DIR/clean_${sample_id}_R2.fastq.gz"
  out_dir="$BINS_DIR/$sample_id"

  # Check that contigs and reads exist
  if [[ -s "$contigs" && -s "$r1" && -s "$r2" ]]; then
    mkdir -p "$out_dir"
    echo " Running MaxBin2 on $sample_id." | tee -a "$LOG_FILE"

    "${MAMBA_RUN[@]}" run_MaxBin.pl \
      -contig "$contigs" \
      -reads "$r1" -reads2 "$r2" \
      -out "$out_dir/bin" \
      >> "$LOG_FILE" 2>&1

    echo " Finished $sample_id" | tee -a "$LOG_FILE"
  else
    echo " Skipping $sample_id — missing contigs or reads." | tee -a "$LOG_FILE"
  fi
done

echo "=== MaxBin2 binning finished ===" | tee -a "$LOG_FILE"