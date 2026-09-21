#!/bin/bash
set -euo pipefail

# Always use the config in THIS project
CONFIG_FILE="$(cd "$(dirname "$0")" && pwd)/config.sh"

# Load config to get ROOT and SCRIPTS_ROOT
source "$CONFIG_FILE"

# Central scripts location
SCRIPTS_ROOT="${SCRIPTS_ROOT:-$ROOT/scripts}"

# Peripheral setup scripts location
SETUP_ROOT="${SETUP_ROOT:-$ROOT/setup}"

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  echo "Usage: ./run.sh {verify|setup-user|trim|kraken2|kraken_summary|bracken_rank|assemble|maxbin|checkm|usable|map|gtdbtk|split|card|card_summary}" >&2
  exit 1
fi

case "$cmd" in
  verify)       	"$SETUP_ROOT/verify.sh" "$CONFIG_FILE" ;;
  setup-user)   	"$SETUP_ROOT/setup_user_envs.sh" "$CONFIG_FILE" ;;
  
  trim)      		"$SCRIPTS_ROOT/trim_all.sh" "$CONFIG_FILE" ;;
  
  kraken2)       	"$SCRIPTS_ROOT/run_kraken2.sh" "$CONFIG_FILE" ;;
  kraken_summary)	"$SCRIPTS_ROOT/run_kraken_summary.sh" "$CONFIG_FILE" ;;
  bracken_rank) "$SCRIPTS_ROOT/bracken_rank.sh" "$CONFIG_FILE" "${2:-}" ;;
  
  assemble)   		"$SCRIPTS_ROOT/assemble_all.sh" "$CONFIG_FILE" ;;
  maxbin)    		"$SCRIPTS_ROOT/run_maxbin2.sh" "$CONFIG_FILE" ;;
  checkm)    		"$SCRIPTS_ROOT/run_checkm_on_bins.sh" "$CONFIG_FILE" ;;
  usable)    		"$SCRIPTS_ROOT/filter_usable_mags.sh" "$CONFIG_FILE" ;;
  map)        		"$SCRIPTS_ROOT/run_map_prevalence.sh" "$CONFIG_FILE" ;;
  gtdbtk)     		"$SCRIPTS_ROOT/run_gtdbtk.sh" "$CONFIG_FILE" ;;
  split)      		"$SCRIPTS_ROOT/split_quality_join_taxa.sh" "$CONFIG_FILE" ;;
  card)       		"$SCRIPTS_ROOT/run_card_rgi.sh" "$CONFIG_FILE" ;;
  card_summary) 	"$SCRIPTS_ROOT/run_card_summary.sh" "$CONFIG_FILE" ;;
  *)
    echo "Unknown step: $cmd" >&2
    echo "Usage: ./run.sh {verify|setup-user|trim|kraken2|kraken_summary|bracken_rank|assemble|maxbin|checkm|usable|map|gtdbtk|split|card|card_summary}" >&2
    exit 1
    ;;
esac
