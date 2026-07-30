"""
Export the mart parquet files (already produced by `dbt run-operation
export_marts`) to small JSON files the static dashboard reads directly -
no build step, no bundler, no Node dependency. Run after export_marts.
"""
import sys
import io
import json
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

import duckdb

ROOT = Path(__file__).resolve().parent.parent
MARTS_DIR = ROOT / ".marts_export"
OUT_DIR = ROOT / "docs" / "dashboard" / "data"

MARTS = [
    "mart_price_index_monthly",
    "mart_mix_shift",
    "mart_index_vs_cso",
    "mart_transaction_volumes",
    "mart_data_quality",
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()
    for mart in MARTS:
        parquet_path = MARTS_DIR / f"{mart}.parquet"
        if not parquet_path.exists():
            print(f"SKIP {mart}: {parquet_path} not found", file=sys.stderr)
            continue
        rows = con.execute(f"select * from read_parquet('{parquet_path.as_posix()}')").fetchdf()
        # dates -> ISO strings for JSON
        for col in rows.columns:
            if str(rows[col].dtype).startswith("datetime"):
                rows[col] = rows[col].dt.strftime("%Y-%m-%d")
        out_path = OUT_DIR / f"{mart}.json"
        out_path.write_text(rows.to_json(orient="records"), encoding="utf-8")
        print(f"Wrote {out_path} ({len(rows):,} rows)")


if __name__ == "__main__":
    main()
