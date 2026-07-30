-- The test that catches an upstream PSRA schema change. Fails if any
-- distinct `Description of Property` value in the raw export has no entry
-- in seeds/property_type_map.csv - meaning CI needs a human to look at the
-- new string and add it (translate it, if it's a new Irish-language
-- variant) before the pipeline can trust property_type again.
select distinct
    s.description_of_property as unmapped_description
from {{ ref('stg_ppr__transactions') }} s
left join {{ ref('property_type_map') }} m
    on s.description_of_property = m.description_raw
where m.description_raw is null
