\pset pager off
-- Federal appellate clusters 2010-2025: total (court-based, the definition
-- used before the RECAP split) versus how the split reassigns them.
SELECT
    EXTRACT(YEAR FROM oc.date_filed)::int AS year,
    count(*)                                        AS fed_app_total_by_court,
    count(*) FILTER (WHERE (d.source & 1) = 0)      AS stays_in_fed_app_band,
    count(*) FILTER (WHERE (d.source & 1) = 1)      AS moved_to_recap_band
FROM public.search_opinioncluster oc
JOIN public.search_docket d ON d.id = oc.docket_id
JOIN public.search_court  c ON c.id = d.court_id
WHERE oc.date_filed IS NOT NULL
  AND EXTRACT(YEAR FROM oc.date_filed) BETWEEN 2010 AND 2025
  AND (c.id = 'scotus' OR c.jurisdiction = 'F')
GROUP BY 1 ORDER BY 1;
