"""Draw the screening calibration set: 40 records both reviewers label before the real screen.

Half come from records an S1 search ("breath counting task") found, so the set has real
includes to calibrate on; half from the rest. The 8 seed records are left out. Fixed seed,
so the draw is reproducible.

    uv run code/search/make_calibration_set.py

Writes derivatives/search/calibration_set.csv (ASReview-readable, no labels).
"""

from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
SEARCH = ROOT / "derivatives" / "search"
SEED = 20261015
N_PER_STRATUM = 20

cand = pd.read_csv(SEARCH / "candidates_asreview.csv", dtype=str)
cand = cand[cand["included"].isna()]
s1 = cand["sources"].str.contains(r"(?:^|;)\w+:S1(?:;|$)")
sample = pd.concat(
    [
        cand[s1].sample(N_PER_STRATUM, random_state=SEED),
        cand[~s1].sample(N_PER_STRATUM, random_state=SEED),
    ]
).sample(frac=1, random_state=SEED)  # shuffle so the strata aren't in blocks
columns = ["title", "abstract", "authors", "year", "doi", "url", "native_id"]
sample[columns].to_csv(SEARCH / "calibration_set.csv", index=False, lineterminator="\n")
print(f"{len(sample)} records ({s1.sum()} S1 hits in the pool) -> calibration_set.csv")
