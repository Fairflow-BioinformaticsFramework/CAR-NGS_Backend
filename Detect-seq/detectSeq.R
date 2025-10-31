#' detectSeq
#'
#' @description Executes a genome-wide assessment of off-target effects associated with cytosine base editors (CBEs)
#' @param input_folder path of the directory containing the fastq files
#' @param genome_folder path of the directory containing the genome fasta file and the index (if already obtained)
#' @param output_folder path of the directory in which the outputs will be saved
#' @param threshold threshold value for filtering
#' @param adapt1 first adapter sequence
#' @param adapt2 second adapter sequence
#' @return Results of the operation
#'
#' @export
detectSeq <- function(input_folder,
genome_folder,
output_folder,
threshold,
adapt1,
adapt2) {
  # Type validation
  if (!is.character(input_folder) || length(input_folder) != 1) {
    stop("input_folder must be a single character string")
  }
  if (!is.character(genome_folder) || length(genome_folder) != 1) {
    stop("genome_folder must be a single character string")
  }
  if (!is.character(output_folder) || length(output_folder) != 1) {
    stop("output_folder must be a single character string")
  }
  if (!is.numeric(threshold) || length(threshold) != 1 || threshold != round(threshold)) {
    stop("threshold must be a single integer value")
  }
  if (!is.character(adapt1) || length(adapt1) != 1) {
    stop("adapt1 must be a single character string")
  }
  if (!is.character(adapt2) || length(adapt2) != 1) {
    stop("adapt2 must be a single character string")
  }
  
  # Security checks
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", input_folder)) {
    stop("Path traversal detected in input_folder")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", genome_folder)) {
    stop("Path traversal detected in genome_folder")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", output_folder)) {
    stop("Path traversal detected in output_folder")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", adapt1)) {
    stop("Path traversal detected in adapt1")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", adapt2)) {
    stop("Path traversal detected in adapt2")
  }
  
  # Check if directory exists
  if (!rrundocker::is_running_in_docker()) {
    if (!dir.exists(input_folder)) {
      stop(paste("input_folder:", input_folder, "does not exist"))
    }
  }
  
  # Check if directory exists
  if (!rrundocker::is_running_in_docker()) {
    if (!dir.exists(genome_folder)) {
      stop(paste("genome_folder:", genome_folder, "does not exist"))
    }
  }
  
  # Check if directory exists
  if (!rrundocker::is_running_in_docker()) {
    if (!dir.exists(output_folder)) {
      stop(paste("output_folder:", output_folder, "does not exist"))
    }
  }
  
  # Process file paths for Docker volume mounting
  # Process input_folder for Docker
  input_folder_abspath <- normalizePath(input_folder, mustWork = FALSE)
  input_folder_dir <- dirname(input_folder_abspath)
  input_folder_filename <- basename(input_folder)
  # Process genome_folder for Docker
  genome_folder_abspath <- normalizePath(genome_folder, mustWork = FALSE)
  genome_folder_dir <- dirname(genome_folder_abspath)
  genome_folder_filename <- basename(genome_folder)
  # Process output_folder for Docker
  output_folder_abspath <- normalizePath(output_folder, mustWork = FALSE)
  output_folder_dir <- dirname(output_folder_abspath)
  output_folder_filename <- basename(output_folder)
  
  # Main volume mount point
  main_mount_dir <- input_folder_dir
  
  # Execute Docker container with error handling
  tryCatch({
    result <- rrundocker::run_in_docker(
      image_name = "repbioinfo/detectseq:latest",
      volumes = list(
        c(input_folder_dir, "/scratch/raw.fastq:ro"),
        c(genome_folder_dir, "/genome"),
        c(output_folder_dir, "/scratch"),
      ),
      additional_arguments = c(
        "/home/detectSeq.sh",
        as.character(threshold),
        adapt1,
        adapt2,
      )
    )
    
    # Process result
    return(list(
      status = "success",
      output_dir = file.path(main_mount_dir, "detectSeq_results")
    ))
  }, error = function(e) {
    stop(paste("Docker execution failed:", e$message))
  })
}
