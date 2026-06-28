# ANSI color codes
RED    <- '\033[91m'
WHITE  <- '\033[97m'
YELLOW <- '\033[93m'
ORANGE <- '\033[38;5;208m'
GREEN  <- '\033[92m'
RESET  <- '\033[0m'

cat_col <- function(..., color = WHITE) {
  cat(color, ..., RESET, '\n', sep = '')
}

usage_str <- paste0(paste0("\033[93m<workdir>", RESET), ' ', paste0("\033[93m<projectdir>", RESET), ' ', paste0("\033[93m<configdir>", RESET), ' ', paste0("\033[92m<config_file>", RESET))

args_raw <- commandArgs(trailingOnly = TRUE)

if (length(args_raw) != 4) {
  cat(WHITE, 'Usage: Rscript wgs_pipeline.R ', usage_str, RESET, '\n\n', sep = '')
  cat_col("Script to launch the WGS/GATK pipeline inside the Docker container", color = YELLOW)
  cat('\n')
  cat_col('Arguments:', color = WHITE)
  cat('\033[93mworkdir         [io]  Path to working directory containing scratch folder', RESET, '\n', sep = '')
  cat('\033[93mprojectdir      [io]  Path to local project folder', RESET, '\n', sep = '')
  cat('\033[93mconfigdir       [io]  Path to directory containing config_file', RESET, '\n', sep = '')
  cat('\033[92mconfig_file           name of the file for a reproducible WGS short-variant discovery pipeline based on BWA, SAMtools and GATK', RESET, '\n', sep = '')
  quit(status = 1)
}

# Parse positional arguments
args <- list()
args$workdir <- args_raw[1]
args$projectdir <- args_raw[2]
args$configdir <- args_raw[3]
args$config_file <- args_raw[4]

# --- Input validation ---
errors <- character(0)

if (!dir.exists(args$workdir)) {
  errors <- c(errors, paste0('Directory not found: workdir = ', args$workdir))
}
if (!dir.exists(args$projectdir)) {
  errors <- c(errors, paste0('Directory not found: projectdir = ', args$projectdir))
}
if (!dir.exists(args$configdir)) {
  errors <- c(errors, paste0('Directory not found: configdir = ', args$configdir))
}

if (length(errors) > 0) {
  for (e in errors) cat(RED, 'ERROR: ', RESET, WHITE, e, RESET, '\n', sep = '')
  quit(status = 1)
}

# --- Scratch directory setup ---
n <- 1
repeat {
  if (dir.exists(file.path(normalizePath(args$workdir), paste0('scratch', n)))) {
    n <- n + 1
  } else {
    break
  }
}

scratch_path <- file.path(normalizePath(args$workdir), paste0('scratch', n))
dir.create(scratch_path, recursive = TRUE, showWarnings = FALSE)

# --- Build docker volume mounts ---
mounts      <- character(0)
docker_vals <- list()
service_idx <- 1

mounts <- c(mounts, paste0('-v "', scratch_path, ':/workDir"'))
docker_vals$workdir <- '/workDir'

# projectdir: read-write directory [io]
mounts <- c(mounts, paste0('-v "', normalizePath(args$projectdir), ':/data"'))
docker_vals$projectdir <- '/data'

# configdir: read-write directory [io]
mounts <- c(mounts, paste0('-v "', normalizePath(args$configdir), ':/config"'))
docker_vals$configdir <- '/config'

# --- Bind files and service volumes ---
mounted_folders <- list()

docker_vals$config_file <- args$config_file

# --- Assemble docker command ---
mount_str <- paste(mounts, collapse = ' ')
cmd <- paste('docker run --rm', mount_str, 'generalized-wgs-gatk-pipeline bash /pipeline/wgs_gatk_pipeline.sh /config/<config_file>')
placeholders <- regmatches(cmd, gregexpr('<[^>]+>', cmd))[[1]]
for (ph in placeholders) {
  key <- gsub('<|>', '', ph)
  val <- docker_vals[[key]]
  if (!is.null(val)) cmd <- gsub(ph, val, cmd, fixed = TRUE)
}
cat('\n', YELLOW, 'Running:\n', RESET, WHITE, cmd, RESET, '\n\n', sep = '')
log_path <- file.path(scratch_path, 'output_log.txt')
cat(YELLOW, 'Log: ', RESET, WHITE, log_path, RESET, '\n\n', sep = '')

con <- file(log_path, open = 'w')
p   <- pipe(paste(cmd, '2>&1'), open = 'r')
while (length(line <- readLines(p, n = 1, warn = FALSE)) > 0) {
  cat(line, '\n', sep = '')
  writeLines(line, con)
}
ret <- close(p)
close(con)

if (ret == 0) {
  cat('\n', GREEN, 'Done. Log saved to: ', log_path, RESET, '\n', sep = '')
} else {
  cat('\n', RED, 'Docker exited with code ', ret, '. See log: ', log_path, RESET, '\n', sep = '')
}
quit(status = ret)