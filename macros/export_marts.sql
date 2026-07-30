{#
  Exports every mart table to parquet, as an intermediate step before
  scripts/export_dashboard_data.py turns them into the small JSON files
  the static dashboard reads. Only the mart aggregates ship (kilobytes) -
  the 600k+ row raw/staging tables never leave the DuckDB warehouse file,
  which itself is gitignored.
  Usage: dbt run-operation export_marts
#}
{% macro export_marts() %}
  {% set marts = [
      'mart_price_index_monthly',
      'mart_mix_shift',
      'mart_index_vs_cso',
      'mart_transaction_volumes',
      'mart_data_quality'
  ] %}
  {% set out_dir = env_var('MARTS_EXPORT_DIR', '.marts_export') %}
  {% do run_query("create schema if not exists tmp_export") %}
  {% for mart in marts %}
    {% set query %}
      copy (select * from {{ ref(mart) }})
      to '{{ out_dir }}/{{ mart }}.parquet' (format parquet)
    {% endset %}
    {% do run_query(query) %}
    {{ log('Exported ' ~ mart ~ ' -> ' ~ out_dir ~ '/' ~ mart ~ '.parquet', info=true) }}
  {% endfor %}
{% endmacro %}
