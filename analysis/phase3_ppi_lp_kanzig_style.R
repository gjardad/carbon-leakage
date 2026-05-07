###############################################################################
# phase3_ppi_lp_kanzig_style.R
#
# PURPOSE:
#   Generate a Känzig-style impulse response figure for the headline NACE 4d
#   PPI panel-LP, to replace the HICP figure in §4 (Strategy 1) of the paper.
#
#   Spec: same as phase3_ppi_passthrough_monthly.R (headline branch),
#         but estimated at every horizon h = 0, 1, ..., 36 so the IRF reads
#         as a smooth curve, and reporting both 68% and 90% confidence bands.
#
#       log(PPI_{s,m+h}) - log(PPI_{s,m-1})
#         = γ_h * (CPShock_m × intensity_base_s) + α_s + δ_m + ε_{s,m,h}
#
#       Sample: 2005m1 to 2019m12 (CPShock coverage), all NACE 4d.
#       RHS: cpshock_shk × intensity_base (primary spec, Känzig App. C.6).
#       Cluster on nace4d.
#
# INPUT:
#   ${PROC_DATA}/deflator_nace4d_2005base_monthly.RData
#   ${RAW_DATA}/carbonPolicyShocks.xlsx (Monthly sheet)
#   ${OUT_DATA}/phase3_sector_exposure.RData (intensity_base via 2013-16 mean)
#
# OUTPUT:
#   ${OUTPUT_FIG}/phase3_ppi_lp_kanzig_style.pdf
#   ${OUTPUT_FIG}/phase3_ppi_lp_kanzig_style.png
#   ${OUTPUT_TAB}/phase3_ppi_lp_kanzig_style.csv  (per-horizon coefficients)
###############################################################################

rm(list = ls())

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readxl)
  library(lubridate)
  library(fixest)
  library(ggplot2)
})

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

###############################################################################
# 1. Load monthly PPI + CPShock + sector intensity (same as headline script)
###############################################################################
load(file.path(PROC_DATA, "deflator_nace4d_2005base_monthly.RData"))

xlsx_path <- file.path(RAW_DATA, "carbonPolicyShocks.xlsx")
cps_raw <- read_excel(xlsx_path, sheet = "Monthly")
cps <- cps_raw %>%
  mutate(year  = as.integer(substr(Date, 1, 4)),
         month = as.integer(substr(Date, 6, 7)),
         date  = as.Date(sprintf("%d-%02d-01", year, month))) %>%
  transmute(date, year, month,
            cpshock_shock = Shock)

load(file.path(OUT_DATA, "phase3_sector_exposure.RData"))
intensity_base_df <- sector_exposure %>%
  filter(year %in% 2013:2016) %>%
  group_by(nace4d) %>%
  summarise(intensity_base = mean(exposure_alt_total, na.rm = TRUE),
            .groups = "drop")

###############################################################################
# 2. Build panel
###############################################################################
panel_m <- deflator_monthly %>%
  filter(date >= as.Date("2005-01-01"),
         date <= as.Date("2019-12-01")) %>%
  left_join(cps %>% select(date, cpshock_shock), by = "date") %>%
  left_join(intensity_base_df, by = "nace4d") %>%
  mutate(
    intensity_base    = coalesce(intensity_base, 0),
    log_ppi           = log(ppi),
    cpshock_shk_x_int = cpshock_shock * intensity_base,
    year_month        = format(date, "%Y-%m")
  ) %>%
  arrange(nace4d, date)

cat(sprintf("Panel: %d obs, %d NACE 4d, %s to %s\n",
            nrow(panel_m), n_distinct(panel_m$nace4d),
            format(min(panel_m$date)), format(max(panel_m$date))))

###############################################################################
# 3. Build cumulative LHS for every horizon h = 0, ..., 36
###############################################################################
H_MAX <- 36L
horizons <- 0:H_MAX

for (h in horizons) {
  col_name <- paste0("dlog_ppi_h", h)
  panel_m[[col_name]] <- ave(panel_m$log_ppi, panel_m$nace4d,
                             FUN = function(x) {
                               n <- length(x)
                               out <- rep(NA_real_, n)
                               for (i in seq_len(n)) {
                                 if ((i + h) <= n && (i - 1) >= 1) {
                                   out[i] <- x[i + h] - x[i - 1]
                                 }
                               }
                               out
                             })
}

###############################################################################
# 4. Run LP at every horizon
###############################################################################
run_lp <- function(h) {
  lhs_col <- paste0("dlog_ppi_h", h)
  dat <- panel_m %>% filter(!is.na(.data[[lhs_col]]))
  frm <- as.formula(sprintf("%s ~ cpshock_shk_x_int | nace4d + year_month",
                            lhs_col))
  m <- feols(frm, data = dat, cluster = ~nace4d)
  ct <- coeftable(m)
  r <- ct["cpshock_shk_x_int", ]
  data.frame(h = h, coef = r[1], se = r[2], n = m$nobs)
}

cat("\nRunning LP at horizons 0..", H_MAX, "...\n", sep = "")
lp <- do.call(rbind, lapply(horizons, run_lp))
lp <- lp %>%
  mutate(lo68 = coef - 1.000 * se,
         hi68 = coef + 1.000 * se,
         lo90 = coef - 1.645 * se,
         hi90 = coef + 1.645 * se)

cat("\n=== IRF coefficients (γ_h on CPShock × intensity) ===\n")
print(lp, digits = 3)

write.csv(lp, file.path(OUTPUT_TAB, "phase3_ppi_lp_kanzig_style.csv"),
          row.names = FALSE)

###############################################################################
# 5. Plot Känzig-style IRF
###############################################################################
p <- ggplot(lp, aes(x = h, y = coef)) +
  geom_hline(yintercept = 0, colour = "black", linewidth = 0.3) +
  geom_ribbon(aes(ymin = lo90, ymax = hi90), fill = "steelblue", alpha = 0.20) +
  geom_ribbon(aes(ymin = lo68, ymax = hi68), fill = "steelblue", alpha = 0.40) +
  geom_line(colour = "black", linewidth = 0.7) +
  scale_x_continuous(breaks = seq(0, H_MAX, by = 6),
                     expand = c(0.01, 0.01)) +
  labs(x = "Horizon (months)",
       y = expression(gamma[h])) +
  theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major = element_line(colour = "grey92", linewidth = 0.3),
        axis.line = element_line(colour = "black"),
        plot.title = element_text(face = "bold", size = 12))

print(p)

ggsave(file.path(OUTPUT_FIG, "phase3_ppi_lp_kanzig_style.pdf"), p,
       width = 6, height = 3.5)
ggsave(file.path(OUTPUT_FIG, "phase3_ppi_lp_kanzig_style.png"), p,
       width = 6, height = 3.5, dpi = 300)

cat("\nSaved:\n  ",
    file.path(OUTPUT_FIG, "phase3_ppi_lp_kanzig_style.pdf"), "\n  ",
    file.path(OUTPUT_FIG, "phase3_ppi_lp_kanzig_style.png"), "\n  ",
    file.path(OUTPUT_TAB, "phase3_ppi_lp_kanzig_style.csv"), "\n")
