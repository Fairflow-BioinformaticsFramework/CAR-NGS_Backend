# Generalized WGS GATK Pipeline

This directory contains a generalized and reproducible Bash pipeline for short-read WGS preprocessing and germline short-variant discovery.

It was derived from a teaching workflow but rewritten to be more robust, configurable and species-independent.

## Files

- `config.sh`: all user-defined parameters.
- `wgs_gatk_pipeline.sh`: main pipeline.
- `README_generalized_pipeline.md`: usage notes.

## Main features

The pipeline:

1. Creates a standard project directory.
2. Downloads reads from SRA, or uses local FASTQ files.
3. Runs FastQC and MultiQC before trimming.
4. Optionally trims reads with Trim Galore.
5. Downloads or uses a local reference genome.
6. Checks whether the reference is already indexed.
7. Creates missing BWA, SAMtools and GATK indexes.
8. Aligns paired reads with BWA-MEM.
9. Produces coordinate-sorted and indexed BAM files.
10. Computes `samtools flagstat` alignment summaries.
11. Marks duplicates with GATK.
12. Optionally performs BQSR, if known variants are available.
13. Calls variants with GATK HaplotypeCaller in GVCF or VCF mode.
14. Writes a manifest with parameters and software versions.

## Basic usage

```bash
chmod +x wgs_gatk_pipeline.sh
bash wgs_gatk_pipeline.sh config.sh
```

For long runs:

```bash
nohup bash wgs_gatk_pipeline.sh config.sh > pipeline.log 2>&1 &
```

## Example 1: Human chromosome 13 tutorial

Edit `config.sh`:

```bash
PROJECT_DIR="$PWD/human_chr13_project"
INPUT_MODE="SRA"

REFERENCE_URL="https://ftp.ensembl.org/pub/current_fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.chromosome.13.fa.gz"
REFERENCE_FASTA="${REF_DIR}/reference.fa"

RUN_BQSR=true
KNOWN_VCF_URL="https://ftp.ensembl.org/pub/current_variation/vcf/homo_sapiens/homo_sapiens-chr13.vcf.gz"
KNOWN_VCF="${REF_DIR}/known_variants.vcf.gz"
```

Create:

```bash
mkdir -p human_chr13_project
nano human_chr13_project/accession.txt
```

with:

```text
ERR10219898
ERR10219899
ERR10219900
ERR10219901
```

Then run:

```bash
bash wgs_gatk_pipeline.sh config.sh
```

## Example 2: Drosophila genome

For Drosophila or other non-human organisms, BQSR is often not possible unless a reliable known-sites VCF is available.

Edit `config.sh`:

```bash
PROJECT_DIR="$PWD/drosophila_project"
INPUT_MODE="SRA"

REFERENCE_URL="https://ftp.ensembl.org/pub/current_fasta/drosophila_melanogaster/dna/Drosophila_melanogaster.BDGP6.46.dna.toplevel.fa.gz"
REFERENCE_FASTA="${REF_DIR}/reference.fa"

RUN_BQSR=false
EMIT_GVCF=true
```

Create an accession file:

```bash
mkdir -p drosophila_project
nano drosophila_project/accession.txt
```

## Example 3: Local FASTQ files

Create a tab-separated sample sheet:

```text
sample_id    R1    R2
sampleA      /absolute/path/sampleA_R1.fastq.gz    /absolute/path/sampleA_R2.fastq.gz
sampleB      /absolute/path/sampleB_R1.fastq.gz    /absolute/path/sampleB_R2.fastq.gz
```

Then set:

```bash
INPUT_MODE="LOCAL"
SAMPLE_SHEET="${PROJECT_DIR}/samples.tsv"
```

## Important scientific notes

### Why mark duplicates?

Duplicate reads can arise during PCR amplification or library preparation. If untreated, they may inflate apparent read support for an allele and bias variant calling. GATK preprocessing therefore includes duplicate marking before variant discovery.

### Why BQSR?

Base quality scores are central to variant calling because they indicate the probability that each base was incorrectly called. BQSR uses known polymorphic sites to model systematic sequencing errors and recalibrate quality scores. If reliable known variant sites are unavailable, BQSR should usually be disabled rather than run incorrectly.

### GVCF versus VCF

A VCF reports variant sites called in one or more samples. A GVCF additionally stores reference-confidence information across the genome, allowing multiple samples to be jointly genotyped later.

## Recommended outputs to report in a Methods section

- Reference genome name, version and source.
- Read accession numbers or FASTQ source.
- Software names and versions.
- Read trimming parameters.
- Alignment program and parameters.
- Duplicate handling strategy.
- Whether BQSR was performed and which known-sites VCF was used.
- HaplotypeCaller mode: GVCF or VCF.
- Variant filtering strategy, if variants are filtered downstream.


## Docker usage

See `README_DOCKER.md`.
