"""
Build the small, committed CI fixture from the real PPR-ALL.csv: a
reproducible stratified sample (~40k rows, evenly split across years) so the
fast `fixture` CI job exercises real data shapes and real data quality
quirks without downloading the full 18MB zip on every push.

Written with the exact same header line and cp1252 encoding as the source
file, so the dbt fixture path exercises the identical decode logic as the
full-data path.
"""
import sys
import io
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

import pandas as pd
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "raw" / "PPR-ALL.csv"
OUT = ROOT / "data" / "fixture" / "ppr_fixture.csv"

TARGET_ROWS = 40_000
SEED = 42

df = pd.read_csv(SRC, encoding="cp1252", dtype=str, keep_default_na=False)
dates = pd.to_datetime(df.iloc[:, 0], format="%d/%m/%Y", errors="coerce")
df["_year"] = dates.dt.year

years = sorted(df["_year"].dropna().unique())
per_year = max(1, TARGET_ROWS // len(years))

rng = np.random.default_rng(SEED)
parts = []
for y in years:
    grp = df[df["_year"] == y]
    n = min(per_year, len(grp))
    idx = rng.choice(grp.index.values, size=n, replace=False)
    parts.append(df.loc[idx])

sample = pd.concat(parts).drop(columns=["_year"])
sample = sample.sort_values(by=sample.columns[0], kind="stable")

# Deliberately keep a few known full-duplicate rows and a couple of
# extreme-price rows in the fixture so the dedupe / range tests have
# something real to catch, matching the full dataset's known quirks.
dup_mask = df.duplicated(keep=False)
dup_rows = df[dup_mask].drop(columns=["_year"]).head(20)
sample = pd.concat([sample, dup_rows]).drop_duplicates()

sample.to_csv(OUT, index=False, encoding="cp1252")
print(f"Wrote {OUT} ({len(sample):,} rows) from {len(df):,} source rows")
