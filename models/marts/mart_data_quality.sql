{#
  Grain: month. Rows in vs excluded (by reason, never silently dropped) and
  Property Size Description coverage over time - the evidence for the
  Tier-A-only stratification decision in DECISIONS.md (coverage collapses
  from ~12-25% in 2010-2018 to ~0% from 2019 onward on the full dataset).
#}

with cleaned as (

    select * from {{ ref('int_transactions__cleaned') }}

),

by_month as (

    select
        sale_month,
        count(*) as n_total,
        count(*) filter (where exclusion_reason is null) as n_included,
        count(*) filter (where exclusion_reason = 'exact_duplicate') as n_excluded_exact_duplicate,
        count(*) filter (where exclusion_reason = 'not_full_market_price') as n_excluded_not_full_market_price,
        count(*) filter (where exclusion_reason = 'unmapped_property_type') as n_excluded_unmapped_property_type,
        count(*) filter (where exclusion_reason = 'invalid_price') as n_excluded_invalid_price,
        count(*) filter (where property_size_description is not null and property_size_description != '') as n_with_size_description
    from cleaned
    group by 1

)

select
    {{ dbt_utils.generate_surrogate_key(['sale_month']) }} as data_quality_id,
    sale_month,
    n_total,
    n_included,
    n_excluded_exact_duplicate,
    n_excluded_not_full_market_price,
    n_excluded_unmapped_property_type,
    n_excluded_invalid_price,
    n_with_size_description,
    round(100.0 * n_with_size_description / nullif(n_total, 0), 2) as pct_size_description_coverage
from by_month
