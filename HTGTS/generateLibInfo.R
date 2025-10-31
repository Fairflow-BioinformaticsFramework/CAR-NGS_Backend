#' generateLibInfo
#'
#' @description Generate sequencing library information from an XML file
#' @param xml_file XML file containing library information
#' @param configType configuration type, as defined in config_types.json (allowed values: HTGTS_mouse, HTGTS_human, CELTICSseq, polyA)
#' @param parent_folder path of the directory containing the xml file
#' @return Results of the operation
#'
#' @export
generateLibInfo <- function(xml_file,
configType,
parent_folder) {
  # Type validation
  if (!is.character(xml_file) || length(xml_file) != 1) {
    stop("xml_file must be a single character string")
  }
  valid_configType <- c("HTGTS_mouse", "HTGTS_human", "CELTICSseq", "polyA")
  if (!is.character(configType) || length(configType) != 1 || !(configType %in% valid_configType)) {
    stop(paste0("configType must be one of: ", paste(valid_configType, collapse=", ")))
  }
  if (!is.character(parent_folder) || length(parent_folder) != 1) {
    stop("parent_folder must be a single character string")
  }
  
  # Security checks
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", xml_file)) {
    stop("Path traversal detected in xml_file")
  }
  if (grepl("\\.\\./|\\.\\\\|\\/\\.\\./|\\\\\\.\\\\\\.\\\\", parent_folder)) {
    stop("Path traversal detected in parent_folder")
  }
  
  # Check if file exists
  if (!rrundocker::is_running_in_docker()) {
    if (!file.exists(xml_file)) {
      stop(paste("xml_file:", xml_file, "does not exist"))
    }
  }
  
  # Check if directory exists
  if (!rrundocker::is_running_in_docker()) {
    if (!dir.exists(parent_folder)) {
      stop(paste("parent_folder:", parent_folder, "does not exist"))
    }
  }
  
  # Process file paths for Docker volume mounting
  # Process xml_file for Docker
  xml_file_abspath <- normalizePath(xml_file, mustWork = FALSE)
  xml_file_dir <- dirname(xml_file_abspath)
  xml_file_filename <- basename(xml_file)
  # Process parent_folder for Docker
  parent_folder_abspath <- normalizePath(parent_folder, mustWork = FALSE)
  parent_folder_dir <- dirname(parent_folder_abspath)
  parent_folder_filename <- basename(parent_folder)
  
  # Main volume mount point
  main_mount_dir <- xml_file_dir
  
  # Execute Docker container with error handling
  tryCatch({
    result <- rrundocker::run_in_docker(
      image_name = "repbioinfo/htgts_pipeline_lts_v16:latest",
      volumes = list(
        c(parent_folder_dir, "/Data"),
      ),
      additional_arguments = c(
        "python3 /Algorithm/sample_sheetTolibInfo.py",
        xml_file_filename,
        "/Data/libseqInfo.txt",
        "/Data/libseqInfo2.txt",
        configType,
      )
    )
    
    # Process result
    return(list(
      status = "success",
      output_dir = file.path(main_mount_dir, "generateLibInfo_results")
    ))
  }, error = function(e) {
    stop(paste("Docker execution failed:", e$message))
  })
}
