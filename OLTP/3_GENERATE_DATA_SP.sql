/*
	EXEC GENERATE_DATA_SP 10,1,1,'20210714'
*/
DROP PROC IF EXISTS GENERATE_DATA_SP
go
CREATE PROC GENERATE_DATA_SP (
	@cntClients	INT,
	@cntCards	INT,
	@cntTrans	INT,
	@Trans_dt	DATE
)
AS
BEGIN
	
	SET NOCOUNT ON 
		
	-- ������� @cntClients ��������
	EXEC CREATE_CLIENTS_SP @cntClients
	
	-- ��������� @cntCards ��� ������� �������
	EXEC CREATE_CARDS_SP @cntCards

	--������� @cntTrans ��������
	EXEC INSERT_TRANSACTIONS_SP @cntTrans, @Trans_dt

END

