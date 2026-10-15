#### load_data.R
####
#### Shared data loader for the BCT meta-analysis.
#### Reads the raw extraction spreadsheets (never modified by code),
#### assigns stable identifiers, applies the documented inclusion rules,
#### and derives the quantities the analysis scripts need.
####
#### Sourced by meta_prepost.R and meta_corr.R; also runnable on its own
#### (writes derivatives/exclusions.csv).

suppressMessages({
  library(here)
  library(dplyr)
  library(readxl)
})

SOURCE_DIR <- here("sourcedata")
DERIV_DIR  <- here("derivatives")
dir.create(DERIV_DIR, showWarnings = FALSE)

## ---- analysis constants -------------------------------------------------
PRIMARY_TASK <- "BCT"   # MVP scope: Levinson-style breath counting task only
R_PREPOST    <- 0.5     # assumed pre/post correlation (not reported by any study)
R_PREPOST_SENS <- c(0.3, 0.7)
RHO_WITHIN   <- 0.5     # assumed correlation among effects from one sample (aggregation sensitivity)

## ---- helpers ------------------------------------------------------------
make_pub_id <- function(author, year) {
  paste0(tolower(gsub("[^A-Za-z]", "", author)), year)
}

## =========================================================================
## 1. Pre/post data
## =========================================================================
prepost_raw <- read_excel(file.path(SOURCE_DIR, "breathpubs_prepost.xlsx"))

prepost <- prepost_raw %>%
  mutate(
    row_in_sheet = row_number() + 1L,            # +1 for the header row, matches Excel row numbers
    pub_id  = make_pub_id(author, year),
    control = as.logical(control),
    arm     = case_when(
      is.na(control)     ~ NA_character_,
      control            ~ "control",
      TRUE               ~ "intervention"
    ),
    # SEM -> SD where only SEM was reported
    sd1 = ifelse(is.na(sd1) & !is.na(sem1), sem1 * sqrt(n), sd1),
    sd2 = ifelse(is.na(sd2) & !is.na(sem2), sem2 * sqrt(n), sd2),
    extraction_source = ifelse(grepl("digitization", warnings, ignore.case = TRUE),
                               "digitized from figure", "reported in text/table")
  )

## Inclusion / exclusion rules (each one documented, each one testable)
prepost <- prepost %>%
  mutate(exclude_reason = case_when(
    study_type != "prepost"                     ~ "not a pre/post design (BCT used as intervention, no BCT outcome)",
    is.na(mean1) | is.na(mean2)                 ~ "no pre/post means extracted",
    is.na(breathtask) | breathtask != PRIMARY_TASK ~ paste0("task is ", breathtask, ", not ", PRIMARY_TASK),
    author == "Lim" & year == 2018              ~ "sample is a subset of Wong 2018 re-tested without intervention",
    intervention == "followup"                  ~ "3-month follow-up of the intervention arm, not a control condition",
    is.na(sd1) | is.na(sd2)                     ~ "no SD/SEM available",
    TRUE                                        ~ NA_character_
  ))

prepost_included <- prepost %>%
  filter(is.na(exclude_reason)) %>%
  mutate(
    # one sample per publication x arm (Levinson 2014 has two control arms)
    sample_id = paste(pub_id, ifelse(is.na(study), "", study), arm,
                      ifelse(arm == "control", tolower(intervention), intervention), sep = "_"),
    sample_id = gsub("__", "_", sample_id),
    label     = paste0(author, " et al., ", year),
    arm_label = ifelse(arm == "control" & intervention == "-", "no training", intervention)
  ) %>%
  arrange(desc(arm), year, author)

## =========================================================================
## 2. Correlation data
## =========================================================================
# 'study' is read as text so sub-samples can be labelled e.g. 1a / 1b
# (Levinson 2014 study 1 ran in two participant blocks); other columns keep readxl's guessed types
corr_path  <- file.path(SOURCE_DIR, "breathpubs_corr.xlsx")
corr_types <- ifelse(names(read_excel(corr_path, n_max = 0)) == "study", "text", "guess")
corr_raw   <- read_excel(corr_path, col_types = corr_types)

corr <- corr_raw %>%
  mutate(
    row_in_sheet = row_number() + 1L,
    pub_id   = make_pub_id(author, year),
    study    = ifelse(is.na(study), "1", study),
    reverse  = as.logical(reverse),
    # sign convention: positive r = better BCT accuracy goes with "more mindful / better wellbeing / better EF"
    r_signed = r * ifelse(reverse, -1, 1)
  ) %>%
  mutate(exclude_reason = case_when(
    is.na(r)                                       ~ "no correlation extracted (placeholder row)",
    is.na(breathtask) | breathtask != PRIMARY_TASK ~ paste0("task is ", breathtask, ", not ", PRIMARY_TASK),
    is.na(n)                                       ~ "no sample size",
    is.na(category)                                ~ "correlate not categorised",
    TRUE                                           ~ NA_character_
  ))

corr_included <- corr %>%
  filter(is.na(exclude_reason)) %>%
  mutate(
    sample_id = paste0(pub_id, "_s", study),
    effect_id = row_number(),
    label     = paste0(author, ", ", year, ", ", study),
    category  = factor(category, levels = c("mindfulness", "wellbeing", "EF"),
                       labels = c("Mindfulness", "Psychological wellbeing", "Executive function"))
  ) %>%
  arrange(category, year, author, study, correlate)

## =========================================================================
## 3. Write the audit trail
## =========================================================================
exclusions <- bind_rows(
  prepost %>% filter(!is.na(exclude_reason)) %>%
    transmute(dataset = "prepost", row_in_sheet, author, year, breathtask, exclude_reason),
  corr %>% filter(!is.na(exclude_reason)) %>%
    transmute(dataset = "correlations", row_in_sheet, author, year, breathtask, exclude_reason)
)
write.csv(exclusions, file.path(DERIV_DIR, "exclusions.csv"), row.names = FALSE)

if (sys.nframe() == 0) {  # only when run directly, not when sourced
  cat(sprintf("pre/post: %d rows read, %d included (%d publications)\n",
              nrow(prepost), nrow(prepost_included), n_distinct(prepost_included$pub_id)))
  cat(sprintf("correlations: %d rows read, %d included (%d publications, %d samples)\n",
              nrow(corr), nrow(corr_included), n_distinct(corr_included$pub_id), n_distinct(corr_included$sample_id)))
  print(table(exclusions$dataset, exclusions$exclude_reason))
}
