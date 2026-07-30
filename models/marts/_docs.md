{% docs mix_adjustment_methodology %}

## Mix-adjusted stratified-median index

```
Index(region, t) = 100 x sum_s [ w_s(region) x median_price(s, region, t) / median_price(s, region, base) ]
```

- `region` is one of two independent computations: `DUBLIN` (10 strata:
  property_type x Dublin district) or `NATIONAL` (8 strata: property_type x
  region bucket).
- `w_s(region)` is a **fixed** weight - stratum `s`'s share of transactions
  during either the 2010-2012 base period (`mixadj_fixed_2010`) or the
  whole sample period (`mixadj_fixed_fullsample`) - normalised to sum to
  1.0 within each region_scope.
- `median_price(s, region, t)` is the median of `price_eur_index_basis`
  (winsorised at p1/p99, VAT-grossed-up for new builds) for stratum `s` in
  month `t`. NULL if that cell has fewer than `min_stratum_n` (default 30)
  transactions - `int_strata__period_medians.sql`.
- If a stratum is missing for a given month, the remaining weights
  renormalise (divide by their own sum, not 1.0) rather than silently
  understating the index.

Why stratification instead of a hedonic regression: PPR has no floor
area, bedroom count, BER rating, or dwelling subtype - the covariates a
hedonic model needs. The CSO's own RPPI can run a hedonic only because it
matches stamp-duty returns to BER data at record level, a join this
project cannot perform on PPR alone. With a small, purely-categorical
covariate set, stratification and a saturated dummy regression are
near-equivalent, so the extra machinery buys nothing - and stratification
is expressible entirely in SQL, which is the point of a dbt project.

Full reasoning, the real coverage numbers behind the Tier-A/Tier-B
decision, and the computed headline finding are in `DECISIONS.md` at the
repo root.

{% enddocs %}
