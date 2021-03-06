USE [YODA]
GO
/****** Object:  StoredProcedure [dbo].[MoveBoToCurrentVersion]    Script Date: 23-Dec-18 15:59:56 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<SimoRML>
-- Create date: <02-12-2018>
-- Description:	<Move BO from old table version to the current version (FOR UPDATE) >
-- =============================================
ALTER PROCEDURE [dbo].[MoveFromTmp]
	@metBoId int
AS
BEGIN
	print '-----MoveBoToCurrentVersion-----';
	
	DECLARE @currentVersion int;
	DECLARE @table varchar(100);
		select @table = BO_DB_NAME, @currentVersion=[VERSION] from META_BO where META_BO_ID= @metBoId;
	DECLARE @table_tmp varchar(100); set @table_tmp = @table + 'tmp';
	
	print '@currentVersion : ' + convert(varchar,@table);
	print '@table : ' + convert(varchar,@table);
	print '@table_tmp : ' + convert(varchar,@table_tmp);

		
	DECLARE @oneField varchar(100);
	DECLARE @fields varchar(MAX) set @fields = 'BO_ID';
			
	DECLARE fields_cursor CURSOR FOR 
		select DB_NAME from META_FIELD where META_BO_ID = @metBoId AND [STATUS] <> 'NEW' AND FORM_TYPE not like 'subform-%';

	OPEN fields_cursor  
	FETCH NEXT FROM fields_cursor INTO @oneField

	WHILE @@FETCH_STATUS = 0  
	BEGIN  
		set @fields += ', ' + @onefield;
		FETCH NEXT FROM fields_cursor INTO @oneField
	END 

	CLOSE fields_cursor  
	DEALLOCATE fields_cursor 

	print '@fields : ' + @fields;
		
	Declare @insertStatement nvarchar(MAX);
		set @insertStatement = 'insert into ' + @table + '('+@fields+') select * from '+@table_tmp;
	print '@@insertStatement : ' + @insertStatement;

	exec sp_executesql @insertStatement;

	print '--------------------------------';
END

GO


-- [MoveFromTmp] 10