# targets: quick access --------------------------------------------
# Sys.setenv(TAR_PROJECT = "main")
# targets::tar_visnetwork(label = "branches") # view pipeline
# targets::tar_make() # run pipeline
#
# targets::tar_prune() # delete stored targets that are no longer part of the pipeline
# targets::tar_destroy() # delete saved pipeline outputs to be able to run the pipeline from scratch
# targets::tar_load() # load any pipeline output by name
# x <- targets::tar_read() # read any pipeline output into an R object
# read more at https://docs.ropensci.org/targets/ and https://books.ropensci.org/targets/

# targets::tar_crew()
# targets_workflow_visnet <- targets::tar_visnetwork()
# htmlwidgets::saveWidget(targets_workflow_visnet, "output/workflow/targets_workflow_visnet.html", selfcontained = TRUE)

# Load packages required to define the pipeline:
library(targets)
library(geotargets)
# library(tarchetypes)
# library(crew)

# setup
# n_crew_workers <- 5 # set the number of workers for parallel processing
osm_pbf_download_dir <- "data/input/osm"
gridded_pop_input_dir <- "data/input/gridded-pop/"
gridded_pop_data_dir <- "data/proc/gridded-pop/"

# list of directories to be created
dirs <- c(
  osm_pbf_download_dir,
  gridded_pop_input_dir,
  gridded_pop_data_dir
)

# now make sure all directories exist
fs::dir_create(dirs, recurse = TRUE)


options("global.nthreads.import" = 4)
options("global.r5_jar_cache_path" = "bin/r5/")
options("global.r5_build_graph_memory_gb" = 6)
options("global.r5_nthreads.routing" = parallelly::availableCores() - 2)


# Set target options:
tar_option_set(
  # packages = packages,
  format = "qs"
  # , controller = crew::crew_controller_local(
  #   workers = n_crew_workers,
  #   seconds_idle = 60
  # )
)

# Import functions from "./R" subfolder
tar_source("R/main/")

# All actions to do the analysis are listed below
list(
  # get OSM data
  tar_target(
    name = osm_data,
    packages = c("osmextract", "rJavaEnv"),
    command = download_geofabrik_data(
      match_places = c(
        "Madrid"
      ),
      target_dir = osm_pbf_download_dir
    ),
    format = "file"
  ),

  # get Madrid boundaries
  tar_target(
    name = madrid_boundaries,
    packages = c("mapSpain"),
    command = mapSpain::esp_get_ccaa(ccaa = "Madrid", epsg = "4326")
  ),

  # get Spanish gridded population data
  tar_target(
    name = gridded_population_parquet,
    packages = c("dplyr", "fs"),
    command = get_gridded_pop_data(
      input_dir = gridded_pop_input_dir,
      output_dir = gridded_pop_data_dir
    ),
    format = "file"
  ),

  # extract grid for Madrid
  tar_target(
    name = madrid_gridded_pop,
    packages = c("duckdb", "dplyr", "glue", "duckspatial", "sf"),
    command = extract_gridded_pop(
      parquet_file = gridded_population_parquet,
      study_area_boundaries = madrid_boundaries
    )
  ),

  # get Overture Maps poi data
  tar_target(
    name = madrid_overture_poi,
    packages = c("sf", "overtureR", "dplyr"),
    command = get_overture_poi(
      study_area_boundaries = madrid_boundaries
    )
  ),

  # get elevation data
  tar_target(
    name = elevation_data,
    packages = c("elevatr", "terra", "fs"),
    command = download_elevation_data(
      study_area_boundaries = madrid_boundaries,
      elevation_raster_save_dir = osm_pbf_download_dir
    ),
    format = "file"
  ),

  # prepare Java environment for r5r router
  tar_target(
    name = java_home,
    packages = c("rJavaEnv"),
    command = prepare_java_env_for_router(),
    format = "file"
  ),

  # download the r5 router
  tar_target(
    name = r5_jar,
    packages = c("r5r"),
    command = cache_r5_jar(
      r5_jar_cache_path = getOption("global.r5_jar_cache_path")
    ),
    format = "file"
  ),

  # copy gtfs data into osm folder
  # data had to be downloaded manually due to login requirement of https://nap.transportes.gob.es/
  # tar_target(
  #   name = gtfs_data_files,
  #   packages = c("fs"),
  #   command = copy_gtfs_data(
  #     input_dir = "data/input/gtfs",
  #     output_dir = osm_pbf_download_dir
  #   )
  # ),
  tar_target(
    name = gtfs_data_files,
    packages = c("fs"),
    command = fix_gtfs_data(
      input_dir = "data/input/gtfs",
      output_dir = osm_pbf_download_dir
    )
  ),

  # prepare the routing data
  tar_target(
    name = r5_graph_files,
    # packages = c("callr", "rJavaEnv", "fs", "r5r"),
    packages = c("r5r", "rJavaEnv", "fs"),
    command = prepare_routing_data(
      osm_data = osm_data,
      gtfs_data = gtfs_data_files,
      elevation_data = elevation_data,
      java_home = java_home,
      r5_jar = r5_jar,
      memory_limit_gb = getOption("global.r5_build_graph_memory_gb")
    ),
    format = "file"
  ),

  tar_target(
    name = locations_with_access,
    packages = c("r5r", "rJavaEnv", "sf", "dplyr", "tidyr"),
    command = calculate_access_r5(
      locations = madrid_gridded_pop,
      java_home = java_home,
      r5_jar = r5_jar,
      r5_graph_files = r5_graph_files,
      n_threads = getOption("global.r5_nthreads.routing"),
      memory_limit_gb = getOption("global.r5_build_graph_memory_gb")
    )
  ),

  tar_terra_rast(
    name = acc_raster,
    packages = c("sf", "dplyr", "terra"),
    command = convert_acc_to_raster(
      acc = locations_with_access
    )
  ),

  tar_target(
    name = exported_acc_raster,
    packages = c("terra", "fs"),
    command = {
      out_dir <- "outputs/raster/"
      fs::dir_create(out_dir, recurse = TRUE)

      outfile <- file.path(out_dir, "acc_raster.tif")

      terra::writeRaster(
        x = acc_raster,
        filename = outfile,
        overwrite = TRUE
      )

      return(outfile)
    },
    format = "file"
  ),

  tar_target(
    name = acc_plot,
    packages = c("terra", "tmap"),
    command = plot_acc(
      r = acc_raster,
      out_dir = "outputs/plots/main/"
    ),
    format = "file"
  )
)

# targets::tar_visnetwork()
# targets::tar_make()
# targets::tar_prune()
# targets::tar_crew()
# targets_workflow_visnet <- targets::tar_visnetwork()
# htmlwidgets::saveWidget(targets_workflow_visnet, "output/workflow/targets_workflow_visnet.html", selfcontained = TRUE)
