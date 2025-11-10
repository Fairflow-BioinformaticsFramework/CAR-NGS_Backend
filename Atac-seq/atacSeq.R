#' atacSeq
#'
#' @description Function to perform Assay for Transposase-Accessible Chromatin with high-throughput sequencing analysis
#' @param input_directory Path to fastq files directory
#' @param genome_directory Path to reference genome fasta files directory
#' @param nThreads Number of cores for parallelization
#' @return Results of the operation
#'
#' @export
atacSeq <- function(input_directory,
genome_directory,
nThreads) {
  # Type validation
  if (!is.character(input_directory) || length(input_directory) != 1) {
    stop("input_directory must be a single character string")
  }
  if (!is.character(genome_directory) || length(genome_directory) != 1) {
    stop("genome_directory must be a single character string")
  }
  if (!is.numeric(nThreads) || length(nThreads) != 1) {
    stop("nThreads must be a single numeric value")
  }
  
  # Security checks
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", input_directory)) {
    stop("Path traversal detected in input_directory")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", genome_directory)) {
    stop("Path traversal detected in genome_directory")
  }
  
  # Check if directory exists
  if (!rrundocker::is_running_in_docker()) {
    if (!dir.exists(input_directory)) {
      stop(paste("input_directory:", input_directory, "does not exist"))
    }
  }
  
  # Check if directory exists
  if (!rrundocker::is_running_in_docker()) {
    if (!dir.exists(genome_directory)) {
      stop(paste("genome_directory:", genome_directory, "does not exist"))
    }
  }
  
  # Process file paths for Docker volume mounting
  # Process input_directory for Docker
  input_directory_abspath <- normalizePath(input_directory, mustWork = FALSE)
  input_directory_dir <- dirname(input_directory_abspath)
  input_directory_filename <- basename(input_directory)
  # Process genome_directory for Docker
  genome_directory_abspath <- normalizePath(genome_directory, mustWork = FALSE)
  genome_directory_dir <- dirname(genome_directory_abspath)
  genome_directory_filename <- basename(genome_directory)
  
  # Main volume mount point
  main_mount_dir <- input_directory_dir
  
  # Execute Docker container with error handling
  tryCatch({
    result <- rrundocker::run_in_docker(
      image_name = "repbioinfo/atacseq",
      volumes = list(
        c(input_directory, "/scratch"),
        c(genome_directory, "/genomes"),
        c("results", "/scratch/results")
      ),
      additional_arguments = c(
        "/home/script.sh",
        as.character(nThreads)
      )
    )
    
    # Process result
    return(list(
      status = "success",
      output_dir = file.path(main_mount_dir, "atacSeq_results")
    ))
  }, error = function(e) {
    stop(paste("Docker execution failed:", e$message))
  })
}
