###############################################################################
# network_exposure_regs_3_assemble_panel.R
#
# PURPOSE:
#   Merge the raw frozen-weights exposure panel (from script 2) with firm
#   characteristics (sector, revenue, ETS status), and deflate revenue using
#   the NACE4d PPI (falling back to NACE2d where NACE4d is missing).
#
# DATA:
#   - data/processed/frozen_weights_exposure_raw.RData  (from script 2)
#   - NBB_data/processed/firm_year_belgian_euets.RData
#   - NBB_data/processed/deployment_panel.RData
#   - NBB_data/processed/deflator_nace4d_2005base.RData
#   - NBB_data/processed/training_sample.RData
#
# OUTPUT:
#   - data/processed/frozen_weights_exposure_panel.RData
#     (frozen_exposure_panel, convergence_df)
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)

# ---- Paths ----
REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Load data ----
cat("Loading data...\n")
load(file.path(OUT_DATA, "frozen_weights_exposure_raw.RData"))
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))
load(file.path(PROC_DATA, "deployment_panel.RData"))
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))
load(file.path(PROC_DATA, "training_sample.RData"))

# ===========================================================================
# Assemble panel: merge firm characteristics + deflate revenue
# ===========================================================================
cat("Assembling panel...\n")

# Merge firm characteristics
ets_firms <- firm_year_belgian_euets %>%
  filter(in_sample == 1) %>%
  select(vat, year, nace5d, revenue) %>%
  mutate(is_ets = 1L)

nonets_firms <- deployment_panel %>%
  select(vat, year, nace5d, revenue) %>%
  mutate(is_ets = 0L)

all_firms_panel <- bind_rows(ets_firms, nonets_firms) %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(year >= 2012, year <= 2021,
         !is.na(nace4d), !is.na(revenue), revenue > 0)

frozen_exposure_panel <- frozen_exposure_panel_raw %>%
  left_join(all_firms_panel %>% select(vat, year, nace5d, nace2d, nace4d,
                                        revenue, is_ets),
            by = c("vat", "year"))

# Deflate revenue
frozen_exposure_panel <- frozen_exposure_panel %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi)) %>%
  select(-ppi_2d) %>%
  mutate(real_revenue = revenue / ppi * 100)

# ---- Save panel ----
save(frozen_exposure_panel, convergence_df,
     file = file.path(OUT_DATA, "frozen_weights_exposure_panel.RData"))
cat("\nPanel saved to:",
    file.path(OUT_DATA, "frozen_weights_exposure_panel.RData"), "\n")
cat("Done.\n")
