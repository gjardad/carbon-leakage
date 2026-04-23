###############################################################################
# phase4_sector_passthrough_classification.R
#
# PURPOSE:
#   Build per-NACE4d-sector realized pass-through coefficients gamma_s via an
#   interacted monthly panel LP at h = 12 months, and classify sectors into
#   high / no / unclassified pass-through buckets. Output consumed by
#   phase4_firm_output_reallocation.R to run Spec 1.C (sample split) of
#   REALLOCATION_MECHANISM_PLAN.md.
#
# SPEC:
#   dlog_ppi_h12_{s,m} = sum_s [ gamma_s * CPShock_m * I(sector=s) ]
#                      + alpha_s + delta_m + eps
#   where dlog_ppi_h12_{s,m} = log(PPI_{s,m+12}) - log(PPI_{s,m-1}).
#   Identification: cross-sector response to the same monthly shock.
#
# Unlike S12 in phase3_ppi_passthrough_monthly.R, the RHS here is CPShock alone
# (interacted with sector dummies), not CPShock * intensity_base_s. gamma_s
# absorbs the intensity_base scale — it is realized per-unit-shock pass-through
# at the sector level, not pass-through per unit of exposure.
#
# Two CPShock variants:
#   - cpshock_shock   (primary, matches the S12 headline series)
#   - cpshock_surprise (robustness)
#
# CLASSIFICATION:
#   high-pass-through: gamma_s > 0 and t > 1.645 (one-sided, 10% significance)
#   no-pass-through:   otherwise (including gamma_s <= 0)
#   unclassified:      sectors without a coefficient (missing sector dummy /
#                      insufficient obs)
#   Robustness cutoffs also computed: 5% two-sided, and top-tercile of gamma_s.
#
# INPUT:
#   NBB_data/processed/deflator_nace4d_2005base_monthly.RData
#   NBB_data/raw/carbonPolicyShocks.xlsx (Monthly sheet)
#   data/processed/phase3_sector_exposure.RData (for ETS-sector filter)
#
# OUTPUT:
#   data/processed/phase4_sector_passthrough.RData
#       - sector_passthrough (data.frame: nace4d, gamma_shock, se_shock,
#                             gamma_surprise, se_surprise, n_obs,
#                             class_shock_10, class_shock_5, class_shock_tercile,
#                             class_surprise_10, ...)
#   output/tables/phase4_sector_passthrough_classification.txt
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readxl)
  library(lubridate)
  library(fixest)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

horizon <- 12
sample_start <- as.Date("2005-01-01")
sample_end   <- as.Date("2019-12-01")

# ---------------------------------------------------------------------------
# Load monthly PPI and CPShock
# ---------------------------------------------------------------------------
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))  # deflator_monthly

xlsx_path <- file.path(RAW_DATA, "carbonPolicyShocks.xlsx")
cps_raw <- read_excel(xlsx_path, sheet = "Monthly")
cps <- cps_raw %>%
  mutate(year  = as.integer(substr(Date, 1, 4)),
         month = as.integer(substr(Date, 6, 7)),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  transmute(date, cpshock_surprise = Surprise, cpshock_shock = Shock)

# ---------------------------------------------------------------------------
# Build panel with cumulative h-step PPI difference
# ---------------------------------------------------------------------------
panel_m <- deflator_monthly %>%
  filter(date >= sample_start, date <= sample_end) %>%
  left_join(cps, by = "date") %>%
  mutate(log_ppi    = log(ppi),
         year_month = format(date, "%Y-%m")) %>%
  arrange(nace4d, date)

# dlog_ppi_h = log(ppi_{m+h}) - log(ppi_{m-1})
panel_m$dlog_ppi_h <- ave(panel_m$log_ppi, panel_m$nace4d,
                          FUN = function(x) {
                            n <- length(x)
                            out <- rep(NA_real_, n)
                            for (i in seq_len(n)) {
                              if ((i + horizon) <= n && (i - 1) >= 1) {
                                out[i] <- x[i + horizon] - x[i - 1]
                              }
                            }
                            out
                          })

cat(sprintf("Monthly panel: %d obs, %d NACE4d sectors, %s to %s\n",
            nrow(panel_m), n_distinct(panel_m$nace4d),
            format(min(panel_m$date)), format(max(panel_m$date))))
cat(sprintf("Non-NA dlog_ppi_h%d: %d\n", horizon, sum(!is.na(panel_m$dlog_ppi_h))))

# ---------------------------------------------------------------------------
# Interacted panel LP: per-sector gamma_s
# ---------------------------------------------------------------------------
# fixest's i(sector, shock) gives per-sector coefficients with the
# sector-FE omitted reference absorbed by alpha_s.

run_per_sector_lp <- function(shock_col) {
  f <- as.formula(sprintf("dlog_ppi_h ~ i(nace4d, %s) | nace4d + year_month",
                          shock_col))
  # Cluster on year_month (not nace4d): with i(nace4d, shock), per-sector
  # coefficients are each within a single nace4d cluster, so cluster-nace4d
  # is degenerate. The shock is month-common, so year_month is the correct
  # dimension for clustering.
  m <- feols(f, data = panel_m, cluster = ~ year_month)
  ct <- coeftable(m)
  # Row names look like "nace4d::1013:cpshock_shock"; extract sector code.
  rows <- rownames(ct)
  pat  <- sprintf("^nace4d::(.+):%s$", shock_col)
  hits <- grepl(pat, rows)
  if (!any(hits)) stop("Could not parse per-sector coefficients.")
  sec  <- sub(pat, "\\1", rows[hits])
  out <- data.frame(
    nace4d = sec,
    gamma  = ct[hits, "Estimate"],
    se     = ct[hits, "Std. Error"],
    row.names = NULL
  ) %>% mutate(t = gamma / se)
  list(model = m, coefs = out)
}

cat("\n=== Per-sector LP with cpshock_shock ===\n")
res_shock <- run_per_sector_lp("cpshock_shock")
cat(sprintf("Sectors with a coefficient: %d / %d\n",
            nrow(res_shock$coefs), n_distinct(panel_m$nace4d)))
print(summary(res_shock$coefs$gamma))
print(summary(res_shock$coefs$t))

cat("\n=== Per-sector LP with cpshock_surprise ===\n")
res_surprise <- run_per_sector_lp("cpshock_surprise")
cat(sprintf("Sectors with a coefficient: %d / %d\n",
            nrow(res_surprise$coefs), n_distinct(panel_m$nace4d)))
print(summary(res_surprise$coefs$gamma))
print(summary(res_surprise$coefs$t))

# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------
tercile_cutoff <- function(x) {
  q <- quantile(x, probs = 2/3, na.rm = TRUE)
  as.numeric(q)
}

cls_shock <- res_shock$coefs %>%
  rename(gamma_shock = gamma, se_shock = se, t_shock = t)
cls_surprise <- res_surprise$coefs %>%
  rename(gamma_surprise = gamma, se_surprise = se, t_surprise = t)

cutoff_shock_tercile    <- tercile_cutoff(cls_shock$gamma_shock)
cutoff_surprise_tercile <- tercile_cutoff(cls_surprise$gamma_surprise)

sector_passthrough <- full_join(cls_shock, cls_surprise, by = "nace4d") %>%
  mutate(
    # Sign-only (loose, keeps sample size up at the cost of noise)
    class_shock_sign     = ifelse(is.na(gamma_shock),    "unclassified",
                            ifelse(gamma_shock > 0,    "high", "no")),
    class_surprise_sign  = ifelse(is.na(gamma_surprise), "unclassified",
                            ifelse(gamma_surprise > 0, "high", "no")),
    # Tercile
    class_shock_tercile  = ifelse(is.na(gamma_shock),    "unclassified",
                            ifelse(gamma_shock    >= cutoff_shock_tercile,   "high", "no")),
    class_surprise_tercile = ifelse(is.na(gamma_surprise), "unclassified",
                            ifelse(gamma_surprise >= cutoff_surprise_tercile, "high", "no")),
    # Significance cutoffs (one-sided vs zero)
    class_shock_10       = ifelse(is.na(gamma_shock), "unclassified",
                            ifelse(gamma_shock > 0 & t_shock > 1.645, "high", "no")),
    class_shock_5        = ifelse(is.na(gamma_shock), "unclassified",
                            ifelse(gamma_shock > 0 & t_shock > 1.96,  "high", "no")),
    class_surprise_10    = ifelse(is.na(gamma_surprise), "unclassified",
                            ifelse(gamma_surprise > 0 & t_surprise > 1.645, "high", "no")),
    class_surprise_5     = ifelse(is.na(gamma_surprise), "unclassified",
                            ifelse(gamma_surprise > 0 & t_surprise > 1.96,  "high", "no")),
    # Intersection (both variants agree γ > 0 and sig at 10%)
    class_intersect_10   = ifelse(class_shock_10 == "high" & class_surprise_10 == "high",
                                  "high",
                            ifelse(class_shock_10 == "unclassified" |
                                   class_surprise_10 == "unclassified",
                                  "unclassified", "no")),
    # Intersection of signs (both variants agree γ > 0, without significance)
    class_intersect_sign = ifelse(class_shock_sign == "high" & class_surprise_sign == "high",
                                  "high",
                            ifelse(class_shock_sign == "unclassified" |
                                   class_surprise_sign == "unclassified",
                                  "unclassified", "no"))
  )

# ---------------------------------------------------------------------------
# Summaries
# ---------------------------------------------------------------------------
summarise_class <- function(col) {
  tab <- table(sector_passthrough[[col]], useNA = "ifany")
  cat(sprintf("  %-28s  ", col))
  print(tab)
}

cat("\n=== Classification counts ===\n")
for (col in c("class_shock_sign","class_shock_tercile","class_shock_10","class_shock_5",
              "class_surprise_sign","class_surprise_tercile","class_surprise_10","class_surprise_5",
              "class_intersect_10","class_intersect_sign")) {
  summarise_class(col)
}

# Top 10 pass-through sectors under each variant
cat("\n=== Top 10 high-pass-through sectors (shock) ===\n")
print(sector_passthrough %>%
        arrange(desc(gamma_shock)) %>%
        head(10) %>%
        select(nace4d, gamma_shock, se_shock, t_shock,
               class_shock_10, class_shock_5))

cat("\n=== Top 10 high-pass-through sectors (surprise) ===\n")
print(sector_passthrough %>%
        arrange(desc(gamma_surprise)) %>%
        head(10) %>%
        select(nace4d, gamma_surprise, se_surprise, t_surprise,
               class_surprise_10, class_surprise_5))

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
save(sector_passthrough, file = file.path(OUT_DATA, "phase4_sector_passthrough.RData"))
cat(sprintf("\nSaved %s (%d rows)\n",
            file.path(OUT_DATA, "phase4_sector_passthrough.RData"),
            nrow(sector_passthrough)))

sink(file.path(OUTPUT_TAB, "phase4_sector_passthrough_classification.txt"))
cat("================================================================\n")
cat(" Per-sector realized pass-through gamma_s at h = 12 months\n")
cat("================================================================\n\n")
cat("Spec: dlog_ppi_h12_{s,m} = sum_s [ gamma_s * CPShock_m * I(sector=s) ]\n")
cat("       + alpha_s + delta_m + eps\n")
cat("Sample: 2005-01 to 2019-12. FE: nace4d + year_month. Cluster: nace4d.\n\n")

cat("Shock variant: gamma_s summary:\n"); print(summary(sector_passthrough$gamma_shock))
cat("Shock variant: t summary:\n");        print(summary(sector_passthrough$t_shock))
cat("Surprise variant: gamma_s summary:\n"); print(summary(sector_passthrough$gamma_surprise))
cat("Surprise variant: t summary:\n");       print(summary(sector_passthrough$t_surprise))

cat("\nClassification counts:\n")
for (col in c("class_shock_10","class_shock_5","class_shock_tercile",
              "class_surprise_10","class_surprise_5","class_surprise_tercile",
              "class_intersect_10")) {
  cat(sprintf("\n%s:\n", col))
  print(table(sector_passthrough[[col]], useNA = "ifany"))
}
sink()

cat("\nWrote per-sector classification tables.\n")
