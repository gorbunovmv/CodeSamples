/*
    EXEC GENERATE_DATA_SP 10,1,1,'20260216'
*/
DROP PROC IF EXISTS [dbo].[GENERATE_DATA_SP]
GO
CREATE PROC [dbo].[GENERATE_DATA_SP] 
     @p_cntClients      INT
,    @p_cntCards        INT
,    @p_cntTrans        INT
,    @p_Trans_dt        DATE -- should be within valid card dates
AS
BEGIN
    
    SET NOCOUNT ON 
        
    -- generating @p_cntClients clients
    EXEC [dbo].[CREATE_CLIENTS_SP]          @p_cntClients
    
    -- creating @p_cntCards for every client
    EXEC [dbo].[CREATE_CARDS_SP]            @p_cntCards

    -- generating @cntTrans transactions
    EXEC [dbo].[INSERT_TRANSACTIONS_SP]     @p_cntTrans
                                        ,   @p_Trans_dt

END

