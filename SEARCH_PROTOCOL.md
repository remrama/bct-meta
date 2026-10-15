# Search protocol

Systematic search for the BCT meta-analysis (identification → deduplicated screening set). This is
the fixed protocol that the PRISMA 2020 report describes. `SEARCH_PLAN.md` is the working plan it
came from. Deviations from that plan are listed in §7.

Protocol fixed: 2026-10-15. Search run: see `derivatives/search/search_log.csv` (one row per
database × query, with the run date).

## 1. Eligibility criteria

Applied at screening (title/abstract, then full text). The search is built to find every record
that could meet them.

| Criterion | Rule |
|---|---|
| Population | Any human sample, any age. |
| Measure | The Breath Counting Task as described by Levinson et al. (2014), or a close variant: participants count breaths in cycles (typically to 9) with button presses, and accuracy (% correct cycles, or an equivalent error metric) is the score. The Meditation Breath Attention Score (MBAS; bell-probe) and Mindful Breathing Exercise (MBE) paradigms are excluded. |
| Data | Reports at least one of: (a) a correlation between BCT accuracy and a self-report mindfulness, wellbeing, or executive-function measure; (b) BCT accuracy before and after an intervention, with a comparison arm. |
| Publication type | Journal articles, preprints, theses, conference papers: anything with extractable numbers. |
| Language | Any at search. Non-English records are flagged at screening, not excluded. |
| Date | Published 2014 onward (the task was introduced by Levinson et al., 2014). |

## 2. Information sources

Free, API-accessible databases:

| Database | Interface | Fields searched |
|---|---|---|
| OpenAlex | `api.openalex.org/works?search=` | title, abstract, and full text where OpenAlex has it |
| PubMed | NCBI E-utilities (`esearch` → `efetch`) | all fields, with PubMed's automatic term mapping (the translation PubMed applied is logged) |
| Europe PMC | REST `search`, `resultType=core`, all sources (includes `SRC:PPR` preprints) | Europe PMC default: title, abstract, keywords, and full text of open-access articles |

Citation searching (OpenAlex):

- **Forward:** every work citing Levinson et al. (2014), DOI 10.3389/fpsyg.2014.01202
  (OpenAlex `filter=cites:<id>`).
- **Backward:** every reference of the 2023 mega-analysis of BCT performance and FFMQ subscales,
  DOI 10.1007/s12671-023-02201-9 (OpenAlex `referenced_works`).

Every citer and every reference goes into the pool without judgement. Screening decides.

Preprints come in through OpenAlex (which indexes PsyArXiv, MindRxiv and other servers by DOI)
and Europe PMC (`SRC:PPR`). No preprint server is searched on its own (see §7).

Not searched: Scopus, Web of Science, PsycInfo (no institutional access). This is a stated
limitation. Google Scholar (Publish or Perish) may be added later as a separate, logged source.

## 3. Search strings

No MeSH or thesaurus term exists for the BCT, so every string is free text.

| ID | String | Purpose |
|---|---|---|
| S1 | `"breath counting task" OR "breath-counting task"` | core |
| S2 | `"breath counting" AND (mindfulness OR meditation OR "mind wandering")` | papers that never say "task" |
| S3 | `"breath count" AND (accuracy OR mindfulness)` | "breath count accuracy", "breath-count score" |
| S4 | `"counting breaths" AND (mindfulness OR meditation)` | verb form |

**Per-database adaptations.** Each submitted string is logged verbatim in `search_log.csv`.

| Database | Adaptation | Date filter |
|---|---|---|
| OpenAlex | strings as written (OpenAlex `search` accepts quoted phrases and AND/OR) | `from_publication_date:2014-01-01` |
| PubMed | `(<string>) AND 2014:3000[dp]` | in the string |
| Europe PMC | `(<string>) AND PUB_YEAR:[2014 TO 3000]` | in the string |

## 4. Records and deduplication

Raw hits are saved untouched, one file per database × query, in `derivatives/search/raw/`.
The number of rows saved is checked against the total the database reports.

Normalisation: DOI lower-cased with any `https://doi.org/` prefix stripped; title key = the title
lower-cased with only letters and digits kept; year as an integer.

Records are merged in this order. Every merge is written to `derivatives/search/dedup_log.csv`
(kept record, dropped record, rule):

0. Same native ID (the same database record returned by more than one query).
1. Exact DOI.
2. PMID.
3. Title key plus year within ±1 (catches preprint ↔ published and online-first ↔ print).
4. Title key alone. These merges are reviewed by hand.

Rules 3 and 4 apply only to title keys of at least 20 characters, so generic titles
("Editorial", "Introduction") are not merged. When a preprint and its published version merge,
the published record is kept and the preprint DOI is kept in a `preprint_doi` column.

Each surviving record has a `sources` field listing every database × query (and citation route)
that found it. This gives per-database counts and the number of records found only by citation
searching.

## 5. Abstracts

Abstracts are taken in this order: PubMed → Europe PMC → CrossRef → OpenAlex (inverted index,
reconstructed) → blank. An `abstract_source` column records which. Records with no abstract stay
in the screening set, and the count is reported.

## 6. Screening set and recall check

The screening set is `derivatives/search/candidates_asreview.csv`, with ASReview columns
(`title`, `abstract`, `authors`, `year`, `doi`, `url`) plus `record_id`, `sources`, `type`,
`pmid`, `openalex_id`, `preprint_doi`, `abstract_source`, and `included`. `included` = 1 marks the
eight BCT publications already extracted in the sheets (Levinson 2014, Lim 2018, Wong 2018,
Rowland 2019, Isbel 2020, Polsinelli 2020, Tortella-Feliu 2020, Stieger 2021). ASReview uses them
as prior knowledge.

**Recall check (go/no-go).** Every publication with task = BCT in `sourcedata/publications.csv`
must be in the deduplicated set. If any is missing, the strings are revised, the affected
searches re-run and logged, and the check repeated before screening starts. The result is written
to `derivatives/search/recall_check.csv`.

## 6a. Screening

Two reviewers (RM and a second reviewer) screen independently in ASReview 3.0.8, pinned in
`uv.lock`. The rules they follow are in `SCREENING_GUIDE.md`.

- **Calibration.** Before the main screen, both reviewers label the same 40 records
  (`derivatives/search/calibration_set.csv`, drawn by `code/search/make_calibration_set.py`) and
  discuss their disagreements. Any rule clarifications are logged in the guide.
- **Title/abstract.** Each reviewer labels every record. ASReview orders the records but there is
  no stopping rule. Agreement is reported as Cohen's κ. A record goes to full text if either
  reviewer includes it.
- **Full text.** Both reviewers screen independently and record one exclusion reason per
  excluded study (`not_empirical`, `no_bct`, `no_eligible_analysis`, `no_data`, first that
  applies). Disagreements are resolved by discussion.

Reviewer exports (ASReview dataset CSV and project file) are stored unchanged in
`sourcedata/screening/`. The consensus decisions feed the PRISMA flow diagram.

## 7. Deviations from SEARCH_PLAN.md

- **Who ran the fetch.** The plan expected the APIs to be blocked from Claude's shell. They
  weren't, so `code/search/fetch_records.py` was run from there. The script and the committed
  raw output are the same either way.
- **OSF Preprints dropped.** The plan searched PsyArXiv through OSF. The OSF v2 `/preprints/`
  endpoint has no keyword filter, and its replacement (the SHARE index) has no boolean OR and
  rate-limited the pilot. In the pilot it returned 2 records for "breath counting" across every
  OSF-hosted server. The one we could check was already found by both OpenAlex and Europe PMC.
  OpenAlex indexes most PsyArXiv and MindRxiv preprints by DOI, and Europe PMC indexes PsyArXiv,
  so OSF was dropped rather than kept as a fragile source with little yield. Preprints are a
  minor part of the evidence base for this review.
- **OpenAlex API key.** OpenAlex now needs a free API key for some paging. One was used (read
  from a gitignored `.env`). It changes rate limits only, not results.
- **PubMed and Europe PMC fields.** The plan expected title/abstract only. The default fields
  were kept instead (PubMed all fields with term mapping; Europe PMC including open-access full
  text), because they find more records and recall is what matters at this stage.
- **CrossRef abstracts** are fetched by `code/search/build_candidates.py` (Step 3) for records
  with a DOI and no PubMed or Europe PMC abstract. They are cached in
  `derivatives/search/raw/crossref_abstracts.csv`.
