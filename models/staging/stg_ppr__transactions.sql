{#
  1:1 with the raw PPR export. No joins, no business-logic filtering here -
  every row from the source appears here exactly once, including exact
  duplicates and rows that will later be excluded from the index (NFMP=Yes,
  price outliers). Business logic lives in intermediate/.
#}

with source as (

    select * from {{ ppr_raw_source() }}

),

renamed as (

    select

        {{ dbt_utils.generate_surrogate_key([
            'date_of_sale_raw', 'address_raw', 'county_raw', 'eircode_raw',
            'price_raw', 'not_full_market_price_raw', 'vat_exclusive_raw',
            'description_raw', 'size_desc_raw'
        ]) }} as transaction_id,

        -- parsed / typed columns
        try_strptime(date_of_sale_raw, '%d/%m/%Y')::date as date_of_sale,
        trim(upper(address_raw)) as address,
        trim(upper(county_raw)) as county,
        nullif(trim(upper(eircode_raw)), '') as eircode,
        cast(
            replace(replace(price_raw, '€', ''), ',', '')
            as decimal(14, 2)
        ) as price_eur,
        case upper(trim(not_full_market_price_raw))
            when 'YES' then true
            when 'NO' then false
            else null
        end as not_full_market_price,
        case upper(trim(vat_exclusive_raw))
            when 'YES' then true
            when 'NO' then false
            else null
        end as vat_exclusive,
        trim(description_raw) as description_of_property,
        trim(size_desc_raw) as property_size_description,

        -- raw values preserved for lineage / debugging
        date_of_sale_raw,
        address_raw,
        county_raw,
        eircode_raw,
        price_raw,
        not_full_market_price_raw,
        vat_exclusive_raw,
        description_raw,
        size_desc_raw

    from source

)

select * from renamed
