###############################################################################
# phase4_within_nace4d_extensive_DiD.R
#
# PURPOSE
#   Extensive-margin analog of phase4_within_nace4d_reallocation_did.R.
#   Same treated cells, same identification strategy, but the outcome is
#   binary supplier presence rather than expenditure share.
#
#       transact_ijt = 1{ spend(j, i, t) > 0 }
#       transact_ijt = alpha_ij + delta_t + beta * top_i * post_t + eps
#
#   Sample: cells in ETS-treated NACE4d with >=2 distinct suppliers in the
#           interval and >=1 supplier with omega > 0. Two suppliers per
#           cell: top-omega and bottom-omega (existing rule).
#
#   beta < 0 with |beta_top| > |beta_bot baseline| means the top-omega
#   supplier gets dropped from the buyer's portfolio more frequently than
#   the bottom-omega supplier post-treatment.
#
# OUTPUTS (output_<machine>/figures/, output_<machine>/tables/)
#   - phase4_within_nace4d_extensive_DiD.{png,pdf}
#         3-facet plot (one per event year), top-omega + bottom-omega
#         survival lines with 95% bootstrap CIs.
#   - phase4_within_nace4d_extensive_DiD_pooled.csv
#         year-version-role means with CIs.
#   - phase4_within_nace4d_extensive_DiD_coefs.csv
#         DiD coefs per version.
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

write_tex_table <- function(dt, file, digits = 4, caption = NULL) {
  x <- xtable(as.data.frame(dt), digits = digits, caption = caption)
  print(x, file = file, include.rownames = FALSE, booktabs = TRUE,
        caption.placement = "top",
        sanitize.colnames.function = function(s) gsub("_", "\\\\_", s, fixed = TRUE),
        sanitize.text.function    = function(s) gsub("_", "\\\\_", s, fixed = TRUE))
  invisible(NULL)
}

set.seed(20260508)

YEAR_LO <- 2005L
YEAR_HI <- 2022L
N_BOOT  <- 1000L

INTERVALS <- list(
  "treat_2008" = list(years = c(2006L, 2007L), treat_year = 2008L),
  "treat_2013" = list(years = c(2011L, 2012L), treat_year = 2013L),
  "treat_2017" = list(years = c(2015L, 2016L), treat_year = 2017L)
)

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
                                       year, shortage, total_cost,
                                       nace4d)]
rm(firm_exposure)

ets_treated_nace4d <- unique(fe$nace4d)
ets_treated_nace4d <- ets_treated_nace4d[!is.na(ets_treated_nace4d)]
ets_vats_all <- unique(fe$vat)

seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b <- b2b[!is.na(seller_nace4d) & seller_nace4d %in% ets_treated_nace4d]

# ---------------------------------------------------------------------------
# 2. Per-interval firm-omega
# ---------------------------------------------------------------------------
build_firm_omega <- function(yrs) {
  d <- fe[year %in% yrs & !is.na(shortage) & !is.na(total_cost) & total_cost > 0,
          .(vat, year, shortage, total_cost)]
  o <- d[, .(n_yrs = .N,
             sum_short = sum(shortage),
             sum_cost  = sum(total_cost)),
         by = vat]
  o <- o[n_yrs == 2L & sum_cost > 0]
  o[, omega := sum_short / sum_cost]
  o[, .(vat, omega)]
}
firm_omega <- lapply(INTERVALS, function(s) build_firm_omega(s$years))

# ---------------------------------------------------------------------------
# 3. Treated cells: top-omega + bottom-omega (same rule as the intensive DiD)
# ---------------------------------------------------------------------------
build_cells_for_interval <- function(label) {
  spec <- INTERVALS[[label]]
  yrs  <- spec$years

  pre <- b2b[year %in% yrs,
             .(int_sales = sum(sales)),
             by = .(buyer, seller_nace4d, seller)]
  pre <- pre[int_sales > 0]

  cn <- pre[, .(n_supp = uniqueN(seller)), by = .(buyer, seller_nace4d)]
  multi <- cn[n_supp >= 2L, .(buyer, seller_nace4d)]
  pre <- merge(pre, multi, by = c("buyer", "seller_nace4d"))

  pre <- merge(pre, firm_omega[[label]],
               by.x = "seller", by.y = "vat", all.x = TRUE)
  pre[is.na(omega), omega := 0]

  setorder(pre, buyer, seller_nace4d, -omega, -int_sales, seller)
  top <- pre[, .SD[1L], by = .(buyer, seller_nace4d)]
  top <- top[omega > 0]
  keys <- top[, .(buyer, seller_nace4d)]

  setorder(pre, buyer, seller_nace4d, omega, -int_sales, seller)
  bot <- pre[, .SD[1L], by = .(buyer, seller_nace4d)]
  bot <- bot[keys, on = c("buyer", "seller_nace4d"), nomatch = 0L]

  cells <- rbind(
    top[, .(buyer, seller_nace4d, supplier_role = "top",
            seller, omega, int_sales)],
    bot[, .(buyer, seller_nace4d, supplier_role = "bot",
            seller, omega, int_sales)]
  )
  cells[, version    := label]
  cells[, treat_year := spec$treat_year]
  cells
}

cell_long <- rbindlist(lapply(names(INTERVALS), build_cells_for_interval),
                       use.names = TRUE)
cat(sprintf("\nTreated cells (one row per cell x role x version):\n"))
print(cell_long[, .(n_rows = .N,
                    n_cells = uniqueN(paste(buyer, seller_nace4d))),
                by = version])

# ---------------------------------------------------------------------------
# 4. Cell-role-year long panel: outcome = transact (binary)
# ---------------------------------------------------------------------------
cat("\nBuilding cell-role-year long panel (binary transact outcome)...\n")

yr_sales <- b2b[, .(buyer, seller_nace4d, seller, year, sales)]

panel <- cell_long[, .(year = YEAR_LO:YEAR_HI),
                   by = .(buyer, seller_nace4d, supplier_role,
                          seller, version, treat_year)]
panel <- merge(panel, yr_sales,
               by = c("buyer", "seller_nace4d", "seller", "year"),
               all.x = TRUE)
panel[, transact := as.integer(!is.na(sales) & sales > 0)]
panel[, top  := as.integer(supplier_role == "top")]
panel[, post := as.integer(year >= treat_year)]
panel[, cell_role_id := paste(buyer, seller_nace4d, supplier_role, sep = "::")]
panel[, cell_id      := paste(buyer, seller_nace4d, sep = "::")]

cat(sprintf("  panel rows: %d\n", nrow(panel)))

# ---------------------------------------------------------------------------
# 5. Aggregate (mean transact across cells with bootstrap CI)
# ---------------------------------------------------------------------------
boot_ci <- function(x, stat = mean, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, stat(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

pooled <- panel[, {
  ci <- boot_ci(transact, stat = mean)
  .(mean_transact = mean(transact),
    n_cells       = .N,
    ci_lo         = ci$lo,
    ci_hi         = ci$hi)
}, by = .(version, treat_year, year, supplier_role)]
setorder(pooled, version, supplier_role, year)
fwrite(pooled,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_extensive_DiD_pooled.csv"))

# ---------------------------------------------------------------------------
# 6. DiD regressions (linear probability model, same FEs as intensive)
# ---------------------------------------------------------------------------
results <- list()
for (label in names(INTERVALS)) {
  cat(sprintf("\n=== %s ===\n", label))
  d <- panel[version == label]
  if (nrow(d) == 0L) next
  fit <- feols(
    transact ~ i(post, top, ref = 0) | cell_role_id + year,
    data    = d,
    cluster = ~ cell_id
  )
  print(summary(fit))
  ct <- as.data.table(coeftable(fit), keep.rownames = "term")
  results[[label]] <- cbind(
    version         = label,
    n_obs           = nobs(fit),
    n_treated_cells = uniqueN(d$cell_id),
    ct
  )
}

coefs <- rbindlist(results, use.names = TRUE, fill = TRUE)
setnames(coefs,
         old = c("Estimate", "Std. Error", "t value", "Pr(>|t|)"),
         new = c("estimate", "std_error", "t_stat", "p_value"),
         skip_absent = TRUE)
fwrite(coefs,
       file.path(OUTPUT_TAB,
                 "phase4_within_nace4d_extensive_DiD_coefs.csv"))
write_tex_table(coefs,
                file.path(OUTPUT_TAB,
                          "phase4_within_nace4d_extensive_DiD_coefs.tex"),
                caption = "Extensive-margin DiD on supplier survival (top-omega vs bottom-omega).")

# ---------------------------------------------------------------------------
# 7. Plot
# ---------------------------------------------------------------------------
version_labels <- c(
  "treat_2008" = "Treatment 2008 (omega from 2006-07)",
  "treat_2013" = "Treatment 2013 (omega from 2011-12)",
  "treat_2017" = "Treatment 2017 (omega from 2015-16)"
)

base_theme <- theme_minimal(base_size = 11) +
  theme(strip.text = element_text(face = "bold"),
        panel.grid.minor = element_blank(),
        legend.position = "bottom")

treat_lines <- data.table(
  version_lab = factor(version_labels, levels = version_labels),
  treat_year  = sapply(INTERVALS, `[[`, "treat_year")
)

d_plot <- copy(pooled)
d_plot[, version_lab := factor(version,
                               levels = names(version_labels),
                               labels = version_labels)]
d_plot[, supplier_role := factor(supplier_role,
                                 levels = c("top", "bot"),
                                 labels = c("Top-omega supplier",
                                            "Bottom-omega supplier"))]

p <- ggplot(d_plot, aes(x = year, y = mean_transact,
                        color = supplier_role, fill = supplier_role)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.18, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 1.1) +
  geom_vline(data = treat_lines,
             aes(xintercept = treat_year - 0.5),
             linetype = "dashed", color = "firebrick",
             inherit.aes = FALSE) +
  facet_wrap(~ version_lab, ncol = 1, scales = "free_y") +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 2)) +
  scale_y_continuous(limits = c(0, 1),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = c("Top-omega supplier"    = "firebrick",
                                "Bottom-omega supplier" = "navy"),
                     name = NULL) +
  scale_fill_manual(values = c("Top-omega supplier"    = "firebrick",
                               "Bottom-omega supplier" = "navy"),
                    name = NULL) +
  labs(title = "Within-NACE4d extensive margin: supplier survival",
       subtitle = "P(buyer transacts with this supplier in year t) across treated cells; 95% bootstrap CI; red dashed = treatment year.",
       x = NULL,
       y = "Share of cells where buyer transacts with this supplier") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_extensive_DiD.png"),
       p, width = 9, height = 10, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_within_nace4d_extensive_DiD.pdf"),
       p, width = 9, height = 10)

cat("\nAll DiD coefficients (extensive margin):\n")
print(coefs[, .(version, term,
                est = round(estimate, 4),
                se  = round(std_error, 4),
                p   = round(p_value, 4),
                n_obs, n_treated_cells)])

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
