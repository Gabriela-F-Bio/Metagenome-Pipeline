#!/bin/bash
set -euo pipefail

# Summarize CARD/RGI output.
# Produces:
#   1. amr_summary_by_mag.tsv = one row per MAG/BinID
#   2. all_rgi_hits.tsv = one row per RGI hit for ARG-level analysis

CONFIG_FILE="${1:-${CONFIG:-./config.sh}}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: config.sh not found at: $CONFIG_FILE" >&2
  echo "Usage: $0 /path/to/project/config.sh" >&2
  exit 1
fi

source "$CONFIG_FILE"

LOG_DIR="${LOG_DIR:-$BASE/logs}"
mkdir -p "$LOG_DIR" "$CARD_RGI_DIR"

LOG_FILE="$LOG_DIR/card_summary_log.txt"
: > "$LOG_FILE"

CARD_DIR="${CARD_RGI_DIR:-$BASE/9card_rgi}"
OUT_SUMMARY="$CARD_DIR/amr_summary_by_mag.tsv"
OUT_HITS="$CARD_DIR/all_rgi_hits.tsv"

MIN_IDENTITY="${AMR_MIN_IDENTITY:-0}"
MIN_COVERAGE="${AMR_MIN_COVERAGE:-0}"

if [[ ! -d "$CARD_DIR" ]]; then
  echo "ERROR: CARD_RGI_DIR does not exist: $CARD_DIR" | tee -a "$LOG_FILE"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found in PATH" | tee -a "$LOG_FILE"
  exit 1
fi

echo "=== CARD/RGI MAG-level AMR summary ===" | tee -a "$LOG_FILE"
echo "CARD_DIR:      $CARD_DIR" | tee -a "$LOG_FILE"
echo "OUT_SUMMARY:   $OUT_SUMMARY" | tee -a "$LOG_FILE"
echo "OUT_HITS:      $OUT_HITS" | tee -a "$LOG_FILE"
echo "MIN_IDENTITY:  $MIN_IDENTITY" | tee -a "$LOG_FILE"
echo "MIN_COVERAGE:  $MIN_COVERAGE" | tee -a "$LOG_FILE"
echo "======================================" | tee -a "$LOG_FILE"

python3 - "$CARD_DIR" "$OUT_SUMMARY" "$OUT_HITS" "$LOG_FILE" <<'PY'
import json, os, csv, sys
from collections import defaultdict

card_dir, out_summary, out_hits, log_file = sys.argv[1:]

summary = defaultdict(lambda: {
    "hit_count": 0,
    "genes": set(),
    "drug_classes": set(),
    "mechanisms": set(),
    "families": set(),
    "source_files": set(),
})

def clean_binid(fn):
    name = os.path.basename(fn)
    if name.endswith("_rgi.json"):
        name = name[:-len("_rgi.json")]
    elif name.endswith(".json"):
        name = name[:-len(".json")]
    return name

def get_first(rec, keys, default=""):
    for key in keys:
        value = rec.get(key)
        if value not in (None, ""):
            return value
    return default

def split_categories(rec):
    drug_classes = set()
    mechanisms = set()
    families = set()
    cats = rec.get("ARO_category", {})
    if isinstance(cats, dict):
        for c in cats.values():
            if not isinstance(c, dict):
                continue
            cname = c.get("category_aro_name", "")
            cclass = c.get("category_aro_class_name", "")
            if not cname:
                continue
            if cclass == "Drug Class":
                drug_classes.add(cname)
            elif cclass == "Resistance Mechanism":
                mechanisms.add(cname)
            elif cclass == "AMR Gene Family":
                families.add(cname)
    return drug_classes, mechanisms, families

json_files = sorted(
    os.path.join(card_dir, f)
    for f in os.listdir(card_dir)
    if f.endswith("_rgi.json")
)

hit_rows = []

for path in json_files:
    binid = clean_binid(path)
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception as e:
        with open(log_file, "a") as log:
            log.write(f"WARNING: skipped {path}: {e}\n")
        continue

    for orf_id, hits in data.items():
        if str(orf_id).startswith("_") or not isinstance(hits, dict):
            continue

        for hit_id, rec in hits.items():
            if not isinstance(rec, dict):
                continue

            aro_name = rec.get("ARO_name", "")
            if not aro_name:
                continue

            summary[binid]["hit_count"] += 1
            summary[binid]["genes"].add(aro_name)
            summary[binid]["source_files"].add(os.path.basename(path))

            drug_classes, mechanisms, families = split_categories(rec)
            summary[binid]["drug_classes"].update(drug_classes)
            summary[binid]["mechanisms"].update(mechanisms)
            summary[binid]["families"].update(families)

            hit_rows.append({
                "BinID": binid,
                "source_file": os.path.basename(path),
                "ORF_ID": orf_id,
                "hit_id": hit_id,
                "ARO_name": aro_name,
                "ARO_accession": get_first(rec, ["ARO_accession", "ARO_accession_number", "ARO"]),
                "model_type": get_first(rec, ["model_type", "Model_type", "type_match"]),
                "cut_off": get_first(rec, ["type_match", "cut_off", "Cut_Off"]),
                "best_hit_bitscore": get_first(rec, ["bit_score", "bitscore", "Best_Hit_Bitscore"]),
                "pass_bitscore": get_first(rec, ["pass_bitscore", "Pass_Bitscore"]),
                "percent_identity": get_first(rec, ["perc_identity", "percent_identity", "Best_Identities"]),
                "drug_classes": ";".join(sorted(drug_classes)),
                "resistance_mechanisms": ";".join(sorted(mechanisms)),
                "amr_gene_families": ";".join(sorted(families)),
            })

with open(out_hits, "w", newline="") as out:
    fieldnames = [
        "BinID",
        "source_file",
        "ORF_ID",
        "hit_id",
        "ARO_name",
        "ARO_accession",
        "model_type",
        "cut_off",
        "best_hit_bitscore",
        "pass_bitscore",
        "percent_identity",
        "drug_classes",
        "resistance_mechanisms",
        "amr_gene_families",
    ]
    writer = csv.DictWriter(out, fieldnames=fieldnames, delimiter="	", extrasaction="ignore")
    writer.writeheader()
    for row in hit_rows:
        writer.writerow(row)

with open(out_summary, "w", newline="") as out:
    writer = csv.writer(out, delimiter="\t")
    writer.writerow([
        "BinID",
        "AMR_hit_count",
        "unique_AMR_gene_count",
        "AMR_genes",
        "AMR_drug_classes",
        "AMR_resistance_mechanisms",
        "AMR_gene_families",
        "CARD_RGI_source_files",
    ])

    for binid in sorted(summary):
        rec = summary[binid]
        writer.writerow([
            binid,
            rec["hit_count"],
            len(rec["genes"]),
            ";".join(sorted(rec["genes"])),
            ";".join(sorted(rec["drug_classes"])),
            ";".join(sorted(rec["mechanisms"])),
            ";".join(sorted(rec["families"])),
            ";".join(sorted(rec["source_files"])),
        ])

with open(log_file, "a") as log:
    log.write(f"JSON files scanned: {len(json_files)}\n")
    log.write(f"MAGs with AMR hits: {len(summary)}\n")
    log.write(f"Summary written: {out_summary}\n")
    log.write(f"Hit table rows written: {len(hit_rows)}\n")
    log.write(f"Hit table written: {out_hits}\n")
PY

cat "$LOG_FILE"
echo "Done." | tee -a "$LOG_FILE"
echo "AMR summary table: $OUT_SUMMARY" | tee -a "$LOG_FILE"
echo "All RGI hits table: $OUT_HITS" | tee -a "$LOG_FILE"
