-- Fails if any (region_scope, index_variant) series has a gap month
-- between its own first and last published point. Does not assert a fixed
-- 2010-01 start (that's a business fact confirmed separately in
-- DECISIONS.md / the README), just that once a series starts, it has no
-- holes through to its most recent point.
with series as (
    select region_scope, index_variant, sale_month
    from {{ ref('mart_price_index_monthly') }}
),

bounds as (
    select
        region_scope,
        index_variant,
        min(sale_month) as min_month,
        max(sale_month) as max_month
    from series
    group by 1, 2
),

expected as (
    select
        b.region_scope,
        b.index_variant,
        unnest(generate_series(b.min_month, b.max_month, interval '1 month'))::date as expected_month
    from bounds b
)

select
    e.region_scope,
    e.index_variant,
    e.expected_month
from expected e
left join series s
    on e.region_scope = s.region_scope
    and e.index_variant = s.index_variant
    and e.expected_month = s.sale_month
where s.sale_month is null
