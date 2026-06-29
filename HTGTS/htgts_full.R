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

usage_str <- paste0(paste0("\033[38;5;208m<fastq1>", RESET), ' ', paste0("\033[38;5;208m<fastq2>", RESET), ' ', paste0("\033[38;5;208m<expinfo>", RESET), ' ', paste0("\033[38;5;208m<expinfo2>", RESET), ' ', paste0("\033[93m<workdir>", RESET), ' ', paste0("\033[93m<outdir>", RESET), ' ', paste0("\033[92m<configtype>", RESET), ' ', paste0("\033[92m<assembly>", RESET))

args_raw <- commandArgs(trailingOnly = TRUE)

if (length(args_raw) != 8) {
  cat(WHITE, 'Usage: Rscript htgts_full.R ', usage_str, RESET, '\n\n', sep = '')
  cat_col("analizzare dati di sequenziamento e mappare le traslocazioni genomiche o i siti di rottura del DNA su larga scala", color = YELLOW)
  cat('\n')
  cat_col('Arguments:', color = WHITE)
  cat('\033[38;5;208mfastq1          [cp]  the first input FASTQ file name', RESET, '\n', sep = '')
  cat('\033[38;5;208mfastq2          [cp]  the second input FASTQ file name', RESET, '\n', sep = '')
  cat('\033[38;5;208mexpinfo         [ro]  name of the libseqInfo.txt file', RESET, '\n', sep = '')
  cat('\033[38;5;208mexpinfo2        [nc]  name of the libseqInfo2.txt file', RESET, '\n', sep = '')
  cat('\033[93mworkdir         [io]  percorso cartella di lavoro', RESET, '\n', sep = '')
  cat('\033[93moutdir          [out] percorso cartella di output', RESET, '\n', sep = '')
  cat('\033[92mconfigtype            tipo di cellule', RESET, '\n', sep = '')
  cat('\033[92massembly              reference genome version', RESET, '\n', sep = '')
  quit(status = 1)
}

# Parse positional arguments
args <- list()
args$fastq1 <- args_raw[1]
args$fastq2 <- args_raw[2]
args$expinfo <- args_raw[3]
args$expinfo2 <- args_raw[4]
args$workdir <- args_raw[5]
args$outdir <- args_raw[6]
args$configtype <- args_raw[7]
args$assembly <- args_raw[8]

# --- Input validation ---
errors <- character(0)

if (!dir.exists(args$workdir)) {
  errors <- c(errors, paste0('Directory not found: workdir = ', args$workdir))
}
if (!dir.exists(args$outdir)) {
  errors <- c(errors, paste0('Directory not found: outdir = ', args$outdir))
}
if (!file.exists(args$fastq1)) {
  errors <- c(errors, paste0('File not found: fastq1 = ', args$fastq1))
}
if (!file.exists(args$fastq2)) {
  errors <- c(errors, paste0('File not found: fastq2 = ', args$fastq2))
}
if (!file.exists(args$expinfo)) {
  errors <- c(errors, paste0('File not found: expinfo = ', args$expinfo))
}
if (!file.exists(args$expinfo2)) {
  errors <- c(errors, paste0('File not found: expinfo2 = ', args$expinfo2))
}
if (!args$configtype %in% c("HTGTS_human", "HTGTS_mouse", "CELTICSseq", "polyA")) {
  errors <- c(errors, paste0('Invalid value for configtype: ', args$configtype, '. Allowed: HTGTS_human, HTGTS_mouse, CELTICSseq, polyA'))
}
if (!args$assembly %in% c("hg38", "mm9", "mm10", "custom")) {
  errors <- c(errors, paste0('Invalid value for assembly: ', args$assembly, '. Allowed: hg38, mm9, mm10, custom'))
}

if (length(errors) > 0) {
  for (e in errors) cat(RED, 'ERROR: ', RESET, WHITE, e, RESET, '\n', sep = '')
  quit(status = 1)
}

# --- Scratch directory setup ---
n <- 1
repeat {
  if (dir.exists(file.path(normalizePath(args$workdir), paste0('scratch', n))) || dir.exists(file.path(normalizePath(args$outdir), paste0('scratch', n)))) {
    n <- n + 1
  } else {
    break
  }
}

scratch_path <- file.path(normalizePath(args$workdir), paste0('scratch', n))
dir.create(scratch_path, recursive = TRUE, showWarnings = FALSE)
scratch_out_path <- file.path(normalizePath(args$outdir), paste0('scratch', n))
dir.create(scratch_out_path, recursive = TRUE, showWarnings = FALSE)

# --- Build docker volume mounts ---
mounts      <- character(0)
docker_vals <- list()
service_idx <- 1

mounts <- c(mounts, paste0('-v "', scratch_path, ':/workDir"'))
docker_vals$workdir <- '/workDir'

host_out_base <- normalizePath(args$outdir)
mounts <- c(mounts, paste0('-v "', host_out_base, ':/outDir"'))
docker_vals$outdir <- paste0('/outDir/scratch', n)

# --- Bind files and service volumes ---
mounted_folders <- list()

src_fastq1 <- normalizePath(args$fastq1)
file.copy(src_fastq1, scratch_path)
docker_vals$fastq1 <- paste0('/workDir/', basename(src_fastq1))

src_fastq2 <- normalizePath(args$fastq2)
file.copy(src_fastq2, scratch_path)
docker_vals$fastq2 <- paste0('/workDir/', basename(src_fastq2))

src_expinfo <- normalizePath(args$expinfo)
dir_expinfo <- dirname(src_expinfo)
if (is.null(mounted_folders[[dir_expinfo]])) {
  m_point <- paste0('/service', service_idx)
  mounted_folders[[dir_expinfo]] <- m_point
  mounts <- c(mounts, paste0('-v "', dir_expinfo, ':', m_point, ':ro"'))
  service_idx <- service_idx + 1
}
docker_vals$expinfo <- paste0(mounted_folders[[dir_expinfo]], '/', basename(src_expinfo))

src_expinfo2 <- normalizePath(args$expinfo2)
dir_expinfo2 <- dirname(src_expinfo2)
if (is.null(mounted_folders[[dir_expinfo2]])) {
  m_point <- paste0('/service', service_idx)
  mounted_folders[[dir_expinfo2]] <- m_point
  mounts <- c(mounts, paste0('-v "', dir_expinfo2, ':', m_point, ':ro"'))
  service_idx <- service_idx + 1
}
docker_vals$expinfo2 <- paste0(mounted_folders[[dir_expinfo2]], '/', basename(src_expinfo2))

docker_vals$configtype <- args$configtype
docker_vals$assembly <- args$assembly

# --- Assemble docker command ---
mount_str <- paste(mounts, collapse = ' ')
cmd <- paste('docker run --rm', mount_str, 'repbioinfo/htgts_pipeline_lts_v16:latest /Algorithm/HTGTS_Full.sh -fastq1 <fastq1> -fastq2 <fastq2> -expInfo <expinfo> -expInfo2 <expinfo2> -outDir <outdir> -configType <configtype> -assembly <assembly>')
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