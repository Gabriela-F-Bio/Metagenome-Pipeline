#!/bin/bash
set -euo pipefail

# Usable MAGs (Round 1 pool)
# Criteria:
#   completeness >= 50
#   contamination <= 10

CONFIG_FILE="${1:-${CONFIG:-./config.sh}}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config.sh not found at: $CONFIG_FILE" >&2
  echo "Usage: $0 /path/to/project/config.sh" >&2
  exit 1
fi

source "$CONFIG_FILE"

LOG_DIR="${LOG_DIR:-$BASE/logs}"
mkdir -p "$LOG_DIR"

BIN_DIR="$CHECKM_BINS_DIR"
OUT_DIR="$USABLE_MAG_DIR"
SUMMARY_FILE="$OUT_DIR/filtering_summary.tsv"
LOG_FILE="$LOG_DIR/filter_usable_mags_log.txt"

# Common CheckM locations
if [[ -f "$CHECKM_DIR/bin_stats_ext.tsv" ]]; then
    STATS_FILE="$CHECKM_DIR/bin_stats_ext.tsv"
elif [[ -f "$CHECKM_DIR/storage/bin_stats_ext.tsv" ]]; then
    STATS_FILE="$CHECKM_DIR/storage/bin_stats_ext.tsv"
else
    echo "ERROR: Could not locate bin_stats_ext.tsv in:"
    echo "  $CHECKM_DIR/"
    echo "  $CHECKM_DIR/storage/"
    exit 1
fi

mkdir -p "$OUT_DIR"
: > "$LOG_FILE"

echo "=== Filtering usable MAGs ===" | tee -a "$LOG_FILE"
echo "BIN_DIR:      $BIN_DIR"        | tee -a "$LOG_FILE"
echo "CHECKM_DIR:   $CHECKM_DIR"     | tee -a "$LOG_FILE"
echo "OUT_DIR:      $OUT_DIR"        | tee -a "$LOG_FILE"
echo "STATS_FILE:   $STATS_FILE"     | tee -a "$LOG_FILE"
echo "SUMMARY_FILE: $SUMMARY_FILE"   | tee -a "$LOG_FILE"
echo "=============================" | tee -a "$LOG_FILE"

if [[ ! -d "$BIN_DIR" ]]; then
  echo "ERROR: BIN_DIR does not exist: $BIN_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

python - "$STATS_FILE" "$SUMMARY_FILE" "$BIN_DIR" "$OUT_DIR" "$LOG_FILE" << 'PY'
import csv, sys, os, shutil, ast

stats_file, summary_file, bin_dir, out_dir, log_file = sys.argv[1:]

MIN_COMP = 50.0
MAX_CONT = 10.0

records = []

with open(stats_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue

        parts = line.split("\t", 1)

        if len(parts) == 2 and parts[1].lstrip().startswith("{"):
            binid = parts[0].strip()
            stats = ast.literal_eval(parts[1])
            records.append({
                "binid": binid,
                "comp": float(stats.get("Completeness", 0)),
                "cont": float(stats.get("Contamination", 0)),
            })

        else:
            # fallback for normal TSV tables
            f.seek(0)
            reader = csv.DictReader(f, delimiter="\t")
            rows = list(reader)

            def find_col(options):
                headers = list(rows[0].keys())
                for opt in options:
                    if opt in headers:
                        return opt
                raise RuntimeError(f"Could not find any of columns {options!r} in header: {headers}")

            bin_col = find_col(["Bin Id", "Bin_Id", "Bin", "BinID"])
            comp_col = find_col(["Completeness"])
            cont_col = find_col(["Contamination"])

            for row in rows:
                records.append({
                    "binid": row[bin_col].strip(),
                    "comp": float(row[comp_col]),
                    "cont": float(row[cont_col]),
                })
            break

if not records:
    raise SystemExit(f"No records found in {stats_file}")

kept = 0
total = 0
missing_fasta = 0

os.makedirs(out_dir, exist_ok=True)

with open(summary_file, "w", newline="") as out, open(log_file, "a") as log:
    writer = csv.writer(out, delimiter="\t")
    writer.writerow(["BinID", "Completeness", "Contamination", "Status"])

    for rec in records:
        total += 1
        binid = rec["binid"]
        comp = rec["comp"]
        cont = rec["cont"]

        if comp >= MIN_COMP and cont <= MAX_CONT:
            src_fa = os.path.join(bin_dir, f"{binid}.fa")
            dst_fa = os.path.join(out_dir, f"{binid}.fa")

            if os.path.isfile(src_fa):
                shutil.copy(src_fa, dst_fa)
                kept += 1
                writer.writerow([binid, comp, cont, "KEPT"])
                print(f"Keeping {binid} (Comp={comp:.2f}, Cont={cont:.2f})", file=log)
            else:
                missing_fasta += 1
                writer.writerow([binid, comp, cont, "KEPT (FASTA missing)"])
                print(f"{binid} passes filters but FASTA not found: {src_fa}", file=log)
        else:
            writer.writerow([binid, comp, cont, "DISCARDED"])

    print(f"\nTotal bins: {total}", file=log)
    print(f"Kept usable: {kept}", file=log)
    print(f"Passing but missing FASTA: {missing_fasta}", file=log)

PY

echo "Usable MAG filtering complete."
echo "  Usable MAGs directory: $OUT_DIR"
echo "  Summary file:          $SUMMARY_FILE"