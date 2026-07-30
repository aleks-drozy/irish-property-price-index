# DECISIONS

Non-obvious calls made while building this project, in the order they came
up, each with the real evidence behind it. Dates in Ireland/UTC.

---

## 2026-07-30 — Block 0 profiling findings (before any modelling)

Ran `DESCRIBE` / `SELECT DISTINCT` over every column of the live
`PPR-ALL.csv` (797,774 rows, downloaded 2026-07-30, sha256-logged by
`scripts/fetch_ppr.py`) before writing a single model. Findings that
changed the plan:

### Encoding is cp1252, not latin-1
The byte `\x80` in the raw file only decodes to `€` (U+20AC) under
Windows-1252. In `latin-1` (ISO-8859-1), `\x80` is an unassigned C1 control
character, not the euro sign. Verified both by direct byte inspection
(`b'\x80343,000.00'`) and by round-tripping through DuckDB's
`read_csv(..., encoding='cp1252')`, which produced the correct `€` glyph
(`hex(ord(c)) == '0x20ac'`). **Decision: read with `encoding='cp1252'`
everywhere** (`macros/ppr_source.sql`), not latin-1 as originally planned.

### Schema differs from the plan's assumption
Actual column order (verified via `DESCRIBE`):
`Date of Sale (dd/mm/yyyy), Address, County, Eircode, Price (€),
Not Full Market Price, VAT Exclusive, Description of Property,
Property Size Description`.

The postcode column is called **`Eircode`**, not `Postal Code`, and sits
**after** `County`, not before. Reading positionally
(`header=false, skip=1`, explicit `columns={...}` map) makes the model
immune to this regardless - see `macros/ppr_source.sql`.

### Property Size Description: the Tier-A/Tier-B gate, decided on real numbers
The plan's own rule: only stratify by size band if coverage is "≥40% and
reasonably stable over time," otherwise drop it and say so.

Measured coverage on the full 797,774-row dataset:

| Year | Coverage | Year | Coverage |
|---|---|---|---|
| 2010 | 25.30% | 2018 | 16.49% |
| 2011 | 16.01% | 2019 | 0.18% |
| 2012 | 12.51% | 2020 | 0.04% |
| 2013 | 12.88% | 2021 | 0.02% |
| 2014 | 12.42% | 2022 | 0.00% |
| 2015 | 12.70% | 2023 | 0.00% |
| 2016 | 13.77% | 2024 | 0.00% |
| 2017 | 17.01% | 2025 / 2026 | 0.00% |

Overall: **6.62% coverage** (52,845 / 797,774 rows non-blank). Never
reaches 40% in any year, and collapses to effectively zero from 2019
onward - filers apparently stopped supplying it. **Decision: Tier A only.**
Strata = `property_type x geo_bucket`, no size dimension. The seed
`size_band_map.csv` still exists and is still tested, but only feeds
`mart_data_quality`'s coverage-over-time chart, not the index. This
decay curve is exactly the evidence the plan asked for before locking
methodology - see `mart_data_quality`.

### Dublin district: no standalone postcode column exists
There is no PPR field that is just "Dublin 14." Two fallback sources, both
measured on the real data (Dublin-county rows only, n=249,744):

- **Eircode routing key** (first 3 chars, e.g. `D14`): 32.32% of Dublin
  rows have *any* Eircode at all (Eircodes only rolled out nationally from
  2015, so pre-2015 sales are structurally unfillable this way).
- **Regex-extracted "DUBLIN NN" from the free-text Address**: 49.10%
  coverage on its own, with some genuine parsing noise (a handful of
  matches like "Dublin 74" / "Dublin 91" that aren't real Dublin postal
  districts - Dublin only goes up to D24 plus D6W). These get zero-padded
  (`"1"` → `"01"`) and joined against `dublin_district_map.csv`, which only
  contains the 22 real codes; anything else falls through unmatched.
- **Combined (Eircode routing key OR address regex), non-overlapping**:
  **54.23%** of Dublin rows resolve to a real district.

**Decision:** try Eircode routing key first, fall back to the address
regex, and bucket anything else into `DUBLIN_UNKNOWN` - a genuine 5th
Dublin stratum per property type, not a silently dropped group. This
matches the plan's own contingency ("+ DUBLIN_UNKNOWN") and is implemented
in `models/intermediate/int_transactions__stratified.sql`.

### Price range and outliers
Full-dataset price range: **min €5,001, max €387,665,198**. 239 rows sit
above €20m - almost certainly data-entry errors (PSRA does not edit
submissions, so these are genuine, kept, and handled by winsorising the
price at the p1/p99 percentiles (`var('winsor_low_pct')`,
`var('winsor_high_pct')`) before it feeds any stratum median, rather than
being dropped. Medians are additionally much more robust to this kind of
outlier than means, which is part of why the index uses medians per
stratum, not means (the naive `headline_mean` variant is kept specifically
so this robustness argument is visible in the data, not just asserted).

### Duplicates: full-row equality, not (date, address, price)
The plan sketched deduping on `(date, address, price)`. Profiling showed
this tuple is **not** sufficiently unique: 2,184 rows share a
`(date, address, price)` value, but only 2,026 of those are fully
identical across all 9 raw columns. The other 158 are genuine distinct
sales - most commonly two different units in the same new development
sold on the same day at the same list price (same `Description of
Property` and `Not Full Market Price`/`VAT Exclusive` flags, different
`Address` suffix or genuinely identical `Address` text for a multi-unit
filing). **Decision: dedupe on a surrogate key hashed over all 9 raw
columns** (`transaction_id` in `stg_ppr__transactions`), so only
byte-identical rows collapse. On the full dataset this drops **1,072**
extra copies (rows with `_dupe_rank > 1` within their `transaction_id`
group) - the remaining rows are kept as genuinely distinct sales. This is
a deliberate, documented deviation from the original one-line sketch,
made because block-0 profiling is what the plan itself demanded before
locking the dedup rule.

### Irish-language and garbled description/size strings
Confirmed exactly as anticipated, plus two mangled-encoding variants not
anticipated:

`Description of Property`: `Second-Hand Dwelling house /Apartment`
(655,350), `New Dwelling house /Apartment` (142,375), `Teach/Árasán
Cónaithe Atháimhe` (45, Irish "second-hand"), `Teach/Árasán Cónaithe Nua`
(3, Irish "new"), and one single-row garbled variant `Teach/?ras?n
C?naithe Nua` (1 row - almost certainly a client-side encoding mismatch on
PSRA's end at the point of filing, not our decode: our own cp1252 read of
this row still produces `?` because the source byte itself is a literal
`?`, not a mis-decoded accented character).

`Property Size Description` similarly has two Irish variants (`níos mó
ná nó cothrom le 38 méadar cearnach agus níos lú ná 125 méadar cearnach`,
`n?os l? n? 38 m?adar cearnach`). All six distinct values (plus blank) are
enumerated in `seeds/property_type_map.csv` / `seeds/size_band_map.csv`.
`tests/assert_unmapped_descriptions_are_zero.sql` fails CI the day PSRA
adds a 7th value, which is the actual point of this test.

---

## Mix-adjustment methodology (confirmed, not changed from the plan)

Fixed-base-weight stratified median index:

```
Index(region, t) = 100 x sum_s [ w_s(region) x median_price(s, region, t) / median_price(s, region, base) ]
```

Two independent `region_scope` computations ship, not one index with a
region dimension bolted on: **NATIONAL** (strata = `property_type x
county_region_map` bucket, 8 strata, computed over every eligible
transaction nationwide) and **DUBLIN** (strata = `property_type x
dublin_district_map` bucket + `DUBLIN_UNKNOWN`, 10 strata, computed only
over Dublin-county transactions). A Dublin sale therefore contributes to
both series independently - once inside the national `DUBLIN` region
bucket, once inside its own Dublin district stratum. Each scope has its
own base weights, normalised to sum to 1.0 within that scope
(`tests/assert_weights_sum_to_one.sql`).

**Base period: 2010-01-01 to 2012-12-31** (three years, the earliest
available, chosen to (a) predate most of the post-crash compositional
recovery and (b) give a large enough n per stratum that the base-period
median itself isn't noisy - checked: even the smallest Dublin stratum,
`NEW_CITY_CENTRE`, has `base_n = 65` transactions over the three years).

**Two weighting variants ship** (`mixadj_fixed_2010`,
`mixadj_fixed_fullsample`), not the full five sketched in the plan.
**Cut, deliberately, per the plan's own explicit cut-line** ("drop
mixadj_chained and mixadj_untrimmed variants (-1h)"): `mixadj_chained`
(period-over-period re-weighting) and `mixadj_untrimmed` (same as
fixed_fullsample but skipping the winsorisation step) were not built, to
keep the time budget on the tests/docs/write-up, which the plan calls out
as the actual signal. `headline_mean` and `headline_median` (unstratified,
naive) ship as the contrast series.

**Missing-cell handling:** if a stratum has no valid median for a given
month (`n < min_stratum_n = 30`, see `int_strata__period_medians.sql`) or
no valid base-period median, it drops out of that month's weighted sum and
the remaining strata's weights are renormalised (divided by their own sum,
not by 1.0) rather than left to silently understate the index. On the
full dataset this renormalisation is rarely invoked - the default
`min_stratum_n=30` produces a fully continuous 2010-01 → 2026-07 series
for both `region_scope`s with zero gaps
(`tests/assert_index_month_series_continuous.sql` passes on real data).
It matters more on the small CI fixture (1/20th scale), where the fixture
job overrides `min_stratum_n` down to 2 - see CI section below.

**Region-bucket definitions** (`seeds/county_region_map.csv`):
`GDA_COMMUTER` = Kildare, Meath, Wicklow (the NTA's Greater Dublin Area
commuter counties, excluding Dublin itself, which is its own bucket).
`OTHER_URBAN` = the three other county-borough cities: Cork, Galway,
Limerick, Waterford. `REST_OF_IRELAND` = the remaining 18 counties. This
is a methodological choice, not a PSRA-provided grouping - a reasonable
alternative (e.g. folding Louth into GDA_COMMUTER) would shift the
national strata slightly; not expected to change the headline finding's
direction.

**Dublin district groups** (`seeds/dublin_district_map.csv`): `CITY_CENTRE`
(D01/D02/D07/D08), `NORTH_DUBLIN` (D03/D05/D09/D11/D13/D17), `SOUTH_DUBLIN`
(D04/D06/D06W/D14/D16/D18), `WEST_DUBLIN` (D10/D12/D15/D20/D22/D24) - a
standard informal grouping of Dublin postal districts by broad geography,
not an official CSO/NTA taxonomy.

---

## The headline finding (computed from `dbt build` on the real 797,774-row dataset, 2026-07-30)

**Full build is green**: 91/91 tests pass with `--warn-error`, both
`region_scope`s produce a continuous month series from 2010-01 to 2026-07
(199 months) with the default `min_stratum_n=30`. 756,288 of 797,774 raw
rows are in-index (1,072 exact-duplicate copies dropped, 40,414
Not-Full-Market-Price sales excluded, zero unmapped descriptions, zero
invalid prices).

Comparing `headline_median` (naive, unstratified) against
`mixadj_fixed_fullsample` (the mix-adjusted index), both on the same
100-base:

- **National**: `headline_median` runs **+2.22 index points above**
  `mixadj_fixed_fullsample` on average across the full series (min -9.48,
  max +15.89).
- **Dublin**: `headline_median` runs **-3.91 index points below**
  `mixadj_fixed_fullsample` on average (min -16.43, max +8.43).

**The gap is opposite in sign between Dublin and the national series** -
this confirms the hypothesis posed in the plan, not by assumption but by
the actual `mart_price_index_monthly` output. In Dublin, looking at the
raw median alone understates price growth relative to the mix-adjusted
measure; nationally, it overstates it. The most direct reading: Dublin's
transaction mix has shifted toward relatively higher-priced strata over
time (pushing the raw median up faster than same-stratum prices actually
grew), while nationally the mix has shifted slightly toward
lower-average-price strata (pulling the raw median down relative to
same-stratum growth) - see `mart_mix_shift` for the underlying composition
series.

**31 individual months (13 national, 18 Dublin, out of 187 months with a
year-on-year comparison available) have `headline_median` YoY growth and
`mixadj_fixed_fullsample` YoY growth moving in opposite directions** -
i.e. the naive series says prices fell year-on-year while the mix-adjusted
series says they rose, or vice versa. The largest single swing:
**National, 2013-06**: headline YoY **-6.28%** vs mix-adjusted YoY
**+6.77%** (a 13.05-point gap) - right at the tail end of the post-crash
trough, plausibly a period where a shrinking pool of higher-value sales
pulled the stratified measure up while a compositional shift toward
distressed/lower-value sales pulled the raw median down. Second largest:
**Dublin, 2016-02**: headline YoY **-5.20%** vs mix-adjusted YoY **+5.28%**
(a 10.47-point gap).

This was written after the pipeline ran, from the actual mart output, per
the plan's explicit instruction not to pre-draft the finding.

---

## CSO RPPI validation (`mart_index_vs_cso`)

Own `mixadj_fixed_fullsample` vs CSO HPM09 (statistic `HPM09C01`, region
codes `-`=National-all and `05`=Dublin-all), both rebased to their first
common month:

- **Level correlation**: National 0.9885, Dublin 0.9875 (both series track
  the same broad trend closely, as expected - both are, ultimately,
  measuring the same underlying market).
- **Year-on-year growth-rate correlation** (the plan's requested metric,
  since level correlation on two trending series is close to guaranteed
  high regardless of method quality): **National 0.8602, Dublin 0.7288**
  - meaningfully lower than the level correlation, and lower for Dublin
    than National. This is the honest, expected result: differencing
    removes the shared trend and leaves the two methods' genuine
    disagreements about month-to-month composition and hedonic effects,
    and Dublin's smaller sample per stratum makes it noisier.
- **Mean absolute level gap**: National 13.28 index points, Dublin 7.48
  index points, over the common period.

**Why they don't match exactly, framed as expected rather than a defect:**
the CSO's HPM09 uses a rolling 12-month **hedonic regression** matched to
BER data (floor area, dwelling type, Small Area deprivation index) on
stamp-duty returns - a record-level join this project cannot perform
because PPR carries none of those covariates. The CSO universe also
excludes non-household and non-market purchases and self-builds
differently than the NFMP flag does here, and its VAT treatment of new
builds is not necessarily the flat 13.5% gross-up used here. Given all
that, a 0.86 YoY correlation nationally is a reasonable directional
validation of a purely-SQL, purely-categorical stratified index against
an independently-built hedonic one - not equivalence, and not claimed as
such anywhere in the README.

---

## Scope cuts taken (all pre-authorised by the plan's own cut-line list)

- Dropped `mixadj_chained` and `mixadj_untrimmed` index variants (see
  mix-adjustment section above).
- Dashboard: see README for what shipped (Evidence.dev vs fallback -
  decided and recorded there once the build was attempted).
- CSO comparison uses the live PxStat API (not cut to a static CSV) -
  the live fetch worked cleanly first try, so no need to take this cut.

## Explicitly out of scope this pass (per the plan)

Address normalisation/geocoding beyond the Dublin-district regex,
full Eircode parsing, Small Area joins, incremental materialisation, any
hedonic model, any per-property page.
