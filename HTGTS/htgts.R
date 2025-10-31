#' htgts
#'
#' @description High-Throughput Genome-wide Translocation Sequencing Analysis
#' @param input_folder path of the directory containing all input data
#' @param fastq1_name character string indicating the first input FASTQ file name
#' @param fastq2_name character string indicating the second input FASTQ file name
#' @param expInfo_name name of the libseqInfo.txt file
#' @param expInfo2_name name of the libseqInfo2.txt file
#' @param configType configuration type, as defined in config_types.json (allowed values: HTGTS_mouse, HTGTS_human, CELTICSseq, polyA)
#' @param assembly reference genome version (e.g., mm9)
#' @return Results of the operation
#'
#' @export
htgts <- function(input_folder,
fastq1_name,
fastq2_name,
expInfo_name,
expInfo2_name,
configType,
assembly) {
  # Type validation
  if (!is.character(input_folder) || length(input_folder) != 1) {
    stop("input_folder must be a single character string")
  }
  if (!is.character(fastq1_name) || length(fastq1_name) != 1) {
    stop("fastq1_name must be a single character string")
  }
  if (!is.character(fastq2_name) || length(fastq2_name) != 1) {
    stop("fastq2_name must be a single character string")
  }
  if (!is.character(expInfo_name) || length(expInfo_name) != 1) {
    stop("expInfo_name must be a single character string")
  }
  if (!is.character(expInfo2_name) || length(expInfo2_name) != 1) {
    stop("expInfo2_name must be a single character string")
  }
  valid_configType <- c("HTGTS_mouse", "HTGTS_human", "CELTICSseq", "polyA")
  if (!is.character(configType) || length(configType) != 1 || !(configType %in% valid_configType)) {
    stop(paste0("configType must be one of: ", paste(valid_configType, collapse=", ")))
  }
  if (!is.character(assembly) || length(assembly) != 1) {
    stop("assembly must be a single character string")
  }
  
  # Security checks
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", input_folder)) {
    stop("Path traversal detected in input_folder")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", fastq1_name)) {
    stop("Path traversal detected in fastq1_name")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", fastq2_name)) {
    stop("Path traversal detected in fastq2_name")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", expInfo_name)) {
    stop("Path traversal detected in expInfo_name")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", expInfo2_name)) {
    stop("Path traversal detected in expInfo2_name")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", assembly)) {
    stop("Path traversal detected in assembly")
  }
  
  # Check if directory exists
  if (!rrundocker::is_running_in_docker()) {
    if (!dir.exists(input_folder)) {
      stop(paste("input_folder:", input_folder, "does not exist"))
    }
  }
  
  # Process file paths for Docker volume mounting
  # Process input_folder for Docker
  input_folder_abspath <- normalizePath(input_folder, mustWork = FALSE)
  input_folder_dir <- dirname(input_folder_abspath)
  input_folder_filename <- basename(input_folder)
  
  # Main volume mount point
  main_mount_dir <- input_folder_dir
  
  # Execute Docker container with error handling
  tryCatch({
    result <- rrundocker::run_in_docker(
      image_name = "repbioinfo/htgts_pipeline_lts_v16:latest",
      volumes = list(
        c(input_folder_dir, "/Data"),
      ),
      additional_arguments = c(
        "/Algorithm/HTGTS_Full.sh -fastq1",
        fastq1_name,
        "-fastq2",
        fastq2_name,
        "-expInfo",
        expInfo_name,
        "-expInfo2",
        expInfo2_name,
        "-outDir /output -configType",
        configType,
        "-assembly",
        assembly,
      )
    )
    
    # Process result
    return(list(
      status = "success",
      output_dir = file.path(main_mount_dir, "htgts_results")
    ))
  }, error = function(e) {
    stop(paste("Docker execution failed:", e$message))
  })
}
