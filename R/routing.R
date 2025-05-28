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
  gtfs_data,
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

calculate_routes_r5 <- function(
  locations,
  java_home,
  r5_jar,
  r5_graph_files,
  n_threads = parallelly::availableCores(),
  memory_limit_gb
) {
  # locations <- targets::tar_read(madrid_gridded_pop) |>
  #   sf::st_point_on_surface() |>
  #   sf::st_transform(4326)
  # java_home <- targets::tar_read(java_home)
  # r5_jar <- targets::tar_read(r5_jar)
  # r5_graph_files <- targets::tar_read(r5_graph_files)
  # n_threads <- parallelly::availableCores() -2
  # memory_limit_gb <- 6

  origins_sf <- locations |>
    # dplyr::slice(1:5) |>
    dplyr::select(id = GRD_ID)

  destinations_sf <- locations |>
    dplyr::slice(100:110) |>
    dplyr::select(id = GRD_ID)

  # departure times can be assumed to be the same for all trips, as we do not have traffic data anyway

  rJavaEnv::java_env_set(where = "session", java_home = java_home, quiet = TRUE)

  options(java.parameters = paste0("-Xmx", memory_limit_gb, "G"))

  r5r_set_cache_dir(fs::path_dir(r5_jar))

  r5r_core <- r5r::setup_r5(
    data_path = fs::path_dir(r5_graph_files[[1]]),
    verbose = TRUE
  )

  routes <- r5r::detailed_itineraries(
    r5r_core = r5r_core,
    origins = origins_sf,
    destinations = destinations_sf,
    departure_datetime = as.POSIXct(
      "13-05-2014 09:00:00",
      format = "%d-%m-%Y %H:%M:%S"
    ), # does not matter, works for public transport only anyway
    mode = c("TRANSIT", "WALK"),
    max_trip_duration = 24 * 60, # 24 hours
    n_threads = n_threads,
    all_to_all = TRUE,
    progress = TRUE,
    drop_geometry = FALSE
  )

  mapgl::maplibre_view(routes)

  trips_and_routes <- list(
    trips = trips_row_id,
    routes = routes
  )

  return(trips_and_routes)
}
