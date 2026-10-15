# Search plan — Steps 1–3 (identification → deduplicated screening set)

Decisions taken 2026-10-15: Route A (script run locally by Remy); forward citation chasing
limited to Levinson et al. (2014); backward chasing of the 2023 FFMQ mega-analysis included.
Screening will be done in ASReview (not covered here).

## 0. Fix the protocol before any searching

Nothing gets fetched until these are written down in `SEARCH_PROTOCOL.md`, because PRISMA reports
what was *planned*, and the recall check in Step 3 can't be judged against moving criteria.

**Eligibility (applied at screening, but the search is designed around it)**
- Population: any human sample, any age.
- Measure: the Breath Counting Task as described by Levinson et al. (2014) or a close variant —
  participants count breaths in cycles (typically to 9) with button presses, and accuracy
  (% correct cycles, or an equivalent error metric) is the score. Excludes MBAS (bell-probe) and
  MBE paradigms.
- Data: reports at least one of (a) a correlation between BCT accuracy and a self-report
  mindfulness, wellbeing, or executive-function measure, or (b) BCT accuracy before and after an
  intervention with a comparison arm.
- Publication type: journal articles, preprints, theses, conference papers — anything with
  extractable numbers. Language: any at search; non-English flagged, not excluded, at screening.
- Date: 2014 onward (the task didn't exist before Levinson 2014).

**Databases (free, API-accessible):** OpenAlex, PubMed, Europe PMC, OSF Preprints (PsyArXiv
provider). Not searched: Scopus, Web of Science, PsycInfo (no access) — stated as a limitation.
Google Scholar may be added separately via Publish or Perish; not part of these three steps.

**Search strings** (run in every database that supports the syntax; adapted per database, every
adaptation logged):

| ID | String | Purpose |
|---|---|---|
| S1 | `"breath counting task" OR "breath-counting task"` | core |
| S2 | `"breath counting" AND (mindfulness OR meditation OR "mind wandering")` | papers that never use the word "task" |
| S3 | `"breath count" AND (accuracy OR mindfulness)` | "breath count accuracy", "breath-count score" |
| S4 | `"counting breaths" AND (mindfulness OR meditation)` | verb form |

No MeSH/thesaurus terms exist for the BCT, so these are free-text in all databases. OpenAlex
`search=` covers title + abstract + fulltext where available; PubMed and Europe PMC are
title/abstract.

**Citation chasing**
- Forward: all works citing Levinson et al. 2014 (OpenAlex `cites:`), regardless of search string.
- Backward: the reference list of the 2023 FFMQ mega-analysis
  (10.1007/s12671-023-02201-9), resolved to records via OpenAlex `referenced_works`.

## 1. Run the searches

**Mechanism (Route A).** Claude writes `code/search/fetch_records.py` (requests + pandas, no
credentials). Remy runs `uv run code/search/fetch_records.py` once on his own machine (the APIs are
blocked from Claude's shells); it writes everything below. Claude does all subsequent steps.

**Per query, per database:**
1. Record date, exact string as submitted, filters (date ≥ 2014), and the reported total in
   `derivatives/search/search_log.csv`.
2. Page through all results; save the raw hits untouched to `derivatives/search/raw/<db>_<S#>.csv` with the
   database's native ID, DOI, title, year, authors, venue, PMID where present.
3. Verify rows saved == reported count (or the API's cap); re-run any mismatch.

**Database specifics**
- OpenAlex: `/works?search=…&filter=from_publication_date:2014-01-01&per-page=200` with
  `select=id,doi,title,publication_year,authorships,primary_location,ids,type`. Keep `type`
  (article / preprint / book-chapter / dissertation) so chapters and theses are identifiable later.
- PubMed: E-utilities `esearch` (ids) → `efetch` (XML: title, abstract, DOI, journal, year).
  Date filter `2014:3000[dp]`.
- Europe PMC: REST `search?query=…&resultType=core` — returns abstracts directly; include
  `SRC:PPR` so preprints are in scope.
- OSF Preprints: `/v2/preprints/?filter[provider]=psyarxiv&filter[q]=…` — limited search syntax,
  so S1 and S2 only.

**Step 1 output:** `search_log.csv` (one row per database × query) and ~16 raw files.

## 2. Citation chasing

- Resolve Levinson 2014's OpenAlex ID from DOI 10.3389/fpsyg.2014.01202; fetch
  `filter=cites:W…` fully paginated. Logged in `search_log.csv` as source
  `citation_forward_levinson2014` with its count. Raw file `raw/openalex_cites_levinson2014.csv`.
- Fetch the 2023 mega-analysis's `referenced_works`, resolve each to a record. Logged as
  `citation_backward_megaanalysis2023`. Raw file `raw/openalex_refs_megaanalysis2023.csv`.
- No judgement applied at this stage — every citer and every reference goes into the pool.

## 3. Deduplicate, enrich, and build the screening set

**3a. Normalise.** DOI lower-cased, `https://doi.org/` stripped. Title key = lower-case
alphanumerics only. Year as integer.

**3b. Merge order.** (1) exact DOI; (2) PMID; (3) title key + year within ±1 (catches preprint ↔
published, online-first ↔ print); (4) title key alone, with a manual look at the survivors. Each
merge written to `derivatives/search/dedup_log.csv` (kept_id, dropped_id, rule) so the PRISMA "duplicates
removed" number is auditable. Preprint–article pairs are merged with the published version kept and
the preprint DOI retained in a `preprint_doi` column.

**3c. Provenance.** Each surviving record carries a `sources` field listing every
`(database, query)` that found it, e.g. `openalex:S1;pubmed:S1;cites:levinson2014`. This gives
per-database counts and the "records from citation searching only" number PRISMA 2020 asks for.

**3d. Abstracts.** Needed for ASReview. Priority: PubMed/Europe PMC text (clean) → CrossRef
abstract field → OpenAlex inverted index reconstructed → blank. An `abstract_source` column records
which. Records with no abstract anywhere stay in the set (ASReview copes with title-only, just less
well); the count is reported.

**3e. ASReview file.** `derivatives/search/candidates_asreview.csv` with the columns ASReview reads: `title`,
`abstract`, `authors`, `year`, `doi`, `url`, plus `record_id`, `sources`, `type`, `pmid`,
`openalex_id`. One extra column, `included`: `1` for the BCT publications already extracted in the
sheets (Levinson 2014, Wong 2018, Lim 2018, Isbel 2020, Tortella-Feliu 2020, Rowland 2019,
Polsinelli 2020, Stieger 2021), blank otherwise — ASReview uses labelled rows as prior knowledge to
seed its model.

**3f. Recall check (go/no-go).** Every BCT publication in `sourcedata/publications.csv` must appear in
the deduplicated set. If any is missing, the strings are revised, the affected searches re-run, and
the log updated — before screening starts. Known tricky cases: Herrero 2018 (J Neurophysiol; may
not use the phrase), Gorman 2016, Thompson 2021.

**3g. Sanity counts** reported: hits per database, per query, duplicates removed, unique records,
records with abstracts, records found only by citation chasing.

## Deliverables

Everything a script writes goes in `derivatives/search/` and is tracked in git. API results drift
over time, so the committed snapshot is the record of what the search returned. Rerunning the fetch
script later is a new search and gets a new log row, not a reproduction.

```
SEARCH_PROTOCOL.md             criteria, strings, databases, dates, limitations   (Step 0)
code/search/
  fetch_records.py             run once locally                                   (Step 1)
derivatives/search/
  search_log.csv               database × query × date × count                   (Steps 1–2)
  raw/*.csv                    untouched per-query hits                          (Steps 1–2)
  dedup_log.csv                every merge and the rule that made it             (Step 3)
  candidates_asreview.csv      the screening set                                 (Step 3)
sourcedata/
  screening_decisions.csv      ASReview export of the human screening decisions  (after Step 3)
```

**Expected scale:** OpenAlex S1 alone returned 142 on 2026-10-15; Levinson 2014 has a few hundred
citers; after dedup, roughly 300–600 unique records, of which perhaps 30–60 are real BCT-outcome
studies.

**Checkpoints:** (i) protocol text approved before fetching; (ii) recall check result before the
screening set is declared final.

## Known related work surfaced by the test query (position the manuscript against these)
- *Mindfulness* 2023, "A Mega-Analysis of the Relationship Between Breath Counting Test Performance
  and Subscales of the FFMQ" (10.1007/s12671-023-02201-9) — overlaps the correlation analysis.
- Springer handbook chapters "Breath Counting Task (BCT)" (2022, 10.1007/978-3-030-77644-2_48-1;
  2025, 10.1007/978-3-031-47219-0_48).
