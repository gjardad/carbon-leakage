###############################################################################
# network_exposure_regs_4_regressions.R
#
# PURPOSE:
#   Run firm-FE + nace4d x year FE regressions on the frozen-weights panel.
#   Outcomes: log(real_revenue) and within-nace4d output share (theta_it).
#   Regressors: standardized upstream and downstream exposure.
#   Samples: all firms; non-ETS only (pure indirect channel).
#
# DATA:
#   - data/processed/frozen_weights_exposure_panel.RData  (from script 3)
###############################################################################

rm(list = ls())

library(dplyr)

# ---- Paths ----
if (Sys.info()[["user"]] == "JARDANG") {
  # RMD
  project_root <- "X:/Documents/JARDANG/carbon-leakage"
} else {
  # Local 1
  project_root <- "c:/Users/jota_/Documents/carbon-leakage"
}
out_data <- file.path(project_root, "data", "processed")

# ---- Load panel ----
cat("Loading panel...\n")
load(file.path(out_data, "frozen_weights_exposure_panel.RData"))

# ===========================================================================
# Regressions (requires fixest)
# ===========================================================================
if (!requireNamespace("fixest", quietly = TRUE)) {
  stop("fixest not installed. Install with: install.packages('fixest')")
}

cat("\n=== REGRESSIONS (frozen base-period weights) ===\n")

library(fixest)

df <- frozen_exposure_panel %>%
  filter(!is.na(nace4d), !is.na(real_revenue), real_revenue > 0,
         !is.na(upstream_exposure)) %>%
  mutate(log_real_rev = log(real_revenue))

# Within-NACE4d output share
df <- df %>%
  group_by(nace4d, year) %>%
  mutate(
    sector_output = sum(real_revenue, na.rm = TRUE),
    theta_it = real_revenue / sector_output,
    n_in_sector = n()
  ) %>%
  ungroup() %>%
  filter(n_in_sector >= 3)

# Standardize
df <- df %>%
  mutate(
    upstream_std = (upstream_exposure - mean(upstream_exposure, na.rm = TRUE)) /
      sd(upstream_exposure, na.rm = TRUE),
    downstream_std = (downstream_exposure - mean(downstream_exposure, na.rm = TRUE)) /
      sd(downstream_exposure, na.rm = TRUE),
    upstream_indirect_std = (upstream_indirect - mean(upstream_indirect, na.rm = TRUE)) /
      sd(upstream_indirect, na.rm = TRUE),
    downstream_indirect_std = (downstream_indirect - mean(downstream_indirect, na.rm = TRUE)) /
      sd(downstream_indirect, na.rm = TRUE)
  )

cat(sprintf("\nRegression sample: %d firm-years, %d firms, years %d-%d\n",
            nrow(df), n_distinct(df$vat),
            min(df$year), max(df$year)))
cat(sprintf("  ETS: %d firm-years, Non-ETS: %d firm-years\n",
            sum(df$is_ets == 1, na.rm = TRUE),
            sum(df$is_ets == 0 | is.na(df$is_ets))))

# --- Firm FE specs (the clean causal ones) ---
cat("\n--- Firm FE + nace4d x year FE (frozen weights) ---\n")
cat("  Identification: within-firm changes driven by time-varying carbon\n")
cat("  price x suppliers' shortage, with predetermined network position.\n\n")

reg1 <- feols(log_real_rev ~ upstream_std | nace4d^year + vat, data = df,
              cluster = ~vat)
cat("[1] log(rev) ~ upstream, firm FE:\n")
print(summary(reg1))

reg2 <- feols(theta_it ~ upstream_std | nace4d^year + vat, data = df,
              cluster = ~vat)
cat("\n[2] theta ~ upstream, firm FE:\n")
print(summary(reg2))

reg3 <- feols(log_real_rev ~ downstream_std | nace4d^year + vat, data = df,
              cluster = ~vat)
cat("\n[3] log(rev) ~ downstream, firm FE:\n")
print(summary(reg3))

reg4 <- feols(theta_it ~ downstream_std | nace4d^year + vat, data = df,
              cluster = ~vat)
cat("\n[4] theta ~ downstream, firm FE:\n")
print(summary(reg4))

reg5 <- feols(log_real_rev ~ upstream_std + downstream_std | nace4d^year + vat,
              data = df, cluster = ~vat)
cat("\n[5] log(rev) ~ upstream + downstream, firm FE:\n")
print(summary(reg5))

reg6 <- feols(theta_it ~ upstream_std + downstream_std | nace4d^year + vat,
              data = df, cluster = ~vat)
cat("\n[6] theta ~ upstream + downstream, firm FE:\n")
print(summary(reg6))

# --- Non-ETS only ---
cat("\n--- Non-ETS firms only (pure indirect channel) ---\n")
df_nonets <- df %>% filter(is_ets == 0 | is.na(is_ets))

df_nonets <- df_nonets %>%
  mutate(
    upstream_indirect_std_ne = (upstream_indirect - mean(upstream_indirect, na.rm = TRUE)) /
      sd(upstream_indirect, na.rm = TRUE)
  )

cat(sprintf("  Non-ETS sample: %d firm-years, %d firms\n",
            nrow(df_nonets), n_distinct(df_nonets$vat)))

reg7 <- feols(log_real_rev ~ upstream_indirect_std_ne | nace4d^year + vat,
              data = df_nonets, cluster = ~vat)
cat("\n[7] Non-ETS, log(rev) ~ upstream indirect, firm FE:\n")
print(summary(reg7))

reg8 <- feols(theta_it ~ upstream_indirect_std_ne | nace4d^year + vat,
              data = df_nonets, cluster = ~vat)
cat("\n[8] Non-ETS, theta ~ upstream indirect, firm FE:\n")
print(summary(reg8))

# --- Summary ---
cat("\n\n========================================\n")
cat("COEFFICIENT SUMMARY (frozen weights, firm FE)\n")
cat("========================================\n")
cat("\nSpec | Dep Var | Sample | Regressor | Coef | SE | t-stat | N\n")
cat(paste(rep("-", 80), collapse = ""), "\n")

print_coef <- function(label, reg) {
  ct <- coeftable(reg)
  cat(sprintf("%s | %.5f | %.5f | %.2f | %d\n",
              label, ct[1, 1], ct[1, 2], ct[1, 3], reg$nobs))
}

print_coef("[1] log(rev) | All     | upstream", reg1)
print_coef("[2] theta   | All     | upstream", reg2)
print_coef("[3] log(rev) | All     | downstream", reg3)
print_coef("[4] theta   | All     | downstream", reg4)
print_coef("[7] log(rev) | Non-ETS | upstream_indirect", reg7)
print_coef("[8] theta   | Non-ETS | upstream_indirect", reg8)

cat("\n\n=== Convergence (frozen A_base) ===\n")
print(convergence_df)

cat("\nDone.\n")
