CREATE TABLE    [Load_Sessions]
(
	[session_id]    INT IDENTITY    ( 1, 1 )    NOT NULL
,	[dts]           DATETIME                    NOT NULL
,   [dte]			DATETIME                    NULL
,	[state]		    INT                         NULL

,	CONSTRAINT [PK_SessionID]   PRIMARY KEY CLUSTERED ( [session_ID] )
)

CREATE TABLE    [WorktablesLog]
(
	[session_id]    INT	                        NOT NULL
,	[num]			INT	                        NOT NULL
,	[tblName]		VARCHAR ( 100 )             NOT NULL
,	[dt_create]	    DATETIME                    NOT NULL
,	[dt_load]		DATETIME                        NULL
,	[dt_preProcess]	DATETIME                        NULL
)

/*
 procedure fills starting and ending zeroes or NULLs by nearest meaning value
*/
CREATE PROC [FillStartingAndEndingSpaces]
	@TABLE_NAME		SysName
,	@COLUMN_NAME	SysName
AS
BEGIN
	SET NOCOUNT ON
	DECLARE @SQL NVARCHAR ( MAX )
	
	SET @SQL = '
				DECLARE @OutVar TABLE   (   PRIOR_DATE  DATE
                                        ,   LATER_DATE  DATE
                                        ,   Method      NVARCHAR ( 20 ) )
				;WITH cte1 AS 
                (
					SELECT rn1, [date] 
                    FROM (
						    SELECT ROW_NUMBER() OVER(ORDER BY [date]) as rn2, *
						    FROM (
							        SELECT	ROW_NUMBER() OVER (ORDER BY [date]) rn1,
								    	    [date], ISNULL('+QUOTENAME(@COLUMN_NAME)+',0) as Ticker
							        FROM '+ QUOTENAME(@TABLE_NAME) +'
						         ) X
						    WHERE Ticker = 0
					) Y
					WHERE rn1 = rn2
				), 
				cte2 AS 
                (
					SELECT TOP 1 rn1+1 AS rn2 
                    FROM cte1 
                    ORDER BY rn1 DESC
				)
				UPDATE l
				SET '+QUOTENAME(@COLUMN_NAME)+' = Ticker
				OUTPUT NULL, X.LATER_DATE, ''NEXT'' INTO @OutVar
				FROM '+ QUOTENAME(@TABLE_NAME) +' l
					JOIN cte1 ON l.[DATE] = cte1.[DATE]
					CROSS JOIN cte2 
					JOIN (  SELECT	ROW_NUMBER() OVER (ORDER BY [date]) rn,
									[DATE] as LATER_DATE, 
									'+QUOTENAME(@COLUMN_NAME)+' as Ticker
						    FROM '+ QUOTENAME(@TABLE_NAME) +'
						 ) X 
                        ON cte2.rn2 = X.rn

				INSERT INTO PreProcessLog
				SELECT DISTINCT '''+@COLUMN_NAME+''', * from @OutVar 						  
			  '
	
	EXEC sp_executesql @SQL
	
	SET @SQL = '
				DECLARE @OutVar TABLE ( PRIOR_DATE  DATE
                                      , LATER_DATE  DATE
                                      , Method      NVARCHAR ( 20 )
                                      )
				;WITH cte1 AS 
                (
					SELECT rn1, [date] 
                    FROM (
						    SELECT ROW_NUMBER() OVER(ORDER BY [date] DESC) AS rn2, *
						    FROM (
							        SELECT	ROW_NUMBER() OVER (ORDER BY [date] DESC) rn1,
									        [date], ISNULL('+QUOTENAME(@COLUMN_NAME)+',0) as Ticker
							        FROM '+ QUOTENAME(@TABLE_NAME) +'
						         ) X
						    WHERE Ticker = 0
					     ) Y
					WHERE rn1 = rn2
				), 
				cte2 AS 
                (
					SELECT TOP 1 rn1+1 AS rn2 
                    FROM cte1 
                    ORDER BY rn1 DESC
				)
				UPDATE l
				SET '+QUOTENAME(@COLUMN_NAME)+' = Ticker
				OUTPUT X.PREV_DATE, NULL, ''PREV'' INTO @OutVar
				FROM '+ QUOTENAME(@TABLE_NAME) +' l
					JOIN cte1 ON l.[DATE] = cte1.[DATE]
					CROSS JOIN cte2 
					JOIN (  SELECT	ROW_NUMBER() OVER (ORDER BY [date] DESC) rn,
									[DATE] PREV_DATE, 
									'+QUOTENAME(@COLUMN_NAME)+' as Ticker
						    FROM '+ QUOTENAME(@TABLE_NAME) +'
						 ) X 
                        ON cte2.rn2 = X.rn
				
				INSERT INTO PreProcessLog
				SELECT DISTINCT '''+@COLUMN_NAME+''', * from @OutVar 
				'
	
	EXEC sp_executesql @SQL

END	 

/*
 procedure interpolates spaces with 2 or more zeros or null
*/
CREATE PROC FillInterpolatedSpacesSeries
	@TABLE_NAME		SysName
,	@COLUMN_NAME	SysName
AS
BEGIN

	SET NOCOUNT ON

	DECLARE @SQL NVARCHAR(MAX)

	SET @SQL = 
	'
	DECLARE @OutVar TABLE   (   PRIOR_DATE  DATE
                            ,   LATER_DATE  DATE
                            ,   Method      NVARCHAR ( 20 )
                            )
	;WITH value_rows AS
    (	
		SELECT ROW_NUMBER() OVER (ORDER BY id) rn, [value], id
        FROM (
				SELECT  * 
                FROM    (
					        SELECT ROW_NUMBER() OVER (ORDER BY DATE) id,
							        '+QUOTENAME(@COLUMN_NAME)+' as [value]
					        FROM '+ QUOTENAME(@TABLE_NAME) +'
			            ) X 
				WHERE ISNULL ( [value], 0 ) <> 0
			) Y
	), 
	step_change AS 
    (
		SELECT  c1.id                                           AS  [id_Start]
            ,   c2.id - 1                                       AS  [id_End]
            ,   c1.[value]
            ,   ( c2.[value] - c1.[value] ) / ( c2.id - c1.id ) AS  [change]

		FROM [value_rows]     AS  c1
			JOIN [value_rows] AS  c2 
                ON c1.rn = c2.rn-1
	)
	, new_values AS 
    (
		SELECT  s.[id]
            ,   s.[date]
            ,   COALESCE ( sc.[value], s.[value] )                              AS  [value]
            ,   COALESCE ( sc.[change], 0 )                                     AS  [change]
            ,   ROW_NUMBER() OVER (PARTITION BY sc.id_start ORDER BY s.id) - 1  AS  [coeff]
		
        FROM (	SELECT	ROW_NUMBER() OVER (ORDER BY DATE)   AS  [id], 
						[date], 
						'+QUOTENAME(@COLUMN_NAME)+'         AS  [value]
				FROM '+ QUOTENAME(@TABLE_NAME) +' 
             )             AS  s

		LEFT JOIN step_change AS sc 
            ON s.id BETWEEN sc.id_Start AND sc.id_End

		WHERE ( id_End - id_Start ) > 1
	),
	last_date AS 
    (
			SELECT  MIN ( X.date )      AS   [PREV_DATE]
                ,   MAX ( X.last_date)  AS   [LATER_DATE]
            FROM
				(
					SELECT LEAD(t.[DATE],1) OVER(ORDER BY t.DATE) AS    [last_date]
                        ,   t.date
                        ,   nv.value

					FROM '+ QUOTENAME(@TABLE_NAME) +' AS    t
						LEFT JOIN new_values AS nv 
                            ON nv.[DATE] = t.[DATE]
				) X
			WHERE [value] is not NULL
	)
	UPDATE l
	SET '+QUOTENAME(@COLUMN_NAME)+' = [value] + coeff * change
	OUTPUT ld.PREV_DATE, ld.LATER_DATE, ''INTERPOLATE'' INTO @OutVar
	FROM '+ QUOTENAME(@TABLE_NAME) +' AS  l
		JOIN new_values               AS  nw 
            ON nw.[DATE] = l.[DATE]
		CROSS JOIN last_date          AS  ld 
		
	INSERT INTO PreProcessLog
	SELECT DISTINCT '''+@COLUMN_NAME+''', * from @OutVar 		
	'
	EXEC sp_executesql @SQL
END


/*
 Procedure fills single spaces by prior date value
*/
CREATE PROC FillSingleSpaces 
	@TABLE_NAME		SysName
,	@COLUMN_NAME	SysName
AS
BEGIN
	SET NOCOUNT ON

	DECLARE @SQL NVARCHAR(MAX)

	SET @SQL = '
		DECLARE @OutVar TABLE   (   PRIOR_DATE  DATE
                                ,   LATER_DATE  DATE
                                ,   Method      NVARCHAR ( 20 ) 
                                )
		UPDATE N
		SET N.'+QUOTENAME(@COLUMN_NAME)+' = z.colName
		OUTPUT z.PRIOR_DATE, z.LATER_DATE, ''FF'' INTO @OutVar
		FROM '+ QUOTENAME(@TABLE_NAME) +' N
			JOIN (
					SELECT X.DATE, colName, PRIOR_DATE, LATER_DATE
					FROM '+ QUOTENAME(@TABLE_NAME) +' N
					JOIN ( 
						SELECT [DATE], IIF(ISNULL('+QUOTENAME(@COLUMN_NAME)+',0)=0, PRIOR_VALUE, '+QUOTENAME(@COLUMN_NAME)+') as colName, PRIOR_DATE, LATER_DATE
						FROM
						(
							SELECT	[DATE], 
									LAG('+QUOTENAME(@COLUMN_NAME)+',1) OVER(ORDER BY [DATE]) as PRIOR_VALUE, 
									LAG([DATE],1) OVER(ORDER BY [DATE]) as PRIOR_DATE, 
									LEAD([DATE],1) OVER(ORDER BY [DATE]) as LATER_DATE,
									'+QUOTENAME(@COLUMN_NAME)+' 
                            FROM '+ QUOTENAME(@TABLE_NAME) +'
						) AS Y
				 ) AS X 
                 ON N.[DATE] = X.[DATE] AND ISNULL('+QUOTENAME(@COLUMN_NAME)+',0)=0
			) AS Z 
            ON N.DATE = Z.DATE

		INSERT INTO PreProcessLog
		SELECT '''+@COLUMN_NAME+''', * from @OutVar 
	'

	EXEC sp_executesql @SQL

END



/*
procedure gets most and least value in column from last success load
*/
CREATE PROC GetLeastMost
		@dts DATE
,		@dte DATE
,		@startAmount FLOAT
,		@Ticker	SysName
AS
BEGIN
	DECLARE @tblName SysName

	SELECT @tblName = TABLE_NAME 

	FROM INFORMATION_SCHEMA.COLUMNS     AS  ic
		JOIN WorktablesLog AS t ON ic.TABLE_NAME  = t.tblName
		JOIN load_sessions AS s ON s.[session_id] = t.[session_id]

	WHERE ic.COLUMN_NAME = @Ticker
		AND s.[session_id] = (  SELECT MAX( [session_id] ) 
                                FROM Load_Sessions 
                                WHERE [state] = 0
                             )
		 
	DECLARE @SQL NVARCHAR(MAX)

	SET @SQL = '
        ;WITH cte1 AS 
        (
		    SELECT ROW_NUMBER() OVER(ORDER BY [DATE]) AS rn, DATE, '+QUOTENAME(@Ticker)+', 0 AS value
		    FROM '+QUOTENAME(@tblName)+'
		    WHERE [DATE] >= '''+CAST(@dts as NVARCHAR(10))+'''
		    AND [DATE] <= '''+CAST(@dte as NVARCHAR(10))+''' 
		    UNION 
		    SELECT 0, ''1900-01-01'', 1, 100
	    ),
	    cte0 AS 
        (
		    SELECT  c2.[value]*(1+c1.'+QUOTENAME(@Ticker)+') AS [value0], c1.*, c1.rn-1 AS rn2
		    FROM cte1 AS c1
			    JOIN cte1 AS c2 ON c1.rn-1 = c2.rn
	    ),
	    cte_rec AS 
        (
		    SELECT * FROM cte0 WHERE rn=1
		    UNION all
		    SELECT r.value0*(1+c2.'+QUOTENAME(@Ticker)+'), c2.rn, c2.DATE, c2.'+QUOTENAME(@Ticker)+', c2.value, r.rn2 
		    FROM cte0 AS c2
			    JOIN cte_rec r ON r.rn = c2.rn2
	    )

	    SELECT MIN(value0) AS [least], MAX(value0) AS [most] 
        FROM   cte_rec
	    OPTION (MAXRECURSION 0)'

	EXEC sp_executesql @SQL
END


