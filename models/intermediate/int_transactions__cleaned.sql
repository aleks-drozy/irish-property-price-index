{#
  Applies the methodological cleaning decisions (see DECISIONS.md):
    1. Drop exact full-row duplicates. Profiling of the full 2026-07-30
       export found 2,026 rows that are byte-identical across all 9 source
       columns, vs. 2,184 rows that merely share (date, address, price) -
       the other 158 are genuine distinct sales (e.g. two units in the same
       development sold the same day at the same price) and must NOT be
       treated as duplicates. So we dedupe on the full-row surrogate key,
       not on (date, address, price) as originally sketched.
    2. Exclude Not Full Market Price = true sales from the index (kept,
       flagged, for the data-quality mart - never silently dropped).
    3. Gross up VAT-exclusive new-build prices by x1.135 so they compare
       like-for-like with second-hand (VAT-inclusive) prices.
    4. Winsorise price at the configured percentiles before it is allowed
       to feed a stratum median, to blunt the effect of the small number of
       clearly-erroneous rows (min observed EUR 5,001, max observed
       EUR 387.7m on the full dataset).
  Every row that would be excluded from the index is KEPT here with an
  exclusion_reason, not dropped - int_transactions__stratified and the
  index models filter on exclusion_reason is null; mart_data_quality
  reports the excluded counts.
#}

with dedup as (

    select
        *,
        row_number() over (
            partition by transaction_id
            order by date_of_sale, address, price_eur
        ) as _dupe_rank
    from {{ ref('stg_ppr__transactions') }}

),

flagged_dupes as (

    select
        *,
        (_dupe_rank > 1) as is_exact_duplicate
    from dedup

),

mapped as (

    select
        f.*,
        pt.property_type
    from flagged_dupes f
    left join {{ ref('property_type_map') }} pt
        on f.description_of_property = pt.description_raw

),

price_bounds as (

    select
        approx_quantile(price_eur, {{ var('winsor_low_pct') }}) as p_low,
        approx_quantile(price_eur, {{ var('winsor_high_pct') }}) as p_high
    from mapped
    where not is_exact_duplicate

),

priced as (

    select
        m.*,
        b.p_low,
        b.p_high,
        least(greatest(m.price_eur, b.p_low), b.p_high) as price_eur_winsorised,
        case
            when m.vat_exclusive and m.property_type = 'NEW'
                then m.price_eur * (1 + {{ var('new_build_vat_rate') }})
            else m.price_eur
        end as price_eur_vat_adjusted
    from mapped m
    cross join price_bounds b

),

with_vat_adjusted_winsor as (

    select
        p.*,
        case
            when p.vat_exclusive and p.property_type = 'NEW'
                then least(greatest(p.price_eur_vat_adjusted, b.p_low * (1 + {{ var('new_build_vat_rate') }})), b.p_high * (1 + {{ var('new_build_vat_rate') }}))
            else p.price_eur_winsorised
        end as price_eur_index_basis
    from priced p
    cross join price_bounds b

),

final as (

    select
        transaction_id,
        date_of_sale,
        date_trunc('month', date_of_sale)::date as sale_month,
        address,
        county,
        eircode,
        price_eur,
        price_eur_vat_adjusted,
        price_eur_index_basis,
        not_full_market_price,
        vat_exclusive,
        description_of_property,
        property_type,
        property_size_description,
        is_exact_duplicate,
        case
            when is_exact_duplicate then 'exact_duplicate'
            when not_full_market_price then 'not_full_market_price'
            when property_type is null then 'unmapped_property_type'
            when price_eur is null or price_eur <= 0 then 'invalid_price'
            else null
        end as exclusion_reason
    from with_vat_adjusted_winsor

)

select * from final
