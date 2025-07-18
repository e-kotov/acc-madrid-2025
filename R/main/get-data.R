download_geofabrik_data <- function(
  match_places, # character vector, e.g. c("Catalunya", "Andalucía")
  target_dir = "data/input/osm" # where all .pbf files will be stored
) {
  # 1. Make sure the download directory exists
  if (!fs::dir_exists(target_dir)) {
    fs::dir_create(target_dir, recurse = TRUE)
  }

  # 2. Tell osmextract where to drop the files
  Sys.setenv(OSMEXT_DOWNLOAD_DIRECTORY = fs::path_real(target_dir))

  # 3. For each place, get the matching Geofabrik URL and download the file
  local_files <- purrr::map_chr(match_places, function(place) {
    print(paste0("Downloading ", place, "..."))
    pbf_info <- osmextract::oe_match(place, provider = "geofabrik")
    osmextract::oe_download(
      file_url = pbf_info$url,
      provider = "geofabrik"
    )
  })

  # 4. Name the vector for easy reference and return it
  names(local_files) <- match_places
  return(local_files)
}

get_gridded_pop_data <- function(
  input_dir,
  output_dir
) {
  # input_dir = gridded_pop_input_dir ; output_dir = gridded_pop_data_dir

  # x_url <- "https://zenodo.org/records/13916658/files/fgoerlich/HIPGDAC-ES-v1.0.0.zip?download=1"
  # https://www.nature.com/articles/s41597-025-04533-8#Sec7

  # https://ec.europa.eu/eurostat/web/gisco/geodata/population-distribution/population-grids
  # The raster, GeoPackage, and GeoParquet files are in the European Terrestrial Reference System 1989 Lambert Azimuthal Equal Area (ETRS989-LAEA, EPSG:3035) projection.
  x_url <- "https://gisco-services.ec.europa.eu/census/2021/Eurostat_Census-GRID_2021_V2.2.zip"
  save_zip_path <- paste0(input_dir, "/Eurostat_Census-GRID_2021_V2.2.zip")
  if (!fs::file_exists(save_zip_path)) {
    downloaded <- download.file(
      url = x_url,
      destfile = save_zip_path,
      method = "libcurl",
      quiet = FALSE,
      mode = "wb"
    )
  } else {
    headers <- curlGetHeaders(x_url)
    content_length_line <- grep(
      "content-length",
      headers,
      value = TRUE,
      ignore.case = TRUE
    )
    content_length_value <- sub(
      "content-length:\\s*(\\d+).*",
      "\\1",
      content_length_line,
      ignore.case = TRUE
    ) |>
      as.numeric()
    local_file_size <- fs::file_size(save_zip_path)

    if (local_file_size != content_length_value) {
      downloaded <- download.file(
        url = x_url,
        destfile = save_zip_path,
        method = "libcurl",
        quiet = FALSE,
        mode = "wb"
      )
    } else {
      print(paste0(save_zip_path, " file already exists and is up to date."))
    }
  }

  files_list <- unzip(
    zipfile = save_zip_path,
    list = TRUE
  )
  parquet_file <- files_list$Name[grepl("parquet", files_list$Name)]
  unzipped <- unzip(
    zipfile = save_zip_path,
    files = parquet_file,
    exdir = output_dir,
    overwrite = TRUE
  )
  return(unzipped)
}

extract_gridded_pop <- function(
  parquet_file,
  study_area_boundaries
) {
  # parquet_file <- targets::tar_read(gridded_population_parquet)
  # study_area_boundaries <- targets::tar_read(madrid_boundaries)

  con <- duckdb::dbConnect(duckdb::duckdb(":memory:"))

  DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")

  DBI::dbExecute(con, "SET enable_geoparquet_conversion=false")

  DBI::dbExecute(
    con,
    glue::glue(
      "CREATE OR REPLACE VIEW census_gp_view
       AS
       SELECT * EXCLUDE (geom), ST_GeomFromWKB(geom) AS geometry
       FROM read_parquet('{parquet_file}');"
    )
  )

  duckspatial::ddbs_write_vector(
    conn = con,
    data = study_area_boundaries |> sf::st_transform(3035),
    name = "study_area_boundaries",
    overwrite = TRUE
  )

  # spatial join
  DBI::dbExecute(
    con,
    "CREATE OR REPLACE VIEW extracted_grid AS
    SELECT
      c.*  
    FROM census_gp_view AS c  
    JOIN study_area_boundaries AS m  
      ON ST_Intersects(c.geometry, m.geometry);"
  )

  extracted_grid <- duckspatial::ddbs_read_vector(
    con,
    name = "extracted_grid",
    crs = 3035
  )

  duckdb::dbDisconnect(con)

  return(extracted_grid)
}

get_overture_poi <- function(
  study_area_boundaries
) {
  # study_area_boundaries <- targets::tar_read(madrid_boundaries)
  poi <- overtureR::open_curtain(
    type = "place",
    spatial_filter = sf::st_bbox(study_area_boundaries),
    as_sf = TRUE,
    mode = "table",
    base_url = "s3://overturemaps-us-west-2/release/2025-04-23.0"
  )
  # format(utils::object.size(poi), units = "Mb") # 850 Mb

  poi_reduced <- poi |>
    dplyr::mutate(primary_category = categories$primary) |>
    dplyr::mutate(
      alternative_categories = purrr::map_chr(
        categories$alternate,
        ~ paste(.x, collapse = ";")
      )
    ) |>
    dplyr::select(
      id,
      primary_category,
      alternative_categories,
      confidence,
      geometry
    )

  return(poi_reduced)
}


# copy_gtfs_data <- function(
#   input_dir = "data/input/gtfs",
#   output_dir
# ) {
#   gtfs_files <- fs::dir_ls(input_dir, type = "file", glob = "*.zip")
#   fs::file_copy(gtfs_files, output_dir, overwrite = TRUE)
#   gtfs_files_at_new_path <- fs::dir_ls(
#     output_dir,
#     type = "file",
#     glob = "*.zip"
#   )

#   return(gtfs_files_at_new_path)
# }

fix_gtfs_data <- function(
  input_dir = "data/input/gtfs",
  output_dir
) {
  gtfs_files <- fs::dir_ls(input_dir, type = "file", glob = "*.zip")
  if (!fs::dir_exists(output_dir)) {
    fs::dir_create(output_dir, recurse = TRUE)
  }
  for (i in seq_along(gtfs_files)) {
    # i <- 4
    x <- gtfstools::read_gtfs(gtfs_files[[i]])
    if (nrow(x$frequencies) == 0) {
      x$frequencies <- NULL
    } else {
      if (nrow(x$stop_times) > 0) {
        x$frequencies <- NULL
      } else {
        x <- gtfstools::frequencies_to_stop_times(x)
      }
    }
    gtfstools::write_gtfs(
      x,
      path = paste0(output_dir, "/gtfs_", fs::path_file(gtfs_files[[i]])),
      standard_only = TRUE,
      quiet = FALSE
    )
  }

  new_files_list <- fs::dir_ls(output_dir, type = "file", glob = "*.zip")
  return(new_files_list)
}


download_elevation_data <- function(
  study_area_boundaries,
  elevation_raster_save_dir = "data/input/osm/"
) {
  # study_area_boundaries <- targets::tar_read(catalunya_boundaries)
  elevation_data <- elevatr::get_elev_raster(
    locations = study_area_boundaries,
    z = 11,
    src = "aws",
    verbose = TRUE,
    ncpu = 4
  )
  elevation_raster_save_path <- paste0(
    elevation_raster_save_dir,
    "/elevation.tiff"
  )
  if (!fs::dir_exists(dirname(elevation_raster_save_path))) {
    fs::dir_create(dirname(elevation_raster_save_path), recurse = TRUE)
  }
  terra::writeRaster(
    elevation_data,
    elevation_raster_save_path,
    overwrite = TRUE
  )

  return(elevation_raster_save_path)
}

gtfs_calendar_dates <- function(
  input_dir = "data/input/osm"
) {
  gtfs_files <- fs::dir_ls(input_dir, type = "file", glob = "*gtfs*.zip")

  gtfs_list <- purrr::map(gtfs_files, gtfstools::read_gtfs)
  gtfs_calendar <- purrr::map(gtfs_list, ~ .x$calendar)
  gtfs_calendar_dates$`data/input/osm/gtfs_20240827_130129_CRTM_Cercanias.zip`

  return(gtfs_calendar_dates)
}
