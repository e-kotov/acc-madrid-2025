prepare_java_env_for_router <- function() {
  java_home <- java_install(
    java_distrib_path = java_download(version = 21),
    autoset_java_env = FALSE
  )

  return(java_home)
}

prepare_java_env_for_router <- function() {
  java_home <- java_install(
    java_distrib_path = java_download(version = 21),
    autoset_java_env = FALSE
  )

  return(java_home)
}

cache_r5_jar <- function(
  r5_jar_cache_path
) {
  r5r_set_cache_dir(r5_jar_cache_path)
  r5_jar <- r5r::download_r5(quiet = FALSE)
  r5_jar
}


r5r_set_cache_dir <- function(path, move = FALSE) {
  path <- path.expand(path)
  if (!dir.exists(path)) dir.create(path, recursive = TRUE)

  # ensure r5r namespace is loaded
  if (!"r5r" %in% loadedNamespaces()) loadNamespace("r5r")
  env <- getFromNamespace("r5r_env", "r5r")

  # optionally move old files
  if (move && dir.exists(env$cache_dir)) {
    old <- env$cache_dir
    files <- list.files(old, full.names = TRUE)
    file.copy(files, path, recursive = TRUE)
    unlink(old, recursive = TRUE, force = TRUE)
  }

  env$cache_dir <- path
  message("r5r cache directory is now: ", path)
  invisible(path)
}


prepare_routing_data <- function(
  osm_data,
  elevation_data,
  java_home,
  r5_jar,
  memory_limit_gb
) {
  # osm_data <- targets::tar_read(osm_data)
  # java_home <- targets::tar_read(java_home)
  # r5_jar <- targets::tar_read(r5_jar) # not used, only passed to imply dependency of setup_r5, even though setup_r5 can also download the missing jar file
  # elevation_data is not used direcly, but it is picked up automatically by setup_r5, so it is passed to this function to imply dependency

  options(java.parameters = paste0("-Xmx", memory_limit_gb, "G"))

  rJavaEnv::java_env_set(where = "session", java_home = java_home, quiet = TRUE)

  # file_list_before_pre_processing <- dir_ls(path_dir(osm_data))

  r5r_set_cache_dir(fs::path_dir(r5_jar))

  r5r_core <- r5r::setup_r5(
    data_path = fs::path_dir(osm_data),
    verbose = TRUE
  )

  r5r::stop_r5(r5r_core)

  r5_files <- fs::dir_ls(
    fs::path_dir(osm_data),
    regexp = "\\.mapdb$|\\.p$|network_settings\\.json|network\\.dat"
  )

  return(r5_files)
}
