{#
  Own mix-adjusted index vs the CSO's official RPPI (HPM09), both rebased
  to the SAME common base month so levels are comparable. This is
  directional validation only - see README "Why my index doesn't equal the
  CSO's" - the two indices differ in universe, method (hedonic vs
  stratified-median), and VAT treatment.
#}

with own_index as (

    select
        region_scope,
        sale_month,
        index_value as own_index_value
    from {{ ref('mart_price_index_monthly') }}
    where index_variant = 'mixadj_fixed_fullsample'

),

cso_filtered as (

    -- HPM09C01 = index level; '-' = National all-residential, '05' = Dublin all-residential
    select
        case region_code
            when '-' then 'NATIONAL'
            when '05' then 'DUBLIN'
        end as region_scope,
        month as sale_month,
        value as cso_index_value
    from {{ ref('stg_cso__rppi') }}
    where statistic_code = 'HPM09C01'
      and region_code in ('-', '05')

),

common_base as (

    -- earliest month both series have a value for each region_scope
    select
        o.region_scope,
        min(o.sale_month) as common_base_month
    from own_index o
    join cso_filtered c
        on o.region_scope = c.region_scope
        and o.sale_month = c.sale_month
    where o.own_index_value is not null
      and c.cso_index_value is not null
    group by 1

),

own_base as (

    select
        o.region_scope,
        o.own_index_value as own_base_value
    from own_index o
    join common_base b
        on o.region_scope = b.region_scope
        and o.sale_month = b.common_base_month

),

cso_base as (

    select
        c.region_scope,
        c.cso_index_value as cso_base_value
    from cso_filtered c
    join common_base b
        on c.region_scope = b.region_scope
        and c.sale_month = b.common_base_month

),

rebased as (

    select
        o.region_scope,
        o.sale_month,
        100.0 * o.own_index_value / ob.own_base_value as own_index_rebased,
        100.0 * c.cso_index_value / cb.cso_base_value as cso_index_rebased
    from own_index o
    join own_base ob on o.region_scope = ob.region_scope
    left join cso_filtered c
        on o.region_scope = c.region_scope
        and o.sale_month = c.sale_month
    left join cso_base cb on c.region_scope = cb.region_scope

)

select
    {{ dbt_utils.generate_surrogate_key(['region_scope', 'sale_month']) }} as index_vs_cso_id,
    region_scope,
    sale_month,
    round(own_index_rebased, 4) as own_index_rebased,
    round(cso_index_rebased, 4) as cso_index_rebased,
    round(own_index_rebased - cso_index_rebased, 4) as level_gap
from rebased
