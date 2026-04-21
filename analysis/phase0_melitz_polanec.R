###############################################################################
# phase0_melitz_polanec.R
#
# PURPOSE:
#   Decompose changes in aggregate emission intensity using the dynamic
#   Olley-Pakes decomposition from Melitz & Polanec (2015, RAND).
#
#   This cleanly handles entry and exit by splitting firms into:
#     S = survivors (present in both t1 and t2)
#     N = entrants  (present only in t2)
#     X = exiters   (present only in t1)
#
#   The Olley-Pakes cross-section decomposition for any group G:
#     Z_G = z_bar_G + cov_G
#   where Z_G is the share-weighted aggregate emission intensity,
#   z_bar_G is the unweighted mean, and cov_G = Σ_i (θ_i - θ_bar)(z_i - z_bar)
#   captures whether dirtier or cleaner firms have larger market shares.
#
#   The Melitz-Polanec dynamic decomposition between periods t1 and t2:
#
#     ΔZ = [Δz_bar_S + Δcov_S]
#           + θ_N,t2 * (Z_N,t2 - Z_S,t2)
#           + θ_X,t1 * (Z_S,t1 - Z_X,t1)
#
#   where:
#     Δz_bar_S = change in unweighted mean among survivors (within-firm)
#     Δcov_S   = change in OP covariance among survivors (reallocation among survivors)
#     θ_N,t2   = aggregate output share of entrants in t2
#     Z_N,t2   = share-weighted emission intensity of entrants
#     Z_S,t2   = share-weighted emission intensity of survivors in t2
#     θ_X,t1   = aggregate output share of exiters in t1
#     Z_X,t1   = share-weighted emission intensity of exiters
#     Z_S,t1   = share-weighted emission intensity of survivors in t1
#
#   Entry contributes negatively (reduces aggregate intensity) if entrants
#   are cleaner than survivors. Exit contributes negatively if exiters
#   are dirtier than survivors.
#
# IMPORTANT: In our context z_i is emission intensity (emissions/real revenue).
#   LOWER z is better (cleaner). So negative ΔZ = good (aggregate getting cleaner).
#
# DATA:
#   - NBB_data/processed/deflator_nace4d_2005base.RData
#   - NBB_data/processed/firm_year_belgian_euets.RData
#
# OUTPUT:
#   - output/figures/phase0_mp_decomp_vA.pdf
#   - output/figures/phase0_mp_by_sector_vA.pdf
#   - output/tables/phase0_mp_decomp_vA.csv
#   - output/tables/phase0_mp_by_sector_vA.csv
###############################################################################

rm(list = ls())

library(dplyr)
library(tidyr)
library(ggplot2)
library(stringr)

# ---- Paths ----
nbb_data     <- "c:/Users/jota_/Documents/NBB_data"
project_root <- "c:/Users/jota_/Documents/carbon_policy_networks"

proc_data  <- file.path(nbb_data, "processed")
output_fig <- file.path(project_root, "output", "figures")
output_tab <- file.path(project_root, "output", "tables")
dir.create(output_fig, showWarnings = FALSE, recursive = TRUE)
dir.create(output_tab, showWarnings = FALSE, recursive = TRUE)

# ---- Config ----
emissions_version <- "ets_only"
base_year <- 2005
end_year  <- 2021  # 2022 data unreliable
version_label <- switch(emissions_version, ets_only = "A", imputed = "B", bounds = "C")

###############################################################################
# SECTION 1: LOAD AND PREPARE DATA
###############################################################################

load(file.path(proc_data, "deflator_nace4d_2005base.RData"))
load(file.path(proc_data, "firm_year_belgian_euets.RData"))

df <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(year >= base_year, year <= end_year,
         !is.na(nace2d), !is.na(emissions), !is.na(revenue),
         emissions > 0, revenue > 0)

# Merge deflator (4d first, fallback to 2d)
df <- df %>%
  left_join(deflator %>% select(nace4d, year, ppi, ppi_source), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi), by = c("nace2d", "year")) %>%
  mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi)) %>%
  select(-ppi_2d, -ppi_source) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100,
         z = emissions / real_revenue)  # emission intensity

###############################################################################
# SECTION 2: MELITZ-POLANEC DECOMPOSITION FUNCTIONS
###############################################################################

# Olley-Pakes cross-section decomposition for a group of firms
# Returns: list(Z_agg, z_bar, cov_op, n)
op_decomp <- function(theta, z) {
  # theta = within-group output shares (sum to 1)
  # z     = emission intensities
  n <- length(z)
  z_bar <- mean(z)
  theta_bar <- 1 / n
  cov_op <- sum((theta - theta_bar) * (z - z_bar))
  Z_agg <- sum(theta * z)  # = z_bar + cov_op
  list(Z_agg = Z_agg, z_bar = z_bar, cov_op = cov_op, n = n)
}

# Melitz-Polanec dynamic decomposition between t1 and t2
# df_t1, df_t2: data frames with columns (vat, real_revenue, z)
# Returns a named list of decomposition components
mp_decomp <- function(df_t1, df_t2) {

  # Identify survivors, entrants, exiters
  vat_t1 <- unique(df_t1$vat)
  vat_t2 <- unique(df_t2$vat)
  vat_S  <- intersect(vat_t1, vat_t2)
  vat_N  <- setdiff(vat_t2, vat_t1)
  vat_X  <- setdiff(vat_t1, vat_t2)

  # Total output in each period
  Y_t1 <- sum(df_t1$real_revenue)
  Y_t2 <- sum(df_t2$real_revenue)

  # Compute output shares relative to TOTAL economy (not group)
  df_t1 <- df_t1 %>% mutate(theta = real_revenue / Y_t1)
  df_t2 <- df_t2 %>% mutate(theta = real_revenue / Y_t2)

  # Aggregate share-weighted emission intensity in t1 and t2
  Z_t1 <- sum(df_t1$theta * df_t1$z)
  Z_t2 <- sum(df_t2$theta * df_t2$z)
  delta_Z <- Z_t2 - Z_t1

  # --- Survivors ---
  S_t1 <- df_t1 %>% filter(vat %in% vat_S)
  S_t2 <- df_t2 %>% filter(vat %in% vat_S)

  # Survivor shares (relative to total economy, not just survivors)
  theta_S_t1 <- sum(S_t1$theta)  # survivors' share of economy in t1
  theta_S_t2 <- sum(S_t2$theta)  # survivors' share of economy in t2

  # For OP decomposition within survivors, need within-group shares
  S_t1 <- S_t1 %>% mutate(theta_within = real_revenue / sum(real_revenue))
  S_t2 <- S_t2 %>% mutate(theta_within = real_revenue / sum(real_revenue))

  op_S_t1 <- op_decomp(S_t1$theta_within, S_t1$z)
  op_S_t2 <- op_decomp(S_t2$theta_within, S_t2$z)

  # Survivor contribution: within-firm + reallocation
  delta_z_bar_S <- op_S_t2$z_bar - op_S_t1$z_bar      # within-firm
  delta_cov_S   <- op_S_t2$cov_op - op_S_t1$cov_op    # reallocation among survivors

  # Z_S in each period (share-weighted among survivors)
  Z_S_t1 <- op_S_t1$Z_agg
  Z_S_t2 <- op_S_t2$Z_agg

  # --- Entrants ---
  N_t2 <- df_t2 %>% filter(vat %in% vat_N)
  theta_N_t2 <- sum(N_t2$theta)  # entrants' share of economy in t2

  if (nrow(N_t2) > 0) {
    N_t2 <- N_t2 %>% mutate(theta_within = real_revenue / sum(real_revenue))
    Z_N_t2 <- sum(N_t2$theta_within * N_t2$z)
    entry_contrib <- theta_N_t2 * (Z_N_t2 - Z_S_t2)
  } else {
    Z_N_t2 <- NA
    entry_contrib <- 0
  }

  # --- Exiters ---
  X_t1 <- df_t1 %>% filter(vat %in% vat_X)
  theta_X_t1 <- sum(X_t1$theta)  # exiters' share of economy in t1

  if (nrow(X_t1) > 0) {
    X_t1 <- X_t1 %>% mutate(theta_within = real_revenue / sum(real_revenue))
    Z_X_t1 <- sum(X_t1$theta_within * X_t1$z)
    exit_contrib <- theta_X_t1 * (Z_S_t1 - Z_X_t1)
  } else {
    Z_X_t1 <- NA
    exit_contrib <- 0
  }

  # --- Full decomposition ---
  # Note: the survivor terms need to be scaled by survivors' share
  # Full formula: ΔZ = θ_S,t2 * ΔZ_S + entry + exit
  #   where ΔZ_S = Δz_bar_S + Δcov_S
  # But we also need to account for the change in survivors' aggregate share
  # The exact Melitz-Polanec formula is:
  #   ΔZ = [Δz_bar_S + Δcov_S] * (some weight) + entry + exit
  # More precisely, using survivors in t2 as reference:

  survivor_within  <- delta_z_bar_S
  survivor_realloc <- delta_cov_S
  survivor_total   <- Z_S_t2 - Z_S_t1  # = delta_z_bar_S + delta_cov_S

  tibble(
    n_t1 = length(vat_t1),
    n_t2 = length(vat_t2),
    n_survivors = length(vat_S),
    n_entrants  = length(vat_N),
    n_exiters   = length(vat_X),
    Z_t1 = Z_t1,
    Z_t2 = Z_t2,
    delta_Z = delta_Z,
    # Components (in same units as Z, i.e., emission intensity)
    within_firm       = survivor_within,
    realloc_survivors = survivor_realloc,
    entry             = entry_contrib,
    exit              = exit_contrib,
    # Shares
    theta_S_t1 = theta_S_t1,
    theta_S_t2 = theta_S_t2,
    theta_N_t2 = theta_N_t2,
    theta_X_t1 = theta_X_t1
  )
}

###############################################################################
# SECTION 3: AGGREGATE DECOMPOSITION (whole economy)
###############################################################################

cat("=== Aggregate Melitz-Polanec decomposition (rolling 5-year windows) ===\n\n")

# Rolling 5-year windows: 2005→2010, 2006→2011, ..., 2016→2021
window <- 5
agg_results <- list()

for (t1 in base_year:(end_year - window)) {
  t2 <- t1 + window
  df_t1 <- df %>% filter(year == t1)
  df_t2 <- df %>% filter(year == t2)

  if (nrow(df_t1) < 5 || nrow(df_t2) < 5) next

  res <- mp_decomp(df_t1, df_t2) %>%
    mutate(t1 = t1, t2 = t2)

  agg_results[[paste(t1, t2)]] <- res
}

agg <- bind_rows(agg_results)

# Express components as % of base-year aggregate intensity
agg_print <- agg %>%
  mutate(
    pct_within     = within_firm / Z_t1 * 100,
    pct_realloc    = realloc_survivors / Z_t1 * 100,
    pct_entry      = entry / Z_t1 * 100,
    pct_exit       = exit / Z_t1 * 100,
    pct_total      = delta_Z / Z_t1 * 100,
    pct_check      = pct_within + pct_realloc + pct_entry + pct_exit
  )

cat("Components as % of base-year aggregate emission intensity:\n")
cat("within     = within-firm change (survivors getting cleaner/dirtier)\n")
cat("realloc    = reallocation among survivors (cleaner survivors gaining share)\n")
cat("entry      = contribution of entrants (cleaner or dirtier than survivors?)\n")
cat("exit       = contribution of exiters (were they cleaner or dirtier?)\n\n")

print(as.data.frame(agg_print %>%
  select(t1, t2, n_survivors, n_entrants, n_exiters,
         pct_total, pct_within, pct_realloc, pct_entry, pct_exit) %>%
  mutate(across(starts_with("pct"), ~ round(., 1)))))

###############################################################################
# SECTION 4: BY-SECTOR DECOMPOSITION
###############################################################################

cat("\n=== Sector-level Melitz-Polanec decomposition (rolling 5-year, top sectors) ===\n\n")

# Get emission shares by sector in base year
sec_em <- df %>%
  filter(year == base_year) %>%
  group_by(nace2d) %>%
  summarise(em_base = sum(emissions), .groups = "drop") %>%
  mutate(em_share = em_base / sum(em_base) * 100)

top_sectors <- sec_em %>% filter(em_share > 1) %>% pull(nace2d)
sectors <- sort(unique(df$nace2d))
sector_results <- list()

for (s in sectors) {
  for (t1 in base_year:(end_year - window)) {
    t2 <- t1 + window
    df_t1 <- df %>% filter(year == t1, nace2d == s)
    df_t2 <- df %>% filter(year == t2, nace2d == s)

    if (nrow(df_t1) < 2 || nrow(df_t2) < 2) next

    res <- mp_decomp(df_t1, df_t2) %>%
      mutate(nace2d = s, t1 = t1, t2 = t2)

    sector_results[[paste(s, t1, t2)]] <- res
  }
}

sec <- bind_rows(sector_results) %>%
  left_join(sec_em, by = "nace2d")

sec <- sec %>%
  mutate(
    pct_total   = delta_Z / Z_t1 * 100,
    pct_within  = within_firm / Z_t1 * 100,
    pct_realloc = realloc_survivors / Z_t1 * 100,
    pct_entry   = entry / Z_t1 * 100,
    pct_exit    = exit / Z_t1 * 100
  )

# Print top sectors, most recent window
sec_print <- sec %>%
  filter(t1 == max(t1)) %>%
  arrange(desc(em_share)) %>%
  select(nace2d, em_share, t1, t2, n_survivors, n_entrants, n_exiters,
         pct_total, pct_within, pct_realloc, pct_entry, pct_exit) %>%
  mutate(across(starts_with("pct") | matches("em_share"), ~ round(., 1)))

cat("Most recent window (", max(sec$t1), "->", max(sec$t2), "):\n")
print(as.data.frame(sec_print))

###############################################################################
# SECTION 5: FIGURES
###############################################################################

# ---- Figure: Aggregate decomposition — rolling 5-year windows ----
plot_agg <- agg_print %>%
  mutate(window_label = paste0(t1, "-", t2)) %>%
  select(window_label, t1, pct_within, pct_realloc, pct_entry, pct_exit) %>%
  pivot_longer(cols = starts_with("pct"), names_to = "component", values_to = "pct") %>%
  mutate(
    component = factor(component,
      levels = c("pct_within", "pct_realloc", "pct_entry", "pct_exit"),
      labels = c("Within-firm (survivors)", "Reallocation (survivors)",
                 "Entry", "Exit"))
  )

p_agg <- ggplot(plot_agg, aes(x = t1, y = pct, fill = component)) +
  geom_bar(stat = "identity", position = "stack", width = 0.7) +
  geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
  geom_vline(xintercept = c(2012.5, 2016.5), linetype = "dashed",
             color = "grey70", linewidth = 0.4) +
  scale_fill_manual(values = c(
    "Within-firm (survivors)" = "#D6604D",
    "Reallocation (survivors)" = "#4393C3",
    "Entry" = "#92C5DE",
    "Exit" = "#F4A582"
  )) +
  labs(
    title = paste0("Melitz-Polanec decomposition (rolling ", window, "-year windows)"),
    subtitle = "Version A: ETS firms only | % change in aggregate emission intensity per window",
    x = "Start year of window", y = "% change in emission intensity",
    fill = NULL
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    legend.position = "bottom",
    axis.line = element_line(color = "black")
  ) +
  scale_x_continuous(breaks = seq(base_year, end_year - window, by = 2))

ggsave(file.path(output_fig, paste0("phase0_mp_decomp_v", version_label, ".pdf")),
       p_agg, width = 10, height = 6)

# ---- Figure: Sector-level decomposition — rolling windows for top sectors ----
plot_sec <- sec %>%
  filter(nace2d %in% top_sectors) %>%
  select(nace2d, t1, pct_within, pct_realloc, pct_entry, pct_exit) %>%
  pivot_longer(cols = starts_with("pct"), names_to = "component", values_to = "pct") %>%
  mutate(
    component = factor(component,
      levels = c("pct_within", "pct_realloc", "pct_entry", "pct_exit"),
      labels = c("Within-firm", "Reallocation", "Entry", "Exit"))
  )

p_sec <- ggplot(plot_sec, aes(x = t1, y = pct, fill = component)) +
  geom_bar(stat = "identity", position = "stack", width = 0.7) +
  geom_hline(yintercept = 0, color = "black", linewidth = 0.5) +
  facet_wrap(~ nace2d, scales = "free_y", ncol = 3) +
  scale_fill_manual(values = c(
    "Within-firm" = "#D6604D",
    "Reallocation" = "#4393C3",
    "Entry" = "#92C5DE",
    "Exit" = "#F4A582"
  )) +
  labs(
    title = paste0("Melitz-Polanec by sector (rolling ", window, "-year windows)"),
    subtitle = "Version A: ETS firms only | Sectors with >1% of base-year emissions",
    x = "Start year of window", y = "% change in sector emission intensity",
    fill = NULL
  ) +
  theme_minimal() +
  theme(
    panel.grid.minor = element_blank(),
    legend.position = "bottom",
    axis.line = element_line(color = "black"),
    strip.text = element_text(face = "bold")
  ) +
  scale_x_continuous(breaks = seq(base_year, end_year - window, by = 4))

ggsave(file.path(output_fig, paste0("phase0_mp_by_sector_v", version_label, ".pdf")),
       p_sec, width = 12, height = 8)

cat("\nFigures saved.\n")

###############################################################################
# SECTION 6: SAVE TABLES
###############################################################################

write.csv(agg_print %>%
  select(t1, t2, n_survivors, n_entrants, n_exiters,
         pct_total, pct_within, pct_realloc, pct_entry, pct_exit) %>%
  mutate(across(starts_with("pct"), ~ round(., 2))),
  file.path(output_tab, paste0("phase0_mp_decomp_v", version_label, ".csv")),
  row.names = FALSE)

write.csv(sec %>%
  filter(nace2d %in% top_sectors) %>%
  select(nace2d, em_share, t1, t2, n_survivors, n_entrants, n_exiters,
         pct_total, pct_within, pct_realloc, pct_entry, pct_exit) %>%
  mutate(across(starts_with("pct") | matches("em_share"), ~ round(., 2))),
  file.path(output_tab, paste0("phase0_mp_by_sector_v", version_label, ".csv")),
  row.names = FALSE)

cat("Tables saved.\n")
