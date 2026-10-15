"""Convert plot-digitizer output for Stieger et al. (2021) into pre/post
means and SDs for the MBSR and control groups (individual points digitized
from data/stieger2021_plot.jpeg, binned by x position into condition).
Values were then entered by hand into data/breathpubs_prepost.xlsx.
"""
from pathlib import Path

import pandas as pd

fname = Path(__file__).resolve().parent.parent / "data" / "stieger2021_digitized.csv"

df = pd.read_csv(fname, header=None, names=["x", "y"])
df.columns = ["x", "y"]
bins = [.5, 1.5, 2.5, 3.5, 4.5]
bin_names = ["CTL_pre", "MBSR_pre", "CTL_post", "MBSR_post"]
df["condition"] = pd.cut(df["x"], bins=bins, labels=bin_names, right=True, ordered=True)
stats = df.groupby("condition", observed=False)["y"].agg(["count", "mean", "std"])
print(stats.round(2))