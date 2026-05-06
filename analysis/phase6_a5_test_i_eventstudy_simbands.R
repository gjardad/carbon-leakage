# =============================================================================
# R2 — Test I event-study with simultaneous confidence bands
# (Olea & Plagborg-Møller 2019). Plan ref: §R2.
#
# The current Test I event-study (in phase5_test_i_cross_nace_substitution.R)
# reports pointwise 95% bands. Following Roth-Sant'Anna-Bilinski-Poe (2023)
# §4.6 best-practice recommendation, this script regenerates the figure with
# *simultaneous* 95% bands computed via the multivariate-normal sup-t critical
# value on the event-study coefficient vector.
#
# Two panels:
#   (a) Continuous treatment: nace_exposure × year_f
#   (b) Binary treatment:     nace_regulated_dummy × year_f
#
# Outputs:
#   ${OUT_TAB}/phase6_a5_test_i_eventstudy_simbands.csv
#   ${OUT_FIG}/phase6_a5_test_i_eventstudy_simbands.pdf
# =============================================================================

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table); library(fixest); library(ggplot2); library(mvtnorm)
})

YEAR_LO <- 2005L; YEAR_HI <- 2022L
ANCHOR  <- 2014L
ALPHA   <- 0.05

OUT_TAB <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "tables")
OUT_FIG <- file.path(REPO_DIR, paste0("output_", MACHINE_TAG), "figures")
dir.create(OUT_TAB, recursive = TRUE, showWarnings = FALSE)
dir.create(OUT_FIG, recursive = TRUE, showWarnings = FALSE)

source(file.path(REPO_DIR, "analysis/phase6_panel_builders.R"))
panel_i <- build_test_i_panel()
cat(sprintf("Test I panel: %d rows, %d cells, NACE-4d: %d\n",
            nrow(panel_i), uniqueN(panel_i$b_n), uniqueN(panel_i$nace4d)))

panel_i[, year_f := factor(year, levels = sort(unique(year)))]

# Compute simultaneous sup-t critical value via mvtnorm.
# The sup-t band for a vector β̂ ~ N(β, Σ) gives a single critical value
# c such that P(max_k |β̂_k - β_k|/se_k <= c) = 1 - α. Compute by
# q <- qmvnorm of multivariate normal centered at 0 with correlation = corr(Σ).
sim_critval <- function(vc, alpha = 0.05) {
  se <- sqrt(diag(vc))
  cor_mat <- vc / outer(se, se)
  cor_mat <- (cor_mat + t(cor_mat)) / 2
  diag(cor_mat) <- 1
  # GenzBretz is the default and is dramatically faster than Miwa for dim ~16.
  set.seed(42)
  q <- mvtnorm::qmvnorm(
    p = 1 - alpha, tail = "both.tails", corr = cor_mat,
    algorithm = mvtnorm::GenzBretz(maxpts = 25000, abseps = 1e-3, releps = 0))
  q$quantile
}

run_es <- function(treat_col, label) {
  rhs <- sprintf("i(year_f, %s, ref = '%s')", treat_col,
                 as.character(ANCHOR - 1L))
  form <- as.formula(sprintf("share ~ %s | by_year + b_n", rhs))
  m <- feols(form, data = panel_i, cluster = ~ buyer, notes = FALSE)
  vn <- names(coef(m))
  use <- grep("^year_f::", vn)
  est <- coef(m)[use]
  vc  <- vcov(m)[use, use]
  yr  <- as.integer(sub("^year_f::([0-9]+):.*$", "\\1", vn[use]))
  ord <- order(yr)
  est <- est[ord]; vc <- vc[ord, ord]; yr <- yr[ord]
  se <- sqrt(diag(vc))
  z_pt <- qnorm(1 - ALPHA / 2)
  z_st <- sim_critval(vc, alpha = ALPHA)
  data.table(
    spec   = label,
    year   = yr,
    est    = as.numeric(est),
    se     = se,
    pt_lo  = est - z_pt * se,
    pt_hi  = est + z_pt * se,
    sim_lo = est - z_st * se,
    sim_hi = est + z_st * se,
    z_sim  = z_st
  )
}

t_cont <- run_es("nace_exposure", "(a) Continuous: nace_exposure × year")
t_bin  <- run_es("nace_regulated_dummy",
                 "(b) Binary: nace_regulated_dummy × year")
es_all <- rbindlist(list(t_cont, t_bin), use.names = TRUE)
fwrite(es_all, file.path(OUT_TAB, "phase6_a5_test_i_eventstudy_simbands.csv"))

cat(sprintf("\nSim-band critical values: continuous = %.3f, binary = %.3f\n",
            t_cont$z_sim[1L], t_bin$z_sim[1L]))
cat("(Pointwise critical = 1.96.)\n")

g <- ggplot(es_all, aes(x = year, y = est)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_vline(xintercept = ANCHOR + 0.5, linetype = "dotted") +
  geom_ribbon(aes(ymin = sim_lo, ymax = sim_hi), alpha = 0.15, fill = "navy") +
  geom_ribbon(aes(ymin = pt_lo, ymax = pt_hi), alpha = 0.30, fill = "navy") +
  geom_line() + geom_point() +
  facet_wrap(~ spec, scales = "free_y", ncol = 1L) +
  labs(title = "Test I event study with pointwise (lighter) and simultaneous (darker) 95% bands",
       subtitle = sprintf(
         "Reference year = %d; sim-band crit = %.2f (continuous) / %.2f (binary).",
         ANCHOR - 1L, t_cont$z_sim[1L], t_bin$z_sim[1L]),
       x = "Year", y = "Coefficient on year_f × treatment") +
  theme_bw()
ggsave(file.path(OUT_FIG, "phase6_a5_test_i_eventstudy_simbands.pdf"),
       g, width = 9, height = 7)

cat("\nDONE.\n")
