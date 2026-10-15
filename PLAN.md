# Plan: from here to a preprint

MVP target: a short meta-analysis manuscript for *Mindfulness* (Springer), preprinted on PsyArXiv,
with data and code in this repository. Status as of 2026-10-15.

## Done
- Analysis pipeline rebuilt and validated on the 2021 extraction set (`code/`, `derivatives/`).
  `Rscript code/run_all.R` regenerates everything.
- Methodological fixes: standardized mean change with assumed pre/post r (sensitivity analyses),
  controlled effect as headline, three-level model + robust SEs for dependent correlations,
  moderator-test p-value bug fixed, exclusions made explicit (`derivatives/exclusions.csv`).
- Data hygiene: codebook matches the sheets, Levinson 2014 study 1 split into independent blocks
  (1a/1b), SART outcomes both in EF, DOIs for all listed publications (`sourcedata/publications.csv`).

## 1. Systematic search  ← current step; see SEARCH_PLAN.md
- Claude writes `code/search/fetch_records.py`; Remy runs it; Claude deduplicates and builds the
  ASReview screening set. Hard gate: recall check against `sourcedata/publications.csv`.
- Remy screens in ASReview (title/abstract, then full text). Decisions exported to
  `sourcedata/screening_decisions.csv` for the PRISMA flow.
- Optional: Google Scholar forward citations via Publish or Perish, merged into the candidate set.

## 2. Extraction
- New eligible studies entered into `sourcedata/breathpubs_corr.xlsx` and `sourcedata/breathpubs_prepost.xlsx`
  using the existing columns (see `sourcedata/codebook.json`). Claude can pre-read PDFs and draft rows;
  Remy verifies every number.
- While in the sheets: fix Gorman year (2016), "Meler" → Meier, resolve Wang 2019.
- Note any study that reports the BCT pre/post correlation — would replace the assumed r = 0.5.
- Decide category assignments for any new correlate types; keep the rule "questionnaire →
  mindfulness/wellbeing, performance task → EF" unless there's a reason not to.

## 3. Rerun and freeze
- `Rscript code/run_all.R`; inspect figures; lock sample IDs and categories.
- Complete `sourcedata/scales_corr.xlsx` (currently ~11 of ~25 acronyms defined).
- Generate the study-characteristics table from the sheets (one row per included study).

## 4. Write (order matters: each section depends on the previous)
1. Methods — search (from `SEARCH_PROTOCOL.md` and `derivatives/search/`), eligibility, extraction, effect sizes, models.
2. Results — PRISMA flow, study table, Figure 1 (pre/post), Figure 2 (correlations),
   sensitivity analyses.
3. Introduction — what the BCT is, why a behavioural measure matters, what Levinson 2014 claimed,
   what the 2023 FFMQ mega-analysis already showed, what this adds (controlled pre/post synthesis;
   wellbeing and EF constructs).
4. Discussion — sensitivity to training vs weak convergence with self-report; limitations
   (small k, digitized values, assumed r, no Scopus/WoS/PsycInfo, single screener with AI
   assistance).
5. Structured abstract (Objectives / Methods / Results / Conclusions, ≤ 250 words), title,
   4–6 keywords.
- Format: Markdown + `.bib` → pandoc → `.docx` (Springer) and PDF (preprint). Keep it short;
  journal cap is 45 double-spaced pages including everything.
- Supplementary: PRISMA 2020 checklist + flow diagram, funnel plots, leave-one-out table.

## 5. Release
- README updated with final numbers; remove the "in progress" banner.
- Push to GitHub; Zenodo DOI for the repository snapshot.
- Preprint on PsyArXiv; submit to *Mindfulness* with a Data Availability Statement pointing at the
  Zenodo DOI. Anonymise the repo link for double-blind review.

## Journal requirements (Mindfulness)
- ≤ 45 double-spaced pages inclusive of references, tables, figures.
- Structured abstract ≤ 250 words; 4–6 keywords.
- PRISMA reporting for meta-analyses.
- APA-style author–year citations; reference list with full DOI links.
- Data Availability Statement required.
