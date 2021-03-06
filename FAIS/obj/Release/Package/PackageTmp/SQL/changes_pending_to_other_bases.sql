﻿SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<SimoRML>
-- Create date: <25/03/2019>
-- =============================================
CREATE PROCEDURE dbo.GetSubForm
	@meta_bo_id int
AS
BEGIN

	select replace(FORM_TYPE,'subform-', '') as subform from META_FIELD 
	where META_BO_ID = @meta_bo_id AND FORM_TYPE like 'subform-%'

END
GO

CREATE PROCEDURE dbo.GetSubFormId
	@meta_bo_id int
AS
BEGIN
	DECLARE @sub varchar(50);
	select @sub = replace(FORM_TYPE,'subform-', '') from META_FIELD 
	where META_BO_ID = @meta_bo_id AND FORM_TYPE like 'subform-%'

	SELECT META_BO_ID FROM META_BO WHERE BO_DB_NAME = @sub;
END

GO

/****** Object:  Table [dbo].[BO_ROLE]    Script Date: 14-Mar-19 11:23:51 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  TABLE [dbo].[BO_ROLE](
	[BO_ROLE_ID] [bigint] IDENTITY(1,1) NOT NULL,
	[META_BO_ID] [bigint] NOT NULL,
	[ROLE_ID] [nvarchar](128) NOT NULL,
	[CAN_READ] [bit] NULL,
	[CAN_WRITE] [bit] NULL,
	[CREATED_BY] [varchar](100) NULL,
	[CREATED_DATE] [datetime] NULL,
	[UPDATED_BY] [varchar](100) NULL,
	[UPDATED_DATE] [datetime] NULL,
	[STATUS] [varchar](10) NULL,
 CONSTRAINT [PK_BO_ROLE] PRIMARY KEY CLUSTERED 
(
	[BO_ROLE_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[BO_ROLE] ADD  CONSTRAINT [DF_BO_ROLE__READ]  DEFAULT ((0)) FOR [CAN_READ]
GO

ALTER TABLE [dbo].[BO_ROLE] ADD  CONSTRAINT [DF_BO_ROLE__WRITE]  DEFAULT ((0)) FOR [CAN_WRITE]
GO

ALTER TABLE [dbo].[BO_ROLE] ADD  DEFAULT (getdate()) FOR [CREATED_DATE]
GO

ALTER TABLE [dbo].[BO_ROLE] ADD  DEFAULT (getdate()) FOR [UPDATED_DATE]
GO

DROP TABLE [dbo].[PAGE]
/****** Object:  Table [dbo].[PAGE]    Script Date: 19/03/2019 11:24:12 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[PAGE](
       [BO_ID] [bigint] NOT NULL,
       [TITLE] [varchar](50) NULL,
       [GROUPE] [varchar](50) NULL,
       [STATUS] [varchar](10) NULL,
       [LAYOUT] [nvarchar](max) NULL,
       [CREATED_DATE] [datetime] NULL,
       [CREATED_BY] [varchar](100) NULL,
       [UPDATED_DATE] [datetime] NULL,
       [UPDATED_BY] [varchar](100) NULL,
CONSTRAINT [PK_PAGE] PRIMARY KEY CLUSTERED 
(
       [BO_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[InitMetaBo]
AS
BEGIN

IF not exists( SELECT object_id 
FROM sys.indexes 
WHERE name='UNIQUE_META_BO_BO_DB_NAME' AND object_id = OBJECT_ID('dbo.META_BO')
)
BEGIN
       CREATE UNIQUE INDEX UNIQUE_META_BO_BO_DB_NAME   
   ON dbo.META_BO (BO_DB_NAME);   
END

IF not exists( SELECT object_id 
FROM sys.indexes 
WHERE name='UNIQUE_META_FIELD_DB_NAME' AND object_id = OBJECT_ID('dbo.META_FIELD')
)
BEGIN
       CREATE UNIQUE INDEX UNIQUE_META_FIELD_DB_NAME
       ON dbo.META_FIELD (META_BO_ID, DB_NAME);   
END

delete from META_FIELD;
delete from VERSIONS;
delete from META_BO;
delete from bo;
SET IDENTITY_INSERT [dbo].[META_BO] OFF;
SET IDENTITY_INSERT [dbo].[META_FIELD] OFF;

SET IDENTITY_INSERT [dbo].[META_BO] ON ;
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE]) 
VALUES (1, N'META_BO', 1, N'admin', CAST(N'2018-11-11T13:06:41.347' AS DateTime), N'admin', CAST(N'2018-11-11T13:06:41.347' AS DateTime), N'-1', N'META_BO', NULL);

INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE]) 
VALUES (2, N'WORKFLOW', 1, N'admin', CAST(N'2018-12-18T13:06:41.347' AS DateTime), N'admin', CAST(N'2018-12-18T13:06:41.347' AS DateTime), N'-1', N'WORKFLOW', NULL);
/*PAGE */
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (3, N'Page', 1, N'admin', CAST(N'2019-03-16T17:53:01.400' AS DateTime), N'admin', CAST(N'2019-03-16T17:53:01.400' AS DateTime), N'-1', N'PAGE', N'form', N'{"TITLE":"","GROUPE":null}')
SET IDENTITY_INSERT [dbo].[META_BO] OFF;
SET IDENTITY_INSERT [dbo].[META_FIELD] ON ;
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION]) VALUES (1, 1, N'META_BO_ID', N'bigint', 0, N'#', NULL, 0, N'', NULL, N'', NULL, 0, 0, NULL, NULL, N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'PK', NULL);
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION]) VALUES (2, 1, N'BO_NAME', N'varchar(100)', 1, N'Nom', NULL, 1, N'Nom', NULL, N'v-text', NULL, 1, 0, 0, NULL, N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'amdin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'LOCKED', NULL);
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION]) VALUES (3, 1, N'STATUS', N'varchar(50)', 1, N'Nom', NULL, 1, N'STATUS', NULL, N'v-label', NULL, 1, 0, NULL, N'PENDING', N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'LOCKED', NULL);
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION]) VALUES (4, 1, N'TYPE', N'varchar(50)', 1, N'Type', N'{"fct":"Display","source":"TYPE"}', 1, N'Type', NULL, N'v-select', N'[{ "Value": "form", "Display": "FORM" }, { "Value": "subform", "Display": "SUB FORM" }]', 1, 0, NULL, N'form', N'admin', CAST(N'2018-12-03T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-03T13:10:28.673' AS DateTime), N'LOCKED', NULL);

INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION]) 
VALUES (5, 2, N'LIBELLE', N'varchar(50)', 1, N'Libelle', '', 1, N'Libelle', NULL, N'v-text', '', 1, 0, NULL, N'form', N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'LOCKED', NULL);
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION]) 
VALUES (6, 2, N'ACTIVE', N'int', 1, N'Active', '', 1, N'Active', NULL, N'v-checkbox', '', 1, 0, NULL, N'form', N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'LOCKED', NULL);
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION]) 
VALUES (7, 2, N'additional.column', '', 1, N'', '{"type":"button", "color":"btn-success","icon":"add","action":"redirect", "data":"#workflow.home"}', 1, N'', NULL, N'', '', 0, 0, NULL, N'form', N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'LOCKED', NULL);
/*PAGE FIELD*/
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) 
VALUES (8, 3, N'TITLE', N'varchar(100)', 1, N'TITLE', NULL, 1, N'TITLE', NULL, N'v-text', N'', 1, 0, 0, NULL, N'admin', NULL, N'admin', NULL, N'LOCKED', NULL, N'')
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION]) 
VALUES (9, 3, N'additional.column', '', 1, N'', '{"type":"button", "color":"btn-success","icon":"settings","action":"redirect", "data":"#admin.page"}', 1, N'', NULL, N'', '', 0, 0, NULL, N'form', N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'LOCKED', NULL);

SET IDENTITY_INSERT [dbo].[META_FIELD] OFF;

DECLARE @tname varchar(100);
DECLARE @sql nvarchar(100);
DECLARE _bo_cursor CURSOR FOR 
             SELECT t.name FROM SYSOBJECTS t WHERE xtype in ( 'U' ) AND (t.name like '%_BO_%' );

OPEN _bo_cursor  
FETCH NEXT FROM _bo_cursor INTO @tname

WHILE @@FETCH_STATUS = 0  
BEGIN  
       SET @sql = 'DROP TABLE ' + @tname;
       EXEC sp_executesql @sql;
       FETCH NEXT FROM _bo_cursor INTO @tname
END 

CLOSE _bo_cursor  
DEALLOCATE _bo_cursor 

END
GO


GO

SET IDENTITY_INSERT [dbo].[META_BO] ON ;
/*PAGE */
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (3, N'Page', 1, N'admin', CAST(N'2019-03-16T17:53:01.400' AS DateTime), N'admin', CAST(N'2019-03-16T17:53:01.400' AS DateTime), N'-1', N'PAGE', N'form', N'{"TITLE":"","GROUPE":null}')
SET IDENTITY_INSERT [dbo].[META_BO] OFF;
SET IDENTITY_INSERT [dbo].[META_FIELD] ON ;
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) 
VALUES (8, 3, N'TITLE', N'varchar(100)', 1, N'TITLE', NULL, 1, N'TITLE', NULL, N'v-text', N'', 1, 0, 0, NULL, N'admin', NULL, N'admin', NULL, N'LOCKED', NULL, N'')
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION]) 
VALUES (9, 3, N'additional.column', '', 1, N'', '{"type":"button", "color":"btn-success","icon":"settings","action":"redirect", "data":"#admin.page"}', 1, N'', NULL, N'', '', 0, 0, NULL, N'form', N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'LOCKED', NULL);

SET IDENTITY_INSERT [dbo].[META_FIELD] OFF;

GO

USE [YODA]
GO
/****** Object:  StoredProcedure [dbo].[PlusSequenceNextID]    Script Date: 05-Apr-19 11:47:22 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<SimoRML>
-- Create date: <08/02/2019>
-- Description:	<Identity by source (ex: BLABLA_513)>
-- =============================================
ALTER PROCEDURE [dbo].[PlusSequenceNextID]
	@cle varchar(500),
	@TableName varchar(500),
	@stepBy int,
	@presist int
AS
BEGIN
	SET NOCOUNT ON; 

	DECLARE @SequenceID int;
	DECLARE @StartValue int;
	DECLARE @CurrentValue int;
	-- INITIATE SEQUENCE
	select @SequenceID = SequenceID from PlusSequence where cle = @cle AND TableName = @TableName
    if @SequenceID is null
	Begin
		insert into PlusSequence (cle, TableName, StartValue, StepBy, CurrentValue)
		values (@cle, @TableName, 1, @stepBy, 0);
		SELECT @SequenceID = SCOPE_IDENTITY();
	END	

	-- CALCULATE NEXT ID
	select @StartValue=StartValue, @StepBy=StepBy, @CurrentValue=CurrentValue from PlusSequence where SequenceID = @SequenceID;

	if @CurrentValue < @StartValue 
	begin
		SET @CurrentValue = @StartValue;
	end
	else
	begin		
		SET @CurrentValue = @CurrentValue + @StepBy;
	end

	if @presist = 1
	begin
		update PlusSequence set CurrentValue = @CurrentValue where SequenceID = @SequenceID;
	end
	select convert(varchar,@CurrentValue);
END
