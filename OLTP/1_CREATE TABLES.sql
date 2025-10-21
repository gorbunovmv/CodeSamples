CREATE TABLE    Clients 
(	
    Client_ID	BIGINT IDENTITY ( 1,  1 )   PRIMARY KEY
,	Last_Name	NVARCHAR        ( 50    )   NOT NULL
,	First_Name	NVARCHAR        ( 50    )   NOT NULL
, 	Middle_Name	NVARCHAR        ( 50    )       NULL
)

CREATE TABLE    Cards 
(	
    Card_ID		BIGINT IDENTITY ( 1, 1  )           PRIMARY KEY
,	Card_Number	NVARCHAR        ( 16    )           NOT NULL
,	Card_Holder	BIGINT                              NOT NULL
, 	Valid_From	DATE                                NOT NULL
,	Valid_To	DATE                                NOT NULL
,	Balance		NUMERIC         ( 18, 2 )           DEFAULT     0

	CONSTRAINT  FK_Clients FOREIGN KEY  ( Card_Holder ) 
                           REFERENCES   Clients ( Client_ID )
)

CREATE TABLE    Transactions 
(	
    Tran_ID		UNIQUEIDENTIFIER PRIMARY KEY
,	Card_ID		BIGINT                              NOT NULL
, 	Tran_Dt		DATE                                NOT NULL
,	Action_Type	INT                                 NOT NULL
,	Amount		NUMERIC         ( 18, 2 )           NOT NULL

,	CONSTRAINT FK_Cards FOREIGN KEY ( Card_ID )
                        REFERENCES  Cards ( Card_ID )
)

CREATE TABLE    Action_Types 
(
	Action_Type_ID      INT IDENTITY    ( 1, 1 )    PRIMARY KEY
,	Action_Type_Desc    NVARCHAR        ( 50   )
,	[Sign]	            SMALLINT
)

INSERT INTO Action_Types 
(   Action_Type_Desc
,   [Sign]
)
VALUES  (  N'IN',     1                )
    ,   (  N'OUT',   -1                )
    ,   ( N'AdjustmentPositive',    1  )
    ,   ( N'AdjustmentNegative',   -1  )

CREATE TABLE LogMessages 
(
    [text]      NVARCHAR         ( MAX )
,	[timestamp] DATETIME DEFAULT GETUTCDATE ( )
)
