--DATA EXPLORATION AND CLEANING

--1. Update the fresh_segments.interest_metrics table by modifying the month_year column to be a date data type with the start of the month
UPDATE dbo.interest_metrics
SET month_year = CAST(CAST([year] AS VARCHAR) + '-' + CAST([month] AS VARCHAR) + '-01' AS DATE);


--2. What is count of records in the fresh_segments.interest_metrics for each month_year value sorted in chronological order (earliest to latest) with the null values appearing first?
SELECT
	month_year,
	COUNT(*) AS number_of_records
FROM dbo.Interest_metrics
GROUP BY month_year
ORDER BY month_year 

--3.What do you think we should do with these null values in the fresh_segments.interest_metrics
DELETE FROM dbo.Interest_metrics
WHERE month_year IS NULL;

--4.How many interest_id values exist in the fresh_segments.interest_metrics table but not in the fresh_segments.interest_map table? What about the other way around?
SELECT COUNT(DISTINCT imt.interest_id) AS not_in_map
FROM dbo.interest_metrics AS imt
LEFT JOIN dbo.interest_map AS imap ON imt.interest_id = imap.id
WHERE imap.id IS NULL;

SELECT COUNT(DISTINCT imap.id) AS not_in_metrics
FROM dbo.interest_map AS imap
LEFT JOIN dbo.interest_metrics AS imt ON imap.id = imt.interest_id
WHERE imt.interest_id IS NULL;

--5.Summarise the id values in the fresh_segments.interest_map by its total record count in this table
SELECT 
	id,
	COUNT(*) AS total_record
FROM dbo.Interest_map
GROUP BY id

SELECT COUNT(*) as total_records
FROM dbo.interest_map;

/*6. What sort of table join should we perform for our analysis and why? 
Check your logic by checking the rows where interest_id = 21246 in your joined output and include all columns from fresh_segments.interest_metrics and all columns from fresh_segments.interest_map except from the id column. */
SELECT im.interest_name, im.interest_summary,im.created_at,im.last_modified, itm.*
FROM dbo.interest_map AS im
INNER JOIN dbo.interest_metrics AS itm ON im.id = itm.interest_id
WHERE itm.interest_id=21246;

/*7.Are there any records in your joined table where the month_year value is before the created_at value from the fresh_segments.interest_map table?
Do you think these values are valid and why? */

WITH get_records AS (SELECT imt.*, imap.interest_name, imap.interest_summary, imap.created_at, imap.last_modified
FROM dbo.interest_metrics AS imt
INNER JOIN dbo.interest_map AS imap ON imt.interest_id = imap.id
WHERE imt.month_year < CAST(imap.created_at AS DATE)
) 
SELECT 
	COUNT(*) AS n_records
FROM get_records

--INTEREST ANALYSIS

--1. Which interests have been present in all month_year dates in our dataset?

SELECT COUNT(DISTINCT month_year) 
FROM dbo.interest_metrics;

SELECT ima.interest_name 
FROM dbo.Interest_map ima
JOIN dbo.Interest_metrics im 
ON ima.id=im.interest_id
GROUP BY interest_name
HAVING COUNT(DISTINCT im.month_year) = 14;

--2. Using this same total_months measure - calculate the cumulative percentage of all records starting at 14 months - which total_months value passes the 90% cumulative percentage value?

WITH cte_total_months AS (
    SELECT interest_id,
           count(DISTINCT month_year) AS total_months
    FROM dbo.interest_metrics
    GROUP BY interest_id
),
cte_cumalative_perc AS (
    SELECT total_months,
           count(*) AS n_ids,
           round(
               100 * sum(count(*)) OVER (
                   ORDER BY total_months desc
               ) / sum(count(*)) over(),
               2
           ) AS cumalative_perc
    FROM cte_total_months
    GROUP BY total_months
) 
-- Select results that are >= 90% and order by total_months DESC
SELECT total_months,
       n_ids,
       cumalative_perc
FROM cte_cumalative_perc
WHERE cumalative_perc >= 90
ORDER BY total_months DESC;

--3. If we were to remove all interest_id values which are lower than the total_months value we found in the previous question - how many total data points would we be removing?

WITH cte_total_months AS (
    SELECT interest_id,
           count(DISTINCT month_year) AS total_months
    FROM dbo.interest_metrics
    GROUP BY interest_id
    HAVING count(DISTINCT month_year) < 6
)
-- Count the total number of rows to be removed
SELECT SUM(monthly_count) AS total_data_points_removed
FROM (
    SELECT interest_id,
           COUNT(*) AS monthly_count
    FROM dbo.interest_metrics
    WHERE interest_id IN (SELECT interest_id FROM cte_total_months)
    GROUP BY interest_id
) AS subquery;


--4. Does this decision make sense to remove these data points from a business perspective? Use an example where there are all 14 months present to a removed interest example for your arguments - think about what it means to have less months present from a segment perspective.


--5. After removing these interests - how many unique interests are there for each month?

-- Identify the interest_ids to be removed based on the threshold
WITH ToRemove AS (
    SELECT interest_id
    FROM dbo.interest_metrics
    GROUP BY interest_id
    HAVING COUNT(DISTINCT month_year) < 6  -- Replace Y with the threshold from the previous question
)
-- Count the number of unique interests for each month, excluding the interests identified for removal
SELECT month_year,
       COUNT(DISTINCT interest_id) AS unique_interests
FROM dbo.interest_metrics
WHERE interest_id NOT IN (SELECT interest_id FROM ToRemove)
GROUP BY month_year
ORDER BY month_year;


--SEGMENT ANALYSIS

/* 1. Using our filtered dataset by removing the interests with less than 6 months worth of data,
which are the top 10 and bottom 10 interests which have the largest composition values in any month_year? 
Only use the maximum composition value for each interest but you must keep the corresponding month_year */

WITH FilteredInterests AS (
    SELECT interest_id
    FROM dbo.interest_metrics
    GROUP BY interest_id
    HAVING COUNT(DISTINCT month_year) >= 6
),
MaxCompositionPerInterest AS (
    SELECT im.interest_id, 
           MAX(im.composition) AS MaxComposition,
           MAX(im.month_year) AS MaxCompositionMonthYear 
    FROM dbo.interest_metrics im
    INNER JOIN FilteredInterests fi ON im.interest_id = fi.interest_id
    GROUP BY im.interest_id
),
RankedInterests AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY MaxComposition DESC) AS RankDesc,
           ROW_NUMBER() OVER (ORDER BY MaxComposition ASC) AS RankAsc
    FROM MaxCompositionPerInterest
)
SELECT *
FROM RankedInterests
WHERE RankDesc <= 10 OR RankAsc <= 10;


--2. Which 5 interests had the lowest average ranking value?

WITH FilteredInterests AS (
    SELECT interest_id
    FROM dbo.interest_metrics
    GROUP BY interest_id
    HAVING COUNT(DISTINCT month_year) >= 6
),
AverageRankings AS (
    SELECT im.interest_id,
          ROUND( AVG(CAST(im.ranking AS FLOAT)),2) AS AvgRanking
    FROM dbo.interest_metrics im
    INNER JOIN FilteredInterests fi ON im.interest_id = fi.interest_id
    GROUP BY im.interest_id
)
SELECT TOP 5
       ar.interest_id,
       im.interest_name,
       ar.AvgRanking
FROM AverageRankings ar
INNER JOIN dbo.interest_map im ON ar.interest_id = im.id
ORDER BY ar.AvgRanking ASC;

--3. Which 5 interests had the largest standard deviation in their percentile_ranking value?

WITH InterestStdDev AS (
    SELECT
        im.interest_id,
       ROUND( STDEV(im.percentile_ranking),2) AS StdDevPercentileRanking
    FROM
        dbo.interest_metrics im
    GROUP BY
        im.interest_id
)
SELECT TOP 5
    ip.id,
    ip.interest_name,
    isd.StdDevPercentileRanking
FROM
    InterestStdDev isd
INNER JOIN dbo.interest_map ip ON
    isd.interest_id = ip.id
ORDER BY
    isd.StdDevPercentileRanking DESC;


/* 4. For the 5 interests found in the previous question,
what was minimum and maximum percentile_ranking values for each interest and its corresponding year_month value?
Can you describe what is happening for these 5 interests? */

-- First, calculate the standard deviation for each interest
WITH InterestStdDev AS (
    SELECT
        interest_id,
        STDEV(percentile_ranking) AS StdDevPercentileRanking
    FROM
        dbo.interest_metrics
    GROUP BY
        interest_id
),
-- Then, select the top 5 interests with the largest standard deviation
TopStdDevInterests AS (
    SELECT TOP 5
        interest_id
    FROM
        InterestStdDev
    ORDER BY
        StdDevPercentileRanking DESC
),
-- Calculate the min and max percentile_ranking for these interests
MinMaxPercentile AS (
    SELECT
        im.interest_id,
        MIN(im.percentile_ranking) AS MinPercentileRanking,
        MAX(im.percentile_ranking) AS MaxPercentileRanking
    FROM
        dbo.interest_metrics im
    WHERE
        im.interest_id IN (SELECT interest_id FROM TopStdDevInterests)
    GROUP BY
        im.interest_id
),
-- Find the month_year for the min and max percentile_ranking
MinMonthYear AS (
    SELECT
        interest_id,
        percentile_ranking,
        month_year
    FROM
        dbo.interest_metrics
    WHERE
        EXISTS (SELECT 1 FROM MinMaxPercentile WHERE interest_id = dbo.interest_metrics.interest_id AND MinPercentileRanking = dbo.interest_metrics.percentile_ranking)
),
MaxMonthYear AS (
    SELECT
        interest_id,
        percentile_ranking,
        month_year
    FROM
        dbo.interest_metrics
    WHERE
        EXISTS (SELECT 1 FROM MinMaxPercentile WHERE interest_id = dbo.interest_metrics.interest_id AND MaxPercentileRanking = dbo.interest_metrics.percentile_ranking)
)
-- Finally, join everything together to get the interest names and corresponding month_year for min and max rankings
SELECT
    ip.id,
    ip.interest_name,
    mmp.MinPercentileRanking,
    mmn.month_year AS MinPercentileMonthYear,
    mmp.MaxPercentileRanking,
    mmx.month_year AS MaxPercentileMonthYear
FROM
    MinMaxPercentile mmp
INNER JOIN dbo.interest_map ip ON
    mmp.interest_id = ip.id
LEFT JOIN MinMonthYear mmn ON
    mmp.interest_id = mmn.interest_id AND mmp.MinPercentileRanking = mmn.percentile_ranking
LEFT JOIN MaxMonthYear mmx ON
    mmp.interest_id = mmx.interest_id AND mmp.MaxPercentileRanking = mmx.percentile_ranking;

--INDEX ANALYSIS

--1.What is the top 10 interests by the average composition for each month?

WITH AverageComposition AS (
    SELECT
        month_year,
        interest_id,
        ROUND(composition / NULLIF(index_value, 0), 2) AS AvgComposition
    FROM
        dbo.interest_metrics
),
RankedInterests AS (
    SELECT
        month_year,
        interest_id,
        AvgComposition,
        RANK() OVER (PARTITION BY month_year ORDER BY AvgComposition DESC) AS Rank
    FROM
        AverageComposition
)
SELECT TOP 10
    im.month_year,
    im.interest_id,
    im.AvgComposition,
    ip.interest_name
FROM
    RankedInterests im
INNER JOIN dbo.interest_map ip ON
    im.interest_id = ip.id
WHERE
    Rank <= 10
ORDER BY
    im.month_year,
    Rank;

--2.For all of these top 10 interests - which interest appears the most often?

WITH AverageComposition AS (
    SELECT
        month_year,
        interest_id,
        ROUND(composition / NULLIF(index_value, 0), 2) AS AvgComposition
    FROM
        dbo.interest_metrics
),
RankedInterests AS (
    SELECT
        month_year,
        interest_id,
        AvgComposition,
        RANK() OVER (PARTITION BY month_year ORDER BY AvgComposition DESC) AS Rank
    FROM
        AverageComposition
),
TopInterests AS (
    SELECT
        im.month_year,
        im.interest_id,
        im.AvgComposition,
        ip.interest_name
    FROM
        RankedInterests im
    INNER JOIN dbo.interest_map ip ON
        im.interest_id = ip.id
    WHERE
        Rank <= 10
),
FrequencyCounts AS (
    SELECT
        interest_name,
        COUNT(*) as Frequency
    FROM
        TopInterests
    GROUP BY
        interest_name
),
RankedFrequency AS (
    SELECT *,
        RANK() OVER (ORDER BY Frequency DESC) as FrequencyRank
    FROM
        FrequencyCounts
)
SELECT
    interest_name,
    Frequency
FROM
    RankedFrequency
WHERE
    FrequencyRank = 1;

--3.What is the average of the average composition for the top 10 interests for each month?

WITH AverageComposition AS (
    SELECT
        month_year,
        interest_id,
        ROUND(composition / NULLIF(index_value, 0), 2) AS AvgComposition
    FROM
        dbo.interest_metrics
),
RankedInterests AS (
    SELECT
        month_year,
        interest_id,
        AvgComposition,
        RANK() OVER (PARTITION BY month_year ORDER BY AvgComposition DESC) AS Rank
    FROM
        AverageComposition
),
TopInterests AS (
    SELECT
        month_year,
        AvgComposition
    FROM
        RankedInterests
    WHERE
        Rank <= 10
),
MonthlyAverage AS (
    SELECT
        month_year,
        AVG(AvgComposition) AS MonthlyAvgOfAvgComposition
    FROM
        TopInterests
    GROUP BY
        month_year
)
SELECT
    month_year,
    ROUND(MonthlyAvgOfAvgComposition, 2) AS AvgOfAvgComposition
FROM
    MonthlyAverage
ORDER BY
    month_year;

/* 4.What is the 3 month rolling average of the max average composition value from September 2018 to August 2019
and include the previous top ranking interests in the same output shown below. */

WITH get_top_avg_composition AS (
    SELECT 
        imet.month_year,
        imet.interest_id,
        imap.interest_name,
        ROUND(imet.composition / NULLIF(imet.index_value, 0), 2) AS avg_composition,
        RANK() OVER (
            PARTITION BY imet.month_year 
            ORDER BY ROUND(imet.composition / NULLIF(imet.index_value, 0), 2) DESC
        ) AS rnk
    FROM 
        dbo.interest_metrics AS imet
        JOIN dbo.interest_map AS imap ON imap.id = imet.interest_id
),
get_moving_avg AS (
    SELECT 
        month_year,
        interest_name,
        avg_composition AS max_index_composition,
        ROUND(AVG(avg_composition) OVER (
            ORDER BY month_year 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2) AS [3_month_moving_avg]
    FROM 
        get_top_avg_composition
    WHERE 
        rnk = 1
),
get_lag_avg AS (
    SELECT *,
        LAG(interest_name, 1) OVER (
            ORDER BY month_year
        ) AS interest_1_name,
        LAG(interest_name, 2) OVER (
            ORDER BY month_year
        ) AS interest_2_name,
        LAG(max_index_composition, 1) OVER ( 
            ORDER BY month_year
        ) AS interest_1_avg,
        LAG(max_index_composition, 2) OVER (
            ORDER BY month_year
        ) AS interest_2_avg
    FROM 
        get_moving_avg
)
SELECT 
    month_year,
    interest_name,
    max_index_composition,
    [3_month_moving_avg],
    interest_1_name + ': ' + CAST(interest_1_avg AS VARCHAR) AS [1_month_ago],
    interest_2_name + ': ' + CAST(interest_2_avg AS VARCHAR) AS [2_month_ago]
FROM 
    get_lag_avg
WHERE 
    month_year BETWEEN '2018-09-01' AND '2019-08-01';

