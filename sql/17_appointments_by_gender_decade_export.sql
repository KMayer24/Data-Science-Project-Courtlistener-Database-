-- 17_appointments_by_gender_decade_export.sql
-- Export counts of distinct persons with a recorded judicial position start,
-- grouped by gender and decade (1920-2025).
--
-- A person is counted at most once within a decade, even if that person has
-- several position records beginning in the same decade. The same person can
-- appear in more than one decade when positions began in different decades.
-- Blank, NULL, and non-binary gender values are grouped as Missing.
-- The output intentionally has no header because the plotting script assigns
-- the column names gender, decade, and n when reading the file.

\o /data/workspace/kmayer/courtlistener/cleaned_csv/appointments_by_gender_decade.csv
COPY (
    WITH decade_counts AS (
        SELECT
            CASE
                WHEN LOWER(TRIM(p.gender)) = 'f' THEN 'Female'
                WHEN LOWER(TRIM(p.gender)) = 'm' THEN 'Male'
                ELSE 'Missing'
            END AS gender,
            (
                FLOOR(EXTRACT(YEAR FROM pos.date_start) / 10) * 10
            )::int AS decade,
            COUNT(DISTINCT pos.person_id) AS n
        FROM public.people_db_position pos
        LEFT JOIN public.people_db_person p
            ON p.id = pos.person_id
        WHERE pos.date_start >= DATE '1920-01-01'
          AND pos.date_start < DATE '2026-01-01'
        GROUP BY gender, decade
    )
    SELECT
        gender,
        decade,
        n
    FROM decade_counts
    ORDER BY
        decade,
        CASE gender
            WHEN 'Female' THEN 1
            WHEN 'Male' THEN 2
            ELSE 3
        END
) TO STDOUT WITH CSV;
\o
