#!/bin/bash
set -euo pipefail

# Shared root is the parent directory of setup/
ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TOOLS_ROOT="${TOOLS_ROOT:-$ROOT/tools}"
GTDB_RELEASE="${GTDB_RELEASE:-release226}"

mkdir -p "$TOOLS_ROOT"
cd "$TOOLS_ROOT"

echo "Tools root: $TOOLS_ROOT"

# 1) micromamba
############## LOCATE / INSTALL MICROMAMBA ##############

if [[ -x "$TOOLS_ROOT/micromamba/micromamba" ]]; then
  MAMBA_EXE="$TOOLS_ROOT/micromamba/micromamba"

elif [[ -x "$TOOLS_ROOT/micromamba" && ! -d "$TOOLS_ROOT/micromamba" ]]; then
  MAMBA_EXE="$TOOLS_ROOT/micromamba"

else
  echo "Installing micromamba..."

  mkdir -p "$TOOLS_ROOT/micromamba"

  curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
    | tar -xvj bin/micromamba

  mv bin/micromamba "$TOOLS_ROOT/micromamba/micromamba"
  rm -rf bin

  MAMBA_EXE="$TOOLS_ROOT/micromamba/micromamba"
fi

export PATH="$(dirname "$MAMBA_EXE"):$PATH"

# 2) BBTools
BBTOOLS_VERSION="39.33"
if [[ ! -d "$TOOLS_ROOT/bbtools" ]]; then
  echo "Installing BBTools..."
  curl -L -o bbtools.tar.gz https://sourceforge.net/projects/bbmap/files/BBMap_${BBTOOLS_VERSION}.tar.gz/download
  tar -xzf bbtools.tar.gz
  rm bbtools.tar.gz
  # folder name is BBMap/; normalize to bbtools
  mv BBMap "$TOOLS_ROOT/bbtools"
fi

# 3) MEGAHIT
if [[ ! -d "$TOOLS_ROOT/MEGAHIT-1.2.9-Linux-x86_64-static" ]]; then
  echo "Installing MEGAHIT..."
  curl -L -o megahit.tar.gz https://github.com/voutcn/megahit/releases/download/v1.2.9/MEGAHIT-1.2.9-Linux-x86_64-static.tar.gz
  tar -xzf megahit.tar.gz
  rm megahit.tar.gz
fi

# 4) Java (optional: system java usually works)
# If VM already has java, skip. Otherwise install a JRE/JDK by OS package manager.
if ! command -v java &>/dev/null; then
  echo "WARNING: java not found. Install system Java (recommended) or place a JDK under $TOOLS_ROOT/java."
fi

# 5) Create envs
mkdir -p "$TOOLS_ROOT/envs"

if [[ ! -d "$TOOLS_ROOT/envs/maxbin_env" ]]; then
    echo "Creating maxbin_env..."
    "$MAMBA_EXE" create -y \
    -p "$TOOLS_ROOT/envs/maxbin_env" \
    -c conda-forge -c bioconda \
    maxbin2=2.2.7 \
    perl=5.32.1
else
    echo "maxbin_env already exists"
fi

if [[ ! -d "$TOOLS_ROOT/envs/checkm_env" ]]; then
	echo "Creating checkm_env..."
	"$MAMBA_EXE" create -y \
    -p "$TOOLS_ROOT/envs/checkm_env" \
    -c conda-forge -c bioconda \
    checkm-genome=1.2.4
else
    echo "checkm_env already exists"
fi
     
if [[ ! -d "$TOOLS_ROOT/envs/mapping_env" ]]; then
	echo "Creating mapping_env..."
	"$MAMBA_EXE" create -y \
    -p "$TOOLS_ROOT/envs/mapping_env" \
    -c conda-forge -c bioconda \
    bowtie2=2.5.5 \
    samtools=1.23.1 \
    coverm=0.7.0
else
    echo "mapping_env already exists"
fi

if [[ ! -d "$TOOLS_ROOT/envs/gtdbtk_env" ]]; then
	echo "Creating gtdbtk_env..."
	"$MAMBA_EXE" create -y \
    -p "$TOOLS_ROOT/envs/gtdbtk_env" \
    -c conda-forge -c bioconda \
    gtdbtk=2.6.1
else
    echo "gtdbtk_env already exists"
fi

if [[ ! -d "$TOOLS_ROOT/envs/rgi_env" ]]; then
	echo "Creating rgi_env..."
	"$MAMBA_EXE" create -y \
     -p "$TOOLS_ROOT/envs/rgi_env" \
     -c conda-forge -c bioconda \
     rgi=6.0.5
else
    echo "rgi_env already exists"
fi

if [[ ! -d "$TOOLS_ROOT/envs/kraken2_env" ]]; then
	echo "Creating kraken2_env..."
	"$MAMBA_EXE" create -y \
	-p "$TOOLS_ROOT/envs/kraken2_env" \
	-c conda-forge -c bioconda \
	kraken2=2.17.1 \
	bracken=3.1
else
    echo "kraken2_env already exists"
fi

# 6) GTDB-Tk reference data
mkdir -p "$TOOLS_ROOT/gtdbtk"

if [[ ! -d "$TOOLS_ROOT/gtdbtk/$GTDB_RELEASE" ]]; then
  echo
  echo "NOTE: GTDB-Tk reference data ($GTDB_RELEASE) are not installed."
  echo "Follow the R226 installation instructions in README.md."
  echo "Expected location:"
  echo "  $TOOLS_ROOT/gtdbtk/$GTDB_RELEASE"
fi

# 7) CARD database
CARD_VERSION="${CARD_VERSION:-3.2.7}"

echo
echo "Checking CARD database..."

INSTALLED_CARD_VERSION=$(
  "$MAMBA_EXE" run -p "$TOOLS_ROOT/envs/rgi_env" \
    rgi database --version 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
  | head -n 1 || true
)

if [[ -z "$INSTALLED_CARD_VERSION" ]]; then
  echo "CARD database is not currently loaded."
  echo "This pipeline requires CARD v${CARD_VERSION}."
  echo "Install/load CARD v${CARD_VERSION} as described in README.md."
elif [[ "$INSTALLED_CARD_VERSION" != "$CARD_VERSION" ]]; then
  echo "WARNING: CARD database version mismatch."
  echo "  Expected: $CARD_VERSION"
  echo "  Found:    $INSTALLED_CARD_VERSION"
  echo "Install/load CARD v${CARD_VERSION} before running the RGI step."
else
  echo "CARD database v${CARD_VERSION} found."
fi

# 8) Kraken2 database location
mkdir -p "$TOOLS_ROOT/kraken2_db_prebuilt"

if [[ ! -f "$TOOLS_ROOT/kraken2_db_prebuilt/hash.k2d" || \
      ! -f "$TOOLS_ROOT/kraken2_db_prebuilt/opts.k2d" || \
      ! -f "$TOOLS_ROOT/kraken2_db_prebuilt/taxo.k2d" ]]; then
  echo "Kraken2 prebuilt database not complete at:"
  echo "  $TOOLS_ROOT/kraken2_db_prebuilt"
  echo "Download and unpack a compatible prebuilt Kraken2/Bracken database as described in README.md."
else
  echo "Kraken2 database found at: $TOOLS_ROOT/kraken2_db_prebuilt"
fi

BRACKEN_DISTRIB="$TOOLS_ROOT/kraken2_db_prebuilt/database150mers.kmer_distrib"

if [[ ! -f "$BRACKEN_DISTRIB" ]]; then
  echo "Bracken support file not found for 150 bp reads."
else
  echo "Bracken support file found: $BRACKEN_DISTRIB"
fi

echo
echo "Bootstrap complete."
echo "Next: Run verify."