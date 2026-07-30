"""
Download the CSO Residential Property Price Index (HPM09) via the PxStat
JSON-stat 2.0 API and land it as a tidy parquet file for dbt to source.

No auth, no API key. Endpoint verified live during project research:
https://ws.cso.ie/public/api.restful/PxStat.Data.Cube_API.ReadDataset/HPM09/JSON-stat/2.0/en

This is the external benchmark used in mart_index_vs_cso to validate the
mix-adjusted index built from PPR data. The CSO series is NOT a like-for-like
comparison (different universe, hedonic-regression not stratified-median,
BER-matched, different VAT treatment) - see README "Why my index doesn't
equal the CSO's" section.
"""
import sys
import io
import json
from pathlib import Path

import requests
import pandas as pd

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

CSO_URL = (
    "https://ws.cso.ie/public/api.restful/PxStat.Data.Cube_API.ReadDataset/"
    "HPM09/JSON-stat/2.0/en"
)

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
OUT_PARQUET = RAW_DIR / "cso_rppi.parquet"
OUT_JSON = RAW_DIR / "cso_rppi_raw.json"


def jsonstat_to_frame(d: dict) -> pd.DataFrame:
    """Flatten a 3-dimensional JSON-stat 2.0 cube into a tidy long frame."""
    dim_ids = d["id"]  # e.g. ['STATISTIC', 'TLIST(M1)', 'C02803V03373']
    sizes = d["size"]  # e.g. [4, 257, 20]

    labels = []
    codes = []
    for dim_id in dim_ids:
        cat = d["dimension"][dim_id]["category"]
        # category["index"] gives code -> position; fall back to label order
        if "index" in cat:
            if isinstance(cat["index"], dict):
                ordered_codes = sorted(cat["index"], key=lambda k: cat["index"][k])
            else:
                ordered_codes = cat["index"]
        else:
            ordered_codes = list(cat["label"].keys())
        codes.append(ordered_codes)
        labels.append(cat.get("label", {}))

    values = d["value"]
    rows = []
    stat_codes, month_codes, region_codes = codes
    n_stat, n_month, n_region = sizes
    idx = 0
    for si, stat_code in enumerate(stat_codes):
        for mi, month_code in enumerate(month_codes):
            for ri, region_code in enumerate(region_codes):
                val = values[idx]
                idx += 1
                rows.append(
                    {
                        "statistic_code": stat_code,
                        "statistic_label": labels[0].get(stat_code, stat_code),
                        "month_code": month_code,
                        "month_label": labels[1].get(month_code, month_code),
                        "region_code": region_code,
                        "region_label": labels[2].get(region_code, region_code),
                        "value": val,
                    }
                )
    return pd.DataFrame(rows)


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Fetching {CSO_URL}")
    resp = requests.get(CSO_URL, timeout=60)
    resp.raise_for_status()
    OUT_JSON.write_bytes(resp.content)
    print(f"Wrote {OUT_JSON} ({len(resp.content):,} bytes)")

    d = json.loads(resp.content)
    print(f"label={d.get('label')!r} updated={d.get('updated')} size={d.get('size')}")

    df = jsonstat_to_frame(d)
    df.to_parquet(OUT_PARQUET, index=False)
    print(f"Wrote {OUT_PARQUET} ({len(df):,} rows)")


if __name__ == "__main__":
    main()
