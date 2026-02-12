SET DATEFORMAT mdy

DECLARE @session_id	INT

INSERT INTO [dbo].[Load_Sessions]	( [dts]		)
VALUES								( GETDATE() )

SELECT	@session_id = MAX( [session_id] ) 
FROM	[dbo].[Load_Sessions]

DROP TABLE IF EXISTS #STAGE_russel2000raw
DROP TABLE IF EXISTS #preTableSet
DROP TABLE IF EXISTS [dbo].[PreProcessLog]

DECLARE @groups INT
	,	@tblNameTemplate VARCHAR (20) = N'loadTable'
	,	@CUR VARCHAR(MAX)
	,	@SQL NVARCHAR(MAX)

-- load file
CREATE TABLE #STAGE_russel2000raw
(	[DATE]	VARCHAR	( 19  )
,	[CUR]	VARCHAR	( 10  )
,	[amt1]	VARCHAR	( 100 )
,	[amt2]	VARCHAR	( 100 )
,	[amt3]	VARCHAR	( 100 )
,	[amt4]	VARCHAR	( 100 )
,	[amt5]	VARCHAR	( 100 )
,	[amt6]	VARCHAR	( 100 )
,	[amt7]	VARCHAR	( 100 )
)

BULK INSERT #STAGE_russel2000raw
FROM 
	--define your filepath here
	'C:\temp\test\russel2000raw\russel2000raw'
	WITH 
	(
	  FIELDTERMINATOR   = ','
	, ROWTERMINATOR     = '0x0a'
	)
CREATE NONCLUSTERED INDEX IX ON #STAGE_RUSSEL2000RAW ( [CUR] )

CREATE TABLE [dbo].[PreProcessLog]
(
	[Ticker]		VARCHAR ( 100 )
,	[PriorDate]		DATE
,	[LaterDate]		DATE
,	[Method]		VARCHAR ( 20  )
)	

DECLARE 	@columnsCnt INT 

--calculating groups count for split
SELECT @columnsCnt =	(	SELECT	COUNT( DISTINCT [CUR] ) 
							FROM	#STAGE_RUSSEL2000RAW
						)
IF ( @columnsCnt ) > 1024  -- SQL Server restrictions
	SET @groups = ( @columnsCnt/1024 ) + 1
ELSE 
	SET @groups = 1

-- splitting columns sets
SELECT	[groupNo]
	,	[CUR]
	,	@tblNameTemplate + CAST(groupNo as VARCHAR(5)) AS [tblName]
INTO	[#preTableSet]
FROM	(
			SELECT	NTILE(@groups) OVER ( ORDER BY [CUR] ) AS [groupNo]
				,	[CUR]
			FROM	(
						SELECT	DISTINCT [CUR] 
						FROM	#STAGE_RUSSEL2000RAW
					)	AS [X] 
		)	AS [Y]

-- creating worktables
DECLARE @groupNo    INT
DECLARE cr CURSOR FOR
SELECT DISTINCT [groupNo] FROM [#preTableSet]

OPEN cr
FETCH NEXT FROM cr INTO @groupNo
WHILE @@FETCH_STATUS = 0
BEGIN
	DECLARE @createColumns VARCHAR ( MAX )

	SELECT	@createColumns = STRING_AGG ( CAST( '['+CUR+'] FLOAT' AS VARCHAR(MAX)), ',' ) 
	FROM	#preTableSet
	WHERE	[groupNo] = @groupNo

	SET @SQL = 'CREATE TABLE '  + @tblNameTemplate 
							    + CAST(@session_id as VARCHAR(10)) +'_' 
							    + CAST(@groupNo as VARCHAR(5))+
			   '([DATE] DATE, ' + @createColumns + ')'

	EXEC sp_executesql @SQL

	INSERT INTO [dbo].[WorktablesLog]
			(	[session_id]
			,	[num]
			,	[tblName]
			,	[dt_create]
			)
	VALUES	(	@session_id
			,	@groupNo
			,	@tblNameTemplate 
				+ CAST( @session_id AS VARCHAR(10) ) 
				+ '_' 
				+ CAST( @groupNo AS VARCHAR(5) )
			,	GETDATE()
			)

	FETCH NEXT FROM cr INTO @groupNo
END

CLOSE cr
DEALLOCATE cr

-- Load Tables
DECLARE @num		INT
	,	@tblName	VARCHAR (100)

DECLARE crTables CURSOR FOR
SELECT	[num]
	,	[tblName]
FROM	[dbo].[WorktablesLog]
WHERE	[session_id] = @session_id

OPEN crTables 
FETCH NEXT FROM crTables INTO @num, @tblName

WHILE @@FETCH_STATUS = 0
BEGIN

	SELECT	@CUR = STRING_AGG( '[' +CAST(CUR AS VARCHAR(MAX))+ ']', ',' ) 
	FROM	[#preTableSet]
	WHERE	[groupNo] = @num
	
	SELECT @SQL = 
		'
		INSERT INTO '+@tblName+'
		SELECT * 
		FROM 
			(
				SELECT	CAST( [DATE] AS DATE)	AS [DATE]
					,	[CUR]
					,	CAST( [amt7] AS FLOAT ) AS [amt7] 
				FROM	[#STAGE_russel2000raw]
			)	AS [T]
		PIVOT (
			SUM( [amt7] )
			FOR [CUR] IN ('+@CUR+')
		) AS [P]'

	EXEC sp_executesql @SQL

	UPDATE	[w]
	SET		[w].[dt_Load] = GETDATE()
	FROM	[dbo].[WorktablesLog]	AS [w]
	WHERE	[w].[session_id]	= @session_id
		AND [w].[tblName]		= @tblName 

	FETCH NEXT FROM crTables INTO @num, @tblName
END
CLOSE crTables
DEALLOCATE crTables

UPDATE	[s]
SET		[s].[dte] = GETDATE()
	,	[state] = 0
FROM	[dbo].[Load_Sessions]	AS [s]
WHERE	[s].[session_id] = @session_id

-- Prerpocessing
DECLARE @TABLE_NAME  VARCHAR(100)
	,	@COLUMN_NAME VARCHAR(10)
		
DECLARE crFields CURSOR FOR 
SELECT	[ic].[TABLE_NAME]
	,	[ic].[COLUMN_NAME] 

FROM	INFORMATION_SCHEMA.COLUMNS	AS	[ic]
	JOIN	[dbo].[WorktablesLog]	AS	[l] 
		ON [l].[tblName] = [ic].[TABLE_NAME] 

WHERE	[l].[session_id]	=	@session_id
	AND [ic].[COLUMN_NAME]	<>	'DATE'

OPEN crFields 
FETCH NEXT FROM crFields INTO @TABLE_NAME, @COLUMN_NAME

WHILE @@FETCH_STATUS = 0
BEGIN

	EXEC FillStartingAndEndingSpaces	@TABLE_NAME,	@COLUMN_NAME
	EXEC FillInterpolatedSpacesSeries	@TABLE_NAME,	@COLUMN_NAME
	EXEC FillSingleSpaces				@TABLE_NAME,	@COLUMN_NAME

	FETCH NEXT FROM crFields INTO @TABLE_NAME, @COLUMN_NAME
END

CLOSE crFields
DEALLOCATE crFields

