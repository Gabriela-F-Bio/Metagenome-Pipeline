#!/bin/bash
set -euo pipefail

# Split usable MAGs into four tiers (high, near_high, near_med, med)
# and join GTDB taxonomy from gtdbtk_taxonomy_map.tsv.
#
# Tiers (non-overlapping, exhaustive for usable MAGs):
#   high:      comp >= 90  AND cont <= 5
#   near_high: comp >= 90  AND 5 < cont <= 10
#   near_med:  50 <= comp < 90 AND cont <= 5
#   med:       50 <= comp < 90 AND 5 < cont <= 10
#
# Assumes:
#   - Usable MAGs are in $USABLE_MAG_DIR as <BinID>.fa
#   - CheckM stats: $CHECKM_DIR/bin_stats_ext.tsv
#   - GTDB taxonomy map: $GTDBTK_DIR/gtdbtk_taxonomy_map.tsv
#   - Prevalence summary (optional): $PREVALENCE_DIR/mag_prevalence.tsv
#
# Outputs:
#   - Copies FASTAs into 4 tier directories
#   - Writes tier tables (TSV) with taxonomy + metrics + prevalence columns
#   - Writes a combined usable table for convenience
#   - If prevalence was not run, prevalence columns are left blank

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
CHECKM_STATS="$CHECKM_DIR/storage/bin_stats_ext.tsv"
TAX_MAP="$GTDBTK_DIR/gtdbtk_taxonomy_map.tsv"
PREVALENCE_MAP="$PREVALENCE_DIR/mag_prevalence.tsv"

# Tier output dirs (define in config.sh, or fallback to sensible defaults under BASE)
HQ_DIR="${HQ_MAG_DIR:-$BASE/7high_quality_mags}"
NEAR_HQ_DIR="${NEAR_HQ_MAG_DIR:-$BASE/7near_high_mags}"
NEAR_MED_DIR="${NEAR_MED_MAG_DIR:-$BASE/7near_medium_mags}"
MED_DIR="${MED_MAG_DIR:-$BASE/7medium_mags}"

# Output tables
OUT_ALL_TABLE="$USABLE_DIR/usable_taxonomy.tsv"
OUT_HQ_TABLE="$HQ_DIR/high_taxonomy.tsv"
OUT_NEAR_HQ_TABLE="$NEAR_HQ_DIR/near_high_taxonomy.tsv"
OUT_NEAR_MED_TABLE="$NEAR_MED_DIR/near_med_taxonomy.tsv"
OUT_MED_TABLE="$MED_DIR/med_taxonomy.tsv"

LOG="$LOG_DIR/split_usable_join_taxonomy.log"
: > "$LOG"

echo "=== Split usable MAGs + join GTDB taxonomy (4 tiers) ===" | tee -a "$LOG"
echo "USABLE_DIR:     $USABLE_DIR" | tee -a "$LOG"
echo "CHECKM_STATS:   $CHECKM_STATS" | tee -a "$LOG"
echo "TAX_MAP:        $TAX_MAP" | tee -a "$LOG"
echo "PREVALENCE_MAP: $PREVALENCE_MAP" | tee -a "$LOG"
echo "HIGH_DIR:       $HQ_DIR" | tee -a "$LOG"
echo "NEAR_HIGH_DIR:  $NEAR_HQ_DIR" | tee -a "$LOG"
echo "NEAR_MED_DIR:   $NEAR_MED_DIR" | tee -a "$LOG"
echo "MED_DIR:        $MED_DIR" | tee -a "$LOG"
echo "=======================================================" | tee -a "$LOG"

# Sanity checks
if [[ ! -d "$USABLE_DIR" ]]; then
  echo "ERROR: USABLE_DIR not found: $USABLE_DIR" | tee -a "$LOG"
  exit 1
fi
if [[ ! -f "$CHECKM_STATS" ]]; then
  echo "ERROR: CheckM stats not found: $CHECKM_STATS" | tee -a "$LOG"
  exit 1
fi
if [[ ! -f "$TAX_MAP" ]]; then
  echo "ERROR: GTDB taxonomy map not found: $TAX_MAP" | tee -a "$LOG"
  echo "Expected: $GTDBTK_DIR/gtdbtk_taxonomy_map.tsv" | tee -a "$LOG"
  exit 1
fi

#Checks for Optional Prevalence 
USE_PREVALENCE=true
if [[ ! -f "$PREVALENCE_MAP" ]]; then
  echo "WARNING: prevalence summary not found: $PREVALENCE_MAP" | tee -a "$LOG"
  echo "Continuing without prevalence data." | tee -a "$LOG"
  USE_PREVALENCE=false
fi

if [[ "$USE_PREVALENCE" == true ]]; then
  echo "Integrating prevalence data into output tables." | tee -a "$LOG"
fi

mkdir -p "$HQ_DIR" "$NEAR_HQ_DIR" "$NEAR_MED_DIR" "$MED_DIR"

python3 - <<'PY' \
  "$USABLE_DIR" "$CHECKM_STATS" "$TAX_MAP" "$PREVALENCE_MAP" "$USE_PREVALENCE" \
  "$HQ_DIR" "$NEAR_HQ_DIR" "$NEAR_MED_DIR" "$MED_DIR" \
  "$OUT_HQ_TABLE" "$OUT_NEAR_HQ_TABLE" "$OUT_NEAR_MED_TABLE" "$OUT_MED_TABLE" "$OUT_ALL_TABLE" "$LOG"
import csv
import os
import shutil
import sys

(
    usable_dir, checkm_stats, tax_map, prevalence_map, use_prevalence_str,
    hq_dir, near_hq_dir, near_med_dir, med_dir,
    out_hq, out_near_hq, out_near_med, out_med, out_all,
    log_file
) = sys.argv[1:]

use_prevalence = use_prevalence_str.lower() == "true"

def log(msg: str):
    with open(log_file, "a") as lf:
        lf.write(msg + "\n")

# Load taxonomy map: user_genome -> (domain, classification)
tax = {}
with open(tax_map) as f:
    r = csv.DictReader(f, delimiter="\t")
    for row in r:
        genome = row.get("user_genome") or row.get("genome") or row.get("BinID")
        if not genome:
            continue
        tax[genome] = {
            "domain": row.get("domain", ""),
            "classification": row.get("classification", ""),
        }

# Load prevalence summary if available: genome -> (samples_present, total_samples, prevalence)
prev = {}
if use_prevalence:
    with open(prevalence_map) as f:
        r = csv.DictReader(f, delimiter="\t")
        for row in r:
            genome = row.get("genome") or row.get("BinID") or row.get("user_genome")
            if not genome:
                continue
            prev[genome] = {
                "samples_present": row.get("samples_present", ""),
                "total_samples": row.get("total_samples", ""),
                "prevalence": row.get("prevalence", ""),
            }

# Read CheckM stats
# Handles CheckM storage/bin_stats_ext.tsv format:
# bin_id<TAB>{stats dictionary}
import ast

rows = []
with open(checkm_stats) as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t", 1)
        if len(parts) != 2:
            continue

        binid, stats_txt = parts
        stats = ast.literal_eval(stats_txt)

        rows.append({
            "Bin Id": binid,
            "Completeness": stats.get("Completeness", ""),
            "Contamination": stats.get("Contamination", "")
        })

if not rows:
    raise SystemExit(f"No rows found in {checkm_stats}")

bin_col = "Bin Id"
comp_col = "Completeness"
cont_col = "Contamination"

header = [
    "BinID", "Completeness", "Contamination", "Tier",
    "GTDB_domain", "GTDB_classification",
    "samples_present", "total_samples", "prevalence",
    "FASTA_status"
]

def write_rows(path, rows_out):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", newline="") as out:
        w = csv.writer(out, delimiter="\t")
        w.writerow(header)
        for r in rows_out:
            w.writerow(r)

hq_rows, near_hq_rows, near_med_rows, med_rows, all_rows = [], [], [], [], []

counts = {"high": 0, "near_high": 0, "near_med": 0, "med": 0}
missing_tax = 0
missing_prev = 0
considered = 0
unclassified = 0

# We only classify bins that exist in usable_dir (so we don't revive discarded bins)
for row in rows:
    binid = row[bin_col]
    fasta_path = os.path.join(usable_dir, f"{binid}.fa")
    if not os.path.isfile(fasta_path):
        continue

    considered += 1

    try:
        comp = float(row[comp_col])
        cont = float(row[cont_col])
    except ValueError:
        log(f"Skipping {binid}: could not parse completeness/contamination")
        continue

    # Tier definitions (exhaustive for usable MAGs if usable was comp>=50 & cont<=10)
    if comp >= 90 and cont <= 5:
        tier = "high"
    elif comp >= 90 and 5 < cont <= 10:
        tier = "near_high"
    elif 50 <= comp < 90 and cont <= 5:
        tier = "near_med"
    elif 50 <= comp < 90 and 5 < cont <= 10:
        tier = "med"
    else:
        tier = "unclassified"
        unclassified += 1
        log(f"Unclassified (still in usable_dir): {binid} comp={comp:.2f} cont={cont:.2f}")

    tx = tax.get(binid)
    if not tx:
        missing_tax += 1
        g_domain, g_class = "", ""
    else:
        g_domain, g_class = tx.get("domain", ""), tx.get("classification", "")

    pv = prev.get(binid)
    if not pv:
        if use_prevalence:
            missing_prev += 1
        samples_present, total_samples, prevalence = "", "", ""
    else:
        samples_present = pv.get("samples_present", "")
        total_samples = pv.get("total_samples", "")
        prevalence = pv.get("prevalence", "")

    fasta_status = "OK"
    row_out = [
        binid, f"{comp:.2f}", f"{cont:.2f}", tier,
        g_domain, g_class,
        samples_present, total_samples, prevalence,
        fasta_status,
    ]

    # Copy fasta into tier folder + collect rows
    if tier == "high":
        dest = os.path.join(hq_dir, f"{binid}.fa")
        if not os.path.exists(dest):
            shutil.copy(fasta_path, dest)
        counts["high"] += 1
        hq_rows.append(row_out)
        all_rows.append(row_out)

    elif tier == "near_high":
        dest = os.path.join(near_hq_dir, f"{binid}.fa")
        if not os.path.exists(dest):
            shutil.copy(fasta_path, dest)
        counts["near_high"] += 1
        near_hq_rows.append(row_out)
        all_rows.append(row_out)

    elif tier == "near_med":
        dest = os.path.join(near_med_dir, f"{binid}.fa")
        if not os.path.exists(dest):
            shutil.copy(fasta_path, dest)
        counts["near_med"] += 1
        near_med_rows.append(row_out)
        all_rows.append(row_out)

    elif tier == "med":
        dest = os.path.join(med_dir, f"{binid}.fa")
        if not os.path.exists(dest):
            shutil.copy(fasta_path, dest)
        counts["med"] += 1
        med_rows.append(row_out)
        all_rows.append(row_out)

    else:
        all_rows.append(row_out)

# Write tables
write_rows(out_all, all_rows)
write_rows(out_hq, hq_rows)
write_rows(out_near_hq, near_hq_rows)
write_rows(out_near_med, near_med_rows)
write_rows(out_med, med_rows)

log("")
log(f"Usable MAGs considered (FASTA present): {considered}")
log(f"High:      {counts['high']}")
log(f"Near_high: {counts['near_high']}")
log(f"Near_med:  {counts['near_med']}")
log(f"Med:       {counts['med']}")
log(f"Unclassified (unexpected): {unclassified}")
log(f"Missing GTDB taxonomy rows: {missing_tax}")
if use_prevalence:
    log(f"Missing prevalence rows: {missing_prev}")
else:
    log("Prevalence not provided; prevalence columns left blank.")
PY

echo "Done splitting usable MAGs." | tee -a "$LOG"
echo "Tables written:" | tee -a "$LOG"
echo "  $OUT_ALL_TABLE" | tee -a "$LOG"
echo "  $OUT_HQ_TABLE" | tee -a "$LOG"
echo "  $OUT_NEAR_HQ_TABLE" | tee -a "$LOG"
echo "  $OUT_NEAR_MED_TABLE" | tee -a "$LOG"
echo "  $OUT_MED_TABLE" | tee -a "$LOG"
echo "Log: $LOG" | tee -a "$LOG"
