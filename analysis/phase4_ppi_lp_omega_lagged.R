###############################################################################
# phase4_ppi_lp_omega_lagged.R
#
# PURPOSE:
#   Appendix (c) of the pass-through section: panel local-projection of
#   monthly sectoral PPI on the interaction of the Känzig (2023) carbon-
#   policy shock with a SECTOR-LEVEL allowance-shortage cost-share that is
#   recomputed each year from the previous year's EUTL data.
#
# SPEC at horizon h (months):
#   log(PPI_{s,m+h}) - log(PPI_{s,m-1}) =
#       γ_h · (CPShock_m · ω^sh_{s, year(m)-1}) + α_s + δ_m + ε_{s,m,h}
#
#   ω^sh_{s,y-1} = Σ_{i∈s} shortage_{i, y-1} / Σ_{i∈s} total_cost_{i, y-1},
#   computed on PRECEDING-YEAR EUTL records (predetermined, sector-time
#   varying). Sectors with zero ω^sh in y-1 enter as a clean zero.
#
#   α_s = NACE 4d FE, δ_m = year-month FE, SE clustered NACE 4d.
#   Sample: 2006m1-2019m12 (CPShock coverage; one-year burn-in for ω lag).
#   Horizons: h ∈ {0, 1, 3, 6, 12, 18, 24}.
#
# OUTPUT:
#   ${OUTPUT_TAB}/phase4_ppi_lp_omega_lagged.csv
#   ${OUTPUT_FIG}/phase4_ppi_lp_omega_lagged.{pdf,png}
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(readxl); library(stringr)
  library(lubridate); library(fixest); library(ggplot2)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

HORIZONS    <- c(0, 1, 3, 6, 12, 18, 24)
SAMPLE_FROM <- as.Date("2006-01-01")
SAMPLE_TO   <- as.Date("2019-12-01")

# ---- 1. Monthly PPI panel (use both sources for the 2006-2009 stretch) ----
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

ppi <- deflator_monthly %>%
  filter(!is.na(ppi), ppi > 0,
         ppi_source %in% c("statbel_4d_chained", "eurostat_2d"),
         date >= as.Date("2005-01-01"), date <= SAMPLE_TO) %>%
  mutate(year   = year(date),
         nace2d = str_pad(nace2d, 2, pad = "0")) %>%
  filter(as.integer(nace2d) %in% c(10:33, 35)) %>%
  mutate(log_ppi = log(ppi)) %>%
  arrange(nace4d, date)

cat(sprintf("PPI panel: %d obs, %d sectors, %s to %s\n",
            nrow(ppi), n_distinct(ppi$nace4d),
            format(min(ppi$date)), format(max(ppi$date))))

# ---- 2. Build (sector, year) ω^sh from PREVIOUS-year EUTL ----
load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))
manuf_set <- c(sprintf("%02d", 10:33), "35")

exposure <- sector_exposure %>%
  mutate(nace2d = str_sub(str_pad(nace4d, 4, pad = "0"), 1, 2)) %>%
  filter(nace2d %in% manuf_set,
         !is.na(total_cost_denom), total_cost_denom > 0) %>%
  mutate(nace4d = case_when(
    str_detect(nace4d, "^351[1-4]$") ~ "3510",
    str_detect(nace4d, "^352[1-3]$") ~ "3520",
    TRUE                              ~ nace4d
  )) %>%
  group_by(nace4d, year) %>%
  summarise(total_shortage   = sum(total_shortage,   na.rm = TRUE),
            total_cost_denom = sum(total_cost_denom, na.rm = TRUE),
            .groups = "drop") %>%
  mutate(omega_sh = total_shortage / total_cost_denom)

# Lagged version: assigned to year y means built on (y-1) data
omega_lag <- exposure %>%
  mutate(assign_year = year + 1L) %>%
  select(nace4d, assign_year, omega_sh_lag = omega_sh)

cat(sprintf("ω^sh lagged: %d (sector,year) cells, %s assign-years\n",
            nrow(omega_lag),
            paste(range(omega_lag$assign_year), collapse = "-")))

# ---- 3. Load Känzig CPShock monthly + Surprise ----
xlsx_path <- file.path(RAW_DATA, "carbonPolicyShocks.xlsx")
cps_raw <- read_excel(xlsx_path, sheet = "Monthly")
cps <- cps_raw %>%
  mutate(year  = as.integer(substr(Date, 1, 4)),
         month = as.integer(substr(Date, 6, 7)),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  transmute(date, year, cps_shock = Shock, cps_surprise = Surprise)
cat(sprintf("CPShock monthly: %d obs, %s to %s\n",
            nrow(cps), format(min(cps$date)), format(max(cps$date))))

# ---- 4. Merge panel ----
panel <- ppi %>%
  inner_join(cps %>% select(date, cps_shock), by = "date") %>%
  left_join(omega_lag, by = c("nace4d", "year" = "assign_year")) %>%
  mutate(omega_sh_lag = coalesce(omega_sh_lag, 0),
         interaction  = cps_shock * omega_sh_lag,
         year_month   = format(date, "%Y-%m"))

cat(sprintf("Merged panel: %d obs, %d sectors, %s to %s\n",
            nrow(panel), n_distinct(panel$nace4d),
            format(min(panel$date)), format(max(panel$date))))

# ---- 5. Build cumulative log-PPI changes at each horizon ----
panel <- panel %>%
  group_by(nace4d) %>%
  arrange(date, .by_group = TRUE) %>%
  mutate(log_ppi_lag1 = lag(log_ppi, 1)) %>%
  ungroup()

run_lp <- function(h) {
  p <- panel %>%
    group_by(nace4d) %>%
    arrange(date, .by_group = TRUE) %>%
    mutate(log_ppi_lead = lead(log_ppi, h)) %>%
    ungroup() %>%
    mutate(dy_h = log_ppi_lead - log_ppi_lag1) %>%
    filter(date >= SAMPLE_FROM, date <= SAMPLE_TO,
           !is.na(dy_h), !is.na(interaction))

  m <- feols(dy_h ~ interaction | nace4d + year_month,
             data = p, cluster = ~nace4d)
  data.frame(h = h, coef = coef(m)[1], se = se(m)[1], n = m$nobs)
}

res <- bind_rows(lapply(HORIZONS, run_lp)) %>%
  mutate(t_stat = coef / se,
         lo90   = coef - 1.645 * se,
         hi90   = coef + 1.645 * se,
         lo95   = coef - 1.96  * se,
         hi95   = coef + 1.96  * se)

cat("\nResults (γ_h per (CPShock × ω^sh_{s, year-1}) interaction):\n")
print(res %>% mutate(across(c(coef, se, t_stat, lo90, hi90, lo95, hi95),
                            ~ round(.x, 4))))

write.csv(res, file.path(OUTPUT_TAB, "phase4_ppi_lp_omega_lagged.csv"),
          row.names = FALSE)
cat(sprintf("\nSaved: %s\n",
            file.path(OUTPUT_TAB, "phase4_ppi_lp_omega_lagged.csv")))

# ---- 6. Plot ----
p <- ggplot(res, aes(x = h, y = coef)) +
  geom_hline(yintercept = 0, colour = "grey60", linewidth = 0.3) +
  geom_ribbon(aes(ymin = lo90, ymax = hi90), fill = "grey75", alpha = 0.6) +
  geom_line(colour = "black", linewidth = 0.6) +
  geom_point(colour = "black", size = 1.8) +
  scale_x_continuous(breaks = HORIZONS) +
  labs(x = "Horizon h (months)",
       y = expression(hat(gamma)[h]),
       title = NULL, subtitle = NULL) +
  theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank(),
        axis.line = element_line(colour = "black"),
        axis.ticks = element_line(colour = "black"))

ggsave(file.path(OUTPUT_FIG, "phase4_ppi_lp_omega_lagged.pdf"), p,
       width = 8, height = 4.2)
ggsave(file.path(OUTPUT_FIG, "phase4_ppi_lp_omega_lagged.png"), p,
       width = 8, height = 4.2, dpi = 200)
cat("Saved: phase4_ppi_lp_omega_lagged.{pdf,png}\n")
