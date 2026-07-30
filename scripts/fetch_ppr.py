"""
Download the PSRA Residential Property Price Register "Download All" zip
and extract PPR-ALL.csv into data/raw/.

Source: https://www.propertypriceregister.ie (Property Services Regulatory
Authority). The PSRA does not edit or clean this data in any way - every
anomaly downstream in this project is genuine.

Windows encoding note (see project memory: windows-encoding-traps):
this script never decodes the CSV itself - it only streams bytes to disk.
Decoding happens in dbt via DuckDB's read_csv_auto(..., encoding='cp1252').
stdout here is guarded to avoid the default cp1252 console codec choking
on box-drawing / progress characters.
"""
import sys
import io
import hashlib
import zipfile
from pathlib import Path

import requests

# Guard stdout against Windows' default cp1252 console encoding.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")

PPR_URL = (
    "https://www.propertypriceregister.ie/website/npsra/ppr/npsra-ppr.nsf/"
    "Downloads/PPR-ALL.zip/$FILE/PPR-ALL.zip"
)

RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"
ZIP_PATH = RAW_DIR / "PPR-ALL.zip"
CSV_PATH = RAW_DIR / "PPR-ALL.csv"


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Fetching {PPR_URL}")
    try:
        resp = requests.get(PPR_URL, timeout=120)
        resp.raise_for_status()
    except requests.exceptions.SSLError as e:
        # civictech-ie has reported a misconfigured cert on this host.
        # Do NOT disable verification - surface the failure instead.
        print(
            "SSL verification failed. Per project policy this script will "
            "not disable certificate verification. If this is a known-bad "
            "cert, pin the correct CA bundle and re-run.",
            file=sys.stderr,
        )
        raise

    ZIP_PATH.write_bytes(resp.content)
    size = ZIP_PATH.stat().st_size
    sha256 = hashlib.sha256(resp.content).hexdigest()
    print(f"Wrote {ZIP_PATH} ({size:,} bytes, sha256={sha256})")

    with zipfile.ZipFile(ZIP_PATH) as z:
        names = z.namelist()
        print(f"Zip contains: {names}")
        z.extractall(RAW_DIR)

    if CSV_PATH.exists():
        csv_size = CSV_PATH.stat().st_size
        print(f"Extracted {CSV_PATH} ({csv_size:,} bytes)")
    else:
        print("WARNING: expected PPR-ALL.csv not found after extraction", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
