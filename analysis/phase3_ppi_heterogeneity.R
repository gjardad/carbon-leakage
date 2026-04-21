###############################################################################
# phase3_ppi_heterogeneity.R
#
# PURPOSE:
#   Investigate heterogeneity in carbon-cost pass-through across Belgian NACE4d
#   sectors. Two dimensions:
#     1. Kaenzig-style interaction: pass-through × pre-period shortage intensity
#        tercile. Tests whether high-exposure sectors show meaningfully larger
#        pass-through than marginally-exposed sectors.
#     2. NACE2d-specific pass-through: run the sector-trend spec separately for
#        the biggest ETS 2-digit industries (steel, cement/glass, chemicals,
#        petroleum, electricity) to see if the aggregate near-zero coefficient
#        is an average over positive and negative sectors.
#
# BASELINE SPEC:
#   S6 (sector-specific linear trends) on exposure_alt (base-period-fixed
#   denominator). This is the cleanest spec in the phase3 set because (a) it
#   absorbs sector-specific structural pricing-power differences, (b) the alt
#   denominator removes mechanical denominator endogeneity.
#
# INPUT:
#   data/processed/phase3_sector_exposure.RData
#   NBB_data/processed/deflator_nace4d_2005base.RData
#
# OUTPUT:
#   output/tables/phase3_ppi_heterogeneity.txt
#   output/figures/phase3_ppi_heterogeneity_by_tercile.pdf
#   output/figures/phase3_ppi_heterogeneity_by_nace2d.pdf
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)
library(tidyr)
library(ggplot2)
library(fixest)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load ----
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))

# ===========================================================================
# Helper: cumulative coefficient across a list of term names
# ===========================================================================
linear_combo <- function(model, terms) {
  cf <- coef(model); V <- vcov(model)
  present <- terms[terms %in% names(cf)]
  if (!length(present))
    return(list(estimate = NA, std.error = NA, statistic = NA, p.value = NA))
  L <- rep(1, length(present))
  est <- sum(cf[present])
  se  <- sqrt(as.numeric(t(L) %*% V[present, present, drop = FALSE] %*% L))
  z   <- est / se
  list(estimate = est, std.error = se, statistic = z,
       p.value  = 2 * pnorm(abs(z), lower.tail = FALSE))
}

# ===========================================================================
# Panel construction (same as phase3_ppi_passthrough)
# ===========================================================================
panel <- deflator %>%
  select(nace4d, nace2d, year, ppi) %>%
  filter(year >= 2005, year <= 2022) %>%
  left_join(
    sector_exposure %>%
      select(nace4d, year,
             exposure_direct_total, exposure_alt_total, n_ets_firms),
    by = c("nace4d", "year")
  ) %>%
  mutate(
    has_ets = !is.na(n_ets_firms),
    exposure_direct_total = coalesce(exposure_direct_total, 0),
    exposure_alt_total    = coalesce(exposure_alt_total,    0),
    log_ppi = log(ppi),
    t       = year - min(year)
  )

# ETS-ever sectors
ets_sectors <- panel %>%
  group_by(nace4d) %>%
  summarise(ever_ets = any(has_ets), .groups = "drop") %>%
  filter(ever_ets) %>% pull(nace4d)

# ===========================================================================
# Pre-period (2013-2016) shortage intensity per sector (Phase 1a convention)
# ===========================================================================
cat("Building pre-period (2013-2016) shortage intensity per sector...\n")

shortage_base <- sector_exposure %>%
  filter(year %in% 2013:2016) %>%
  group_by(nace4d) %>%
  summarise(
    pre_shortage_intensity = mean(exposure_alt_total, na.rm = TRUE),
    n_base_yr = n(),
    .groups = "drop"
  ) %>%
  filter(!is.na(pre_shortage_intensity))

# Classify
pos <- shortage_base %>% filter(pre_shortage_intensity > 0)
if (nrow(pos) >= 3) {
  qs <- quantile(pos$pre_shortage_intensity, probs = c(1/3, 2/3))
} else {
  qs <- c(0, 0)
}

sector_group <- shortage_base %>%
  mutate(group = case_when(
    pre_shortage_intensity == 0            ~ "T0_zero",
    pre_shortage_intensity <= qs[1]        ~ "T1_low",
    pre_shortage_intensity <= qs[2]        ~ "T2_mid",
    TRUE                                   ~ "T3_high"
  ))

cat("\nTercile thresholds (positive-only):\n")
cat(sprintf("  T1 <= %.4f, T2 <= %.4f, T3 > %.4f\n", qs[1], qs[2], qs[2]))
cat("\nSectors per group:\n")
print(table(sector_group$group))

# Attach to panel
panel <- panel %>%
  left_join(sector_group %>% select(nace4d, group), by = "nace4d") %>%
  mutate(
    group = ifelse(is.na(group), "T0_zero", group),
    group = factor(group, levels = c("T0_zero", "T1_low", "T2_mid", "T3_high"))
  )

# ===========================================================================
# Output file
# ===========================================================================
sink(file.path(OUTPUT_TAB, "phase3_ppi_heterogeneity.txt"))

cat("================================================================\n")
cat(" Phase 3, Task 2: Heterogeneity in PPI pass-through\n")
cat("================================================================\n\n")

cat(sprintf("Panel: %d rows, %d sectors, years %d-%d.\n",
            nrow(panel), n_distinct(panel$nace4d),
            min(panel$year), max(panel$year)))
cat(sprintf("Ever-ETS sectors: %d\n\n", length(ets_sectors)))

cat("Pre-period (2013-2016) shortage-intensity groups:\n")
print(table(sector_group$group))
cat(sprintf("\nTercile thresholds: T1 <= %.4f, T2 <= %.4f, T3 > %.4f\n\n",
            qs[1], qs[2], qs[2]))

# ===========================================================================
# 1. By-tercile pass-through with sector trends
# ===========================================================================
cat("================================================================\n")
cat(" (1) By-tercile pass-through, spec: S6-alt (sector trends + year FE)\n")
cat("     log(PPI) ~ exposure_alt × tercile  |  nace4d[t] + year\n")
cat("================================================================\n\n")

# Group-specific slopes (drop T0_zero level effect; it's the control group)
mH1 <- feols(
  log_ppi ~ i(group, exposure_alt_total, ref = "T0_zero")
          | nace4d[t] + year,
  data = panel %>% filter(!is.na(log_ppi)),
  cluster = ~nace4d
)
print(summary(mH1))
cat("\n")

# Same spec, first-differences with year FE
cat("----------------------------------------------------------------\n")
cat(" (1b) First-difference: Δ log(PPI) ~ Δ exposure_alt × tercile | year FE\n")
cat("----------------------------------------------------------------\n")

panel <- panel %>%
  arrange(nace4d, year) %>%
  group_by(nace4d) %>%
  mutate(
    d_log_ppi = log_ppi - lag(log_ppi),
    d_exp_alt = exposure_alt_total - lag(exposure_alt_total)
  ) %>%
  ungroup()

mH1b <- feols(
  d_log_ppi ~ i(group, d_exp_alt, ref = "T0_zero") | year,
  data = panel %>% filter(!is.na(d_log_ppi)),
  cluster = ~nace4d
)
print(summary(mH1b))
cat("\n")

# ===========================================================================
# 2. Side-by-side: single-slope by tercile (cleaner comparison)
#    Each tercile gets its own separate regression
# ===========================================================================
cat("================================================================\n")
cat(" (2) Separate S6 regression for each tercile\n")
cat("     Each tercile's coefficient on exposure_alt, with own sector trends\n")
cat("================================================================\n\n")

run_tercile <- function(grp_label, dat) {
  d <- dat %>% filter(group %in% c("T0_zero", grp_label), !is.na(log_ppi))
  if (n_distinct(d$nace4d) < 4) {
    cat(sprintf("  Too few sectors in %s, skipping\n", grp_label))
    return(NULL)
  }
  m <- feols(log_ppi ~ exposure_alt_total | nace4d[t] + year,
             data = d, cluster = ~nace4d)
  ct <- coeftable(m)
  if ("exposure_alt_total" %in% rownames(ct)) {
    r <- ct["exposure_alt_total", ]
    cat(sprintf("  %-10s : coef = %.4f (SE %.4f, t = %.2f, N = %d, sectors = %d)\n",
                grp_label, r[1], r[2], r[3], m$nobs, n_distinct(d$nace4d)))
  }
  invisible(m)
}

for (g in c("T1_low", "T2_mid", "T3_high")) run_tercile(g, panel)
cat("\n")

# ===========================================================================
# 3. NACE2d-specific pass-through (biggest ETS industries)
# ===========================================================================
cat("================================================================\n")
cat(" (3) NACE2d-specific pass-through\n")
cat("================================================================\n\n")

# Rank NACE2d by total ETS emissions in base period to pick the top few
nace2d_size <- sector_exposure %>%
  filter(year %in% 2013:2016) %>%
  group_by(nace2d) %>%
  summarise(total_em = sum(total_emissions, na.rm = TRUE),
            n_sectors = n_distinct(nace4d),
            .groups = "drop") %>%
  arrange(desc(total_em))

cat("Top ETS-emitting NACE2d sectors (2013-2016 avg):\n")
print(as.data.frame(nace2d_size))
cat("\n")

top_nace2d <- nace2d_size %>%
  filter(n_sectors >= 2) %>%
  head(10) %>%
  pull(nace2d)

cat("\nRunning S6-alt for each of the top NACE2d sectors with >= 2 4d sub-sectors:\n")
cat("  spec: log(PPI) ~ exp_alt | nace4d[t] + year, restricted to sector\n\n")

by_2d_results <- list()
for (n2 in top_nace2d) {
  d <- panel %>% filter(nace2d == n2, !is.na(log_ppi))
  if (n_distinct(d$nace4d) < 2) next

  m <- tryCatch(
    feols(log_ppi ~ exposure_alt_total | nace4d[t] + year,
          data = d, cluster = ~nace4d),
    error = function(e) NULL
  )
  if (is.null(m)) next

  ct <- coeftable(m)
  if ("exposure_alt_total" %in% rownames(ct)) {
    r <- ct["exposure_alt_total", ]
    by_2d_results[[n2]] <- data.frame(
      nace2d = n2,
      n_sectors = n_distinct(d$nace4d),
      n_obs = m$nobs,
      coef = r[1], se = r[2], t = r[3], p = r[4]
    )
  }
}

if (length(by_2d_results) > 0) {
  res_2d <- bind_rows(by_2d_results) %>% arrange(nace2d)
  rownames(res_2d) <- NULL
  cat("Results:\n")
  print(as.data.frame(res_2d))
  cat("\n")
} else {
  cat("No NACE2d-specific regressions could be estimated.\n\n")
}

# ===========================================================================
# 4. Visualization
# ===========================================================================
cat("Writing figures...\n")

# Panel 1: tercile-specific coefficients (from mH1)
grp_ct <- coeftable(mH1)
grp_rows <- grep("group::", rownames(grp_ct))
if (length(grp_rows) > 0) {
  plot_tercile <- data.frame(
    group = gsub("group::(T[0-9_a-z]+):exposure_alt_total", "\\1",
                  rownames(grp_ct)[grp_rows]),
    coef  = grp_ct[grp_rows, 1],
    se    = grp_ct[grp_rows, 2]
  ) %>%
    mutate(
      lo = coef - 1.96 * se, hi = coef + 1.96 * se,
      group = factor(group, levels = c("T1_low", "T2_mid", "T3_high"))
    )

  p_t <- ggplot(plot_tercile, aes(x = group, y = coef, ymin = lo, ymax = hi)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(color = "#1f77b4", size = 0.6) +
    labs(title = "Pass-through by pre-period shortage intensity tercile",
         subtitle = "S6-alt: log(PPI) ~ exp_alt × tercile | nace4d[t] + year FE",
         x = "Tercile of 2013-2016 shortage intensity",
         y = "Pass-through coefficient (1 = full)") +
    theme_bw(base_size = 10) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(OUTPUT_FIG, "phase3_ppi_heterogeneity_by_tercile.pdf"),
         p_t, width = 7, height = 4.5)
  cat("Tercile plot saved.\n")
}

# Panel 2: NACE2d coefficients
if (length(by_2d_results) > 0) {
  plot_2d <- res_2d %>%
    mutate(lo = coef - 1.96 * se, hi = coef + 1.96 * se,
           nace2d = factor(nace2d, levels = rev(sort(unique(nace2d)))))

  p_2 <- ggplot(plot_2d, aes(y = nace2d, x = coef, xmin = lo, xmax = hi)) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
    geom_pointrange(color = "#1f77b4", size = 0.5) +
    geom_text(aes(label = sprintf("n=%d, k=%d", n_obs, n_sectors)),
              hjust = -0.2, size = 3, color = "grey40", nudge_x = 0) +
    labs(title = "Pass-through by NACE2d sector",
         subtitle = "S6-alt separately per NACE2d; only sectors with >= 2 4d sub-sectors",
         x = "Pass-through coefficient on exposure_alt",
         y = "NACE2d sector") +
    theme_bw(base_size = 10) +
    theme(plot.title = element_text(face = "bold"))

  ggsave(file.path(OUTPUT_FIG, "phase3_ppi_heterogeneity_by_nace2d.pdf"),
         p_2, width = 8, height = 5)
  cat("NACE2d plot saved.\n")
}

sink()
cat("\nOutput written to:", file.path(OUTPUT_TAB, "phase3_ppi_heterogeneity.txt"), "\n")
cat("Done.\n")
