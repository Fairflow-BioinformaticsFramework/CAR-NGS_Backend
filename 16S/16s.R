#' sixteenS
#'
#' @description Pipeline for the analysis of 16S rRNA gene sequencing data
#' @param input_directory Path to input directory containing fastq files
#' @return Results of the operation
#'
#' @export
sixteenS <- function(input_directory) {
  # Type validation
  if (!is.character(input_directory) || length(input_directory) != 1) {
    stop("input_directory must be a single character string")
  }
  
  # Security checks
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", input_directory)) {
    stop("Path traversal detected in input_directory")
  }
  
  # Check if directory exists
  if (!rrundocker::is_running_in_docker()) {
    if (!dir.exists(input_directory)) {
      stop(paste("input_directory:", input_directory, "does not exist"))
    }
  }
  
  # Process file paths for Docker volume mounting
  # Process input_directory for Docker
  input_directory_abspath <- normalizePath(input_directory, mustWork = FALSE)
  input_directory_dir <- dirname(input_directory_abspath)
  input_directory_filename <- basename(input_directory)
  
  # Main volume mount point
  main_mount_dir <- input_directory_dir
  
  # Execute Docker container with error handling
  tryCatch({
    result <- rrundocker::run_in_docker(
      image_name = "repbioinfo/qiime2023",
      volumes = list(
        c(input_directory_dir, "/scratch")
      ),
      additional_arguments = c(
        "/home/qiime_full.sh"
      )
    )
    
    # Process result
    return(list(
      status = "success",
      output_dir = file.path(main_mount_dir, "sixteenS_results")
    ))
  }, error = function(e) {
    stop(paste("Docker execution failed:", e$message))
  })
}
