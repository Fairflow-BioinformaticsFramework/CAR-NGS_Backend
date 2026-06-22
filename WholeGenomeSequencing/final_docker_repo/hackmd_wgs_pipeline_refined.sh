#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# hackmd_wgs_pipeline_refined.sh
#
# Refined and generalized version of the HackMD tutorial:
# "WGS pipeline using GATK best practices".
#
# This script keeps the same conceptual structure as the tutorial:
#   1. SRA download
#   2. raw read QC
#   3. trimming
#   4. post-trimming QC
#   5. reference download/indexing
#   6. BWA-MEM alignment
#   7. BAM sorting/indexing
#   8. GATK MarkDuplicates
#   9. optional BQSR
#  10. HaplotypeCaller
#  11. optional joint genotyping
#  12. optional hard filtering
#
# The script is intentionally written in Bash, not Snakemake/Nextflow,
# because it is meant to be a polished version of the original tutorial.
# ============================================================

# -----------------------------
# User-editable parameters
# -----------------------------

PROJECT_DIR="${PROJECT_DIR:-$PWD/wgs_project}"
ACCESSION_FILE="${ACCESSION_FILE:-$PROJECT_DIR/accession.txt}"

THREADS="${THREADS:-4}"
JAVA_MEM="${JAVA_MEM:-4g}"

# Input mode:
#   SRA   = download using SRA Toolkit
#   LOCAL = use existing paired FASTQ files listed in samples.tsv
INPUT_MODE="${INPUT_MODE:-SRA}"
SAMPLE_SHEET="${SAMPLE_SHEET:-$PROJECT_DIR/samples.tsv}"

# Reference genome:
# Provide either REFERENCE_URL or an existing REFERENCE_FASTA.
REFERENCE_URL="${REFERENCE_URL:-https://ftp.ensembl.org/pub/current_fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.chromosome.13.fa.gz}"
REFERENCE_FASTA="${REFERENCE_FASTA:-$PROJECT_DIR/reference/reference.fa}"

# Known variants for BQSR.
# BQSR requires reliable known-sites.
# For non-model organisms, set RUN_BQSR=false unless a trusted known-sites VCF exists.
RUN_BQSR="${RUN_BQSR:-true}"
KNOWN_VCF_URL="${KNOWN_VCF_URL:-https://ftp.ensembl.org/pub/current_variation/vcf/homo_sapiens/homo_sapiens-chr13.vcf.gz}"
KNOWN_VCF="${KNOWN_VCF:-$PROJECT_DIR/reference/known_variants.vcf.gz}"

# HaplotypeCaller output:
# true  = GVCF mode, recommended for multiple samples and joint genotyping
# false = ordinary per-sample VCF
EMIT_GVCF="${EMIT_GVCF:-true}"

# Joint genotyping:
# requires EMIT_GVCF=true and multiple samples.
RUN_JOINT_GENOTYPING="${RUN_JOINT_GENOTYPING:-true}"

# Variant filtering:
# This script implements simple hard filtering.
# Thresholds are examples and should be justified for the dataset.
RUN_HARD_FILTERING="${RUN_HARD_FILTERING:-true}"

# Duplicate handling:
# GATK normally marks duplicates. Removing duplicates is not usually recommended
# for germline variant discovery.
REMOVE_DUPLICATES="${REMOVE_DUPLICATES:-false}"

# Optional region/intervals, for example "13" or "chr13" or a BED/interval list.
INTERVALS="${INTERVALS:-}"

# SRA tool:
# fasterq-dump is preferred when available.
SRA_TOOL="${SRA_TOOL:-fasterq-dump}"

# -----------------------------
# Directory structure
# -----------------------------

RAW_DIR="$PROJECT_DIR/01_fastq_raw"
QC_RAW_DIR="$PROJECT_DIR/02_fastqc_raw"
TRIM_DIR="$PROJECT_DIR/03_fastq_trimmed"
QC_TRIM_DIR="$PROJECT_DIR/04_fastqc_trimmed"
REF_DIR="$PROJECT_DIR/reference"
BAM_DIR="$PROJECT_DIR/05_bam"
GATK_DIR="$PROJECT_DIR/06_gatk"
VCF_DIR="$PROJECT_DIR/07_vcf"
METRICS_DIR="$PROJECT_DIR/metrics"
LOG_DIR="$PROJECT_DIR/logs"

# -----------------------------
# Utility functions
# -----------------------------

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

log() {
    echo "[$(timestamp)] $*"
}

die() {
    echo "[$(timestamp)] ERROR: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

mkdirs() {
    mkdir -p "$RAW_DIR" "$QC_RAW_DIR" "$TRIM_DIR" "$QC_TRIM_DIR" \
             "$REF_DIR" "$BAM_DIR" "$GATK_DIR" "$VCF_DIR" \
             "$METRICS_DIR" "$LOG_DIR"
}

check_commands() {
    log "Checking software..."

    require_command bwa
    require_command samtools
    require_command gatk
    require_command fastqc
    require_command multiqc
    require_command trim_galore
    require_command wget

    if [[ "$INPUT_MODE" == "SRA" ]]; then
        require_command "$SRA_TOOL"
        if [[ "$SRA_TOOL" == "fasterq-dump" ]]; then
            require_command gzip
        fi
    fi
}

write_versions() {
    local versions="$PROJECT_DIR/software_versions.txt"

    {
        echo "Run date: $(timestamp)"
        echo
        echo "bwa:"
        bwa 2>&1 | head -n 3 || true
        echo
        echo "samtools:"
        samtools --version | head -n 2 || true
        echo
        echo "gatk:"
        gatk --version 2>&1 || true
        echo
        echo "fastqc:"
        fastqc --version 2>&1 || true
        echo
        echo "multiqc:"
        multiqc --version 2>&1 || true
        echo
        echo "trim_galore:"
        trim_galore --version 2>&1 | head -n 3 || true
        echo
        echo "sra tool:"
        if command -v "$SRA_TOOL" >/dev/null 2>&1; then
            "$SRA_TOOL" --version 2>&1 | head -n 3 || true
        fi
    } > "$versions"
}

# -----------------------------
# Step 1: input reads
# -----------------------------

download_sra_reads() {
    [[ "$INPUT_MODE" == "SRA" ]] || return

    [[ -f "$ACCESSION_FILE" ]] || die "Missing accession file: $ACCESSION_FILE"

    log "Downloading reads from SRA..."

    while read -r sample; do
        [[ -z "$sample" || "$sample" =~ ^# ]] && continue

        local r1="$RAW_DIR/${sample}_1.fastq.gz"
        local r2="$RAW_DIR/${sample}_2.fastq.gz"

        if [[ -f "$r1" && -f "$r2" ]]; then
            log "$sample: raw FASTQ already present."
            continue
        fi

        log "$sample: downloading..."

        if [[ "$SRA_TOOL" == "fasterq-dump" ]]; then
            fasterq-dump --split-files --threads "$THREADS" --outdir "$RAW_DIR" "$sample"
            gzip -f "$RAW_DIR/${sample}"_*.fastq
        else
            fastq-dump --gzip --split-3 --outdir "$RAW_DIR" "$sample"
        fi

    done < "$ACCESSION_FILE"
}

create_sample_sheet_from_sra() {
    [[ "$INPUT_MODE" == "SRA" ]] || return

    log "Creating sample sheet from SRA accessions..."

    {
        echo -e "sample_id\tR1\tR2"
        while read -r sample; do
            [[ -z "$sample" || "$sample" =~ ^# ]] && continue
            echo -e "$sample\t$RAW_DIR/${sample}_1.fastq.gz\t$RAW_DIR/${sample}_2.fastq.gz"
        done < "$ACCESSION_FILE"
    } > "$SAMPLE_SHEET"
}

validate_sample_sheet() {
    [[ -f "$SAMPLE_SHEET" ]] || die "Missing sample sheet: $SAMPLE_SHEET"

    log "Validating sample sheet..."

    tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
        [[ -z "$sample" ]] && continue
        [[ -f "$r1" ]] || die "$sample: R1 file not found: $r1"
        [[ -f "$r2" ]] || die "$sample: R2 file not found: $r2"
    done
}

# -----------------------------
# Step 2: quality control
# -----------------------------

run_fastqc_raw() {
    log "Running FastQC on raw reads..."

    tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
        [[ -z "$sample" ]] && continue

        local html1="$QC_RAW_DIR/$(basename "${r1%.fastq.gz}")_fastqc.html"
        local html2="$QC_RAW_DIR/$(basename "${r2%.fastq.gz}")_fastqc.html"

        if [[ -f "$html1" && -f "$html2" ]]; then
            log "$sample: raw FastQC already present."
        else
            fastqc -t "$THREADS" "$r1" "$r2" --outdir "$QC_RAW_DIR"
        fi
    done

    multiqc "$QC_RAW_DIR" -o "$QC_RAW_DIR" --force
}

# -----------------------------
# Step 3: trimming
# -----------------------------

trim_reads() {
    log "Trimming reads with Trim Galore..."

    local trimmed_sheet="$PROJECT_DIR/samples.trimmed.tsv"

    {
        echo -e "sample_id\tR1\tR2"

        tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
            [[ -z "$sample" ]] && continue

            local tr1="$TRIM_DIR/${sample}_1_val_1.fq.gz"
            local tr2="$TRIM_DIR/${sample}_2_val_2.fq.gz"

            if [[ -f "$tr1" && -f "$tr2" ]]; then
                log "$sample: trimmed reads already present."
            else
                log "$sample: trimming..."

                trim_galore \
                    --paired \
                    --phred33 \
                    -j "$THREADS" \
                    -q 10 \
                    --length 5 \
                    -o "$TRIM_DIR" \
                    "$r1" "$r2"

                # Normalize Trim Galore output names.
                local basename_r1 basename_r2 produced_r1 produced_r2
                basename_r1="$(basename "$r1")"
                basename_r2="$(basename "$r2")"
                basename_r1="${basename_r1%.fastq.gz}"
                basename_r2="${basename_r2%.fastq.gz}"

                produced_r1="$(find "$TRIM_DIR" -maxdepth 1 -name "${basename_r1}*_val_1.fq.gz" | head -n 1)"
                produced_r2="$(find "$TRIM_DIR" -maxdepth 1 -name "${basename_r2}*_val_2.fq.gz" | head -n 1)"

                [[ -f "$produced_r1" ]] || die "$sample: trimmed R1 not found."
                [[ -f "$produced_r2" ]] || die "$sample: trimmed R2 not found."

                cp -f "$produced_r1" "$tr1"
                cp -f "$produced_r2" "$tr2"
            fi

            echo -e "$sample\t$tr1\t$tr2"
        done
    } > "$trimmed_sheet"

    SAMPLE_SHEET="$trimmed_sheet"
}

run_fastqc_trimmed() {
    log "Running FastQC on trimmed reads..."

    tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
        [[ -z "$sample" ]] && continue

        local html1="$QC_TRIM_DIR/$(basename "${r1%.fq.gz}")_fastqc.html"
        local html2="$QC_TRIM_DIR/$(basename "${r2%.fq.gz}")_fastqc.html"

        if [[ -f "$html1" && -f "$html2" ]]; then
            log "$sample: trimmed FastQC already present."
        else
            fastqc -t "$THREADS" "$r1" "$r2" --outdir "$QC_TRIM_DIR"
        fi
    done

    multiqc "$QC_TRIM_DIR" -o "$QC_TRIM_DIR" --force
}

# -----------------------------
# Step 4: reference genome
# -----------------------------

prepare_reference() {
    log "Preparing reference genome..."

    if [[ ! -f "$REFERENCE_FASTA" ]]; then
        [[ -n "$REFERENCE_URL" ]] || die "REFERENCE_FASTA not found and REFERENCE_URL is empty."

        local gz="${REFERENCE_FASTA}.gz"
        mkdir -p "$(dirname "$REFERENCE_FASTA")"

        log "Downloading reference genome..."
        wget -O "$gz" "$REFERENCE_URL"

        log "Uncompressing reference genome..."
        gunzip -f "$gz"
    else
        log "Reference genome already present."
    fi
}

index_reference() {
    log "Checking reference indexes..."

    local bwa_ok=true
    for ext in amb ann bwt pac sa; do
        [[ -f "${REFERENCE_FASTA}.${ext}" ]] || bwa_ok=false
    done

    if [[ "$bwa_ok" == "true" ]]; then
        log "BWA index already present."
    else
        log "Creating BWA index..."
        bwa index "$REFERENCE_FASTA"
    fi

    if [[ -f "${REFERENCE_FASTA}.fai" ]]; then
        log "SAMtools FASTA index already present."
    else
        log "Creating SAMtools FASTA index..."
        samtools faidx "$REFERENCE_FASTA"
    fi

    local dict="${REFERENCE_FASTA%.*}.dict"

    if [[ -f "$dict" ]]; then
        log "GATK sequence dictionary already present."
    else
        log "Creating GATK sequence dictionary..."
        gatk CreateSequenceDictionary \
            --REFERENCE "$REFERENCE_FASTA" \
            --OUTPUT "$dict"
    fi
}

# -----------------------------
# Step 5: alignment
# -----------------------------

align_reads() {
    log "Running BWA-MEM alignment..."

    tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
        [[ -z "$sample" ]] && continue

        local bam="$BAM_DIR/${sample}.sorted.bam"

        if [[ -f "$bam" && -f "${bam}.bai" ]]; then
            log "$sample: sorted BAM and index already present."
        else
            log "$sample: aligning and sorting..."

            bwa mem \
                -M \
                -t "$THREADS" \
                -R "@RG\tID:${sample}\tSM:${sample}\tPL:ILLUMINA\tLB:${sample}\tPU:${sample}" \
                "$REFERENCE_FASTA" "$r1" "$r2" \
                | samtools sort -@ "$THREADS" -o "$bam" -

            samtools index "$bam"
        fi

        samtools flagstat "$bam" > "$METRICS_DIR/${sample}.alignment.flagstat.txt"
        samtools view -b -f 4 "$bam" > "$METRICS_DIR/${sample}.unaligned_reads.bam"
    done
}

# -----------------------------
# Step 6: GATK known sites
# -----------------------------

prepare_known_vcf() {
    if [[ "$RUN_BQSR" != "true" ]]; then
        log "BQSR disabled. Skipping known-sites VCF."
        return
    fi

    log "Preparing known-sites VCF..."

    if [[ ! -f "$KNOWN_VCF" ]]; then
        [[ -n "$KNOWN_VCF_URL" ]] || die "RUN_BQSR=true but no KNOWN_VCF or KNOWN_VCF_URL was provided."

        mkdir -p "$(dirname "$KNOWN_VCF")"
        wget -O "$KNOWN_VCF" "$KNOWN_VCF_URL"
    fi

    if [[ -f "${KNOWN_VCF}.tbi" || -f "${KNOWN_VCF}.idx" ]]; then
        log "Known-sites VCF index already present."
    else
        gatk IndexFeatureFile -F "$KNOWN_VCF"
    fi
}

# -----------------------------
# Step 7: GATK preprocessing and calling
# -----------------------------

gatk_per_sample() {
    log "Running GATK per-sample steps..."

    tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
        [[ -z "$sample" ]] && continue

        local input_bam="$BAM_DIR/${sample}.sorted.bam"
        local dedup_bam="$GATK_DIR/${sample}.dedup.bam"
        local recal_table="$GATK_DIR/${sample}.recal.table"
        local bqsr_bam="$GATK_DIR/${sample}.dedup.bqsr.bam"
        local post_table="$GATK_DIR/${sample}.post_recal.table"
        local cov_pdf="$GATK_DIR/${sample}.AnalyzeCovariates.pdf"

        local caller_input
        local out_vcf

        [[ -f "$input_bam" ]] || die "$sample: missing sorted BAM."

        if [[ -f "$dedup_bam" && -f "${dedup_bam}.bai" ]]; then
            log "$sample: duplicate-marked BAM already present."
        else
            log "$sample: marking duplicates..."

            gatk --java-options "-Xmx${JAVA_MEM}" MarkDuplicates \
                --INPUT "$input_bam" \
                --OUTPUT "$dedup_bam" \
                --METRICS_FILE "$METRICS_DIR/${sample}.duplicate_metrics.txt" \
                --REMOVE_DUPLICATES "$REMOVE_DUPLICATES" \
                --CREATE_INDEX true
        fi

        if [[ "$RUN_BQSR" == "true" ]]; then
            if [[ ! -f "$recal_table" ]]; then
                log "$sample: building BQSR model..."

                gatk --java-options "-Xmx${JAVA_MEM}" BaseRecalibrator \
                    --input "$dedup_bam" \
                    --output "$recal_table" \
                    --reference "$REFERENCE_FASTA" \
                    --known-sites "$KNOWN_VCF" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi

            if [[ ! -f "$bqsr_bam" ]]; then
                log "$sample: applying BQSR..."

                gatk --java-options "-Xmx${JAVA_MEM}" ApplyBQSR \
                    --bqsr-recal-file "$recal_table" \
                    --input "$dedup_bam" \
                    --output "$bqsr_bam" \
                    --reference "$REFERENCE_FASTA" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi

            if [[ ! -f "$post_table" ]]; then
                log "$sample: post-BQSR recalibration table..."

                gatk --java-options "-Xmx${JAVA_MEM}" BaseRecalibrator \
                    --input "$bqsr_bam" \
                    --output "$post_table" \
                    --reference "$REFERENCE_FASTA" \
                    --known-sites "$KNOWN_VCF" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi

            if [[ ! -f "$cov_pdf" ]]; then
                log "$sample: AnalyzeCovariates..."

                gatk --java-options "-Xmx${JAVA_MEM}" AnalyzeCovariates \
                    -before "$recal_table" \
                    -after "$post_table" \
                    -plots "$cov_pdf"
            fi

            caller_input="$bqsr_bam"
        else
            caller_input="$dedup_bam"
        fi

        if [[ "$EMIT_GVCF" == "true" ]]; then
            out_vcf="$VCF_DIR/${sample}.g.vcf.gz"

            if [[ -f "$out_vcf" ]]; then
                log "$sample: GVCF already present."
            else
                log "$sample: HaplotypeCaller GVCF mode..."

                gatk --java-options "-Xmx${JAVA_MEM}" HaplotypeCaller \
                    --reference "$REFERENCE_FASTA" \
                    --input "$caller_input" \
                    --output "$out_vcf" \
                    --ERC GVCF \
                    --native-pair-hmm-threads "$THREADS" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi
        else
            out_vcf="$VCF_DIR/${sample}.vcf.gz"

            if [[ -f "$out_vcf" ]]; then
                log "$sample: VCF already present."
            else
                log "$sample: HaplotypeCaller VCF mode..."

                gatk --java-options "-Xmx${JAVA_MEM}" HaplotypeCaller \
                    --reference "$REFERENCE_FASTA" \
                    --input "$caller_input" \
                    --output "$out_vcf" \
                    --native-pair-hmm-threads "$THREADS" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi
        fi
    done
}

# -----------------------------
# Step 8: joint genotyping
# -----------------------------

joint_genotyping() {
    [[ "$RUN_JOINT_GENOTYPING" == "true" ]] || return
    [[ "$EMIT_GVCF" == "true" ]] || die "Joint genotyping requires EMIT_GVCF=true."

    log "Running joint genotyping..."

    local gvcf_map="$VCF_DIR/gvcf_map.txt"
    local genomicsdb="$VCF_DIR/genomicsdb"
    local joint_vcf="$VCF_DIR/cohort.raw.vcf.gz"

    {
        tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
            [[ -z "$sample" ]] && continue
            echo -e "$sample\t$VCF_DIR/${sample}.g.vcf.gz"
        done
    } > "$gvcf_map"

    if [[ -d "$genomicsdb" ]]; then
        log "GenomicsDB already present."
    else
        gatk --java-options "-Xmx${JAVA_MEM}" GenomicsDBImport \
            --sample-name-map "$gvcf_map" \
            --genomicsdb-workspace-path "$genomicsdb" \
            ${INTERVALS:+--intervals "$INTERVALS"}
    fi

    if [[ -f "$joint_vcf" ]]; then
        log "Joint VCF already present."
    else
        gatk --java-options "-Xmx${JAVA_MEM}" GenotypeGVCFs \
            --reference "$REFERENCE_FASTA" \
            --variant "gendb://$genomicsdb" \
            --output "$joint_vcf"
    fi
}

# -----------------------------
# Step 9: simple hard filtering
# -----------------------------

hard_filter_variants() {
    [[ "$RUN_HARD_FILTERING" == "true" ]] || return

    log "Running simple hard filtering..."

    local input_vcf

    if [[ "$RUN_JOINT_GENOTYPING" == "true" && -f "$VCF_DIR/cohort.raw.vcf.gz" ]]; then
        input_vcf="$VCF_DIR/cohort.raw.vcf.gz"
    else
        log "No joint VCF found. Hard filtering per-sample VCFs/GVCFs is not implemented in this section."
        return
    fi

    local snps="$VCF_DIR/cohort.raw.snps.vcf.gz"
    local indels="$VCF_DIR/cohort.raw.indels.vcf.gz"
    local filtered_snps="$VCF_DIR/cohort.filtered.snps.vcf.gz"
    local filtered_indels="$VCF_DIR/cohort.filtered.indels.vcf.gz"

    gatk SelectVariants \
        --reference "$REFERENCE_FASTA" \
        --variant "$input_vcf" \
        --select-type-to-include SNP \
        --output "$snps"

    gatk SelectVariants \
        --reference "$REFERENCE_FASTA" \
        --variant "$input_vcf" \
        --select-type-to-include INDEL \
        --output "$indels"

    gatk VariantFiltration \
        --reference "$REFERENCE_FASTA" \
        --variant "$snps" \
        --filter-name "QD_lt_2" --filter-expression "QD < 2.0" \
        --filter-name "FS_gt_60" --filter-expression "FS > 60.0" \
        --filter-name "MQ_lt_40" --filter-expression "MQ < 40.0" \
        --filter-name "SOR_gt_3" --filter-expression "SOR > 3.0" \
        --filter-name "MQRankSum_lt_-12.5" --filter-expression "MQRankSum < -12.5" \
        --filter-name "ReadPosRankSum_lt_-8" --filter-expression "ReadPosRankSum < -8.0" \
        --output "$filtered_snps"

    gatk VariantFiltration \
        --reference "$REFERENCE_FASTA" \
        --variant "$indels" \
        --filter-name "QD_lt_2" --filter-expression "QD < 2.0" \
        --filter-name "FS_gt_200" --filter-expression "FS > 200.0" \
        --filter-name "SOR_gt_10" --filter-expression "SOR > 10.0" \
        --filter-name "ReadPosRankSum_lt_-20" --filter-expression "ReadPosRankSum < -20.0" \
        --output "$filtered_indels"
}

# -----------------------------
# Manifest
# -----------------------------

write_manifest() {
    local manifest="$PROJECT_DIR/run_manifest.txt"

    {
        echo "Run date: $(timestamp)"
        echo "Project directory: $PROJECT_DIR"
        echo "Input mode: $INPUT_MODE"
        echo "Sample sheet: $SAMPLE_SHEET"
        echo "Reference FASTA: $REFERENCE_FASTA"
        echo "Reference URL: $REFERENCE_URL"
        echo "RUN_BQSR: $RUN_BQSR"
        echo "KNOWN_VCF: $KNOWN_VCF"
        echo "KNOWN_VCF_URL: $KNOWN_VCF_URL"
        echo "EMIT_GVCF: $EMIT_GVCF"
        echo "RUN_JOINT_GENOTYPING: $RUN_JOINT_GENOTYPING"
        echo "RUN_HARD_FILTERING: $RUN_HARD_FILTERING"
        echo "REMOVE_DUPLICATES: $REMOVE_DUPLICATES"
        echo "THREADS: $THREADS"
        echo "JAVA_MEM: $JAVA_MEM"
        echo "INTERVALS: $INTERVALS"
    } > "$manifest"
}

# -----------------------------
# Main
# -----------------------------

main() {
    mkdirs
    check_commands
    write_versions

    download_sra_reads
    create_sample_sheet_from_sra
    validate_sample_sheet

    run_fastqc_raw
    trim_reads
    run_fastqc_trimmed

    prepare_reference
    index_reference

    align_reads

    prepare_known_vcf
    gatk_per_sample

    joint_genotyping
    hard_filter_variants

    write_manifest

    log "Pipeline completed successfully."
}

main "$@"
