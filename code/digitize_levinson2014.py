"""Convert plot-digitizer output for Levinson et al. (2014) Study 4 (Fig. 6)
into pre/post means and SDs for the BCT, n-back and no-training groups.
Points were digitized from data/levinson2014_plot.jpg; values were then
entered by hand into data/breathpubs_prepost.xlsx (rows flagged "values from digitization!").
"""
from pathlib import Path

import numpy as np
import pandas as pd

fname = Path(__file__).resolve().parent.parent / "data" / "levinson2014_digitized.csv"

df = pd.read_csv(fname, header=None, names=["bar","y"])

# bar0, bar3, bar6, etc are the low SEM points left-to-right on the figure
# bar1, bar4, bar7, etc are the mean points ...
# bar2, bar5, bar8, etc are the mean points ...
df["point_purpose"] = np.tile(["sem_lo", "mean", "sem_hi"], 6)
df["timepoint"] = np.tile(np.repeat(["pre", "post"], 3), 3)
df["training"] = np.repeat(["nback", "bct", "ctl"], 6)

summ = df.pivot(columns="point_purpose", index=["training","timepoint"], values="y"
    ).reindex(["nback", "bct", "ctl"], level="training"
    ).reindex(["pre","post"], level="timepoint")

summ["n"] = np.repeat([22, 20, 29], 2)

def sem2std(row):
    # take mean of hi/lo SEMs as SEM
    sem1 = abs(row["mean"] - row["sem_hi"])
    sem2 = abs(row["mean"] - row["sem_lo"])
    sem = np.mean([sem1, sem2])
    std = sem * np.sqrt(row["n"])
    return std

summ["std"] = summ.apply(sem2std, axis=1)

print(summ[["mean", "std"]].round(2))
