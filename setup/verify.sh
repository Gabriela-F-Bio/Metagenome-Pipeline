#!/bin/bash
set -euo pipefail

# Optional project config passed by run.sh
CONFIG_FILE="${1:-}"

if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE" >&2
    exit 1
  fi
  source "$CONFIG_FILE"
fi

TOOLS_ROOT="${TOOLS_ROOT:-$ROOT/tools}"

############## LOCATE MICROMAMBA ##############

if [[ -n "${MICROMAMBA_BIN:-}" && -x "$MICROMAMBA_BIN" ]]; then
  MAMBA_EXE="$MICROMAMBA_BIN"
elif [[ -x "$TOOLS_ROOT/micromamba/micromamba" ]]; then
  MAMBA_EXE="$TOOLS_ROOT/micromamba/micromamba"
elif [[ -x "$TOOLS_ROOT/micromamba" && ! -d "$TOOLS_ROOT/micromamba" ]]; then
  MAMBA_EXE="$TOOLS_ROOT/micromamba"
else
  MAMBA_EXE="$(command -v micromamba || true)"
fi

if [[ -z "${MAMBA_EXE:-}" || ! -x "$MAMBA_EXE" ]]; then
  echo "ERROR: micromamba executable not found." >&2
  exit 1
fi

############## UPDATE PATH ##############

export PATH="$(dirname "$MAMBA_EXE"):$TOOLS_ROOT/bbtools:$TOOLS_ROOT/MEGAHIT-1.2.9-Linux-x86_64-static/bin:$PATH"

############## REPORT PATHS ##############

echo "=== Metagenome pipeline verification ==="
echo
echo "TOOLS_ROOT:  $TOOLS_ROOT"
echo "micromamba:  $MAMBA_EXE"
echo "bbduk.sh:    $(command -v bbduk.sh || true)"
echo "megahit:     $(command -v megahit || true)"
echo "java:        $(command -v java || true)"
echo

############## CHECK STANDALONE TOOLS ##############

command -v bbduk.sh >/dev/null || {
  echo "ERROR: bbduk.sh not found." >&2
  exit 1
}

command -v megahit >/dev/null || {
  echo "ERROR: MEGAHIT not found." >&2
  exit 1
}

command -v java >/dev/null || {
  echo "ERROR: Java not found." >&2
  exit 1
}

############## ENVIRONMENT HELPER ##############

# Prefer shared path-based environments created by bootstrap.sh.
# Fall back to named environments created by setup_user_envs.sh.
run_in_env() {
  local env_name="$1"
  shift

  if [[ -d "$TOOLS_ROOT/envs/$env_name" ]]; then
    "$MAMBA_EXE" run -p "$TOOLS_ROOT/envs/$env_name" "$@"
  else
    "$MAMBA_EXE" run -n "$env_name" "$@"
  fi
}

############## VERIFY CORE ENVIRONMENTS ##############

echo "Checking MaxBin2..."
run_in_env maxbin_env run_MaxBin.pl -v >/dev/null

echo "Checking CheckM..."
run_in_env checkm_env checkm -h >/dev/null

echo "Checking GTDB-Tk..."
run_in_env gtdbtk_env gtdbtk --help >/dev/null

############## VERIFY OPTIONAL ENVIRONMENTS ##############

echo "Checking Bowtie2..."
run_in_env mapping_env bowtie2 --version >/dev/null

echo "Checking SAMtools..."
run_in_env mapping_env samtools --version >/dev/null

echo "Checking CoverM..."
run_in_env mapping_env coverm --help >/dev/null


############## VERIFY CARD / RGI ##############

echo "Checking CARD/RGI..."
run_in_env rgi_env rgi --help >/dev/null

EXPECTED_CARD_VERSION="${CARD_VERSION:-3.2.7}"

INSTALLED_CARD_VERSION=$(
  run_in_env rgi_env rgi database --version 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
  | head -n 1
)

if [[ -z "$INSTALLED_CARD_VERSION" ]]; then
  echo "ERROR: Could not determine the installed CARD database version."
  echo "Expected CARD version: $EXPECTED_CARD_VERSION"
  echo
  echo "Check manually with:"
  echo "  rgi database --version"
  exit 1
fi

if [[ "$INSTALLED_CARD_VERSION" != "$EXPECTED_CARD_VERSION" ]]; then
  echo "ERROR: CARD database version mismatch."
  echo "Expected: $EXPECTED_CARD_VERSION"
  echo "Found:    $INSTALLED_CARD_VERSION"
  exit 1
fi

echo "CARD database version verified: $INSTALLED_CARD_VERSION"

############## VERIFY KRAKEN2 / BRACKEN ##############

echo "Checking Kraken2..."
run_in_env kraken2_env kraken2 --version >/dev/null

echo "Checking Kraken2-build..."
run_in_env kraken2_env kraken2-build --help >/dev/null

echo "Checking Bracken..."
run_in_env kraken2_env bracken -v >/dev/null 2>&1 || \
  run_in_env kraken2_env bracken --help >/dev/null

echo "Checking Bracken-build..."
run_in_env kraken2_env bracken-build --help >/dev/null

############## VERIFY GTDB-TK DATABASE ##############

if [[ -z "${GTDBTK_DATA_PATH:-}" ]]; then
  echo "ERROR: GTDBTK_DATA_PATH is not set."
  echo "Set it in config.sh, for example:"
  echo "  export GTDBTK_DATA_PATH=\"$TOOLS_ROOT/gtdbtk/release226\""
  exit 1
fi

if [[ ! -d "$GTDBTK_DATA_PATH" ]]; then
  echo "ERROR: GTDBTK_DATA_PATH does not exist:"
  echo "  $GTDBTK_DATA_PATH"
  exit 1
fi

if [[ -z "$(find "$GTDBTK_DATA_PATH" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "ERROR: GTDBTK_DATA_PATH exists but is empty:"
  echo "  $GTDBTK_DATA_PATH"
  exit 1
fi

echo "GTDB-Tk reference data found"
echo "  $GTDBTK_DATA_PATH"

############## VERIFY KRAKEN2 DATABASE ##############

KRAKEN2_DB="${KRAKEN2_DB:-$TOOLS_ROOT/kraken2_db_prebuilt}"

if [[ ! -f "$KRAKEN2_DB/hash.k2d" || \
      ! -f "$KRAKEN2_DB/opts.k2d" || \
      ! -f "$KRAKEN2_DB/taxo.k2d" ]]; then
  echo "WARNING: Kraken2 environment is installed, but database files are not complete:"
  echo "  $KRAKEN2_DB"
  echo "Expected: hash.k2d, opts.k2d, taxo.k2d"
else
  echo "Kraken2 prebuilt database found"
fi

############## VERIFY BRACKEN SUPPORT FILES ##############

BRACKEN_DISTRIB="$KRAKEN2_DB/database${BRACKEN_READ_LEN}mers.kmer_distrib"

if [[ ! -f "$BRACKEN_DISTRIB" ]]; then
  echo "WARNING: Bracken support file is not complete for read length ${BRACKEN_READ_LEN}:"
  echo "  $BRACKEN_DISTRIB"
  echo "Kraken2 can run, but Bracken abundance estimation will be skipped."
else
  echo "Bracken support files found (${BRACKEN_READ_LEN} bp)"
fi

############## SUMMARY ##############

echo
echo "BBTools found"
echo "MEGAHIT found"
echo "Java found"
echo "MaxBin2 environment found"
echo "CheckM environment found"
echo "GTDB-Tk environment found"
echo "Mapping environment found"
echo "CARD/RGI environment found"
echo "CARD database v${EXPECTED_CARD_VERSION} verified"
echo "Kraken2/Bracken environment found"
echo "GTDB-Tk database found"
echo
echo "All core tool checks passed."
