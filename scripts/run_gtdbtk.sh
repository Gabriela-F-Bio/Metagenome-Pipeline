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
GENOMES_DIR="$USABLE_MAG_DIR"    # 7usable_mags
OUT_DIR="$GTDBTK_DIR"            # 8gtdbtk
LOG="$LOG_DIR/gtdbtk_run_log.txt"

mkdir -p "$OUT_DIR"
: > "$LOG"

# --- Force safe TMPDIR for GTDB-Tk / SkANI ---
TMPDIR="$OUT_DIR/tmp"
mkdir -p "$TMPDIR"
export TMPDIR
export TEMP="$TMPDIR"
export TMP="$TMPDIR"

echo "TMPDIR set to: $TMPDIR" | tee -a "$LOG"

# CPUs (override by running: CPUS=16 ./run.sh gtdbtk)
CPUS="${CPUS:-$(nproc)}"
ENV_NAME="${GTDBTK_ENV_NAME:-gtdbtk_env}"

# --- Determine whether to use shared or named micromamba env ---
SHARED_ENV_PATH="$TOOLS_ROOT/envs/$ENV_NAME"

if [[ -d "$SHARED_ENV_PATH" ]]; then
  echo "Using shared GTDB-Tk env at: $SHARED_ENV_PATH" | tee -a "$LOG"
  MAMBA_RUN=(micromamba run -p "$SHARED_ENV_PATH")
else
  echo "Using per-user GTDB-Tk env: $ENV_NAME" | tee -a "$LOG"
  MAMBA_RUN=(micromamba run -n "$ENV_NAME")
fi

echo "GTDB-Tk classify_wf starting." | tee -a "$LOG"
echo "Genomes dir:  $GENOMES_DIR" | tee -a "$LOG"
echo "Output dir:   $OUT_DIR" | tee -a "$LOG"
echo "Env:          $ENV_NAME" | tee -a "$LOG"
echo "CPUs:         $CPUS" | tee -a "$LOG"

# --- sanity checks ---
if [[ ! -d "$GENOMES_DIR" ]]; then
  echo "ERROR: GENOMES_DIR does not exist: $GENOMES_DIR" | tee -a "$LOG"
  exit 1
fi

shopt -s nullglob
fa_count=("$GENOMES_DIR"/*.fa)
shopt -u nullglob
if [[ ${#fa_count[@]} -eq 0 ]]; then
  echo "ERROR: No .fa files found in $GENOMES_DIR" | tee -a "$LOG"
  exit 1
fi

if [[ -z "${GTDBTK_DATA_PATH:-}" ]]; then
  echo "ERROR: GTDBTK_DATA_PATH is not set." | tee -a "$LOG"
  echo "Fix: set it in config.sh, e.g.:" | tee -a "$LOG"
  echo "export GTDBTK_DATA_PATH=\"$TOOLS_ROOT/gtdbtk/release226\"" | tee -a "$LOG"
  exit 1
fi

if [[ ! -d "$GTDBTK_DATA_PATH" ]]; then
  echo "ERROR: GTDBTK_DATA_PATH does not exist: $GTDBTK_DATA_PATH" | tee -a "$LOG"
  exit 1
fi

if ! command -v micromamba &>/dev/null; then
  echo "ERROR: micromamba not found in PATH. Check config.sh." | tee -a "$LOG"
  exit 1
fi

# Optional but helpful for GTDB-Tk/pplacer
ulimit -n 65535 2>/dev/null || ulimit -n 8192 2>/dev/null || true
echo "ulimit -n: $(ulimit -n)" | tee -a "$LOG"

#env sanity check
if ! "${MAMBA_RUN[@]}" gtdbtk --version &>/dev/null; then
  echo "ERROR: GTDB-Tk not available in selected environment." | tee -a "$LOG"
  echo "Install with:" | tee -a "$LOG"
  echo "  micromamba create -y -p $TOOLS_ROOT/envs/$ENV_NAME -c bioconda -c conda-forge gtdbtk" | tee -a "$LOG"
  exit 1
fi

# --- run classify ---
echo "Running gtdbtk classify_wf..." | tee -a "$LOG"

"${MAMBA_RUN[@]}" gtdbtk classify_wf \
  --genome_dir "$GENOMES_DIR" \
  --out_dir "$OUT_DIR" \
  --extension fa \
  --cpus "$CPUS" \
  --pplacer_cpus "$CPUS" \
  2>&1 | tee -a "$LOG"

echo "GTDB-Tk finished. Building combined summaries..." | tee -a "$LOG"

# Combine bac120 + ar122 summaries and add a Domain column
SUM_COMBINED="$OUT_DIR/gtdbtk_summary_combined.tsv"
{
  header=""
  for f in "$OUT_DIR"/gtdbtk.*.summary.tsv; do
    [[ -f "$f" ]] || continue
    dom=$(basename "$f" | sed -E 's/.*\.(bac120|ar122)\.summary\.tsv/\1/')

    if [[ -z "$header" ]]; then
      printf "domain\t"
      head -n 1 "$f"
      header="done"
    fi

    tail -n +2 "$f" | awk -v d="$dom" 'BEGIN{OFS="\t"}{print (d=="bac120"?"Bacteria":"Archaea"), $0}'
  done
} > "$SUM_COMBINED"

# Create a compact mapping (bin -> GTDB taxonomy)
awk -F'\t' 'NR==1{
  for(i=1;i<=NF;i++){h[$i]=i}
  print "user_genome","domain","classification"
  next
}{
  print $h["user_genome"],$1,$h["classification"]
}' OFS='\t' "$SUM_COMBINED" > "$OUT_DIR/gtdbtk_taxonomy_map.tsv"

echo "Combined summary: $SUM_COMBINED" | tee -a "$LOG"
echo "Taxonomy map:     $OUT_DIR/gtdbtk_taxonomy_map.tsv" | tee -a "$LOG"

# Quick counts by phylum (optional quick view)
echo "Counts by phylum (quick view):" | tee -a "$LOG"
cut -f3 "$OUT_DIR/gtdbtk_taxonomy_map.tsv" | awk -F';' '/^d__/{
  phylum="p__Unclassified"
  for(i=1;i<=NF;i++){
    gsub(/^ +| +$/,"",$i)
    if($i ~ /^p__/) {phylum=$i; break}
  }
  print phylum
}' | sort | uniq -c | sort -nr | head -n 20 | tee -a "$LOG"

echo "Done." | tee -a "$LOG"