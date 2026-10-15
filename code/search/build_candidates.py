"""Deduplicate the raw search results and build the ASReview screening set (Step 3).

Reads derivatives/search/raw/*.csv (written by fetch_records.py) and writes, next to them:
  dedup_log.csv            every merge: kept_id, dropped_id, rule, matched_on
  candidates_asreview.csv  one row per unique record, ASReview columns first
  recall_check.csv         every BCT publication in sourcedata/publications.csv: found or not
  sanity_counts.csv        hits per source, duplicates removed, abstracts, citation-only

Abstracts missing from PubMed and Europe PMC are looked up on CrossRef by DOI. Lookups
are cached in raw/crossref_abstracts.csv, so a rerun only asks for new DOIs.

    uv run code/search/build_candidates.py            # derivatives/search/
    uv run code/search/build_candidates.py --dir DIR  # a pilot run's folder

Exits with status 1 if the recall check fails.
"""

import argparse
import datetime as dt
import html
import re
import sys
import time
from pathlib import Path

import pandas as pd
from fetch_records import clean_doi, get

ROOT = Path(__file__).resolve().parents[2]
CROSSREF = "https://api.crossref.org/works"

# Raw file stem -> provenance tag used in the `sources` column.
CITATION_SOURCES = {
    "openalex_cites_levinson2014": "cites:levinson2014",
    "openalex_refs_megaanalysis2023": "refs:megaanalysis2023",
}
# Lower is better when picking which record's metadata to keep.
DB_PRIORITY = {"pubmed": 0, "europepmc": 1, "openalex": 2}
PREPRINT_DOI_PREFIXES = (
    "10.31234/",  # PsyArXiv
    "10.31219/",  # OSF Preprints
    "10.31231/",  # MindRxiv
    "10.31235/",  # SocArXiv
    "10.1101/",  # bioRxiv, medRxiv
    "10.21203/",  # Research Square
    "10.20944/",  # Preprints.org
    "10.2139/",  # SSRN
    "10.48550/",  # arXiv
    "10.36227/",  # TechRxiv
)
MIN_TITLE_KEY = 20  # rules 3-4 skip shorter title keys ("editorial", "introduction")

# Record pairs judged not to be duplicates on manual review of the rule 3-4 merges.
# Two clusters are never joined if they'd put such a pair together.
NOT_DUPLICATES = {
    # 2015 doctoral thesis and the 2017 journal article from it: two reports, same study.
    frozenset(("openalex:W2270891286", "openalex:W4316083010")),
}

TAG = re.compile(r"</?[a-zA-Z][^>]*>")


def clean_text(s):
    if not isinstance(s, str):
        return None
    s = html.unescape(TAG.sub(" ", s))
    s = re.sub(r"\s+", " ", s).strip()
    return s or None


def title_key(title):
    return re.sub(r"[^a-z0-9]", "", title.lower()) if isinstance(title, str) else ""


def is_preprint(rec):
    doi = rec["doi"] if isinstance(rec["doi"], str) else ""
    return (
        rec["native_id"].startswith("PPR:")
        or (rec["db"] == "openalex" and rec["type"] == "preprint")
        or doi.startswith(PREPRINT_DOI_PREFIXES)
    )


def load_raw(raw_dir):
    """All raw hits, one row per (record, source)."""
    frames = []
    for f in sorted(raw_dir.glob("*.csv")):
        if f.stem == "crossref_abstracts":
            continue
        db, _, query = f.stem.partition("_")
        df = pd.read_csv(f, dtype=str)
        df["db"] = db
        df["source"] = CITATION_SOURCES.get(f.stem, f"{db}:{query}")
        frames.append(df)
    hits = pd.concat(frames, ignore_index=True)
    hits["key"] = hits["db"] + ":" + hits["native_id"]
    hits["year"] = pd.to_numeric(hits["year"], errors="coerce").astype("Int64")
    hits["title"] = hits["title"].map(clean_text)
    hits["abstract"] = hits["abstract"].map(clean_text)
    hits["doi"] = hits["doi"].str.lower()
    hits["title_key"] = hits["title"].map(title_key)
    return hits


class Clusters:
    """Union-find over records; each union is logged as kept <- dropped."""

    def __init__(self, records):
        self.records = records
        self.parent = {k: k for k in records.index}
        self.members = {k: {k} for k in records.index}
        self.log = []

    def rank(self, key):
        rec = self.records.loc[key]
        return (
            is_preprint(rec),
            not isinstance(rec["doi"], str),
            DB_PRIORITY[rec["db"]],
            key,
        )

    def find(self, k):
        while self.parent[k] != k:
            self.parent[k] = self.parent[self.parent[k]]
            k = self.parent[k]
        return k

    def union(self, a, b, rule, matched_on):
        ra, rb = self.find(a), self.find(b)
        if ra == rb or any(
            frozenset((x, y)) in NOT_DUPLICATES
            for x in self.members[ra]
            for y in self.members[rb]
        ):
            return
        kept, dropped = sorted((ra, rb), key=self.rank)
        self.parent[dropped] = kept
        self.members[kept] |= self.members.pop(dropped)
        self.log.append(
            {
                "kept_id": kept,
                "dropped_id": dropped,
                "rule": rule,
                "matched_on": matched_on,
            }
        )

    def merge_on(self, keys, rule):
        """Union every pair of records that share a value in `keys` (index -> value)."""
        for value, group in keys.dropna().groupby(keys.dropna()):
            members = list(group.index)
            for other in members[1:]:
                self.union(members[0], other, rule, value)

    def merge_title_year(self, rule):
        """Rule 3: same title key, years within +-1 (cluster-level comparison)."""
        recs = self.records[self.records["title_key"].str.len() >= MIN_TITLE_KEY]
        for value, group in recs.groupby("title_key"):
            members = group.sort_values("year").index.tolist()
            for i, a in enumerate(members):
                for b in members[i + 1 :]:
                    ya, yb = recs.at[a, "year"], recs.at[b, "year"]
                    if pd.notna(ya) and pd.notna(yb) and abs(ya - yb) <= 1:
                        self.union(a, b, rule, f"{value} ({ya}/{yb})")


def crossref_abstracts(dois, cache_file):
    """DOI -> abstract (or None) from CrossRef, using and updating the cache."""
    cache = (
        pd.read_csv(cache_file, dtype=str, keep_default_na=False)
        if cache_file.exists()
        else pd.DataFrame(columns=["doi", "abstract", "fetched"])
    )
    todo = sorted(set(dois) - set(cache["doi"]))
    for i in range(0, len(todo), 50):
        batch = todo[i : i + 50]
        page = get(
            CROSSREF,
            {
                "filter": ",".join(f"doi:{d}" for d in batch),
                "select": "DOI,abstract",
                "rows": 100,
            },
        )
        found = {
            item["DOI"].lower(): clean_text(item.get("abstract"))
            for item in page["message"]["items"]
        }
        new = pd.DataFrame(
            {
                "doi": batch,
                "abstract": [found.get(d) or "" for d in batch],
                "fetched": dt.date.today().isoformat(),
            }
        )
        # Saved after every batch so an interrupted run keeps what it fetched.
        cache = pd.concat([cache, new], ignore_index=True).sort_values("doi")
        cache.to_csv(cache_file, index=False, lineterminator="\n")
        time.sleep(1)
    abstracts = dict(zip(cache["doi"], cache["abstract"]))
    return {
        d: (re.sub(r"^abstract\s*", "", a, flags=re.IGNORECASE) or None)
        for d, a in abstracts.items()
    }


def first(values):
    return next((v for v in values if isinstance(v, str) and v), None)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", type=Path, default=ROOT / "derivatives" / "search")
    out = parser.parse_args().dir
    hits = load_raw(out / "raw")

    # Rule 0: the same database record returned by more than one query.
    sources = hits.groupby("key")["source"].agg(lambda s: sorted(set(s)))
    dedup_log = [
        {
            "kept_id": key,
            "dropped_id": f"{key} [{src}]",
            "rule": "0_same_record",
            "matched_on": key,
        }
        for key, srcs in sources.items()
        for src in srcs[1:]
    ]
    dedup_log += [
        {
            "kept_id": key,
            "dropped_id": f"{key} [{src}]",
            "rule": "0_same_record",
            "matched_on": "repeated within one query",
        }
        for (key, src), n in hits.groupby(["key", "source"]).size().items()
        for _ in range(n - 1)
    ]
    records = hits.drop_duplicates("key").set_index("key")

    clusters = Clusters(records)
    clusters.merge_on(records["doi"], "1_doi")
    clusters.merge_on(records["pmid"], "2_pmid")
    clusters.merge_title_year("3_title_year")
    long_keys = records["title_key"].where(
        records["title_key"].str.len() >= MIN_TITLE_KEY
    )
    clusters.merge_on(long_keys, "4_title_only")
    dedup_log += clusters.log
    dedup_log = pd.DataFrame(dedup_log)
    dedup_log.to_csv(out / "dedup_log.csv", index=False, lineterminator="\n")

    records["cluster"] = [clusters.find(k) for k in records.index]
    records["preprint"] = [is_preprint(records.loc[k]) for k in records.index]

    # Abstracts: PubMed -> Europe PMC -> CrossRef -> OpenAlex.
    need_crossref = set()
    for _, g in records.groupby("cluster"):
        if not first(g.loc[g["db"].isin(["pubmed", "europepmc"]), "abstract"]):
            need_crossref |= set(g["doi"].dropna())
    crossref = crossref_abstracts(need_crossref, out / "raw" / "crossref_abstracts.csv")

    pubs = pd.read_csv(ROOT / "sourcedata" / "publications.csv", dtype=str)
    pubs["doi"] = pubs["doi"].map(clean_doi, na_action="ignore")
    seed_dois = set(
        pubs.loc[(pubs["task"] == "BCT") & (pubs["sheet_status"] == "extracted"), "doi"]
    )

    rows = []
    for kept, g in records.groupby("cluster"):
        g = g.loc[sorted(g.index, key=clusters.rank)]
        rep = g.loc[kept]
        by_db = {db: gg for db, gg in g.groupby("db")}
        abstract, abstract_source = None, ""
        for name in ("pubmed", "europepmc", "crossref", "openalex"):
            if name == "crossref":
                abstract = first(crossref.get(d) for d in g["doi"].dropna())
            elif name in by_db:
                abstract = first(by_db[name]["abstract"])
            if abstract:
                abstract_source = name
                break
        doi = first(g["doi"])
        preprint_dois = g.loc[g["preprint"] & (g["doi"] != doi), "doi"]
        openalex = by_db.get("openalex")
        pmid = first(g["pmid"])
        openalex_id = (
            first(openalex.index.str.removeprefix("openalex:"))
            if openalex is not None
            else None
        )
        if doi:
            url = f"https://doi.org/{doi}"
        elif pmid:
            url = f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/"
        elif openalex_id:
            url = f"https://openalex.org/{openalex_id}"
        else:
            url = f"https://europepmc.org/article/{rep['native_id'].replace(':', '/')}"
        rows.append(
            {
                "title": rep["title"] or first(g["title"]),
                "abstract": abstract,
                "authors": rep["authors"]
                if isinstance(rep["authors"], str)
                else first(g["authors"]),
                "year": rep["year"],
                "doi": doi,
                "url": url,
                "native_id": kept,
                "sources": ";".join(sorted({s for k in g.index for s in sources[k]})),
                "type": first(openalex["type"])
                if openalex is not None
                else rep["type"],
                "pmid": pmid,
                "openalex_id": openalex_id,
                "preprint_doi": first(preprint_dois) if not rep["preprint"] else None,
                "abstract_source": abstract_source,
                "included": 1 if seed_dois & set(g["doi"].dropna()) else None,
                "member_ids": ";".join(g.index),
                "all_dois": set(g["doi"].dropna()),
            }
        )
    cand = pd.DataFrame(rows)
    cand["sort_key"] = cand["title"].map(title_key)
    cand = cand.sort_values(["year", "sort_key", "native_id"], na_position="last")
    cand.insert(6, "record_id", range(1, len(cand) + 1))
    cand["year"] = cand["year"].astype("Int64")
    cand["included"] = cand["included"].astype("Int64")

    # Recall check: every BCT publication must be in the deduplicated set.
    bct = pubs[pubs["task"] == "BCT"].copy()
    hit = {d: r for r in cand.itertuples() for d in r.all_dois}
    bct["found"] = bct["doi"].isin(hit.keys())
    bct["record_id"] = bct["doi"].map(lambda d: hit[d].record_id if d in hit else None)
    bct["sources"] = bct["doi"].map(lambda d: hit[d].sources if d in hit else None)
    bct["found_by_string"] = bct["sources"].map(
        lambda s: (
            isinstance(s, str)
            and any(t.split(":")[1].startswith("S") for t in s.split(";"))
        )
    )
    recall = bct[
        [
            "first_author",
            "year",
            "doi",
            "sheet_status",
            "found",
            "found_by_string",
            "record_id",
            "sources",
        ]
    ]
    recall.to_csv(out / "recall_check.csv", index=False, lineterminator="\n")

    cand = cand.drop(columns=["all_dois", "sort_key", "member_ids"])
    cand.to_csv(out / "candidates_asreview.csv", index=False, lineterminator="\n")

    # Sanity counts.
    counts = [
        ("hits", f"raw:{src}", n) for src, n in hits.groupby("source").size().items()
    ]
    is_citation = hits["source"].isin(CITATION_SOURCES.values())
    counts += [
        ("prisma", "records_from_databases", int((~is_citation).sum())),
        ("prisma", "records_from_citation_searching", int(is_citation.sum())),
        ("prisma", "records_total", len(hits)),
        ("prisma", "duplicates_removed", len(dedup_log)),
        ("prisma", "unique_records", len(cand)),
    ]
    counts += [
        ("dedup", f"rule:{r}", n)
        for r, n in dedup_log["rule"].value_counts().sort_index().items()
    ]
    citation_only = cand["sources"].map(
        lambda s: all(t in CITATION_SOURCES.values() for t in s.split(";"))
    )
    counts.append(
        ("prisma", "unique_records_citation_searching_only", int(citation_only.sum()))
    )
    for db in ["openalex", "pubmed", "europepmc"]:
        n = cand["sources"].str.contains(rf"(?:^|;){db}:S").sum()
        counts.append(("coverage", f"unique_records_found_by:{db}", int(n)))
    for src, n in cand["abstract_source"].replace("", "none").value_counts().items():
        counts.append(("abstracts", f"abstract_source:{src}", int(n)))
    counts.append(
        ("abstracts", "with_abstract", int((cand["abstract_source"] != "").sum()))
    )
    counts.append(
        ("seed", "included_seed_records", int(cand["included"].notna().sum()))
    )
    counts += [
        ("recall", "bct_publications", len(recall)),
        ("recall", "bct_publications_found", int(recall["found"].sum())),
        (
            "recall",
            "bct_publications_found_by_string",
            int(recall["found_by_string"].sum()),
        ),
    ]
    counts = pd.DataFrame(counts, columns=["group", "metric", "value"])
    counts.to_csv(out / "sanity_counts.csv", index=False, lineterminator="\n")
    print(counts.to_string(index=False))

    print("\nRule 4 (title only) merges, check by hand:")
    for r in dedup_log[dedup_log["rule"] == "4_title_only"].itertuples():
        print(f"  {r.kept_id} <- {r.dropped_id}  [{r.matched_on}]")

    missing = recall[~recall["found"]]
    if len(missing):
        print("\nRECALL CHECK FAILED. Missing:")
        print(missing[["first_author", "year", "doi"]].to_string(index=False))
        sys.exit(1)
    print("\nRecall check passed: all", len(recall), "BCT publications found.")


if __name__ == "__main__":
    main()
