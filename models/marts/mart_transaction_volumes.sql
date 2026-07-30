{#
  Grain: month x county. Raw volumes and medians (all arm's-length sales,
  i.e. exclusion_reason is null except for the not_full_market_price
  exclusion which is genuinely non-market and belongs in
  mart_data_quality, not here) plus year-over-year change.
#}

with cleaned as (

    select *
    from {{ ref('int_transactions__cleaned') }}
    where exclusion_reason is null

),

monthly as (

    select
        sale_month,
        county,
        count(*) as n_transactions,
        median(price_eur_index_basis) as median_price
    from cleaned
    group by 1, 2

),

with_yoy as (

    select
        m.*,
        lag(m.n_transactions, 12) over (partition by m.county order by m.sale_month) as n_transactions_yoy_ago,
        lag(m.median_price, 12) over (partition by m.county order by m.sale_month) as median_price_yoy_ago
    from monthly m

)

select
    {{ dbt_utils.generate_surrogate_key(['sale_month', 'county']) }} as transaction_volume_id,
    sale_month,
    county,
    n_transactions,
    round(median_price, 2) as median_price,
    case
        when n_transactions_yoy_ago is not null and n_transactions_yoy_ago > 0
        then round(100.0 * (n_transactions - n_transactions_yoy_ago) / n_transactions_yoy_ago, 2)
    end as n_transactions_yoy_pct,
    case
        when median_price_yoy_ago is not null and median_price_yoy_ago > 0
        then round(100.0 * (median_price - median_price_yoy_ago) / median_price_yoy_ago, 2)
    end as median_price_yoy_pct
from with_yoy
