--FIO-string generating function
DROP FUNCTION IF EXISTS [dbo].[getString]
GO
CREATE FUNCTION    [dbo].[getString] 
(
    @p1 UNIQUEIDENTIFIER
)
RETURNS NVARCHAR ( 50 )
AS
BEGIN
    DECLARE    @str NVARCHAR ( 255 )

    SELECT    @str = CAST ( @p1 AS NVARCHAR ( 255 ) )

    SELECT    @str = REPLACE ( @str, [NUMBER], '' )
    FROM (
            SELECT    [NUMBER] 
            FROM    (
                        VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)
                    )   AS t( [NUMBER] )
         ) AS [X]

    RETURN REPLACE ( @str,'-','' )
END

GO 

--card number generating function
DROP FUNCTION IF EXISTS [dbo].[getCardNumber]
GO
CREATE FUNCTION [dbo].[getCardNumber] 
(
    @p_rnd FLOAT
)
RETURNS NVARCHAR ( 16 )
AS
BEGIN
    DECLARE @res NVARCHAR(16)

    SET @res = ( SELECT    RIGHT( STR( @p_rnd, 25, 8 ), 8 )
                         + RIGHT( STR( @p_rnd, 25, 8 ), 8 )
               )
    RETURN  @res
END

GO

--card duration generating function 
DROP FUNCTION IF EXISTS [dbo].[getCardDuration]
GO
CREATE FUNCTION [dbo].[getCardDuration] 
(
    @p_rnd FLOAT
)
RETURNS DATE
AS
BEGIN
    
    DECLARE  @res     DATE
        ,    @days    INT

    -- cards expire period will be from 1 till 9 days from now
    SET @days = ROUND ( @p_rnd*10, 0 )

    SET @days = ( SELECT    CASE WHEN @days <> 0 THEN @days  
                            ELSE 1 -- to avoid issuing card with 0 days
                            END
                ) 
    SET @res =  ( SELECT DATEADD ( day, @days, GETDATE() ) )
    
    RETURN @res
END

GO

-- customer list generating procedure 
DROP PROCEDURE IF EXISTS [dbo].[CREATE_CLIENTS_SP] 
GO
CREATE PROCEDURE [dbo].[CREATE_CLIENTS_SP] 
    @p_cntClients INT
AS
BEGIN
    
    SET NOCOUNT ON

    DECLARE @cnt INT = 0

    WHILE 1=1 
    BEGIN
        IF @cnt = @p_cntClients
        BREAK

        INSERT INTO [dbo].[Clients] 
        (
             [Last_Name]
        ,    [First_Name]
        ,    [Middle_Name]
        )
        SELECT   [dbo].[getString] ( NEWID() )
            ,    [dbo].[getString] ( NEWID() )
            ,    [dbo].[getString] ( NEWID() )
    
        SET @cnt += 1 
    END
END

GO 

-- transaction type generating function in range [1-4]
DROP FUNCTION IF EXISTS [dbo].[getActionType]
go
CREATE FUNCTION [dbo].[getActionType]
(
    @p_rnd FLOAT
)
RETURNS INT
AS
BEGIN
    DECLARE  @smallest   INT = 1
        ,    @biggest    INT = 4
        ,    @res        INT

    SET @res = FLOOR( @p_rnd * ( @biggest-@smallest+1 )) + @smallest

    RETURN  @res
END

GO

--transaction amount generation function in range [1-10]
DROP FUNCTION IF EXISTS [dbo].[getTransactionAmount]
GO
CREATE FUNCTION [dbo].[getTransactionAmount] 
(
    @p_rnd FLOAT
)
RETURNS NUMERIC ( 18, 2 )
AS
BEGIN
    DECLARE  @smallest   INT     = 1
        ,    @biggest    INT     = 10
        ,    @res        NUMERIC ( 18, 2 )

    SET @res = ROUND ( @p_rnd * ( @biggest-@smallest+1 ) + @smallest, 2 )

    RETURN @res
END

GO

-- cards generation procedure
DROP PROC IF EXISTS [dbo].[CREATE_CARDS_SP]
GO
CREATE PROC [dbo].[CREATE_CARDS_SP]
    @p_cntCards INT
AS
BEGIN
    -- there is no unambiguous definition of cards quantity (by client or random by all ), 
    -- so we'll generate @p_cntCards cards for every client 
    SET NOCOUNT ON
    
    DECLARE  @Client_ID    INT
        ,    @cnt          INT

    DECLARE crClients CURSOR FAST_FORWARD READ_ONLY FOR
    SELECT [Client_ID] FROM [dbo].[Clients]

    OPEN crClients

    FETCH FROM crClients INTO @Client_ID

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @cnt = 0        
        WHILE 1=1 BEGIN
            IF @cnt = @p_cntCards
            BREAK
            
            INSERT INTO [dbo].[Cards] 
            (
                 [Card_Number]
            ,    [Card_Holder]
            ,    [Valid_From]
            ,    [Valid_To]
            )
            SELECT 
                 [dbo].[getCardNumber]   ( RAND() )
            ,    @Client_ID
            ,    GETDATE ()                            -- card date issuing - today 
            ,    [dbo].[getCardDuration] ( RAND() )    -- card duration value is different for every card

            SET @cnt +=1
        END

        FETCH FROM crClients INTO @Client_ID
    END

    CLOSE       crClients
    DEALLOCATE  crClients

END

GO

-- inserting transactions procedure
DROP PROCEDURE IF EXISTS [dbo].[INSERT_TRANSACTIONS_SP]
GO
CREATE PROCEDURE [dbo].[INSERT_TRANSACTIONS_SP]
     @p_cntTrans    INT
,    @p_Trans_dt    DATE
AS 
BEGIN
    -- there is no unambiguous definition of transactions quantity (by client, by day or random by all ), 
    -- so we'll generate @p_cntTrans transactions for every card 
    SET NOCOUNT ON

    DECLARE  @Card_ID            INT
        ,    @Valid_From         DATE
        ,    @Valid_To           DATE
        ,    @TransactionAmount  INT
        ,    @Action_Type        SMALLINT
        ,    @cnt                INT

    DECLARE crCards CURSOR FAST_FORWARD READ_ONLY FOR
    SELECT 
         [Card_ID]
    ,    [Valid_From]
    ,    [Valid_To] 

    FROM [dbo].[Cards]

    OPEN crCards

    FETCH   FROM    crCards 
            INTO    @Card_ID
                ,   @Valid_From
                ,   @Valid_To

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @cnt = 0        
        WHILE 1=1 BEGIN
            IF @cnt = @p_cntTrans
            BREAK
            
            SET @Action_Type       = [dbo].[getActionType]( RAND() )
            SET @TransactionAmount = [dbo].[getTransactionAmount]( RAND() )

            IF @p_Trans_dt NOT BETWEEN @Valid_From AND @Valid_To 
            BEGIN
                INSERT INTO [dbo].[LogMessages] ( [text] )
                SELECT  N'Card ' + [Card_Number] + N' is expired'
                FROM    [dbo].[Cards]
                WHERE   [Card_ID] = @Card_ID

                BREAK
            END
            ELSE 
                IF  (   SELECT  [sign]
                        FROM    [dbo].[Action_Types]
                        WHERE   [Action_Type_ID] = @Action_Type
                    ) = -1
                    AND 
                    (   SELECT  [Balance] 
                        FROM    [dbo].[Cards]
                        WHERE   [Card_ID] = @Card_ID
                    ) < @TransactionAmount 
                BEGIN
                        INSERT INTO [dbo].[LogMessages] ( [text] )
                        SELECT    N'Card remain ' + Card_Number + N' is not enough for transactioning'
                                + ( SELECT   [Action_Type_Desc] 
                                    FROM     [dbo].[Action_Types] 
                                    WHERE    [Action_Type_Id] = @Action_Type
                                  )
                                + N' amount '+ CAST(@TransactionAmount AS NVARCHAR( 20 ))
                                + N'. Avaliable funds: '+ CAST( [Balance] AS NVARCHAR( 20 )) 
                        FROM    [dbo].[Cards]
                        WHERE   [Card_ID] = @Card_ID
                    
                    BREAK
                END
                ELSE
                    BEGIN TRAN

                        INSERT INTO [dbo].[Transactions]
                        SELECT   NEWID()
                            ,    @Card_ID
                            ,    @p_Trans_dt
                            ,    @Action_Type
                            ,    @TransactionAmount

                        UPDATE   [c]
                        SET      [Balance] = [Balance] + @TransactionAmount * [CA].[sign]
                        FROM     [dbo].[Cards] AS [c]
                        CROSS APPLY 
                        (
                            SELECT  [sign] 
                            FROM    [dbo].[Action_Types]
                            WHERE   [Action_Type_ID] = @Action_Type
                        )   AS  [CA]
                        WHERE   [c].[Card_ID] = @Card_ID

                    COMMIT TRAN
            SET @cnt += 1
        END

        FETCH   FROM crCards 
                INTO @Card_ID
                 ,   @Valid_From
                 ,   @Valid_To
    END

    CLOSE crCards
    DEALLOCATE crCards
        
END