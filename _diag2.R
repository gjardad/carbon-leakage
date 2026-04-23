suppressPackageStartupMessages({library(dplyr); library(tidyr); library(stringr)})
f <- "C:/Users/jota_/Documents/NBB_data/raw/Eurostat/sts_inppd_m_BE.tsv.gz"
eu_wide <- read.delim(gzfile(f), stringsAsFactors = FALSE,
                      check.names = FALSE, na.strings = c(":", ": ", ""))
dim_col <- names(eu_wide)[1]

eu_long <- eu_wide %>%
  rename(dims = !!sym(dim_col)) %>%
  separate(dims,
           into = c("freq", "indic_bt", "nace_r2", "s_adj", "unit", "geo"),
           sep = ",", extra = "drop", fill = "right") %>%
  filter(indic_bt == "PRC_PRR_DOM", s_adj == "NSA")

cat("After filter:", nrow(eu_long), "rows wide\n")
cat("Unique nace_r2 codes (all):\n")
nace_codes <- sort(unique(eu_long$nace_r2))
print(nace_codes)

cat("\nCodes matching ^C[0-9]{2}$:\n")
print(nace_codes[str_detect(nace_codes, "^C[0-9]{2}$")])

cat("\nAll codes starting with C:\n")
print(nace_codes[str_detect(nace_codes, "^C")])
