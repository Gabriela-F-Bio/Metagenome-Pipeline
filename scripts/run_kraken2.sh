#!/bin/bash
set -euo pipefail

CONFIG_FILE="${1:-${CONFIG:-./config.sh}}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config.sh not found at: $CONFIG_FILE" >&2
  exit 1
fi

source "$CONFIG_FILE"

LOG_DIR="${LOG_DIR:-$BASE/logs}"
mkdir -p "$LOG_DIR"

KRAKEN2_DIR="${KRAKEN2_DIR:-$BASE/11kraken2}"
KRAKEN2_REPORT_DIR="${KRAKEN2_REPORT_DIR:-$KRAKEN2_DIR/reports}"
KRAKEN2_OUTPUT_DIR="${KRAKEN2_OUTPUT_DIR:-$KRAKEN2_DIR/outputs}"
BRACKEN_DIR="${BRACKEN_DIR:-$KRAKEN2_DIR/bracken}"
KRAKEN2_SUMMARY_DIR="${KRAKEN2_SUMMARY_DIR:-$KRAKEN2_DIR/summary}"

mkdir -p "$KRAKEN2_REPORT_DIR" "$KRAKEN2_OUTPUT_DIR" "$BRACKEN_DIR" "$KRAKEN2_SUMMARY_DIR"

LOG_FILE="$LOG_DIR/kraken2_log.txt"
: > "$LOG_FILE"

KRAKEN2_THREADS="${KRAKEN2_THREADS:-${THREADS:-8}}"
KRAKEN2_CONFIDENCE="${KRAKEN2_CONFIDENCE:-0.10}"
BRACKEN_READ_LEN="${BRACKEN_READ_LEN:-150}"
BRACKEN_LEVEL="${BRACKEN_LEVEL:-S}"

if [[ ! -d "$TRIMMED_DIR" ]]; then
  echo "ERROR: TRIMMED_DIR does not exist: $TRIMMED_DIR" >&2
  exit 1
fi

if [[ -z "${KRAKEN2_DB:-}" || ! -d "$KRAKEN2_DB" ]]; then
  echo "ERROR: KRAKEN2_DB does not exist: ${KRAKEN2_DB:-unset}" >&2
  exit 1
fi

BRACKEN_DISTRIB="$KRAKEN2_DB/database${BRACKEN_READ_LEN}mers.kmer_distrib"

if [[ ! -f "$KRAKEN2_DB/hash.k2d" || ! -f "$KRAKEN2_DB/opts.k2d" || ! -f "$KRAKEN2_DB/taxo.k2d" ]]; then
  echo "ERROR: KRAKEN2_DB exists but does not look complete: $KRAKEN2_DB" >&2
  echo "Expected files: hash.k2d opts.k2d taxo.k2d" >&2
  exit 1
fi

############## KRAKEN2 / BRACKEN ENVIRONMENT ##############

KRAKEN2_ENV_NAME="${KRAKEN2_ENV_NAME:-kraken2_env}"
KRAKEN2_ENV_PATH="$TOOLS_ROOT/envs/$KRAKEN2_ENV_NAME"

if [[ -z "${MICROMAMBA_BIN:-}" || ! -x "$MICROMAMBA_BIN" ]]; then
  echo "ERROR: MICROMAMBA_BIN is not set or is not executable: ${MICROMAMBA_BIN:-unset}" >&2
  exit 1
fi

# Prefer the shared path-based environment created by bootstrap.sh.
# Fall back to the named user environment created by setup_user_envs.sh.
if [[ -d "$KRAKEN2_ENV_PATH" ]]; then
  KRAKEN2_ENV_ARGS=(-p "$KRAKEN2_ENV_PATH")
  KRAKEN2_ENV_LABEL="$KRAKEN2_ENV_PATH"
else
  KRAKEN2_ENV_ARGS=(-n "$KRAKEN2_ENV_NAME")
  KRAKEN2_ENV_LABEL="$KRAKEN2_ENV_NAME"
fi

if ! "$MICROMAMBA_BIN" run "${KRAKEN2_ENV_ARGS[@]}" kraken2 --version >/dev/null 2>&1; then
  echo "ERROR: Kraken2 environment not found or kraken2 is unavailable." >&2
  echo "Checked shared environment: $KRAKEN2_ENV_PATH" >&2
  echo "Checked named environment:  $KRAKEN2_ENV_NAME" >&2
  exit 1
fi

shopt -s nullglob
READS=("$TRIMMED_DIR"/clean_*_R1.fastq.gz)
shopt -u nullglob

if [[ ${#READS[@]} -eq 0 ]]; then
  echo "ERROR: No clean_*_R1.fastq.gz files found in $TRIMMED_DIR" >&2
  exit 1
fi

SUMMARY="$KRAKEN2_SUMMARY_DIR/kraken2_sample_summary.tsv"
echo -e "sample\tkraken_report\tkraken_output\tbracken_species" > "$SUMMARY"

echo "=== Kraken2 starting ===" | tee -a "$LOG_FILE"
echo "Config file: $CONFIG_FILE" | tee -a "$LOG_FILE"
echo "Trimmed dir: $TRIMMED_DIR" | tee -a "$LOG_FILE"
echo "Database:    $KRAKEN2_DB" | tee -a "$LOG_FILE"
echo "Output dir:  $KRAKEN2_DIR" | tee -a "$LOG_FILE"
echo "Threads:     $KRAKEN2_THREADS" | tee -a "$LOG_FILE"
echo "Confidence:  $KRAKEN2_CONFIDENCE" | tee -a "$LOG_FILE"
echo "Bracken read length: $BRACKEN_READ_LEN" | tee -a "$LOG_FILE"
echo "Bracken level:       $BRACKEN_LEVEL" | tee -a "$LOG_FILE"
echo "Environment: $KRAKEN2_ENV_LABEL" | tee -a "$LOG_FILE"

for R1 in "${READS[@]}"; do
  R2="${R1/_R1.fastq.gz/_R2.fastq.gz}"
  SAMPLE=$(basename "$R1" _R1.fastq.gz)
  SAMPLE="${SAMPLE#clean_}"

  REPORT="$KRAKEN2_REPORT_DIR/${SAMPLE}.kraken2.report"
  OUTPUT="$KRAKEN2_OUTPUT_DIR/${SAMPLE}.kraken2.output"
  BRACKEN_OUT="$BRACKEN_DIR/${SAMPLE}.bracken.${BRACKEN_LEVEL}.tsv"

  echo "Processing $SAMPLE..." | tee -a "$LOG_FILE"

  if [[ ! -f "$R2" ]]; then
    echo "WARNING: Missing mate file for $R1. Expected: $R2. Skipping." | tee -a "$LOG_FILE"
    continue
  fi

  "$MICROMAMBA_BIN" run "${KRAKEN2_ENV_ARGS[@]}" kraken2 \
    --db "$KRAKEN2_DB" \
    --threads "$KRAKEN2_THREADS" \
    --paired "$R1" "$R2" \
    --gzip-compressed \
    --confidence "$KRAKEN2_CONFIDENCE" \
    --report "$REPORT" \
    --output "$OUTPUT" \
    >> "$LOG_FILE" 2>&1

  if "$MICROMAMBA_BIN" run "${KRAKEN2_ENV_ARGS[@]}" bracken -v >/dev/null 2>&1 && \
   [[ -f "$BRACKEN_DISTRIB" ]]; then
  	"$MICROMAMBA_BIN" run "${KRAKEN2_ENV_ARGS[@]}" bracken \
  		-d "$KRAKEN2_DB" \
    	-i "$REPORT" \
    	-o "$BRACKEN_OUT" \
    	-r "$BRACKEN_READ_LEN" \
    	-l "$BRACKEN_LEVEL" \
    	>> "$LOG_FILE" 2>&1 || {
      		echo "WARNING: Bracken failed for $SAMPLE. Kraken2 output was still created." \
        		| tee -a "$LOG_FILE"
      		BRACKEN_OUT="NA"
    	}
  else
  	BRACKEN_OUT="NA"

  	if [[ ! -f "$BRACKEN_DISTRIB" ]]; then
    	echo "WARNING: Bracken support file not found: $BRACKEN_DISTRIB" \
      		| tee -a "$LOG_FILE"
    	echo "Install Bracken support files for read length $BRACKEN_READ_LEN or run bracken-build." \
      		| tee -a "$LOG_FILE"
  	else
    	echo "WARNING: Bracken is not available in $KRAKEN2_ENV_LABEL. Kraken2 output was still created." \
    		| tee -a "$LOG_FILE"
  	fi
fi

  echo -e "${SAMPLE}\t${REPORT}\t${OUTPUT}\t${BRACKEN_OUT}" >> "$SUMMARY"
  echo "Finished $SAMPLE" | tee -a "$LOG_FILE"
done

echo "Summary file: $SUMMARY" | tee -a "$LOG_FILE"
echo "=== Kraken2 finished ===" | tee -a "$LOG_FILE"
