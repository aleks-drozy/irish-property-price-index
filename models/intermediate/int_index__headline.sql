{#
  Naive, unstratified mean & median price index at the same grain as the
  mix-adjusted variants, indexed to the same base period. This is the
  contrast series - the whole point of the project is showing where it
  diverges from the mix-adjusted line.
#}

with stratified as (

    select * from {{ ref('int_transactions__stratified') }}

),

base_period as (

    select
        region_scope,
        avg(price_eur_index_basis) as base_mean,
        median(price_eur_index_basis) as base_median
    from stratified
    where date_of_sale between
        '{{ var("base_period_start") }}'::date and '{{ var("base_period_end") }}'::date
    group by 1

),

period_agg as (

    select
        region_scope,
        sale_month,
        avg(price_eur_index_basis) as mean_price,
        median(price_eur_index_basis) as median_price,
        count(*) as n
    from stratified
    group by 1, 2

),

mean_series as (

    select
        p.region_scope,
        p.sale_month,
        'headline_mean' as index_variant,
        100.0 * p.mean_price / b.base_mean as index_value,
        cast(null as double) as effective_weight_sum,
        p.n as n_transactions_used,
        cast(null as integer) as n_strata_used
    from period_agg p
    join base_period b using (region_scope)

),

median_series as (

    select
        p.region_scope,
        p.sale_month,
        'headline_median' as index_variant,
        100.0 * p.median_price / b.base_median as index_value,
        cast(null as double) as effective_weight_sum,
        p.n as n_transactions_used,
        cast(null as integer) as n_strata_used
    from period_agg p
    join base_period b using (region_scope)

)

select * from mean_series
union all
select * from median_series
