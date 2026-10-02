\pset pager off
\timing on
-- Von den in ext via A3b/pre_inline aufgeloesten Opinions, die der Neubau
-- verliert: wuerde das A3b-Muster OHNE den Zeilenabstand-Guard greifen?
WITH lost AS (
    SELECT a.opinion_id, a.html_extracted_author_name AS name_in_ext
    FROM ext.author_gender_from_text_extraction a
    JOIN ext_test.author_gender_from_text_extraction b USING (opinion_id)
    WHERE a.html_gender_resolved
      AND a.html_extraction_pattern = 'A3_circuit_judge_line_pre_inline'
      AND NOT b.html_gender_resolved
),
txt AS (
    SELECT l.opinion_id, l.name_in_ext,
           LEFT(REGEXP_REPLACE(REGEXP_REPLACE(COALESCE(o.html_with_citations,''),
                '</p>|</div>|<br\s*/?>|</blockquote>|</center>', E'\n','gi'),
                '<[^>]+>', ' ', 'g'), 8000) AS html_text_lines
    FROM lost l JOIN public.search_opinion o ON o.id = l.opinion_id
),
-- Dasselbe Muster wie A3b, aber ohne die Guard-Bedingung
m AS (
    SELECT t.opinion_id, t.name_in_ext,
           NULLIF(BTRIM((REGEXP_MATCH(t.html_text_lines,
             $re$(?im)^\s*(?:[_[:blank:]]+)?([A-Z][A-Za-z.'[:blank:]-]{2,80}?),\s*(?:Chief\s+|Senior\s+)?Circuit\s+Judge\s*[:.](?:\s|$)$re$
           ))[1]), '') AS name_ohne_guard
    FROM txt t
)
SELECT count(*)                                                        AS verlorene_faelle,
       count(*) FILTER (WHERE name_ohne_guard IS NOT NULL)             AS ohne_guard_gefunden,
       count(*) FILTER (WHERE upper(btrim(name_ohne_guard)) = upper(btrim(name_in_ext)))
                                                                       AS identischer_name,
       count(*) FILTER (WHERE name_ohne_guard IS NULL)                 AS weiterhin_kein_treffer
FROM m;
