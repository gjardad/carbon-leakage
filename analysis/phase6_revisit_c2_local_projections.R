###############################################################################
# phase6_revisit_c2_local_projections.R
#
# PURPOSE:
#   Component 2 of the China-shock revisit. Estimate the China-origin
#   Armington elasticity at multiple horizons h to recover the
#   short-run-vs-long-run shape (BLP 2022 Figure 2 analog; Peter & Ruane
#   Figure 4 analog).
#
#   For each horizon h in {3, 5, 7, 10, 15, 20}, run the same 2SLS as in
#   Component 1 with the long-difference taken from BASE_YEAR (2002) to
#   BASE_YEAR + h:
#
#     dlog_h (ChinaShare_{i,k} / NonChinaShare_{i,k})
#       = alpha_h + (1 - sigma^h) * dlog_h (P^China_k / P^non-China_k)
#         + FE_{NACE2d_i} + e
#
#   instrumented with delta_h ChinaShare_k_EU26 (BACI shifter cumulated over
#   the same window).
#
#   Output: a table of {h, beta^h, sigma^h, SE, F-stat, N} and an impulse-
#   response figure showing sigma^h vs h with 95% CIs.
#
# INPUT:
#   data/processed/phase6_revisit_importer_hs6_panel.RData
#     Built by Component 1; contains the 2002 -> 2012 panel only.
#   data/processed/phase6_china_shifter_2002_2012.RData (HS6 IV)
#   data/processed/phase6_belgian_unit_values.RData     (HS6 prices by year)
#   ${PROC_DATA}/customs_selected_sample_china.RData    (importer x HS6 x year x source)
#   ${PROC_DATA}/annual_accounts_selected_sample_key_variables.RData
#
# OUTPUT:
#   data/processed/phase6_revisit_c2_results.RData
#   output/tables/phase6_revisit_c2_summary.csv
#   output/tables/phase6_revisit_c2_summary.txt
#   output/figures/phase6_revisit_c2_impulse_response.pdf
#
# CAVEATS:
#   - Same caveats as Component 1 (importer != Belgian-firm population;
#     intensive-margin only; trim 1% tails per horizon).
#   - The IV at horizon h is delta_h ChinaShare = ChinaShare_{2002+h} -
#     ChinaShare_{2002}. We don't currently have a multi-horizon BACI
#     shifter cached (E1 only built 2002 -> 2012). This script reconstructs
#     it from the BACI raw files via the same loop pattern as E1/E2.
#     For local-1 prototyping we cap h at min(20, max BACI year - 2002).
#   - First-stage F is reported per horizon. Expect F to fall as h grows
#     (longer windows accumulate more measurement error).
#   - Local projections use OVERLAPPING long differences when run on a
#     single base year. We rely on the cluster (HS6) SE for serial
#     correlation; the BLP paper does the same.
###############################################################################

rm(list = ls())

library(data.table)
library(fixest)
library(ggplot2)
library(scales)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

BACI_DIR <- file.path(RAW_DATA, "BACI_HS02_V202601")
stopifnot(dir.exists(BACI_DIR))

# ---- Tunables ----
BASE_YEAR <- 2002L
HORIZONS  <- c(1L, 3L, 5L, 7L, 10L, 15L, 20L)
CHINA_ISO <- c("CN", "HK")
TRIM_PCT  <- 0.01

# ---- 1. Load shifter / EU country lookups (from E1) ----
load(file.path(OUT_DATA, "phase6_china_shifter_2002_2012.RData"))
# eu26_numeric, china_numeric, eu26_iso3 in scope.
load(file.path(OUT_DATA, "phase6_belgian_unit_values.RData"))
# uv_panel: HS6 x year x {uv_china, uv_nonchina}; covers 2002, 2007, 2012, 2017, 2022.

uv_panel    <- as.data.table(uv_panel)
years_uv    <- sort(unique(uv_panel$year))
years_avail <- intersect(BASE_YEAR + HORIZONS, years_uv)
HORIZONS    <- intersect(HORIZONS, years_uv - BASE_YEAR)
cat("Horizons available given E2 uv_panel coverage:",
    paste(HORIZONS, collapse = ", "), "\n")

# ---- 2. BACI shifter at multiple horizons (reuse E1 logic) ----
build_baci_shifter_year <- function(year) {
  f <- file.path(BACI_DIR, sprintf("BACI_HS02_Y%d_V202601.csv", year))
  if (!file.exists(f)) {
    warning(sprintf("BACI file missing for %d: %s", year, f))
    return(NULL)
  }
  dt <- fread(f, colClasses = c(t = "integer", i = "integer", j = "integer",
                                k = "character", v = "numeric"))
  dt <- dt[j %in% eu26_numeric]
  dt[, k := formatC(as.integer(k), width = 6, flag = "0")]
  v_total <- dt[, .(value_total = sum(v, na.rm = TRUE)), by = k]
  v_china <- dt[i %in% china_numeric,
                .(value_china = sum(v, na.rm = TRUE)), by = k]
  s <- merge(v_total, v_china, by = "k", all.x = TRUE)
  s[is.na(value_china), value_china := 0]
  s <- s[value_total > 0]
  s[, china_share := value_china / value_total]
  s[, year := year]
  s
}

needed_baci_years <- c(BASE_YEAR, BASE_YEAR + HORIZONS)
shifter_by_year <- rbindlist(
  lapply(needed_baci_years, build_baci_shifter_year),
  fill = TRUE
)

# Build delta_h ChinaShare per (HS6 x horizon)
build_iv_horizon <- function(h) {
  base <- shifter_by_year[year == BASE_YEAR,
                           .(k, china_share_base = china_share,
                             value_total_base = value_total)]
  endd <- shifter_by_year[year == BASE_YEAR + h,
                           .(k, china_share_end = china_share)]
  out <- merge(base, endd, by = "k")
  out[, delta_china_share := china_share_end - china_share_base]
  out[, h := h]
  out[, .(hs6 = k, h, delta_china_share, value_total_base)]
}
iv_panel <- rbindlist(lapply(HORIZONS, build_iv_horizon))

# ---- 3. HS6 price changes per horizon ----
build_price_horizon <- function(h) {
  base <- uv_panel[year == BASE_YEAR,
                   .(k, uv_china_b = uv_china, uv_nonchina_b = uv_nonchina)]
  endd <- uv_panel[year == BASE_YEAR + h,
                   .(k, uv_china_e = uv_china, uv_nonchina_e = uv_nonchina)]
  pp <- merge(base, endd, by = "k")
  pp[uv_china_b > 0 & uv_china_e > 0,
     dlog_p_china := log(uv_china_e) - log(uv_china_b)]
  pp[uv_nonchina_b > 0 & uv_nonchina_e > 0,
     dlog_p_nonchina := log(uv_nonchina_e) - log(uv_nonchina_b)]
  pp[, dlog_p_ratio := dlog_p_china - dlog_p_nonchina]
  pp[, h := h]
  pp[, .(hs6 = k, h, dlog_p_china, dlog_p_nonchina, dlog_p_ratio)]
}
price_panel <- rbindlist(lapply(HORIZONS, build_price_horizon))

# Trim 1% tails of dlog_p_ratio within horizon
for (col in c("dlog_p_china", "dlog_p_nonchina", "dlog_p_ratio")) {
  for (h in HORIZONS) {
    x <- price_panel[h == h, get(col)]
    if (sum(!is.na(x)) > 50) {
      lo <- quantile(x, TRIM_PCT,     na.rm = TRUE)
      hi <- quantile(x, 1 - TRIM_PCT, na.rm = TRUE)
      price_panel[h == h & !is.na(get(col)) & (get(col) < lo | get(col) > hi),
                  (col) := NA]
    }
  }
}

# ---- 4. Customs panel at importer x hs6 x year, for years needed ----
load(file.path(PROC_DATA, "customs_selected_sample_china.RData"))
cust <- as.data.table(df_customs_selected_sample_china)
rm(df_customs_selected_sample_china)
needed_cust_years <- c(BASE_YEAR, BASE_YEAR + HORIZONS)
cust <- cust[year %in% needed_cust_years]

cust_w <- dcast(cust, vat + hs6 + year ~ source,
                value.var = "value", fill = 0)
setnames(cust_w, c("china", "nonchina"), c("v_china", "v_nonchina"))

# Restrict to selected-sample importers
load(file.path(PROC_DATA, "annual_accounts_selected_sample_key_variables.RData"))
aa <- as.data.table(df_annual_accounts_selected_sample_key_variables)
rm(df_annual_accounts_selected_sample_key_variables)
aa <- aa[year == BASE_YEAR,
         .(vat, nace2d = substr(sprintf("%05d", as.integer(nace5d)), 1, 2))]
aa <- unique(aa[!is.na(nace2d)])

cust_w <- merge(cust_w, aa, by = "vat", all.x = FALSE)
cat("Customs panel rows after sample restriction:", nrow(cust_w), "\n")

# ---- 5. Build per-horizon long-difference panel and run 2SLS ----
trim_tails <- function(dt, col) {
  x <- dt[[col]]
  if (sum(!is.na(x)) > 50) {
    lo <- quantile(x, TRIM_PCT,     na.rm = TRUE)
    hi <- quantile(x, 1 - TRIM_PCT, na.rm = TRUE)
    dt[!is.na(get(col)) & (get(col) < lo | get(col) > hi), (col) := NA]
  }
  dt
}

run_horizon <- function(h) {
  base <- cust_w[year == BASE_YEAR,
                  .(vat, hs6, nace2d,
                    v_china_b = v_china, v_nonchina_b = v_nonchina)]
  endd <- cust_w[year == BASE_YEAR + h,
                  .(vat, hs6,
                    v_china_e = v_china, v_nonchina_e = v_nonchina)]
  ph <- merge(base, endd, by = c("vat", "hs6"))
  ph <- ph[v_china_b > 0 & v_china_e > 0 &
           v_nonchina_b > 0 & v_nonchina_e > 0]
  ph[, dlog_share_ratio :=
       (log(v_china_e) - log(v_nonchina_e)) -
       (log(v_china_b) - log(v_nonchina_b))]
  ph <- trim_tails(ph, "dlog_share_ratio")
  ph[, h := h]

  iv_h    <- iv_panel[h == h, .(hs6, delta_china_share, value_total_base)]
  price_h <- price_panel[h == h, .(hs6, dlog_p_china, dlog_p_nonchina, dlog_p_ratio)]

  ph <- merge(ph, iv_h, by = "hs6", all.x = FALSE)
  ph <- merge(ph, price_h, by = "hs6", all.x = TRUE)

  ph_reg <- ph[!is.na(dlog_share_ratio) & !is.na(delta_china_share) &
                !is.na(dlog_p_ratio) & !is.na(nace2d)]

  if (nrow(ph_reg) < 100) {
    return(list(
      horizon = h,
      panel   = ph_reg,
      result  = data.table(h = h, n = nrow(ph_reg), beta = NA_real_,
                           se = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
                           sigma = NA_real_, sigma_lo = NA_real_,
                           sigma_hi = NA_real_, f_stat = NA_real_)
    ))
  }

  m_iv <- feols(
    dlog_share_ratio ~ 1 | nace2d | dlog_p_ratio ~ delta_china_share,
    data    = ph_reg,
    cluster = ~ hs6
  )
  ce <- coeftable(m_iv)
  rn <- grep("^fit_", rownames(ce), value = TRUE)[1]
  est <- ce[rn, "Estimate"]
  se  <- ce[rn, "Std. Error"]
  ci  <- est + c(-1, 1) * 1.96 * se
  fs_F <- tryCatch(unname(fitstat(m_iv, "ivf1", simplify = TRUE)),
                    error = function(e) NA_real_)

  list(
    horizon = h,
    panel   = ph_reg,
    result  = data.table(
      h        = h,
      n        = nobs(m_iv),
      beta     = est,
      se       = se,
      ci_lo    = ci[1],
      ci_hi    = ci[2],
      sigma    = 1 - est,
      sigma_lo = 1 - ci[2],
      sigma_hi = 1 - ci[1],
      f_stat   = fs_F
    )
  )
}

cat("Running local projections at h =",
    paste(HORIZONS, collapse = ", "), "...\n")
horizon_runs <- lapply(HORIZONS, run_horizon)
results_dt   <- rbindlist(lapply(horizon_runs, `[[`, "result"))

print(results_dt, digits = 4)
fwrite(results_dt, file.path(OUTPUT_TAB, "phase6_revisit_c2_summary.csv"))
cat("Saved:", file.path(OUTPUT_TAB, "phase6_revisit_c2_summary.csv"), "\n")

save(results_dt, horizon_runs, iv_panel, price_panel,
     file = file.path(OUT_DATA, "phase6_revisit_c2_results.RData"))
cat("Saved:", file.path(OUT_DATA, "phase6_revisit_c2_results.RData"), "\n")

# ---- 6. Impulse-response figure ----
p_ir <- ggplot(results_dt[!is.na(beta)], aes(x = h, y = sigma)) +
  geom_hline(yintercept = 1, linetype = "dashed", colour = "grey40") +
  geom_ribbon(aes(ymin = sigma_lo, ymax = sigma_hi),
              alpha = 0.2, fill = "steelblue") +
  geom_line(colour = "steelblue", linewidth = 0.8) +
  geom_point(size = 3, colour = "steelblue") +
  scale_x_continuous(breaks = HORIZONS) +
  labs(
    title    = "Component 2 -- Impulse response of sigma to horizon",
    subtitle = "sigma^h = 1 - beta^h, where beta^h is the long-difference 2SLS slope on dlog(P_China/P_nonChina). 95% CI shown.",
    x        = "Horizon h (years from 2002)",
    y        = "Implied sigma (Armington origin substitution)",
    caption  = "Source: BACI HS02 V202601 + Belgian customs + selected-sample annual accounts. Component 2, ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md."
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title.position = "plot",
        plot.subtitle = element_text(colour = "grey30", size = 9))

ggsave(file.path(OUTPUT_FIG, "phase6_revisit_c2_impulse_response.pdf"),
       p_ir, width = 8, height = 5)
cat("Saved:", file.path(OUTPUT_FIG, "phase6_revisit_c2_impulse_response.pdf"), "\n")

# ---- 7. Readable summary ----
sink(file.path(OUTPUT_TAB, "phase6_revisit_c2_summary.txt"))

cat("================================================================\n")
cat("Component 2 -- China-origin Armington sigma at multiple horizons\n")
cat("Generated by analysis/phase6_revisit_c2_local_projections.R\n")
cat("================================================================\n\n")

cat("Specification (per horizon h):\n")
cat("  dlog_h(ChinaShare/NonChinaShare) = alpha + (1 - sigma^h) * dlog_h(P_China/P_nonChina)\n")
cat("                                   + FE_NACE2d + e\n")
cat("  IV: delta_h ChinaShare_k_EU26.\n")
cat("  Cluster SE on HS6.\n\n")

cat("Results:\n")
print(results_dt, digits = 4)
cat("\n")

cat("BLP (2022) benchmark:\n")
cat("  epsilon^1  = -0.76,  sigma^1  = 1.76\n")
cat("  epsilon^7  = -2.06,  sigma^7  = 3.06\n")
cat("  epsilon^10 = -2.12,  sigma^10 = 3.12\n")
cat("  Convergence in 7-10 years.\n\n")

if (nrow(results_dt[!is.na(sigma)]) >= 2) {
  shortest <- results_dt[!is.na(sigma)][which.min(h)]
  longest  <- results_dt[!is.na(sigma)][which.max(h)]
  cat(sprintf("Our shape: sigma^%d = %.2f vs sigma^%d = %.2f.\n",
              shortest$h, shortest$sigma, longest$h, longest$sigma))
  if (longest$sigma > shortest$sigma + 0.5) {
    cat("  PASS: long-run sigma materially exceeds short-run.\n")
    cat("        Consistent with BLP / Peter-Ruane.\n")
  } else if (longest$sigma > shortest$sigma) {
    cat("  WEAK: sigma rises with h but the gap is small.\n")
  } else {
    cat("  FAIL or NULL: no LR > SR pattern. Either elasticity is flat\n")
    cat("                across horizons or identification is too noisy at LR.\n")
  }
}

cat("================================================================\n")
sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase6_revisit_c2_summary.txt"), "\n")

cat("\nDone.\n")
