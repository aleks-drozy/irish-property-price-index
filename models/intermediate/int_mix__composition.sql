{#
  Stratum's share of transactions per (region_scope, month) - the visual
  proof of the composition-shift mechanism behind mart_mix_shift.
#}

with stratified as (

    select * from {{ ref('int_transactions__stratified') }}

),

counts as (

    select
        region_scope,
        sale_month,
        stratum_key,
        count(*) as n
    from stratified
    group by 1, 2, 3

),

totals as (

    select
        region_scope,
        sale_month,
        sum(n) as total_n
    from counts
    group by 1, 2

)

select
    c.region_scope,
    c.sale_month,
    c.stratum_key,
    c.n,
    c.n * 1.0 / t.total_n as share
from counts c
join totals t
    on c.region_scope = t.region_scope
    and c.sale_month = t.sale_month
