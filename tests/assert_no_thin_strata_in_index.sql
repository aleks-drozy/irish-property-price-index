-- Regression guard: no (region_scope, stratum, month) cell with n below
-- the configured minimum is allowed to have contributed a non-null median
-- that could feed a published index point. int_strata__period_medians is
-- supposed to null out median_price below the threshold already - this
-- test fails loudly if that logic ever regresses.
select
    region_scope,
    stratum_key,
    sale_month,
    n,
    median_price
from {{ ref('int_strata__period_medians') }}
where median_price is not null
  and n < {{ var('min_stratum_n') }}
