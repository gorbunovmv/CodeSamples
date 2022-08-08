SET DATEFORMAT mdy

DECLARE @session_id	INT

INSERT INTO Load_Sessions (dts)
VALUES (GETDATE())

SELECT @session_id = MAX(session_id) FROM Load_Sessions

DROP TABLE IF EXISTS #STAGE_russel2000raw
DROP TABLE IF EXISTS #preTableSet
DROP TABLE IF EXISTS PreProcessLog

DECLARE @groups INT,
		@tblNameTemplate VARCHAR(20) = N'loadTable',
		@CUR VARCHAR(MAX),
		@SQL NVARCHAR(MAX)

-- load file
CREATE TABLE #STAGE_russel2000raw
(
	  [DATE] VARCHAR(19)
	, CUR	 VARCHAR(10)
	, amt1	 VARCHAR(100)
	, amt2	 VARCHAR(100)
	, amt3	 VARCHAR(100)
	, amt4	 VARCHAR(100)
	, amt5	 VARCHAR(100)
	, amt6	 VARCHAR(100)
	, amt7	 VARCHAR(100)
)

BULK INSERT #STAGE_russel2000raw
FROM 
	'C:\Users\Admin\Desktop\TEST\russel2000raw'
	WITH (
	  FIELDTERMINATOR  = ','
	, ROWTERMINATOR = '0x0a'
	)
CREATE NONCLUSTERED INDEX IX ON #STAGE_RUSSEL2000RAW (CUR)

CREATE TABLE PreProcessLog 
(
	Ticker		VARCHAR(100),
	PriorDate	DATE,
	LaterDate	DATE,
	Method		VARCHAR(20)
)	

DECLARE 	@columnsCnt INT 

--calculating groups count for split
SELECT @columnsCnt = (SELECT COUNT(DISTINCT CUR) FROM #STAGE_RUSSEL2000RAW)
IF (@columnsCnt) > 1024 
	SET @groups = (@columnsCnt/1024)+1
ELSE 
	SET @groups = 1

-- splitting columns sets
SELECT groupNo, CUR, @tblNameTemplate + CAST(groupNo as VARCHAR(5)) as tblName
INTO #preTableSet
FROM (
		SELECT NTILE(@groups) OVER (ORDER BY CUR) as groupNo, CUR
		FROM (
			SELECT DISTINCT CUR FROM #STAGE_RUSSEL2000RAW
		) X 
) Y

-- creating worktables
DECLARE @groupNo INT
DECLARE cr CURSOR FOR
SELECT DISTINCT groupNo FROM #preTableSet

OPEN cr
FETCH NEXT FROM cr INTO @groupNo
WHILE @@FETCH_STATUS = 0
BEGIN
	DECLARE @createColumns VARCHAR(MAX)

	SELECT @createColumns = STRING_AGG(CAST('['+CUR+'] FLOAT' as VARCHAR(MAX)),',') FROM #preTableSet
	WHERE groupNo = @groupNo

	SET @SQL = 'CREATE TABLE '  + @tblNameTemplate 
							    + CAST(@session_id as VARCHAR(10)) +'_' 
							    + CAST(@groupNo as VARCHAR(5))+
			   '([DATE] DATE, ' + @createColumns + ')'

	EXEC sp_executesql @SQL

	INSERT INTO WorktablesLog (session_id, num, tblName, dt_create)
	VALUES(	@session_id,
			@groupNo, 
			@tblNameTemplate + CAST(@session_id as VARCHAR(10)) +'_' + CAST(@groupNo as VARCHAR(5)),
			GETDATE())

	FETCH NEXT FROM cr INTO @groupNo
END

CLOSE cr
DEALLOCATE cr

-- Load Tables
DECLARE @num INT,
		@tblName VARCHAR(100)

DECLARE crTables CURSOR FOR
SELECT num, tblName 
FROM WorktablesLog
WHERE session_id = @session_id

OPEN crTables 
FETCH NEXT FROM crTables INTO @num, @tblName

WHILE @@FETCH_STATUS = 0
BEGIN

	SELECT @CUR = STRING_AGG('['+CAST(CUR AS VARCHAR(MAX))+']',',') 
	FROM #preTableSet
	WHERE groupNo = @num
	
	SELECT @SQL = '
		INSERT INTO '+@tblName+'
		SELECT * 
		FROM 
		(
			SELECT CAST([DATE] AS DATE) as [DATE], CUR, CAST(amt7 as FLOAT) as amt7 FROM #STAGE_russel2000raw
		) T
		PIVOT (
			SUM(amt7)
			FOR CUR IN ('+@CUR+')
		) AS P'

	EXEC sp_executesql @SQL

	UPDATE WorktablesLog
	SET dt_Load = GETDATE()
	WHERE session_id = @session_id
		AND tblName = @tblName 

	FETCH NEXT FROM crTables INTO @num, @tblName
END
CLOSE crTables
DEALLOCATE crTables

UPDATE Load_Sessions
SET dte = GETDATE(), [state] = 0
WHERE session_id = @session_id

-- Prerpocessing
DECLARE @TABLE_NAME  VARCHAR(100),
		@COLUMN_NAME VARCHAR(10)
		
DECLARE crFields CURSOR FOR 
SELECT TABLE_NAME, COLUMN_NAME 
FROM INFORMATION_SCHEMA.COLUMNS ic
	JOIN WorktablesLog l ON ic.TABLE_NAME = l.tblName
WHERE l.session_id = @session_id
	AND COLUMN_NAME <> 'DATE'

OPEN crFields 
FETCH NEXT FROM crFields INTO @TABLE_NAME, @COLUMN_NAME

WHILE @@FETCH_STATUS = 0
BEGIN

	EXEC FillStartingAndEndingSpaces @TABLE_NAME, @COLUMN_NAME
	EXEC FillInterpolatedSpacesSeries @TABLE_NAME, @COLUMN_NAME
	EXEC FillSingleSpaces @TABLE_NAME, @COLUMN_NAME

	FETCH NEXT FROM crFields INTO @TABLE_NAME, @COLUMN_NAME
END

CLOSE crFields
DEALLOCATE crFields

