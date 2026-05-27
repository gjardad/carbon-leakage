# =============================================================================
# phase6_cdgm_event_study_honestdid.R
#
# Event study + Rambachan-Roth HonestDiD for the international (CdGM) margin,
# around the 2017 MSR event. Motivated by a visible PRE-TREND in the sourcing-
# probability series (Figure phase2_cdgm_figure2 panel b): the extensive-margin
# DiD coefficient is positive at the MSR (+0.0124**), but if it merely continues
# a pre-existing trend it is not a causal response. HonestDiD asks how large a
# parallel-trends violation would have to be to overturn the post-MSR effect.
#
# Mirrors analysis/phase4_within_intensive_did_honestdid.R (relative-magnitudes
# bounds via createSensitivityResults_relativeMagnitudes; breakdown Mbar).
#
# Spec (event study, ref = 2016 = MSR year - 1):
#   y_{f,p,i,t} = sum_{tau != 2016} beta_tau * 1[regulated]_p * 1[year=tau]
#                 + alpha_{f,p,i} + delta_{i,t} + delta_{s,t} + e
#   Sample: non-ETS source, ex-Switzerland, window 2010-2022. Outcomes: import
#   share and sourcing probability. Two-way clustered firm + country.
#
# OUTPUTS (output_*/{figures,tables}; .tex/.png tracked, .csv gitignored):
#   figures/phase6_cdgm_eventstudy_<prob|share>.{png}     -- leads/lags + pre-trend
#   figures/phase6_cdgm_honestdid_<prob|share>.{png}      -- CI vs Mbar
#   tables/phase6_cdgm_honestdid_bounds.tex               -- breakdown-Mbar table
# =============================================================================

if (!requireNamespace("HonestDiD", quietly = TRUE))
  install.packages("HonestDiD", repos = "https://cloud.r-project.org/")

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2)
  library(HonestDiD); library(xtable)
})
set.seed(20260527)

YEAR_LO    <- 2010L
YEAR_HI    <- 2022L
TREAT_YEAR <- 2017L                 # MSR; reference = TREAT_YEAR - 1 = 2016
M_BAR_VEC  <- c(0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2)

OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Load panel; non-ETS, ex-Switzerland; window.
# ---------------------------------------------------------------------------
ext_rdata <- file.path(PROC_DATA, "customs_import_panel_extended.RData")
reg_dta   <- file.path(PROC_DATA, "customs_import_panel_regulated.dta")
reg_rdata <- file.path(PROC_DATA, "customs_import_panel_regulated.RData")
mock_path <- file.path(PROC_DATA, "mock_customs_import_panel_regulated.RData")

if (file.exists(ext_rdata)) { cat("EXTENDED panel.\n"); load(ext_rdata); d <- as.data.table(panel)
} else if (file.exists(reg_dta)) { cat("WARNING: CdGM-window panel (2000-2019).\n")
  if (!requireNamespace("haven", quietly = TRUE)) install.packages("haven", repos = "https://cloud.r-project.org")
  d <- as.data.table(haven::read_dta(reg_dta))
} else if (file.exists(reg_rdata)) { cat("WARNING: CdGM-window panel (RData).\n"); load(reg_rdata); d <- as.data.table(panel)
} else { cat("MOCK panel.\n"); load(mock_path); d <- as.data.table(panel) }

d <- d[is_non_ets_country == 1L]
d <- d[partner_iso2 != "CH"]
d <- d[year %between% c(YEAR_LO, YEAR_HI)]
cat("Rows (non-ETS, ex-CH,", YEAR_LO, "-", YEAR_HI, "):", nrow(d), "\n")

d[, total_value_ft := sum(value), by = .(vat, year)]
d[, share := ifelse(total_value_ft > 0, value / total_value_ft, 0)]
d[, prob_active := as.integer(value > 0)]
d[, firm_prod_country := paste(vat, cn8, partner_iso2, sep = "_")]
d[, country_year      := paste(partner_iso2, year, sep = "_")]
d[, sector_year       := paste(buyer_nace2d, year, sep = "_")]

# ---------------------------------------------------------------------------
# 2. Per-outcome: event study -> betahat/sigma -> event-study plot + HonestDiD.
# ---------------------------------------------------------------------------
run_outcome <- function(outcome, ylab) {
  cat("\n================", outcome, "================\n")
  fm <- as.formula(sprintf(
    "%s ~ i(year, is_regulated_product, ref = %d) | firm_prod_country + country_year + sector_year",
    outcome, TREAT_YEAR - 1L))
  m <- feols(fm, data = d, cluster = ~ vat + partner_iso2, notes = FALSE)

  ct <- coeftable(m); vc <- vcov(m)
  keep <- grepl("^year::\\d+:is_regulated_product$", rownames(ct))
  betahat <- ct[keep, "Estimate"]
  sigma   <- vc[keep, keep, drop = FALSE]
  yrs <- as.integer(sub(".*year::(\\d+).*", "\\1", names(betahat)))
  o <- order(yrs); betahat <- betahat[o]; sigma <- sigma[o, o, drop = FALSE]; yrs <- yrs[o]
  se <- sqrt(diag(sigma))

  # --- event-study plot (shows the pre-trend) ---
  es <- rbind(data.table(year = yrs, beta = betahat, se = se),
              data.table(year = TREAT_YEAR - 1L, beta = 0, se = 0))
  setorder(es, year)
  es[, `:=`(lo = beta - 1.96 * se, hi = beta + 1.96 * se)]
  g_es <- ggplot(es, aes(year, beta)) +
    geom_hline(yintercept = 0, color = "grey60") +
    geom_vline(xintercept = TREAT_YEAR - 0.5, linetype = "dashed", color = "firebrick") +
    geom_pointrange(aes(ymin = lo, ymax = hi), color = "navy", size = 0.4) +
    annotate("text", x = TREAT_YEAR - 0.4, y = max(es$hi), label = "MSR",
             hjust = 0, size = 3.5, color = "firebrick") +
    labs(x = NULL, y = ylab) +
    theme_classic(base_size = 14) +
    theme(panel.grid = element_blank(), axis.title = element_text(size = 15),
          axis.text = element_text(size = 13))
  ggsave(file.path(OUT_FIG, sprintf("phase6_cdgm_eventstudy_%s.png", outcome)),
         g_es, width = 8, height = 4.8, dpi = 200)

  N_PRE <- sum(yrs < TREAT_YEAR); N_POST <- sum(yrs >= TREAT_YEAR)
  cat(sprintf("pre periods: %d  post periods: %d\n", N_PRE, N_POST))
  print(es[, .(year, beta = round(beta, 4), se = round(se, 4))])

  # --- HonestDiD relative-magnitudes on average post-MSR effect ---
  l_vec <- rep(1 / N_POST, N_POST)
  post_idx <- yrs >= TREAT_YEAR
  avg_beta <- sum(l_vec * betahat[post_idx])
  avg_se   <- as.numeric(sqrt(t(l_vec) %*% sigma[post_idx, post_idx, drop = FALSE] %*% l_vec))

  hdid <- as.data.table(createSensitivityResults_relativeMagnitudes(
    betahat = betahat, sigma = sigma, numPrePeriods = N_PRE,
    numPostPeriods = N_POST, Mbarvec = M_BAR_VEC, l_vec = l_vec, alpha = 0.05))
  res <- rbind(
    data.table(method = "Original (no PT slack)", Mbar = 0,
               lb = avg_beta - 1.96 * avg_se, ub = avg_beta + 1.96 * avg_se),
    hdid[, .(method = "HonestDiD (rel. magnitudes)", Mbar, lb, ub)])
  res[, outcome := outcome]
  cat(sprintf("avg post-MSR effect: %.4f (SE %.4f)\n", avg_beta, avg_se))
  print(res)

  # breakdown Mbar = smallest Mbar whose CI includes 0
  bd <- hdid[lb <= 0 & ub >= 0, min(Mbar)]
  cat(sprintf("breakdown Mbar (CI first includes 0): %s\n",
              ifelse(is.finite(bd), sprintf("%.2f", bd), ">max")))

  # --- HonestDiD CI-vs-Mbar plot ---
  pl <- hdid
  g_h <- ggplot(pl, aes(Mbar)) +
    geom_hline(yintercept = 0, color = "grey50") +
    geom_hline(yintercept = avg_beta, color = "navy", linetype = "dashed") +
    geom_ribbon(aes(ymin = lb, ymax = ub), alpha = 0.2, fill = "navy") +
    geom_line(aes(y = lb), color = "navy") + geom_line(aes(y = ub), color = "navy") +
    scale_x_continuous(breaks = M_BAR_VEC) +
    labs(x = expression(bar(M)), y = sprintf("95%% CI, avg post-MSR effect (%s)", outcome)) +
    theme_classic(base_size = 14) + theme(panel.grid = element_blank())
  ggsave(file.path(OUT_FIG, sprintf("phase6_cdgm_honestdid_%s.png", outcome)),
         g_h, width = 8, height = 5, dpi = 200)

  res[, breakdown_Mbar := ifelse(is.finite(bd), bd, NA_real_)]
  res
}

probr  <- run_outcome("prob_active", "Sourcing prob.: regulated vs unregulated")
sharer <- run_outcome("share",       "Import share: regulated vs unregulated")

# ---------------------------------------------------------------------------
# 3. Combined bounds table (.tex).
# ---------------------------------------------------------------------------
mock_tag <- if (max(d$year) < 2020L) "_NOEXT" else ""
all_res <- rbind(probr, sharer)
fwrite(all_res, file.path(OUT_TAB, sprintf("phase6_cdgm_honestdid_bounds%s.csv", mock_tag)))

tex_dt <- all_res[method == "HonestDiD (rel. magnitudes)",
                  .(Outcome = ifelse(outcome == "prob_active", "Sourcing prob.", "Import share"),
                    `$\\bar{M}$` = sprintf("%.2f", Mbar),
                    `95\\% CI` = sprintf("[%.4f, %.4f]", lb, ub))]
xt <- xtable(tex_dt,
             caption = paste("HonestDiD relative-magnitudes bounds on the average",
                             "post-MSR (2017) treatment effect, international margin",
                             "(non-ETS source, ex-Switzerland, 2010--2022).",
                             "$\\bar{M}=0$ assumes exact parallel trends; for",
                             "$\\bar{M}>0$ the post-period violation is at most",
                             "$\\bar{M}$ times the largest pre-period violation.",
                             "The breakdown $\\bar{M}$ is the smallest value whose",
                             "CI includes zero. Event-study coefficients are",
                             "two-way clustered on firm and country."),
             label = "tab:cdgm_honestdid_bounds", align = "llcr")
print(xt, file = file.path(OUT_TAB, sprintf("phase6_cdgm_honestdid_bounds%s.tex", mock_tag)),
      include.rownames = FALSE, booktabs = TRUE,
      sanitize.colnames.function = identity, sanitize.text.function = identity,
      caption.placement = "top")

cat("\nDone. figures:", OUT_FIG, "\n tables:", OUT_TAB, "\n")
