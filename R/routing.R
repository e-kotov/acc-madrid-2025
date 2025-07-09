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
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE)
  }

  # ensure r5r namespace is loaded
  if (!"r5r" %in% loadedNamespaces()) {
    loadNamespace("r5r")
  }
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
  gtfs_data, # not really neded, only used to imply dependency
  elevation_data, # not really neded, only used to imply dependency
  java_home,
  r5_jar,
  memory_limit_gb
) {
  # osm_data <- targets::tar_read(osm_data)
  # gtfs_data <- targets::tar_read(gtfs_data_files) # not really neded
  # elevation_data <- targets::tar_read(elevation_data) # not really neded
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

  selected_ids <- c(
    "CRS3035RES1000mN2035000E3157000",
    "CRS3035RES1000mN2028000E3162000"
  )

  origins_sf <- locations |>
    dplyr::filter(GRD_ID %in% selected_ids) |>
    dplyr::select(id = GRD_ID)

  destinations_sf <- locations |>
    dplyr::filter(T > 0) |>
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
      "01-07-2025 09:00:00",
      format = "%d-%m-%Y %H:%M:%S"
    ),
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

calculate_access_r5 <- function(
  locations,
  java_home,
  r5_jar,
  r5_graph_files,
  n_threads = parallelly::availableCores(),
  memory_limit_gb
  # accessibility_output_dir = "data/output/accessibility"
) {
  # locations <- targets::tar_read(madrid_gridded_pop) |>
  #   sf::st_point_on_surface() |>
  #   sf::st_transform(4326)
  # java_home <- targets::tar_read(java_home)
  # r5_jar <- targets::tar_read(r5_jar)
  # r5_graph_files <- targets::tar_read(r5_graph_files)
  # n_threads <- parallelly::availableCores() -2
  # memory_limit_gb <- 6

  # if (!dir.exists(accessibility_output_dir)) {
  #   dir.create(accessibility_output_dir, recursive = TRUE)
  # }

  origins_sf <- locations |>
    # dplyr::slice(1:1000) |>
    dplyr::select(id = GRD_ID) |>
    sf::st_transform(3042) |>
    sf::st_point_on_surface() |>
    sf::st_transform(4326)

  destinations_sf <- locations |>
    # dplyr::slice(100:110) |>
    dplyr::select(
      id = GRD_ID,
      total = `T`,
      males = `M`,
      females = `F`
    ) |>
    sf::st_transform(3042) |>
    sf::st_point_on_surface() |>
    sf::st_transform(4326)

  # departure times can be assumed to be the same for all trips, as we do not have traffic data anyway

  rJavaEnv::java_env_set(where = "session", java_home = java_home, quiet = TRUE)

  options(java.parameters = paste0("-Xmx", memory_limit_gb, "G"))

  r5r_set_cache_dir(fs::path_dir(r5_jar))

  r5r_core <- r5r::setup_r5(
    data_path = fs::path_dir(r5_graph_files[[1]]),
    verbose = TRUE
  )

  acc <- r5r::accessibility(
    r5r_core = r5r_core,
    origins = origins_sf,
    destinations = destinations_sf,
    opportunities_colnames = c("total", "males", "females"),
    departure_datetime = as.POSIXct(
      "03-07-2025 09:00:00",
      format = "%d-%m-%Y %H:%M:%S"
    ),
    mode = c("TRANSIT", "WALK"),
    mode_egress = "WALK",
    cutoffs = c(10, 20, 30, 40, 50, 60),
    time_window = 10,
    max_trip_duration = 24 * 60, # 24 hours
    n_threads = n_threads,
    # output_dir = accessibility_output_dir,
    progress = TRUE
  )

  # acc |>
  #   ggplot2::ggplot() +
  #   ggplot2::aes(x = accessibility) +
  #   ggplot2::geom_histogram() +
  #   ggplot2::scale_x_log10() +
  #   ggplot2::facet_wrap(~cutoff)

  # saveRDS(acc, "acc.rds")
  # acc <- readRDS("acc.rds")
  # mitms_districts <- targets::tar_read(mitms_districts)
  # sf::st_crs(mitms_districts)

  # madrid_districts <- mitms_districts |>
  #   dplyr::filter(grepl("Madrid di", name))

  # table(acc$opportunity)
  # table(acc$cutoff)
  # # table(acc$percentile)
  # dplyr::glimpse(acc)
  acc_wide <- acc |>
    dplyr::select(id, cutoff, opportunity, accessibility) |>
    tidyr::pivot_wider(
      names_from = c(opportunity, cutoff),
      values_from = accessibility
    )

  locations_with_access <- locations |>
    dplyr::rename(id = GRD_ID) |>
    dplyr::left_join(acc_wide, by = "id")

  return(locations_with_access)
}
