-- 10_data_completeness_export.sql
-- Export completeness overview to CSV

\o /data/workspace/kmayer/courtlistener/cleaned_csv/data_completeness_overview.csv
COPY (
  SELECT
      table_name,
      variable_name,
      total_rows,
      missing_count,
      missing_pct,
      completeness_pct
  FROM data_completeness_overview
  ORDER BY table_name, variable_name
) TO STDOUT WITH CSV HEADER;
\o

\o /data/workspace/kmayer/courtlistener/cleaned_csv/data_completeness_table_level.csv
COPY (
  SELECT
      table_name,
      COUNT(*) AS n_variables_checked,
      ROUND(AVG(completeness_pct), 2) AS avg_completeness_pct,
      ROUND(
          PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY completeness_pct)::numeric,
          2
      ) AS median_completeness_pct,
      ROUND(MIN(completeness_pct), 2) AS min_completeness_pct,
      ROUND(MAX(completeness_pct), 2) AS max_completeness_pct,
      COUNT(*) FILTER (WHERE completeness_pct < 50) AS n_below_50_pct,
      COUNT(*) FILTER (WHERE completeness_pct = 100) AS n_full_100_pct
  FROM data_completeness_overview
  GROUP BY table_name
  ORDER BY avg_completeness_pct DESC, table_name
) TO STDOUT WITH CSV HEADER;
\o