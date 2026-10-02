\set ON_ERROR_STOP on

DO $$
DECLARE
    gender_counts bigint[];
    gender_channels bigint[];
    fjc_counts bigint[];
    luttig_ok boolean;
BEGIN
    SELECT ARRAY[
        count(*), count(*) FILTER (WHERE gender_resolved),
        count(*) FILTER (WHERE gender = 'f'),
        count(*) FILTER (WHERE gender = 'm')
    ] INTO gender_counts
    FROM deposit.opinion_author_attribution;

    IF gender_counts IS DISTINCT FROM ARRAY[1472533,555297,69936,485361]::bigint[] THEN
        RAISE EXCEPTION 'Gender release check failed: %', gender_counts;
    END IF;

    SELECT ARRAY[
        count(*) FILTER (WHERE assignment_channel = 'previous_final'),
        count(*) FILTER (WHERE assignment_channel = 'xml_author_tag'),
        count(*) FILTER (WHERE assignment_channel = 'html_extraction')
    ] INTO gender_channels
    FROM deposit.opinion_author_attribution_diagnostics d
    JOIN deposit.opinion_author_attribution a USING (opinion_id)
    WHERE a.gender_resolved;

    IF gender_channels IS DISTINCT FROM ARRAY[418479,11514,125304]::bigint[] THEN
        RAISE EXCEPTION 'Gender channel check failed: %', gender_channels;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM deposit.opinion_author_attribution a
        JOIN deposit.opinion_author_attribution_diagnostics d USING (opinion_id)
        WHERE a.opinion_id = 2966699 AND a.gender = 'm' AND a.gender_resolved
          AND d.assignment_channel = 'html_extraction'
          AND d.html_stage_pattern = 'A3_circuit_judge_line_pre_inline'
          AND d.html_stage_extracted_name = 'LUTTIG'
    ) INTO luttig_ok;
    IF NOT luttig_ok THEN RAISE EXCEPTION 'Required LUTTIG attribution is absent'; END IF;

    SELECT ARRAY[
        (SELECT count(*) FROM deposit.fjc_appellate_case),
        (SELECT count(*) FROM deposit.opinion_fjc_match),
        (SELECT count(*) FROM deposit.opinion_case_covariates),
        (SELECT count(*) FROM deposit.opinion_case_covariates WHERE analysis_eligible)
    ] INTO fjc_counts;
    IF fjc_counts IS DISTINCT FROM ARRAY[2403096,1414601,1164762,1069145]::bigint[] THEN
        RAISE EXCEPTION 'FJC release check failed: %', fjc_counts;
    END IF;
END $$;

DO $$
DECLARE
    expected_constraint text;
    opinion_count bigint;
BEGIN
    -- The complete release includes the large opinion-text table.  Smaller
    -- derived-only test packages intentionally do not, so apply these checks
    -- only when that table is present.
    IF to_regclass('public.search_opinion') IS NOT NULL THEN
        SELECT count(*) INTO opinion_count FROM public.search_opinion;
        IF opinion_count <> 10745929 THEN
            RAISE EXCEPTION 'Opinion release check failed: expected 10745929, got %',
                opinion_count;
        END IF;

        IF to_regclass('public.search_opinion_joined_by') IS NOT NULL THEN
            expected_constraint := 'fk_joinedby_opinion';
            IF NOT EXISTS (
                SELECT 1
                FROM pg_constraint
                WHERE conrelid = 'public.search_opinion_joined_by'::regclass
                  AND conname = expected_constraint
                  AND contype = 'f'
                  AND convalidated
            ) THEN
                RAISE EXCEPTION 'Required validated foreign key is absent: %',
                    expected_constraint;
            END IF;
        END IF;

        IF to_regclass('public.search_opinionscited') IS NOT NULL THEN
            FOREACH expected_constraint IN ARRAY ARRAY[
                'fk_opinionscited_cited', 'fk_opinionscited_citing'
            ] LOOP
                IF NOT EXISTS (
                    SELECT 1
                    FROM pg_constraint
                    WHERE conrelid = 'public.search_opinionscited'::regclass
                      AND conname = expected_constraint
                      AND contype = 'f'
                      AND convalidated
                ) THEN
                    RAISE EXCEPTION 'Required validated foreign key is absent: %',
                        expected_constraint;
                END IF;
            END LOOP;
        END IF;
    END IF;
END $$;

SELECT count(*) AS opinions,
       count(*) FILTER (WHERE gender_resolved) AS gender_resolved,
       count(*) FILTER (WHERE gender = 'f') AS female,
       count(*) FILTER (WHERE gender = 'm') AS male
FROM deposit.opinion_author_attribution;
