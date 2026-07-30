{#
  1:1 with the tidy long parquet produced by scripts/fetch_cso_rppi.py,
  which already flattens the JSON-stat 2.0 cube (dims: STATISTIC x
  TLIST(M1) x C02803V03373) into one row per (statistic, month, region).
  No filtering here - that happens in intermediate/.
#}

with source as (

    select * from {{ cso_rppi_raw_source() }}

),

renamed as (

    select
        statistic_code,
        statistic_label,
        month_code,
        try_strptime(month_code, '%Y%m')::date as month,
        region_code,
        region_label,
        value

    from source

)

select * from renamed
