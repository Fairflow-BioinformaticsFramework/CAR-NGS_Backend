#!/usr/bin/env bash

# ============================================================
# config.sh
# General configuration file for a reproducible WGS short-variant
# discovery pipeline based on BWA, SAMtools and GATK.
#
# Modify this file only. The main pipeline script reads variables
# from here.
# ============================================================

# -----------------------------
# Project structure
# -----------------------------
PROJECT_DIR="${PROJECT_DIR:-$PWD/wgs_project}"

RAW_DIR="${PROJECT_DIR}/01_raw_fastq"
QC_RAW_DIR="${PROJECT_DIR}/02_qc_raw"
TRIM_DIR="${PROJECT_DIR}/03_trimmed_fastq"
QC_TRIM_DIR="${PROJECT_DIR}/04_qc_trimmed"
REF_DIR="${PROJECT_DIR}/05_reference"
BAM_DIR="${PROJECT_DIR}/06_bam"
GATK_DIR="${PROJECT_DIR}/07_gatk"
METRICS_DIR="${PROJECT_DIR}/08_metrics"
LOG_DIR="${PROJECT_DIR}/logs"

# -----------------------------
# Sample input
# -----------------------------
# Option A: SRA accession file, one accession per line.
ACCESSION_FILE="${PROJECT_DIR}/accession.txt"

# Option B: sample sheet for already downloaded FASTQ files.
# Tab-separated file with columns:
# sample_id    R1    R2
# Example:
# sampleA      /path/sampleA_R1.fastq.gz      /path/sampleA_R2.fastq.gz
SAMPLE_SHEET="${PROJECT_DIR}/samples.tsv"

# Choose one:
#   SRA      = download reads from SRA using fasterq-dump or fastq-dump
#   LOCAL    = use existing FASTQ files from SAMPLE_SHEET
INPUT_MODE="${INPUT_MODE:-SRA}"

# -----------------------------
# Reference genome
# -----------------------------
# Species-independent design:
# provide either a local reference FASTA or a URL to download it.
#
# Examples:
# Human chr13:
# REFERENCE_URL="https://ftp.ensembl.org/pub/current_fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.chromosome.13.fa.gz"
#
# Drosophila melanogaster genome:
# REFERENCE_URL="https://ftp.ensembl.org/pub/current_fasta/drosophila_melanogaster/dna/Drosophila_melanogaster.BDGP6.46.dna.toplevel.fa.gz"

REFERENCE_URL="${REFERENCE_URL:-}"
REFERENCE_FASTA="${REFERENCE_FASTA:-${REF_DIR}/reference.fa}"

# Optional annotation file for IGV/reporting only.
ANNOTATION_GFF_URL="${ANNOTATION_GFF_URL:-}"
ANNOTATION_GFF="${ANNOTATION_GFF:-${REF_DIR}/annotation.gff3}"

# -----------------------------
# Known variants for BQSR
# -----------------------------
# BQSR requires known variant sites.
# For model organisms without reliable known variants, set:
# RUN_BQSR=false
#
# If RUN_BQSR=true, provide KNOWN_VCF or KNOWN_VCF_URL.
RUN_BQSR="${RUN_BQSR:-true}"
KNOWN_VCF_URL="${KNOWN_VCF_URL:-}"
KNOWN_VCF="${KNOWN_VCF:-${REF_DIR}/known_variants.vcf.gz}"

# -----------------------------
# Analysis options
# -----------------------------
THREADS="${THREADS:-4}"
JAVA_MEM="${JAVA_MEM:-4g}"

# Use trim_galore by default.
RUN_TRIMMING="${RUN_TRIMMING:-true}"

# Remove duplicates or only mark them?
# GATK Best Practices generally mark duplicates;
# removing duplicates may be undesirable for some analyses.
REMOVE_DUPLICATES="${REMOVE_DUPLICATES:-false}"

# HaplotypeCaller output mode:
#   true  = produce GVCF, useful for joint genotyping
#   false = produce ordinary VCF
EMIT_GVCF="${EMIT_GVCF:-true}"

# Optional intervals file or region, e.g. "chr13" or intervals.list.
INTERVALS="${INTERVALS:-}"

# SRA download method:
#   fasterq-dump is preferred if available; gzip is applied afterwards.
#   fastq-dump is slower but directly supports --gzip.
SRA_TOOL="${SRA_TOOL:-fasterq-dump}"
