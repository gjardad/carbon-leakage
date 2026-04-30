###############################################################################
# phase6_eyeball_e1_shifter_dispersion.R
#
# PURPOSE:
#   Eyeball E1 from ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md (China shock section).
#
#   Distribution of Delta-ChinaShare_k,EU-excl-BE,2002→2012 across HS6 products.
#   Direct analog of Peter & Ruane (2025) Appendix Figure B.3 (distribution
#   of tariff changes across 5-digit ASICC inputs) and Figure B.4
#   (importance-weighted density).
#
#     ChinaShare_k,t = (China exports to EU-26-excl-BE of HS6 k, year t)
#                      / (total imports into EU-26-excl-BE of HS6 k, year t)
#
#     Delta-ChinaShare_k = ChinaShare_k,2012 - ChinaShare_k,2002
#
#   Verdict reading:
#     - Trade-weighted SD ≥ 20pp     -> shifter is dispersed; proceed.
#     - Trade-weighted SD 5–20pp     -> moderate; identification will be noisy.
#     - Trade-weighted SD < 5pp      -> abandon. Shifter is too tight at source.
#
# INPUT:
#   $RAW_DATA/BACI_HS02_V202601/BACI_HS02_Y2002_V202601.csv
#   $RAW_DATA/BACI_HS02_V202601/BACI_HS02_Y2012_V202601.csv
#   $RAW_DATA/BACI_HS02_V202601/country_codes_V202601.csv
#
# OUTPUT:
#   data/processed/phase6_china_shifter_2002_2012.RData
#     china_shifter_hs6: HS6 × {ChinaShare_2002, ChinaShare_2012, delta,
#                                value_total_2002, importance_weight, ...}
#     eu26_iso3, eu26_numeric, china_numeric (lookup vectors)
#   output/figures/phase6_eyeball_e1_shifter_dispersion.pdf
#   output/figures/phase6_eyeball_e1_shifter_density.pdf
#   output/tables/phase6_eyeball_e1_summary.csv
#   output/tables/phase6_eyeball_e1_summary.txt
#
# CAVEATS:
#   - Importer set: fixed EU-27 (post-2007 enlargement) minus Belgium = 26
#     countries. Croatia (joined 2013) is excluded throughout to keep a
#     stable set across the 2002-2012 window. UK is in throughout — Brexit
#     (2020) is outside the LR window for E1.
#   - HS02 vintage: HS6 codes are stable across 2002-2012 within the same
#     HS revision. HS6 codes appearing in only one endpoint are reported but
#     dropped from the delta.
#   - Values in BACI are nominal thousand USD. Inflation does not affect
#     ChinaShare (a within-year ratio).
#   - HS6 codes with zero EU-26 import value in either endpoint are dropped
#     (cannot compute share). HS6 codes in the lower 1% by 2002 trade value
#     are flagged for the headline figure to avoid noise from negligible
#     products; untrimmed stats reported alongside.
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

# ---- EU-26 country list (EU-27 as of 2007 minus Belgium) ----
# Croatia (joined 2013) excluded so the importer set is fixed across our
# 2002-2012 LR window. ISO3 alpha for readability; numeric codes resolved
# below from the BACI dictionary so we never hardcode CEPII numeric IDs.
eu26_iso3 <- c(
  "AUT", "BGR", "CYP", "CZE", "DEU", "DNK", "ESP", "EST",
  "FIN", "FRA", "GBR", "GRC", "HUN", "IRL", "ITA", "LTU",
  "LUX", "LVA", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
  "SVN", "SWE"
)
stopifnot(length(eu26_iso3) == 26)

# ---- Country codes ----
cat("Loading country codes...\n")
country_codes <- fread(file.path(BACI_DIR, "country_codes_V202601.csv"))

# Some ISO3 codes map to multiple historical numeric codes in BACI's
# dictionary (e.g., DEU → 276 [Germany] and 280 [Fed. Rep. of Germany,
# pre-1990]). Including all of them is harmless: pre-1990 entities have
# no flows in our 2002-2012 window and are silent no-ops in the importer
# filter. We assert that all 26 ISO3 codes are FOUND, not that exactly
# 26 numeric codes match.
eu26_numeric <- country_codes[country_iso3 %in% eu26_iso3, country_code]
missing_iso3 <- setdiff(eu26_iso3, country_codes$country_iso3)
stopifnot(length(missing_iso3) == 0)
stopifnot(length(eu26_numeric) >= 26)

n_extra <- length(eu26_numeric) - 26
if (n_extra > 0) {
  extras <- country_codes[country_iso3 %in% eu26_iso3,
                          .(.N), by = country_iso3][N > 1]
  cat(sprintf("Note: %d extra historical numeric codes map to ISO3 in EU-26 ",
              n_extra),
      "(harmless — no flows in 2002-2012):\n", sep = "")
  print(extras)
}

china_numeric <- country_codes[country_iso3 == "CHN", country_code]
stopifnot(length(china_numeric) >= 1)
if (length(china_numeric) > 1) {
  cat(sprintf("Note: %d historical numeric codes map to CHN; using all.\n",
              length(china_numeric)))
}

cat(sprintf("EU-26 numeric codes (incl. historical): %s\n",
            paste(sort(eu26_numeric), collapse = ", ")))
cat(sprintf("China numeric codes: %s\n",
            paste(sort(china_numeric), collapse = ", ")))

# ---- Loader: read one annual BACI file, filter to EU-26 importers ----
load_baci_year <- function(year) {
  f <- file.path(BACI_DIR, sprintf("BACI_HS02_Y%d_V202601.csv", year))
  cat(sprintf("Reading %s ...\n", basename(f)))
  dt <- fread(f, colClasses = c(t = "integer", i = "integer", j = "integer",
                                k = "character", v = "numeric", q = "character"))
  dt <- dt[j %in% eu26_numeric]
  # Pad HS6 to 6 chars (BACI strips leading zeros on integer codes).
  dt[, k := formatC(as.integer(k), width = 6, flag = "0")]
  dt
}

y2002 <- load_baci_year(2002)
y2012 <- load_baci_year(2012)

cat(sprintf("Rows after EU-26 filter: 2002 = %s, 2012 = %s\n",
            format(nrow(y2002), big.mark = ","),
            format(nrow(y2012), big.mark = ",")))

# ---- Aggregate to HS6 × year ----
agg_share <- function(dt, china_codes) {
  total <- dt[, .(value_total = sum(v, na.rm = TRUE)), by = k]
  china <- dt[i %in% china_codes, .(value_china = sum(v, na.rm = TRUE)), by = k]
  merged <- merge(total, china, by = "k", all.x = TRUE)
  merged[is.na(value_china), value_china := 0]
  merged <- merged[value_total > 0]
  merged[, china_share := value_china / value_total]
  merged
}

share_2002 <- agg_share(y2002, china_numeric)
share_2012 <- agg_share(y2012, china_numeric)

setnames(share_2002,
         c("value_total", "value_china", "china_share"),
         c("value_total_2002", "value_china_2002", "china_share_2002"))
setnames(share_2012,
         c("value_total", "value_china", "china_share"),
         c("value_total_2012", "value_china_2012", "china_share_2012"))

# ---- Merge endpoints, compute Δ ----
shifter <- merge(share_2002, share_2012, by = "k", all = TRUE)

n_only_2002 <- shifter[is.na(china_share_2012), .N]
n_only_2012 <- shifter[is.na(china_share_2002), .N]
n_both      <- shifter[!is.na(china_share_2002) & !is.na(china_share_2012), .N]
cat(sprintf("HS6 codes only in 2002: %d\n", n_only_2002))
cat(sprintf("HS6 codes only in 2012: %d\n", n_only_2012))
cat(sprintf("HS6 codes in both     : %d\n", n_both))

shifter <- shifter[!is.na(china_share_2002) & !is.na(china_share_2012)]
shifter[, delta_china_share := china_share_2012 - china_share_2002]

# Importance weight: 2002 baseline EU-26 trade value (P&R / Borusyak style).
shifter[, importance_weight := value_total_2002 / sum(value_total_2002)]

# Lower-1% trade trim flag for headline figure.
trade_q01 <- shifter[, quantile(value_total_2002, 0.01)]
shifter[, headline_keep := value_total_2002 >= trade_q01]
n_trimmed <- shifter[headline_keep == FALSE, .N]
cat(sprintf("Trimmed for headline (lower 1%% by 2002 trade value): %d HS6.\n",
            n_trimmed))

# ---- Weighted-quantile helper (no external dependency) ----
wquantile <- function(x, w, probs) {
  keep <- !is.na(x) & !is.na(w) & w > 0
  x <- x[keep]; w <- w[keep]
  ord <- order(x)
  xo <- x[ord]; wo <- w[ord]
  cw <- cumsum(wo) / sum(wo)
  approx(cw, xo, xout = probs, ties = mean, rule = 2)$y
}

# ---- Summary moments ----
summarize_delta <- function(dt, weighted = FALSE) {
  x <- dt$delta_china_share
  if (weighted) {
    w  <- dt$importance_weight
    mu <- sum(x * w) / sum(w)
    list(
      n    = nrow(dt),
      mean = mu,
      sd   = sqrt(sum(w * (x - mu)^2) / sum(w)),
      p10  = wquantile(x, w, 0.10),
      p25  = wquantile(x, w, 0.25),
      p50  = wquantile(x, w, 0.50),
      p75  = wquantile(x, w, 0.75),
      p90  = wquantile(x, w, 0.90),
      p99  = wquantile(x, w, 0.99)
    )
  } else {
    list(
      n    = nrow(dt),
      mean = mean(x),
      sd   = sd(x),
      p10  = unname(quantile(x, 0.10)),
      p25  = unname(quantile(x, 0.25)),
      p50  = unname(quantile(x, 0.50)),
      p75  = unname(quantile(x, 0.75)),
      p90  = unname(quantile(x, 0.90)),
      p99  = unname(quantile(x, 0.99))
    )
  }
}

stats_full <- summarize_delta(shifter, weighted = FALSE)
stats_trim <- summarize_delta(shifter[headline_keep == TRUE], weighted = FALSE)
stats_w    <- summarize_delta(shifter[headline_keep == TRUE], weighted = TRUE)

make_row <- function(scope_label, stats) {
  do.call(data.table, c(list(scope = scope_label), stats))
}

summary_dt <- rbindlist(list(
  make_row("all_HS6_unweighted",    stats_full),
  make_row("trimmed_unweighted",    stats_trim),
  make_row("trimmed_weighted_2002", stats_w)
), fill = TRUE)

print(summary_dt, digits = 3)

fwrite(summary_dt, file.path(OUTPUT_TAB, "phase6_eyeball_e1_summary.csv"))
cat("Saved:", file.path(OUTPUT_TAB, "phase6_eyeball_e1_summary.csv"), "\n")

# ---- Effective number of shifts (Borusyak inverse Herfindahl) ----
herf  <- sum(shifter$importance_weight^2)
n_eff <- 1 / herf
cat(sprintf("Effective number of shifts (1/H of importance weights): %.1f\n",
            n_eff))
cat(sprintf("Largest single-HS6 weight                              : %.4f\n",
            max(shifter$importance_weight)))

# ---- Figure 1: histogram of Delta-ChinaShare ----
plot_dt <- shifter[headline_keep == TRUE]

p_hist <- ggplot(plot_dt, aes(x = delta_china_share)) +
  geom_histogram(bins = 60, fill = "steelblue", alpha = 0.85) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40") +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  labs(
    title    = "Distribution of Delta-ChinaShare across HS6, 2002 -> 2012",
    subtitle = sprintf(
      paste0("EU-26 (excl. Belgium and Croatia) imports. N = %s HS6 after 1%% lower-trade trim. ",
             "Unweighted SD = %.1fpp; trade-weighted SD = %.1fpp; effective shifts = %.0f."),
      format(stats_trim$n, big.mark = ","),
      100 * stats_trim$sd, 100 * stats_w$sd, n_eff),
    x        = "Delta-ChinaShare = China share of EU-26 imports of HS6 k, 2012 minus 2002",
    y        = "Number of HS6 codes",
    caption  = "Source: BACI HS02 V202601. Eyeball E1, ALTERNATIVE_SHOCKS_TO_ESTIMATE_ELASTICITY.md."
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.title.position = "plot",
        plot.subtitle = element_text(colour = "grey30", size = 9))

ggsave(file.path(OUTPUT_FIG, "phase6_eyeball_e1_shifter_dispersion.pdf"),
       p_hist, width = 9, height = 6)
cat("Saved:", file.path(OUTPUT_FIG, "phase6_eyeball_e1_shifter_dispersion.pdf"),
    "\n")

# ---- Figure 2: weighted vs unweighted density (P&R Appendix Fig B.4 analog) ----
p_density <- ggplot(plot_dt, aes(x = delta_china_share)) +
  geom_density(aes(weight = importance_weight, colour = "Trade-weighted (2002 value)"),
               linewidth = 0.9) +
  geom_density(aes(colour = "Unweighted"), linewidth = 0.9, linetype = "dashed") +
  geom_vline(xintercept = 0, linetype = "dotted", colour = "grey40") +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_colour_manual(values = c("Trade-weighted (2002 value)" = "steelblue",
                                  "Unweighted"                  = "tomato")) +
  labs(
    title    = "Delta-ChinaShare density: trade-weighted vs unweighted",
    subtitle = "Trade-weighted uses 2002 EU-26 import value as importance weight (Borusyak et al. 2022).",
    x        = "Delta-ChinaShare 2002 -> 2012",
    y        = "Density",
    colour   = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom")

ggsave(file.path(OUTPUT_FIG, "phase6_eyeball_e1_shifter_density.pdf"),
       p_density, width = 8, height = 5)
cat("Saved:", file.path(OUTPUT_FIG, "phase6_eyeball_e1_shifter_density.pdf"),
    "\n")

# ---- Persist processed shifter for downstream eyeballs ----
china_shifter_hs6 <- shifter
save(china_shifter_hs6, eu26_iso3, eu26_numeric, china_numeric,
     file = file.path(OUT_DATA, "phase6_china_shifter_2002_2012.RData"))
cat("Saved:", file.path(OUT_DATA, "phase6_china_shifter_2002_2012.RData"), "\n")

# ---- Readable summary text file ----
sink(file.path(OUTPUT_TAB, "phase6_eyeball_e1_summary.txt"))

cat("================================================================\n")
cat("Eyeball E1 -- China shifter dispersion 2002 -> 2012\n")
cat("Generated by analysis/phase6_eyeball_e1_shifter_dispersion.R\n")
cat("================================================================\n\n")

cat("Definition:\n")
cat("  ChinaShare_k,t = China exports to EU-26-excl-BE in HS6 k, year t\n")
cat("                   / total imports into EU-26-excl-BE in HS6 k, year t\n")
cat("  Delta-ChinaShare_k = ChinaShare_k,2012 - ChinaShare_k,2002\n\n")

cat("Importer set (EU-27 as of 2007 minus Belgium, fixed across years):\n")
cat(sprintf("  %s\n", paste(eu26_iso3, collapse = ", ")))
cat(sprintf("  N countries: %d\n\n", length(eu26_iso3)))

cat("Sample sizes:\n")
cat(sprintf("  HS6 in BACI 2002 (EU-26 importers, value > 0): %d\n",
            n_only_2002 + n_both))
cat(sprintf("  HS6 in BACI 2012 (EU-26 importers, value > 0): %d\n",
            n_only_2012 + n_both))
cat(sprintf("  HS6 in both                                  : %d\n", n_both))
cat(sprintf("  HS6 dropped (lower-1%% trade trim, headline)  : %d\n", n_trimmed))
cat(sprintf("  HS6 in headline figure                       : %d\n\n",
            stats_trim$n))

cat("Summary statistics (Δ in fractional units; multiply by 100 for pp):\n")
print(summary_dt, digits = 4)
cat("\n")

cat("Effective number of shifts (Borusyak et al. 2022):\n")
cat(sprintf("  1 / Herfindahl(importance_weights) = %.1f\n", n_eff))
cat(sprintf("  Largest single-HS6 importance weight = %.4f\n\n",
            max(shifter$importance_weight)))

cat("================================================================\n")
cat("Verdict (using trade-weighted SD):\n")
cat(sprintf("  Trade-weighted SD = %.2f pp\n", 100 * stats_w$sd))
cat("  P&R benchmark (Indian tariff SD): 41pp raw, 36pp weighted.\n")
if (100 * stats_w$sd >= 20) {
  cat("  PASS: shifter is dispersed enough to support identification.\n")
} else if (100 * stats_w$sd >= 5) {
  cat("  BORDERLINE: dispersion is moderate; identification will be noisy.\n")
} else {
  cat("  FAIL: dispersion is too small at the source.\n")
  cat("        Abandon the China shock, or look for a different shifter.\n")
}
cat("================================================================\n")

sink()
cat("Saved:", file.path(OUTPUT_TAB, "phase6_eyeball_e1_summary.txt"), "\n")

cat("\nDone.\n")
