# ============================================================
# Dockerfile
# Reproducible container for the refined HackMD WGS/GATK pipeline
# ============================================================

FROM continuumio/miniconda3:24.5.0-0

LABEL description="Docker environment for WGS preprocessing and GATK variant calling pipeline"

SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    unzip \
    gzip \
    bzip2 \
    ca-certificates \
    procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN conda create -y -n wgs_env -c conda-forge -c bioconda \
    bwa \
    samtools \
    gatk4 \
    fastqc \
    multiqc \
    trim-galore \
    sra-tools \
    && conda clean -afy

ENV PATH="/opt/conda/envs/wgs_env/bin:${PATH}"

WORKDIR /pipeline

COPY hackmd_wgs_pipeline_refined.sh /pipeline/hackmd_wgs_pipeline_refined.sh

RUN chmod +x /pipeline/hackmd_wgs_pipeline_refined.sh

CMD ["bash", "/pipeline/hackmd_wgs_pipeline_refined.sh"]
