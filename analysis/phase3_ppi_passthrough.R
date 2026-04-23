###############################################################################
# phase3_ppi_passthrough.R
#
# PURPOSE:
#   Task 2. Test whether Belgian NACE4d domestic PPIs respond to sector-level
#   ETS carbon-cost exposure. Two exposure measures:
#
#     (a) Direct exposure:
#           exposure_direct_{s,t} =
#             sum_{i in s} (carbon_cost_{it}) / sum_{i in s} (total_cost_{it})
#         Built in phase3_build_exposure_panel.R. Non-zero only for sectors
#         that contain ETS firms.
#
#     (b) Network-adjusted (upstream) exposure:
#           Sector-level mean of firm-level upstream_exposure from the frozen-
#           weights pipeline (2012-2021). Captures exposure coming through the
#           supply chain.
#
#   Specifications:
#     S1. log(PPI)_{s,t}   ~ exp_direct + FE(sector) + FE(year)
#     S2. Δ log(PPI)_{s,t} ~ Δ exp_direct + FE(year)              [first diff]
#     S3. log(PPI)_{s,t}   ~ exp_direct + exp_upstream_indirect + FE(sector, year)
#     S4. log(PPI)_{s,t}   ~ 0/1/2-year lags of exp_direct + FEs   [dist lag]
#
#   Samples:
#     Main:   all NACE4d sectors (non-ETS sectors are controls with zero exp).
#     Focus:  NACE4d sectors that contain at least one ETS firm in any year.
#
# INPUT:
#   data/processed/phase3_sector_exposure.RData
#   NBB_data/processed/deflator_nace4d_2005base.RData
#
# OUTPUT:
#   output/tables/phase3_task2_passthrough_regs.txt
#   output/figures/phase3_task2_event_study.pdf  (event-study around MSR reform)
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)
library(tidyr)
library(ggplot2)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

if (!requireNamespace("fixest", quietly = TRUE)) {
  stop("fixest not installed. Install with: install.packages('fixest')")
}
library(fixest)

# ---- Load ----
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))

# ===========================================================================
# Build the panel:
#   Start from deflator (all NACE4d sectors, 2005-2024).
#   Merge in sector_exposure (direct exposure + network exposure).
#   Where sector_exposure is missing, exposure = 0 (sector has no ETS firms).
# ===========================================================================
cat("Building panel...\n")

panel <- deflator %>%
  select(nace4d, nace2d, year, ppi) %>%
  filter(year >= 2005, year <= 2022) %>%
  left_join(
    sector_exposure %>%
      select(nace4d, year,
             exposure_direct_total, exposure_direct_mat, exposure_direct_rev,
             exposure_alt_total, exposure_alt_mat, exposure_alt_rev,
             net_upstream, net_upstream_ind, net_downstream_ind,
             n_ets_firms),
    by = c("nace4d", "year")
  ) %>%
  mutate(
    has_ets = !is.na(n_ets_firms),
    exposure_direct_total = coalesce(exposure_direct_total, 0),
    exposure_direct_mat   = coalesce(exposure_direct_mat,   0),
    exposure_direct_rev   = coalesce(exposure_direct_rev,   0),
    exposure_alt_total    = coalesce(exposure_alt_total,    0),
    exposure_alt_mat      = coalesce(exposure_alt_mat,      0),
    exposure_alt_rev      = coalesce(exposure_alt_rev,      0),
    # Network columns left as NA where not defined (restrict to 2012-2021)
    log_ppi = log(ppi)
  )

# First-differences and lagged first-differences
panel <- panel %>%
  arrange(nace4d, year) %>%
  group_by(nace4d) %>%
  mutate(
    d_log_ppi      = log_ppi - lag(log_ppi),

    # Direct exposure: contemporaneous and lagged changes
    d_exp_dir      = exposure_direct_total - lag(exposure_direct_total),
    d_exp_dir_L1   = lag(d_exp_dir, 1),
    d_exp_dir_L2   = lag(d_exp_dir, 2),

    # Alt exposure (base-period-fixed denominator): same lag/diff structure
    d_exp_alt      = exposure_alt_total - lag(exposure_alt_total),
    d_exp_alt_L1   = lag(d_exp_alt, 1),
    d_exp_alt_L2   = lag(d_exp_alt, 2),
    lag1_exp_alt   = lag(exposure_alt_total, 1),
    lag2_exp_alt   = lag(exposure_alt_total, 2),

    # Upstream network exposure (total): contemporaneous and lagged changes
    d_exp_up       = net_upstream - lag(net_upstream),
    d_exp_up_L1    = lag(d_exp_up, 1),
    d_exp_up_L2    = lag(d_exp_up, 2),

    # Upstream network indirect (direct subtracted out)
    d_exp_upi      = net_upstream_ind - lag(net_upstream_ind),
    d_exp_upi_L1   = lag(d_exp_upi, 1),
    d_exp_upi_L2   = lag(d_exp_upi, 2),

    # Level lags (for S4 level regression)
    lag1_exp_dir = lag(exposure_direct_total, 1),
    lag2_exp_dir = lag(exposure_direct_total, 2)
  ) %>%
  ungroup()

# Identify NACE4d sectors with at least one ETS firm-year
ets_sectors <- panel %>%
  group_by(nace4d) %>%
  summarise(ever_ets = any(has_ets), .groups = "drop") %>%
  filter(ever_ets) %>%
  pull(nace4d)

cat(sprintf("Panel: %d rows, %d NACE4d sectors (%d ever-ETS), years %d-%d\n",
            nrow(panel), n_distinct(panel$nace4d), length(ets_sectors),
            min(panel$year), max(panel$year)))

# ===========================================================================
# Regressions
# ===========================================================================

# Helper: cumulative coefficient (sum) with SE, z, and p-value from a
# fixest model. For a set of coefficient names, returns a list with the
# sum, its SE from the cluster-robust vcov, a normal-approx z, and p.
linear_combo <- function(model, terms) {
  cf <- coef(model)
  V  <- vcov(model)
  present <- terms[terms %in% names(cf)]
  if (length(present) == 0) {
    return(list(estimate = NA_real_, std.error = NA_real_,
                statistic = NA_real_, p.value = NA_real_,
                terms = terms))
  }
  L   <- rep(1, length(present))
  est <- sum(cf[present])
  se  <- sqrt(as.numeric(t(L) %*% V[present, present, drop = FALSE] %*% L))
  z   <- est / se
  p   <- 2 * pnorm(abs(z), lower.tail = FALSE)
  list(estimate = est, std.error = se, statistic = z, p.value = p,
       terms = present)
}

sink(file.path(OUTPUT_TAB, "phase3_task2_passthrough_regs.txt"))

cat("================================================================\n")
cat(" Phase 3, Task 2: PPI pass-through regressions\n")
cat("================================================================\n\n")

cat("Panel: Belgian NACE4d domestic PPI (Statbel + Eurostat chained to\n")
cat("2005=100), merged with sector-level direct and network-adjusted\n")
cat("carbon cost exposure aggregated from the ETS panel.\n\n")

cat(sprintf(
  "Panel size: %d rows, %d NACE4d sectors (%d ever contain an ETS firm)\n",
  nrow(panel), n_distinct(panel$nace4d), length(ets_sectors)))
cat(sprintf("Years: %d-%d\n\n", min(panel$year), max(panel$year)))

# --- S1a. Levels, direct exposure only, all sectors ---
cat("----------------------------------------------------------------\n")
cat(" [S1a] log(PPI) ~ exposure_direct  |  sector + year FE, all sectors\n")
cat("----------------------------------------------------------------\n")
m1a <- feols(log_ppi ~ exposure_direct_total | nace4d + year,
             data = panel %>% filter(!is.na(log_ppi)),
             cluster = ~nace4d)
print(summary(m1a))
cat("\n")

# --- S1b. Same spec, ETS sectors only ---
cat("----------------------------------------------------------------\n")
cat(" [S1b] log(PPI) ~ exposure_direct  |  sector + year FE, ever-ETS sectors only\n")
cat("----------------------------------------------------------------\n")
m1b <- feols(log_ppi ~ exposure_direct_total | nace4d + year,
             data = panel %>% filter(!is.na(log_ppi), nace4d %in% ets_sectors),
             cluster = ~nace4d)
print(summary(m1b))
cat("\n")

# --- S2a. First differences, direct exposure, all sectors ---
cat("----------------------------------------------------------------\n")
cat(" [S2a] Δ log(PPI) ~ Δ exposure_direct  |  year FE, all sectors\n")
cat("----------------------------------------------------------------\n")
m2a <- feols(d_log_ppi ~ d_exp_dir | year,
             data = panel %>% filter(!is.na(d_log_ppi)),
             cluster = ~nace4d)
print(summary(m2a))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S2b] Δ log(PPI) ~ Δ exposure_direct  |  year FE, ever-ETS sectors only\n")
cat("----------------------------------------------------------------\n")
m2b <- feols(d_log_ppi ~ d_exp_dir | year,
             data = panel %>% filter(!is.na(d_log_ppi), nace4d %in% ets_sectors),
             cluster = ~nace4d)
print(summary(m2b))
cat("\n")

# --- S2c/S2d. Distributed lags in first differences ---
# A lagged-difference coefficient tests whether a change in exposure LAST year
# shows up as a change in prices THIS year, which is the natural spec when
# firms renegotiate input contracts on a 6-12 month horizon.
# Cumulative coefficient beta0 + beta1 + beta2 is the total pass-through of a
# permanent 1pp rise in exposure; we test it jointly below.

cat("----------------------------------------------------------------\n")
cat(" [S2c] Δ log(PPI) ~ Δ exp_dir + L1 Δ exp_dir + L2 Δ exp_dir  |  year FE (all sec)\n")
cat("       (captures delayed pass-through; cumulative = contemporaneous + lagged)\n")
cat("----------------------------------------------------------------\n")
m2c <- feols(d_log_ppi ~ d_exp_dir + d_exp_dir_L1 + d_exp_dir_L2 | year,
             data = panel %>% filter(!is.na(d_log_ppi),
                                      !is.na(d_exp_dir_L1),
                                      !is.na(d_exp_dir_L2)),
             cluster = ~nace4d)
print(summary(m2c))
cum_2c <- linear_combo(m2c, c("d_exp_dir", "d_exp_dir_L1", "d_exp_dir_L2"))
cat(sprintf("\nCumulative pass-through: %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_2c$estimate, cum_2c$std.error, cum_2c$statistic, cum_2c$p.value))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S2d] Δ log(PPI) ~ Δ exp_dir + L1 + L2  |  year FE (ETS sec only)\n")
cat("----------------------------------------------------------------\n")
m2d <- feols(d_log_ppi ~ d_exp_dir + d_exp_dir_L1 + d_exp_dir_L2 | year,
             data = panel %>% filter(!is.na(d_log_ppi),
                                      !is.na(d_exp_dir_L1),
                                      !is.na(d_exp_dir_L2),
                                      nace4d %in% ets_sectors),
             cluster = ~nace4d)
print(summary(m2d))
cum_2d <- linear_combo(m2d, c("d_exp_dir", "d_exp_dir_L1", "d_exp_dir_L2"))
cat(sprintf("\nCumulative pass-through: %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_2d$estimate, cum_2d$std.error, cum_2d$statistic, cum_2d$p.value))
cat("\n")

# --- S3. Add network exposure (restricted to 2012-2021 where defined) ---
cat("----------------------------------------------------------------\n")
cat(" [S3a] log(PPI) ~ direct + upstream_indirect  |  sector + year FE\n")
cat("       (2012-2021 panel; network exposure available)\n")
cat("----------------------------------------------------------------\n")
m3a <- feols(log_ppi ~ exposure_direct_total + net_upstream_ind | nace4d + year,
             data = panel %>% filter(!is.na(log_ppi), !is.na(net_upstream_ind)),
             cluster = ~nace4d)
print(summary(m3a))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S3b] log(PPI) ~ direct + upstream (total)  |  sector + year FE\n")
cat("----------------------------------------------------------------\n")
m3b <- feols(log_ppi ~ exposure_direct_total + net_upstream | nace4d + year,
             data = panel %>% filter(!is.na(log_ppi), !is.na(net_upstream)),
             cluster = ~nace4d)
print(summary(m3b))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S3c] Δ log(PPI) ~ Δ direct + Δ upstream_indirect  |  year FE (contemporaneous)\n")
cat("----------------------------------------------------------------\n")
cat("NOTE: Network exposure was built on this machine with the DOWNSAMPLED\n")
cat("B2B panel; when re-built on RMD with the full B2B file the sample will\n")
cat("be larger and coefficients more precise. The point estimates here are\n")
cat("directional only.\n")
cat("----------------------------------------------------------------\n")
m3c <- feols(d_log_ppi ~ d_exp_dir + d_exp_upi | year,
             data = panel %>% filter(!is.na(d_log_ppi), !is.na(d_exp_upi)),
             cluster = ~nace4d)
print(summary(m3c))
cat("\n")

# --- S3d. Distributed lags in first differences with network exposure ---
cat("----------------------------------------------------------------\n")
cat(" [S3d] Δ log(PPI) ~ Δ direct + L1 + L2, Δ upstream_ind + L1 + L2 | year FE\n")
cat("       (delayed pass-through through own ETS costs AND supplier costs)\n")
cat("----------------------------------------------------------------\n")
m3d <- feols(
  d_log_ppi ~ d_exp_dir + d_exp_dir_L1 + d_exp_dir_L2 +
              d_exp_upi + d_exp_upi_L1 + d_exp_upi_L2 | year,
  data = panel %>% filter(!is.na(d_log_ppi),
                           !is.na(d_exp_dir_L2),
                           !is.na(d_exp_upi_L2)),
  cluster = ~nace4d)
print(summary(m3d))
cum_3d_dir <- linear_combo(m3d, c("d_exp_dir", "d_exp_dir_L1", "d_exp_dir_L2"))
cum_3d_upi <- linear_combo(m3d, c("d_exp_upi", "d_exp_upi_L1", "d_exp_upi_L2"))
cat(sprintf("\nCumulative direct pass-through:  %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_3d_dir$estimate, cum_3d_dir$std.error, cum_3d_dir$statistic, cum_3d_dir$p.value))
cat(sprintf("Cumulative upstream-indirect:     %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_3d_upi$estimate, cum_3d_upi$std.error, cum_3d_upi$statistic, cum_3d_upi$p.value))
cat("\n")

# --- S3e. Same without own direct exposure: pure network pass-through ---
cat("----------------------------------------------------------------\n")
cat(" [S3e] Δ log(PPI) ~ Δ upstream_ind + L1 + L2 | year FE\n")
cat("       (isolating pass-through of supplier carbon costs)\n")
cat("----------------------------------------------------------------\n")
m3e <- feols(d_log_ppi ~ d_exp_upi + d_exp_upi_L1 + d_exp_upi_L2 | year,
             data = panel %>% filter(!is.na(d_log_ppi),
                                      !is.na(d_exp_upi_L2)),
             cluster = ~nace4d)
print(summary(m3e))
cum_3e <- linear_combo(m3e, c("d_exp_upi", "d_exp_upi_L1", "d_exp_upi_L2"))
cat(sprintf("\nCumulative upstream-indirect pass-through: %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_3e$estimate, cum_3e$std.error, cum_3e$statistic, cum_3e$p.value))
cat("\n")

# --- S4. Distributed lag of direct exposure ---
cat("----------------------------------------------------------------\n")
cat(" [S4] log(PPI) ~ exposure_direct + L1 + L2  |  sector + year FE\n")
cat("----------------------------------------------------------------\n")
m4 <- feols(log_ppi ~ exposure_direct_total + lag1_exp_dir + lag2_exp_dir
                     | nace4d + year,
             data = panel %>%
               filter(!is.na(log_ppi), !is.na(lag1_exp_dir), !is.na(lag2_exp_dir)),
             cluster = ~nace4d)
print(summary(m4))
cat("\n")

# ===========================================================================
# NEW: Identification fixes targeting sector-specific time-varying confounds
#
# Motivation: the S1/S4 level specs give a negative coefficient on
# exposure_direct. The primary suspect is sector-specific time-varying shocks
# that correlate with exposure. E.g., high-exposure sectors (basic metals,
# cement, chemicals, refining) went through a global commodity-cycle downturn
# 2012-2016 while their ETS exposure was rising because of free-allocation
# tightening. Sector FE and year FE don't absorb this differential time path.
#
# Two remedies:
#   S5. Sector FE + NACE2d x year FE. Absorbs any time-varying shock common
#       to 2-digit industries in a year. Identification from within-2d-across-4d
#       variation.
#   S6. Sector FE + year FE + sector-specific linear trends. Assumes each 4d
#       sector has its own linear PPI drift and kills it. Cheaper in d.f. but
#       assumes trends are linear, and risks absorbing real ETS variation that
#       happens to be trend-like.
# ===========================================================================

# Linear time index for sector-specific trends
panel <- panel %>% mutate(t = year - min(year))

# --- S5a. NACE2d x year FE, levels, all sectors ---
cat("----------------------------------------------------------------\n")
cat(" [S5a] log(PPI) ~ exp_dir  |  nace4d + nace2d^year FE, all sectors\n")
cat("----------------------------------------------------------------\n")
m5a <- feols(log_ppi ~ exposure_direct_total | nace4d + nace2d^year,
             data = panel %>% filter(!is.na(log_ppi)),
             cluster = ~nace4d)
print(summary(m5a))
cat("\n")

# --- S5b. NACE2d x year FE, levels, ETS sectors only ---
cat("----------------------------------------------------------------\n")
cat(" [S5b] log(PPI) ~ exp_dir  |  nace4d + nace2d^year FE, ETS sectors only\n")
cat("----------------------------------------------------------------\n")
m5b <- feols(log_ppi ~ exposure_direct_total | nace4d + nace2d^year,
             data = panel %>% filter(!is.na(log_ppi), nace4d %in% ets_sectors),
             cluster = ~nace4d)
print(summary(m5b))
cat("\n")

# --- S5c. NACE2d x year FE, levels with distributed lag ---
cat("----------------------------------------------------------------\n")
cat(" [S5c] log(PPI) ~ exp_dir + L1 + L2  |  nace4d + nace2d^year FE\n")
cat("----------------------------------------------------------------\n")
m5c <- feols(log_ppi ~ exposure_direct_total + lag1_exp_dir + lag2_exp_dir
                     | nace4d + nace2d^year,
             data = panel %>%
               filter(!is.na(log_ppi), !is.na(lag1_exp_dir), !is.na(lag2_exp_dir)),
             cluster = ~nace4d)
print(summary(m5c))
cum_5c <- linear_combo(m5c,
  c("exposure_direct_total", "lag1_exp_dir", "lag2_exp_dir"))
cat(sprintf("\nCumulative (t + L1 + L2): %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_5c$estimate, cum_5c$std.error, cum_5c$statistic, cum_5c$p.value))
cat("\n")

# --- S5d. NACE2d x year FE, first differences ---
cat("----------------------------------------------------------------\n")
cat(" [S5d] Δ log(PPI) ~ Δ exp_dir  |  nace2d^year FE, all sectors\n")
cat("       (differences out sector FE; nace2d^year absorbs 2d cycles)\n")
cat("----------------------------------------------------------------\n")
m5d <- feols(d_log_ppi ~ d_exp_dir | nace2d^year,
             data = panel %>% filter(!is.na(d_log_ppi)),
             cluster = ~nace4d)
print(summary(m5d))
cat("\n")

# --- S5e. NACE2d x year FE, first differences with lags ---
cat("----------------------------------------------------------------\n")
cat(" [S5e] Δ log(PPI) ~ Δ exp_dir + L1 + L2  |  nace2d^year FE\n")
cat("----------------------------------------------------------------\n")
m5e <- feols(d_log_ppi ~ d_exp_dir + d_exp_dir_L1 + d_exp_dir_L2 | nace2d^year,
             data = panel %>% filter(!is.na(d_log_ppi),
                                      !is.na(d_exp_dir_L1),
                                      !is.na(d_exp_dir_L2)),
             cluster = ~nace4d)
print(summary(m5e))
cum_5e <- linear_combo(m5e, c("d_exp_dir", "d_exp_dir_L1", "d_exp_dir_L2"))
cat(sprintf("\nCumulative pass-through: %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_5e$estimate, cum_5e$std.error, cum_5e$statistic, cum_5e$p.value))
cat("\n")

# --- S6a. Sector-specific linear trends, levels, all sectors ---
# Implemented as nace4d[t] in fixest: varying slopes on t by nace4d
cat("----------------------------------------------------------------\n")
cat(" [S6a] log(PPI) ~ exp_dir  |  nace4d[t] + year FE, all sectors\n")
cat("       (sector-specific linear trends)\n")
cat("----------------------------------------------------------------\n")
m6a <- feols(log_ppi ~ exposure_direct_total | nace4d[t] + year,
             data = panel %>% filter(!is.na(log_ppi)),
             cluster = ~nace4d)
print(summary(m6a))
cat("\n")

# --- S6b. Sector-specific linear trends, levels, ETS sectors only ---
cat("----------------------------------------------------------------\n")
cat(" [S6b] log(PPI) ~ exp_dir  |  nace4d[t] + year FE, ETS sectors only\n")
cat("----------------------------------------------------------------\n")
m6b <- feols(log_ppi ~ exposure_direct_total | nace4d[t] + year,
             data = panel %>% filter(!is.na(log_ppi), nace4d %in% ets_sectors),
             cluster = ~nace4d)
print(summary(m6b))
cat("\n")

# --- S6c. Sector-specific linear trends, levels with distributed lag ---
cat("----------------------------------------------------------------\n")
cat(" [S6c] log(PPI) ~ exp_dir + L1 + L2  |  nace4d[t] + year FE\n")
cat("----------------------------------------------------------------\n")
m6c <- feols(log_ppi ~ exposure_direct_total + lag1_exp_dir + lag2_exp_dir
                     | nace4d[t] + year,
             data = panel %>%
               filter(!is.na(log_ppi), !is.na(lag1_exp_dir), !is.na(lag2_exp_dir)),
             cluster = ~nace4d)
print(summary(m6c))
cum_6c <- linear_combo(m6c,
  c("exposure_direct_total", "lag1_exp_dir", "lag2_exp_dir"))
cat(sprintf("\nCumulative (t + L1 + L2): %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_6c$estimate, cum_6c$std.error, cum_6c$statistic, cum_6c$p.value))
cat("\n")

# ===========================================================================
# S7 / S8: Känzig (2025 JMP) CPShock identification
#
# Motivation: even though EUA_t is exogenous to Belgian-sector-specific
# shocks (small-country argument), it may still correlate with euro-area-
# wide macro variables (gas, oil, demand) that also affect Belgian PPIs.
# Känzig's refined carbon policy surprise orthogonalizes daily EUA moves
# against pre-event macro/financial/oil news, so its variation reflects
# ETS regulatory decisions (cap changes, NAP approvals, MSR) rather than
# macro co-movement.
#
# Identification: interact aggregate CPShock_t (Känzig 2025) with each
# NACE4d sector's base-period shortage intensity. Sector FE absorb the
# time-invariant intensity; year FE absorb the aggregate CPShock_t and
# all other aggregate confounders. γ is identified purely from within-
# year cross-sector variation in how much the shock bites into costs.
#
# Reduced-form specs:
#   S7a. log(PPI) ~ CPShock × intensity | nace4d + year (all sec)
#   S7b. same, ETS sectors only
#   S7c. Δ log(PPI) ~ Δ(CPShock × intensity) | year FE
#   S7d. distributed lag in levels: t + L1 + L2
#
# IV spec (Strategy B, synthesis doc):
#   S8a. log(PPI) ~ exp_direct  |  nace4d + year  |  exp_direct ~ CPShock×int
#   S8b. same, ETS sectors only
#
# Base period for sector intensity: 2013-2016 (post-auctioning, pre-MSR).
# Uses exposure_alt so the base-period cost denominator is already fixed
# to 2010-2012 — no mechanical drift in the intensity weights.
#
# Sample: 2005-2019 (Känzig JMP window; Surprise series ends 2019M12).
# BKR 2024 extension deferred; will revisit if S7/S8 results are promising.
# ===========================================================================

# Load Kaenzig annual surprise series
load(file.path(OUT_DATA, "cpshock_annual.RData"))

# Base-period shortage intensity per NACE4d sector
intensity_base_df <- panel %>%
  filter(year %in% 2013:2016) %>%
  group_by(nace4d) %>%
  summarise(intensity_base = mean(exposure_alt_total, na.rm = TRUE),
            .groups = "drop")

# Merge, build interaction, restrict to Kaenzig window.
# Two RHS variants:
#   cpshock_surprise = raw refined event-day surprise (external instrument)
#   cpshock_shock    = VAR-identified structural shock (Kaenzig Step 5 output)
# Our Kaenzig-HICP replication (separate script) shows that the Shock column
# reproduces his published IRF magnitudes very closely, while Surprise is
# noisier. We run both variants for our sector-PPI specs.
panel_cp <- panel %>%
  left_join(cpshock_annual %>% select(year, cpshock_surprise, cpshock_shock),
            by = "year") %>%
  left_join(intensity_base_df, by = "nace4d") %>%
  mutate(
    intensity_base     = coalesce(intensity_base, 0),
    cpshock_x_int      = cpshock_surprise * intensity_base,
    cpshock_shk_x_int  = cpshock_shock    * intensity_base
  ) %>%
  filter(year >= 2005, year <= 2019) %>%
  arrange(nace4d, year) %>%
  group_by(nace4d) %>%
  mutate(
    # Surprise-based lags/diffs
    d_cpshock_x_int       = cpshock_x_int - lag(cpshock_x_int),
    l1_cpshock_x_int      = lag(cpshock_x_int, 1),
    l2_cpshock_x_int      = lag(cpshock_x_int, 2),
    # Shock-based lags/diffs
    d_cpshock_shk_x_int   = cpshock_shk_x_int - lag(cpshock_shk_x_int),
    l1_cpshock_shk_x_int  = lag(cpshock_shk_x_int, 1),
    l2_cpshock_shk_x_int  = lag(cpshock_shk_x_int, 2)
  ) %>%
  ungroup()

cat(sprintf(
  "\nCPShock panel: %d rows, %d NACE4d, years %d-%d; %d sectors with intensity_base > 0\n",
  nrow(panel_cp), n_distinct(panel_cp$nace4d),
  min(panel_cp$year), max(panel_cp$year),
  n_distinct(panel_cp$nace4d[panel_cp$intensity_base > 0])))

# --- S7a. Reduced form, levels, all sectors ---
cat("----------------------------------------------------------------\n")
cat(" [S7a] log(PPI) ~ CPShock_t × intensity_base_s  |  nace4d + year (all sec)\n")
cat("----------------------------------------------------------------\n")
m7a <- feols(log_ppi ~ cpshock_x_int | nace4d + year,
             data = panel_cp %>% filter(!is.na(log_ppi)),
             cluster = ~nace4d)
print(summary(m7a))
cat("\n")

# --- S7b. Reduced form, levels, ETS sectors only ---
cat("----------------------------------------------------------------\n")
cat(" [S7b] log(PPI) ~ CPShock × intensity  |  nace4d + year (ETS sec only)\n")
cat("----------------------------------------------------------------\n")
m7b <- feols(log_ppi ~ cpshock_x_int | nace4d + year,
             data = panel_cp %>%
               filter(!is.na(log_ppi), nace4d %in% ets_sectors),
             cluster = ~nace4d)
print(summary(m7b))
cat("\n")

# --- S7c. Reduced form, first differences, all sectors ---
cat("----------------------------------------------------------------\n")
cat(" [S7c] Δ log(PPI) ~ Δ (CPShock × intensity)  |  year FE (all sec)\n")
cat("----------------------------------------------------------------\n")
m7c <- feols(d_log_ppi ~ d_cpshock_x_int | year,
             data = panel_cp %>% filter(!is.na(d_log_ppi),
                                         !is.na(d_cpshock_x_int)),
             cluster = ~nace4d)
print(summary(m7c))
cat("\n")

# --- S7d. Distributed lag in levels, h = 0, 1, 2 ---
cat("----------------------------------------------------------------\n")
cat(" [S7d] log(PPI) ~ CPShock × int + L1 + L2  |  nace4d + year\n")
cat("----------------------------------------------------------------\n")
m7d <- feols(log_ppi ~ cpshock_x_int + l1_cpshock_x_int + l2_cpshock_x_int
                     | nace4d + year,
             data = panel_cp %>% filter(!is.na(log_ppi),
                                         !is.na(l1_cpshock_x_int),
                                         !is.na(l2_cpshock_x_int)),
             cluster = ~nace4d)
print(summary(m7d))
cum_7d <- linear_combo(m7d,
  c("cpshock_x_int", "l1_cpshock_x_int", "l2_cpshock_x_int"))
cat(sprintf("\nCumulative (t + L1 + L2): %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_7d$estimate, cum_7d$std.error, cum_7d$statistic, cum_7d$p.value))
cat("\n")

# --- First-stage diagnostic for the IV design ---
cat("----------------------------------------------------------------\n")
cat(" First-stage diagnostic: does CPShock × intensity predict exp_direct?\n")
cat("   exp_direct_{s,t} ~ CPShock × intensity | nace4d + year\n")
cat("----------------------------------------------------------------\n")
m_fs <- feols(exposure_direct_total ~ cpshock_x_int | nace4d + year,
              data = panel_cp %>% filter(!is.na(log_ppi)),
              cluster = ~nace4d)
print(summary(m_fs))
cat("\n")

# --- S8. IV: exp_direct instrumented by CPShock × intensity ---
# Guarded with tryCatch because very weak first stage can make the fitted
# endogenous collinear with FE.
cat("----------------------------------------------------------------\n")
cat(" [S8a] log(PPI) ~ exp_direct  (IV: CPShock × intensity)  |  nace4d + year\n")
cat("       Additionally purges EUA_t of euro-area macro/oil co-movement.\n")
cat("----------------------------------------------------------------\n")
m8a <- tryCatch(
  feols(log_ppi ~ 1 | nace4d + year |
          exposure_direct_total ~ cpshock_x_int,
        data = panel_cp %>% filter(!is.na(log_ppi)),
        cluster = ~nace4d),
  error = function(e) { cat("S8a failed:", conditionMessage(e), "\n"); NULL })
if (!is.null(m8a)) print(summary(m8a))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S8b] IV same as S8a, ETS sectors only\n")
cat("----------------------------------------------------------------\n")
m8b <- tryCatch(
  feols(log_ppi ~ 1 | nace4d + year |
          exposure_direct_total ~ cpshock_x_int,
        data = panel_cp %>%
          filter(!is.na(log_ppi), nace4d %in% ets_sectors),
        cluster = ~nace4d),
  error = function(e) { cat("S8b failed:", conditionMessage(e), "\n"); NULL })
if (!is.null(m8b)) print(summary(m8b))
cat("\n")

# ===========================================================================
# Weak-first-stage diagnosis: because exposure_direct is a LEVEL and
# CPShock is an annual aggregate of daily SURPRISES (mean-zero, non-trending),
# the first stage of exp_direct on CPShock × intensity is near zero after
# year FE absorb the EUA-price trend. Three fixes, each addressing the
# mismatch in a different way:
#
#   Fix 1 (S8c): Use Δexposure as the endogenous variable (flow-on-flow).
#   Fix 2 (S9):  Use cumulative CPShock as proxy for the EUA level.
#   Fix 3 (S10): Local projections at h = 0, 1, 2, 3 (Kaenzig eq 10 panel).
# ===========================================================================

# ---- Fix 1 (S8c): Δexposure IV with CPShock × intensity ----
cat("----------------------------------------------------------------\n")
cat(" First-stage for Δexposure: Δ exp_direct ~ CPShock × int  |  year FE\n")
cat("----------------------------------------------------------------\n")
m_fs_dx <- feols(d_exp_dir ~ cpshock_x_int | year,
                 data = panel_cp %>%
                   filter(!is.na(d_log_ppi),
                          !is.na(d_exp_dir),
                          !is.na(cpshock_x_int)),
                 cluster = ~nace4d)
print(summary(m_fs_dx))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S8c] Δ log(PPI) ~ Δ exp_direct  (IV: CPShock × intensity)  |  year FE\n")
cat("       Flow-on-flow match; should improve over S8 levels IV\n")
cat("----------------------------------------------------------------\n")
m8c <- tryCatch(
  feols(d_log_ppi ~ 1 | year | d_exp_dir ~ cpshock_x_int,
        data = panel_cp %>% filter(!is.na(d_log_ppi),
                                   !is.na(d_exp_dir),
                                   !is.na(cpshock_x_int)),
        cluster = ~nace4d),
  error = function(e) { cat("S8c failed:", conditionMessage(e), "\n"); NULL })
if (!is.null(m8c)) print(summary(m8c))
cat("\n")

# ---- Fix 2 (S9): Cumulative CPShock as proxy for EUA level ----
# Build cumulative shocks within the 2005-2019 window
panel_cp <- panel_cp %>%
  left_join(
    cpshock_annual %>%
      filter(year >= 2005, year <= 2019) %>%
      arrange(year) %>%
      mutate(cum_cpshock = cumsum(cpshock_surprise)) %>%
      select(year, cum_cpshock),
    by = "year"
  ) %>%
  mutate(cum_cpshock_x_int = cum_cpshock * intensity_base)

cat("----------------------------------------------------------------\n")
cat(" First-stage: exp_direct ~ cum_CPShock × int  |  nace4d + year\n")
cat("----------------------------------------------------------------\n")
m_fs_cum <- feols(exposure_direct_total ~ cum_cpshock_x_int | nace4d + year,
                  data = panel_cp %>% filter(!is.na(log_ppi)),
                  cluster = ~nace4d)
print(summary(m_fs_cum))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S9a] log(PPI) ~ cum_CPShock × intensity  (RF)  |  nace4d + year (all)\n")
cat("----------------------------------------------------------------\n")
m9a <- feols(log_ppi ~ cum_cpshock_x_int | nace4d + year,
             data = panel_cp %>% filter(!is.na(log_ppi)),
             cluster = ~nace4d)
print(summary(m9a))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S9b] log(PPI) ~ cum_CPShock × intensity  (RF)  |  nace4d + year (ETS)\n")
cat("----------------------------------------------------------------\n")
m9b <- feols(log_ppi ~ cum_cpshock_x_int | nace4d + year,
             data = panel_cp %>%
               filter(!is.na(log_ppi), nace4d %in% ets_sectors),
             cluster = ~nace4d)
print(summary(m9b))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S9c] log(PPI) ~ exp_direct  (IV: cum_CPShock × int)  |  nace4d + year\n")
cat("----------------------------------------------------------------\n")
m9c <- tryCatch(
  feols(log_ppi ~ 1 | nace4d + year |
          exposure_direct_total ~ cum_cpshock_x_int,
        data = panel_cp %>% filter(!is.na(log_ppi)),
        cluster = ~nace4d),
  error = function(e) { cat("S9c failed:", conditionMessage(e), "\n"); NULL })
if (!is.null(m9c)) print(summary(m9c))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [S9d] log(PPI) ~ exp_direct  (IV: cum_CPShock × int)  |  nace4d + year (ETS)\n")
cat("----------------------------------------------------------------\n")
m9d <- tryCatch(
  feols(log_ppi ~ 1 | nace4d + year |
          exposure_direct_total ~ cum_cpshock_x_int,
        data = panel_cp %>%
          filter(!is.na(log_ppi), nace4d %in% ets_sectors),
        cluster = ~nace4d),
  error = function(e) { cat("S9d failed:", conditionMessage(e), "\n"); NULL })
if (!is.null(m9d)) print(summary(m9d))
cat("\n")

# ---- Fix 3 (S10): Local projections, h = 0, 1, 2, 3 ----
# Builds lead variables of log_ppi for the LP.
panel_cp <- panel_cp %>%
  arrange(nace4d, year) %>%
  group_by(nace4d) %>%
  mutate(
    log_ppi_h1 = lead(log_ppi, 1),
    log_ppi_h2 = lead(log_ppi, 2),
    log_ppi_h3 = lead(log_ppi, 3)
  ) %>%
  ungroup()

cat("----------------------------------------------------------------\n")
cat(" [S10] Local projections (Kaenzig 2025 eq 10 panel):\n")
cat("       log_ppi_{s,t+h} ~ CPShock_t × intensity_base_s | nace4d + year\n")
cat("----------------------------------------------------------------\n")
lp_results <- data.frame(h = integer(), coef = numeric(), se = numeric(),
                         lo = numeric(), hi = numeric(), n = integer(),
                         sample = character())
run_lp <- function(sample_label, sample_filter) {
  for (h in 0:3) {
    y_col <- if (h == 0) "log_ppi" else paste0("log_ppi_h", h)
    dat <- panel_cp %>%
      filter(!is.na(.data[[y_col]])) %>%
      (\(d) if (sample_filter == "ets") d %>% filter(nace4d %in% ets_sectors) else d)()
    frm <- as.formula(sprintf("%s ~ cpshock_x_int | nace4d + year", y_col))
    m_lp <- feols(frm, data = dat, cluster = ~nace4d)
    cat(sprintf("\n  sample = %s, h = %d\n", sample_label, h))
    print(summary(m_lp))
    ct <- coeftable(m_lp)["cpshock_x_int", ]
    lp_results <<- rbind(lp_results, data.frame(
      h = h, coef = ct[1], se = ct[2],
      lo = ct[1] - 1.96 * ct[2],
      hi = ct[1] + 1.96 * ct[2],
      n = m_lp$nobs,
      sample = sample_label
    ))
  }
}
run_lp("all",         "all")
run_lp("ETS-only",    "ets")

cat("\nLocal projections summary:\n")
print(lp_results)
cat("\n")

# ===========================================================================
# Shock-based robustness (following Kaenzig 2025 Appendix C.6)
#
# Rationale: our HICP replication (phase3_replicate_kanzig_hicp.R) shows
# that regressing outcomes on the VAR-identified Shock column gives
# headline IRFs that match Kaenzig's published benchmark almost exactly
# (+0.19% vs his +0.2%). Surprise-based reduced form is noisier. Re-run
# S7a/b/c/d and LP at h=0..3 with Shock for a cleaner validation of our
# sector-PPI pass-through estimates.
#
# Important caveat: using `cpshock_shock` imports Kaenzig's VAR
# identification assumptions; it is not a purely reduced-form exercise.
# The Surprise-based specs remain our primary analysis.
# ===========================================================================

cat("\n================================================================\n")
cat(" S7-S10 Shock-based robustness  (RHS = Kaenzig structural Shock)\n")
cat("================================================================\n\n")

# --- S7a-shk ---
cat("----------------------------------------------------------------\n")
cat(" [S7a-shk] log(PPI) ~ Shock × intensity  |  nace4d + year (all)\n")
cat("----------------------------------------------------------------\n")
m7a_shk <- feols(log_ppi ~ cpshock_shk_x_int | nace4d + year,
                 data = panel_cp %>% filter(!is.na(log_ppi)),
                 cluster = ~nace4d)
print(summary(m7a_shk))
cat("\n")

# --- S7b-shk ---
cat("----------------------------------------------------------------\n")
cat(" [S7b-shk] log(PPI) ~ Shock × intensity  |  nace4d + year (ETS)\n")
cat("----------------------------------------------------------------\n")
m7b_shk <- feols(log_ppi ~ cpshock_shk_x_int | nace4d + year,
                 data = panel_cp %>%
                   filter(!is.na(log_ppi), nace4d %in% ets_sectors),
                 cluster = ~nace4d)
print(summary(m7b_shk))
cat("\n")

# --- S7c-shk ---
cat("----------------------------------------------------------------\n")
cat(" [S7c-shk] Δ log(PPI) ~ Δ(Shock × intensity)  |  year FE (all)\n")
cat("----------------------------------------------------------------\n")
m7c_shk <- feols(d_log_ppi ~ d_cpshock_shk_x_int | year,
                 data = panel_cp %>% filter(!is.na(d_log_ppi),
                                             !is.na(d_cpshock_shk_x_int)),
                 cluster = ~nace4d)
print(summary(m7c_shk))
cat("\n")

# --- S7d-shk: distributed lag ---
cat("----------------------------------------------------------------\n")
cat(" [S7d-shk] log(PPI) ~ Shock × int + L1 + L2  |  nace4d + year\n")
cat("----------------------------------------------------------------\n")
m7d_shk <- feols(log_ppi ~ cpshock_shk_x_int + l1_cpshock_shk_x_int +
                           l2_cpshock_shk_x_int
                       | nace4d + year,
                 data = panel_cp %>% filter(!is.na(log_ppi),
                                             !is.na(l1_cpshock_shk_x_int),
                                             !is.na(l2_cpshock_shk_x_int)),
                 cluster = ~nace4d)
print(summary(m7d_shk))
cum_7d_shk <- linear_combo(m7d_shk,
  c("cpshock_shk_x_int", "l1_cpshock_shk_x_int", "l2_cpshock_shk_x_int"))
cat(sprintf("\nCumulative (t + L1 + L2): %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_7d_shk$estimate, cum_7d_shk$std.error,
            cum_7d_shk$statistic, cum_7d_shk$p.value))
cat("\n")

# --- LP-shk at h = 0, 1, 2, 3 ---
cat("----------------------------------------------------------------\n")
cat(" [S10-shk] Local projections with Shock RHS (h = 0, 1, 2, 3)\n")
cat("----------------------------------------------------------------\n")
lp_results_shk <- data.frame(h = integer(), coef = numeric(), se = numeric(),
                             lo = numeric(), hi = numeric(), n = integer(),
                             sample = character())
run_lp_shk <- function(sample_label, sample_filter) {
  for (h in 0:3) {
    y_col <- if (h == 0) "log_ppi" else paste0("log_ppi_h", h)
    dat <- panel_cp %>%
      filter(!is.na(.data[[y_col]])) %>%
      (\(d) if (sample_filter == "ets") d %>% filter(nace4d %in% ets_sectors) else d)()
    frm <- as.formula(sprintf("%s ~ cpshock_shk_x_int | nace4d + year", y_col))
    m_lp <- feols(frm, data = dat, cluster = ~nace4d)
    cat(sprintf("\n  sample = %s, h = %d\n", sample_label, h))
    print(summary(m_lp))
    ct <- coeftable(m_lp)["cpshock_shk_x_int", ]
    lp_results_shk <<- rbind(lp_results_shk, data.frame(
      h = h, coef = ct[1], se = ct[2],
      lo = ct[1] - 1.96 * ct[2],
      hi = ct[1] + 1.96 * ct[2],
      n = m_lp$nobs,
      sample = sample_label
    ))
  }
}
run_lp_shk("all",      "all")
run_lp_shk("ETS-only", "ets")

cat("\nShock-based LP summary:\n")
print(lp_results_shk)
cat("\n")

# ===========================================================================
# S11 — Phase IV CPShock (2020-2024) using our own rebuilt surprise series
#
# Motivation: Kaenzig's CPShock ends 2019. Phase IV (EUA €25 → €98) is where
# the carbon shock becomes quantitatively meaningful. We rebuild the annual
# shock from BKR (2026) Appendix A.1 (45 events, 2020-2024) + ICE EUA front-
# month futures (investing.com CFI2), using log-return normalization (BKR
# Figure B.7 / B.3 robustness). Sample extends to 2024 because the interaction
# spec only needs base-period intensity (time-invariant) + PPI + CPShock.
#
# Specs:
#   S11a. log(PPI) ~ CPShock_p4 × intensity_base | nace4d + year (all)
#   S11b. same, ETS sectors only
#   S11c. Percent-change CPShock (BKR Fig B.3) — robustness
#   S11d. Local projections h = 0, 1, 2
# ===========================================================================

load(file.path(OUT_DATA, "cpshock_phase4_annual.RData"))

cat("\n================================================================\n")
cat(" S11 — Phase IV CPShock on 2020-2024 panel\n")
cat("================================================================\n")
cat("Annual CPShock_y (Phase IV, log-return normalization):\n")
print(cpshock_phase4_annual)
cat("\n")

# Build 2020-2024 panel with base-period intensity from earlier block
# Reuses intensity_base_df computed for S7-S10
panel_p4 <- deflator %>%
  select(nace4d, nace2d, year, ppi) %>%
  filter(year >= 2020, year <= 2024) %>%
  left_join(intensity_base_df, by = "nace4d") %>%
  left_join(cpshock_phase4_annual %>%
              select(year, cpshock_logret, cpshock_pct, n_events),
            by = "year") %>%
  mutate(
    intensity_base      = coalesce(intensity_base, 0),
    log_ppi             = log(ppi),
    cpshock_x_int_p4    = cpshock_logret * intensity_base,
    cpshock_x_int_p4pct = cpshock_pct    * intensity_base
  )

cat(sprintf("Panel P4: %d rows, %d sectors, years %d-%d; %d sectors with intensity > 0\n",
            nrow(panel_p4), n_distinct(panel_p4$nace4d),
            min(panel_p4$year), max(panel_p4$year),
            n_distinct(panel_p4$nace4d[panel_p4$intensity_base > 0])))

# --- S11a. Levels RF, all sectors ---
cat("----------------------------------------------------------------\n")
cat(" [S11a] log(PPI) ~ CPShock_p4(log-ret) × intensity  |  nace4d + year (all)\n")
cat("----------------------------------------------------------------\n")
m11a <- feols(log_ppi ~ cpshock_x_int_p4 | nace4d + year,
              data = panel_p4 %>% filter(!is.na(log_ppi)),
              cluster = ~nace4d)
print(summary(m11a))
cat("\n")

# --- S11b. Levels RF, ETS sectors only ---
cat("----------------------------------------------------------------\n")
cat(" [S11b] log(PPI) ~ CPShock_p4(log-ret) × intensity  |  nace4d + year (ETS)\n")
cat("----------------------------------------------------------------\n")
m11b <- feols(log_ppi ~ cpshock_x_int_p4 | nace4d + year,
              data = panel_p4 %>%
                filter(!is.na(log_ppi), nace4d %in% ets_sectors),
              cluster = ~nace4d)
print(summary(m11b))
cat("\n")

# --- S11c. Percent-change robustness (BKR Figure B.3 formula) ---
cat("----------------------------------------------------------------\n")
cat(" [S11c] log(PPI) ~ CPShock_p4(%-change) × intensity  |  nace4d + year (all)\n")
cat("        BKR Figure B.3 alternative scaling\n")
cat("----------------------------------------------------------------\n")
m11c <- feols(log_ppi ~ cpshock_x_int_p4pct | nace4d + year,
              data = panel_p4 %>% filter(!is.na(log_ppi)),
              cluster = ~nace4d)
print(summary(m11c))
cat("\n")

# --- S11d. Local projections h = 0, 1, 2 (LP at longer h hits panel end) ---
cat("----------------------------------------------------------------\n")
cat(" [S11d] LP Phase IV: log(PPI)_{t+h} ~ CPShock_p4 × int  (h = 0, 1, 2)\n")
cat("----------------------------------------------------------------\n")
panel_p4 <- panel_p4 %>%
  arrange(nace4d, year) %>%
  group_by(nace4d) %>%
  mutate(
    log_ppi_h1 = lead(log_ppi, 1),
    log_ppi_h2 = lead(log_ppi, 2)
  ) %>%
  ungroup()

lp_p4 <- data.frame(h = integer(), coef = numeric(), se = numeric(),
                    lo = numeric(), hi = numeric(), n = integer(),
                    sample = character())
run_lp_p4 <- function(sample_label, sample_filter) {
  for (h in 0:2) {
    y_col <- if (h == 0) "log_ppi" else paste0("log_ppi_h", h)
    dat <- panel_p4 %>%
      filter(!is.na(.data[[y_col]])) %>%
      (\(d) if (sample_filter == "ets") d %>% filter(nace4d %in% ets_sectors) else d)()
    frm <- as.formula(sprintf("%s ~ cpshock_x_int_p4 | nace4d + year", y_col))
    m_lp <- feols(frm, data = dat, cluster = ~nace4d)
    cat(sprintf("\n  sample = %s, h = %d\n", sample_label, h))
    print(summary(m_lp))
    ct <- coeftable(m_lp)
    if ("cpshock_x_int_p4" %in% rownames(ct)) {
      r <- ct["cpshock_x_int_p4", ]
      lp_p4 <<- rbind(lp_p4, data.frame(
        h = h, coef = r[1], se = r[2],
        lo = r[1] - 1.96 * r[2],
        hi = r[1] + 1.96 * r[2],
        n = m_lp$nobs,
        sample = sample_label
      ))
    }
  }
}
run_lp_p4("all",      "all")
run_lp_p4("ETS-only", "ets")

cat("\nPhase IV LP summary:\n")
print(lp_p4)
cat("\n")

# ===========================================================================
# DIAGNOSTIC: Headline specs re-run with base-period-fixed-denominator
# exposure (exposure_alt_total). All time variation comes from
# shortage_{s,t} * EUA_t, not from current cost inflation.
#
# If the negative coefficient in S1/S5 was driven by the endogenous cost
# denominator, exposure_alt_* should give a cleaner (less negative or
# positive) coefficient. If the negative coefficient persists, it's the
# "selection into exposure" story (high-exposure sectors structurally have
# weaker pricing power) rather than a denominator artefact.
# ===========================================================================
cat("\n================================================================\n")
cat(" DIAGNOSTIC: same specs with base-period-fixed-denominator exposure\n")
cat(" exposure_alt_{s,t} = (shortage_{s,t} * EUA_t) / mean_cost_{s,2010-12}\n")
cat("================================================================\n\n")

# --- A1 / A1b. levels, sector + year FE ---
cat("----------------------------------------------------------------\n")
cat(" [A1a] log(PPI) ~ exp_alt  |  sector + year FE, all sectors\n")
cat("----------------------------------------------------------------\n")
mA1a <- feols(log_ppi ~ exposure_alt_total | nace4d + year,
              data = panel %>% filter(!is.na(log_ppi)),
              cluster = ~nace4d)
print(summary(mA1a))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [A1b] log(PPI) ~ exp_alt  |  sector + year FE, ETS sectors only\n")
cat("----------------------------------------------------------------\n")
mA1b <- feols(log_ppi ~ exposure_alt_total | nace4d + year,
              data = panel %>% filter(!is.na(log_ppi), nace4d %in% ets_sectors),
              cluster = ~nace4d)
print(summary(mA1b))
cat("\n")

# --- A5 / A6. levels with NACE2d^year and sector-trend FE variants ---
cat("----------------------------------------------------------------\n")
cat(" [A5a] log(PPI) ~ exp_alt  |  nace4d + nace2d^year FE\n")
cat("----------------------------------------------------------------\n")
mA5a <- feols(log_ppi ~ exposure_alt_total | nace4d + nace2d^year,
              data = panel %>% filter(!is.na(log_ppi)),
              cluster = ~nace4d)
print(summary(mA5a))
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" [A6a] log(PPI) ~ exp_alt  |  nace4d[t] + year FE (sector trends)\n")
cat("----------------------------------------------------------------\n")
mA6a <- feols(log_ppi ~ exposure_alt_total | nace4d[t] + year,
              data = panel %>% filter(!is.na(log_ppi)),
              cluster = ~nace4d)
print(summary(mA6a))
cat("\n")

# --- A2. first-differences ---
cat("----------------------------------------------------------------\n")
cat(" [A2a] Δ log(PPI) ~ Δ exp_alt  |  year FE\n")
cat("----------------------------------------------------------------\n")
mA2a <- feols(d_log_ppi ~ d_exp_alt | year,
              data = panel %>% filter(!is.na(d_log_ppi)),
              cluster = ~nace4d)
print(summary(mA2a))
cat("\n")

# --- A2c. first-diff with distributed lags ---
cat("----------------------------------------------------------------\n")
cat(" [A2c] Δ log(PPI) ~ Δ exp_alt + L1 + L2  |  year FE\n")
cat("----------------------------------------------------------------\n")
mA2c <- feols(d_log_ppi ~ d_exp_alt + d_exp_alt_L1 + d_exp_alt_L2 | year,
              data = panel %>% filter(!is.na(d_log_ppi),
                                       !is.na(d_exp_alt_L1),
                                       !is.na(d_exp_alt_L2)),
              cluster = ~nace4d)
print(summary(mA2c))
cum_A2c <- linear_combo(mA2c,
  c("d_exp_alt", "d_exp_alt_L1", "d_exp_alt_L2"))
cat(sprintf("\nCumulative pass-through: %.4f  (SE %.4f, z = %.2f, p = %.4f)\n",
            cum_A2c$estimate, cum_A2c$std.error, cum_A2c$statistic, cum_A2c$p.value))
cat("\n")

# --- Coefficient summary ---
cat("================================================================\n")
cat(" Coefficient summary (all specifications)\n")
cat("================================================================\n\n")

summ <- function(label, reg, regressor) {
  ct <- coeftable(reg)
  if (regressor %in% rownames(ct)) {
    r <- ct[regressor, ]
    cat(sprintf("%-55s | %8.4f | %7.4f | %6.2f | %5d\n",
                label, r[1], r[2], r[3], reg$nobs))
  }
}
cat(sprintf("%-55s | %8s | %7s | %6s | %5s\n",
            "Specification", "coef", "se", "t", "N"))
cat(paste(rep("-", 95), collapse = ""), "\n")
summ("[S1a] log(PPI) ~ exp_dir (all sec)", m1a, "exposure_direct_total")
summ("[S1b] log(PPI) ~ exp_dir (ETS sec only)", m1b, "exposure_direct_total")
summ("[S2a] d_log(PPI) ~ d_exp_dir (all sec)", m2a, "d_exp_dir")
summ("[S2b] d_log(PPI) ~ d_exp_dir (ETS sec only)", m2b, "d_exp_dir")
summ("[S2c] d_exp_dir + L1 + L2 (all):  d_exp_dir", m2c, "d_exp_dir")
summ("[S2c] d_exp_dir + L1 + L2 (all):  L1", m2c, "d_exp_dir_L1")
summ("[S2c] d_exp_dir + L1 + L2 (all):  L2", m2c, "d_exp_dir_L2")
summ("[S2d] d_exp_dir + L1 + L2 (ETS): d_exp_dir", m2d, "d_exp_dir")
summ("[S2d] d_exp_dir + L1 + L2 (ETS): L1", m2d, "d_exp_dir_L1")
summ("[S2d] d_exp_dir + L1 + L2 (ETS): L2", m2d, "d_exp_dir_L2")
summ("[S3a] log(PPI) ~ exp_dir + upstr_ind: exp_dir", m3a, "exposure_direct_total")
summ("[S3a] log(PPI) ~ exp_dir + upstr_ind: upstr_ind", m3a, "net_upstream_ind")
summ("[S3b] log(PPI) ~ exp_dir + upstr_total: exp_dir", m3b, "exposure_direct_total")
summ("[S3b] log(PPI) ~ exp_dir + upstr_total: upstr", m3b, "net_upstream")
summ("[S3c] d_log(PPI) ~ d_exp_dir + d_upstr_ind: d_exp_dir", m3c, "d_exp_dir")
summ("[S3c] d_log(PPI) ~ d_exp_dir + d_upstr_ind: d_upstr_ind", m3c, "d_exp_upi")
summ("[S3d] d_dir + L1 + L2 & d_upi + L1 + L2: d_exp_dir", m3d, "d_exp_dir")
summ("[S3d] d_dir + L1 + L2 & d_upi + L1 + L2: d_exp_dir_L1", m3d, "d_exp_dir_L1")
summ("[S3d] d_dir + L1 + L2 & d_upi + L1 + L2: d_exp_dir_L2", m3d, "d_exp_dir_L2")
summ("[S3d] d_dir + L1 + L2 & d_upi + L1 + L2: d_exp_upi", m3d, "d_exp_upi")
summ("[S3d] d_dir + L1 + L2 & d_upi + L1 + L2: d_exp_upi_L1", m3d, "d_exp_upi_L1")
summ("[S3d] d_dir + L1 + L2 & d_upi + L1 + L2: d_exp_upi_L2", m3d, "d_exp_upi_L2")
summ("[S3e] d_upi + L1 + L2 only:  d_exp_upi", m3e, "d_exp_upi")
summ("[S3e] d_upi + L1 + L2 only:  d_exp_upi_L1", m3e, "d_exp_upi_L1")
summ("[S3e] d_upi + L1 + L2 only:  d_exp_upi_L2", m3e, "d_exp_upi_L2")
summ("[S4] log(PPI) ~ exp_dir + L1 + L2: exp_dir", m4, "exposure_direct_total")
summ("[S4] log(PPI) ~ exp_dir + L1 + L2: L1", m4, "lag1_exp_dir")
summ("[S4] log(PPI) ~ exp_dir + L1 + L2: L2", m4, "lag2_exp_dir")
# New specs targeting sector-specific trend confounds
summ("[S5a] log(PPI) ~ exp_dir | nace2d^year (all)", m5a, "exposure_direct_total")
summ("[S5b] log(PPI) ~ exp_dir | nace2d^year (ETS)", m5b, "exposure_direct_total")
summ("[S5c] exp_dir + L1 + L2 | nace2d^year: exp_dir", m5c, "exposure_direct_total")
summ("[S5c] exp_dir + L1 + L2 | nace2d^year: L1", m5c, "lag1_exp_dir")
summ("[S5c] exp_dir + L1 + L2 | nace2d^year: L2", m5c, "lag2_exp_dir")
summ("[S5d] d_log(PPI) ~ d_exp_dir | nace2d^year", m5d, "d_exp_dir")
summ("[S5e] d_exp_dir + L1 + L2 | nace2d^year: d_exp_dir", m5e, "d_exp_dir")
summ("[S5e] d_exp_dir + L1 + L2 | nace2d^year: L1", m5e, "d_exp_dir_L1")
summ("[S5e] d_exp_dir + L1 + L2 | nace2d^year: L2", m5e, "d_exp_dir_L2")
summ("[S6a] log(PPI) ~ exp_dir | nace4d[t]+year (all)", m6a, "exposure_direct_total")
summ("[S6b] log(PPI) ~ exp_dir | nace4d[t]+year (ETS)", m6b, "exposure_direct_total")
summ("[S6c] exp_dir + L1 + L2 | nace4d[t]+year: exp_dir", m6c, "exposure_direct_total")
summ("[S6c] exp_dir + L1 + L2 | nace4d[t]+year: L1", m6c, "lag1_exp_dir")
summ("[S6c] exp_dir + L1 + L2 | nace4d[t]+year: L2", m6c, "lag2_exp_dir")
# Kaenzig CPShock identification (2005-2019 window)
summ("[S7a] log(PPI) ~ CPShock*int (all)            ", m7a, "cpshock_x_int")
summ("[S7b] log(PPI) ~ CPShock*int (ETS only)       ", m7b, "cpshock_x_int")
summ("[S7c] d_log(PPI) ~ d(CPShock*int)             ", m7c, "d_cpshock_x_int")
summ("[S7d] CPShock*int + L1 + L2: t                ", m7d, "cpshock_x_int")
summ("[S7d] CPShock*int + L1 + L2: L1               ", m7d, "l1_cpshock_x_int")
summ("[S7d] CPShock*int + L1 + L2: L2               ", m7d, "l2_cpshock_x_int")
if (!is.null(m8a))
  summ("[S8a] IV exp_dir ~ CPShock*int (all)          ", m8a, "fit_exposure_direct_total")
if (!is.null(m8b))
  summ("[S8b] IV exp_dir ~ CPShock*int (ETS only)     ", m8b, "fit_exposure_direct_total")
if (!is.null(m8c))
  summ("[S8c] d_log(PPI) IV d_exp (CPShock*int)       ", m8c, "fit_d_exp_dir")
summ("[S9a] log(PPI) ~ cum_CPShock*int (all)        ", m9a, "cum_cpshock_x_int")
summ("[S9b] log(PPI) ~ cum_CPShock*int (ETS)        ", m9b, "cum_cpshock_x_int")
if (!is.null(m9c))
  summ("[S9c] IV exp_dir ~ cum_CPShock*int (all)      ", m9c, "fit_exposure_direct_total")
if (!is.null(m9d))
  summ("[S9d] IV exp_dir ~ cum_CPShock*int (ETS)      ", m9d, "fit_exposure_direct_total")
# Local projections (one row per sample × horizon)
for (i in seq_len(nrow(lp_results))) {
  r <- lp_results[i, ]
  cat(sprintf("%-55s | %8.4f | %7.4f | %6.2f | %5d\n",
              sprintf("[S10] LP h=%d (%s)", r$h, r$sample),
              r$coef, r$se, r$coef / r$se, r$n))
}
# Shock-based robustness
summ("[S7a-shk] log(PPI) ~ Shock*int (all)           ", m7a_shk, "cpshock_shk_x_int")
summ("[S7b-shk] log(PPI) ~ Shock*int (ETS)           ", m7b_shk, "cpshock_shk_x_int")
summ("[S7c-shk] d_log(PPI) ~ d(Shock*int)            ", m7c_shk, "d_cpshock_shk_x_int")
summ("[S7d-shk] Shock*int + L1 + L2: t               ", m7d_shk, "cpshock_shk_x_int")
summ("[S7d-shk] Shock*int + L1 + L2: L1              ", m7d_shk, "l1_cpshock_shk_x_int")
summ("[S7d-shk] Shock*int + L1 + L2: L2              ", m7d_shk, "l2_cpshock_shk_x_int")
for (i in seq_len(nrow(lp_results_shk))) {
  r <- lp_results_shk[i, ]
  cat(sprintf("%-55s | %8.4f | %7.4f | %6.2f | %5d\n",
              sprintf("[S10-shk] LP h=%d (%s)", r$h, r$sample),
              r$coef, r$se, r$coef / r$se, r$n))
}
# Phase IV CPShock
summ("[S11a] log(PPI) ~ CPShock_p4*int (all)         ", m11a, "cpshock_x_int_p4")
summ("[S11b] log(PPI) ~ CPShock_p4*int (ETS)         ", m11b, "cpshock_x_int_p4")
summ("[S11c] log(PPI) ~ CPShock_p4(%)*int (all)      ", m11c, "cpshock_x_int_p4pct")
for (i in seq_len(nrow(lp_p4))) {
  r <- lp_p4[i, ]
  cat(sprintf("%-55s | %8.4f | %7.4f | %6.2f | %5d\n",
              sprintf("[S11d] LP-P4 h=%d (%s)", r$h, r$sample),
              r$coef, r$se, r$coef / r$se, r$n))
}
# Alt-exposure (base-period-fixed denominator) diagnostic
summ("[A1a] log(PPI) ~ exp_alt (all)              ", mA1a, "exposure_alt_total")
summ("[A1b] log(PPI) ~ exp_alt (ETS only)         ", mA1b, "exposure_alt_total")
summ("[A5a] log(PPI) ~ exp_alt | nace2d^year (all)", mA5a, "exposure_alt_total")
summ("[A6a] log(PPI) ~ exp_alt | nace4d[t]+year   ", mA6a, "exposure_alt_total")
summ("[A2a] d_log(PPI) ~ d_exp_alt (all)          ", mA2a, "d_exp_alt")
summ("[A2c] d_exp_alt + L1 + L2: d_exp_alt        ", mA2c, "d_exp_alt")
summ("[A2c] d_exp_alt + L1 + L2: L1               ", mA2c, "d_exp_alt_L1")
summ("[A2c] d_exp_alt + L1 + L2: L2               ", mA2c, "d_exp_alt_L2")
cat("\n")

# --- Cumulative pass-through summary ---
cat("----------------------------------------------------------------\n")
cat(" Cumulative pass-through (sum of contemporaneous + lagged diffs)\n")
cat(" Joint Wald test of (beta_0 + beta_1 + beta_2) = 0\n")
cat("----------------------------------------------------------------\n")
print_cum <- function(label, h, n) {
  cat(sprintf("%-55s | %8.4f | %7.4f | %6.2f | %.4f | %d\n",
              label, h$estimate, h$std.error, h$statistic, h$p.value, n))
}
cat(sprintf("%-55s | %8s | %7s | %6s | %6s | %5s\n",
            "Specification", "cum coef", "se", "stat", "p", "N"))
cat(paste(rep("-", 95), collapse = ""), "\n")
print_cum("[S2c] sum direct lags (all sec)",           cum_2c,     m2c$nobs)
print_cum("[S2d] sum direct lags (ETS sec only)",      cum_2d,     m2d$nobs)
print_cum("[S3d] sum direct lags (w/ network)",        cum_3d_dir, m3d$nobs)
print_cum("[S3d] sum upstream-indirect lags (w/ direct)", cum_3d_upi, m3d$nobs)
print_cum("[S3e] sum upstream-indirect lags (no direct)", cum_3e,    m3e$nobs)
print_cum("[S5c] sum direct (lev) | nace2d^year",      cum_5c,     m5c$nobs)
print_cum("[S5e] sum direct (diff) | nace2d^year",     cum_5e,     m5e$nobs)
print_cum("[S6c] sum direct (lev) | nace4d[t]+year",   cum_6c,     m6c$nobs)
print_cum("[S7d] sum CPShock*int lags (lev)",          cum_7d,     m7d$nobs)
print_cum("[S7d-shk] sum Shock*int lags (lev)",        cum_7d_shk, m7d_shk$nobs)
print_cum("[A2c] sum alt-exp lags (first diff)",      cum_A2c,    mA2c$nobs)
cat("\n")

cat("----------------------------------------------------------------\n")
cat(" Interpretation (coefficient scale)\n")
cat("----------------------------------------------------------------\n")
cat("log(PPI) and Δ log(PPI) are unitless. Exposure is in share units\n")
cat("(fraction of sector total cost). A coefficient of 1.0 on exp_direct\n")
cat("means a 1-percentage-point rise in sector exposure raises the\n")
cat("sector PPI by ~1 log point (~1%). Full pass-through would give a\n")
cat("coefficient near 1; weaker pass-through gives coefficients < 1.\n")
cat("Negative or noisy near-zero coefficients imply no systematic\n")
cat("pass-through of the ETS carbon-cost shock into sector prices.\n")

sink()

cat("Regression output written to:",
    file.path(OUTPUT_TAB, "phase3_task2_passthrough_regs.txt"), "\n")

# ===========================================================================
# Event study around the MSR reform (2017-2018 break)
#
# For each NACE4d sector, compute log PPI relative to 2016 and overlay by
# exposure tercile (tercile of mean exposure_direct_total over 2017-2021).
# ===========================================================================
cat("\n=== Event study around MSR reform (2017 break) ===\n")

# Mean post-reform exposure per sector
sector_mean_exp <- panel %>%
  filter(year %in% 2017:2021) %>%
  group_by(nace4d) %>%
  summarise(mean_exp = mean(exposure_direct_total, na.rm = TRUE),
            .groups = "drop") %>%
  filter(!is.na(mean_exp))

# Terciles of POSITIVE exposure; sectors with zero exposure are the control
pos <- sector_mean_exp %>% filter(mean_exp > 0)
qs  <- quantile(pos$mean_exp, probs = c(1/3, 2/3), na.rm = TRUE)

sector_group <- sector_mean_exp %>%
  mutate(group = case_when(
    mean_exp == 0      ~ "Zero-exposure (control)",
    mean_exp <= qs[1]  ~ "Low exposure (T1)",
    mean_exp <= qs[2]  ~ "Mid exposure (T2)",
    TRUE               ~ "High exposure (T3)"
  ))

# Build event-study plot data: mean log_ppi relative to 2016 within each group
es <- panel %>%
  filter(year >= 2010, year <= 2022) %>%
  left_join(sector_group %>% select(nace4d, group), by = "nace4d") %>%
  filter(!is.na(group), !is.na(log_ppi))

# Anchor each sector to its 2016 log_ppi, then compute within-group mean
es <- es %>%
  group_by(nace4d) %>%
  mutate(log_ppi_anchor = log_ppi[year == 2016][1],
         log_ppi_rel    = log_ppi - log_ppi_anchor) %>%
  ungroup()

es_summary <- es %>%
  group_by(group, year) %>%
  summarise(mean_rel = mean(log_ppi_rel, na.rm = TRUE),
            n        = n_distinct(nace4d),
            .groups  = "drop")

p_es <- ggplot(es_summary, aes(x = year, y = 100 * mean_rel, color = group)) +
  geom_vline(xintercept = 2017, linetype = "dashed", color = "grey40") +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.8) +
  annotate("text", x = 2017.1, y = min(100 * es_summary$mean_rel) - 1,
           label = "MSR reform", size = 3, hjust = 0, color = "grey30") +
  scale_color_manual(values = c("Zero-exposure (control)" = "#7f7f7f",
                                "Low exposure (T1)" = "#9ecae1",
                                "Mid exposure (T2)" = "#3182bd",
                                "High exposure (T3)" = "#08306b"),
                     name = NULL) +
  labs(
    title = "Event study: sector PPIs around the 2017 MSR reform",
    subtitle = "log(PPI) relative to 2016, averaged within sector-exposure groups (based on 2017-2021 mean direct exposure).",
    x = NULL, y = "Percent change in PPI since 2016"
  ) +
  theme_bw(base_size = 10) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave(file.path(OUTPUT_FIG, "phase3_task2_event_study.pdf"), p_es,
       width = 9, height = 5.5)

cat("Event study saved to:",
    file.path(OUTPUT_FIG, "phase3_task2_event_study.pdf"), "\n")

# ===========================================================================
# Local-projection IRF plot (S10)
# ===========================================================================
p_lp <- ggplot(lp_results, aes(x = h, y = coef, color = sample, fill = sample)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
  geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.20, color = NA) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.5) +
  scale_color_manual(values = c("all" = "#08306b", "ETS-only" = "#cb181d")) +
  scale_fill_manual(values  = c("all" = "#3182bd", "ETS-only" = "#fb6a4a")) +
  labs(
    title = "Local projection: PPI response to carbon policy surprise × sector intensity",
    subtitle = "log(PPI)_{s,t+h} regressed on CPShock_t × base-period intensity (2005-2019, NACE4d + year FE)",
    x = "Horizon (years since shock)",
    y = expression(gamma[h]),
    color = NULL, fill = NULL
  ) +
  theme_bw(base_size = 10) +
  theme(plot.title = element_text(face = "bold"),
        legend.position = "bottom")

ggsave(file.path(OUTPUT_FIG, "phase3_task2_cpshock_lp.pdf"), p_lp,
       width = 8, height = 5)
cat("LP IRF saved to:",
    file.path(OUTPUT_FIG, "phase3_task2_cpshock_lp.pdf"), "\n")

cat("\nDone.\n")
