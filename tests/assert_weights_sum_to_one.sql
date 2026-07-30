-- Fails if any (region_scope, weight_variant) combination's fixed weights
-- don't sum to 1.0 within 1e-6.
select
    region_scope,
    weight_variant,
    sum(weight) as weight_sum
from {{ ref('int_strata__base_weights') }}
group by 1, 2
having abs(sum(weight) - 1.0) > 1e-6
