#!/bin/bash
set -euo pipefail

echo "=== Per-user micromamba environment setup ==="

# 1) Ensure micromamba is available
if ! command -v micromamba &>/dev/null; then
  echo "ERROR: micromamba not found in PATH."
  echo "Run setup/bootstrap.sh first."
  exit 1
fi

# 2) Helper function: create env if missing
create_env() {
  local env_name="$1"
  shift
  local pkgs=("$@")

  if micromamba env list | awk '{print $1}' | grep -qx "$env_name"; then
    echo "✔ Environment '$env_name' already exists (skipping)"
  else
    echo "→ Creating environment '$env_name'"
    micromamba create -y -n "$env_name" -c conda-forge -c bioconda "${pkgs[@]}"
  fi
}

# 3) Create per-user environments
create_env maxbin_env maxbin2=2.2.7 perl=5.32.1
create_env checkm_env checkm-genome=1.2.4
create_env gtdbtk_env gtdbtk=2.6.1
create_env mapping_env bowtie2=2.5.5 samtools=1.23.1 coverm=0.7.0
create_env rgi_env rgi=6.0.5
create_env kraken2_env kraken2=2.17.1 bracken=3.1

echo
echo "=== Done ==="
echo "You can now run the pipeline normally:"
echo "  ./run.sh kraken2"
echo "  ./run.sh maxbin"
echo "  ./run.sh checkm"
echo "  ./run.sh map"
echo "  ./run.sh gtdbtk"
echo "  ./run.sh card"