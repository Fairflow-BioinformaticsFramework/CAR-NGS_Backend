#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# wgs_gatk_pipeline.sh
#
# Generalized WGS preprocessing and germline short-variant
# discovery pipeline using:
#   - SRA Toolkit
#   - FastQC / MultiQC
#   - Trim Galore
#   - BWA-MEM
#   - SAMtools
#   - GATK4
#
# The script is designed to be species-independent.
# All project-specific settings are defined in config.sh.
# ============================================================

CONFIG_FILE="${1:-config.sh}"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: configuration file not found: $CONFIG_FILE"
    echo "Usage: bash wgs_gatk_pipeline.sh config.sh"
    exit 1
fi

source "$CONFIG_FILE"

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

log() {
    echo "[$(timestamp)] $*"
}

fail() {
    echo "[$(timestamp)] ERROR: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

safe_mkdirs() {
    mkdir -p \
        "$RAW_DIR" "$QC_RAW_DIR" "$TRIM_DIR" "$QC_TRIM_DIR" \
        "$REF_DIR" "$BAM_DIR" "$GATK_DIR" "$METRICS_DIR" "$LOG_DIR"
}

check_software() {
    log "Checking required software..."

    require_command bwa
    require_command samtools
    require_command gatk
    require_command fastqc
    require_command multiqc

    if [[ "$RUN_TRIMMING" == "true" ]]; then
        require_command trim_galore
    fi

    if [[ "$INPUT_MODE" == "SRA" ]]; then
        require_command "$SRA_TOOL"
        if [[ "$SRA_TOOL" == "fasterq-dump" ]]; then
            require_command gzip
        fi
    fi

    if [[ -n "$REFERENCE_URL" || -n "$KNOWN_VCF_URL" || -n "$ANNOTATION_GFF_URL" ]]; then
        require_command wget
    fi
}

download_reference() {
    log "Preparing reference genome..."

    if [[ -f "$REFERENCE_FASTA" ]]; then
        log "Reference FASTA already exists: $REFERENCE_FASTA"
        return
    fi

    [[ -n "$REFERENCE_URL" ]] || fail "REFERENCE_FASTA not found and REFERENCE_URL is empty."

    local ref_gz="${REFERENCE_FASTA}.gz"

    log "Downloading reference from: $REFERENCE_URL"
    wget -O "$ref_gz" "$REFERENCE_URL"

    log "Uncompressing reference..."
    gunzip -f "$ref_gz"

    [[ -f "$REFERENCE_FASTA" ]] || fail "Reference FASTA was not created: $REFERENCE_FASTA"
}

download_annotation_if_requested() {
    if [[ -z "$ANNOTATION_GFF_URL" ]]; then
        return
    fi

    if [[ -f "$ANNOTATION_GFF" ]]; then
        log "Annotation file already exists: $ANNOTATION_GFF"
    else
        log "Downloading annotation file..."
        wget -O "$ANNOTATION_GFF" "$ANNOTATION_GFF_URL"
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

    local dict_file="${REFERENCE_FASTA%.*}.dict"
    if [[ -f "$dict_file" ]]; then
        log "GATK sequence dictionary already present."
    else
        log "Creating GATK sequence dictionary..."
        gatk CreateSequenceDictionary \
            --REFERENCE "$REFERENCE_FASTA" \
            --OUTPUT "$dict_file"
    fi
}

download_and_index_known_vcf() {
    if [[ "$RUN_BQSR" != "true" ]]; then
        log "BQSR disabled. Known variants are not required."
        return
    fi

    log "Preparing known variants VCF for BQSR..."

    if [[ ! -f "$KNOWN_VCF" ]]; then
        [[ -n "$KNOWN_VCF_URL" ]] || fail "RUN_BQSR=true but KNOWN_VCF is missing and KNOWN_VCF_URL is empty."

        log "Downloading known variants from: $KNOWN_VCF_URL"
        wget -O "$KNOWN_VCF" "$KNOWN_VCF_URL"
    else
        log "Known variants VCF already exists: $KNOWN_VCF"
    fi

    if [[ "$KNOWN_VCF" == *.gz ]]; then
        if [[ -f "${KNOWN_VCF}.tbi" ]]; then
            log "Known variants tabix index already present."
        else
            log "Indexing compressed known variants with GATK IndexFeatureFile..."
            gatk IndexFeatureFile -F "$KNOWN_VCF"
        fi
    else
        if [[ -f "${KNOWN_VCF}.idx" ]]; then
            log "Known variants index already present."
        else
            log "Indexing known variants with GATK IndexFeatureFile..."
            gatk IndexFeatureFile -F "$KNOWN_VCF"
        fi
    fi
}

download_sra_reads() {
    [[ "$INPUT_MODE" == "SRA" ]] || return

    [[ -f "$ACCESSION_FILE" ]] || fail "ACCESSION_FILE not found: $ACCESSION_FILE"

    log "Downloading reads from SRA..."

    while read -r sample; do
        [[ -z "$sample" || "$sample" =~ ^# ]] && continue

        local r1="${RAW_DIR}/${sample}_1.fastq.gz"
        local r2="${RAW_DIR}/${sample}_2.fastq.gz"

        if [[ -f "$r1" && -f "$r2" ]]; then
            log "FASTQ files already present for ${sample}."
            continue
        fi

        log "Downloading ${sample}..."

        if [[ "$SRA_TOOL" == "fasterq-dump" ]]; then
            fasterq-dump --split-files --threads "$THREADS" --outdir "$RAW_DIR" "$sample"
            gzip -f "${RAW_DIR}/${sample}"_*.fastq
        else
            fastq-dump --gzip --split-3 --outdir "$RAW_DIR" "$sample"
        fi

    done < "$ACCESSION_FILE"
}

make_sample_sheet_from_sra() {
    [[ "$INPUT_MODE" == "SRA" ]] || return

    log "Creating sample sheet from SRA accessions: $SAMPLE_SHEET"

    {
        echo -e "sample_id\tR1\tR2"
        while read -r sample; do
            [[ -z "$sample" || "$sample" =~ ^# ]] && continue
            echo -e "${sample}\t${RAW_DIR}/${sample}_1.fastq.gz\t${RAW_DIR}/${sample}_2.fastq.gz"
        done < "$ACCESSION_FILE"
    } > "$SAMPLE_SHEET"
}

validate_sample_sheet() {
    [[ -f "$SAMPLE_SHEET" ]] || fail "SAMPLE_SHEET not found: $SAMPLE_SHEET"

    log "Validating sample sheet..."

    tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
        [[ -z "$sample" ]] && continue
        [[ -f "$r1" ]] || fail "R1 FASTQ not found for ${sample}: $r1"
        [[ -f "$r2" ]] || fail "R2 FASTQ not found for ${sample}: $r2"
    done
}

run_fastqc_raw() {
    log "Running FastQC on raw reads..."

    if compgen -G "${QC_RAW_DIR}/*_fastqc.html" > /dev/null; then
        log "Raw FastQC outputs already present. Skipping raw FastQC."
    else
        tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
            [[ -z "$sample" ]] && continue
            fastqc -t "$THREADS" "$r1" "$r2" --outdir "$QC_RAW_DIR"
        done
    fi

    multiqc "$QC_RAW_DIR" -o "$QC_RAW_DIR" --force
}

trim_reads() {
    if [[ "$RUN_TRIMMING" != "true" ]]; then
        log "Trimming disabled. Using raw FASTQ files for alignment."
        return
    fi

    log "Trimming reads..."

    local trimmed_sheet="${PROJECT_DIR}/samples.trimmed.tsv"

    {
        echo -e "sample_id\tR1\tR2"

        tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
            [[ -z "$sample" ]] && continue

            local trim_r1="${TRIM_DIR}/${sample}_1_val_1.fq.gz"
            local trim_r2="${TRIM_DIR}/${sample}_2_val_2.fq.gz"

            if [[ -f "$trim_r1" && -f "$trim_r2" ]]; then
                log "Trimmed FASTQ already present for ${sample}."
            else
                log "Trimming ${sample}..."
                trim_galore \
                    --paired \
                    --phred33 \
                    -j "$THREADS" \
                    -q 10 \
                    --length 5 \
                    -o "$TRIM_DIR" \
                    "$r1" "$r2"

                # Trim Galore names output based on the original FASTQ basename.
                # Rename to standardized names if needed.
                local produced_r1
                local produced_r2
                produced_r1=$(find "$TRIM_DIR" -maxdepth 1 -name "$(basename "${r1%.fastq.gz}")*val_1.fq.gz" | head -n 1)
                produced_r2=$(find "$TRIM_DIR" -maxdepth 1 -name "$(basename "${r2%.fastq.gz}")*val_2.fq.gz" | head -n 1)

                [[ -f "$produced_r1" ]] || fail "Trimmed R1 not found for ${sample}"
                [[ -f "$produced_r2" ]] || fail "Trimmed R2 not found for ${sample}"

                cp -f "$produced_r1" "$trim_r1"
                cp -f "$produced_r2" "$trim_r2"
            fi

            echo -e "${sample}\t${trim_r1}\t${trim_r2}"
        done
    } > "$trimmed_sheet"

    SAMPLE_SHEET="$trimmed_sheet"
}

run_fastqc_trimmed() {
    if [[ "$RUN_TRIMMING" != "true" ]]; then
        return
    fi

    log "Running FastQC on trimmed reads..."

    if compgen -G "${QC_TRIM_DIR}/*_fastqc.html" > /dev/null; then
        log "Trimmed FastQC outputs already present. Skipping trimmed FastQC."
    else
        tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
            [[ -z "$sample" ]] && continue
            fastqc -t "$THREADS" "$r1" "$r2" --outdir "$QC_TRIM_DIR"
        done
    fi

    multiqc "$QC_TRIM_DIR" -o "$QC_TRIM_DIR" --force
}

alignment_extra_args() {
    if [[ -n "$INTERVALS" ]]; then
        # BWA cannot restrict mapping to intervals in the same way GATK can.
        # Intervals are used later by GATK only.
        echo ""
    else
        echo ""
    fi
}

align_sort_index() {
    log "Aligning reads and producing coordinate-sorted BAM files..."

    tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
        [[ -z "$sample" ]] && continue

        local sorted_bam="${BAM_DIR}/${sample}.sorted.bam"
        local flagstat="${METRICS_DIR}/${sample}.sorted.flagstat.txt"

        if [[ -f "$sorted_bam" && -f "${sorted_bam}.bai" ]]; then
            log "Sorted BAM already present for ${sample}."
        else
            log "Aligning ${sample}..."

            bwa mem \
                -M \
                -t "$THREADS" \
                -R "@RG\tID:${sample}\tSM:${sample}\tPL:ILLUMINA\tLB:${sample}\tPU:${sample}" \
                "$REFERENCE_FASTA" "$r1" "$r2" \
                | samtools sort -@ "$THREADS" -o "$sorted_bam" -

            samtools index "$sorted_bam"
        fi

        samtools flagstat "$sorted_bam" > "$flagstat"
        samtools view -b -f 4 "$sorted_bam" > "${METRICS_DIR}/${sample}.unmapped.bam"
    done
}

gatk_preprocess_and_call() {
    log "Running GATK preprocessing and variant calling..."

    tail -n +2 "$SAMPLE_SHEET" | while IFS=$'\t' read -r sample r1 r2; do
        [[ -z "$sample" ]] && continue

        local input_bam="${BAM_DIR}/${sample}.sorted.bam"
        local dedup_bam="${GATK_DIR}/${sample}.dedup.bam"
        local recal_table="${GATK_DIR}/${sample}.recal.table"
        local post_recal_table="${GATK_DIR}/${sample}.post_recal.table"
        local bqsr_bam="${GATK_DIR}/${sample}.dedup.bqsr.bam"
        local covariates_pdf="${GATK_DIR}/${sample}.bqsr.covariates.pdf"

        local hc_input_bam
        local output_variant

        [[ -f "$input_bam" ]] || fail "Missing input BAM for ${sample}: $input_bam"

        if [[ -f "$dedup_bam" && -f "${dedup_bam}.bai" ]]; then
            log "Deduplicated BAM already present for ${sample}."
        else
            log "Marking duplicates for ${sample}..."

            gatk --java-options "-Xmx${JAVA_MEM}" MarkDuplicates \
                --INPUT "$input_bam" \
                --OUTPUT "$dedup_bam" \
                --METRICS_FILE "${METRICS_DIR}/${sample}.duplicate_metrics.txt" \
                --REMOVE_DUPLICATES "$REMOVE_DUPLICATES" \
                --CREATE_INDEX true
        fi

        if [[ "$RUN_BQSR" == "true" ]]; then
            if [[ -f "$recal_table" ]]; then
                log "BQSR recalibration table already present for ${sample}."
            else
                log "Building BQSR model for ${sample}..."

                gatk --java-options "-Xmx${JAVA_MEM}" BaseRecalibrator \
                    --input "$dedup_bam" \
                    --output "$recal_table" \
                    --reference "$REFERENCE_FASTA" \
                    --known-sites "$KNOWN_VCF" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi

            if [[ -f "$bqsr_bam" && -f "${bqsr_bam}.bai" ]]; then
                log "BQSR BAM already present for ${sample}."
            else
                log "Applying BQSR for ${sample}..."

                gatk --java-options "-Xmx${JAVA_MEM}" ApplyBQSR \
                    --bqsr-recal-file "$recal_table" \
                    --input "$dedup_bam" \
                    --output "$bqsr_bam" \
                    --reference "$REFERENCE_FASTA" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi

            if [[ ! -f "$post_recal_table" ]]; then
                log "Creating post-BQSR recalibration table for ${sample}..."

                gatk --java-options "-Xmx${JAVA_MEM}" BaseRecalibrator \
                    --input "$bqsr_bam" \
                    --output "$post_recal_table" \
                    --reference "$REFERENCE_FASTA" \
                    --known-sites "$KNOWN_VCF" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi

            if [[ ! -f "$covariates_pdf" ]]; then
                log "Generating BQSR covariates plot for ${sample}..."

                gatk --java-options "-Xmx${JAVA_MEM}" AnalyzeCovariates \
                    -before "$recal_table" \
                    -after "$post_recal_table" \
                    -plots "$covariates_pdf"
            fi

            hc_input_bam="$bqsr_bam"
        else
            log "BQSR disabled for ${sample}; HaplotypeCaller will use duplicate-marked BAM."
            hc_input_bam="$dedup_bam"
        fi

        if [[ "$EMIT_GVCF" == "true" ]]; then
            output_variant="${GATK_DIR}/${sample}.g.vcf.gz"

            if [[ -f "$output_variant" ]]; then
                log "GVCF already present for ${sample}."
            else
                log "Running HaplotypeCaller in GVCF mode for ${sample}..."

                gatk --java-options "-Xmx${JAVA_MEM}" HaplotypeCaller \
                    --reference "$REFERENCE_FASTA" \
                    --input "$hc_input_bam" \
                    --output "$output_variant" \
                    --ERC GVCF \
                    --native-pair-hmm-threads "$THREADS" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi
        else
            output_variant="${GATK_DIR}/${sample}.vcf.gz"

            if [[ -f "$output_variant" ]]; then
                log "VCF already present for ${sample}."
            else
                log "Running HaplotypeCaller in ordinary VCF mode for ${sample}..."

                gatk --java-options "-Xmx${JAVA_MEM}" HaplotypeCaller \
                    --reference "$REFERENCE_FASTA" \
                    --input "$hc_input_bam" \
                    --output "$output_variant" \
                    --native-pair-hmm-threads "$THREADS" \
                    ${INTERVALS:+--intervals "$INTERVALS"}
            fi
        fi
    done
}

write_manifest() {
    local manifest="${PROJECT_DIR}/pipeline_manifest.txt"

    log "Writing pipeline manifest..."

    {
        echo "Pipeline run date: $(timestamp)"
        echo "Project directory: $PROJECT_DIR"
        echo "Input mode: $INPUT_MODE"
        echo "Reference FASTA: $REFERENCE_FASTA"
        echo "Known VCF: $KNOWN_VCF"
        echo "RUN_BQSR: $RUN_BQSR"
        echo "RUN_TRIMMING: $RUN_TRIMMING"
        echo "REMOVE_DUPLICATES: $REMOVE_DUPLICATES"
        echo "EMIT_GVCF: $EMIT_GVCF"
        echo "THREADS: $THREADS"
        echo
        echo "Software versions:"
        echo "bwa: $(bwa 2>&1 | head -n 3 | tr '\n' ' ')"
        echo "samtools: $(samtools --version | head -n 1)"
        echo "gatk: $(gatk --version 2>&1 | head -n 1)"
        echo "fastqc: $(fastqc --version 2>&1 | head -n 1)"
        echo "multiqc: $(multiqc --version 2>&1 | head -n 1)"
    } > "$manifest"
}

main() {
    safe_mkdirs
    check_software
    download_reference
    download_annotation_if_requested
    index_reference
    download_and_index_known_vcf
    download_sra_reads
    make_sample_sheet_from_sra
    validate_sample_sheet
    run_fastqc_raw
    trim_reads
    run_fastqc_trimmed
    align_sort_index
    gatk_preprocess_and_call
    write_manifest

    log "Pipeline completed successfully."
}

main "$@"
