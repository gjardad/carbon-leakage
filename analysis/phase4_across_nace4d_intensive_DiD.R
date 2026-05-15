###############################################################################
# phase4_across_nace4d_intensive_DiD.R
#
# PURPOSE
#   Buyer-level analog of phase4_within_nace4d_reallocation_did.R: does the
#   marginal B2B dollar flow away from ETS-treated NACE4d (2005 event) or
#   away from high-shortage ETS-NACE4d (2017 event)?
#
#   Unit of observation:  buyer x NACE4d x year
#   Outcome:              share_jnt = spend(j, n, t) / total spend(j, t)
#                         where total = buyer j's total B2B spend across all
#                         sellers (including those without classifiable NACE4d)
#
#   Spec (static DiD):
#       share_jnt = alpha_jn + delta_t + beta * treatment_n * post_t + eps
#       buyer x NACE4d FE + year FE, SE clustered on cell (buyer x NACE4d).
#
#   Two events, five variants:
#       - 2005:                 treatment_n = ets_treated_n (binary).
#                               Sample: NACE4d the buyer bought from in 2002-04
#                               (ETS-treated and non-ETS pooled).
#                               Regression window: 2002-22.
#       - 2017-tight:           treatment_n = high_omega_n (median split among ETS).
#                               Sample: ETS-treated NACE4d the buyer bought from
#                               in 2015-16. Regression window: 2013-22.
#       - 2017-sym:             same as 2017-tight, regression window 2012-22.
#       - 2017-long:            same as 2017-tight, regression window 2002-22.
#       - 2017-topq-vs-nonets:  treatment_n = 1{NACE4d in top quartile of omega
#                               among classifiable ETS-NACE4d}; control = non-ETS.
#                               ETS-NACE4d below the Q75 omega threshold are
#                               dropped from the sample. Regression window 2012-22.
#
#   omega_n (NACE4d-level shortage / total cost):
#       omega_n = sum_{f in N, t in 2015-16} shortage_ft
#               / sum_{f in N, t in 2015-16} total_cost_ft
#   built from firm_exposure restricted to 2015-16.  Sectors with < 2 firm-
#   years of pre-period coverage are dropped (consistent with the descriptive
#   phase4_across_nace4d_intensive_by_shortage.R rule).
#
#   Event-study figure: tau in [-5, +5] with tau = -1 as reference.
#       - 2005 event uses regression window 2002-2010 (tau in [-3, +5];
#         B2B panel starts in 2002).
#       - 2017 event uses regression window 2012-2022 (tau in [-5, +5]),
#         i.e. the 2017-sym window.
#
#   Two FE specifications per regression:
#       - base        : cell_id + year FE.
#       - nace2dxyear : cell_id + NACE2d x year FE.  Absorbs sector-aggregate
#                       (NACE2d-by-year) demand cycles.  Identification moves
#                       to within-NACE2d-year cross-NACE4d variation in
#                       high_omega -- so beta only loads on differential
#                       behavior of high-omega vs low-omega NACE4d that
#                       coexist within the same NACE2d group.
#
# NOTE on the RTM concern (see conversation 2026-05-15)
#   This is the supplier-NACE4d-shortage cut, NOT the buyer-exposure cut.
#   Treatment is a NACE4d attribute built from EUTL data on sellers, so the
#   regressor is not constructed from the buyer's spending behavior, and the
#   regression-to-the-mean trap that would affect a buyer-exposure DiD does
#   not bite here.
#
# OUTPUTS (output_<machine>/figures/, output_<machine>/tables/)
#   - phase4_across_nace4d_intensive_DiD_coefs.csv         (diagnostic, all variants x FE specs)
#   - phase4_across_nace4d_intensive_DiD_coefs.tex         (diagnostic, raw xtable)
#   - phase4_across_nace4d_intensive_DiD_paper.tex         (paper-ready: 2 events x 2 FE specs)
#   - phase4_across_nace4d_intensive_DiD_eventstudy.csv
#   - phase4_across_nace4d_intensive_DiD.{png,pdf}         (paper-ready event-study)
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(fixest)
  library(xtable)
})

set.seed(20260515)

YEAR_LO        <- 2002L     # B2B panel starts in 2002
YEAR_HI        <- 2022L
OMEGA_YEARS    <- 2015L:2016L   # NACE4d omega-construction window for 2017 event
MIN_FYRS_OMEGA <- 2L            # require >= 2 firm-years in OMEGA_YEARS per NACE4d

# Static-DiD variants
VARIANTS <- list(
  "2005" = list(
    treat_year      = 2005L,
    treatment_kind  = "ets",          # binary ETS-treated vs non-ETS
    pre_years       = 2002L:2004L,    # cell-inclusion window
    reg_lo          = 2002L, reg_hi = 2022L
  ),
  "2017-tight" = list(
    treat_year      = 2017L,
    treatment_kind  = "omega",        # binary high-omega within ETS
    pre_years       = 2015L:2016L,
    reg_lo          = 2013L, reg_hi = 2022L
  ),
  "2017-sym" = list(
    treat_year      = 2017L,
    treatment_kind  = "omega",
    pre_years       = 2015L:2016L,
    reg_lo          = 2012L, reg_hi = 2022L
  ),
  "2017-long" = list(
    treat_year      = 2017L,
    treatment_kind  = "omega",
    pre_years       = 2015L:2016L,
    reg_lo          = 2002L, reg_hi = 2022L
  ),
  # Heterogeneity for 2017: top-quartile omega (most exposed ETS NACE4d) vs
  # non-ETS NACE4d. Drops ETS NACE4d below the Q75 omega threshold from the
  # sample so the contrast is sharp.
  "2017-topq-vs-nonets" = list(
    treat_year      = 2017L,
    treatment_kind  = "top_q_omega_vs_nonets",
    pre_years       = 2015L:2016L,
    reg_lo          = 2012L, reg_hi = 2022L
  ),
  # 2017 binary ETS-treated vs non-ETS (same construction as 2005 but with
  # treat_year = 2017 and pre = 2015-16). Headline 2017 contrast for the
  # paper table.
  "2017-ets-vs-nonets" = list(
    treat_year      = 2017L,
    treatment_kind  = "ets",
    pre_years       = 2015L:2016L,
    reg_lo          = 2012L, reg_hi = 2022L
  )
)

# Event-study windows (tau range and regression window). One entry per
# table column so the event-study figure mirrors the paper table 1:1.
ES_SPECS <- list(
  "2005-ets" = list(
    treat_year     = 2005L,
    treatment_kind = "ets",
    pre_years      = 2002L:2004L,
    reg_lo         = 2002L, reg_hi = 2010L,
    tau_lo         = -3L,   tau_hi = 5L
  ),
  "2017-ets" = list(
    treat_year     = 2017L,
    treatment_kind = "ets",
    pre_years      = 2015L:2016L,
    reg_lo         = 2012L, reg_hi = 2022L,
    tau_lo         = -5L,   tau_hi = 5L
  ),
  "2017-omega" = list(
    treat_year     = 2017L,
    treatment_kind = "omega",
    pre_years      = 2015L:2016L,
    reg_lo         = 2012L, reg_hi = 2022L,
    tau_lo         = -5L,   tau_hi = 5L
  ),
  "2017-topq" = list(
    treat_year     = 2017L,
    treatment_kind = "top_q_omega_vs_nonets",
    pre_years      = 2015L:2016L,
    reg_lo         = 2012L, reg_hi = 2022L,
    tau_lo         = -5L,   tau_hi = 5L
  )
)

# FE specifications -- each regression below runs once per FE spec.
# Diagnostic CSV keeps all three. The paper table and figure use
# `nace3dxyear` (set below as PAPER_FE_SPEC) -- the most granular sector-
# cycle control that still leaves identification on the 2017 sample.
FE_SPECS <- list(
  "base"        = "cell_id + year",
  "nace2dxyear" = "cell_id + nace2d^year",
  "nace3dxyear" = "cell_id + nace3d^year"
)

# ---------------------------------------------------------------------------
# Helper: write a data.table as a clean LaTeX tabular
# ---------------------------------------------------------------------------
write_tex_table <- function(dt, file, digits = 4, caption = NULL) {
  x <- xtable(as.data.frame(dt), digits = digits, caption = caption)
  print(x, file = file, include.rownames = FALSE, booktabs = TRUE,
        caption.placement = "top",
        sanitize.colnames.function = function(s) gsub("_", "\\\\_", s, fixed = TRUE),
        sanitize.text.function    = function(s) gsub("_", "\\\\_", s, fixed = TRUE))
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# 1. Load data
# ---------------------------------------------------------------------------
cat("Loading data...\n")

load(file.path(PROC_DATA, "b2b_selected_sample.RData"))
b2b <- as.data.table(df_b2b_selected_sample)
rm(df_b2b_selected_sample)
setnames(b2b,
         old = c("vat_i_ano", "vat_j_ano", "corr_sales_ij"),
         new = c("seller", "buyer", "sales"),
         skip_absent = TRUE)
b2b <- b2b[year %between% c(YEAR_LO, YEAR_HI) & !is.na(sales) & sales > 0,
           .(seller = as.character(seller),
             buyer  = as.character(buyer),
             year   = as.integer(year),
             sales)]

load(file.path(PROC_DATA, "annual_accounts_selected_sample.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample)[, .(
  vat = as.character(vat_ano),
  year = as.integer(year),
  nace4d = substr(nace5d, 1, 4)
)]
rm(df_annual_accounts_selected_sample)
aa <- unique(aa[!is.na(nace4d) & nace4d != ""])

load(file.path(OUT_DATA, "phase3_firm_exposure.RData"))
fe <- as.data.table(firm_exposure)[, .(vat = as.character(vat),
                                       year = as.integer(year),
                                       shortage, total_cost,
                                       nace4d)]
rm(firm_exposure)

# ETS-treated NACE4d = any NACE4d containing an in-sample firm in firm_exposure
ets_treated_nace4d <- unique(fe$nace4d[!is.na(fe$nace4d) & fe$nace4d != ""])
cat(sprintf("  ETS-treated NACE4d: %d\n", length(ets_treated_nace4d)))

# Attach seller NACE4d to b2b (per year, using AA panel)
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
cat(sprintf("  b2b rows: %d   (with NACE4d: %d)\n",
            nrow(b2b),
            nrow(b2b[!is.na(seller_nace4d)])))

# ---------------------------------------------------------------------------
# 2. NACE4d-level omega from 2015-16 firm_exposure
# ---------------------------------------------------------------------------
cat("\nBuilding NACE4d-level omega (2015-16)...\n")

fe_omega <- fe[year %in% OMEGA_YEARS &
               !is.na(shortage) & !is.na(total_cost) & total_cost > 0 &
               !is.na(nace4d) & nace4d != ""]
omega_nace <- fe_omega[, .(n_firm_yrs = .N,
                           sum_short  = sum(shortage),
                           sum_cost   = sum(total_cost)),
                       by = nace4d]
omega_nace <- omega_nace[n_firm_yrs >= MIN_FYRS_OMEGA & sum_cost > 0]
omega_nace[, omega := sum_short / sum_cost]

# Median split among ETS-treated NACE4d that have classifiable omega
med_omega <- median(omega_nace$omega, na.rm = TRUE)
omega_nace[, high_omega := as.integer(omega > med_omega)]
# Top-quartile split (top 25% of omega among classifiable ETS-treated NACE4d)
q75_omega <- quantile(omega_nace$omega, 0.75, na.rm = TRUE)
omega_nace[, top_q_omega := as.integer(omega > q75_omega)]
cat(sprintf("  NACE4d with classifiable omega: %d  (median = %.4f, Q75 = %.4f)\n",
            nrow(omega_nace), med_omega, q75_omega))
cat(sprintf("  high_omega == 1: %d   high_omega == 0: %d\n",
            sum(omega_nace$high_omega == 1L),
            sum(omega_nace$high_omega == 0L)))
cat(sprintf("  top_q_omega == 1: %d   classifiable ETS but not top_q: %d\n",
            sum(omega_nace$top_q_omega == 1L),
            sum(omega_nace$top_q_omega == 0L)))

# Long-form NACE4d attribute table
nace_attr <- data.table(nace4d = unique(b2b$seller_nace4d[!is.na(b2b$seller_nace4d)]))
nace_attr[, ets_treated := as.integer(nace4d %in% ets_treated_nace4d)]
nace_attr <- merge(nace_attr,
                   omega_nace[, .(nace4d, omega, high_omega, top_q_omega)],
                   by = "nace4d", all.x = TRUE)

# ---------------------------------------------------------------------------
# 3. Build buyer-NACE4d-year panel
# ---------------------------------------------------------------------------
# For each (buyer, year), total spend across ALL sellers (denominator).
# For each (buyer, NACE4d, year) with NACE4d in b2b, sum sales (numerator).
# share_jnt = numerator / denominator.
# ---------------------------------------------------------------------------
cat("\nBuilding buyer-NACE4d-year aggregates...\n")

buyer_year_total <- b2b[, .(total_spend = sum(sales)),
                        by = .(buyer, year)]

buyer_nace_year <- b2b[!is.na(seller_nace4d) & seller_nace4d != "",
                       .(spend = sum(sales)),
                       by = .(buyer, nace4d = seller_nace4d, year)]
cat(sprintf("  unique (buyer, nace4d, year): %d\n", nrow(buyer_nace_year)))

# ---------------------------------------------------------------------------
# 4. Helper: build one (cell x year) panel for a given variant
# ---------------------------------------------------------------------------
build_panel <- function(spec) {
  # Cell inclusion: (buyer, NACE4d) pairs where buyer bought from NACE4d
  # in any pre-year. NACE4d sample depends on treatment_kind.
  if (spec$treatment_kind == "ets") {
    eligible_nace <- nace_attr$nace4d                       # ETS-treated U non-ETS
  } else if (spec$treatment_kind == "omega") {
    eligible_nace <- nace_attr[!is.na(high_omega), nace4d]  # ETS-treated with classifiable omega
  } else if (spec$treatment_kind == "top_q_omega_vs_nonets") {
    # Top-quartile omega (among classifiable ETS-NACE4d) PLUS all non-ETS
    eligible_nace <- nace_attr[(!is.na(top_q_omega) & top_q_omega == 1L) |
                               ets_treated == 0L, nace4d]
  } else {
    stop("Unknown treatment_kind: ", spec$treatment_kind)
  }

  pre_cells <- buyer_nace_year[year %in% spec$pre_years &
                               nace4d %in% eligible_nace &
                               spend > 0,
                               .(buyer, nace4d)]
  pre_cells <- unique(pre_cells)

  # Expand to (cell, year) panel over the regression window
  panel <- pre_cells[, .(year = spec$reg_lo:spec$reg_hi),
                     by = .(buyer, nace4d)]

  # Attach numerator (zero-filled) and denominator
  panel <- merge(panel, buyer_nace_year,
                 by = c("buyer", "nace4d", "year"), all.x = TRUE)
  panel[is.na(spend), spend := 0]
  panel <- merge(panel, buyer_year_total,
                 by = c("buyer", "year"), all.x = TRUE)
  panel <- panel[!is.na(total_spend) & total_spend > 0]
  panel[, share := spend / total_spend]

  # Attach treatment label
  panel <- merge(panel, nace_attr[, .(nace4d, ets_treated, high_omega, top_q_omega)],
                 by = "nace4d", all.x = TRUE)
  if (spec$treatment_kind == "ets") {
    panel[, treatment := ets_treated]
  } else if (spec$treatment_kind == "omega") {
    panel[, treatment := high_omega]
  } else if (spec$treatment_kind == "top_q_omega_vs_nonets") {
    # 1 if top-quartile omega ETS NACE4d; 0 if non-ETS NACE4d
    panel[, treatment := fifelse(!is.na(top_q_omega) & top_q_omega == 1L, 1L,
                                 fifelse(ets_treated == 0L, 0L, NA_integer_))]
    panel <- panel[!is.na(treatment)]
  }
  panel[, post       := as.integer(year >= spec$treat_year)]
  panel[, cell_id    := paste(buyer, nace4d, sep = "::")]
  panel[, nace2d     := substr(nace4d, 1L, 2L)]
  panel[, nace3d     := substr(nace4d, 1L, 3L)]
  panel[, tau        := year - spec$treat_year]
  panel
}

# ---------------------------------------------------------------------------
# 5. Static DiD for each variant
# ---------------------------------------------------------------------------
cat("\n=== Static DiD ===\n")

static_results <- list()
for (label in names(VARIANTS)) {
  cat(sprintf("\n--- variant: %s ---\n", label))
  spec <- VARIANTS[[label]]
  d    <- build_panel(spec)
  cat(sprintf("  cells: %d   buyers: %d   nace4d: %d   panel rows: %d\n",
              uniqueN(d$cell_id), uniqueN(d$buyer), uniqueN(d$nace4d),
              nrow(d)))

  for (fe_lab in names(FE_SPECS)) {
    cat(sprintf("  > FE spec: %s\n", fe_lab))
    form <- as.formula(paste0("share ~ i(post, treatment, ref = 0) | ",
                              FE_SPECS[[fe_lab]]))
    fit <- feols(form, data = d, cluster = ~ cell_id)
    print(summary(fit))

    ct <- as.data.table(coeftable(fit), keep.rownames = "term")
    static_results[[paste(label, fe_lab, sep = "::")]] <- cbind(
      variant       = label,
      fe_spec       = fe_lab,
      n_obs         = nobs(fit),
      n_cells       = uniqueN(d$cell_id),
      n_buyers      = uniqueN(d$buyer),
      n_nace4d      = uniqueN(d$nace4d),
      ct
    )
  }
}

coefs <- rbindlist(static_results, use.names = TRUE, fill = TRUE)
setnames(coefs,
         old = c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
         new = c("estimate", "std_error", "t_stat", "p_value"),
         skip_absent = TRUE)
fwrite(coefs,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_intensive_DiD_coefs.csv"))
write_tex_table(coefs,
                file.path(OUTPUT_TAB,
                          "phase4_across_nace4d_intensive_DiD_coefs.tex"),
                caption = "Across-NACE4d intensive-margin DiD on buyer portfolio share. 2005 event: binary ETS-treated vs non-ETS. 2017 variants: high-omega vs low-omega within ETS-treated.")

# ---------------------------------------------------------------------------
# 5b. Paper-ready table -- 3 rows (coef / SE / N) x 4 columns
# (2005 ETS-vs-non-ETS, 2017 ETS-vs-non-ETS, 2017 high-vs-low,
# 2017 top-quartile-vs-non-ETS). Single FE spec (cell + NACE2d x year).
# Multi-level column header groups the three 2017 columns.
# ---------------------------------------------------------------------------
paper_columns <- list(
  list(variant = "2005",                group = "2005 Treatment",
       label  = ""),                      # 2005 column has no sub-label
  list(variant = "2017-ets-vs-nonets",  group = "2017 Treatment",
       label  = "ETS vs non-ETS"),
  list(variant = "2017-sym",            group = "2017 Treatment",
       label  = "High vs Low Exposure"),
  list(variant = "2017-topq-vs-nonets", group = "2017 Treatment",
       label  = "Q1 Exposure vs non-ETS")
)
PAPER_FE_SPEC <- "nace3dxyear"   # single FE spec shown in the paper table + figure

stars_for <- function(p) {
  ifelse(p < 0.001, "$^{***}$",
  ifelse(p < 0.01,  "$^{**}$",
  ifelse(p < 0.05,  "$^{*}$",
  ifelse(p < 0.10,  "$^{\\dagger}$",
                    ""))))
}
format_n <- function(n) {
  if (n >= 1e6) sprintf("%.1fM", n / 1e6)
  else if (n >= 1e3) sprintf("%.0fk", n / 1e3)
  else format(n, big.mark = ",")
}

# Pull the cell for each column under the paper FE spec.
col_cells <- lapply(paper_columns, function(c) {
  row <- coefs[coefs$variant == c$variant & coefs$fe_spec == PAPER_FE_SPEC, ]
  if (nrow(row) != 1L) {
    list(coef = "--", se = "--", n = "--")
  } else {
    list(
      coef = paste0(sprintf("%.4f", row$estimate), stars_for(row$p_value)),
      se   = sprintf("(%.4f)", row$std_error),
      n    = format_n(row$n_obs)
    )
  }
})

# Build the grouped header. The first column belongs to "2005 Treatment";
# columns 2-4 are spanned by "2017 Treatment".
groups <- vapply(paper_columns, `[[`, character(1), "group")
labels <- vapply(paper_columns, `[[`, character(1), "label")
# Find spans of consecutive identical group names.
group_runs <- rle(groups)
header_cells <- character(0)
col_idx      <- 1L
cmidrules    <- character(0)
for (i in seq_along(group_runs$lengths)) {
  span <- group_runs$lengths[i]
  name <- group_runs$values[i]
  if (span == 1L) {
    header_cells <- c(header_cells, name)
  } else {
    header_cells <- c(header_cells,
                      sprintf("\\multicolumn{%d}{c}{%s}", span, name))
    cmidrules <- c(cmidrules,
                   sprintf("\\cmidrule(lr){%d-%d}",
                           col_idx + 1L,             # +1 for leading column
                           col_idx + span))
  }
  col_idx <- col_idx + span
}

header_row1 <- paste0(" & ", paste(header_cells, collapse = " & "), " \\\\")
header_row2 <- paste0(" & ", paste(labels,        collapse = " & "), " \\\\")

coef_row <- paste0("Coefficient & ",
                   paste(vapply(col_cells, `[[`, character(1), "coef"),
                         collapse = " & "), " \\\\")
se_row   <- paste0("Std. error & ",
                   paste(vapply(col_cells, `[[`, character(1), "se"),
                         collapse = " & "), " \\\\")
n_row    <- paste0("$N$ & ",
                   paste(vapply(col_cells, `[[`, character(1), "n"),
                         collapse = " & "), " \\\\")

paper_tex <- c(
  "% Requires \\usepackage{makecell,booktabs} in main.tex",
  "% Across-NACE4d intensive-margin DiD: headline static-DiD coefficients.",
  sprintf("\\begin{tabular}{l%s}", paste(rep("c", length(paper_columns)),
                                         collapse = "")),
  "\\toprule",
  header_row1,
  if (length(cmidrules) > 0) paste(cmidrules, collapse = "") else NULL,
  header_row2,
  "\\midrule",
  coef_row,
  se_row,
  n_row,
  "\\bottomrule",
  "\\end{tabular}",
  "% Notes: Outcome is buyer's share of total B2B spend directed at NACE4d $n$ in year $t$.",
  "% Unit of observation is buyer $\\times$ NACE4d $\\times$ year. Cell = buyer $\\times$ NACE4d.",
  "% Specification: $\\text{share}_{jnt} = \\alpha_{jn} + \\gamma_{s(n),t} + \\beta \\cdot \\mathrm{treatment}_n \\times \\mathrm{post}_t + \\varepsilon_{jnt}$, with cell FE $\\alpha_{jn}$ (buyer $\\times$ NACE4d) and NACE3d $\\times$ year FE $\\gamma_{s(n),t}$.",
  "% Cluster-robust standard errors in parentheses, clustered at the cell (buyer $\\times$ NACE4d) level.",
  "% $\\omega_n = \\sum_{f \\in n,\\, t \\in 2015\\text{--}16} \\mathrm{shortage}_{ft} / \\sum \\mathrm{total\\_cost}_{ft}$, aggregated from firm-level EUTL data to NACE4d.",
  "% High vs Low Exposure uses the median split of $\\omega$ among ETS-treated NACE4d with $\\geq 2$ firm-years of 2015--16 coverage. Q1 Exposure = top quartile of the same distribution. The Q1-vs-non-ETS column drops ETS NACE4d below the Q75 threshold.",
  "% 2005 Treatment uses pre = 2002--04, post = 2005--22, regression window 2002--22. 2017 Treatment uses pre = 2015--16, post = 2017--22, regression window 2012--22.",
  "% Significance: $^{\\dagger}\\,p<0.10$, $^{*}\\,p<0.05$, $^{**}\\,p<0.01$, $^{***}\\,p<0.001$."
)
# Drop the conditional NULL line if no cmidrules were generated.
paper_tex <- paper_tex[!sapply(paper_tex, is.null)]
writeLines(paper_tex,
           file.path(OUTPUT_TAB,
                     "phase4_across_nace4d_intensive_DiD_paper.tex"))

# ---------------------------------------------------------------------------
# 6. Event-study (per event), tau in [-5, +5] with reference tau = -1
# ---------------------------------------------------------------------------
cat("\n=== Event-study ===\n")

es_results <- list()
for (label in names(ES_SPECS)) {
  cat(sprintf("\n--- event-study: %s ---\n", label))
  spec <- ES_SPECS[[label]]
  d    <- build_panel(spec)
  d    <- d[tau %between% c(spec$tau_lo, spec$tau_hi)]
  cat(sprintf("  cells: %d   panel rows: %d   tau range: [%d, %d]\n",
              uniqueN(d$cell_id), nrow(d), spec$tau_lo, spec$tau_hi))

  for (fe_lab in names(FE_SPECS)) {
    cat(sprintf("  > FE spec: %s\n", fe_lab))
    form <- as.formula(paste0("share ~ i(tau, treatment, ref = -1) | ",
                              FE_SPECS[[fe_lab]]))
    fit <- feols(form, data = d, cluster = ~ cell_id)
    print(summary(fit))

    ct <- as.data.table(coeftable(fit), keep.rownames = "term")
    ct[, tau := as.integer(sub(".*tau::(-?[0-9]+).*", "\\1", term))]
    ct[, event   := label]
    ct[, fe_spec := fe_lab]
    es_results[[paste(label, fe_lab, sep = "::")]] <- ct
  }
}

es_coefs <- rbindlist(es_results, use.names = TRUE, fill = TRUE)
setnames(es_coefs,
         old = c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
         new = c("estimate", "std_error", "t_stat", "p_value"),
         skip_absent = TRUE)
es_coefs[, ci_lo := estimate - 1.96 * std_error]
es_coefs[, ci_hi := estimate + 1.96 * std_error]

# Add the reference period (tau = -1, estimate = 0) explicitly for plotting,
# one row per (event, fe_spec).
ref_rows <- rbindlist(lapply(names(ES_SPECS), function(lab) {
  rbindlist(lapply(names(FE_SPECS), function(fl) {
    data.table(event = lab, fe_spec = fl,
               term = "tau::-1:treatment",
               tau = -1L,
               estimate = 0, std_error = NA_real_,
               t_stat = NA_real_, p_value = NA_real_,
               ci_lo = 0, ci_hi = 0)
  }))
}))
es_coefs_plot <- rbind(es_coefs[, .(event, fe_spec, term, tau,
                                    estimate, std_error, t_stat, p_value,
                                    ci_lo, ci_hi)],
                       ref_rows,
                       use.names = TRUE)
setorder(es_coefs_plot, event, fe_spec, tau)

fwrite(es_coefs_plot,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_intensive_DiD_eventstudy.csv"))

# ---------------------------------------------------------------------------
# 7. Event-study figure
# ---------------------------------------------------------------------------
event_lab_lookup <- list(
  "2005-ets"   = "2005: ETS-treated vs non-ETS",
  "2017-ets"   = "2017: ETS-treated vs non-ETS",
  "2017-omega" = "2017: high-ω vs low-ω (within ETS)",
  "2017-topq"  = "2017: Q1-ω vs non-ETS"
)
# Paper figure shows only the PAPER_FE_SPEC specification (the one with
# absorbed sector-aggregate cycles, i.e. the most credible pre-trends).
es_coefs_paper <- es_coefs_plot[fe_spec == PAPER_FE_SPEC]
es_coefs_paper[, event_lab := factor(unlist(event_lab_lookup[event]),
                                     levels = unlist(event_lab_lookup))]

p <- ggplot(es_coefs_paper,
            aes(x = tau, y = estimate)) +
  geom_hline(yintercept = 0, linetype = "dotted", color = "grey40") +
  geom_vline(xintercept = -0.5, linetype = "dotted", color = "grey40") +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                width = 0.15, color = "#1f77b4") +
  geom_point(size = 2.2, color = "#1f77b4") +
  facet_wrap(~ event_lab, ncol = 2, scales = "free") +
  labs(x = expression(tau ~ "(years from treatment)"),
       y = expression(beta[tau])) +
  theme_classic(base_size = 12) +
  theme(strip.text       = element_text(face = "bold"),
        strip.background = element_rect(fill = "grey95", color = "grey80"),
        panel.border     = element_rect(color = "grey80", fill = NA))

# Use Cairo to embed Unicode (ω, ×) reliably across devices.
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_DiD.png"),
       p, width = 10, height = 7.5, dpi = 200,
       type = "cairo")
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_DiD.pdf"),
       p, width = 10, height = 7.5,
       device = cairo_pdf)

cat("\nDone.\n")
cat("  Tables:  ", OUTPUT_TAB, "\n", sep = "")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
