# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Data + analysis code for a meta-analysis of the Breath Counting Task (BCT; Levinson et al., 2014), headed for a short manuscript in *Mindfulness* and a PsyArXiv preprint. Two analyses: pre/post sensitivity to mindfulness training (`code/meta_prepost.R`) and convergent validity correlations with mindfulness / wellbeing / executive function (`code/meta_corr.R`). `README.md` describes the methods and outputs. `PLAN.md` is the roadmap to submission. `SEARCH_PLAN.md` is the agreed protocol for the systematic literature search, which is the current step.

## Commands

Run these from the repo root. `.Rprofile` activates renv only when R starts there.

```sh
Rscript -e "renv::restore()"  # install the package versions pinned in renv.lock (first time / after lockfile changes)
Rscript code/run_all.R        # full pipeline, ~10 s; regenerates everything in derivatives/
Rscript code/load_data.R      # loader only: prints inclusion counts + exclusion table, writes derivatives/exclusions.csv
```

- R packages are managed with renv (`renv.lock`, R 4.6.1). `run_all.R` stops if renv isn't active or packages are missing. It never installs anything itself. To add a package, use it in the code, then run `Rscript -e "renv::install('<pkg>'); renv::snapshot()"` and commit `renv.lock`. Don't use bare `install.packages()`.
- Inside scripts, paths resolve via `here::here()`, anchored by the empty `.here` file at the root.
- There are no tests and no R linter. Check a change by rerunning `run_all.R` and reading `git diff derivatives/`. Differences in the last few digits usually come from different R or package versions, not from your change.
- Python is only used for the one-off digitizer scripts and the planned search tooling (`code/search/`). It is a uv project (`pyproject.toml` + committed `uv.lock`, no build system). Run scripts with `uv run <script>.py` (e.g. `uv run code/digitize_levinson2014.py`) and add dependencies with `uv add <pkg>`. Never use bare `python` or `pip`.
- Python style comes from ruff (dev dependency, configured in `pyproject.toml`). Run `uv run ruff check` and `uv run ruff format` before committing Python changes.
- `.gitattributes` stores and checks out every text file with LF endings. R on Windows still writes CRLF into `derivatives/`, but git normalizes that on `git add`, so those files don't show up as changed just because of their line endings.

## Architecture

- **`sourcedata/*.xlsx` are the source of truth and are never written by code.** Extraction is entered by hand (the human verifies every number). Column meanings are in `sourcedata/codebook.json`. Keep it in sync if you add sheet columns.
- **`code/load_data.R` is the single place for inclusion logic.** It reads both sheets, builds IDs (`pub_id` = lowercased author + year, `sample_id`, `effect_id`), converts SEM→SD, applies sign flips (`reverse` → `r_signed`, so positive r means "better BCT accuracy ↔ more mindful / better wellbeing / better EF"), and assigns an `exclude_reason` to each row through a `case_when`. Excluded rows are written to `derivatives/exclusions.csv` instead of being dropped silently. To add or change an exclusion rule, add a `case_when` arm there. Don't filter in the analysis scripts.
- Analysis constants live at the top of `load_data.R`: `PRIMARY_TASK = "BCT"` (MBAS/MBE rows stay in the sheets but are excluded), the assumed pre/post `R_PREPOST = 0.5` with sensitivity values `R_PREPOST_SENS`, and `RHO_WITHIN` for aggregation.
- `meta_prepost.R` and `meta_corr.R` each `source()` `load_data.R`. `run_all.R` runs all three in fresh environments and writes `derivatives/session_info.txt`.
- **Pre/post model:** `SMCR` (pre-test SD standardization, Hedges-corrected) per arm. Multiple control arms within one study are pooled first (Levinson 2014: n-back + no training). The headline is the *controlled* effect (intervention change minus control change, Becker 1988), pooled with REML random effects. Also writes leave-one-out, Egger's test and r-sensitivity outputs.
- **Correlation model:** Fisher-z, with one three-level `rma.mv` per construct (`~ 1 | sample_id / effect_id`) plus cluster-robust SEs by sample. Sensitivity analysis aggregates to one effect per sample × construct. Rows sharing `author`+`year`+`study` are one sample. `study` is read as text so independent blocks can be coded `1a`/`1b`.
- Top-level split: `sourcedata/` holds only hand-curated inputs. `derivatives/` holds everything repo code writes, including literature-search API results (`derivatives/search/`). Both are tracked, except figures (`derivatives/**/*.png` and `*.pdf`), which are gitignored. Rerun the pipeline after any data or code change so the committed derivatives match. The digitizer CSVs count as source data because they come from an external digitizer tool, not from repo code.
- `code/digitize_*.py` turn plot-digitizer CSVs into means/SDs that were then typed into the xlsx by hand (rows flagged "values from digitization!" in the `warnings` column). They don't feed the pipeline.

## Domain conventions

- Category rule for correlates: questionnaire → mindfulness or wellbeing; performance task → EF. `sourcedata/scales_corr.xlsx` maps acronyms to instruments (incomplete).
- Known extraction fixes pending in the sheets (see `PLAN.md` §2): Gorman year should be 2016, "Meler" should be Meier, Wang 2019 unresolved.
- The planned search layout (`SEARCH_PROTOCOL.md`, `code/search/`, `derivatives/search/`, `sourcedata/screening/`), dedup rules, and recall-check gate (every BCT publication in `sourcedata/publications.csv` must appear in the deduplicated set) are specified in `SEARCH_PLAN.md`. `SEARCH_PROTOCOL.md` is the fixed protocol and lists where it departs from the plan (e.g. OSF dropped). The literature APIs (OpenAlex, PubMed, Europe PMC, CrossRef) are reachable from Claude's shell. The OpenAlex API key is read from a gitignored `.env` via python-dotenv. Screening is dual and independent in ASReview (pinned in `uv.lock`; it needs pandas < 3), following `SCREENING_GUIDE.md`.
