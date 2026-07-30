{#
  Positional read of the raw PPR CSV. We deliberately do NOT read by header
  name: PSRA's export mangles the euro sign in the "Price" column header
  under some encodings, and header text has drifted between PPR exports in
  the past. Reading positionally with header=false, skip=1 is immune to
  that. Column order confirmed by profiling the live 2026-07-30 export:
    1 Date of Sale (dd/mm/yyyy)   6 Not Full Market Price
    2 Address                     7 VAT Exclusive
    3 County                      8 Description of Property
    4 Eircode                     9 Property Size Description
    5 Price (EUR)
  Set PPR_USE_FIXTURE=true in CI's fast job to point at the small committed
  sample instead of the full (gitignored) download.
#}
{% macro ppr_raw_source() %}
  {% set use_fixture = env_var('PPR_USE_FIXTURE', 'false') %}
  {% if use_fixture == 'true' %}
    {% set csv_path = env_var('PPR_FIXTURE_PATH', 'data/fixture/ppr_fixture.csv') %}
  {% else %}
    {% set csv_path = env_var('PPR_RAW_CSV_PATH', 'data/raw/PPR-ALL.csv') %}
  {% endif %}
  read_csv(
    '{{ csv_path }}',
    header = false,
    skip = 1,
    encoding = 'cp1252',
    columns = {
      'date_of_sale_raw': 'VARCHAR',
      'address_raw': 'VARCHAR',
      'county_raw': 'VARCHAR',
      'eircode_raw': 'VARCHAR',
      'price_raw': 'VARCHAR',
      'not_full_market_price_raw': 'VARCHAR',
      'vat_exclusive_raw': 'VARCHAR',
      'description_raw': 'VARCHAR',
      'size_desc_raw': 'VARCHAR'
    }
  )
{% endmacro %}

{% macro cso_rppi_raw_source() %}
  {% set parquet_path = env_var('CSO_RPPI_PARQUET_PATH', 'data/raw/cso_rppi.parquet') %}
  read_parquet('{{ parquet_path }}')
{% endmacro %}
