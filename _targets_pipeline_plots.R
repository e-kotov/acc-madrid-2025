# targets: quick access lines --------------------------------------------
# Sys.setenv(TAR_PROJECT = "pipeline_plots")
# targets::tar_visnetwork(label = "branches") # view pipeline
# targets::tar_make() # run pipeline
#
# targets::tar_prune() # delete stored targets that are no longer part of the pipeline
# targets::tar_destroy() # delete saved pipeline outputs to be able to run the pipeline from scratch
# targets::tar_load() # load any pipeline output by name
# x <- targets::tar_read() # read any pipeline output into an R object
# read more at https://docs.ropensci.org/targets/ and https://books.ropensci.org/targets/

library(targets)

tar_option_set(
  format = "qs"
)

# source the R scripts
tar_source("R/pipeline_plots/")

# parameters -------------------------------------------------------------

pipeline_plots_dir <- "outputs/plots/pipeline-plots"

if (!fs::dir_exists(pipeline_plots_dir)) {
  fs::dir_create(pipeline_plots_dir, recurse = TRUE)
}


list(
  tar_target(
    name = pipelines,
    packages = c("fs", "jsonlite"),
    command = detect_pipelines_in_current_project()
  ),

  tar_target(
    name = pipeline_mermaid_files,
    packages = c("fs", "targets"),
    command = generate_pipelines_mermaid_code(
      pipelines = pipelines,
      plots_output_dir = pipeline_plots_dir
    ),
    format = "file"
  ),

  # update mermaid js for DiagrammeR to be able to render the mermaid plots from targets::tar_mermaid()
  # see https://github.com/rich-iannone/DiagrammeR/issues/464
  # the correct mermaid js is already burned into the container for this project
  # so it is not updated if it is already present
  tar_target(
    name = mermaid_js,
    command = update_mermaid_js(version = "11.8.1")
  ),

  tar_target(
    name = pipeline_plots_html,
    packages = c("DiagrammeR", "webshot2", "fs", "htmlwidgets"),
    command = render_mermaid_plots_html(
      pipeline_mermaid_files = pipeline_mermaid_files,
      plots_output_dir = pipeline_plots_dir,
      mermaid_js = mermaid_js
    ),
    format = "file"
  ),

  tar_target(
    name = pipeline_plots_png,
    packages = c("DiagrammeR", "webshot2", "fs", "htmlwidgets"),
    command = render_mermaid_plots_png(
      pipelines_html_files = pipeline_plots_html,
      plots_output_dir = pipeline_plots_dir
    ),
    format = "file"
  )
)
