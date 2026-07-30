{#
  Fixed weights + base-period median (the ratio denominator) per
  (region_scope, stratum, weight_variant). Two weighting schemes ship as
  separate index variants, per DECISIONS.md:
    - fixed_2010: stratum's share of transactions during the base period
      ({{ var('base_period_start') }} .. {{ var('base_period_end') }}) only.
    - fixed_fullsample: stratum's share of transactions across the whole
      sample period - reduces sensitivity to a noisy/small base period.
  Both variants use the SAME base-period median as the ratio denominator;
  only the weighting scheme differs (per plan: "only the weights differ").
  Weights are renormalised to sum to 1.0 within each (region_scope,
  weight_variant) - enforced by assert_weights_sum_to_one.sql.
#}

with stratified as (

    select * from {{ ref('int_transactions__stratified') }}

),

base_period_rows as (

    select *
    from stratified
    where date_of_sale between
        '{{ var("base_period_start") }}'::date and '{{ var("base_period_end") }}'::date

),

base_medians as (

    select
        region_scope,
        stratum_key,
        count(*) as base_n,
        median(price_eur_index_basis) as base_median_price
    from base_period_rows
    group by 1, 2

),

base_period_counts as (

    select
        region_scope,
        stratum_key,
        count(*) as stratum_txn_count
    from base_period_rows
    group by 1, 2

),

base_period_totals as (

    select region_scope, sum(stratum_txn_count) as total_txn_count
    from base_period_counts
    group by 1

),

fixed_2010_weights as (

    select
        c.region_scope,
        c.stratum_key,
        'fixed_2010' as weight_variant,
        c.stratum_txn_count * 1.0 / t.total_txn_count as weight
    from base_period_counts c
    join base_period_totals t using (region_scope)

),

fullsample_counts as (

    select
        region_scope,
        stratum_key,
        count(*) as stratum_txn_count
    from stratified
    group by 1, 2

),

fullsample_totals as (

    select region_scope, sum(stratum_txn_count) as total_txn_count
    from fullsample_counts
    group by 1

),

fixed_fullsample_weights as (

    select
        c.region_scope,
        c.stratum_key,
        'fixed_fullsample' as weight_variant,
        c.stratum_txn_count * 1.0 / t.total_txn_count as weight
    from fullsample_counts c
    join fullsample_totals t using (region_scope)

),

all_weights as (

    select * from fixed_2010_weights
    union all
    select * from fixed_fullsample_weights

)

select
    w.region_scope,
    w.stratum_key,
    w.weight_variant,
    w.weight,
    bm.base_n,
    bm.base_median_price
from all_weights w
left join base_medians bm
    on w.region_scope = bm.region_scope
    and w.stratum_key = bm.stratum_key
