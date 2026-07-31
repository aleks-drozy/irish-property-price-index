"""
Build the small, committed CI fixture from the real PPR-ALL.csv: a
reproducible stratified sample (~40k rows, evenly split across years) so the
fast `fixture` CI job exercises real data shapes and real data quality
quirks without downloading the full 18MB zip on every push.

Written with the exact same header line and cp1252 encoding as the source
file, so the dbt fixture path exercises the identical decode logic as the
full-data path.

Privacy: the fixture is committed to a public repo, so the two columns that
identify individual properties - Address and Eircode - are replaced with
synthetic values after sampling. Everything the pipeline actually consumes
from those columns is preserved:
  - Address is only used downstream for the "DUBLIN NN" postal-district
    regex in int_transactions__stratified.sql, so any district token the
    real address contained (including invalid ones like "DUBLIN 74", which
    exercise the fall-through-to-DUBLIN_UNKNOWN path) is re-embedded
    verbatim in the synthetic address.
  - Eircode is only used downstream for its first-3-character routing key
    (and only 'D__' keys resolve to a district), so the real routing key is
    kept and only the unique 4-character identifier is replaced.
All other columns (date, county, price, NFMP, VAT, description, size) are
kept byte-identical - the tests depend on them.

Duplicates: exact full-row duplicates are a real quirk of the PPR export
that int_transactions__cleaned must catch, but anonymisation makes every
base row unique (each synthetic address embeds a per-row sequence number).
So a fixed number of rows are deliberately duplicated AFTER anonymisation,
and the script asserts the written file contains >0 full-row duplicates so
the dedupe path can never silently stop being exercised again.
"""
import re
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
N_INJECTED_DUPLICATES = 20
SEED = 42

# Same pattern as int_transactions__stratified.sql applies to the address.
DISTRICT_RE = re.compile(r"DUBLIN[ ]*([0-9]{1,2}W?)\b")
# Real Eircode character set (no B/G/I/J/L/M/O/Q/S/U/Z).
EIRCODE_CHARS = list("ACDEFHKNPRTVWXY0123456789")

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
sample = sample.sort_values(by=sample.columns[0], kind="stable").reset_index(drop=True)

addr_col, county_col, eircode_col = sample.columns[1], sample.columns[2], sample.columns[3]


def synthetic_address(seq: int, real_address: str, county: str) -> str:
    """Unique synthetic address preserving only the Dublin-district token."""
    m = DISTRICT_RE.search(real_address.upper())
    suffix = f"DUBLIN {m.group(1)}" if m else county.upper()
    return f"{seq} FIXTURE STREET, SAMPLETOWN, {suffix}"


def synthetic_eircode(real_eircode: str) -> str:
    """Keep the (non-identifying) 3-char routing key; replace the rest."""
    trimmed = real_eircode.strip().upper()
    if len(trimmed) <= 3:
        return trimmed
    unique_part = "".join(rng.choice(EIRCODE_CHARS, size=4))
    return trimmed[:3] + unique_part


sample[addr_col] = [
    synthetic_address(i + 1, a, c)
    for i, (a, c) in enumerate(zip(sample[addr_col], sample[county_col]))
]
sample[eircode_col] = [synthetic_eircode(e) for e in sample[eircode_col]]

# Deliberately duplicate a few anonymised rows so the fixture exercises the
# full-row dedupe path in int_transactions__cleaned (the real export's known
# exact-duplicate quirk). Injected AFTER anonymisation: copies are byte-
# identical, so they collapse to the same surrogate key downstream.
dup_positions = rng.choice(len(sample), size=N_INJECTED_DUPLICATES, replace=False)
sample = pd.concat([sample, sample.iloc[sorted(dup_positions)]], ignore_index=True)

sample.to_csv(OUT, index=False, encoding="cp1252")

# Regression guard: the written file must contain full-row duplicates, or
# the fast CI job's dedupe coverage has silently regressed again.
check = pd.read_csv(OUT, encoding="cp1252", dtype=str, keep_default_na=False)
n_dups = int(check.duplicated().sum())
assert n_dups > 0, f"{OUT} contains no full-row duplicates; dedupe path untested"
assert len(check) == len(sample), f"row count mismatch after round-trip: {len(check)} != {len(sample)}"

print(
    f"Wrote {OUT} ({len(sample):,} rows, {n_dups} full-row duplicate rows, "
    f"addresses/eircodes synthetic) from {len(df):,} source rows"
)
