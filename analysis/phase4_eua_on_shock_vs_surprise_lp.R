###############################################################################
# phase4_eua_on_shock_vs_surprise_lp.R
#
# PURPOSE:
#   Appendix (b) of the pass-through section: time-series local-projection
#   "first-stage" regressions of the cumulative monthly log-EUA price change
#   on the Känzig (2023) Shock and on the Känzig Surprise series, in
#   parallel. The two-column table shows the dynamic R_h coefficients side
#   by side, so the reader can compare the EUA-price response to the two
#   instruments at common horizons.
#
# SPEC at horizon h (months):
#   log(EUA_{m+h}) - log(EUA_{m-1}) =
#       R_h^{shock}    · Shock_m    + Σ_{j=1..6} φ_j · log(EUA_{m-j})  + u_{m,h}
#   log(EUA_{m+h}) - log(EUA_{m-1}) =
#       R_h^{surprise} · Surprise_m + Σ_{j=1..6} φ_j · log(EUA_{m-j})  + u_{m,h}
#
#   Heteroskedasticity-robust SE (matches phase3_passthrough_iv.R first
#   stage). Sample: 2005m1-2019m12 (Känzig CPShock coverage).
#   Horizons: h ∈ {0, 1, 3, 6, 12, 18, 24}.
#
# OUTPUT:
#   ${OUTPUT_TAB}/phase4_eua_on_shock_vs_surprise_lp.csv
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readr); library(readxl)
  library(lubridate); library(fixest)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

P_LAGS      <- 6L
HORIZONS    <- c(0, 1, 3, 6, 12, 18, 24)
SAMPLE_FROM <- as.Date("2005-01-01")
SAMPLE_TO   <- as.Date("2019-12-01")

# ---- 1. Daily EUA → monthly log-mean ----
eua_file <- file.path(
  RAW_DATA,
  "European Union Carbon Permits Allowance (EUA) Yearly Futures Historical Data.csv"
)
eua_raw <- read_csv(
  eua_file,
  col_types = cols(Date = col_date(format = "%m/%d/%Y"),
                   Price = col_double(), .default = col_character()))
eua_d <- eua_raw %>% rename(date = Date, price = Price) %>%
  filter(!is.na(date), !is.na(price), price > 0) %>% arrange(date)

eua_m <- eua_d %>%
  mutate(year = year(date), month = month(date)) %>%
  group_by(year, month) %>%
  summarise(eua_mean = mean(price, na.rm = TRUE), .groups = "drop") %>%
  mutate(date    = as.Date(sprintf("%d-%02d-01", year, month)),
         log_eua = log(eua_mean)) %>%
  arrange(date) %>%
  filter(date >= as.Date("2003-01-01"), date <= SAMPLE_TO)
cat(sprintf("Monthly EUA: %d obs, %s to %s\n",
            nrow(eua_m), format(min(eua_m$date)), format(max(eua_m$date))))

# ---- 2. CPShock monthly (Shock + Surprise) ----
xlsx_path <- file.path(RAW_DATA, "carbonPolicyShocks.xlsx")
cps_raw <- read_excel(xlsx_path, sheet = "Monthly")
cps <- cps_raw %>%
  mutate(year  = as.integer(substr(Date, 1, 4)),
         month = as.integer(substr(Date, 6, 7)),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  transmute(date, shock = Shock, surprise = Surprise)
cat(sprintf("CPShock monthly: %d obs, %s to %s\n",
            nrow(cps), format(min(cps$date)), format(max(cps$date))))

# ---- 3. Build time-series with lags ----
ts <- eua_m %>% select(date, log_eua) %>%
  left_join(cps, by = "date") %>%
  arrange(date)

for (j in 1:P_LAGS) {
  ts[[paste0("log_eua_lag", j)]] <- dplyr::lag(ts$log_eua, j)
}
for (h in HORIZONS) {
  ts[[paste0("log_eua_lead", h)]] <-
    sapply(seq_len(nrow(ts)),
           function(i) if ((i + h) <= nrow(ts)) ts$log_eua[i + h] else NA_real_)
}

# ---- 4. Run LP for each instrument and horizon ----
eua_lag_terms <- paste(paste0("log_eua_lag", 1:P_LAGS), collapse = " + ")

run_R_lp <- function(h, instrument_col) {
  lhs_col <- paste0("log_eua_lead", h)
  dat <- ts %>%
    transmute(y_eua  = .data[[lhs_col]] - log_eua_lag1,
              instr  = .data[[instrument_col]],
              date,
              log_eua_lag1, log_eua_lag2, log_eua_lag3,
              log_eua_lag4, log_eua_lag5, log_eua_lag6) %>%
    filter(date >= SAMPLE_FROM, date <= SAMPLE_TO,
           !is.na(y_eua), !is.na(instr), !is.na(log_eua_lag6))

  frm <- as.formula(sprintf("y_eua ~ instr + %s", eua_lag_terms))
  m <- feols(frm, data = dat, vcov = "hetero")
  ct <- coeftable(m)
  data.frame(h = h,
             instrument = instrument_col,
             R = ct["instr", 1], R_se = ct["instr", 2], n = m$nobs)
}

res_shock <- bind_rows(lapply(HORIZONS, run_R_lp, instrument_col = "shock"))
res_surp  <- bind_rows(lapply(HORIZONS, run_R_lp, instrument_col = "surprise"))

res <- bind_rows(res_shock, res_surp) %>%
  mutate(t_stat = R / R_se,
         lo90   = R - 1.645 * R_se,
         hi90   = R + 1.645 * R_se,
         lo95   = R - 1.96  * R_se,
         hi95   = R + 1.96  * R_se)

cat("\nResults (R_h: cumulative log-EUA response per unit instrument):\n")
print(res %>% mutate(across(c(R, R_se, t_stat, lo90, hi90, lo95, hi95),
                            ~ round(.x, 4))))

write.csv(res, file.path(OUTPUT_TAB, "phase4_eua_on_shock_vs_surprise_lp.csv"),
          row.names = FALSE)
cat(sprintf("\nSaved: %s\n",
            file.path(OUTPUT_TAB, "phase4_eua_on_shock_vs_surprise_lp.csv")))

# Wide form for paper table
wide <- res %>%
  select(h, instrument, R, R_se) %>%
  pivot_wider(names_from = instrument,
              values_from = c(R, R_se),
              names_glue   = "{instrument}_{.value}")
cat("\nWide form for paper table:\n")
print(wide %>% mutate(across(-h, ~ round(.x, 4))))
