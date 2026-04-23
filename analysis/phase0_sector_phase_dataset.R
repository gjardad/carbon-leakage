###############################################################################
# phase0_sector_phase_dataset.R
#
# Builds a sector-phase dataset combining:
#   (1) the per-sector pairwise emission decomposition (five channels) over the
#       years that span each EU ETS phase, and
#   (2) the allocation rule in force in that sector during that phase
#       (grandfathered_free, full_auction, CL_list_free, partial_free_declining),
#       hand-coded at NACE 2d from Commission Decisions 2010/2/EU (Phase 3 CL
#       list), 2014/746/EU (Phase 3 CL list update), and 2019/708/EU (Phase 4
#       CL list).
#
# Phase windows used for the decomposition:
#   Phase 1: 2005 -> 2007
#   Phase 2: 2008 -> 2012
#   Phase 3: 2013 -> 2020  (ends 2020 to avoid the NACE 20/24 EUTL
#                           reclassifications that contaminate 2021+)
#   Phase 4: 2021 -> 2022  (only 2 years available; three contaminated VATs
#                           are excluded)
#
# The contaminated VATs are excluded from every year of the sample (same
# as the aggregate pairwise decomposition).
#
# Output:
#   output/tables/phase0_sector_phase_dataset.csv
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(stringr)

REPO_DIR <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile, winslash = "/")),
                     error = function(e) normalizePath(getwd(), winslash = "/"))
while (!file.exists(file.path(REPO_DIR, "paths.R"))) REPO_DIR <- dirname(REPO_DIR)
source(file.path(REPO_DIR, "paths.R"))

# ---- Config ----
phase_windows <- tribble(
  ~phase,      ~t0,    ~t1,    ~paying_start,     ~learning_date,      ~learning_event,
  "Phase 1",   2005L,  2007L,  "2005-01-01",      "2003-10-13",        "Directive 2003/87/EC (pre-Kanzig sample)",
  "Phase 2",   2008L,  2012L,  "2008-01-01",      "2005-06-20",        "First Kanzig surprise, Phase 1 launch priced in",
  "Phase 3",   2013L,  2020L,  "2013-01-01",      "2009-04-23",        "Directive 2009/29/EC adopted (Phase 3 auctioning framework)",
  "Phase 4",   2021L,  2022L,  "2021-01-01",      "2018-03-14",        "Directive 2018/410 adopted (Phase 4 cap trajectory)"
)

min_firms_both <- 3

contaminated_vats <- c(
  "68A2F4B84714EC1829E0AC28D29F204FDEBFF70F71F2A22FDE65461FF3ADDDFF",
  "F8F1FAA7804D5A5B8495B44A8586C93F19689545D2D96B5CBBB19221519EC076",
  "1061796C42F184760E3BAF45DC443875C42284348C2B209B70F02ED964EDAC7E"
)

# ---- NACE 2d allocation rule per phase (hand-coded) ----
# Based on EU Commission Decisions defining the carbon leakage (CL) list:
#  - 2010/2/EU (Dec 2009): Phase 3 CL list
#  - 2014/746/EU (Oct 2014): Phase 3 CL list, 2015-2019
#  - 2019/708/EU (May 2019): Phase 4 CL list, 2021-2030
# NACE 2d is coarser than the CL list (which is at NACE 4d); assignments below
# reflect whether the dominant (emissions-weighted) sub-sectors are on the list.
allocation_rule <- tribble(
  ~nace2d, ~sector_name,                        ~rule_phase1,            ~rule_phase2,            ~rule_phase3,               ~rule_phase4,
  "10",    "Food",                              "grandfathered_free",    "grandfathered_free",    "partial_free_declining",   "partial_free_declining",
  "11",    "Beverages",                         "grandfathered_free",    "grandfathered_free",    "partial_free_declining",   "partial_free_declining",
  "13",    "Textiles",                          "grandfathered_free",    "grandfathered_free",    "partial_free_declining",   "partial_free_declining",
  "17",    "Paper",                             "grandfathered_free",    "grandfathered_free",    "CL_list_free",             "partial_free_declining",
  "19",    "Petroleum refining",                "grandfathered_free",    "grandfathered_free",    "CL_list_free",             "CL_list_free",
  "20",    "Chemicals",                         "grandfathered_free",    "grandfathered_free",    "CL_list_free",             "CL_list_free",
  "21",    "Pharmaceuticals",                   "grandfathered_free",    "grandfathered_free",    "partial_free_declining",   "partial_free_declining",
  "22",    "Rubber, plastics",                  "grandfathered_free",    "grandfathered_free",    "partial_free_declining",   "partial_free_declining",
  "23",    "Cement, glass, ceramics",           "grandfathered_free",    "grandfathered_free",    "CL_list_free",             "CL_list_free",
  "24",    "Basic metals",                      "grandfathered_free",    "grandfathered_free",    "CL_list_free",             "CL_list_free",
  "25",    "Fabricated metals",                 "grandfathered_free",    "grandfathered_free",    "partial_free_declining",   "partial_free_declining",
  "29",    "Motor vehicles",                    "grandfathered_free",    "grandfathered_free",    "partial_free_declining",   "partial_free_declining",
  "35",    "Electricity",                       "grandfathered_free",    "grandfathered_free",    "full_auction",             "full_auction"
)

allocation_long <- allocation_rule %>%
  pivot_longer(starts_with("rule_phase"),
               names_to = "phase", values_to = "allocation_rule") %>%
  mutate(phase = recode(phase,
                        "rule_phase1" = "Phase 1",
                        "rule_phase2" = "Phase 2",
                        "rule_phase3" = "Phase 3",
                        "rule_phase4" = "Phase 4"))

# ---- Load + deflate firm panel (same as phase0_pairwise_decomposition_by_sector.R) ----
load(file.path(PROC_DATA, "deflator_nace4d_2005base.RData"))
load(file.path(PROC_DATA, "firm_year_belgian_euets.RData"))

df <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(!is.na(nace2d), !is.na(emissions), !is.na(revenue),
         emissions > 0, revenue > 0,
         !(vat %in% contaminated_vats)) %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi),
            by = c("nace2d", "year")) %>%
  mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100)

# ---- Per-sector decomposition function (five channels) ----
sector_pair_decomp <- function(df_s, t0, t1, nace2d_target) {
  d0 <- df_s %>% filter(year == t0) %>%
    select(vat, e_0 = emissions, q_0 = real_revenue)
  d1 <- df_s %>% filter(year == t1) %>%
    select(vat, e_1 = emissions, q_1 = real_revenue)

  if (nrow(d0) < min_firms_both || nrow(d1) < min_firms_both) return(NULL)

  survivors <- inner_join(d0, d1, by = "vat")
  exiters   <- anti_join(d0, d1, by = "vat")
  entrants  <- anti_join(d1, d0, by = "vat")

  E_t0 <- sum(d0$e_0); E_t1 <- sum(d1$e_1)
  E_s_0 <- sum(survivors$e_0); E_s_1 <- sum(survivors$e_1)
  Y_s_0 <- sum(survivors$q_0); Y_s_1 <- sum(survivors$q_1)
  E_entry <- sum(entrants$e_1); E_exit <- sum(exiters$e_0)

  if (nrow(survivors) == 0 || Y_s_0 == 0 || Y_s_1 == 0) return(NULL)

  s <- survivors %>%
    mutate(theta_0 = q_0 / Y_s_0, theta_1 = q_1 / Y_s_1,
           z_0 = e_0 / q_0,       z_1 = e_1 / q_1)

  E_scale       <- Y_s_1 * sum(s$theta_0 * s$z_0)
  E_scale_reall <- Y_s_1 * sum(s$theta_1 * s$z_0)
  E_actual      <- Y_s_1 * sum(s$theta_1 * s$z_1)

  scale_eff <- E_scale       - E_s_0
  reall_eff <- E_scale_reall - E_scale
  tech_eff  <- E_actual      - E_scale_reall
  entry_eff <- E_entry
  exit_eff  <- -E_exit

  total <- E_t1 - E_t0

  tibble(
    nace2d = nace2d_target,
    t0 = t0, t1 = t1,
    n_surv = nrow(survivors),
    n_ent  = nrow(entrants),
    n_exit = nrow(exiters),
    E_t0_kt = E_t0 / 1000,
    E_t1_kt = E_t1 / 1000,
    total_pp = total / E_t0 * 100,
    scale_pp = scale_eff / E_t0 * 100,
    within_pp = reall_eff / E_t0 * 100,
    tech_pp = tech_eff / E_t0 * 100,
    entry_pp = entry_eff / E_t0 * 100,
    exit_pp = exit_eff / E_t0 * 100
  )
}

# ---- Run for each sector x phase ----
sectors <- df %>% distinct(nace2d) %>% pull(nace2d)

results <- bind_rows(lapply(seq_len(nrow(phase_windows)), function(i) {
  pw <- phase_windows[i, ]
  bind_rows(lapply(sectors, function(s) {
    tryCatch(sector_pair_decomp(df %>% filter(nace2d == s), pw$t0, pw$t1, s),
             error = function(e) NULL)
  })) %>%
    mutate(phase = pw$phase,
           paying_start = pw$paying_start,
           learning_date = pw$learning_date,
           learning_event = pw$learning_event)
}))

# ---- Merge allocation rule ----
results <- results %>%
  left_join(allocation_long %>% select(nace2d, phase, sector_name, allocation_rule),
            by = c("nace2d", "phase")) %>%
  mutate(sector_name = coalesce(sector_name, "[unmapped]"),
         allocation_rule = coalesce(allocation_rule, "unknown")) %>%
  select(nace2d, sector_name, phase, t0, t1,
         paying_start, learning_date, learning_event, allocation_rule,
         n_surv, n_ent, n_exit, E_t0_kt, E_t1_kt,
         total_pp, scale_pp, within_pp, tech_pp, entry_pp, exit_pp) %>%
  arrange(phase, desc(E_t0_kt))

# ---- Print ----
cat("\n=== Sector-phase dataset ===\n")
cat("pp columns sum to total_pp. Denominator = sector's own emissions in t0.\n\n")

for (ph in c("Phase 1", "Phase 2", "Phase 3", "Phase 4")) {
  cat("--- ", ph, " ---\n", sep = "")
  tbl <- results %>% filter(phase == ph) %>%
    mutate(across(ends_with("_pp"), ~ round(., 1)),
           E_t0_kt = round(E_t0_kt, 0),
           E_t1_kt = round(E_t1_kt, 0))
  print(as.data.frame(tbl %>%
    select(nace2d, sector_name, allocation_rule, n_surv, n_ent, n_exit,
           E_t0_kt, total_pp, scale_pp, within_pp, tech_pp, entry_pp, exit_pp)))
  cat("\n")
}

# ---- Save ----
out_path <- file.path(OUTPUT_TAB, "phase0_sector_phase_dataset.csv")
write.csv(results %>%
  mutate(across(c(total_pp, scale_pp, within_pp, tech_pp, entry_pp, exit_pp),
                ~ round(., 2)),
         across(c(E_t0_kt, E_t1_kt), ~ round(., 1))),
  out_path, row.names = FALSE)
cat("Saved:", out_path, "\n")
