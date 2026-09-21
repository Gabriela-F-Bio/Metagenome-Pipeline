#!/bin/bash
set -euo pipefail

CONFIG_FILE="${1:-${CONFIG:-./config.sh}}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config.sh not found at: $CONFIG_FILE" >&2
  echo "Usage: $0 /path/to/project/config.sh" >&2
  exit 1
fi

source "$CONFIG_FILE"

LOG_DIR="${LOG_DIR:-$BASE/logs}"
mkdir -p "$LOG_DIR" "$MAP_DIR" "$BOWTIE2_DIR" "$COVERAGE_DIR" "$PREVALENCE_DIR"
LOG_FILE="$LOG_DIR/map_prevalence_log.txt"
: > "$LOG_FILE"

BOWTIE2_ENV_NAME="${BOWTIE2_ENV_NAME:-mapping_env}"
SHARED_ENV_PATH="$TOOLS_ROOT/envs/$BOWTIE2_ENV_NAME"

if [[ -d "$SHARED_ENV_PATH" ]]; then
  echo "Using shared mapping env at: $SHARED_ENV_PATH" | tee -a "$LOG_FILE"
  MAMBA_RUN=(micromamba run -p "$SHARED_ENV_PATH")
else
  echo "Using named mapping env: $BOWTIE2_ENV_NAME" | tee -a "$LOG_FILE"
  MAMBA_RUN=(micromamba run -n "$BOWTIE2_ENV_NAME")
fi

REF_FASTA="${REF_FASTA:-$MAP_DIR/all_mags.fa}"
INDEX_PREFIX="${BOWTIE2_INDEX_PREFIX:-$BOWTIE2_DIR/usable_mags_idx}"
BAM_MANIFEST="$MAP_DIR/bam_manifest.tsv"
COVERAGE_TSV="$COVERAGE_DIR/mag_coverage_by_sample.tsv"
PRESENCE_TSV="$PREVALENCE_DIR/mag_presence_absence.tsv"
PREVALENCE_TSV="$PREVALENCE_DIR/mag_prevalence.tsv"
THREADS="${THREADS:-8}"
MIN_BREADTH="${MIN_BREADTH:-0.30}"
MIN_MEAN_COV="${MIN_MEAN_COV:-1.0}"

for cmd in micromamba python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found in PATH: $cmd" | tee -a "$LOG_FILE"
    exit 1
  fi
done

if ! "${MAMBA_RUN[@]}" bowtie2 --version >/dev/null 2>&1; then
  echo "ERROR: bowtie2 not available in env '$BOWTIE2_ENV_NAME'." | tee -a "$LOG_FILE"
  exit 1
fi
if ! "${MAMBA_RUN[@]}" samtools --version >/dev/null 2>&1; then
  echo "ERROR: samtools not available in env '$BOWTIE2_ENV_NAME'." | tee -a "$LOG_FILE"
  exit 1
fi
if ! "${MAMBA_RUN[@]}" coverm --help >/dev/null 2>&1; then
  echo "ERROR: coverm not available in env '$BOWTIE2_ENV_NAME'." | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -d "$USABLE_MAG_DIR" ]]; then
  echo "ERROR: USABLE_MAG_DIR does not exist: $USABLE_MAG_DIR" | tee -a "$LOG_FILE"
  exit 1
fi
if [[ ! -d "$TRIMMED_DIR" ]]; then
  echo "ERROR: TRIMMED_DIR does not exist: $TRIMMED_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

shopt -s nullglob
mag_files=("$USABLE_MAG_DIR"/*.fa "$USABLE_MAG_DIR"/*.fasta "$USABLE_MAG_DIR"/*.fna)
if [[ ${#mag_files[@]} -eq 0 ]]; then
  echo "ERROR: no MAG FASTA files found in $USABLE_MAG_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

r1_files=("$TRIMMED_DIR"/*_R1.fastq "$TRIMMED_DIR"/*_R1.fastq.gz)
if [[ ${#r1_files[@]} -eq 0 ]]; then
  echo "ERROR: no trimmed R1 FASTQ files found in $TRIMMED_DIR" | tee -a "$LOG_FILE"
  exit 1
fi
shopt -u nullglob

if [[ ! -s "$REF_FASTA" ]]; then
  echo "Concatenating usable MAGs into $REF_FASTA" | tee -a "$LOG_FILE"
  : > "$REF_FASTA"

for f in "${mag_files[@]}"; do
  mag=$(basename "$f")
  mag="${mag%.*}"

  awk -v mag="$mag" '
    /^>/ {
      sub(/^>/, "", $0)
      print ">" mag "|" $0
      next
    }
    { print }
  ' "$f" >> "$REF_FASTA"
done

fi

if [[ ! -s "$REF_FASTA" ]]; then
  echo "ERROR: reference FASTA is empty: $REF_FASTA" | tee -a "$LOG_FILE"
  exit 1
fi

if [[ ! -f "${INDEX_PREFIX}.1.bt2" && ! -f "${INDEX_PREFIX}.1.bt2l" ]]; then
  echo "Building Bowtie2 index..." | tee -a "$LOG_FILE"
  "${MAMBA_RUN[@]}" bowtie2-build "$REF_FASTA" "$INDEX_PREFIX" >> "$LOG_FILE" 2>&1
fi

echo -e "sample\tbam" > "$BAM_MANIFEST"

echo "Mapping samples..." | tee -a "$LOG_FILE"
shopt -s nullglob
for r1 in "$TRIMMED_DIR"/*_R1.fastq "$TRIMMED_DIR"/*_R1.fastq.gz; do
  [[ -e "$r1" ]] || continue
	base=$(basename "$r1")
	sample="$base"
	sample="${sample%_R1.fastq.gz}"
	sample="${sample%_R1.fastq}"
	sample="${sample%_1.fastq.gz}"
	sample="${sample%_1.fastq}"

	r2="$r1"
	r2="${r2/_R1.fastq.gz/_R2.fastq.gz}"
	r2="${r2/_R1.fastq/_R2.fastq}"
	r2="${r2/_1.fastq.gz/_2.fastq.gz}"
	r2="${r2/_1.fastq/_2.fastq}"
  if [[ ! -f "$r2" ]]; then
    echo "WARNING: skipping $sample because mate file not found for $r1" | tee -a "$LOG_FILE"
    continue
  fi

  bam="$BOWTIE2_DIR/${sample}.sorted.bam"
  if [[ -f "$bam" ]]; then
    echo "Existing BAM found for $sample, skipping mapping" | tee -a "$LOG_FILE"
  else
    echo "Mapping $sample" | tee -a "$LOG_FILE"
    "${MAMBA_RUN[@]}" bowtie2 --very-sensitive -x "$INDEX_PREFIX" -1 "$r1" -2 "$r2" -p "$THREADS" 2>> "$LOG_FILE" |
      "${MAMBA_RUN[@]}" samtools view -bS - 2>> "$LOG_FILE" |
      "${MAMBA_RUN[@]}" samtools sort -@ "$THREADS" -o "$bam" - 2>> "$LOG_FILE"
    "${MAMBA_RUN[@]}" samtools index "$bam" >> "$LOG_FILE" 2>&1
  fi

  echo -e "${sample}\t${bam}" >> "$BAM_MANIFEST"
done
shopt -u nullglob

mapfile -t bam_files < <(tail -n +2 "$BAM_MANIFEST" | cut -f2)
if [[ ${#bam_files[@]} -eq 0 ]]; then
  echo "ERROR: no BAM files produced." | tee -a "$LOG_FILE"
  exit 1
fi

COVERM_GENOME_DIR="$MAP_DIR/coverm_genomes_fna"
mkdir -p "$COVERM_GENOME_DIR"
rm -f "$COVERM_GENOME_DIR"/*.fna

for f in "$USABLE_MAG_DIR"/*.fa "$USABLE_MAG_DIR"/*.fasta "$USABLE_MAG_DIR"/*.fna; do
  [[ -e "$f" ]] || continue
  base=$(basename "$f")
  base="${base%.*}"

  awk -v mag="$base" '
    /^>/ {
      sub(/^>/, "", $0)
      print ">" mag "|" $0
      next
    }
    { print }
  ' "$f" > "$COVERM_GENOME_DIR/${base}.fna"
done

expected_bam_count=${#bam_files[@]}

coverage_sample_count=0
if [[ -s "$COVERAGE_TSV" ]]; then
  coverage_sample_count=$(awk -F'\t' 'NR > 1 {seen[$1]=1} END {print length(seen)}' "$COVERAGE_TSV")
fi

if [[ -s "$COVERAGE_TSV" && "$coverage_sample_count" -eq "$expected_bam_count" ]]; then
  echo "Using existing coverage table: $COVERAGE_TSV" | tee -a "$LOG_FILE"
  echo "Coverage table sample count matches BAM manifest: $coverage_sample_count/$expected_bam_count" | tee -a "$LOG_FILE"
elif [[ -s "$COVERAGE_TSV" ]]; then
  timestamp=$(date +%Y%m%d_%H%M%S)
  backup_coverage="${COVERAGE_TSV}.old_${coverage_sample_count}samples_${timestamp}"
  backup_presence="${PRESENCE_TSV}.old_${timestamp}"
  backup_prevalence="${PREVALENCE_TSV}.old_${timestamp}"

  echo "WARNING: Existing coverage table has $coverage_sample_count samples, but BAM manifest has $expected_bam_count samples." | tee -a "$LOG_FILE"
  echo "Backing up old coverage table to: $backup_coverage" | tee -a "$LOG_FILE"
  mv "$COVERAGE_TSV" "$backup_coverage"

  if [[ -s "$PRESENCE_TSV" ]]; then
    echo "Backing up old presence table to: $backup_presence" | tee -a "$LOG_FILE"
    mv "$PRESENCE_TSV" "$backup_presence"
  fi
  if [[ -s "$PREVALENCE_TSV" ]]; then
    echo "Backing up old prevalence table to: $backup_prevalence" | tee -a "$LOG_FILE"
    mv "$PREVALENCE_TSV" "$backup_prevalence"
  fi

  echo "Regenerating genome coverage with coverM using all $expected_bam_count BAM files..." | tee -a "$LOG_FILE"
  "${MAMBA_RUN[@]}" coverm genome \
    --bam-files "${bam_files[@]}" \
    --genome-fasta-directory "$COVERM_GENOME_DIR" \
    --methods mean covered_fraction \
    --threads "$THREADS" \
    --output-format sparse \
    > "$COVERAGE_TSV"
else
  echo "Calculating genome coverage with coverM using $expected_bam_count BAM files..." | tee -a "$LOG_FILE"
  "${MAMBA_RUN[@]}" coverm genome \
    --bam-files "${bam_files[@]}" \
    --genome-fasta-directory "$COVERM_GENOME_DIR" \
    --methods mean covered_fraction \
    --threads "$THREADS" \
    --output-format sparse \
    > "$COVERAGE_TSV"
fi

new_coverage_sample_count=$(awk -F'\t' 'NR > 1 {seen[$1]=1} END {print length(seen)}' "$COVERAGE_TSV")
if [[ "$new_coverage_sample_count" -ne "$expected_bam_count" ]]; then
  echo "ERROR: Coverage table has $new_coverage_sample_count samples, but BAM manifest has $expected_bam_count samples." | tee -a "$LOG_FILE"
  echo "Coverage samples:" | tee -a "$LOG_FILE"
  cut -f1 "$COVERAGE_TSV" | sort -u | tee -a "$LOG_FILE"
  echo "BAM manifest samples:" | tee -a "$LOG_FILE"
  tail -n +2 "$BAM_MANIFEST" | cut -f1 | sort -u | tee -a "$LOG_FILE"
  exit 1
fi

python3 - "$COVERAGE_TSV" "$PRESENCE_TSV" "$PREVALENCE_TSV" "$MIN_BREADTH" "$MIN_MEAN_COV" <<'PY'
import csv
import sys
from collections import defaultdict

coverage_tsv, presence_tsv, prevalence_tsv, min_breadth, min_mean_cov = sys.argv[1:]
min_breadth = float(min_breadth)
min_mean_cov = float(min_mean_cov)

rows = []
with open(coverage_tsv, newline='') as f:
    reader = csv.DictReader(f, delimiter='\t')
    for row in reader:
        rows.append(row)

if not rows:
    raise SystemExit('No coverage rows found in ' + coverage_tsv)

sample_key = next((k for k in rows[0] if k.lower() == 'sample'), None)
genome_key = next((k for k in rows[0] if k.lower() == 'genome'), None)
mean_key = next((k for k in rows[0] if 'mean' in k.lower()), None)
breadth_key = next((k for k in rows[0] if 'covered' in k.lower() and 'fraction' in k.lower()), None)

if not all([sample_key, genome_key, mean_key, breadth_key]):
    raise SystemExit('Missing expected columns in coverM output')

samples = sorted({r[sample_key] for r in rows})
genomes = sorted({r[genome_key] for r in rows})
presence = defaultdict(dict)
counts = defaultdict(int)

for r in rows:
    sample = r[sample_key]
    genome = r[genome_key]
    mean_cov = float(r[mean_key]) if r[mean_key] not in ('', 'NA') else 0.0
    breadth = float(r[breadth_key]) if r[breadth_key] not in ('', 'NA') else 0.0
    present = int(mean_cov >= min_mean_cov and breadth >= min_breadth)
    presence[genome][sample] = present
    counts[genome] += present

with open(presence_tsv, 'w', newline='') as f:
    writer = csv.writer(f, delimiter='\t')
    writer.writerow(['genome'] + samples)
    for genome in genomes:
        writer.writerow([genome] + [presence[genome].get(sample, 0) for sample in samples])

with open(prevalence_tsv, 'w', newline='') as f:
    writer = csv.writer(f, delimiter='\t')
    writer.writerow(['genome', 'samples_present', 'total_samples', 'prevalence'])
    total = len(samples)
    for genome in genomes:
        c = counts[genome]
        writer.writerow([genome, c, total, c / total if total else 0])
PY

echo "Done." | tee -a "$LOG_FILE"
echo "Combined reference: $REF_FASTA" | tee -a "$LOG_FILE"
echo "BAM manifest:       $BAM_MANIFEST" | tee -a "$LOG_FILE"
echo "Coverage table:     $COVERAGE_TSV" | tee -a "$LOG_FILE"
echo "Presence table:     $PRESENCE_TSV" | tee -a "$LOG_FILE"
echo "Prevalence table:   $PREVALENCE_TSV" | tee -a "$LOG_FILE"
