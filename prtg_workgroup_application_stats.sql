-- Extracts, background tasks --
--------------------------------

-- Number of failed extracts in the last 60 minutes
-- Display Name: Extracts: Number of Failed in the Last 60 Minutes
SELECT
    'number_of_failed_extracts_last_60min' AS name,
    COUNT(*) AS value
FROM public.background_jobs
WHERE job_name IN ('Refresh Extracts', 'Increment Extracts')
    AND finish_code <> 0
    AND completed_at > NOW() - INTERVAL '60 minutes'
    
UNION ALL    

-- Absolute delay in the last 4 hours, for extract tasks, in seconds
-- Display Name: Extracts: Avg Delay (s) in the Last 4 Hours
SELECT
    'extracts_avg_delay_s_last_4h' AS name,
    EXTRACT(epoch FROM (AVG(started_at - created_at))) AS value
FROM public."background_jobs"
WHERE job_name IN ('Refresh Extracts', 'Increment Extracts')
    AND created_at >= NOW() - INTERVAL '240 minutes'

UNION ALL

-- Relative duration of recent Extracts (last 8h) vs last 3 weeks, %. High percentages (e.g. 150%) signify increased duration.
-- Display Name: Extracts: Relative Avg Duration (%), Last 8 Hours vs Last 3 Weeks
SELECT
    'extracts_avg_duration_8h_vs_3w' AS name,
    -- Avg duration in the last 8h
    EXTRACT(epoch FROM (AVG(
        CASE created_at >= NOW() - INTERVAL '480 minutes'
            WHEN TRUE THEN completed_at - started_at
            ELSE NULL
        END
    )))
    /
    -- Avg duration in the last 21d
    EXTRACT(epoch FROM (AVG(
        CASE created_at >= NOW() - INTERVAL '30240 minutes'
            WHEN TRUE THEN completed_at - started_at
            ELSE NULL
        END
    ))) AS value
FROM public."background_jobs"
WHERE job_name IN ('Refresh Extracts', 'Increment Extracts')

UNION ALL

-- View performance --
----------------------

-- Avg Load time of the top 10 views in the last 4h
-- Display Name: Performance: Avg Load Time (s) for Top 10 Views
SELECT
    'top_views_avg_elapsed_s_4h' AS name,
    CASE COUNT(*) > 10 -- Only if there were sufficient views
        WHEN TRUE THEN EXTRACT(epoch FROM (AVG(completed_at - created_at)))
        ELSE NULL -- Avg load time registered AS NULL seconds if there was not enough activity
    END AS value
FROM public."http_requests" hr 
WHERE action = 'bootstrapSession'
    AND created_at >= NOW() - INTERVAL '240 minutes'
    -- Everything below is just to select the top 10 views.
    AND CONCAT((regexp_split_to_array(currentsheet, E'\\/'))[1], '_', (regexp_split_to_array(currentsheet, E'\\/'))[2]) IN
        (WITH top_views AS (
            SELECT
                -- Split 'Planning_0/PlanningOverview' into workbook and view
                CONCAT((regexp_split_to_array(currentsheet, E'\\/'))[1], '_', (regexp_split_to_array(currentsheet, E'\\/'))[2]) AS workbook_view,
                COUNT(*) AS number_of_requests
            FROM public."http_requests" hr 
            WHERE action = 'bootstrapSession'
                AND currentsheet NOT LIKE 'ds:%'
                AND currentsheet <> ''
                AND created_at >= NOW() - INTERVAL '10080 minutes' -- Most popular views of the last 7 days
            GROUP BY 1)
        SELECT
            workbook_view
        FROM top_views
        WHERE workbook_view IS NOT NULL
        ORDER BY number_of_requests DESC
        LIMIT 10
        )

;