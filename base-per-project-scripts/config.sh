#!/bin/bash
#
# config.sh - edit ONLY these variables for a new user/project/VM

############## BASIC PROJECT INFO ##############

# Root of the cloned Metagenome-pipeline repository
ROOT="${ROOT:-/path/to/Metagenome-pipeline}"

# Your folder name (replace with your actual one once)
USER_ID="${USER_ID:-firstnamelastinitial}"

# Project name (replace with your actual one once)
PROJECT="${PROJECT:-projectname}"

# Base project directory
BASE="$ROOT/$USER_ID/$PROJECT"

############## STANDARD PROJECT SUBFOLDERS ##############

RAW_DIR="$BASE/1raw"
TRIMMED_DIR="$BASE/2trimmed"
MEGAHIT_DIR="$BASE/3megahit"
MAXBIN_DIR="$BASE/4maxbin2"
CHECKM_BINS_DIR="$BASE/5checkm_bins"
CHECKM_DIR="$BASE/6checkm"
USABLE_MAG_DIR="$BASE/7usable_mags"

HQ_MAG_DIR="$BASE/7high_quality_mags"
NEAR_HQ_MAG_DIR="$BASE/7near_high_mags"
NEAR_MED_MAG_DIR="$BASE/7near_medium_mags"
MED_MAG_DIR="$BASE/7medium_mags"

GTDBTK_DIR="$BASE/8gtdbtk"
CARD_RGI_DIR="$BASE/9card_rgi"
MAP_DIR="$BASE/10mapping"

BOWTIE2_DIR="$MAP_DIR/bowtie2"
COVERAGE_DIR="$MAP_DIR/coverage"
PREVALENCE_DIR="$MAP_DIR/prevalence"

KRAKEN2_DIR="$BASE/11kraken2"

LOG_DIR="$BASE/logs"

############## MAP PREVALENCE PATHS AND PARAMETERS ##############

# Combined MAG reference FASTA
REF_FASTA="$MAP_DIR/all_mags.fa"

# Bowtie2 index prefix
BOWTIE2_INDEX_PREFIX="$BOWTIE2_DIR/usable_mags_idx"

# Detection thresholds
MIN_BREADTH="0.30"
MIN_MEAN_COV="1.0"
THREADS="8"

############## MICROMAMBA ENV NAMES ##############

MAXBIN_ENV_NAME="maxbin_env"
CHECKM_ENV_NAME="checkm_env"
GTDBTK_ENV_NAME="gtdbtk_env"
RGI_ENV_NAME="rgi_env"
BOWTIE2_ENV_NAME="mapping_env"
KRAKEN2_ENV_NAME="kraken2_env"

############## SCRIPTS (shared across projects) ##############

SCRIPTS_ROOT="$ROOT/scripts"

############## SETUP (shared across projects) ##############

SETUP_ROOT="$ROOT/setup"

############## TOOLS (shared across projects) ##############

TOOLS_ROOT="$ROOT/tools"

# Core tools
BBTOOLS_BIN="$TOOLS_ROOT/bbtools"
MEGAHIT_BIN="$TOOLS_ROOT/MEGAHIT-1.2.9-Linux-x86_64-static/bin"
JAVA_BIN="$TOOLS_ROOT/java/bin"
LOCAL_BIN="$TOOLS_ROOT/bin"

# Micromamba executable. On this VM it is inside a micromamba/ folder.
if [[ -x "$TOOLS_ROOT/micromamba/micromamba" ]]; then
  MICROMAMBA_BIN="$TOOLS_ROOT/micromamba/micromamba"
elif [[ -x "$TOOLS_ROOT/micromamba" ]]; then
  MICROMAMBA_BIN="$TOOLS_ROOT/micromamba"
else
  MICROMAMBA_BIN="micromamba"
fi

export GTDBTK_DATA_PATH="$TOOLS_ROOT/gtdbtk/release226"

############## CARD / RGI PARAMETERS ##############

CARD_VERSION="3.2.7"

############## KRAKEN2 / BRACKEN PARAMETERS ##############

KRAKEN2_DB="$TOOLS_ROOT/kraken2_db_prebuilt"
KRAKEN2_THREADS="10"
KRAKEN2_CONFIDENCE="0.10"
BRACKEN_READ_LEN="150"
BRACKEN_LEVEL="S"

############## UPDATE PATH ##############

export PATH="$BBTOOLS_BIN:$MEGAHIT_BIN:$JAVA_BIN:$LOCAL_BIN:$(dirname "$MICROMAMBA_BIN"):$PATH"
