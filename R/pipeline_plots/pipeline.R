detect_pipelines_in_current_project <- function() {
  targets_yaml <- yaml::read_yaml("_targets.yaml")
  pipelines <- names(targets_yaml)
  # remove self
  pipelines <- pipelines[pipelines != "pipeline_plots"]
  return(pipelines)
}

generate_pipelines_mermaid_code <- function(
  pipelines,
  plots_output_dir
) {
  if (!fs::dir_exists(plots_output_dir)) {
    fs::dir_create(plots_output_dir, recurse = TRUE)
  }

  pipeline_mermaid_files <- list()

  # get code
  for (pipeline in pipelines) {
    print(paste0("Building mermaid plot for: ", pipeline))
    Sys.setenv("TAR_PROJECT" = pipeline)
    pipeline_mermaid_tmp <- targets::tar_mermaid(label = "branches")
    mermaid_save_path <- file.path(
      plots_output_dir,
      paste0(pipeline, ".mermaid")
    )
    writeLines(
      text = pipeline_mermaid_tmp,
      con = mermaid_save_path
    )
    print(paste0("Finished building mermaid plot for: ", pipeline))
    pipeline_mermaid_files[[pipeline]] <- mermaid_save_path
  }
  pipeline_mermaid_files <- unlist(pipeline_mermaid_files)
  return(pipeline_mermaid_files)
}

render_mermaid_plots_html <- function(
  pipeline_mermaid_files,
  plots_output_dir,
  mermaid_js
) {
  # pipeline_mermaid_files <- targets::tar_read(pipeline_mermaid_files)
  # pipeline_plots_dir <- "outputs/plots/pipeline-plots"

  pipelines_html_files <- list()
  for (pipeline_mermaid_file in pipeline_mermaid_files) {
    pipeline_mermaid_tmp_single <- pipeline_mermaid_file |>
      readLines() |>
      paste0(collapse = "\n")
    pipeline_diagram <- DiagrammeR::DiagrammeR(
      diagram = pipeline_mermaid_tmp_single,
      type = "mermaid"
    )
    html_save_path <- gsub("mermaid", "html", pipeline_mermaid_file)

    # custom css injection to allow for larger viewport for webshot2
    custom_css <- "
      body {
        width: 1600px;
        height: 1200px;
      }

      div#htmlwidget_container {
        width: 1600px;
        height: 1200px;
      }
    "
    css_string <- jsonlite::toJSON(custom_css, auto_unbox = TRUE)
    pipeline_diagram_with_css <- htmlwidgets::onRender(
      pipeline_diagram,
      sprintf(
        "function(el, x) {
      // Retrieve the custom CSS that was passed from R
      var css = %s;
      // Create a <style> element
      var style = document.createElement('style');
      style.type = 'text/css';
      // Check for IE support (old IE versions)
      if (style.styleSheet) {
        style.styleSheet.cssText = css;
      } else {
        style.appendChild(document.createTextNode(css));
      }
      // Append the style to the document head
      document.head.appendChild(style);
    }",
        css_string
      )
    )

    htmlwidgets::saveWidget(
      widget = pipeline_diagram_with_css,
      file = html_save_path,
      selfcontained = TRUE
    )
    # cleanup dependencies
    unlink(gsub("\\.html", "_files/", html_save_path), recursive = TRUE)
    pipelines_html_files[[html_save_path]] <- html_save_path
  }
  pipelines_html_files <- unlist(pipelines_html_files)
  return(pipelines_html_files)
}

render_mermaid_plots_png <- function(
  pipelines_html_files,
  plots_output_dir
) {
  # https://github.com/rstudio/chromote/issues/178#issue-2534999818
  chromote::set_chrome_args(c(chromote:::default_chrome_args(), "--no-sandbox"))
  # https://github.com/rstudio/chromote/issues/187#issuecomment-2596286873
  options(chromote.headless = "new")

  pipelines_png_files <- list()
  for (pipeline_html_file in pipelines_html_files) {
    png_save_path <- gsub("html", "png", pipeline_html_file)
    webshot2::webshot(
      url = pipeline_html_file,
      file = png_save_path,
      zoom = 2,
      vwidth = 1600,
      vheight = 1200
    )
    img <- imager::load.image(png_save_path)
    img_cropped <- imager::autocrop(img)
    imager::save.image(img_cropped, png_save_path)

    pipelines_png_files[[png_save_path]] <- png_save_path
  }

  # chromote::chromote_info()
  pipelines_png_files <- unlist(pipelines_png_files)
  return(pipelines_png_files)
}

# fix to render tar_mermaid
# https://github.com/rich-iannone/DiagrammeR/issues/475#issue-1412818156
#'  Update the mermaid library in the package
#' @param version A [character] of the desired version (the latest by default)
#' @return See value returned by [download.file]
update_mermaid_js <- function(
  version = "11.8.1"
) {
  destfile <- system.file(
    "htmlwidgets/lib/mermaid/dist/mermaid.slim.min.js",
    package = "DiagrammeR"
  )
  # check current version
  mermaid_js <- readLines(destfile) |> paste0(collapse = "\n")
  if (
    grepl(
      paste0('name:\\"mermaid\\",version:\\"', version, '\\"'),
      mermaid_js
    ) ==
      TRUE
  ) {
    return(TRUE)
  } else {
    url <- "https://cdn.jsdelivr.net/npm/mermaid@version/dist/mermaid.min.js"
    if (version != "") {
      stopifnot(grepl("^[[:digit:]]+\\.[[:digit:]]+\\.[[:digit:]]+$", version))
      version <- paste0("@", version)
    }
    url <- gsub("@version", version, url)
    try(
      download.file(
        url = url,
        destfile = destfile
      )
    )
    return(TRUE)
  }
}
