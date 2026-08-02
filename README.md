# Irish Property Price Index: mix-adjusted vs headline

A dbt + DuckDB analytics-engineering project on the PSRA Residential
Property Price Register (797,774 sale records, Ireland, 2010–2026): a
fixed-base-weight **stratified-median price index**, built entirely in
SQL, that shows where a naive headline median diverges from a
composition-adjusted measure, and how that divergence differs between
Dublin and the rest of the country.

**[Dashboard →](https://aleks-drozy.github.io/irish-property-price-index/dashboard/)** · **[dbt docs / lineage DAG →](https://aleks-drozy.github.io/irish-property-price-index/dbt/)**: both built from the real 797,774-row dataset. Deployed via GitHub Pages from `docs/`; to run them locally instead, open via a local static file server (`fetch()` needs `http://`, not `file://`; see "Running it locally").

---

## The finding (real numbers, computed from a full `dbt build` on 2026-07-30)

Comparing the naive `headline_median` index against the
`mixadj_fixed_fullsample` (mix-adjusted) index, both based to 100 over
2010–2012:

- **Nationally, the headline median runs +2.22 index points above the
  mix-adjusted index on average.** Looking at the raw national median
  alone slightly *overstates* price growth relative to the mix-adjusted
  measure.
- **In Dublin, the headline median runs 3.91 index points *below* the
  mix-adjusted index on average: the opposite sign.** In Dublin, the raw
  median *understates* price growth relative to the mix-adjusted measure.
- **31 individual months (18 in Dublin, 13 nationally, out of 187 months
  with a year-on-year comparison) have the headline and mix-adjusted
  series moving in opposite directions**: one says prices fell
  year-on-year, the other says they rose. The largest single swing:
  **National, June 2013**: headline YoY **-6.28%** vs mix-adjusted YoY
  **+6.77%**, a 13.05-point gap, right at the tail of the post-crash
  trough. Second largest: **National, April 2014**: headline YoY
  **-3.45%** vs mix-adjusted YoY **+8.06%**, an 11.51-point gap.

This isn't a "gotcha" about a broken headline number: both series
correlate at 0.99+ in levels over the full period. It's the standard
Simpson's-paradox mechanism in property data: *what* gets sold shifts
composition over time (see the "mix shift" chart in the dashboard), and a
raw median conflates that shift with genuine within-segment price
movement. The point of building the stratified index is to separate the
two, and the two regions turn out to disagree about which direction the
conflation runs.

Full derivation, every intermediate number, and the reasoning behind every
methodological choice are in **[DECISIONS.md](./DECISIONS.md)**, written
*after* the pipeline ran, from the actual mart output, not drafted in
advance.

---

## Why a stratified index, not a hedonic regression

The CSO's own official RPPI uses a rolling 12-month hedonic regression,
which it can run because it matches stamp-duty returns to BER
(Building Energy Rating) data at record level: floor area, dwelling type,
Small Area deprivation index. **PPR itself carries none of those
covariates.** A hedonic fit on PPR alone would regress price on the same
handful of categorical fields a stratified index already uses: same
information, more machinery, more assumptions, worse explainability. With
a small, purely categorical covariate set, stratification and a saturated
dummy regression are close to equivalent anyway. Stratification is also
expressible entirely in SQL, which is the point of a dbt portfolio piece.

```
Index(region, t) = 100 × Σ_s [ w_s(region) × median_price(s, region, t) / median_price(s, region, base) ]
```

- **Two independent region scopes**, not one index with a region column
  bolted on: **NATIONAL** (8 strata: property_type × 4 region buckets:
  Dublin / GDA commuter counties / other city counties / rest of Ireland)
  and **DUBLIN** (10 strata: property_type × 5 Dublin district groups,
  including a `DUBLIN_UNKNOWN` bucket for addresses that can't be placed
  in a district; see below).
- **Base period 2010-01 to 2012-12**, fixed weights = each stratum's share
  of transactions in that period (`mixadj_fixed_2010`) or across the whole
  sample (`mixadj_fixed_fullsample`, the primary series).
- **Medians, not means**, per stratum: the naive `headline_mean` variant
  ships alongside specifically so this robustness argument is visible in
  the data, not just asserted.
- Not stratified by property size: `Property Size Description` coverage
  is **6.62% overall and collapses to ~0% from 2019 onward** on the real
  data (measured, not assumed, before deciding). Full table in
  DECISIONS.md and the "Data quality" panel of the dashboard.

---

## Data sources

- **Primary**: [PSRA Residential Property Price Register](https://www.propertypriceregister.ie/website/npsra/pprweb.nsf/page/ppr-home-en):
  "Download All" zip, refetched by `scripts/fetch_ppr.py`. 797,774 rows
  as of the 2026-07-30 export. The PSRA does not edit this data in any
  way, so every anomaly documented here (duplicates, outliers, garbled
  Irish-language strings) is genuine, not a scraping artefact. **PSRA
  attribution required on reuse**: given here and in every place the
  dashboard shows the data.
- **Validation benchmark**: [CSO Residential Property Price Index (HPM09)](https://www.cso.ie/en/methods/prices/residentialpropertypriceindex/)
  via the PxStat JSON-stat API, no auth required, refetched by
  `scripts/fetch_cso_rppi.py`.

---

## Real data quirks handled (and why each matters)

| Quirk | Evidence | Handling |
|---|---|---|
| CP1252 encoding, not UTF-8 or latin-1 | `\x80` only decodes to `€` under cp1252; confirmed by byte inspection | `read_csv(..., encoding='cp1252')` everywhere |
| Schema differs from common assumption | Real column order: `..., County, Eircode, Price (€), ...`; postcode column is `Eircode`, after `County`, not before | Positional read (`header=false, skip=1`, explicit column map), immune to header text entirely |
| `Property Size Description` sparsely populated | Measured: 6.62% overall, collapsing to ~0% from 2019 | Not used to stratify the index (Tier A only); tracked in `mart_data_quality` |
| Duplicate rows | 2,026 rows are byte-identical across all 9 columns; a further 158 share `(date, address, price)` but are genuinely distinct sales | Dedupe on a full-row surrogate key, not `(date, address, price)`; 1,072 extra copies dropped |
| County / district embedded in free text | No standalone Dublin-district column exists; Eircode routing key covers 32.3% of Dublin rows, address regex a further chunk, combined 54.2% | Eircode routing key → address regex fallback → `DUBLIN_UNKNOWN` (not silently dropped) |
| `Not Full Market Price = Yes` rows aren't arm's-length sales | PSRA site | Excluded from the index, kept + flagged in `mart_data_quality` |
| New-dwelling prices are VAT-exclusive (13.5%) | PSRA site | Grossed up ×1.135 to compare like-for-like with second-hand sales |
| Irish-language + garbled filing variants | 6 distinct property-type strings, 6 distinct size strings, incl. 2 mangled-encoding one-row anomalies | Enumerated in `seeds/property_type_map.csv` / `size_band_map.csv`; `assert_unmapped_descriptions_are_zero` fails CI if PSRA adds a 7th |
| Price outliers | Real range €5,001–€387.7m; 239 rows >€20m | Winsorised at p1/p99 before feeding any stratum median, never dropped |

---

## Validation against the CSO's official index

`mart_index_vs_cso` compares `mixadj_fixed_fullsample` against CSO HPM09,
both rebased to their first common month:

| | National | Dublin |
|---|---|---|
| Level correlation | 0.9885 | 0.9875 |
| **YoY growth-rate correlation** | **0.8602** | **0.7288** |
| Mean absolute level gap (index pts) | 13.28 | 7.48 |

**Why it doesn't match exactly, and why that's expected**: the CSO's
universe excludes non-household and non-market purchases differently than
the `Not Full Market Price` flag used here; its method is a 12-month
rolling hedonic regression, not a fixed-weight stratified median; it's
matched to BER data this project has no record-level access to; and its
VAT treatment of new builds isn't necessarily the flat 13.5% gross-up used
here. A 0.86 national YoY correlation between two independently-built,
methodologically-different indices over the same market is a reasonable
directional validation, not claimed as equivalence anywhere in this
project.

---

## Project structure

```
seeds/                    property_type_map, size_band_map, county_region_map, dublin_district_map
models/
  staging/                stg_ppr__transactions, stg_cso__rppi  (1:1 with source, positional, typed)
  intermediate/           cleaning, dedup, VAT gross-up, stratification, base weights, period medians,
                           mix-adjusted + headline index calculation, mix composition
  marts/                  mart_price_index_monthly (dashboard primary), mart_mix_shift,
                           mart_index_vs_cso, mart_transaction_volumes, mart_data_quality
tests/                    4 singular tests (weights sum to 1, no thin strata in the index,
                           continuous month series, zero unmapped descriptions) + 69 generic tests
scripts/                  fetch_ppr.py, fetch_cso_rppi.py, build_fixture.py, export_dashboard_data.py
docs/dashboard/           static, dependency-free dashboard (Overview / Mix shift / Method / Validation)
data/fixture/             ~40k-row stratified sample of the real data, committed, used by fast CI
.github/workflows/        build.yml: fixture job (every push) + full job (weekly + manual)
```

## Running it locally

```bash
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt      # Windows
$env:DBT_PROFILES_DIR = "."

.venv\Scripts\python scripts\fetch_ppr.py            # ~18MB download from propertypriceregister.ie
.venv\Scripts\python scripts\fetch_cso_rppi.py        # ~110KB, no auth

.venv\Scripts\dbt deps
.venv\Scripts\dbt build --warn-error                  # 91/91 nodes pass (14 models, 4 seeds, 73 data tests), ~2 min on the full 797k rows

.venv\Scripts\dbt run-operation export_marts
.venv\Scripts\python scripts\export_dashboard_data.py
# open docs/dashboard/index.html via any static file server (fetch() needs http://, not file://)
```

Fast CI-style run against the committed fixture instead of the full
download:

```bash
$env:PPR_USE_FIXTURE = "true"
.venv\Scripts\dbt build --warn-error --vars '{min_stratum_n: 2}'
```

(`min_stratum_n` is scaled down for the fixture only: it's a ~1/20 sample
of the real data, so its smallest strata don't reliably clear the
production threshold of 30 every month. The full weekly CI job uses the
real default. See DECISIONS.md.)

---

## Roadmap

- **Optional upgrade, not required**: swap the static dashboard for
  Evidence.dev. The current build uses a dependency-free static page,
  which is a deliberate, documented fallback rather than a placeholder;
  see DECISIONS.md for the trade-off.
