{#
  The Simpson's-paradox exhibit: how the transaction mix (property_type x
  geo_bucket) shifts over time, per region_scope. Grain: month x region x
  stratum.
#}

select
    {{ dbt_utils.generate_surrogate_key(['region_scope', 'sale_month', 'stratum_key']) }} as mix_shift_id,
    region_scope,
    sale_month,
    stratum_key,
    case
        when starts_with(stratum_key, 'SECOND_HAND_') then 'SECOND_HAND'
        when starts_with(stratum_key, 'NEW_') then 'NEW'
    end as property_type,
    case
        when starts_with(stratum_key, 'SECOND_HAND_') then substr(stratum_key, length('SECOND_HAND_') + 1)
        when starts_with(stratum_key, 'NEW_') then substr(stratum_key, length('NEW_') + 1)
    end as geo_bucket,
    n,
    round(share, 6) as share
from {{ ref('int_mix__composition') }}
