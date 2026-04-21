###############################################################################
# phase1a_output_share_by_exposure.R
#
# PURPOSE:
#   Eyeball test: do high carbon-exposure ETS firms lose output share
#   after the 2017 MSR reform?
#
#   Three versions:
#     1. Binary split within NACE 2-digit (original)
#     2. Binary split within NACE 4-digit
#     3. Continuous treatment (binscatter-style)
#
# DATA:
#   - NBB_data/processed/firm_year_belgian_euets.RData
#   - NBB_data/processed/deflator_nace4d_2005base.RData
###############################################################################

rm(list = ls())

library(dplyr)
library(stringr)
library(tidyr)
library(ggplot2)

# ---- Paths ----
nbb_data     <- "c:/Users/jota_/Documents/NBB_data"
project_root <- "c:/Users/jota_/Documents/carbon_policy_networks"
proc_data    <- file.path(nbb_data, "processed")
output_fig   <- file.path(project_root, "output", "figures")

base_year <- 2005
end_year  <- 2021

# ---- Load and prepare data ----
load(file.path(proc_data, "deflator_nace4d_2005base.RData"))
load(file.path(proc_data, "firm_year_belgian_euets.RData"))

df <- firm_year_belgian_euets %>%
  mutate(nace2d = str_sub(nace5d, 1, 2),
         nace4d = str_sub(nace5d, 1, 4)) %>%
  filter(year >= base_year, year <= end_year,
         !is.na(nace2d), !is.na(nace4d),
         !is.na(revenue), revenue > 0) %>%
  left_join(deflator %>% select(nace4d, year, ppi), by = c("nace4d", "year")) %>%
  left_join(deflator_2d_only %>% select(nace2d, year, ppi_2d = ppi), by = c("nace2d", "year")) %>%
  mutate(ppi = ifelse(is.na(ppi), ppi_2d, ppi)) %>%
  select(-ppi_2d) %>%
  filter(!is.na(ppi)) %>%
  mutate(real_revenue = revenue / ppi * 100)

# ---- Pre-MSR allowance shortage (2013-2016) ----
# One observation per firm (not per vat-year)
pre_msr <- df %>%
  filter(year >= 2013, year <= 2016) %>%
  group_by(vat) %>%
  summarise(
    nace2d = first(nace2d),
    nace4d = first(nace4d),
    avg_emissions = mean(emissions, na.rm = TRUE),
    avg_free = mean(allocated_free, na.rm = TRUE),
    avg_revenue = mean(real_revenue, na.rm = TRUE),
    n_years = n(),
    .groups = "drop"
  ) %>%
  # Deduplicate: keep one row per vat
  distinct(vat, .keep_all = TRUE) %>%
  mutate(
    shortage = pmax(avg_emissions - avg_free, 0),
    shortage_intensity = shortage / avg_revenue
  ) %>%
  filter(!is.na(shortage_intensity), avg_revenue > 0)

cat("Firms with pre-MSR data:", nrow(pre_msr), "\n")

###############################################################################
# VERSION 1: Binary split within NACE 2-digit
###############################################################################

pre_msr_2d <- pre_msr %>%
  group_by(nace2d) %>%
  mutate(high_exp_2d = as.integer(shortage_intensity > median(shortage_intensity))) %>%
  ungroup()

df_v1 <- df %>%
  inner_join(pre_msr_2d %>% select(vat, high_exp_2d), by = "vat",
             relationship = "many-to-one")

# Aggregate output share by group
share_v1 <- df_v1 %>%
  group_by(year, high_exp_2d) %>%
  summarise(group_rev = sum(real_revenue), .groups = "drop") %>%
  group_by(year) %>%
  mutate(group_share = group_rev / sum(group_rev)) %>%
  ungroup() %>%
  mutate(group = ifelse(high_exp_2d == 1, "High exposure", "Low exposure"))

# Index to 2016
norm_v1 <- share_v1 %>% filter(year == 2016) %>% select(high_exp_2d, norm = group_share)
share_v1 <- share_v1 %>%
  left_join(norm_v1, by = "high_exp_2d") %>%
  mutate(indexed = group_share / norm)

###############################################################################
# VERSION 2: Binary split within NACE 4-digit
###############################################################################

# Only sectors with 3+ firms (need meaningful median)
nace4d_counts <- pre_msr %>%
  count(nace4d) %>%
  filter(n >= 3)

pre_msr_4d <- pre_msr %>%
  filter(nace4d %in% nace4d_counts$nace4d) %>%
  group_by(nace4d) %>%
  mutate(high_exp_4d = as.integer(shortage_intensity > median(shortage_intensity))) %>%
  ungroup()

cat("Firms in 4-digit sectors with 3+ firms:", nrow(pre_msr_4d), "\n")
cat("Sectors:", n_distinct(pre_msr_4d$nace4d), "\n")

df_v2 <- df %>%
  inner_join(pre_msr_4d %>% select(vat, high_exp_4d), by = "vat",
             relationship = "many-to-one")

share_v2 <- df_v2 %>%
  group_by(year, high_exp_4d) %>%
  summarise(group_rev = sum(real_revenue), .groups = "drop") %>%
  group_by(year) %>%
  mutate(group_share = group_rev / sum(group_rev)) %>%
  ungroup() %>%
  mutate(group = ifelse(high_exp_4d == 1, "High exposure", "Low exposure"))

norm_v2 <- share_v2 %>% filter(year == 2016) %>% select(high_exp_4d, norm = group_share)
share_v2 <- share_v2 %>%
  left_join(norm_v2, by = "high_exp_4d") %>%
  mutate(indexed = group_share / norm)

###############################################################################
# VERSION 3: Continuous treatment — terciles of shortage intensity
###############################################################################

pre_msr_cont <- pre_msr %>%
  mutate(
    tercile = ntile(shortage_intensity, 3),
    tercile_label = case_when(
      tercile == 1 ~ "Low (T1)",
      tercile == 2 ~ "Medium (T2)",
      tercile == 3 ~ "High (T3)"
    )
  )

cat("\nTercile cutpoints:\n")
print(pre_msr_cont %>%
  group_by(tercile_label) %>%
  summarise(n = n(), min_si = min(shortage_intensity),
            median_si = median(shortage_intensity),
            max_si = max(shortage_intensity), .groups = "drop"))

df_v3 <- df %>%
  inner_join(pre_msr_cont %>% select(vat, tercile, tercile_label), by = "vat",
             relationship = "many-to-one")

share_v3 <- df_v3 %>%
  group_by(year, tercile, tercile_label) %>%
  summarise(group_rev = sum(real_revenue), .groups = "drop") %>%
  group_by(year) %>%
  mutate(group_share = group_rev / sum(group_rev)) %>%
  ungroup()

norm_v3 <- share_v3 %>% filter(year == 2016) %>% select(tercile, norm = group_share)
share_v3 <- share_v3 %>%
  left_join(norm_v3, by = "tercile") %>%
  mutate(indexed = group_share / norm)

###############################################################################
# FIGURES
###############################################################################

make_plot <- function(data, color_col, title_suffix, filename) {
  ggplot(data, aes(x = year, y = indexed, color = .data[[color_col]])) +
    geom_line(linewidth = 1.1) +
    geom_point(size = 2) +
    geom_vline(xintercept = 2017, linetype = "dashed", color = "grey40", linewidth = 0.7) +
    geom_hline(yintercept = 1, linetype = "dotted", color = "grey50") +
    annotate("text", x = 2017.3, y = max(data$indexed) * 0.97,
             label = "MSR reform", size = 3, hjust = 0, color = "grey40") +
    labs(
      title = paste0("Output share by carbon exposure — ", title_suffix),
      subtitle = "Exposure = pre-MSR allowance shortage (2013-16) / revenue | Indexed to 2016 = 1",
      x = "", y = "Output share (2016 = 1)", color = NULL
    ) +
    theme_minimal() +
    theme(legend.position = "bottom", axis.line = element_line(color = "black")) +
    scale_x_continuous(breaks = seq(base_year, end_year, by = 2))
}

# V1: NACE 2-digit split
p1 <- make_plot(share_v1, "group", "NACE 2-digit median split",
                "phase1a_v1_nace2d_split.pdf") +
  scale_color_manual(values = c("High exposure" = "#D6604D", "Low exposure" = "#4393C3"))
ggsave(file.path(output_fig, "phase1a_v1_nace2d_split.pdf"), p1, width = 10, height = 6)

# V2: NACE 4-digit split
p2 <- make_plot(share_v2, "group", "NACE 4-digit median split (sectors with 3+ firms)",
                "phase1a_v2_nace4d_split.pdf") +
  scale_color_manual(values = c("High exposure" = "#D6604D", "Low exposure" = "#4393C3"))
ggsave(file.path(output_fig, "phase1a_v2_nace4d_split.pdf"), p2, width = 10, height = 6)

# V3: Terciles
p3 <- make_plot(share_v3, "tercile_label", "terciles of shortage intensity",
                "phase1a_v3_terciles.pdf") +
  scale_color_manual(values = c("Low (T1)" = "#4393C3", "Medium (T2)" = "#999999",
                                "High (T3)" = "#D6604D"))
ggsave(file.path(output_fig, "phase1a_v3_terciles.pdf"), p3, width = 10, height = 6)

# ---- Print key numbers ----
cat("\n=== V1: NACE 2d median split ===\n")
print(as.data.frame(share_v1 %>%
  filter(year %in% c(2012, 2016, 2019, 2021)) %>%
  select(year, group, group_share, indexed) %>%
  mutate(group_share = round(group_share * 100, 1), indexed = round(indexed, 3))))

cat("\n=== V2: NACE 4d median split ===\n")
print(as.data.frame(share_v2 %>%
  filter(year %in% c(2012, 2016, 2019, 2021)) %>%
  select(year, group, group_share, indexed) %>%
  mutate(group_share = round(group_share * 100, 1), indexed = round(indexed, 3))))

cat("\n=== V3: Terciles ===\n")
print(as.data.frame(share_v3 %>%
  filter(year %in% c(2012, 2016, 2019, 2021)) %>%
  select(year, tercile_label, group_share, indexed) %>%
  mutate(group_share = round(group_share * 100, 1), indexed = round(indexed, 3))))

cat("\nFigures saved.\n")
