{#
  Median price and transaction count per (region_scope, stratum, month).
  n < {{ var('min_stratum_n') }} => median_price is NULL, never allowed to
  feed a published index point (see assert_no_thin_strata_in_index.sql).
#}

with stratified as (

    select * from {{ ref('int_transactions__stratified') }}

),

agg as (

    select
        region_scope,
        stratum_key,
        sale_month,
        count(*) as n,
        median(price_eur_index_basis) as median_price
    from stratified
    group by 1, 2, 3

)

select
    region_scope,
    stratum_key,
    sale_month,
    n,
    case when n >= {{ var('min_stratum_n') }} then median_price else null end as median_price
from agg
