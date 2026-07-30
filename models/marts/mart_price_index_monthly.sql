{#
  DASHBOARD PRIMARY. Grain: sale_month x region_scope x index_variant.
  Five columns of index_variant: headline_mean, headline_median,
  fixed_2010, fixed_fullsample (renamed mixadj_* below for clarity), all
  based to 100 over {{ var('base_period_start') }}..{{ var('base_period_end') }}.
#}

with mix_adjusted as (

    select
        region_scope,
        case index_variant
            when 'fixed_2010' then 'mixadj_fixed_2010'
            when 'fixed_fullsample' then 'mixadj_fixed_fullsample'
            else index_variant
        end as index_variant,
        sale_month,
        index_value,
        n_transactions_used,
        n_strata_used
    from {{ ref('int_index__mix_adjusted') }}

),

headline as (

    select
        region_scope,
        index_variant,
        sale_month,
        index_value,
        n_transactions_used,
        n_strata_used
    from {{ ref('int_index__headline') }}

),

unioned as (

    select * from mix_adjusted
    union all
    select * from headline

)

select
    {{ dbt_utils.generate_surrogate_key(['region_scope', 'index_variant', 'sale_month']) }} as price_index_id,
    region_scope,
    index_variant,
    sale_month,
    round(index_value, 4) as index_value,
    n_transactions_used,
    n_strata_used
from unioned
