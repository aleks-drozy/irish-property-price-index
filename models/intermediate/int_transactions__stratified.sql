{#
  Assigns each in-index transaction (exclusion_reason is null) to a stratum
  within one or both region scopes:
    - NATIONAL scope: every eligible transaction nationwide, stratum =
      property_type x county_region_map bucket (8 strata: 2 x 4).
    - DUBLIN scope: only Dublin-county transactions, stratum =
      property_type x dublin_district_map bucket (10 strata: 2 x 5,
      the 5th being DUBLIN_UNKNOWN for addresses we can't place in a
      district - see district derivation below).

  A Dublin transaction therefore appears twice in this model: once under
  NATIONAL (counted in the DUBLIN region_region bucket) and once under
  DUBLIN scope (assigned to a district). That is intentional - the two
  scopes are independent index computations over independently-normalised
  weights, per the mix-adjustment formula in DECISIONS.md.

  Dublin district derivation (see DECISIONS.md block 0 profiling): PPR has
  no standalone postal-district column. We try, in order:
    1. Eircode routing key (first 3 chars, e.g. 'D14') - covers 32.3% of
       Dublin rows in the full dataset.
    2. Regex-extracted "DUBLIN NN" from the free-text Address - covers a
       further chunk, 49.1% of Dublin rows on its own (some overlap with
       #1). Only codes that are real Dublin districts (01-24, 06W) match
       the seed; regex false positives (e.g. "Dublin 74") fall through.
    3. Otherwise: DUBLIN_UNKNOWN. Combined coverage measured at 54.2% of
       Dublin rows - the remaining 45.8% is a genuine, reported data gap,
       not silently dropped.
#}

with cleaned as (

    select * from {{ ref('int_transactions__cleaned') }}
    where exclusion_reason is null

),

dublin_district_extracted as (

    select
        c.*,
        upper(nullif(trim(substr(c.eircode, 1, 3)), '')) as eircode_routing_key,
        upper(
            regexp_extract(
                upper(c.address), 'DUBLIN[ ]*([0-9]{1,2}W?)\b', 1
            )
        ) as address_district_raw,
        case
            when length(
                upper(regexp_extract(upper(c.address), 'DUBLIN[ ]*([0-9]{1,2}W?)\b', 1))
            ) = 1
            then '0' || upper(regexp_extract(upper(c.address), 'DUBLIN[ ]*([0-9]{1,2}W?)\b', 1))
            else upper(regexp_extract(upper(c.address), 'DUBLIN[ ]*([0-9]{1,2}W?)\b', 1))
        end as address_district_padded
    from cleaned c

),

dublin_district_resolved as (

    select
        d.*,
        coalesce(
            case when d.eircode_routing_key like 'D__' then substr(d.eircode_routing_key, 2, 2) end,
            nullif(d.address_district_padded, '')
        ) as district_code_candidate
    from dublin_district_extracted d

),

national_scope as (

    select
        r.transaction_id,
        r.date_of_sale,
        r.sale_month,
        r.county,
        r.property_type,
        r.price_eur_index_basis,
        'NATIONAL' as region_scope,
        cr.region as geo_bucket,
        r.property_type || '_' || cr.region as stratum_key
    from dublin_district_resolved r
    left join {{ ref('county_region_map') }} cr
        on r.county = cr.county

),

dublin_scope as (

    select
        r.transaction_id,
        r.date_of_sale,
        r.sale_month,
        r.county,
        r.property_type,
        r.price_eur_index_basis,
        'DUBLIN' as region_scope,
        coalesce(dm.district_group, 'DUBLIN_UNKNOWN') as geo_bucket,
        r.property_type || '_' || coalesce(dm.district_group, 'DUBLIN_UNKNOWN') as stratum_key
    from dublin_district_resolved r
    left join {{ ref('dublin_district_map') }} dm
        on r.district_code_candidate = dm.district_code
    where r.county = 'DUBLIN'

),

unioned as (

    select * from national_scope
    union all
    select * from dublin_scope

)

select * from unioned
