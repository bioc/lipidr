#' Informative plots to investigate samples
#'
#' `lipidr` supports two types of plots for sample quality checking.\cr\cr
#' `tic` plots a bar chart for total sample intensity.\cr\cr
#' `boxplot` plots a boxplot chart to examine the distribution of values
#' per sample.
#' @param data LipidomicsExperiment object.
#' @param type plot type, either `tic` or `boxplot`. Default is `tic`.
#' @param measure Which measure to use as intensity, usually Area,
#'   Area Normalized or Height. Default is `Area`
#' @param log Whether values should be log2 transformed. Default is `TRUE`
#' @param color The column name of a sample annotation to be used as color
#'
#' @return A ggplot object.
#' @export
#' @examples
#' data(data_normalized)
#'
#' plot_samples(data_normalized, type = "tic", "Area", log = TRUE)
#' plot_samples(data_normalized, type = "tic", "Background", log = FALSE)
#' plot_samples(
#'   data_normalized[, data_normalized$group == "QC"],
#'   type = "boxplot",
#'   measure = "Retention Time", log = FALSE
#' )
plot_samples <- function(data, type = c("tic", "boxplot"),
  measure = "Area", log = TRUE, color=NULL) {
  stopifnot(inherits(data, "LipidomicsExperiment"))
  validObject(data)
  type <- match.arg(type)
  dlong <- to_long_format(data, measure) %>% fix_all_na() 
  measure <- sym(measure)
  if (log) {
    measure <- .check_log(data, measure)
  }
  if (!is.null(color)) {
    color <- sym(color)
  }
  #color <- sym(color)
  if (type == "tic") {
    return(.display_plot(.plot_sample_tic(dlong, measure, color)))
  }

  .display_plot(.plot_sample_boxplot(dlong, measure, color))
}

.plot_sample_tic <- function(dlong, measure, color) {
  ggplot(dlong, aes(Sample, !!measure, fill = !!color)) +
    stat_summary(fun = mean, geom = "bar") +
    facet_wrap(~filename, ncol = 1, scales = "free_y") +
    theme(axis.text.x = element_text(angle = -90, vjust = 0.5)) +
    guides(size = "none")
}

.plot_sample_boxplot <- function(dlong, measure, color) {
  ggplot(dlong, aes(Sample, !!measure, fill = !!color)) + geom_boxplot() +
    facet_wrap(~filename, ncol = 1, scales = "free_y") +
    theme(axis.text.x = element_text(angle = -90, vjust = 0.5)) +
    guides(size = "none")
}

#' Informative plots to investigate lipid classes
#'
#' `lipidr` supports two types of plots for to visualize at lipid classes.\cr\cr
#' `sd` plots a bar chart for standard deviation of a certain measure in each
#' class. This plot type is usually used to look at standard deviations of
#' intensity in each class, but can also be used to look at different measures
#' such as `Retention Time`, to ensure all lipids are eluted within the expected
#' range. To assess instrumental variation apply the function to technical
#' quality control samples. \cr\cr
#' `boxplot` Plots a boxplot chart to examine the distribution of values per
#' class. This plot type is usually used to look at the intensity distribution
#' in each class, but can also be used to look at different measures, such as
#' `Retention Time` or `Background`.
#'
#' @param data LipidomicsExperiment object.
#' @param type plot type, either `boxplot` or `sd`. Default is `boxplot`.
#' @param measure Which measure to plot the distribution of: usually Area,
#'   Area Normalized, Height or Retention Time. Default is `Area`
#' @param log Whether values should be log2 transformed. Default is `TRUE`
#'   (Set FALSE for retention time).
#'
#' @return A ggplot object.
#' @export
#' @examples
#' data(data_normalized)
#'
#' d_qc <- data_normalized[, data_normalized$group == "QC"]
#' plot_lipidclass(d_qc, "sd", "Area", log = TRUE)
#' plot_lipidclass(d_qc, "sd", "Retention Time", log = FALSE)
#' plot_lipidclass(d_qc, "boxplot", "Area", log = TRUE)
#' plot_lipidclass(d_qc, "boxplot", "Retention Time", log = FALSE)
plot_lipidclass <- function(data, type = c("boxplot", "sd"),
  measure = "Area", log = TRUE) {
  stopifnot(inherits(data, "LipidomicsExperiment"))
  validObject(data)
  type <- match.arg(type)
  dlong <- to_long_format(data, measure) %>% fix_all_na() 
  
  measure <- sym(measure)
  if (log) {
    measure <- .check_log(data, measure)
  }
  if (type == "sd") {
    return(.display_plot(.plot_class_sd(dlong, measure)))
  }

  .display_plot(.plot_class_boxplot(dlong, measure))
}

.plot_class_sd <- function(dlong, measure) {
  ggplot(dlong, aes(Class, !!measure, fill = Class)) +
    stat_summary(fun = sd, geom = "bar") +
    facet_wrap(~filename, scales = "free_x") +
    theme(axis.text.x = element_text(angle = -90, vjust = 0.5)) +
    ylab(paste("SD of", as_label(measure)))
}

.plot_class_boxplot <- function(dlong, measure) {
  ggplot(dlong, aes(Class, !!measure, fill = Class)) +
    geom_boxplot() +
    facet_wrap(~filename, scales = "free_x") +
    theme(axis.text.x = element_text(angle = -90, vjust = 0.5))
}

#' Plot logFC of lipids per class showing chain information
#'
#' Plot a chart of (log2) fold changes of lipids per class showing chain
#' lengths and unsaturations. If multiple molecules with the same total chain
#' length and unsaturation are present in the dataset, the `measure` is averaged,
#' and the number of molecules is indicated on the plot.
#'
#' @param de_results Output of [de_analysis()].
#' @param measure Which measure to plot the distribution of: logFC, P.Value,
#'   Adj.P.Val. Default is `logFC`
#' @param contrast Which comparison to plot. if not provided, defaults to the
#'   the first comparison.
#'
#' @return A ggplot object.
#' @export
#' @examples
#' data(data_normalized)
#' de_results <- de_analysis(
#'   data_normalized,
#'   HighFat_water - NormalDiet_water,
#'   measure = "Area"
#' )
#' plot_chain_distribution(de_results)
plot_chain_distribution <- function(de_results, contrast = NULL,
                                    measure = "logFC") {
  if (is.null(contrast)) {
    use_contrast <- de_results$contrast[[1]]
  } else {
    use_contrast <- contrast
  }
  measure <- sym(measure)

  de_results <- de_results$Molecule %>%
    annotate_lipids() %>%
    filter(!istd) %>%
    .left_join_silent(de_results)

  de_results <- de_results %>%
    filter(contrast == use_contrast) %>%
    select(total_cl, total_cs, !!measure, Class) %>%
    mutate_at(vars(total_cl, total_cs), factor) %>%
    group_by(Class, total_cl, total_cs) %>%
    summarise(!!measure := mean(!!measure), nmolecules = n())

  p <- ggplot(de_results, aes(total_cs, total_cl, fill = !!measure)) + geom_tile() +
    facet_wrap(~Class) +
    xlab("Total chain unsaturation") + ylab("Total chain length") +
    scale_fill_gradient2(midpoint = 0) +
    geom_text(aes(label = ifelse(nmolecules > 1, nmolecules, "")))

  .display_plot(p)
}

#' Plot a regulation trend line  between logFC and chain annotation
#'
#' Fit and plot a regression line of (log2) fold changes and total chain
#' lengths or unsaturations. If multiple comparisons are included, one
#' regression is plotted for each.
#'
#' @param de_results Output of [de_analysis]().
#' @param annotation Whether to fit trend line against chain `length` or `unsat`.
#'
#' @return A ggplot object.
#' @export
#' @examples
#' data(data_normalized)
#' de_results <- de_analysis(
#'   data_normalized,
#'   HighFat_water - NormalDiet_water,
#'   NormalDiet_DCA - NormalDiet_water,
#'   measure = "Area"
#' )
#' plot_trend(de_results, "length")
plot_trend <- function(de_results, annotation = c("length", "unsat")) {
  annotation <- match.arg(annotation)
  x <- rlang::sym(ifelse(annotation == "length", "total_cl", "total_cs"))
  x_lab <- ifelse(
    annotation == "length", "Total chain length", "Total unsaturated bonds"
  )
  x_breaks <- if (annotation == "length") seq(10, 80, 2) else seq(0, 12, 1)


  ggplot(de_results, aes(!!x, logFC, color = contrast)) +
    geom_hline(color = "black", yintercept = 0, lty = 2) +
    geom_smooth(alpha = 0.2) +
    labs(x = x_lab, y = "logFC") +
    scale_x_continuous(breaks = x_breaks) +
    theme(legend.position = "bottom")
}

#' Informative plots to investigate individual lipid molecules
#'
#' `lipidr` supports three types of plots for to visualize at lipid molecules.
#' \cr\cr
#' `cv` plots a bar chart for coefficient of variation of lipid molecules. This
#' plot type is usually used to investigate the CV in lipid intensity or
#' retention time, in QC samples. \cr\cr
#' `sd` plots a bar chart for standard deviations of a certain measure in each
#' lipid. This plot type is usually used to look at standard deviation of
#' intensity for each lipid, but can also be used to look at different
#' measures such as `Retention Time`, to ensure all lipids elute within
#' expected range. \cr\cr
#' `boxplot` plots a boxplot chart to examine the distribution of values per
#' lipid. This plot type is usually used to look at intensity distribution
#' for each lipid, but can also be used to look at different measures, such as
#' `Retention Time` or `Background`.
#'
#' @param data LipidomicsExperiment object.
#' @param type plot type, either `cv`, `sd` or `boxplot`. Default is `cv`.
#' @param measure Which measure to plot the distribution of: usually Area,
#'   Area Normalized or Height. Default is `Area`
#' @param log Whether values should be log2 transformed
#'   (Set FALSE for retention time). Default is `TRUE`
#' @param color The column name of a row annotation to be used as color
#'
#' @return A ggplot object.
#' @export
#' @examples
#' data(data_normalized)
#' d_qc <- data_normalized[, data_normalized$group == "QC"]
#'
#' # plot the variation in intensity and retention time of all measured
#' #   lipids in QC samples
#' plot_molecules(d_qc, "cv", "Area")
#' plot_molecules(d_qc, "cv", "Retention Time", log = FALSE)
#'
#' # plot the variation in intensity, RT of ISTD (internal standards)
#' #   in QC samples
#' d_istd_qc <- data_normalized[
#'   rowData(data_normalized)$istd,
#'   data_normalized$group == "QC"
#' ]
#' plot_molecules(d_istd_qc, "sd", "Area")
#' plot_molecules(d_istd_qc, "sd", "Retention Time", log = FALSE)
#'
#' plot_molecules(d_istd_qc, "boxplot")
#' plot_molecules(d_istd_qc, "boxplot", "Retention Time", log = FALSE)
plot_molecules <- function(data, type = c("cv", "sd", "boxplot"),
  measure = "Area", log = TRUE, color = "Class") {
  stopifnot(inherits(data, "LipidomicsExperiment"))
  validObject(data)
  type <- match.arg(type)
  dlong <- to_long_format(data, measure) %>% fix_all_na()
  measure <- sym(measure)
  if (log) {
    measure <- .check_log(data, measure)
  }
  if (!is.null(color)) {
    color <- sym(color)
  }
  mol_dimname = metadata(data)$dimnames[[1]]
  if (type == "cv") {
    return(.display_plot(.plot_molecule_cv(dlong, measure, color, mol_dimname)))
  }
  else if (type == "sd") {
    return(.display_plot(.plot_molecule_sd(dlong, measure, color, mol_dimname)))
  }

  .display_plot(.plot_molecule_boxplot(dlong, measure, color, mol_dimname))
}

.plot_molecule_sd <- function(dlong, measure, color, mol_dimname) {
  molecule_names = setNames(dlong$Molecule, as.character(dlong[[mol_dimname]]))
  ggplot(
    dlong,
    aes(!!sym(mol_dimname), !!measure, fill = !!color, color = !!color)
  ) +
    stat_summary(fun = sd, geom = "bar") +
    scale_x_discrete(labels= ~ molecule_names[as.character(.x)]) +
    facet_wrap(~filename, scales = "free_y") + coord_flip() +
    theme(axis.text.x = element_text(angle = -90, vjust = 0.5)) +
    ylab(paste("SD of", as_label(measure)))
}

.plot_molecule_cv <- function(dlong, measure, color, mol_dimname) {
  molecule_names = setNames(dlong$Molecule, as.character(dlong[[mol_dimname]]))
  ggplot(
    dlong,
    aes(!!sym(mol_dimname), !!measure, fill = !!color, color = !!color)
  ) +
    stat_summary(fun = .cv, geom = "bar") + coord_flip() +
    scale_x_discrete(labels= ~ molecule_names[as.character(.x)]) +
    facet_wrap(~filename, scales = "free_y") +
    theme(axis.text.x = element_text(angle = -90, vjust = 0.5)) +
    ylab(paste("%CV of", as_label(measure)))
}

.plot_molecule_boxplot <- function(dlong, measure, color, mol_dimname) {
  molecule_names = setNames(dlong$Molecule, as.character(dlong[[mol_dimname]]))
  ggplot(
    dlong,
    aes(!!sym(mol_dimname), !!measure, fill = !!color, color = !!color)
  ) +
    geom_boxplot(outlier.size = 0.5, outlier.alpha = 0.3) + coord_flip() +
    scale_x_discrete(labels= ~ molecule_names[as.character(.x)]) +
    facet_wrap(~filename, scales = "free_y") +
    theme(axis.text.x = element_text(angle = -90, vjust = 0.5))
}

.display_plot <- function(p) {
  if (.myDataEnv$interactive) {
    p <- plotly::ggplotly(p)
  }
  return(p)
}



# colnames used in plot_chain_distribution
utils::globalVariables(c("nmolecules"))
