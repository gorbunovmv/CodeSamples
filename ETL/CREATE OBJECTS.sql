DROP TABLE IF EXISTS [dbo].[Load_Sessions]
GO
CREATE TABLE    [dbo].[Load_Sessions]
(
    [session_id]    INT IDENTITY ( 1, 1 )   NOT NULL
,   [dts]           DATETIME                NOT NULL
,   [dte]           DATETIME                NULL
,   [state]         INT                     NULL
,   CONSTRAINT      PK_SessionID    PRIMARY KEY    CLUSTERED 
    (
        session_ID
    )
)
GO
DROP TABLE IF EXISTS    [dbo].[WorktablesLog]
GO
CREATE TABLE    [dbo].[WorktablesLog]
(
    [session_id]    INT                     NOT NULL
,   [num]           INT                     NOT NULL
,   [tblName]       VARCHAR ( 100 )         NOT NULL
,   [dt_create]     DATETIME                NOT NULL
,   [dt_load]       DATETIME                    NULL
,   [dt_preProcess] DATETIME                    NULL
)
GO
/*
 procedure fills starting and ending zeroes or NULLs by nearest meaning value
*/
DROP PROCEDURE IF EXISTS [dbo].[FillStartingAndEndingSpaces] 
GO
CREATE PROCEDURE    [dbo].[FillStartingAndEndingSpaces]
    @P_TABLE_NAME       SysName
,   @P_COLUMN_NAME      SysName
AS
BEGIN
    SET NOCOUNT ON
    DECLARE @SQL    NVARCHAR    ( MAX )

    SET @SQL = '
                DECLARE @OutVar TABLE ( [PRIOR_DATE]    DATE
                                      , [LATER_DATE]    DATE
                                      , [Method]        NVARCHAR ( 20 )
                                      )
                    ;WITH [cte1]
                    AS  (
                            SELECT  [rn1]
                                 ,  [date]
                            FROM (
                                    SELECT  ROW_NUMBER () OVER ( ORDER BY [X].[date] )                  AS [rn2]
                                        ,   *
                                    FROM    (
                                                SELECT  ROW_NUMBER () OVER ( ORDER BY [date] )          AS [rn1]
                                                    ,   [date]
                                                    ,   ISNULL (' + QUOTENAME(@P_COLUMN_NAME) + ',0)    AS [Ticker]
                                                FROM '+ QUOTENAME(@P_TABLE_NAME) +'
                                            )   AS    [X]
                                    WHERE   [X].[Ticker] = 0
                            )   AS  [Y]
                            WHERE   [rn1] = [rn2]
                        ), 
                [cte2] AS 
                (
                    SELECT TOP 1 [rn1]+1 as [rn2] FROM [cte1] ORDER BY [rn1] DESC
                )
                UPDATE  [l]
                SET     '+QUOTENAME(@P_COLUMN_NAME)+' = [Ticker]
                OUTPUT  NULL
                    ,   [X].[LATER_DATE]
                    ,   ''NEXT'' 
                    INTO @OutVar
                FROM '+ QUOTENAME(@P_TABLE_NAME) +' AS [l]
                JOIN    [cte1]
                    ON  [cte1].[DATE] = [l].[DATE] 
                CROSS 
                    JOIN [cte2] 
                    JOIN (    SELECT    ROW_NUMBER() OVER ( ORDER BY [date] )   AS [rn]
                                    ,   [DATE]                                  AS [LATER_DATE]
                                    ,   ' + QUOTENAME(@P_COLUMN_NAME) + '       AS [Ticker]
                            FROM    ' + QUOTENAME(@P_TABLE_NAME) +'
                          ) AS [X] 
                        ON  [X].[rn] = [cte2].[rn2]

                INSERT INTO [dbo].[PreProcessLog]
                SELECT DISTINCT ''' + @P_COLUMN_NAME + ''', * FROM @OutVar                           
              '
   
    EXEC sp_executesql @SQL
    
    SET @SQL = '
                DECLARE @OutVar TABLE ( [PRIOR_DATE]    DATE
                                      , [LATER_DATE]    DATE
                                      , [Method]        NVARCHAR ( 20 )
                                      )
                ;WITH [cte1] AS 
                (
                    SELECT  [rn1]
                        ,   [date] 
                    FROM    
                        (
                            SELECT  ROW_NUMBER() OVER( ORDER BY [date] DESC )               AS [rn2]
                                ,   *
                            FROM (
                                    SELECT   ROW_NUMBER() OVER ( ORDER BY [date] DESC )     AS [rn1]
                                        ,    [date]
                                        ,    ISNULL(' + QUOTENAME(@P_COLUMN_NAME) + ',0 )   AS [Ticker]
                                    FROM '+ QUOTENAME(@P_TABLE_NAME) +'
                                 )  AS [X]
                            WHERE   [X].[Ticker] = 0
                         )  AS [Y]
                    WHERE [rn1] = [rn2]
                ), 
                [cte2] AS (
                    SELECT TOP 1 [rn1]+1 AS [rn2] FROM [cte1] ORDER BY [rn1] DESC
                )
                UPDATE   [l]
                SET      '+QUOTENAME(@P_COLUMN_NAME)+' = [Ticker]
                OUTPUT   [X].[PREV_DATE]
                    ,    NULL
                    ,    ''PREV'' 
                    INTO @OutVar
                FROM    '+ QUOTENAME(@P_TABLE_NAME) +' AS [l]
                    JOIN [cte1] 
                        ON [cte1].[DATE] = [l].[DATE] 
                    CROSS JOIN [cte2] 
                    JOIN (    SELECT    ROW_NUMBER() OVER (ORDER BY [date] DESC)    AS [rn]
                                    ,   [DATE] AS [PREV_DATE]
                                    ,   ' + QUOTENAME(@P_COLUMN_NAME) + '           AS [Ticker]
                              FROM  '+ QUOTENAME(@P_TABLE_NAME) +'
                         )  AS [X] 
                        ON [X].[rn] = [cte2].[rn2] 
                
                INSERT INTO [dbo].[PreProcessLog]
                SELECT DISTINCT '''+@P_COLUMN_NAME+''', * FROM @OutVar 
                '
    
    EXEC sp_executesql @SQL

END     

GO
/*
 procedure interpolates spaces with 2 or more zeros or null
*/
DROP PROCEDURE IF EXISTS [dbo].[FillInterpolatedSpacesSeries]
GO
CREATE PROCEDURE [dbo].[FillInterpolatedSpacesSeries]
    @P_TABLE_NAME    SysName
,   @P_COLUMN_NAME   SysName
AS
BEGIN

    SET NOCOUNT ON

    DECLARE @SQL NVARCHAR ( MAX )

    SET @SQL = 
    '
    DECLARE @OutVar TABLE    (    [PRIOR_DATE]    DATE
                             ,    [LATER_DATE]    DATE
                             ,    [Method]        NVARCHAR ( 20 )
                             )
    ;WITH [value_rows] AS 
    (    
        SELECT   ROW_NUMBER() OVER ( ORDER BY [id] )                            AS [rn]
            ,    [value]
            ,    [id]
        FROM    (
                    SELECT  * 
                    FROM    (
                                SELECT    ROW_NUMBER() OVER ( ORDER BY [DATE] ) AS [id]
                                    ,   ' + QUOTENAME(@P_COLUMN_NAME) + '       AS [value]
                                FROM    '+ QUOTENAME(@P_TABLE_NAME) +'
                            ) AS [X] 
                    WHERE   ISNULL( [value],0 ) <> 0
                ) AS [Y]
    ), 
    [step_change] AS 
    (
        SELECT   [c1].[id]                                    AS    [id_Start]
            ,    [c2].[id] - 1                                AS    [id_End]
            ,    [c1].[value]
            ,    ( [c2].[value] - [c1].[value] ) 
                 / 
                 ( [c2].[id] - [c1].[id] )                    AS    [change]
        FROM    [value_rows]                                  AS    [c1]
        JOIN    [value_rows] AS [c2] 
            ON  [c2].[rn]-1 = [c1].[rn]
    )
    , [new_values] AS 
    (
        SELECT   [s].[id]
            ,    [s].[date]
            ,    COALESCE( [sc].[value], [s].[value] )              AS [value]
            ,    COALESCE( [sc].[change], 0)                        AS [change]
            ,    ROW_NUMBER() OVER (    PARTITION BY [sc].[id_start] 
                                        ORDER BY     [s].[id]
                                  ) - 1                             AS [coeff]
        FROM (    SELECT    ROW_NUMBER() OVER (ORDER BY [date])     AS [id]
                       ,    [date]
                       ,    ' + QUOTENAME(@P_COLUMN_NAME) + '       AS [value]
                FROM '+ QUOTENAME(@P_TABLE_NAME) +' 
             )  AS [s]
        LEFT JOIN [step_change] AS [sc] 
            ON [s].[id] BETWEEN [sc].[id_Start] AND [sc].[id_End]
        WHERE ( [sc].[id_End] - [sc].[id_Start] ) > 1
    ),
    [last_date] AS 
    (
        SELECT  MIN ( [X].[date] )        AS [PREV_DATE]
            ,   MAX ( [X].[last_date])    AS [LATER_DATE]
        FROM (
                SELECT  LEAD( [t].[DATE], 1 ) OVER ( ORDER BY [t].[DATE] )    AS [last_date]
                    ,   [t].[date]
                    ,   [nv].[value]
                FROM    '+ QUOTENAME(@P_TABLE_NAME) +'    AS [t]
                    LEFT JOIN [new_values]                AS [nv] 
                        ON [nv].[DATE] = [t].[DATE] 
             )                                            AS [X]
        WHERE [X].[value] IS NOT NULL
    )
    UPDATE    [l]
    SET        '+QUOTENAME(@P_COLUMN_NAME)+' = [value] + [coeff] * [change]
    OUTPUT    [ld].[PREV_DATE]
        ,     [ld].[LATER_DATE]
        ,    ''INTERPOLATE'' 
        INTO @OutVar
    FROM    '+ QUOTENAME(@P_TABLE_NAME) +'  AS [l]
    JOIN    [new_values]    AS [nw] 
        ON  [nw].[DATE] = [l].[DATE] 
    CROSS 
        JOIN [last_date]    AS [ld] 
        
    INSERT INTO [dbo].[PreProcessLog]
    SELECT DISTINCT '''+@P_COLUMN_NAME+''', * FROM @OutVar         
    '
    EXEC sp_executesql @SQL
END

GO
/*
 Procedure fills single spaces by prior date value
*/
DROP PROCEDURE IF EXISTS [dbo].[FillSingleSpaces] 
GO
CREATE PROCEDURE [dbo].[FillSingleSpaces] 
     @P_TABLE_NAME    SysName
,    @P_COLUMN_NAME   SysName
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @SQL NVARCHAR(MAX)

    SET @SQL = '
        DECLARE @OutVar TABLE (    [PRIOR_DATE]    DATE
                              ,    [LATER_DATE]    DATE
                              ,    [Method]        NVARCHAR (20)
                              )
        UPDATE    [N]
        SET       N.' + QUOTENAME(@P_COLUMN_NAME) + ' = [z].[colName]
        OUTPUT    [z].[PRIOR_DATE]
            ,     [z].[LATER_DATE]
            ,     ''FF'' 
            INTO @OutVar
        FROM    '+ QUOTENAME(@P_TABLE_NAME) +'                AS [N]
            JOIN (
                    SELECT    [X].[DATE]
                        ,    [colName]
                        ,    [PRIOR_DATE]
                        ,    [LATER_DATE]
                    FROM    '+ QUOTENAME(@P_TABLE_NAME) +'    AS [N]
                    JOIN ( 
                            SELECT    [Y].[DATE]
                                ,     IIF ( ISNULL('+QUOTENAME(@P_COLUMN_NAME)+',0) = 0
                                          , [Y].[PRIOR_VALUE]
                                          , '+QUOTENAME(@P_COLUMN_NAME)+') AS [colName]
                                ,     [Y].[PRIOR_DATE]
                                ,     [Y].[LATER_DATE]
                            FROM    (
                                        SELECT    [DATE]
                                            ,     LAG (' +QUOTENAME(@P_COLUMN_NAME)+ ',1) OVER( ORDER BY [DATE] )    AS [PRIOR_VALUE]
                                            ,     LAG ( [DATE],1 ) OVER( ORDER BY [DATE] )                           AS [PRIOR_DATE]
                                            ,     LEAD( [DATE],1 ) OVER( ORDER BY [DATE] )                           AS [LATER_DATE]
                                            ,     '+QUOTENAME(@P_COLUMN_NAME)+' 
                                        FROM '+ QUOTENAME(@P_TABLE_NAME) +'
                                    ) AS [Y]
                         )    AS [X] 
                        ON    [X].[DATE] = [N].[DATE] 
                        AND ISNULL(' +QUOTENAME(@P_COLUMN_NAME)+ ',0) = 0
                 )    AS [Z] 
                ON [Z].[DATE] = [N].[DATE] 

        INSERT INTO [dbo].[PreProcessLog]
        SELECT '''+@P_COLUMN_NAME+''', * FROM @OutVar 
    '

    EXEC sp_executesql @SQL

END

GO

/*
procedure gets most and least value in column from last success load
*/
DROP PROCEDURE IF EXISTS [dbo].[GetLeastMost]
GO

CREATE PROCEDURE [dbo].[GetLeastMost]
     @dts            DATE
,    @dte            DATE
,    @startAmount    FLOAT
,    @Ticker         SysName
AS
BEGIN
    DECLARE @tblName SysName

    SELECT  @tblName    =    [ic].[TABLE_NAME] 
    FROM    INFORMATION_SCHEMA.COLUMNS                AS    [ic]
        JOIN [dbo].[WorktablesLog]                    AS    [t]
            ON [t].[tblName] = [ic].[TABLE_NAME] 
        JOIN [dbo].[Load_Sessions]                    AS    [s] 
            ON [s].[session_id] = [t].[session_id]
    WHERE   [ic].[COLUMN_NAME]  = @Ticker
        AND [s].[session_id]    = ( SELECT  MAX( [session_id] ) 
                                    FROM    [dbo].[Load_Sessions]
                                    WHERE   [state] = 0
                                  )
    DECLARE @SQL NVARCHAR(MAX)

    SET @SQL = 
        '
        ;WITH [cte1] AS 
        (
            SELECT   ROW_NUMBER() OVER( ORDER BY [DATE] )     AS [rn]
                ,    [DATE]
                ,    ' +QUOTENAME(@Ticker)+ '
                ,    0                                        AS [value]
            FROM    '+QUOTENAME(@tblName)+'
            WHERE    [DATE] >= ''' +CAST(@dts as NVARCHAR(10))+ '''
                AND  [DATE] <= ''' +CAST(@dte as NVARCHAR(10))+ ''' 
            UNION 
            SELECT   0
                ,    ''1900-01-01''
                ,    1
                ,    100
        ),
        [cte0] AS 
        (
            SELECT   [c2].[value] * ( 1+[c1].' +QUOTENAME(@Ticker)+')    AS [value0]
                ,    [c1].*
                ,    [c1].[rn]-1       AS    [rn2]
            FROM [cte1]                AS    [c1]
                JOIN [cte1] AS [c2] 
                    ON [c2].[rn] = [c1].[rn]-1 
        ),
        [cte_rec] AS 
        (
            SELECT  * 
            FROM    [cte0] 
            WHERE   [rn] = 1
            UNION ALL
            SELECT   [r].[value0] * (1+[c2].' +QUOTENAME(@Ticker)+')
                ,    [c2].[rn]
                ,    [c2].[DATE]
                ,    [c2].' +QUOTENAME(@Ticker)+ '
                ,    [c2].[value]
                ,    [r].[rn2]
            FROM     [cte0]       AS [c2]
                JOIN [cte_rec]    AS [r] 
                    ON [r].[rn] = [c2].[rn2]
        )
        SELECT  MIN( value0 ) AS [least]
            ,   MAX( value0 ) AS [most] 
        FROM    [cte_rec]
        OPTION(MAXRECURSION 0)'
    
    EXEC sp_executesql @SQL
END


