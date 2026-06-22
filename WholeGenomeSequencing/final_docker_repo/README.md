# Refined HackMD WGS Pipeline

This repository contains a polished Bash implementation of the HackMD tutorial:

**WGS pipeline using GATK best practices**

The goal is not to replace the original tutorial with a workflow manager, but to make the same workflow more reproducible, general and GitHub-ready.

## What this pipeline does

The script follows the same conceptual order as the tutorial:

1. Download reads from SRA
2. Run FastQC and MultiQC on raw reads
3. Trim reads with Trim Galore
4. Run FastQC and MultiQC after trimming
5. Download or use a reference genome
6. Index the reference genome with:
   - `bwa index`
   - `samtools faidx`
   - `gatk CreateSequenceDictionary`
7. Align reads with `bwa mem`
8. Produce sorted and indexed BAM files
9. Compute alignment statistics with `samtools flagstat`
10. Mark duplicates with GATK
11. Optionally run BQSR
12. Run HaplotypeCaller
13. Optionally run joint genotyping
14. Optionally apply simple hard filters

## Minimal use

```bash
chmod +x hackmd_wgs_pipeline_refined.sh
bash hackmd_wgs_pipeline_refined.sh
```

By default, the script uses the same human chromosome 13 example used in the tutorial.

## Required accession file

Create:

```bash
mkdir -p wgs_project
nano wgs_project/accession.txt
```

Example:

```text
ERR10219898
ERR10219899
ERR10219900
ERR10219901
```

## Human chromosome 13 example

The default settings use:

```bash
REFERENCE_URL="https://ftp.ensembl.org/pub/current_fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.chromosome.13.fa.gz"
KNOWN_VCF_URL="https://ftp.ensembl.org/pub/current_variation/vcf/homo_sapiens/homo_sapiens-chr13.vcf.gz"
RUN_BQSR=true
```

## Drosophila example

For Drosophila:

```bash
PROJECT_DIR="$PWD/drosophila_project" \
REFERENCE_URL="https://ftp.ensembl.org/pub/current_fasta/drosophila_melanogaster/dna/Drosophila_melanogaster.BDGP6.46.dna.toplevel.fa.gz" \
RUN_BQSR=false \
bash hackmd_wgs_pipeline_refined.sh
```

BQSR is disabled here because BQSR requires reliable known variant sites. If such a VCF is available, set `RUN_BQSR=true` and provide `KNOWN_VCF` or `KNOWN_VCF_URL`.

## Using local FASTQ files

Create a tab-separated file:

```text
sample_id    R1    R2
sampleA      /path/sampleA_R1.fastq.gz    /path/sampleA_R2.fastq.gz
sampleB      /path/sampleB_R1.fastq.gz    /path/sampleB_R2.fastq.gz
```

Then run:

```bash
INPUT_MODE=LOCAL \
SAMPLE_SHEET=/path/samples.tsv \
bash hackmd_wgs_pipeline_refined.sh
```

## Important corrections compared with the didactic version

The tutorial is designed for teaching. This refined version adds:

- error handling with `set -euo pipefail`
- checks for required software
- checks for existing output files before rerunning steps
- no unnecessary SAM intermediate files
- read-group information during alignment
- sorted BAM output directly from BWA
- software version tracking
- a run manifest
- optional BQSR
- optional joint genotyping
- optional hard filtering
- generalized reference genome and known-sites input

## Notes on duplicate handling

The original tutorial uses:

```bash
--REMOVE_DUPLICATES true
```

For most germline variant discovery workflows it is usually preferable to mark duplicates rather than remove them:

```bash
--REMOVE_DUPLICATES false
```

This refined pipeline therefore defaults to:

```bash
REMOVE_DUPLICATES=false
```

## Notes on BQSR

BQSR should only be used when a suitable known-sites VCF is available. For human data this is generally possible. For non-model organisms, disabling BQSR is often safer than using an inappropriate known-sites file.

## Notes on filtering

The hard-filtering thresholds included here are common starting values, not universal truths. They should be justified, inspected and adapted to the organism, sequencing design, coverage and downstream goals.

## Suggested repository structure

```text
.
├── hackmd_wgs_pipeline_refined.sh
├── README.md
├── LICENSE
├── CITATION.cff
└── examples/
    ├── accession_human_chr13.txt
    └── samples.tsv
```

## Suggested citation text

A refined Bash implementation of a WGS preprocessing and GATK germline variant discovery workflow was used. The workflow includes read quality control, trimming, BWA-MEM alignment, duplicate marking, optional base quality score recalibration, GATK HaplotypeCaller, optional joint genotyping and hard filtering.
