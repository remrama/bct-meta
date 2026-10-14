import pandas as pd

fname = "/Users/remy/Google Drive/projects/breathtmr/strieger_data.csv"

df = pd.read_csv(fname, header=None, names=["x", "y"])
df.columns = ["x", "y"]
bins = [.5, 1.5, 2.5, 3.5, 4.5]
bin_names = ["CTL_pre", "MBSR_pre", "CTL_post", "MBSR_post"]
df["condition"] = pd.cut(df["x"], bins=bins, labels=bin_names, right=True, ordered=True)
stats = df.groupby("condition")["y"].agg(["count", "mean", "std"])
print(stats.round(2))