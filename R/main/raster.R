convert_acc_to_raster <- function(
  acc
) {
  # acc <- targets::tar_read(locations_with_access)

  acc_sel <- acc |>
    dplyr::select(
      id,
      dplyr::contains("total_"),
      dplyr::contains("males_"),
      dplyr::contains("females_")
    ) |>
    sf::st_transform(acc_sel, crs = 3035)
  # dplyr::glimpse(acc_sel)

  v <- terra::vect(acc_sel)

  # create an empty raster template at 1 km resolution in EPSG:3035
  r_template <- rast(
    ext(v), # match extent of the vector
    resolution = 1000, # 1 km cells
    crs = "EPSG:3035"
  )

  # rasterize the vector data onto the raster template
  fields <- names(acc_sel)[
    !names(acc_sel) %in% c("id", attr(acc_sel, "sf_column"))
  ]
  r_list <- lapply(fields, function(fld) {
    terra::rasterize(v, r_template, field = fld, fun = "sum")
  })
  r <- terra::rast(r_list) # stack rasters
  names(r) <- fields

  return(r)
}

plot_acc <- function(
  r,
  out_dir = "output/plots/"
) {
  file_names <- c(
    "reachability_total.png",
    "reachability_females.png",
    "reachability_males.png"
  )
  # r <- targets::tar_read(acc_raster)
  if (!dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE)
  }

  # utils::install.packages("tmap")
  # library(tmap)
  tmap::tmap_mode("plot")

  base_plot <- function(r, vars) {
    p <- tmap::tm_shape(r) +
      tmap::tm_raster(
        col = vars, # small multiples for each total_ layer
        col.scale = tm_scale_intervals(
          values = "viridis",
          style = "fisher",
          n = 5
        ),
        col.free = c(FALSE, FALSE, TRUE)
      ) +
      tmap::tm_facets(
        ncol = 3
      ) +
      tmap::tm_layout(legend.outside = TRUE)
    return(p)
  }

  total_vars <- paste0("total_", seq(10, 60, by = 10))
  total <- base_plot(r, total_vars) +
    tmap::tm_title("Population Reachability within X-Minute Travel Thresholds")

  tmap::tmap_save(
    tm = total,
    filename = file.path(out_dir, file_names[1]),
    width = 8,
    height = 7,
    units = "in",
    dpi = 150
  )

  # females
  female_vars <- paste0("females_", seq(10, 60, by = 10))
  females <- base_plot(r, female_vars) +
    tmap::tm_title("Females Reachability within X-Minute Travel Thresholds")

  tmap::tmap_save(
    tm = females,
    filename = file.path(out_dir, file_names[2]),
    width = 8,
    height = 7,
    units = "in",
    dpi = 150
  )

  # males
  male_vars <- paste0("males_", seq(10, 60, by = 10))
  males <- base_plot(r, male_vars) +
    tmap::tm_title("Males Reachability within X-Minute Travel Thresholds")

  tmap::tmap_save(
    tm = males,
    filename = file.path(out_dir, file_names[3]),
    width = 8,
    height = 7,
    units = "in",
    dpi = 150
  )

  files <- file.path(out_dir, file_names) |> fs::path()
  return(files)
}
