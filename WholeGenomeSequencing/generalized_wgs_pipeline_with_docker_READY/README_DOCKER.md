# Docker usage for generalized WGS/GATK pipeline

This version adds Docker support to the generalized WGS/GATK pipeline.

## Files

- `config.sh`
  - Main configuration file.
- `wgs_gatk_pipeline.sh`
  - Main generalized pipeline.
- `Dockerfile`
  - Defines the reproducible software environment.
- `build_docker.sh`
  - Builds the Docker image.
- `run_pipeline_docker.sh`
  - External launcher. Run this from the host computer, not from inside Docker.

## Build the Docker image

From this repository folder:

```bash
bash build_docker.sh
```

This builds:

```bash
generalized-wgs-gatk-pipeline
```

## Prepare the project directory

Create a project folder:

```bash
mkdir -p wgs_project
```

For SRA input, create:

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

## Run from outside Docker

```bash
bash run_pipeline_docker.sh
```

Internally, the script runs:

```bash
docker run --rm -it \
    -v "$PROJECT_DIR":/data \
    -e PROJECT_DIR=/data \
    generalized-wgs-gatk-pipeline
```

This means that:

- the local project folder is mounted inside Docker as `/data`;
- the pipeline receives `PROJECT_DIR=/data`;
- all outputs are written back to your local `wgs_project` folder;
- the user does not need to manually enter the Docker container.

## Use a different project directory

```bash
PROJECT_DIR=/absolute/path/to/my_project bash run_pipeline_docker.sh
```

## Use a different Docker image name

```bash
IMAGE_NAME=my-generalized-wgs bash build_docker.sh
IMAGE_NAME=my-generalized-wgs bash run_pipeline_docker.sh
```

## Important note about configuration

The Docker image contains the default `config.sh`. The external launcher overrides only:

```bash
PROJECT_DIR=/data
```

If you want to change reference genome URLs, BQSR settings, or other pipeline parameters, edit `config.sh` before building the Docker image, or modify the launcher to mount a custom configuration file.
