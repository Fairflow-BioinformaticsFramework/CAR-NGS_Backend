# Docker wrapper for the WGS/GATK pipeline

This folder adds Docker support to the refined HackMD WGS/GATK pipeline.

## Files

- `Dockerfile`: defines the computational environment.
- `build_docker.sh`: builds the Docker image.
- `run_pipeline_docker.sh`: external launcher script. This is the script you run from your computer, outside Docker.
- `hackmd_wgs_pipeline_refined.sh`: the pipeline that runs inside Docker.

## Build the image

```bash
bash build_docker.sh
```

This creates the Docker image:

```bash
wgs-gatk-pipeline
```

## Prepare input

Create a project folder:

```bash
mkdir -p wgs_project
```

Inside it, create:

```bash
wgs_project/accession.txt
```

Example:

```text
ERR10219898
ERR10219899
ERR10219900
ERR10219901
```

## Run the pipeline from outside Docker

```bash
bash run_pipeline_docker.sh
```

The launcher runs:

```bash
docker run --rm -it \
    -v "$PROJECT_DIR":/data \
    -e PROJECT_DIR=/data \
    wgs-gatk-pipeline
```

This means:

- your local project folder is mounted inside Docker as `/data`;
- the pipeline writes outputs into your local folder;
- you do not need to manually enter the Docker container.

## Use another project folder

```bash
PROJECT_DIR=/absolute/path/to/project bash run_pipeline_docker.sh
```

## Use another image name

```bash
IMAGE_NAME=my-wgs-pipeline bash build_docker.sh
IMAGE_NAME=my-wgs-pipeline bash run_pipeline_docker.sh
```

## Explanation

The Docker image contains all programs needed by the pipeline:

- BWA
- SAMtools
- GATK4
- FastQC
- MultiQC
- Trim Galore
- SRA Toolkit

The external launcher script allows the user to start the full analysis from the host machine without manually working inside the container.
