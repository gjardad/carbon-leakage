###############################################################################
# phase6_eyeball_e2_first_stage.R
#
# PURPOSE:
#   Eyeball E2 from ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md (China shock section).
#
#   Belgian first stage: does the BACI ΔChinaShare shifter actually predict
#   changes in Belgian HS6 unit values? Direct analog of P&R Figure 2
#   (non-parametric first stage, tariff-change vs price-change scatter).
#
#   First-stage regression (one observation per HS6 product k):
#     Δlog(UV_Belgium,k,source) = α + ψ × ΔChinaShare_k + ε
#
#   where source ∈ {China-only, non-China}. The non-China version is the
#   pro-competitive analog of P&R Table 1: even Belgian buyers who never
#   source from China face price changes because non-Chinese suppliers cut
#   prices to compete. This is the load-bearing version for downstream
#   substitution work — the leakage paper is about Belgian-to-Belgian B2B,
#   not direct Chinese imports. The China-only version is a sanity check
#   on the mechanical channel.
#
#   Horizons: 2002 -> {2007, 2012, 2017, 2022}. P&R's central point is
#   that elasticities are horizon-dependent; we want to see whether the
#   first-stage slope ψ steepens with horizon.
#
# INPUT:
#   data/processed/phase6_china_shifter_2002_2012.RData (eu26_numeric, china_numeric)
#   $RAW_DATA/BACI_HS02_V202601/BACI_HS02_Y{2002,2007,2012,2017,2022}_V202601.csv
#
# OUTPUT:
#   data/processed/phase6_belgian_unit_values.RData    (shifter_panel + uv_panel)
#   data/processed/phase6_e2_first_stage_results.RData (results_dt + horizon_data)
#   output/figures/phase6_eyeball_e2_first_stage.pdf   (headline 2002->2012 scatter)
#   output/figures/phase6_eyeball_e2_horizons.pdf      (slope-by-horizon CIs)
#   output/tables/phase6_eyeball_e2_summary.csv
#   output/tables/phase6_eyeball_e2_summary.txt
#
# CAVEATS:
#   - Belgium ISO numeric: 56. BLEU (Belgium-Luxembourg) was separated in
#     1999, before our 2002 baseline; no historical aggregate to worry about.
#   - HS6 codes require positive value AND quantity in both endpoints to
#     compute Δlog(unit value). Codes missing q in either endpoint are
#     dropped from that source's regression and counted in the summary.
#   - 1% tails on Δlog(UV) trimmed within each horizon × source (P&R
#     measurement convention).
#   - Importance weights = HS6 × 2002 EU-26 import value (same as E1).
#   - Non-China unit value = sum(v_i,k) / sum(q_i,k) over all i ≠ China and
#     i ≠ Belgium (avoid the BACI mirror-flow self-import edge case).
###############################################################################

rm(list = ls())

library(data.table)
library(ggplot2)
library(scales)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

BACI_DIR <- file.path(RAW_DATA, "BACI_HS02_V202601")
stopifnot(dir.exists(BACI_DIR))

# ---- Load E1 lookups (eu26_numeric, china_numeric, eu26_iso3) ----
load(file.path(OUT_DATA, "phase6_china_shifter_2002_2012.RData"))

# Belgium ISO numeric. As with EU-26, BACI's dictionary maps BEL to two
# historical codes (56 modern Belgium, 58 Belgium-Luxembourg pre-1998).
# Code 58 has no flows in our 2002+ window; including both is harmless.
country_codes <- fread(file.path(BACI_DIR, "country_codes_V202601.csv"))
belgium_numeric <- country_codes[country_iso3 == "BEL", country_code]
stopifnot(length(belgium_numeric) >= 1)
cat(sprintf("Belgium numeric codes (incl. historical): %s\n",
            paste(sort(belgium_numeric), collapse = ", ")))

# ---- Years to load ----
# Added {2003, 2005, 2009} on 2026-04-30 so Component 2 of the China-shock
# revisit can report sigma at h in {1, 3, 5, 7, 10, 15, 20}, directly
# comparable to BLP (2022) Figure 2 horizons.
years    <- c(2002, 2003, 2005, 2007, 2009, 2012, 2017, 2022)
horizons <- c(2003, 2005, 2007, 2009, 2012, 2017, 2022)  # all paired against 2002

# ---- Loader: read one BACI year, keep only EU-26 ∪ Belgium importers ----
load_baci_year <- function(year) {
  f <- file.path(BACI_DIR, sprintf("BACI_HS02_Y%d_V202601.csv", year))
  cat(sprintf("Reading %s ...\n", basename(f)))
  dt <- fread(f, colClasses = c(t = "integer", i = "integer", j = "integer",
                                k = "character", v = "numeric", q = "character"))
  keep_importers <- unique(c(eu26_numeric, belgium_numeric))
  dt <- dt[j %in% keep_importers]
  dt[, k := formatC(as.integer(k), width = 6, flag = "0")]
  dt[, q := suppressWarnings(as.numeric(q))]
  dt
}

# ---- Per-year aggregates (shifter inputs + Belgian UV by source) ----
shifter_list <- vector("list", length(years))
uv_list      <- vector("list", length(years))

for (idx in seq_along(years)) {
  yr      <- years[idx]
  dt_yr   <- load_baci_year(yr)

  # (a) Shifter inputs: EU-26 importers only
  dt_eu26      <- dt_yr[j %in% eu26_numeric]
  v_total_eu26 <- dt_eu26[, .(value_total = sum(v, na.rm = TRUE)), by = k]
  v_china_eu26 <- dt_eu26[i %in% china_numeric,
                          .(value_china = sum(v, na.rm = TRUE)), by = k]
  shifter_yr   <- merge(v_total_eu26, v_china_eu26, by = "k", all.x = TRUE)
  shifter_yr[is.na(value_china), value_china := 0]
  shifter_yr   <- shifter_yr[value_total > 0]
  shifter_yr[, china_share := value_china / value_total]
  shifter_yr[, year := yr]
  shifter_list[[idx]] <- shifter_yr

  # (b) Belgian UV by source. Drop rows with NA or zero quantity (UV undefined).
  dt_be <- dt_yr[j %in% belgium_numeric & !is.na(q) & q > 0]

  uv_china <- dt_be[i %in% china_numeric,
                    .(v_china_be = sum(v, na.rm = TRUE),
                      q_china_be = sum(q, na.rm = TRUE)),
                    by = k]
  uv_china[, uv_china := v_china_be / q_china_be]

  uv_nonchina <- dt_be[!(i %in% china_numeric) & !(i %in% belgium_numeric),
                       .(v_nonchina_be = sum(v, na.rm = TRUE),
                         q_nonchina_be = sum(q, na.rm = TRUE)),
                       by = k]
  uv_nonchina[, uv_nonchina := v_nonchina_be / q_nonchina_be]

  uv_be <- merge(uv_china[,    .(k, uv_china,    v_china_be)],
                 uv_nonchina[, .(k, uv_nonchina, v_nonchina_be)],
                 by = "k", all = TRUE)
  uv_be[, year := yr]
  uv_list[[idx]] <- uv_be

  rm(dt_yr, dt_eu26, dt_be); gc(verbose = FALSE)
}

shifter_panel <- rbindlist(shifter_list)
uv_panel      <- rbindlist(uv_list)

cat(sprintf("Shifter panel rows: %d (HS6 × year, %d years)\n",
            nrow(shifter_panel), length(years)))
cat(sprintf("UV panel rows     : %d\n", nrow(uv_panel)))

save(shifter_panel, uv_panel, belgium_numeric, eu26_numeric, china_numeric,
     file = file.path(OUT_DATA, "phase6_belgian_unit_values.RData"))
cat("Saved:", file.path(OUT_DATA, "phase6_belgian_unit_values.RData"), "\n")

# ---- Build first-stage data per horizon (2002 -> end_year) ----
build_horizon <- function(end_year) {
  base <- shifter_panel[year == 2002,
                        .(k,
                          china_share_base = china_share,
                          value_total_base = value_total)]
  end  <- shifter_panel[year == end_year,
                        .(k, china_share_end = china_share)]
  shifter_h <- merge(base, end, by = "k")
  shifter_h[, delta_china_share := china_share_end - china_share_base]
  shifter_h[, importance_weight := value_total_base / sum(value_total_base)]

  uv_base <- uv_panel[year == 2002,
                      .(k,
                        uv_china_base    = uv_china,
                        uv_nonchina_base = uv_nonchina)]
  uv_end  <- uv_panel[year == end_year,
                      .(k,
                        uv_china_end    = uv_china,
                        uv_nonchina_end = uv_nonchina)]
  uv_h <- merge(uv_base, uv_end, by = "k")
  uv_h[uv_china_base > 0 & uv_china_end > 0,
       dlog_uv_china := log(uv_china_end) - log(uv_china_base)]
  uv_h[uv_nonchina_base > 0 & uv_nonchina_end > 0,
       dlog_uv_nonchina := log(uv_nonchina_end) - log(uv_nonchina_base)]

  out <- merge(shifter_h, uv_h, by = "k", all.x = TRUE)
  out[, horizon_end := end_year]
  out
}

horizon_data <- rbindlist(lapply(horizons, build_horizon), fill = TRUE)

# ---- Trim 1% tails of Δlog(UV) within each horizon × source ----
trim_tails <- function(dt, col) {
  for (h in horizons) {
    x <- dt[horizon_end == h, get(col)]
    if (sum(!is.na(x)) > 50) {
      lo <- quantile(x, 0.01, na.rm = TRUE)
      hi <- quantile(x, 0.99, na.rm = TRUE)
      dt[horizon_end == h & !is.na(get(col)) & (get(col) < lo | get(col) > hi),
         (col) := NA]
    }
  }
  dt
}
horizon_data <- trim_tails(horizon_data, "dlog_uv_china")
horizon_data <- trim_tails(horizon_data, "dlog_uv_nonchina")

# ---- WLS first-stage per horizon × source ----
run_first_stage <- function(dt, outcome_col, label, end_yr) {
  d <- dt[!is.na(get(outcome_col)) & !is.na(delta_china_share) &
          !is.na(importance_weight) & importance_weight > 0]
  if (nrow(d) < 50) {
    return(data.table(spec = label, end_year = end_yr, n = nrow(d),
                       psi = NA_real_, se = NA_real_, t_stat = NA_real_,
                       p_value = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_,
                       f_stat = NA_real_, r2 = NA_real_))
  }
  fit <- lm(as.formula(sprintf("%s ~ delta_china_share", outcome_col)),
            data = d, weights = d$importance_weight)
  s   <- summary(fit)
  ci  <- confint(fit, "delta_china_share", level = 0.95)

  data.table(
    spec     = label,
    end_year = end_yr,
    n        = nrow(d),
    psi      = unname(coef(fit)["delta_china_share"]),
    se       = unname(s$coefficients["delta_china_share", "Std. Error"]),
    t_stat   = unname(s$coefficients["delta_china_share", "t value"]),
    p_value  = unname(s$coefficients["delta_china_share", "Pr(>|t|)"]),
    ci_lo    = ci[1],
    ci_hi    = ci[2],
    f_stat   = unname(s$fstatistic["value"]),
    r2       = unname(s$r.squared)
  )
}

results <- list()
for (h in horizons) {
  d_h <- horizon_data[horizon_end == h]
  results[[paste0("ch_",  h)]] <- run_first_stage(d_h, "dlog_uv_china",
                                                  sprintf("China-only %d-yr", h - 2002), h)
  results[[paste0("nch_", h)]] <- run_first_stage(d_h, "dlog_uv_nonchina",
                                                  sprintf("Non-China %d-yr", h - 2002), h)
}
results_dt <- rbindlist(results)
results_dt[, source := ifelse(grepl("Non-China", spec), "Non-China", "China-only")]
results_dt[, horizon_yrs := end_year - 2002]

print(results_dt[, .(spec, n, psi, se, t_stat, p_value, ci_lo, ci_hi,
                      f_stat, r2)], digits = 4)

fwrite(results_dt, file.path(OUTPUT_TAB, "phase6_eyeball_e2_summary.csv"))
cat("Saved:", file.path(OUTPUT_TAB, "phase6_eyeball_e2_summary.csv"), "\n")

# ---- Headline figure: 2002→2012 bin-scatter with WLS fits ----
plot_dt <- horizon_data[horizon_end == 2012]

make_binscatter <- function(dt, ycol, label) {
  d <- dt[!is.na(get(ycol)) & !is.na(delta_china_share) & importance_weight > 0]
  if (nrow(d) < 50) return(data.table())
  qbreaks <- unique(quantile(d$delta_china_share,
                              probs = seq(0, 1, length.out = 51), na.rm = TRUE))
  d[, bin := cut(delta_china_share, breaks = qbreaks, include.lowest = TRUE)]
  out <- d[, .(x = weighted.mean(delta_china_share, importance_weight),
                y = weighted.mean(get(ycol),         importance_weight),
                weight_sum = sum(importance_weight)),
            by = bin][!is.na(x) & !is.na(y)]
  out[, source := label]
  out
}

bs <- rbindlist(list(
  make_binscatter(plot_dt, "dlog_uv_china",    "China-only"),
  make_binscatter(plot_dt, "dlog_uv_nonchina", "Non-China")
))

ch_10  <- results_dt[spec == "China-only 10-yr"]
nch_10 <- results_dt[spec == "Non-China 10-yr"]

p_first_stage <- ggplot() +
  geom_point(data = bs, aes(x = x, y = y, colour = source, size = weight_sum),
             alpha = 0.75) +
  geom_smooth(data = plot_dt[!is.na(dlog_uv_china)],
              aes(x = delta_china_share, y = dlog_uv_china,
                  weight = importance_weight, colour = "China-only"),
              method = "lm", se = TRUE, linewidth = 0.8) +
  geom_smooth(data = plot_dt[!is.na(dlog_uv_nonchina)],
              aes(x = delta_china_share, y = dlog_uv_nonchina,
                  weight = importance_weight, colour = "Non-China"),
              method = "lm", se = TRUE, linewidth = 0.8) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey40") +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40") +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_colour_manual(values = c("China-only" = "tomato",
                                  "Non-China"  = "steelblue")) +
  scale_size_continuous(guide = "none", range = c(1, 6)) +
  labs(
    title    = "Belgian first stage: Delta-ChinaShare -> Belgian HS6 unit value, 2002 -> 2012",
    subtitle = sprintf(
      paste0("Bin-scatter (50 quantile bins of Delta-ChinaShare). WLS slopes: ",
             "China-only psi = %.3f (F = %.1f, N = %s); Non-China psi = %.3f (F = %.1f, N = %s). ",
             "Weights = 2002 EU-26 import value. 1%% tails of dlog(UV) trimmed."),
      ch_10$psi, ch_10$f_stat, format(ch_10$n, big.mark = ","),
      nch_10$psi, nch_10$f_stat, format(nch_10$n, big.mark = ",")),
    x        = "Delta-ChinaShare 2002 -> 2012 (China share of EU-26 imports, excl. BE)",
    y        = "Delta log(unit value) of Belgian imports, 2002 -> 2012",
    colour   = "Source of Belgian imports",
    caption  = "Source: BACI HS02 V202601. Eyeball E2, ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md."
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title.position = "plot",
        plot.subtitle = element_text(colour = "grey30", size = 9))

ggsave(file.path(OUTPUT_FIG, "phase6_eyeball_e2_first_stage.pdf"),
       p_first_stage, width = 10, height = 7)
cat("Saved:", file.path(OUTPUT_FIG, "phase6_eyeball_e2_first_stage.pdf"), "\n")

# ---- Horizon-comparison plot ----
p_horizons <- ggplot(results_dt, aes(x = horizon_yrs, y = psi, colour = source)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey40") +
  geom_errorbar(aes(ymin = ci_lo, ymax = ci_hi),
                width = 0.4, position = position_dodge(width = 0.5)) +
  geom_point(size = 3, position = position_dodge(width = 0.5)) +
  geom_line(position = position_dodge(width = 0.5)) +
  scale_x_continuous(breaks = c(5, 10, 15, 20)) +
  scale_colour_manual(values = c("China-only" = "tomato",
                                  "Non-China"  = "steelblue")) +
  labs(
    title    = "First-stage slope psi by horizon",
    subtitle = "psi = WLS coefficient on Delta-ChinaShare in Delta-log(UV_Belgium) regression. 95% CI shown.",
    x        = "Horizon (years after 2002)",
    y        = "Slope psi",
    colour   = "Source of Belgian imports"
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        plot.title.position = "plot")

ggsave(file.path(OUTPUT_FIG, "phase6_eyeball_e2_horizons.pdf"),
       p_horizons, width = 8, height = 5)
cat("Saved:", file.path(OUTPUT_FIG, "phase6_eyeball_e2_horizons.pdf"), "\n")

# ---- Save results ----
save(results_dt, horizon_data,
     file = file.path(OUT_DATA, "phase6_e2_first_stage_results.RData"))
cat("Saved:", file.path(OUT_DATA, "phase6_e2_first_stage_results.RData"), "\n")

# ---- Readable summary ----
sink(file.path(OUTPUT_TAB, "phase6_eyeball_e2_summary.txt"))

cat("================================================================\n")
cat("Eyeball E2 -- Belgian first stage (BACI shifter -> Belgian HS6 UV)\n")
cat("Generated by analysis/phase6_eyeball_e2_first_stage.R\n")
cat("================================================================\n\n")

cat("Definitions:\n")
cat("  ChinaShare_k,t       = v_China,EU26-excl-BE,k,t / v_total,EU26-excl-BE,k,t\n")
cat("  Delta-ChinaShare_k   = ChinaShare_k,end - ChinaShare_k,2002\n\n")
cat("  UV_Belgium,k,t,China    = v_China->BE,k,t  / q_China->BE,k,t\n")
cat("  UV_Belgium,k,t,nonChina = v_nonChina->BE,k,t / q_nonChina->BE,k,t\n")
cat("    (excludes self-imports; non-China sums all i != China and i != BE)\n\n")
cat("First-stage regression (one obs per HS6 product):\n")
cat("  Delta-log(UV_Belgium,k,source) = alpha + psi * Delta-ChinaShare_k + e\n")
cat("  WLS, weights = HS6 2002 EU-26 import value.\n")
cat("  1% tails of Delta-log(UV) trimmed within each horizon x source.\n\n")

cat(sprintf("Horizons: 2002 -> {%s}\n\n", paste(horizons, collapse = ", ")))

cat("Results:\n")
print(results_dt[, .(spec, n, psi, se, t_stat, p_value, ci_lo, ci_hi,
                      f_stat, r2)], digits = 4)
cat("\n")

cat("================================================================\n")
cat("Verdict (using non-China 10-yr horizon -- the load-bearing version)\n")

cat(sprintf("  Non-China  10yr: psi = %.4f, F = %.1f, p = %.4g, N = %d\n",
            nch_10$psi, nch_10$f_stat, nch_10$p_value, nch_10$n))
cat(sprintf("  China-only 10yr: psi = %.4f, F = %.1f, p = %.4g, N = %d\n",
            ch_10$psi, ch_10$f_stat, ch_10$p_value, ch_10$n))
cat("\n")
cat("  P&R 7-yr first stage: psi = -0.16 per pp tariff cut, F = 18.\n")
cat("  Note: P&R's psi is in (Δlog price) per pp tariff change, ours is\n")
cat("        in (Δlog price) per unit change in fractional ChinaShare.\n")
cat("        Multiply our psi by 0.01 to convert to 'per pp' scaling.\n\n")

if (!is.na(nch_10$f_stat) && nch_10$f_stat >= 10 && nch_10$psi < 0) {
  cat("  PASS: non-China first stage F >= 10 and slope is negative.\n")
  cat("        Project moves on to E3.\n")
} else if (!is.na(nch_10$f_stat) && nch_10$f_stat >= 5 && nch_10$psi < 0) {
  cat("  BORDERLINE: F in [5,10] and slope negative. Identification noisy\n")
  cat("              but viable. Proceed to E3 with explicit caveats on F.\n")
} else if (!is.na(nch_10$psi) && nch_10$psi < 0) {
  cat("  WEAK: slope negative but F < 5. Consider an alternative outcome\n")
  cat("        (Belgian PPI, or BACI-cleaned UV) before abandoning.\n")
} else {
  cat("  FAIL: slope wrong-sign or zero. China shock does not transmit\n")
  cat("        to Belgian unit values via the pro-competitive channel.\n")
  cat("        Likely abandon the China shock.\n")
}

cat("================================================================\n")
sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase6_eyeball_e2_summary.txt"), "\n")

cat("\nDone.\n")
