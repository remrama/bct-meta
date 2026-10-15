"""Run the database searches and citation chasing in SEARCH_PROTOCOL.md (Steps 1-2).

Writes one raw CSV per database x query to derivatives/search/raw/ and appends one row
per search to derivatives/search/search_log.csv. Each run is a new search: the log keeps
every run, the raw files hold the latest one (earlier snapshots live in git history).

    uv run code/search/fetch_records.py            # writes to derivatives/search/
    uv run code/search/fetch_records.py --out DIR  # pilot run somewhere else

Optional environment variables, read from the shell or a gitignored .env file at the
repo root: OPENALEX_API_KEY, OPENALEX_MAILTO, NCBI_API_KEY. None is required.
"""

import argparse
import datetime as dt
import os
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import pandas as pd
import requests
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / ".env")

QUERIES = {
    "S1": '"breath counting task" OR "breath-counting task"',
    "S2": '"breath counting" AND (mindfulness OR meditation OR "mind wandering")',
    "S3": '"breath count" AND (accuracy OR mindfulness)',
    "S4": '"counting breaths" AND (mindfulness OR meditation)',
}
LEVINSON2014_DOI = "10.3389/fpsyg.2014.01202"
MEGA2023_DOI = "10.1007/s12671-023-02201-9"

OPENALEX = "https://api.openalex.org"
EUTILS = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
EUROPEPMC = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"

RAW_COLUMNS = [
    "native_id",
    "doi",
    "pmid",
    "title",
    "year",
    "authors",
    "venue",
    "type",
    "abstract",
]

session = requests.Session()
session.headers["User-Agent"] = "bct-meta-analysis literature search (requests)"


def get(url, params=None, accept_json=True, tries=7):
    """GET with retries (exponential backoff, or Retry-After) on errors, 429 and 5xx."""
    headers = {"Accept": "application/json"} if accept_json else {}
    for attempt in range(tries):
        wait = 2 ** (attempt + 1)
        try:
            r = session.get(url, params=params, headers=headers, timeout=120)
        except (requests.ConnectionError, requests.Timeout):
            if attempt == tries - 1:
                raise
            time.sleep(wait)
            continue
        if (r.status_code == 429 or r.status_code >= 500) and attempt < tries - 1:
            retry_after = r.headers.get("Retry-After", "")
            time.sleep(int(retry_after) if retry_after.isdigit() else wait)
            continue
        r.raise_for_status()
        return r.json() if accept_json else r.text


def clean_doi(doi):
    if not doi:
        return None
    doi = doi.strip().lower()
    for prefix in ("https://doi.org/", "http://doi.org/", "http://dx.doi.org/", "doi:"):
        doi = doi.removeprefix(prefix)
    return doi or None


# --- OpenAlex ---------------------------------------------------------------

OA_SELECT = (
    "id,doi,title,publication_year,authorships,primary_location,ids,type,"
    "abstract_inverted_index"
)


def openalex_params(**params):
    if key := os.environ.get("OPENALEX_API_KEY"):
        params["api_key"] = key
    if mailto := os.environ.get("OPENALEX_MAILTO"):
        params["mailto"] = mailto
    return params


def openalex_abstract(inverted):
    if not inverted:
        return None
    words = {pos: word for word, positions in inverted.items() for pos in positions}
    return " ".join(words[i] for i in sorted(words))


def openalex_row(w):
    loc = w.get("primary_location") or {}
    source = loc.get("source") or {}
    pmid = (w.get("ids") or {}).get("pmid")
    return {
        "native_id": w["id"].rsplit("/", 1)[1],
        "doi": clean_doi(w.get("doi")),
        "pmid": pmid.rstrip("/").rsplit("/", 1)[1] if pmid else None,
        "title": w.get("title"),
        "year": w.get("publication_year"),
        "authors": "; ".join(
            a["author"]["display_name"] for a in w.get("authorships") or []
        ),
        "venue": source.get("display_name"),
        "type": w.get("type"),
        "abstract": openalex_abstract(w.get("abstract_inverted_index")),
    }


def openalex_works(search=None, filter_=None):
    """Page through /works. Returns (reported_total, rows).

    Uses page= rather than cursor= paging: cursor paging needs an API key, page paging
    doesn't and reaches 10,000 results, far more than any search here returns.
    """
    params = openalex_params(per_page=200, select=OA_SELECT, page=1)
    if search:
        params["search"] = search
    if filter_:
        params["filter"] = filter_
    rows = []
    while True:
        page = get(f"{OPENALEX}/works", params)
        total = page["meta"]["count"]
        rows += [openalex_row(w) for w in page["results"]]
        if not page["results"] or params["page"] * 200 >= total:
            return total, rows
        params["page"] += 1


def openalex_id(doi):
    work = get(f"{OPENALEX}/works/doi:{doi}", openalex_params(select="id"))
    return work["id"].rsplit("/", 1)[1]


def openalex_references(doi):
    """Resolve every referenced work of one paper. Returns (reported_total, rows)."""
    work = get(
        f"{OPENALEX}/works/doi:{doi}", openalex_params(select="id,referenced_works")
    )
    ids = [r.rsplit("/", 1)[1] for r in work["referenced_works"]]
    rows = []
    for i in range(0, len(ids), 50):
        batch = "|".join(ids[i : i + 50])
        _, part = openalex_works(filter_=f"openalex_id:{batch}")
        rows += part
    return len(ids), rows


# --- PubMed -----------------------------------------------------------------


def ncbi_params(**params):
    params["tool"] = "bct-meta-analysis"
    if key := os.environ.get("NCBI_API_KEY"):
        params["api_key"] = key
    return params


def xml_text(el):
    return "".join(el.itertext()).strip() if el is not None else None


def pubmed_row(art):
    citation = art.find("MedlineCitation")
    article = citation.find("Article")
    ids = {
        a.get("IdType"): a.text
        for a in art.findall("PubmedData/ArticleIdList/ArticleId")
    }
    parts = []
    for a in article.findall("Abstract/AbstractText"):
        label = a.get("Label")
        text = xml_text(a)
        parts.append(f"{label}: {text}" if label else text)
    year = article.findtext("Journal/JournalIssue/PubDate/Year")
    if not year:
        medline_date = (
            article.findtext("Journal/JournalIssue/PubDate/MedlineDate") or ""
        )
        year = medline_date[:4] or None
    authors = []
    for a in article.findall("AuthorList/Author"):
        name = " ".join(filter(None, [a.findtext("ForeName"), a.findtext("LastName")]))
        authors.append(name or a.findtext("CollectiveName") or "")
    return {
        "native_id": citation.findtext("PMID"),
        "doi": clean_doi(ids.get("doi")),
        "pmid": citation.findtext("PMID"),
        "title": xml_text(article.find("ArticleTitle")),
        "year": int(year) if year and year.isdigit() else None,
        "authors": "; ".join(authors),
        "venue": article.findtext("Journal/Title"),
        "type": "; ".join(
            xml_text(t) for t in article.findall("PublicationTypeList/PublicationType")
        ),
        "abstract": " ".join(p for p in parts if p) or None,
    }


def pubmed_search(term):
    """esearch for PMIDs, then efetch the records. Returns (total, rows, translation)."""
    res = get(
        f"{EUTILS}/esearch.fcgi",
        ncbi_params(db="pubmed", term=term, retmode="json", retmax=9999),
    )["esearchresult"]
    pmids = res["idlist"]
    rows = []
    for i in range(0, len(pmids), 200):
        time.sleep(0.4)
        xml = get(
            f"{EUTILS}/efetch.fcgi",
            ncbi_params(db="pubmed", id=",".join(pmids[i : i + 200]), retmode="xml"),
            accept_json=False,
        )
        rows += [pubmed_row(a) for a in ET.fromstring(xml).findall("PubmedArticle")]
    return int(res["count"]), rows, res.get("querytranslation")


# --- Europe PMC -------------------------------------------------------------


def europepmc_row(r):
    journal = ((r.get("journalInfo") or {}).get("journal") or {}).get("title")
    book = (r.get("bookOrReportDetails") or {}).get("publisher")
    pub_types = (r.get("pubTypeList") or {}).get("pubType") or []
    return {
        "native_id": f"{r['source']}:{r['id']}",
        "doi": clean_doi(r.get("doi")),
        "pmid": r.get("pmid"),
        "title": r.get("title"),
        "year": int(r["pubYear"]) if r.get("pubYear") else None,
        "authors": r.get("authorString"),
        "venue": journal or book,
        "type": "; ".join(pub_types),
        "abstract": r.get("abstractText"),
    }


def europepmc_search(query):
    params = {
        "query": query,
        "resultType": "core",
        "format": "json",
        "pageSize": 1000,
        "cursorMark": "*",
    }
    rows, total = [], None
    while True:
        page = get(EUROPEPMC, params)
        total = page["hitCount"]
        results = page["resultList"]["result"]
        rows += [europepmc_row(r) for r in results]
        nxt = page.get("nextCursorMark")
        if not results or not nxt or nxt == params["cursorMark"]:
            break
        params["cursorMark"] = nxt
    return total, rows


# --- driver -----------------------------------------------------------------


def save(out, db, query_id, submitted, filters, total, rows, note=""):
    raw = out / "raw" / f"{db}_{query_id}.csv"
    df = pd.DataFrame(rows, columns=RAW_COLUMNS).drop_duplicates("native_id")
    df.to_csv(raw, index=False, lineterminator="\n")
    status = "ok" if len(df) == total else "MISMATCH"
    print(f"{db:>9} {query_id:<26} reported {total:>5}  saved {len(df):>5}  {status}")
    return {
        "run_date": dt.date.today().isoformat(),
        "database": db,
        "query_id": query_id,
        "string_submitted": submitted,
        "filters": filters,
        "reported_total": total,
        "rows_saved": len(df),
        "status": status,
        "raw_file": raw.relative_to(out).as_posix(),
        "note": note,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=ROOT / "derivatives" / "search")
    out = parser.parse_args().out
    (out / "raw").mkdir(parents=True, exist_ok=True)

    log = []
    for qid, q in QUERIES.items():
        total, rows = openalex_works(
            search=q, filter_="from_publication_date:2014-01-01"
        )
        log.append(
            save(
                out, "openalex", qid, q, "from_publication_date:2014-01-01", total, rows
            )
        )

        term = f"({q}) AND 2014:3000[dp]"
        total, rows, translation = pubmed_search(term)
        log.append(
            save(
                out,
                "pubmed",
                qid,
                term,
                "2014:3000[dp]",
                total,
                rows,
                f"PubMed translation: {translation}",
            )
        )

        query = f"({q}) AND PUB_YEAR:[2014 TO 3000]"
        total, rows = europepmc_search(query)
        log.append(
            save(out, "europepmc", qid, query, "PUB_YEAR:[2014 TO 3000]", total, rows)
        )

    wid = openalex_id(LEVINSON2014_DOI)
    total, rows = openalex_works(filter_=f"cites:{wid}")
    log.append(
        save(
            out,
            "openalex",
            "cites_levinson2014",
            f"filter=cites:{wid}",
            "none",
            total,
            rows,
            f"source citation_forward_levinson2014; {LEVINSON2014_DOI}",
        )
    )

    total, rows = openalex_references(MEGA2023_DOI)
    log.append(
        save(
            out,
            "openalex",
            "refs_megaanalysis2023",
            f"referenced_works of doi:{MEGA2023_DOI}",
            "none",
            total,
            rows,
            "source citation_backward_megaanalysis2023",
        )
    )

    log_file = out / "search_log.csv"
    new = pd.DataFrame(log)
    if log_file.exists():
        new = pd.concat([pd.read_csv(log_file, dtype=str), new.astype(str)])
    new.to_csv(log_file, index=False, lineterminator="\n")

    mismatches = [r for r in log if r["status"] != "ok"]
    if mismatches:
        print(f"\n{len(mismatches)} search(es) saved a different count than reported.")
        sys.exit(1)


if __name__ == "__main__":
    main()
