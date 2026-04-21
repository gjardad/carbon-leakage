###############################################################################
# phase2_network_exposure_output.R
#
# PURPOSE:
#   Test whether within-NACE4d network-adjusted ETS exposure correlates with
#   firm output (levels or shares). Uses sector×year FE to absorb all
#   sector-level shocks — identification comes from within-sector variation
#   in network position.
#
# DATA:
#   - data/processed/network_exposure_panel.RData
#
# OUTPUT:
#   - Console: regression summaries
#   - output/tables/phase2_network_exposure_regs.txt
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(fixest)  # for feols with high-dimensional FE
library(stringr)

# ---- Paths ----
project_root <- "c:/Users/jota_/Documents/carbon_policy_networks"
out_data     <- file.path(project_root, "data", "processed")
output_tab   <- file.path(project_root, "output", "tables")
output_fig   <- file.path(project_root, "output", "figures")

dir.create(output_tab, recursive = TRUE, showWarnings = FALSE)

# ---- Load data ----
load(file.path(out_data, "network_exposure_panel.RData"))

# ---- Prepare regression sample ----
df <- network_exposure_panel %>%
  filter(!is.na(nace4d), !is.na(real_revenue), real_revenue > 0,
         !is.na(upstream_exposure)) %>%
  mutate(
    log_real_rev = log(real_revenue),
    sector_year = paste0(nace4d, "_", year)
  )

# Compute within-NACE4d output share
df <- df %>%
  group_by(nace4d, year) %>%
  mutate(
    sector_output = sum(real_revenue, na.rm = TRUE),
    theta_it = real_revenue / sector_output,
    n_in_sector = n()
  ) %>%
  ungroup()

# Restrict to sectors with at least 3 firms (need within-sector variation)
df <- df %>% filter(n_in_sector >= 3)

cat(sprintf("Regression sample: %d firm-years, %d firms, %d sector-years\n",
            nrow(df), n_distinct(df$vat), n_distinct(df$sector_year)))
cat(sprintf("  ETS firm-years: %d\n", sum(df$is_ets == 1, na.rm = TRUE)))
cat(sprintf("  Non-ETS firm-years: %d\n", sum(df$is_ets == 0 | is.na(df$is_ets))))

# Winsorize extreme exposure values at 1st/99th percentile
winsorize <- function(x, probs = c(0.01, 0.99)) {
  q <- quantile(x, probs, na.rm = TRUE)
  pmin(pmax(x, q[1]), q[2])
}

df <- df %>%
  mutate(
    upstream_w = winsorize(upstream_exposure),
    downstream_w = winsorize(downstream_exposure),
    upstream_indirect_w = winsorize(upstream_indirect),
    downstream_indirect_w = winsorize(downstream_indirect)
  )

# Standardize for interpretability (1 SD change)
df <- df %>%
  mutate(
    upstream_std = (upstream_w - mean(upstream_w, na.rm = TRUE)) /
      sd(upstream_w, na.rm = TRUE),
    downstream_std = (downstream_w - mean(downstream_w, na.rm = TRUE)) /
      sd(downstream_w, na.rm = TRUE),
    upstream_indirect_std = (upstream_indirect_w - mean(upstream_indirect_w, na.rm = TRUE)) /
      sd(upstream_indirect_w, na.rm = TRUE),
    downstream_indirect_std = (downstream_indirect_w - mean(downstream_indirect_w, na.rm = TRUE)) /
      sd(downstream_indirect_w, na.rm = TRUE)
  )

# ============================================================================
# REGRESSIONS
# ============================================================================

cat("\n\n========================================\n")
cat("REGRESSION RESULTS\n")
cat("========================================\n")

# ---- A. Log revenue ~ network exposure + sector×year FE ----
cat("\n--- A. Log(real revenue) ~ upstream exposure + nace4d×year FE ---\n")

reg_a1 <- feols(log_real_rev ~ upstream_std | nace4d^year, data = df,
                cluster = ~vat)
cat("\n[A1] All firms, upstream total:\n")
print(summary(reg_a1))

reg_a2 <- feols(log_real_rev ~ downstream_std | nace4d^year, data = df,
                cluster = ~vat)
cat("\n[A2] All firms, downstream total:\n")
print(summary(reg_a2))

reg_a3 <- feols(log_real_rev ~ upstream_std + downstream_std | nace4d^year,
                data = df, cluster = ~vat)
cat("\n[A3] All firms, both directions:\n")
print(summary(reg_a3))

# ---- B. Output share ~ network exposure + sector×year FE ----
cat("\n--- B. Output share (theta) ~ upstream exposure + nace4d×year FE ---\n")

reg_b1 <- feols(theta_it ~ upstream_std | nace4d^year, data = df,
                cluster = ~vat)
cat("\n[B1] All firms, upstream total:\n")
print(summary(reg_b1))

reg_b2 <- feols(theta_it ~ downstream_std | nace4d^year, data = df,
                cluster = ~vat)
cat("\n[B2] All firms, downstream total:\n")
print(summary(reg_b2))

reg_b3 <- feols(theta_it ~ upstream_std + downstream_std | nace4d^year,
                data = df, cluster = ~vat)
cat("\n[B3] All firms, both directions:\n")
print(summary(reg_b3))

# ---- C. Non-ETS firms only (isolate pure network channel) ----
cat("\n--- C. Non-ETS firms only (pure network channel) ---\n")

df_nonets <- df %>% filter(is_ets == 0 | is.na(is_ets))
cat(sprintf("  Non-ETS sample: %d firm-years\n", nrow(df_nonets)))

# Re-standardize within non-ETS sample
df_nonets <- df_nonets %>%
  mutate(
    upstream_indirect_std_ne = (upstream_indirect_w -
      mean(upstream_indirect_w, na.rm = TRUE)) /
      sd(upstream_indirect_w, na.rm = TRUE)
  )

reg_c1 <- feols(log_real_rev ~ upstream_indirect_std_ne | nace4d^year,
                data = df_nonets, cluster = ~vat)
cat("\n[C1] Non-ETS, log(rev) ~ upstream indirect:\n")
print(summary(reg_c1))

reg_c2 <- feols(theta_it ~ upstream_indirect_std_ne | nace4d^year,
                data = df_nonets, cluster = ~vat)
cat("\n[C2] Non-ETS, output share ~ upstream indirect:\n")
print(summary(reg_c2))

# ---- D. Firm FE (within-firm variation in exposure) ----
cat("\n--- D. Firm FE: within-firm changes in exposure ---\n")
cat("  (absorbs permanent size/centrality differences)\n")

reg_d1 <- feols(log_real_rev ~ upstream_std | nace4d^year + vat, data = df,
                cluster = ~vat)
cat("\n[D1] All firms, log(rev) ~ upstream + firm FE + nace4d×year FE:\n")
print(summary(reg_d1))

reg_d2 <- feols(theta_it ~ upstream_std | nace4d^year + vat, data = df,
                cluster = ~vat)
cat("\n[D2] All firms, theta ~ upstream + firm FE + nace4d×year FE:\n")
print(summary(reg_d2))

reg_d3 <- feols(log_real_rev ~ downstream_std | nace4d^year + vat, data = df,
                cluster = ~vat)
cat("\n[D3] All firms, log(rev) ~ downstream + firm FE + nace4d×year FE:\n")
print(summary(reg_d3))

reg_d4 <- feols(theta_it ~ downstream_std | nace4d^year + vat, data = df,
                cluster = ~vat)
cat("\n[D4] All firms, theta ~ downstream + firm FE + nace4d×year FE:\n")
print(summary(reg_d4))

# Non-ETS only with firm FE
reg_d5 <- feols(log_real_rev ~ upstream_indirect_std_ne | nace4d^year + vat,
                data = df_nonets, cluster = ~vat)
cat("\n[D5] Non-ETS, log(rev) ~ upstream indirect + firm FE:\n")
print(summary(reg_d5))

reg_d6 <- feols(theta_it ~ upstream_indirect_std_ne | nace4d^year + vat,
                data = df_nonets, cluster = ~vat)
cat("\n[D6] Non-ETS, theta ~ upstream indirect + firm FE:\n")
print(summary(reg_d6))

# ---- E. Summary table ----
cat("\n\n========================================\n")
cat("COEFFICIENT SUMMARY\n")
cat("========================================\n")
cat("\nSpec | Dep Var | Sample | Regressor | Coef | SE | t-stat | N\n")
cat(paste(rep("-", 90), collapse = ""), "\n")

print_coef <- function(label, reg, var_name = NULL) {
  ct <- coeftable(reg)
  if (is.null(var_name)) var_name <- rownames(ct)[1]
  idx <- which(rownames(ct) == var_name)
  if (length(idx) == 0) idx <- 1
  cat(sprintf("%s | %.4f | %.4f | %.2f | %d\n",
              label, ct[idx, 1], ct[idx, 2], ct[idx, 3], reg$nobs))
}

print_coef("A1 | log(rev) | All | upstream_std       | no firm FE", reg_a1)
print_coef("A2 | log(rev) | All | downstream_std     | no firm FE", reg_a2)
print_coef("B1 | theta   | All | upstream_std       | no firm FE", reg_b1)
print_coef("B2 | theta   | All | downstream_std     | no firm FE", reg_b2)
print_coef("C1 | log(rev) | Non-ETS | upstream_indirect  | no firm FE", reg_c1)
print_coef("C2 | theta   | Non-ETS | upstream_indirect  | no firm FE", reg_c2)
print_coef("D1 | log(rev) | All | upstream_std       | + firm FE", reg_d1)
print_coef("D2 | theta   | All | upstream_std       | + firm FE", reg_d2)
print_coef("D3 | log(rev) | All | downstream_std     | + firm FE", reg_d3)
print_coef("D4 | theta   | All | downstream_std     | + firm FE", reg_d4)
print_coef("D5 | log(rev) | Non-ETS | upstream_indirect  | + firm FE", reg_d5)
print_coef("D6 | theta   | Non-ETS | upstream_indirect  | + firm FE", reg_d6)

# ---- Save results summary ----
sink(file.path(output_tab, "phase2_network_exposure_regs.txt"))
cat("Phase 2: Network Exposure and Output\n")
cat("=====================================\n\n")
cat("Sample: firms in NACE4d sectors with >= 3 firms\n")
cat(sprintf("N firm-years: %d, N firms: %d\n\n", nrow(df), n_distinct(df$vat)))

cat("A. Log(real revenue) with nace4d×year FE, clustered by firm\n\n")
cat("[A1] Upstream total:\n"); print(summary(reg_a1))
cat("\n[A2] Downstream total:\n"); print(summary(reg_a2))
cat("\n[A3] Both:\n"); print(summary(reg_a3))

cat("\n\nB. Output share (theta_it) with nace4d×year FE\n\n")
cat("[B1] Upstream:\n"); print(summary(reg_b1))
cat("\n[B2] Downstream:\n"); print(summary(reg_b2))

cat("\n\nC. Non-ETS firms only\n\n")
cat("[C1] Log(rev) ~ upstream indirect:\n"); print(summary(reg_c1))
cat("\n[C2] Theta ~ upstream indirect:\n"); print(summary(reg_c2))

cat("\n\nD. Firm FE (within-firm variation)\n\n")
cat("[D1] Log(rev) ~ upstream + firm FE:\n"); print(summary(reg_d1))
cat("\n[D2] Theta ~ upstream + firm FE:\n"); print(summary(reg_d2))
cat("\n[D3] Log(rev) ~ downstream + firm FE:\n"); print(summary(reg_d3))
cat("\n[D4] Theta ~ downstream + firm FE:\n"); print(summary(reg_d4))
cat("\n[D5] Non-ETS, log(rev) ~ upstream indirect + firm FE:\n"); print(summary(reg_d5))
cat("\n[D6] Non-ETS, theta ~ upstream indirect + firm FE:\n"); print(summary(reg_d6))
sink()

cat("\nResults saved to:", file.path(output_tab, "phase2_network_exposure_regs.txt"), "\n")
cat("Done.\n")
