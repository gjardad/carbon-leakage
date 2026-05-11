###############################################################################
# phase4_across_nace4d_intensive_by_size_holding_exposure.R
#
# PURPOSE
#   Heterogeneity #7 on across-NACE4d intensive margin: bin buyers on TWO
#   dimensions -- pre-period exposure AND pre-period size -- and plot the
#   share of B2B expenditure on ETS-NACE4d for each (exposure x size) cell.
#
#   Motivation: the original aggregate-vs-mean gap in the intensive-margin
#   plot suggests that large buyers shifted away from ETS-NACE4d in the
#   aggregate. The question is whether this is just composition (large
#   buyers happen to be the high-exposure ones, who can mechanically
#   shift more) or a genuine size effect (within an exposure bin, large
#   buyers reallocate more than small ones). Plot #7 holds exposure fixed
#   and varies size.
#
#   Definitions (all pre-period 2008-2012):
#     expo_j = sum_{t in 2008-12, n in ETS-NACE4d} spend(j, n, t)
#            / sum_{t in 2008-12}                  spend(j, t)
#     size_j = sum_{t in 2008-12} spend(j, t)            (log domain for bins)
#
#   Exposure binning: Q0 (expo == 0) + tertiles of (expo > 0). Matches
#   plot #2 to keep buyer assignments comparable.
#   Size binning:     quartiles within each exposure bin (independent within
#   bin so cell counts are balanced).
#
#   Outcome: buyer-year share on ANY ETS-NACE4d (all 106 sectors, not just
#   high-shortage). This is the broadest reallocation outcome and matches
#   the original phase4_across_nace4d_intensive_margin plot.
#
# OUTPUTS
#   - phase4_across_nace4d_intensive_by_size_holding_exposure.{png,pdf}
#   - phase4_across_nace4d_intensive_by_size_holding_exposure.csv
###############################################################################

rm(list = ls())

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

set.seed(20260511)

YEAR_LO   <- 2005L
YEAR_HI   <- 2022L
PRE_YEARS <- 2008L:2012L
N_BOOT    <- 1000L

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
ets_nace4d <- unique(as.data.table(firm_exposure)$nace4d)
ets_nace4d <- ets_nace4d[!is.na(ets_nace4d) & ets_nace4d != ""]
rm(firm_exposure)

# ---------------------------------------------------------------------------
# 2. Tag B2B with seller NACE4d and ETS flag
# ---------------------------------------------------------------------------
seller_nace <- aa[, .(seller = vat, year, seller_nace4d = nace4d)]
b2b <- merge(b2b, seller_nace, by = c("seller", "year"), all.x = TRUE)
b2b[, is_ets := as.integer(!is.na(seller_nace4d) & seller_nace4d %in% ets_nace4d)]

# ---------------------------------------------------------------------------
# 3. Pre-period buyer exposure and size
# ---------------------------------------------------------------------------
cat("\nComputing pre-period exposure and size on", paste(range(PRE_YEARS), collapse = "-"), "...\n")
buyer_pre <- b2b[year %in% PRE_YEARS, .(
  pre_spend_ets = sum(sales * is_ets),
  pre_spend_tot = sum(sales)
), by = buyer]
buyer_pre <- buyer_pre[pre_spend_tot > 0]
buyer_pre[, expo     := pre_spend_ets / pre_spend_tot]
buyer_pre[, log_size := log(pre_spend_tot)]

# Exposure bins: Q0 (expo == 0) + tertiles of positive exposure
buyer_pre[, expo_q := NA_integer_]
buyer_pre[expo == 0, expo_q := 0L]
pos_breaks <- quantile(buyer_pre[expo > 0, expo], probs = c(0, 1/3, 2/3, 1),
                       na.rm = TRUE)
buyer_pre[expo > 0,
          expo_q := as.integer(cut(expo, breaks = pos_breaks,
                                   include.lowest = TRUE, labels = FALSE))]
buyer_pre[, expo_lab := factor(expo_q,
                               levels = 0:3,
                               labels = c("Exposure: zero",
                                          "Exposure: low",
                                          "Exposure: mid",
                                          "Exposure: high"))]

# Size quartiles WITHIN exposure bin (so cells are balanced)
buyer_pre[, size_q := NA_integer_]
buyer_pre[, size_q := as.integer(cut(log_size,
                                     breaks = quantile(log_size,
                                                       probs = seq(0, 1, .25),
                                                       na.rm = TRUE),
                                     include.lowest = TRUE, labels = FALSE)),
          by = expo_q]
buyer_pre[, size_lab := factor(size_q,
                               levels = 1:4,
                               labels = c("Size Q1 (smallest)",
                                          "Size Q2", "Size Q3",
                                          "Size Q4 (largest)"))]

cat("  buyers per (exposure, size) cell:\n")
print(dcast(buyer_pre[, .N, by = .(expo_lab, size_lab)],
            expo_lab ~ size_lab, value.var = "N", fill = 0L))

# ---------------------------------------------------------------------------
# 4. Buyer-year ETS share, attach bins
# ---------------------------------------------------------------------------
buyer_year <- b2b[, .(spend_ets = sum(sales * is_ets),
                      spend_tot = sum(sales)),
                  by = .(buyer, year)]
buyer_year <- buyer_year[spend_tot > 0]
buyer_year[, share_ets := spend_ets / spend_tot]
buyer_year <- merge(buyer_year,
                    buyer_pre[, .(buyer, expo_lab, size_lab)],
                    by = "buyer")

# ---------------------------------------------------------------------------
# 5. Per-cell per-year mean with 95% bootstrap CI
# ---------------------------------------------------------------------------
boot_ci <- function(x, n_boot = N_BOOT, alpha = 0.05) {
  x <- x[!is.na(x)]
  if (length(x) < 5L) return(list(lo = NA_real_, hi = NA_real_))
  m <- length(x)
  draws <- replicate(n_boot, mean(x[sample.int(m, m, replace = TRUE)]))
  q <- quantile(draws, c(alpha / 2, 1 - alpha / 2), names = FALSE)
  list(lo = q[1], hi = q[2])
}

pooled <- buyer_year[, {
  ci <- boot_ci(share_ets)
  .(n_buyers       = .N,
    mean_share     = mean(share_ets),
    aggregate_share = sum(spend_ets) / sum(spend_tot),
    ci_lo          = ci$lo,
    ci_hi          = ci$hi)
}, by = .(expo_lab, size_lab, year)]
setorder(pooled, expo_lab, size_lab, year)

fwrite(pooled,
       file.path(OUTPUT_TAB,
                 "phase4_across_nace4d_intensive_by_size_holding_exposure.csv"))

# ---------------------------------------------------------------------------
# 6. Plot: 4 panels (exposure), 4 lines per panel (size)
# ---------------------------------------------------------------------------
size_colors <- c("Size Q1 (smallest)" = "#fdd49e",
                 "Size Q2"            = "#fdbb84",
                 "Size Q3"            = "#e34a33",
                 "Size Q4 (largest)"  = "#b30000")

base_theme <- theme_minimal(base_size = 10) +
  theme(panel.grid.minor = element_blank(),
        legend.position  = "bottom",
        strip.text       = element_text(face = "bold"))

p <- ggplot(pooled, aes(x = year, color = size_lab, fill = size_lab)) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi), alpha = 0.15, color = NA) +
  geom_line(aes(y = mean_share), linewidth = 0.75) +
  geom_point(aes(y = mean_share), size = 1.0) +
  facet_wrap(~ expo_lab, ncol = 2) +
  scale_x_continuous(breaks = seq(YEAR_LO, YEAR_HI, by = 3)) +
  scale_y_continuous(limits = c(0, NA),
                     labels = scales::percent_format(accuracy = 1)) +
  scale_color_manual(values = size_colors, name = "Pre-period B2B-spend size quartile") +
  scale_fill_manual (values = size_colors, name = "Pre-period B2B-spend size quartile") +
  labs(title    = "Across-NACE4d intensive margin: buyer share on ETS-NACE4d, by size within each exposure bin",
       subtitle = "Each panel = one pre-period exposure bin. Lines = pre-period size quartiles (computed within bin). Mean across buyers (95% bootstrap CI).",
       x = NULL,
       y = "Share of buyer's B2B expenditure on ETS-NACE4d") +
  base_theme

ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_by_size_holding_exposure.png"),
       p, width = 10, height = 7, dpi = 200)
ggsave(file.path(OUTPUT_FIG,
                 "phase4_across_nace4d_intensive_by_size_holding_exposure.pdf"),
       p, width = 10, height = 7)

cat("\nDone.\n")
cat("  Figures: ", OUTPUT_FIG, "\n", sep = "")
cat("  Tables : ", OUTPUT_TAB, "\n", sep = "")
