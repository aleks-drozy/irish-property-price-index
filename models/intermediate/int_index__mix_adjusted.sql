{#
  Index(region_scope, t) = 100 x sum_s [ w_s x median_s,t / base_median_s ]

  If a stratum has no valid median for a given month (n < min_stratum_n,
  see int_strata__period_medians) or no valid base-period median, it drops
  out of that month's sum and the remaining weights are renormalised
  (divided by their own sum rather than 1.0) so a temporarily-thin stratum
  doesn't silently understate the index. This only happens in the sparsest
  early-Dublin-district-x-NEW cells; assert_no_thin_strata_in_index.sql
  proves no n<30 cell contributes un-renormalised.
#}

with joined as (

    select
        bw.region_scope,
        bw.weight_variant as index_variant,
        pm.sale_month,
        bw.stratum_key,
        bw.weight,
        bw.base_median_price,
        pm.median_price,
        pm.n
    from {{ ref('int_strata__base_weights') }} bw
    join {{ ref('int_strata__period_medians') }} pm
        on bw.region_scope = pm.region_scope
        and bw.stratum_key = pm.stratum_key
    where bw.base_median_price is not null
      and pm.median_price is not null

),

agg as (

    select
        region_scope,
        index_variant,
        sale_month,
        sum(weight) as effective_weight_sum,
        sum(weight * median_price / base_median_price) as weighted_ratio_sum,
        sum(n) as n_transactions_used,
        count(*) as n_strata_used
    from joined
    group by 1, 2, 3

)

select
    region_scope,
    index_variant,
    sale_month,
    100.0 * weighted_ratio_sum / effective_weight_sum as index_value,
    effective_weight_sum,
    n_transactions_used,
    n_strata_used
from agg
