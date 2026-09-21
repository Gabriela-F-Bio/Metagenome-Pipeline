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
BIN_SOURCE="$MAXBIN_DIR"        # 4maxbin2
BIN_DEST="$CHECKM_BINS_DIR"     # 5checkm_bins
CHECKM_OUT="$CHECKM_DIR"        # 6checkm
SUMMARY_FILE="$CHECKM_OUT/qa_summary.tsv"
LOG_FILE="$LOG_DIR/checkm_log.txt"
ENV_NAME="${CHECKM_ENV_NAME:-checkm_env}"

# --- Determine whether to use shared or named micromamba env ---
SHARED_ENV_PATH="$TOOLS_ROOT/envs/$ENV_NAME"

if [[ -d "$SHARED_ENV_PATH" ]]; then
  echo "Using shared CheckM env at: $SHARED_ENV_PATH" | tee -a "$LOG_FILE"
  MAMBA_RUN=(micromamba run -p "$SHARED_ENV_PATH")
else
  echo "Using per-user CheckM env: $ENV_NAME" | tee -a "$LOG_FILE"
  MAMBA_RUN=(micromamba run -n "$ENV_NAME")
fi

# --- Setup ---
mkdir -p "$BIN_DEST" "$CHECKM_OUT"
: > "$LOG_FILE"

echo "=== CheckM for MAGs starting ===" | tee -a "$LOG_FILE"
echo "BIN_SOURCE:   $BIN_SOURCE"   | tee -a "$LOG_FILE"
echo "BIN_DEST:     $BIN_DEST"     | tee -a "$LOG_FILE"
echo "CHECKM_OUT:   $CHECKM_OUT"   | tee -a "$LOG_FILE"
echo "ENV_NAME:     $ENV_NAME"     | tee -a "$LOG_FILE"
echo "===============================" | tee -a "$LOG_FILE"

# --- Sanity checks ---
if [[ ! -d "$BIN_SOURCE" ]]; then
  echo "ERROR: BIN_SOURCE does not exist: $BIN_SOURCE" | tee -a "$LOG_FILE"
  exit 1
fi

if ! command -v micromamba &>/dev/null; then
  echo "ERROR: 'micromamba' not found in PATH. Check config.sh." | tee -a "$LOG_FILE"
  exit 1
fi

# quick check that CheckM is actually in the env
if ! "${MAMBA_RUN[@]}" checkm -h &>/dev/null; then
  echo "ERROR: CheckM not available in micromamba env '$ENV_NAME'." | tee -a "$LOG_FILE"
  echo "       Install with:" | tee -a "$LOG_FILE"
  echo "       micromamba create -y -p $TOOLS_ROOT/envs/$ENV_NAME -c bioconda -c conda-forge checkm-genome" | tee -a "$LOG_FILE"
  exit 1
fi

# --- Step 1: Collect bin.*.fasta files into a single folder ---
echo " Collecting MAG bins into $BIN_DEST" | tee -a "$LOG_FILE"

shopt -s nullglob
find "$BIN_SOURCE" -type f -name "bin.*.fasta" | while read -r bin_file; do
  sample=$(basename "$(dirname "$bin_file")")
  bin_id=$(basename "$bin_file" .fasta)
  cp "$bin_file" "$BIN_DEST/${sample}_${bin_id}.fa"
done
shopt -u nullglob

# --- Step 2: Run CheckM with logging ---
echo " Running CheckM lineage_wf..." | tee -a "$LOG_FILE"

"${MAMBA_RUN[@]}" checkm lineage_wf \
  -x fa \
  "$BIN_DEST" \
  "$CHECKM_OUT" \
  --reduced_tree --force -t 4 \
  >> "$LOG_FILE" 2>&1

echo " CheckM finished. Summary files should be under: $CHECKM_OUT" | tee -a "$LOG_FILE"
echo "=== CheckM for MAGs finished ===" | tee -a "$LOG_FILE"
