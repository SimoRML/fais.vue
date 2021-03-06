USE [YODA]
GO
/****** Object:  UserDefinedFunction [dbo].[GetJsonStringValue]    Script Date: 16-Mar-19 16:09:23 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE function [dbo].[GetJsonStringValue](@Key varchar(100), @data nvarchar(max))
returns varchar(max)
as
begin
    declare @keyIdx int = charindex(@Key, @data)
    declare @valueIdx int = @keyIdx + len(@Key) + 3 -- +3 to account for characters between key and value
    declare @termIdx int = charindex('"', @data, @valueIdx)

    declare @valueLength int = @termIdx - @valueIdx
    declare @retValue varchar(max) = substring(@data, @valueIdx, @valueLength)
    return @retValue
end
GO
/****** Object:  UserDefinedFunction [dbo].[JSON_VALUE_]    Script Date: 16-Mar-19 16:09:23 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE function [dbo].[JSON_VALUE_](@data nvarchar(max), @Key varchar(100))
returns varchar(max)
as
begin
    DECLARE @value varchar(max);
	select @value = stringValue  from dbo.parseJSON(@data) where NAME =replace(@Key,'$.','')
	return @value;
end
GO
/****** Object:  UserDefinedFunction [dbo].[parseJSON]    Script Date: 16-Mar-19 16:09:23 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[parseJSON]( @JSON NVARCHAR(MAX))
	RETURNS @hierarchy TABLE
	  (
	   element_id INT IDENTITY(1, 1) NOT NULL, /* internal surrogate primary key gives the order of parsing and the list order */
	   sequenceNo [int] NULL, /* the place in the sequence for the element */
	   parent_ID INT,/* if the element has a parent then it is in this column. The document is the ultimate parent, so you can get the structure from recursing from the document */
	   Object_ID INT,/* each list or object has an object id. This ties all elements to a parent. Lists are treated as objects here */
	   NAME NVARCHAR(2000),/* the name of the object */
	   StringValue NVARCHAR(MAX) NOT NULL,/*the string representation of the value of the element. */
	   ValueType VARCHAR(10) NOT null /* the declared type of the value represented as a string in StringValue*/
	  )
	AS
	BEGIN
	  DECLARE
	    @FirstObject INT, --the index of the first open bracket found in the JSON string
	    @OpenDelimiter INT,--the index of the next open bracket found in the JSON string
	    @NextOpenDelimiter INT,--the index of subsequent open bracket found in the JSON string
	    @NextCloseDelimiter INT,--the index of subsequent close bracket found in the JSON string
	    @Type NVARCHAR(10),--whether it denotes an object or an array
	    @NextCloseDelimiterChar CHAR(1),--either a '}' or a ']'
	    @Contents NVARCHAR(MAX), --the unparsed contents of the bracketed expression
	    @Start INT, --index of the start of the token that you are parsing
	    @end INT,--index of the end of the token that you are parsing
	    @param INT,--the parameter at the end of the next Object/Array token
	    @EndOfName INT,--the index of the start of the parameter at end of Object/Array token
	    @token NVARCHAR(200),--either a string or object
	    @value NVARCHAR(MAX), -- the value as a string
	    @SequenceNo int, -- the sequence number within a list
	    @name NVARCHAR(200), --the name as a string
	    @parent_ID INT,--the next parent ID to allocate
	    @lenJSON INT,--the current length of the JSON String
	    @characters NCHAR(36),--used to convert hex to decimal
	    @result BIGINT,--the value of the hex symbol being parsed
	    @index SMALLINT,--used for parsing the hex value
	    @Escape INT --the index of the next escape character
	    
	  DECLARE @Strings TABLE /* in this temporary table we keep all strings, even the names of the elements, since they are 'escaped' in a different way, and may contain, unescaped, brackets denoting objects or lists. These are replaced in the JSON string by tokens representing the string */
	    (
	     String_ID INT IDENTITY(1, 1),
	     StringValue NVARCHAR(MAX)
	    )
	  SELECT--initialise the characters to convert hex to ascii
	    @characters='0123456789abcdefghijklmnopqrstuvwxyz',
	    @SequenceNo=0, --set the sequence no. to something sensible.
	  /* firstly we process all strings. This is done because [{} and ] aren't escaped in strings, which complicates an iterative parse. */
	    @parent_ID=0;
	  WHILE 1=1 --forever until there is nothing more to do
	    BEGIN
	      SELECT
	        @start=PATINDEX('%[^a-zA-Z]["]%', @json collate SQL_Latin1_General_CP850_Bin);--next delimited string
	      IF @start=0 BREAK --no more so drop through the WHILE loop
	      IF SUBSTRING(@json, @start+1, 1)='"' 
	        BEGIN --Delimited Name
	          SET @start=@Start+1;
	          SET @end=PATINDEX('%[^\]["]%', RIGHT(@json, LEN(@json+'|')-@start) collate SQL_Latin1_General_CP850_Bin);
	        END
	      IF @end=0 --no end delimiter to last string
	        BREAK --no more
	      SELECT @token=SUBSTRING(@json, @start+1, @end-1)
	      --now put in the escaped control characters
	      SELECT @token=REPLACE(@token, FROMString, TOString)
	      FROM
	        (SELECT
	          '\"' AS FromString, '"' AS ToString
	         UNION ALL SELECT '\\', '\'
	         UNION ALL SELECT '\/', '/'
	         UNION ALL SELECT '\b', CHAR(08)
	         UNION ALL SELECT '\f', CHAR(12)
	         UNION ALL SELECT '\n', CHAR(10)
	         UNION ALL SELECT '\r', CHAR(13)
	         UNION ALL SELECT '\t', CHAR(09)
	        ) substitutions
	      SELECT @result=0, @escape=1
	  --Begin to take out any hex escape codes
	      WHILE @escape>0
	        BEGIN
	          SELECT @index=0,
	          --find the next hex escape sequence
	          @escape=PATINDEX('%\x[0-9a-f][0-9a-f][0-9a-f][0-9a-f]%', @token collate SQL_Latin1_General_CP850_Bin)
	          IF @escape>0 --if there is one
	            BEGIN
	              WHILE @index<4 --there are always four digits to a \x sequence   
	                BEGIN
	                  SELECT --determine its value
	                    @result=@result+POWER(16, @index)
	                    *(CHARINDEX(SUBSTRING(@token, @escape+2+3-@index, 1),
	                                @characters)-1), @index=@index+1 ;
	         
	                END
	                -- and replace the hex sequence by its unicode value
	              SELECT @token=STUFF(@token, @escape, 6, NCHAR(@result))
	            END
	        END
	      --now store the string away 
	      INSERT INTO @Strings (StringValue) SELECT @token
	      -- and replace the string with a token
	      SELECT @JSON=STUFF(@json, @start, @end+1,
	                    '@string'+CONVERT(NVARCHAR(5), @@identity))
	    END
	  -- all strings are now removed. Now we find the first leaf.  
	  WHILE 1=1  --forever until there is nothing more to do
	  BEGIN
	 
	  SELECT @parent_ID=@parent_ID+1
	  --find the first object or list by looking for the open bracket
	  SELECT @FirstObject=PATINDEX('%[{[[]%', @json collate SQL_Latin1_General_CP850_Bin)--object or array
	  IF @FirstObject = 0 BREAK
	  IF (SUBSTRING(@json, @FirstObject, 1)='{') 
	    SELECT @NextCloseDelimiterChar='}', @type='object'
	  ELSE 
	    SELECT @NextCloseDelimiterChar=']', @type='array'
	  SELECT @OpenDelimiter=@firstObject
	  WHILE 1=1 --find the innermost object or list...
	    BEGIN
	      SELECT
	        @lenJSON=LEN(@JSON+'|')-1
	  --find the matching close-delimiter proceeding after the open-delimiter
	      SELECT
	        @NextCloseDelimiter=CHARINDEX(@NextCloseDelimiterChar, @json,
	                                      @OpenDelimiter+1)
	  --is there an intervening open-delimiter of either type
	      SELECT @NextOpenDelimiter=PATINDEX('%[{[[]%',
	             RIGHT(@json, @lenJSON-@OpenDelimiter)collate SQL_Latin1_General_CP850_Bin)--object
	      IF @NextOpenDelimiter=0 
	        BREAK
	      SELECT @NextOpenDelimiter=@NextOpenDelimiter+@OpenDelimiter
	      IF @NextCloseDelimiter<@NextOpenDelimiter 
	        BREAK
	      IF SUBSTRING(@json, @NextOpenDelimiter, 1)='{' 
	        SELECT @NextCloseDelimiterChar='}', @type='object'
	      ELSE 
	        SELECT @NextCloseDelimiterChar=']', @type='array'
	      SELECT @OpenDelimiter=@NextOpenDelimiter
	    END
	  ---and parse out the list or name/value pairs
	  SELECT
	    @contents=SUBSTRING(@json, @OpenDelimiter+1,
	                        @NextCloseDelimiter-@OpenDelimiter-1)
	  SELECT
	    @JSON=STUFF(@json, @OpenDelimiter,
	                @NextCloseDelimiter-@OpenDelimiter+1,
	                '@'+@type+CONVERT(NVARCHAR(5), @parent_ID))
	  WHILE (PATINDEX('%[A-Za-z0-9@+.e]%', @contents collate SQL_Latin1_General_CP850_Bin))<>0 
	    BEGIN
	      IF @Type='Object' --it will be a 0-n list containing a string followed by a string, number,boolean, or null
	        BEGIN
	          SELECT
	            @SequenceNo=0,@end=CHARINDEX(':', ' '+@contents)--if there is anything, it will be a string-based name.
	          SELECT  @start=PATINDEX('%[^A-Za-z@][@]%', ' '+@contents collate SQL_Latin1_General_CP850_Bin)--AAAAAAAA
	          SELECT @token=SUBSTRING(' '+@contents, @start+1, @End-@Start-1),
	            @endofname=PATINDEX('%[0-9]%', @token collate SQL_Latin1_General_CP850_Bin),
	            @param=RIGHT(@token, LEN(@token)-@endofname+1)
	          SELECT
	            @token=LEFT(@token, @endofname-1),
	            @Contents=RIGHT(' '+@contents, LEN(' '+@contents+'|')-@end-1)
	          SELECT  @name=stringvalue FROM @strings
	            WHERE string_id=@param --fetch the name
	        END
	      ELSE 
	        SELECT @Name=null,@SequenceNo=@SequenceNo+1 
	      SELECT
	        @end=CHARINDEX(',', @contents)-- a string-token, object-token, list-token, number,boolean, or null
                IF @end=0
	        --HR Engineering notation bugfix start
	          IF ISNUMERIC(@contents) = 1
		    SELECT @end = LEN(@contents) + 1
	          Else
	        --HR Engineering notation bugfix end 
		  SELECT  @end=PATINDEX('%[A-Za-z0-9@+.e][^A-Za-z0-9@+.e]%', @contents+' ' collate SQL_Latin1_General_CP850_Bin) + 1
	       SELECT
	        @start=PATINDEX('%[^A-Za-z0-9@+.e][A-Za-z0-9@+.e]%', ' '+@contents collate SQL_Latin1_General_CP850_Bin)
	      --select @start,@end, LEN(@contents+'|'), @contents  
	      SELECT
	        @Value=RTRIM(SUBSTRING(@contents, @start, @End-@Start)),
	        @Contents=RIGHT(@contents+' ', LEN(@contents+'|')-@end)
	      IF SUBSTRING(@value, 1, 7)='@object' 
	        INSERT INTO @hierarchy
	          (NAME, SequenceNo, parent_ID, StringValue, Object_ID, ValueType)
	          SELECT @name, @SequenceNo, @parent_ID, SUBSTRING(@value, 8, 5),
	            SUBSTRING(@value, 8, 5), 'object' 
	      ELSE 
	        IF SUBSTRING(@value, 1, 6)='@array' 
	          INSERT INTO @hierarchy
	            (NAME, SequenceNo, parent_ID, StringValue, Object_ID, ValueType)
	            SELECT @name, @SequenceNo, @parent_ID, SUBSTRING(@value, 7, 5),
	              SUBSTRING(@value, 7, 5), 'array' 
	        ELSE 
	          IF SUBSTRING(@value, 1, 7)='@string' 
	            INSERT INTO @hierarchy
	              (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	              SELECT @name, @SequenceNo, @parent_ID, stringvalue, 'string'
	              FROM @strings
	              WHERE string_id=SUBSTRING(@value, 8, 5)
	          ELSE 
	            IF @value IN ('true', 'false') 
	              INSERT INTO @hierarchy
	                (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	                SELECT @name, @SequenceNo, @parent_ID, @value, 'boolean'
	            ELSE
	              IF @value='null' 
	                INSERT INTO @hierarchy
	                  (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	                  SELECT @name, @SequenceNo, @parent_ID, @value, 'null'
	              ELSE
	                IF PATINDEX('%[^0-9]%', @value collate SQL_Latin1_General_CP850_Bin)>0 
	                  INSERT INTO @hierarchy
	                    (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	                    SELECT @name, @SequenceNo, @parent_ID, @value, 'real'
	                ELSE
	                  INSERT INTO @hierarchy
	                    (NAME, SequenceNo, parent_ID, StringValue, ValueType)
	                    SELECT @name, @SequenceNo, @parent_ID, @value, 'int'
	      if @Contents=' ' Select @SequenceNo=0
	    END
	  END
	INSERT INTO @hierarchy (NAME, SequenceNo, parent_ID, StringValue, Object_ID, ValueType)
	  SELECT '-',1, NULL, '', @parent_id-1, @type
	--
	   RETURN
	END
GO
/****** Object:  Table [dbo].[AspNetRoles]    Script Date: 16-Mar-19 16:09:23 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[AspNetRoles](
	[Id] [nvarchar](128) NOT NULL,
	[Name] [nvarchar](256) NOT NULL,
 CONSTRAINT [PK_dbo.AspNetRoles] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[AspNetUserClaims]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[AspNetUserClaims](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[UserId] [nvarchar](128) NOT NULL,
	[ClaimType] [nvarchar](max) NULL,
	[ClaimValue] [nvarchar](max) NULL,
 CONSTRAINT [PK_dbo.AspNetUserClaims] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[AspNetUserLogins]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[AspNetUserLogins](
	[LoginProvider] [nvarchar](128) NOT NULL,
	[ProviderKey] [nvarchar](128) NOT NULL,
	[UserId] [nvarchar](128) NOT NULL,
 CONSTRAINT [PK_dbo.AspNetUserLogins] PRIMARY KEY CLUSTERED 
(
	[LoginProvider] ASC,
	[ProviderKey] ASC,
	[UserId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[AspNetUserRoles]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[AspNetUserRoles](
	[UserId] [nvarchar](128) NOT NULL,
	[RoleId] [nvarchar](128) NOT NULL,
 CONSTRAINT [PK_dbo.AspNetUserRoles] PRIMARY KEY CLUSTERED 
(
	[UserId] ASC,
	[RoleId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[AspNetUsers]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[AspNetUsers](
	[Id] [nvarchar](128) NOT NULL,
	[Email] [nvarchar](256) NULL,
	[EmailConfirmed] [bit] NOT NULL,
	[PasswordHash] [nvarchar](max) NULL,
	[SecurityStamp] [nvarchar](max) NULL,
	[PhoneNumber] [nvarchar](max) NULL,
	[PhoneNumberConfirmed] [bit] NOT NULL,
	[TwoFactorEnabled] [bit] NOT NULL,
	[LockoutEndDateUtc] [datetime] NULL,
	[LockoutEnabled] [bit] NOT NULL,
	[AccessFailedCount] [int] NOT NULL,
	[UserName] [nvarchar](256) NOT NULL,
 CONSTRAINT [PK_dbo.AspNetUsers] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[BO]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[BO](
	[BO_ID] [bigint] IDENTITY(1,1) NOT NULL,
	[CREATED_BY] [varchar](100) NULL,
	[CREATED_DATE] [datetime] NULL,
	[UPDATED_BY] [varchar](100) NULL,
	[UPDATED_DATE] [datetime] NULL,
	[STATUS] [char](10) NULL,
	[BO_TYPE] [varchar](100) NULL,
	[VERSION] [int] NULL,
 CONSTRAINT [PK__BO__D4ABCFC65599051D] PRIMARY KEY CLUSTERED 
(
	[BO_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[BO_CHILDS]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[BO_CHILDS](
	[BO_PARENT_ID] [bigint] NOT NULL,
	[BO_CHILD_ID] [bigint] NOT NULL,
	[RELATION] [varchar](50) NULL,
PRIMARY KEY CLUSTERED 
(
	[BO_PARENT_ID] ASC,
	[BO_CHILD_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[BO_ROLE]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[BO_ROLE](
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
/****** Object:  Table [dbo].[META_BO]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[META_BO](
	[META_BO_ID] [bigint] IDENTITY(1,1) NOT NULL,
	[BO_NAME] [varchar](100) NULL,
	[VERSION] [int] NULL,
	[CREATED_BY] [varchar](100) NULL,
	[CREATED_DATE] [datetime] NULL,
	[UPDATED_BY] [varchar](100) NULL,
	[UPDATED_DATE] [datetime] NULL,
	[STATUS] [varchar](50) NULL,
	[BO_DB_NAME] [varchar](50) NULL,
	[TYPE] [varchar](50) NULL,
	[JSON_DATA] [nvarchar](max) NULL,
 CONSTRAINT [PK__META_BO__28ADAC72D031570B] PRIMARY KEY CLUSTERED 
(
	[META_BO_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[META_FIELD]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[META_FIELD](
	[META_FIELD_ID] [bigint] IDENTITY(1,1) NOT NULL,
	[META_BO_ID] [bigint] NOT NULL,
	[DB_NAME] [varchar](100) NOT NULL,
	[DB_TYPE] [varchar](20) NOT NULL,
	[DB_NULL] [int] NOT NULL,
	[GRID_NAME] [varchar](100) NOT NULL,
	[GRID_FORMAT] [nvarchar](max) NULL,
	[GRID_SHOW] [int] NULL,
	[FORM_NAME] [varchar](100) NULL,
	[FORM_FORMAT] [nvarchar](max) NULL,
	[FORM_TYPE] [varchar](100) NOT NULL,
	[FORM_SOURCE] [nvarchar](max) NULL,
	[FORM_SHOW] [int] NULL,
	[FORM_OPTIONAL] [int] NULL,
	[IS_FILTER] [int] NULL,
	[FORM_DEFAULT] [varchar](100) NULL,
	[CREATED_BY] [varchar](100) NOT NULL,
	[CREATED_DATE] [datetime] NULL,
	[UPDATED_BY] [varchar](100) NULL,
	[UPDATED_DATE] [datetime] NULL,
	[STATUS] [varchar](50) NULL,
	[VERSION] [int] NULL,
	[JSON_DATA] [nvarchar](max) NULL,
 CONSTRAINT [PK__META_FIE__604B6642F2AB887C] PRIMARY KEY CLUSTERED 
(
	[META_FIELD_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[NOTIF]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[NOTIF](
	[ID_NOTIF] [int] IDENTITY(1,1) NOT NULL,
	[VALIDATOR] [varchar](50) NULL,
	[ETAT] [int] NULL,
	[CREATED_DATE] [datetime] NULL,
 CONSTRAINT [PK_NOTIF] PRIMARY KEY CLUSTERED 
(
	[ID_NOTIF] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[PAGE]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[PAGE](
	[PAGE_ID] [bigint] IDENTITY(1,1) NOT NULL,
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
	[PAGE_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[PlusSequence]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[PlusSequence](
	[SequenceID] [int] IDENTITY(1,1) NOT NULL,
	[cle] [varchar](500) NULL,
	[TableName] [varchar](50) NULL,
	[StartValue] [int] NULL,
	[StepBy] [int] NULL,
	[CurrentValue] [int] NULL,
 CONSTRAINT [PK_SourceSequence] PRIMARY KEY CLUSTERED 
(
	[SequenceID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]
GO
/****** Object:  Table [dbo].[TASK]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[TASK](
	[TASK_ID] [int] IDENTITY(1,1) NOT NULL,
	[BO_ID] [int] NULL,
	[JSON_DATA] [nvarchar](max) NULL,
	[STATUS] [varchar](50) NULL,
	[ETAT] [int] NULL,
	[TASK_LEVEL] [int] NULL,
	[TASK_TYPE] [varchar](50) NULL,
	[CREATED_DATE] [datetime] NULL,
	[CREATED_BY] [varchar](50) NULL,
 CONSTRAINT [PK_VALIDATION] PRIMARY KEY CLUSTERED 
(
	[TASK_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[VERSIONS]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[VERSIONS](
	[VERSIONS_ID] [bigint] IDENTITY(1,1) NOT NULL,
	[META_BO_ID] [bigint] NULL,
	[NUM] [int] NOT NULL,
	[SQLQUERY] [varchar](max) NOT NULL,
	[CREATED_BY] [varchar](100) NULL,
	[CREATED_DATE] [datetime] NULL,
	[UPDATED_BY] [varchar](100) NULL,
	[UPDATED_DATE] [datetime] NULL,
	[STATUS] [varchar](10) NULL,
PRIMARY KEY CLUSTERED 
(
	[VERSIONS_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
/****** Object:  Table [dbo].[WORKFLOW]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[WORKFLOW](
	[BO_ID] [bigint] NOT NULL,
	[LIBELLE] [varchar](50) NULL,
	[ACTIVE] [int] NULL,
	[ITEMS] [nvarchar](max) NULL,
 CONSTRAINT [PK_WORKFLOW] PRIMARY KEY CLUSTERED 
(
	[BO_ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO
INSERT [dbo].[AspNetRoles] ([Id], [Name]) VALUES (N'c147b3be-fc72-4155-bd0c-b6e1a59a5ffd', N'AAAAA')
GO
INSERT [dbo].[AspNetRoles] ([Id], [Name]) VALUES (N'a7cfd5f5-9f3d-4d18-a028-28ff37ed97fe', N'admin')
GO
INSERT [dbo].[AspNetRoles] ([Id], [Name]) VALUES (N'78c10fe3-22ef-446c-bd84-8e622b6e3612', N'DATA READER')
GO
INSERT [dbo].[AspNetRoles] ([Id], [Name]) VALUES (N'80631063-e62c-429c-a99e-7bb6d55a42a1', N'DATA WRITER')
GO
INSERT [dbo].[AspNetRoles] ([Id], [Name]) VALUES (N'280d03d2-5a57-4c52-816e-e2aded466d28', N'FM')
GO
INSERT [dbo].[AspNetRoles] ([Id], [Name]) VALUES (N'0018898c-a333-42f1-b0c8-896dd84c4bc7', N'OWNER')
GO
INSERT [dbo].[AspNetUserRoles] ([UserId], [RoleId]) VALUES (N'33bff03f-ed4d-45bd-99e7-73b47bcc9362', N'280d03d2-5a57-4c52-816e-e2aded466d28')
GO
INSERT [dbo].[AspNetUserRoles] ([UserId], [RoleId]) VALUES (N'8e54c0e9-77c3-4bd2-9096-ae12f1763348', N'280d03d2-5a57-4c52-816e-e2aded466d28')
GO
INSERT [dbo].[AspNetUserRoles] ([UserId], [RoleId]) VALUES (N'33bff03f-ed4d-45bd-99e7-73b47bcc9362', N'a7cfd5f5-9f3d-4d18-a028-28ff37ed97fe')
GO
INSERT [dbo].[AspNetUserRoles] ([UserId], [RoleId]) VALUES (N'9177d347-7032-42c8-b095-b4fe8e72859d', N'c147b3be-fc72-4155-bd0c-b6e1a59a5ffd')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'33bff03f-ed4d-45bd-99e7-73b47bcc9362', N'simo@simo.com', 0, N'AO4BK820lnEtgw+Q0jPzmn4SJCpKES59aitwvltfn8HwRY6iGiOfFedX6Z+QZqUB5g==', N'4b1a476c-a6cc-42af-bcbc-bb6bcbdf4efe', NULL, 0, 0, NULL, 0, 0, N'simo@simo.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'37833646-17cb-4953-946f-39fcb3de6184', N'U6@simo.com', 0, N'AO0BWGVIoTrZlXvWvYwTdx8XDUkAEAmSirX8GB0VW5ZtKkIJLcVIeGJwULBXM+jdSg==', N'e8fc6039-004c-401b-ba21-cba158afc5b2', NULL, 0, 0, NULL, 0, 0, N'U6@simo.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'3d164bc9-3652-442c-9732-4cd805e6837e', N'U2@simo.com', 0, N'ANGOcIHoULxr4Gk5XjnoMfVChzOLHytM2s8nS13Dibo7PSTQ9TLhf5wFrhrJQihndw==', N'1dfcb3dc-dc34-4f78-9e91-b73a2d510e31', NULL, 0, 0, NULL, 0, 0, N'U2@simo.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'481e6134-3bdd-4689-87c6-da117dee2f36', N'U3@simo.com', 0, N'ANbcP5LE+Q49TDO6KJHT0BmcDNZy9x9XTj9WxfOwVUU2ca+/gdoHZBurJAQ2FiBa3w==', N'e33fcca6-c68b-4cd5-8d28-ef4364b4a92b', NULL, 0, 0, NULL, 0, 0, N'U3@simo.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'8e54c0e9-77c3-4bd2-9096-ae12f1763348', N'U_writer2@simo.com', 0, N'ABEo5nt9QD85geUxBDGP107/3tJuyp/n/r/ARZL97Nu8dbepnKzNL6vcfdGpMDZa8g==', N'f89961ec-b4fc-4541-94c3-cb1d45a6aaa1', NULL, 0, 0, NULL, 0, 0, N'U_writer2@simo.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'9177d347-7032-42c8-b095-b4fe8e72859d', N'U4@simo.com', 0, N'ACu6p218ZuhZoGJWoz4cy+AsyRaudKZhhtSNVPJC4N9/mjC2HD7t5uZOoPQirzewaw==', N'08a8241a-2646-4c97-b71e-069ecc663608', NULL, 0, 0, NULL, 0, 0, N'U4@simo.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'97d8ecb2-8b0b-4b5e-a544-3e71102f1170', N's@s.com', 0, N'ABsrFhYxIT4A4nDJ0GwXzRsVLtIzs7yMlAt4EB6nGbQATLChi+qoIZq/o3LIxCWjXg==', N'bcb16fab-ed19-44f8-9842-f8bb046d07f9', NULL, 0, 0, NULL, 0, 0, N's@s.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'a74c3098-1f7c-42e0-92fb-a6f7638a7a4f', N'U5@simo.com', 0, N'AOmMnh9e3G+fqp+DyyJkxyM9kPoUss6Wd6wRKfvdGU0fG/HkeAOmZdjBfaCxoKE19Q==', N'7cfbff2e-4f4b-48ac-9240-d4dfd22087b5', NULL, 0, 0, NULL, 0, 0, N'U5@simo.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'a80f78d9-4d0e-4949-bad4-f3f10c620c10', N'U_writer@simo.com', 0, N'APiL2GxKjqvWs3oTQsl1HF82fqAe9kPOES78e1xsHSpNQd1YabV94lCKzuQP7JFFeQ==', N'b44de7a4-0409-42b2-9a52-bd973e7ebec1', NULL, 0, 0, NULL, 0, 0, N'U_writer@simo.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'd6691522-7b04-42d7-8489-d57afbb2d2c6', N'U_reader2@simo.com', 0, N'AFfj98xUMno4G86LN5dff8vW8em5XoGTiCPiQyLNXF/6zmmbbZ2L6jUNiWgOP9oW2w==', N'2bf4c265-5e0a-4137-8ba7-9d5ff122db08', NULL, 0, 0, NULL, 0, 0, N'U_reader2@simo.com')
GO
INSERT [dbo].[AspNetUsers] ([Id], [Email], [EmailConfirmed], [PasswordHash], [SecurityStamp], [PhoneNumber], [PhoneNumberConfirmed], [TwoFactorEnabled], [LockoutEndDateUtc], [LockoutEnabled], [AccessFailedCount], [UserName]) VALUES (N'f47df665-7dff-45b2-9bae-a35c5a84e5eb', N'U_reader@simo.com', 0, N'AAbVl3ONlMuP0tx12T+nUMggoArdtF9uRgBROViFBuitT43YQgwUt+5Wy1IONIJQ4w==', N'1ef2b52d-0296-41a2-8ec7-b001e5a8ee20', NULL, 0, 0, NULL, 0, 0, N'U_reader@simo.com')
GO
SET IDENTITY_INSERT [dbo].[BO] ON 
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (98, N'simo@simo.com', CAST(N'2019-01-07T11:49:22.800' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:22:37.013' AS DateTime), N'1         ', N'48', 2)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (99, N'simo@simo.com', CAST(N'2019-01-07T11:49:33.243' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:22:51.623' AS DateTime), N'1         ', N'48', 2)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (100, N'simo@simo.com', CAST(N'2019-01-07T11:49:47.903' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:22:57.340' AS DateTime), N'1         ', N'48', 2)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (101, N'simo@simo.com', CAST(N'2019-01-07T12:14:20.243' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:14:20.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (102, N'simo@simo.com', CAST(N'2019-01-07T12:14:26.980' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:14:26.980' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (103, N'simo@simo.com', CAST(N'2019-01-07T12:14:32.647' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:14:32.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (104, N'simo@simo.com', CAST(N'2019-01-07T12:14:37.647' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:14:37.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (105, N'simo@simo.com', CAST(N'2019-01-07T12:14:41.223' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:14:41.223' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (106, N'simo@simo.com', CAST(N'2019-01-08T15:00:35.353' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T15:40:41.687' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (107, N'simo@simo.com', CAST(N'2019-01-08T15:52:20.963' AS DateTime), N'simo@simo.com', CAST(N'2019-01-08T15:52:34.447' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (10088, N'simo@simo.com', CAST(N'2019-01-13T18:52:38.667' AS DateTime), N'simo@simo.com', CAST(N'2019-01-13T18:52:38.667' AS DateTime), N'1         ', N'2', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (10089, N'simo@simo.com', CAST(N'2019-01-13T19:07:28.677' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:08:38.953' AS DateTime), N'1         ', N'2', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (10090, N'simo@simo.com', CAST(N'2019-01-13T19:29:01.253' AS DateTime), N'simo@simo.com', CAST(N'2019-01-13T19:29:01.253' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20088, N'sys', CAST(N'2019-01-17T16:59:24.410' AS DateTime), N'sys', CAST(N'2019-01-17T16:59:24.410' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20089, N'sys', CAST(N'2019-01-17T16:59:24.410' AS DateTime), N'sys', CAST(N'2019-01-17T16:59:24.410' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20090, N'sys', CAST(N'2019-01-17T17:14:12.453' AS DateTime), N'sys', CAST(N'2019-01-17T17:14:12.453' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20091, N'sys', CAST(N'2019-01-17T17:14:12.470' AS DateTime), N'sys', CAST(N'2019-01-17T17:14:12.470' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20092, N'sys', CAST(N'2019-01-17T17:14:15.130' AS DateTime), N'sys', CAST(N'2019-01-17T17:14:15.130' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20093, N'sys', CAST(N'2019-01-17T17:14:15.147' AS DateTime), N'sys', CAST(N'2019-01-17T17:14:15.147' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20094, N'sys', CAST(N'2019-01-17T17:14:22.080' AS DateTime), N'sys', CAST(N'2019-01-17T17:14:22.080' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20095, N'sys', CAST(N'2019-01-17T17:14:22.080' AS DateTime), N'sys', CAST(N'2019-01-17T17:14:22.080' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20096, N'sys', CAST(N'2019-01-17T17:14:24.260' AS DateTime), N'sys', CAST(N'2019-01-17T17:14:24.260' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20097, N'sys', CAST(N'2019-01-17T17:14:24.260' AS DateTime), N'sys', CAST(N'2019-01-17T17:14:24.260' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20098, N'sys', CAST(N'2019-01-17T17:15:31.237' AS DateTime), N'sys', CAST(N'2019-01-17T17:15:31.237' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20099, N'sys', CAST(N'2019-01-17T17:15:31.237' AS DateTime), N'sys', CAST(N'2019-01-17T17:15:31.237' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20100, N'sys', CAST(N'2019-01-17T17:15:47.273' AS DateTime), N'sys', CAST(N'2019-01-17T17:15:47.273' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20101, N'sys', CAST(N'2019-01-17T17:15:47.290' AS DateTime), N'sys', CAST(N'2019-01-17T17:15:47.290' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20102, N'sys', CAST(N'2019-01-17T17:16:45.760' AS DateTime), N'sys', CAST(N'2019-01-17T17:16:45.760' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20103, N'sys', CAST(N'2019-01-17T17:17:08.623' AS DateTime), N'sys', CAST(N'2019-01-17T17:17:08.623' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20104, N'sys', CAST(N'2019-01-17T17:17:08.623' AS DateTime), N'sys', CAST(N'2019-01-17T17:17:08.623' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20105, N'sys', CAST(N'2019-01-17T17:17:15.030' AS DateTime), N'sys', CAST(N'2019-01-17T17:17:15.030' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20106, N'sys', CAST(N'2019-01-17T17:17:15.030' AS DateTime), N'sys', CAST(N'2019-01-17T17:17:15.030' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20107, N'sys', CAST(N'2019-01-17T17:17:25.420' AS DateTime), N'sys', CAST(N'2019-01-17T17:17:25.420' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20108, N'sys', CAST(N'2019-01-17T17:17:25.420' AS DateTime), N'sys', CAST(N'2019-01-17T17:17:25.420' AS DateTime), N'1         ', N'49', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20109, N'sys', CAST(N'2019-01-17T17:19:17.207' AS DateTime), N'sys', CAST(N'2019-01-17T17:19:17.207' AS DateTime), N'1         ', N'20048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20110, N'sys', CAST(N'2019-01-17T17:19:17.207' AS DateTime), N'sys', CAST(N'2019-01-17T17:19:17.207' AS DateTime), N'1         ', N'20048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20111, N'sys', CAST(N'2019-01-17T17:19:18.950' AS DateTime), N'sys', CAST(N'2019-01-17T17:19:18.950' AS DateTime), N'1         ', N'20048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20112, N'sys', CAST(N'2019-01-17T17:19:18.950' AS DateTime), N'sys', CAST(N'2019-01-17T17:19:18.950' AS DateTime), N'1         ', N'20048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20113, N'sys', CAST(N'2019-01-17T17:19:19.453' AS DateTime), N'sys', CAST(N'2019-01-17T17:19:19.453' AS DateTime), N'1         ', N'20048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20114, N'sys', CAST(N'2019-01-17T17:19:19.453' AS DateTime), N'sys', CAST(N'2019-01-17T17:19:19.453' AS DateTime), N'1         ', N'20048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20115, N'sys', CAST(N'2019-01-17T17:19:19.690' AS DateTime), N'sys', CAST(N'2019-01-17T17:19:19.690' AS DateTime), N'1         ', N'20048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (20116, N'sys', CAST(N'2019-01-17T17:19:19.690' AS DateTime), N'sys', CAST(N'2019-01-17T17:19:19.690' AS DateTime), N'1         ', N'20048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30088, N'simo@simo.com', CAST(N'2019-01-21T11:24:13.687' AS DateTime), N'simo@simo.com', CAST(N'2019-01-21T11:26:08.413' AS DateTime), N'1         ', N'30048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30089, N'simo@simo.com', CAST(N'2019-01-21T11:24:17.753' AS DateTime), N'simo@simo.com', CAST(N'2019-01-21T11:26:11.197' AS DateTime), N'1         ', N'30048', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30090, N'simo@simo.com', CAST(N'2019-01-21T12:48:56.557' AS DateTime), N'simo@simo.com', CAST(N'2019-01-21T12:48:56.557' AS DateTime), N'1         ', N'48', 4)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30091, N'simo@simo.com', CAST(N'2019-01-23T15:17:48.647' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T15:17:48.647' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30092, N'simo@simo.com', CAST(N'2019-01-23T15:17:54.880' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T15:17:54.880' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30093, N'simo@simo.com', CAST(N'2019-01-23T15:17:59.303' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T15:17:59.303' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30094, N'simo@simo.com', CAST(N'2019-01-23T15:18:19.150' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T15:18:19.150' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30095, N'simo@simo.com', CAST(N'2019-01-23T15:18:56.260' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T15:36:48.883' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30096, N'simo@simo.com', CAST(N'2019-01-23T15:19:49.017' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T15:41:39.007' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30097, N'simo@simo.com', CAST(N'2019-01-23T15:20:59.020' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T16:17:13.560' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30098, N'simo@simo.com', CAST(N'2019-01-23T15:50:03.737' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T15:50:03.737' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30099, N'simo@simo.com', CAST(N'2019-01-23T16:20:48.163' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T16:20:48.163' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30100, N'simo@simo.com', CAST(N'2019-01-23T16:21:24.107' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T16:21:24.107' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30101, N'simo@simo.com', CAST(N'2019-01-23T16:21:31.327' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T16:21:31.327' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30102, N'simo@simo.com', CAST(N'2019-01-23T16:21:34.840' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T16:21:34.840' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30103, N'simo@simo.com', CAST(N'2019-01-23T16:23:00.100' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T16:23:00.100' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30104, N'simo@simo.com', CAST(N'2019-01-23T16:23:15.090' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T16:39:11.463' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30105, N'simo@simo.com', CAST(N'2019-01-23T16:23:38.980' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T16:39:14.500' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30106, N'simo@simo.com', CAST(N'2019-01-23T16:23:45.913' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T15:41:44.443' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30107, N'simo@simo.com', CAST(N'2019-01-23T16:23:59.587' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T16:23:59.587' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30108, N'simo@simo.com', CAST(N'2019-01-23T17:55:17.777' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T17:55:17.777' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30109, N'simo@simo.com', CAST(N'2019-01-23T17:55:54.983' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T17:55:54.983' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30110, N'simo@simo.com', CAST(N'2019-01-23T17:56:29.040' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T17:56:29.040' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30111, N'simo@simo.com', CAST(N'2019-01-23T17:58:39.260' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T17:58:39.260' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30112, N'simo@simo.com', CAST(N'2019-01-23T17:59:40.527' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T17:59:40.527' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30113, N'simo@simo.com', CAST(N'2019-01-23T18:00:59.133' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T18:00:59.133' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30114, N'simo@simo.com', CAST(N'2019-01-24T14:54:58.227' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T14:54:58.227' AS DateTime), N'1         ', N'49', 3)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30115, N'simo@simo.com', CAST(N'2019-01-25T18:59:09.043' AS DateTime), N'simo@simo.com', CAST(N'2019-01-25T18:59:09.043' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30116, N'sys', CAST(N'2019-01-25T19:00:45.433' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.433' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30117, N'sys', CAST(N'2019-01-25T19:00:45.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30118, N'sys', CAST(N'2019-01-25T19:00:45.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30119, N'sys', CAST(N'2019-01-25T19:00:45.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30120, N'sys', CAST(N'2019-01-25T19:00:45.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30121, N'sys', CAST(N'2019-01-25T19:00:45.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30122, N'sys', CAST(N'2019-01-25T19:00:45.447' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.447' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30123, N'sys', CAST(N'2019-01-25T19:00:45.447' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.447' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30124, N'sys', CAST(N'2019-01-25T19:00:45.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30125, N'sys', CAST(N'2019-01-25T19:00:45.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30126, N'sys', CAST(N'2019-01-25T19:00:45.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30127, N'sys', CAST(N'2019-01-25T19:00:45.453' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.453' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30128, N'sys', CAST(N'2019-01-25T19:00:45.453' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.453' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30129, N'sys', CAST(N'2019-01-25T19:00:45.453' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.453' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30130, N'sys', CAST(N'2019-01-25T19:00:45.457' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.457' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30131, N'sys', CAST(N'2019-01-25T19:00:45.457' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.457' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30132, N'sys', CAST(N'2019-01-25T19:00:45.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30133, N'sys', CAST(N'2019-01-25T19:00:45.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30134, N'sys', CAST(N'2019-01-25T19:00:45.463' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.463' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30135, N'sys', CAST(N'2019-01-25T19:00:45.463' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.463' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30136, N'sys', CAST(N'2019-01-25T19:00:45.463' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.463' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30137, N'sys', CAST(N'2019-01-25T19:00:45.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30138, N'sys', CAST(N'2019-01-25T19:00:45.523' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.523' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30139, N'sys', CAST(N'2019-01-25T19:00:45.527' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.527' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30140, N'sys', CAST(N'2019-01-25T19:00:45.527' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.527' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30141, N'sys', CAST(N'2019-01-25T19:00:45.530' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.530' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30142, N'sys', CAST(N'2019-01-25T19:00:45.530' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.530' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30143, N'sys', CAST(N'2019-01-25T19:00:45.530' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.530' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30144, N'sys', CAST(N'2019-01-25T19:00:45.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30145, N'sys', CAST(N'2019-01-25T19:00:45.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30146, N'sys', CAST(N'2019-01-25T19:00:45.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30147, N'sys', CAST(N'2019-01-25T19:00:45.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30148, N'sys', CAST(N'2019-01-25T19:00:45.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30149, N'sys', CAST(N'2019-01-25T19:00:45.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30150, N'sys', CAST(N'2019-01-25T19:00:45.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30151, N'sys', CAST(N'2019-01-25T19:00:45.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30152, N'sys', CAST(N'2019-01-25T19:00:45.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30153, N'sys', CAST(N'2019-01-25T19:00:45.617' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.617' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30154, N'sys', CAST(N'2019-01-25T19:00:45.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30155, N'sys', CAST(N'2019-01-25T19:00:45.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30156, N'sys', CAST(N'2019-01-25T19:00:45.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30157, N'sys', CAST(N'2019-01-25T19:00:45.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30158, N'sys', CAST(N'2019-01-25T19:00:45.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30159, N'sys', CAST(N'2019-01-25T19:00:45.627' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.627' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30160, N'sys', CAST(N'2019-01-25T19:00:45.670' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.670' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30161, N'sys', CAST(N'2019-01-25T19:00:45.670' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.670' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30162, N'sys', CAST(N'2019-01-25T19:00:45.673' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.673' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30163, N'sys', CAST(N'2019-01-25T19:00:45.673' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.673' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30164, N'sys', CAST(N'2019-01-25T19:00:45.677' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.677' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30165, N'sys', CAST(N'2019-01-25T19:00:45.677' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.677' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30166, N'sys', CAST(N'2019-01-25T19:00:45.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30167, N'sys', CAST(N'2019-01-25T19:00:45.767' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.767' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30168, N'sys', CAST(N'2019-01-25T19:00:45.770' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.770' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30169, N'sys', CAST(N'2019-01-25T19:00:45.770' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.770' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30170, N'sys', CAST(N'2019-01-25T19:00:45.770' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.770' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30171, N'sys', CAST(N'2019-01-25T19:00:45.770' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.770' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30172, N'sys', CAST(N'2019-01-25T19:00:45.773' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.773' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30173, N'sys', CAST(N'2019-01-25T19:00:45.773' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.773' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30174, N'sys', CAST(N'2019-01-25T19:00:45.813' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.813' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30175, N'sys', CAST(N'2019-01-25T19:00:45.813' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.813' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30176, N'sys', CAST(N'2019-01-25T19:00:45.817' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.817' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30177, N'sys', CAST(N'2019-01-25T19:00:45.817' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.817' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30178, N'sys', CAST(N'2019-01-25T19:00:45.817' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.817' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30179, N'sys', CAST(N'2019-01-25T19:00:45.820' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.820' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30180, N'sys', CAST(N'2019-01-25T19:00:45.820' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.820' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30181, N'sys', CAST(N'2019-01-25T19:00:45.860' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.860' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30182, N'sys', CAST(N'2019-01-25T19:00:45.863' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.863' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30183, N'sys', CAST(N'2019-01-25T19:00:45.863' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.863' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30184, N'sys', CAST(N'2019-01-25T19:00:45.867' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.867' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30185, N'sys', CAST(N'2019-01-25T19:00:45.867' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.867' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30186, N'sys', CAST(N'2019-01-25T19:00:45.870' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.870' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30187, N'sys', CAST(N'2019-01-25T19:00:45.870' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.870' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30188, N'sys', CAST(N'2019-01-25T19:00:45.870' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.870' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30189, N'sys', CAST(N'2019-01-25T19:00:45.920' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.920' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30190, N'sys', CAST(N'2019-01-25T19:00:45.920' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.920' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30191, N'sys', CAST(N'2019-01-25T19:00:45.920' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.920' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30192, N'sys', CAST(N'2019-01-25T19:00:45.923' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.923' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30193, N'sys', CAST(N'2019-01-25T19:00:45.923' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.923' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30194, N'sys', CAST(N'2019-01-25T19:00:45.927' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.927' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30195, N'sys', CAST(N'2019-01-25T19:00:45.927' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.927' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30196, N'sys', CAST(N'2019-01-25T19:00:45.980' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.980' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30197, N'sys', CAST(N'2019-01-25T19:00:45.980' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.980' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30198, N'sys', CAST(N'2019-01-25T19:00:45.980' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.980' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30199, N'sys', CAST(N'2019-01-25T19:00:45.983' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.983' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30200, N'sys', CAST(N'2019-01-25T19:00:45.983' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.983' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30201, N'sys', CAST(N'2019-01-25T19:00:45.987' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.987' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30202, N'sys', CAST(N'2019-01-25T19:00:45.987' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:45.987' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30203, N'sys', CAST(N'2019-01-25T19:00:46.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30204, N'sys', CAST(N'2019-01-25T19:00:46.033' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.033' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30205, N'sys', CAST(N'2019-01-25T19:00:46.033' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.033' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30206, N'sys', CAST(N'2019-01-25T19:00:46.037' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.037' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30207, N'sys', CAST(N'2019-01-25T19:00:46.037' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.037' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30208, N'sys', CAST(N'2019-01-25T19:00:46.040' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.040' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30209, N'sys', CAST(N'2019-01-25T19:00:46.040' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.040' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30210, N'sys', CAST(N'2019-01-25T19:00:46.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30211, N'sys', CAST(N'2019-01-25T19:00:46.083' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.083' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30212, N'sys', CAST(N'2019-01-25T19:00:46.083' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.083' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30213, N'sys', CAST(N'2019-01-25T19:00:46.087' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.087' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30214, N'sys', CAST(N'2019-01-25T19:00:46.087' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.087' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30215, N'sys', CAST(N'2019-01-25T19:00:46.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30216, N'sys', CAST(N'2019-01-25T19:00:46.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30217, N'sys', CAST(N'2019-01-25T19:00:46.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30218, N'sys', CAST(N'2019-01-25T19:00:46.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30219, N'sys', CAST(N'2019-01-25T19:00:46.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30220, N'sys', CAST(N'2019-01-25T19:00:46.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30221, N'sys', CAST(N'2019-01-25T19:00:46.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30222, N'sys', CAST(N'2019-01-25T19:00:46.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30223, N'sys', CAST(N'2019-01-25T19:00:46.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30224, N'sys', CAST(N'2019-01-25T19:00:46.140' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.140' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30225, N'sys', CAST(N'2019-01-25T19:00:46.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30226, N'sys', CAST(N'2019-01-25T19:00:46.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30227, N'sys', CAST(N'2019-01-25T19:00:46.183' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.183' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30228, N'sys', CAST(N'2019-01-25T19:00:46.183' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.183' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30229, N'sys', CAST(N'2019-01-25T19:00:46.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30230, N'sys', CAST(N'2019-01-25T19:00:46.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30231, N'sys', CAST(N'2019-01-25T19:00:46.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30232, N'sys', CAST(N'2019-01-25T19:00:46.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30233, N'sys', CAST(N'2019-01-25T19:00:46.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30234, N'sys', CAST(N'2019-01-25T19:00:46.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30235, N'sys', CAST(N'2019-01-25T19:00:46.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30236, N'sys', CAST(N'2019-01-25T19:00:46.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30237, N'sys', CAST(N'2019-01-25T19:00:46.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30238, N'sys', CAST(N'2019-01-25T19:00:46.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30239, N'sys', CAST(N'2019-01-25T19:00:46.277' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.277' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30240, N'sys', CAST(N'2019-01-25T19:00:46.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30241, N'sys', CAST(N'2019-01-25T19:00:46.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30242, N'sys', CAST(N'2019-01-25T19:00:46.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30243, N'sys', CAST(N'2019-01-25T19:00:46.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30244, N'sys', CAST(N'2019-01-25T19:00:46.283' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.283' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30245, N'sys', CAST(N'2019-01-25T19:00:46.283' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.283' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30246, N'sys', CAST(N'2019-01-25T19:00:46.283' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.283' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30247, N'sys', CAST(N'2019-01-25T19:00:46.313' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.313' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30248, N'sys', CAST(N'2019-01-25T19:00:46.317' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.317' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30249, N'sys', CAST(N'2019-01-25T19:00:46.317' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.317' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30250, N'sys', CAST(N'2019-01-25T19:00:46.317' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.317' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30251, N'sys', CAST(N'2019-01-25T19:00:46.320' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.320' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30252, N'sys', CAST(N'2019-01-25T19:00:46.320' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.320' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30253, N'sys', CAST(N'2019-01-25T19:00:46.320' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.320' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30254, N'sys', CAST(N'2019-01-25T19:00:46.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30255, N'sys', CAST(N'2019-01-25T19:00:46.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30256, N'sys', CAST(N'2019-01-25T19:00:46.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30257, N'sys', CAST(N'2019-01-25T19:00:46.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30258, N'sys', CAST(N'2019-01-25T19:00:46.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30259, N'sys', CAST(N'2019-01-25T19:00:46.357' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.357' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30260, N'sys', CAST(N'2019-01-25T19:00:46.357' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.357' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30261, N'sys', CAST(N'2019-01-25T19:00:46.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30262, N'sys', CAST(N'2019-01-25T19:00:46.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30263, N'sys', CAST(N'2019-01-25T19:00:46.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30264, N'sys', CAST(N'2019-01-25T19:00:46.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30265, N'sys', CAST(N'2019-01-25T19:00:46.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30266, N'sys', CAST(N'2019-01-25T19:00:46.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30267, N'sys', CAST(N'2019-01-25T19:00:46.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30268, N'sys', CAST(N'2019-01-25T19:00:46.437' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.437' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30269, N'sys', CAST(N'2019-01-25T19:00:46.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30270, N'sys', CAST(N'2019-01-25T19:00:46.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30271, N'sys', CAST(N'2019-01-25T19:00:46.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30272, N'sys', CAST(N'2019-01-25T19:00:46.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30273, N'sys', CAST(N'2019-01-25T19:00:46.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30274, N'sys', CAST(N'2019-01-25T19:00:46.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30275, N'sys', CAST(N'2019-01-25T19:00:46.447' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.447' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30276, N'sys', CAST(N'2019-01-25T19:00:46.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30277, N'sys', CAST(N'2019-01-25T19:00:46.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30278, N'sys', CAST(N'2019-01-25T19:00:46.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30279, N'sys', CAST(N'2019-01-25T19:00:46.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30280, N'sys', CAST(N'2019-01-25T19:00:46.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30281, N'sys', CAST(N'2019-01-25T19:00:46.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30282, N'sys', CAST(N'2019-01-25T19:00:46.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30283, N'sys', CAST(N'2019-01-25T19:00:46.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30284, N'sys', CAST(N'2019-01-25T19:00:46.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30285, N'sys', CAST(N'2019-01-25T19:00:46.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30286, N'sys', CAST(N'2019-01-25T19:00:46.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30287, N'sys', CAST(N'2019-01-25T19:00:46.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30288, N'sys', CAST(N'2019-01-25T19:00:46.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30289, N'sys', CAST(N'2019-01-25T19:00:46.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30290, N'sys', CAST(N'2019-01-25T19:00:46.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30291, N'sys', CAST(N'2019-01-25T19:00:46.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30292, N'sys', CAST(N'2019-01-25T19:00:46.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30293, N'sys', CAST(N'2019-01-25T19:00:46.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30294, N'sys', CAST(N'2019-01-25T19:00:46.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30295, N'sys', CAST(N'2019-01-25T19:00:46.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30296, N'sys', CAST(N'2019-01-25T19:00:46.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30297, N'sys', CAST(N'2019-01-25T19:00:46.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30298, N'sys', CAST(N'2019-01-25T19:00:46.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30299, N'sys', CAST(N'2019-01-25T19:00:46.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30300, N'sys', CAST(N'2019-01-25T19:00:46.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30301, N'sys', CAST(N'2019-01-25T19:00:46.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30302, N'sys', CAST(N'2019-01-25T19:00:46.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30303, N'sys', CAST(N'2019-01-25T19:00:46.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30304, N'sys', CAST(N'2019-01-25T19:00:46.643' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.643' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30305, N'sys', CAST(N'2019-01-25T19:00:46.647' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30306, N'sys', CAST(N'2019-01-25T19:00:46.647' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30307, N'sys', CAST(N'2019-01-25T19:00:46.647' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30308, N'sys', CAST(N'2019-01-25T19:00:46.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30309, N'sys', CAST(N'2019-01-25T19:00:46.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30310, N'sys', CAST(N'2019-01-25T19:00:46.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30311, N'sys', CAST(N'2019-01-25T19:00:46.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30312, N'sys', CAST(N'2019-01-25T19:00:46.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30313, N'sys', CAST(N'2019-01-25T19:00:46.683' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.683' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30314, N'sys', CAST(N'2019-01-25T19:00:46.683' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.683' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30315, N'sys', CAST(N'2019-01-25T19:00:46.683' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.683' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30316, N'sys', CAST(N'2019-01-25T19:00:46.687' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.687' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30317, N'sys', CAST(N'2019-01-25T19:00:46.687' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.687' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30318, N'sys', CAST(N'2019-01-25T19:00:46.687' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.687' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30319, N'sys', CAST(N'2019-01-25T19:00:46.747' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.747' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30320, N'sys', CAST(N'2019-01-25T19:00:46.747' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.747' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30321, N'sys', CAST(N'2019-01-25T19:00:46.750' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.750' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30322, N'sys', CAST(N'2019-01-25T19:00:46.750' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.750' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30323, N'sys', CAST(N'2019-01-25T19:00:46.750' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.750' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30324, N'sys', CAST(N'2019-01-25T19:00:46.753' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.753' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30325, N'sys', CAST(N'2019-01-25T19:00:46.753' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.753' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30326, N'sys', CAST(N'2019-01-25T19:00:46.800' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.800' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30327, N'sys', CAST(N'2019-01-25T19:00:46.800' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.800' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30328, N'sys', CAST(N'2019-01-25T19:00:46.803' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.803' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30329, N'sys', CAST(N'2019-01-25T19:00:46.803' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.803' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30330, N'sys', CAST(N'2019-01-25T19:00:46.807' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.807' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30331, N'sys', CAST(N'2019-01-25T19:00:46.807' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.807' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30332, N'sys', CAST(N'2019-01-25T19:00:46.807' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.807' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30333, N'sys', CAST(N'2019-01-25T19:00:46.857' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.857' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30334, N'sys', CAST(N'2019-01-25T19:00:46.857' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.857' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30335, N'sys', CAST(N'2019-01-25T19:00:46.860' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.860' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30336, N'sys', CAST(N'2019-01-25T19:00:46.860' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.860' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30337, N'sys', CAST(N'2019-01-25T19:00:46.860' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.860' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30338, N'sys', CAST(N'2019-01-25T19:00:46.860' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.860' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30339, N'sys', CAST(N'2019-01-25T19:00:46.863' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.863' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30340, N'sys', CAST(N'2019-01-25T19:00:46.863' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.863' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30341, N'sys', CAST(N'2019-01-25T19:00:46.907' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.907' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30342, N'sys', CAST(N'2019-01-25T19:00:46.910' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.910' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30343, N'sys', CAST(N'2019-01-25T19:00:46.910' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.910' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30344, N'sys', CAST(N'2019-01-25T19:00:46.910' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.910' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30345, N'sys', CAST(N'2019-01-25T19:00:46.913' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.913' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30346, N'sys', CAST(N'2019-01-25T19:00:46.913' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.913' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30347, N'sys', CAST(N'2019-01-25T19:00:46.917' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.917' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30348, N'sys', CAST(N'2019-01-25T19:00:46.967' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.967' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30349, N'sys', CAST(N'2019-01-25T19:00:46.970' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.970' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30350, N'sys', CAST(N'2019-01-25T19:00:46.970' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.970' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30351, N'sys', CAST(N'2019-01-25T19:00:46.970' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.970' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30352, N'sys', CAST(N'2019-01-25T19:00:46.973' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.973' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30353, N'sys', CAST(N'2019-01-25T19:00:46.973' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.973' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30354, N'sys', CAST(N'2019-01-25T19:00:46.973' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:46.973' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30355, N'sys', CAST(N'2019-01-25T19:00:47.027' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.027' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30356, N'sys', CAST(N'2019-01-25T19:00:47.027' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.027' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30357, N'sys', CAST(N'2019-01-25T19:00:47.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30358, N'sys', CAST(N'2019-01-25T19:00:47.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30359, N'sys', CAST(N'2019-01-25T19:00:47.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30360, N'sys', CAST(N'2019-01-25T19:00:47.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30361, N'sys', CAST(N'2019-01-25T19:00:47.033' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.033' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30362, N'sys', CAST(N'2019-01-25T19:00:47.077' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.077' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30363, N'sys', CAST(N'2019-01-25T19:00:47.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30364, N'sys', CAST(N'2019-01-25T19:00:47.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30365, N'sys', CAST(N'2019-01-25T19:00:47.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30366, N'sys', CAST(N'2019-01-25T19:00:47.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30367, N'sys', CAST(N'2019-01-25T19:00:47.083' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.083' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30368, N'sys', CAST(N'2019-01-25T19:00:47.083' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.083' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30369, N'sys', CAST(N'2019-01-25T19:00:47.087' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.087' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30370, N'sys', CAST(N'2019-01-25T19:00:47.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30371, N'sys', CAST(N'2019-01-25T19:00:47.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30372, N'sys', CAST(N'2019-01-25T19:00:47.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30373, N'sys', CAST(N'2019-01-25T19:00:47.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30374, N'sys', CAST(N'2019-01-25T19:00:47.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30375, N'sys', CAST(N'2019-01-25T19:00:47.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30376, N'sys', CAST(N'2019-01-25T19:00:47.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30377, N'sys', CAST(N'2019-01-25T19:00:47.193' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.193' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30378, N'sys', CAST(N'2019-01-25T19:00:47.193' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.193' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30379, N'sys', CAST(N'2019-01-25T19:00:47.197' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.197' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30380, N'sys', CAST(N'2019-01-25T19:00:47.197' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.197' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30381, N'sys', CAST(N'2019-01-25T19:00:47.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30382, N'sys', CAST(N'2019-01-25T19:00:47.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30383, N'sys', CAST(N'2019-01-25T19:00:47.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30384, N'sys', CAST(N'2019-01-25T19:00:47.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30385, N'sys', CAST(N'2019-01-25T19:00:47.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30386, N'sys', CAST(N'2019-01-25T19:00:47.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30387, N'sys', CAST(N'2019-01-25T19:00:47.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30388, N'sys', CAST(N'2019-01-25T19:00:47.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30389, N'sys', CAST(N'2019-01-25T19:00:47.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30390, N'sys', CAST(N'2019-01-25T19:00:47.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30391, N'sys', CAST(N'2019-01-25T19:00:47.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30392, N'sys', CAST(N'2019-01-25T19:00:47.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30393, N'sys', CAST(N'2019-01-25T19:00:47.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30394, N'sys', CAST(N'2019-01-25T19:00:47.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30395, N'sys', CAST(N'2019-01-25T19:00:47.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30396, N'sys', CAST(N'2019-01-25T19:00:47.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30397, N'sys', CAST(N'2019-01-25T19:00:47.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30398, N'sys', CAST(N'2019-01-25T19:00:47.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30399, N'sys', CAST(N'2019-01-25T19:00:47.277' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.277' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30400, N'sys', CAST(N'2019-01-25T19:00:47.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30401, N'sys', CAST(N'2019-01-25T19:00:47.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30402, N'sys', CAST(N'2019-01-25T19:00:47.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30403, N'sys', CAST(N'2019-01-25T19:00:47.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30404, N'sys', CAST(N'2019-01-25T19:00:47.283' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.283' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30405, N'sys', CAST(N'2019-01-25T19:00:47.283' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.283' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30406, N'sys', CAST(N'2019-01-25T19:00:47.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30407, N'sys', CAST(N'2019-01-25T19:00:47.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30408, N'sys', CAST(N'2019-01-25T19:00:47.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30409, N'sys', CAST(N'2019-01-25T19:00:47.303' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.303' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30410, N'sys', CAST(N'2019-01-25T19:00:47.303' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.303' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30411, N'sys', CAST(N'2019-01-25T19:00:47.307' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.307' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30412, N'sys', CAST(N'2019-01-25T19:00:47.307' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.307' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30413, N'sys', CAST(N'2019-01-25T19:00:47.327' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.327' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30414, N'sys', CAST(N'2019-01-25T19:00:47.327' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.327' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30415, N'sys', CAST(N'2019-01-25T19:00:47.327' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.327' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30416, N'sys', CAST(N'2019-01-25T19:00:47.330' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.330' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30417, N'sys', CAST(N'2019-01-25T19:00:47.330' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.330' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30418, N'sys', CAST(N'2019-01-25T19:00:47.330' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.330' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30419, N'sys', CAST(N'2019-01-25T19:00:47.333' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.333' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30420, N'sys', CAST(N'2019-01-25T19:00:47.343' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.343' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30421, N'sys', CAST(N'2019-01-25T19:00:47.347' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.347' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30422, N'sys', CAST(N'2019-01-25T19:00:47.347' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.347' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30423, N'sys', CAST(N'2019-01-25T19:00:47.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30424, N'sys', CAST(N'2019-01-25T19:00:47.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30425, N'sys', CAST(N'2019-01-25T19:00:47.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30426, N'sys', CAST(N'2019-01-25T19:00:47.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30427, N'sys', CAST(N'2019-01-25T19:00:47.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30428, N'sys', CAST(N'2019-01-25T19:00:47.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30429, N'sys', CAST(N'2019-01-25T19:00:47.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30430, N'sys', CAST(N'2019-01-25T19:00:47.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30431, N'sys', CAST(N'2019-01-25T19:00:47.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30432, N'sys', CAST(N'2019-01-25T19:00:47.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30433, N'sys', CAST(N'2019-01-25T19:00:47.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30434, N'sys', CAST(N'2019-01-25T19:00:47.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30435, N'sys', CAST(N'2019-01-25T19:00:47.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30436, N'sys', CAST(N'2019-01-25T19:00:47.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30437, N'sys', CAST(N'2019-01-25T19:00:47.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30438, N'sys', CAST(N'2019-01-25T19:00:47.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30439, N'sys', CAST(N'2019-01-25T19:00:47.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30440, N'sys', CAST(N'2019-01-25T19:00:47.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30441, N'sys', CAST(N'2019-01-25T19:00:47.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30442, N'sys', CAST(N'2019-01-25T19:00:47.413' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.413' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30443, N'sys', CAST(N'2019-01-25T19:00:47.413' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.413' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30444, N'sys', CAST(N'2019-01-25T19:00:47.417' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.417' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30445, N'sys', CAST(N'2019-01-25T19:00:47.417' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.417' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30446, N'sys', CAST(N'2019-01-25T19:00:47.417' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.417' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30447, N'sys', CAST(N'2019-01-25T19:00:47.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30448, N'sys', CAST(N'2019-01-25T19:00:47.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30449, N'sys', CAST(N'2019-01-25T19:00:47.433' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.433' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30450, N'sys', CAST(N'2019-01-25T19:00:47.437' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.437' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30451, N'sys', CAST(N'2019-01-25T19:00:47.437' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.437' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30452, N'sys', CAST(N'2019-01-25T19:00:47.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30453, N'sys', CAST(N'2019-01-25T19:00:47.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30454, N'sys', CAST(N'2019-01-25T19:00:47.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30455, N'sys', CAST(N'2019-01-25T19:00:47.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30456, N'sys', CAST(N'2019-01-25T19:00:47.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30457, N'sys', CAST(N'2019-01-25T19:00:47.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30458, N'sys', CAST(N'2019-01-25T19:00:47.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30459, N'sys', CAST(N'2019-01-25T19:00:47.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30460, N'sys', CAST(N'2019-01-25T19:00:47.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30461, N'sys', CAST(N'2019-01-25T19:00:47.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30462, N'sys', CAST(N'2019-01-25T19:00:47.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30463, N'sys', CAST(N'2019-01-25T19:00:47.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30464, N'sys', CAST(N'2019-01-25T19:00:47.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30465, N'sys', CAST(N'2019-01-25T19:00:47.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30466, N'sys', CAST(N'2019-01-25T19:00:47.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30467, N'sys', CAST(N'2019-01-25T19:00:47.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30468, N'sys', CAST(N'2019-01-25T19:00:47.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30469, N'sys', CAST(N'2019-01-25T19:00:47.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30470, N'sys', CAST(N'2019-01-25T19:00:47.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30471, N'sys', CAST(N'2019-01-25T19:00:47.513' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.513' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30472, N'sys', CAST(N'2019-01-25T19:00:47.513' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.513' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30473, N'sys', CAST(N'2019-01-25T19:00:47.513' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.513' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30474, N'sys', CAST(N'2019-01-25T19:00:47.517' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.517' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30475, N'sys', CAST(N'2019-01-25T19:00:47.517' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.517' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30476, N'sys', CAST(N'2019-01-25T19:00:47.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30477, N'sys', CAST(N'2019-01-25T19:00:47.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30478, N'sys', CAST(N'2019-01-25T19:00:47.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30479, N'sys', CAST(N'2019-01-25T19:00:47.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30480, N'sys', CAST(N'2019-01-25T19:00:47.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30481, N'sys', CAST(N'2019-01-25T19:00:47.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30482, N'sys', CAST(N'2019-01-25T19:00:47.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30483, N'sys', CAST(N'2019-01-25T19:00:47.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30484, N'sys', CAST(N'2019-01-25T19:00:47.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30485, N'sys', CAST(N'2019-01-25T19:00:47.560' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.560' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30486, N'sys', CAST(N'2019-01-25T19:00:47.560' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.560' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30487, N'sys', CAST(N'2019-01-25T19:00:47.560' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.560' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30488, N'sys', CAST(N'2019-01-25T19:00:47.563' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.563' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30489, N'sys', CAST(N'2019-01-25T19:00:47.563' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.563' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30490, N'sys', CAST(N'2019-01-25T19:00:47.567' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.567' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30491, N'sys', CAST(N'2019-01-25T19:00:47.567' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.567' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30492, N'sys', CAST(N'2019-01-25T19:00:47.567' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.567' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30493, N'sys', CAST(N'2019-01-25T19:00:47.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30494, N'sys', CAST(N'2019-01-25T19:00:47.583' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.583' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30495, N'sys', CAST(N'2019-01-25T19:00:47.583' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.583' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30496, N'sys', CAST(N'2019-01-25T19:00:47.583' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.583' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30497, N'sys', CAST(N'2019-01-25T19:00:47.587' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.587' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30498, N'sys', CAST(N'2019-01-25T19:00:47.587' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.587' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30499, N'sys', CAST(N'2019-01-25T19:00:47.590' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.590' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30500, N'sys', CAST(N'2019-01-25T19:00:47.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30501, N'sys', CAST(N'2019-01-25T19:00:47.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30502, N'sys', CAST(N'2019-01-25T19:00:47.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30503, N'sys', CAST(N'2019-01-25T19:00:47.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30504, N'sys', CAST(N'2019-01-25T19:00:47.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30505, N'sys', CAST(N'2019-01-25T19:00:47.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30506, N'sys', CAST(N'2019-01-25T19:00:47.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30507, N'sys', CAST(N'2019-01-25T19:00:47.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30508, N'sys', CAST(N'2019-01-25T19:00:47.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30509, N'sys', CAST(N'2019-01-25T19:00:47.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30510, N'sys', CAST(N'2019-01-25T19:00:47.633' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.633' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30511, N'sys', CAST(N'2019-01-25T19:00:47.633' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.633' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30512, N'sys', CAST(N'2019-01-25T19:00:47.633' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.633' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30513, N'sys', CAST(N'2019-01-25T19:00:47.637' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.637' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30514, N'sys', CAST(N'2019-01-25T19:00:47.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30515, N'sys', CAST(N'2019-01-25T19:00:47.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30516, N'sys', CAST(N'2019-01-25T19:00:47.653' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.653' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30517, N'sys', CAST(N'2019-01-25T19:00:47.653' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.653' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30518, N'sys', CAST(N'2019-01-25T19:00:47.657' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.657' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30519, N'sys', CAST(N'2019-01-25T19:00:47.657' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.657' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30520, N'sys', CAST(N'2019-01-25T19:00:47.657' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.657' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30521, N'sys', CAST(N'2019-01-25T19:00:47.660' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.660' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30522, N'sys', CAST(N'2019-01-25T19:00:47.673' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.673' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30523, N'sys', CAST(N'2019-01-25T19:00:47.677' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.677' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30524, N'sys', CAST(N'2019-01-25T19:00:47.677' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.677' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30525, N'sys', CAST(N'2019-01-25T19:00:47.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30526, N'sys', CAST(N'2019-01-25T19:00:47.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30527, N'sys', CAST(N'2019-01-25T19:00:47.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30528, N'sys', CAST(N'2019-01-25T19:00:47.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30529, N'sys', CAST(N'2019-01-25T19:00:47.700' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.700' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30530, N'sys', CAST(N'2019-01-25T19:00:47.700' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.700' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30531, N'sys', CAST(N'2019-01-25T19:00:47.703' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.703' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30532, N'sys', CAST(N'2019-01-25T19:00:47.703' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.703' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30533, N'sys', CAST(N'2019-01-25T19:00:47.707' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.707' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30534, N'sys', CAST(N'2019-01-25T19:00:47.707' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.707' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30535, N'sys', CAST(N'2019-01-25T19:00:47.707' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.707' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30536, N'sys', CAST(N'2019-01-25T19:00:47.723' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.723' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30537, N'sys', CAST(N'2019-01-25T19:00:47.727' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.727' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30538, N'sys', CAST(N'2019-01-25T19:00:47.727' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.727' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30539, N'sys', CAST(N'2019-01-25T19:00:47.730' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.730' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30540, N'sys', CAST(N'2019-01-25T19:00:47.730' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.730' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30541, N'sys', CAST(N'2019-01-25T19:00:47.730' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.730' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30542, N'sys', CAST(N'2019-01-25T19:00:47.730' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.730' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30543, N'sys', CAST(N'2019-01-25T19:00:47.750' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.750' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30544, N'sys', CAST(N'2019-01-25T19:00:47.753' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.753' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30545, N'sys', CAST(N'2019-01-25T19:00:47.753' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.753' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30546, N'sys', CAST(N'2019-01-25T19:00:47.757' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.757' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30547, N'sys', CAST(N'2019-01-25T19:00:47.757' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.757' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30548, N'sys', CAST(N'2019-01-25T19:00:47.757' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.757' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30549, N'sys', CAST(N'2019-01-25T19:00:47.760' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.760' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30550, N'sys', CAST(N'2019-01-25T19:00:47.770' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.770' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30551, N'sys', CAST(N'2019-01-25T19:00:47.773' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.773' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30552, N'sys', CAST(N'2019-01-25T19:00:47.773' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.773' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30553, N'sys', CAST(N'2019-01-25T19:00:47.777' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.777' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30554, N'sys', CAST(N'2019-01-25T19:00:47.777' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.777' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30555, N'sys', CAST(N'2019-01-25T19:00:47.777' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.777' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30556, N'sys', CAST(N'2019-01-25T19:00:47.780' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.780' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30557, N'sys', CAST(N'2019-01-25T19:00:47.780' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.780' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30558, N'sys', CAST(N'2019-01-25T19:00:47.800' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.800' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30559, N'sys', CAST(N'2019-01-25T19:00:47.800' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.800' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30560, N'sys', CAST(N'2019-01-25T19:00:47.800' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.800' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30561, N'sys', CAST(N'2019-01-25T19:00:47.800' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.800' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30562, N'sys', CAST(N'2019-01-25T19:00:47.803' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.803' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30563, N'sys', CAST(N'2019-01-25T19:00:47.803' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.803' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30564, N'sys', CAST(N'2019-01-25T19:00:47.803' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.803' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30565, N'sys', CAST(N'2019-01-25T19:00:47.820' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.820' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30566, N'sys', CAST(N'2019-01-25T19:00:47.823' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.823' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30567, N'sys', CAST(N'2019-01-25T19:00:47.823' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.823' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30568, N'sys', CAST(N'2019-01-25T19:00:47.823' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.823' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30569, N'sys', CAST(N'2019-01-25T19:00:47.827' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.827' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30570, N'sys', CAST(N'2019-01-25T19:00:47.827' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.827' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30571, N'sys', CAST(N'2019-01-25T19:00:47.830' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.830' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30572, N'sys', CAST(N'2019-01-25T19:00:47.847' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.847' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30573, N'sys', CAST(N'2019-01-25T19:00:47.847' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.847' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30574, N'sys', CAST(N'2019-01-25T19:00:47.850' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.850' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30575, N'sys', CAST(N'2019-01-25T19:00:47.850' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.850' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30576, N'sys', CAST(N'2019-01-25T19:00:47.850' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.850' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30577, N'sys', CAST(N'2019-01-25T19:00:47.853' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.853' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30578, N'sys', CAST(N'2019-01-25T19:00:47.853' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.853' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30579, N'sys', CAST(N'2019-01-25T19:00:47.870' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.870' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30580, N'sys', CAST(N'2019-01-25T19:00:47.870' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.870' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30581, N'sys', CAST(N'2019-01-25T19:00:47.870' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.870' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30582, N'sys', CAST(N'2019-01-25T19:00:47.873' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.873' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30583, N'sys', CAST(N'2019-01-25T19:00:47.873' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.873' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30584, N'sys', CAST(N'2019-01-25T19:00:47.873' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.873' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30585, N'sys', CAST(N'2019-01-25T19:00:47.877' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.877' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30586, N'sys', CAST(N'2019-01-25T19:00:47.877' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.877' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30587, N'sys', CAST(N'2019-01-25T19:00:47.897' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.897' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30588, N'sys', CAST(N'2019-01-25T19:00:47.897' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.897' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30589, N'sys', CAST(N'2019-01-25T19:00:47.900' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.900' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30590, N'sys', CAST(N'2019-01-25T19:00:47.900' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.900' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30591, N'sys', CAST(N'2019-01-25T19:00:47.900' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.900' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30592, N'sys', CAST(N'2019-01-25T19:00:47.900' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.900' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30593, N'sys', CAST(N'2019-01-25T19:00:47.903' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.903' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30594, N'sys', CAST(N'2019-01-25T19:00:47.920' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.920' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30595, N'sys', CAST(N'2019-01-25T19:00:47.920' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.920' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30596, N'sys', CAST(N'2019-01-25T19:00:47.923' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.923' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30597, N'sys', CAST(N'2019-01-25T19:00:47.923' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.923' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30598, N'sys', CAST(N'2019-01-25T19:00:47.927' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.927' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30599, N'sys', CAST(N'2019-01-25T19:00:47.927' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.927' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30600, N'sys', CAST(N'2019-01-25T19:00:47.927' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.927' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30601, N'sys', CAST(N'2019-01-25T19:00:47.943' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.943' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30602, N'sys', CAST(N'2019-01-25T19:00:47.947' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.947' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30603, N'sys', CAST(N'2019-01-25T19:00:47.947' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.947' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30604, N'sys', CAST(N'2019-01-25T19:00:47.947' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.947' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30605, N'sys', CAST(N'2019-01-25T19:00:47.950' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.950' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30606, N'sys', CAST(N'2019-01-25T19:00:47.950' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.950' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30607, N'sys', CAST(N'2019-01-25T19:00:47.950' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.950' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30608, N'sys', CAST(N'2019-01-25T19:00:47.970' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.970' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30609, N'sys', CAST(N'2019-01-25T19:00:47.970' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.970' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30610, N'sys', CAST(N'2019-01-25T19:00:47.973' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.973' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30611, N'sys', CAST(N'2019-01-25T19:00:47.973' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.973' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30612, N'sys', CAST(N'2019-01-25T19:00:47.977' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.977' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30613, N'sys', CAST(N'2019-01-25T19:00:47.977' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.977' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30614, N'sys', CAST(N'2019-01-25T19:00:47.977' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.977' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30615, N'sys', CAST(N'2019-01-25T19:00:47.980' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.980' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30616, N'sys', CAST(N'2019-01-25T19:00:47.997' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.997' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30617, N'sys', CAST(N'2019-01-25T19:00:47.997' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:47.997' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30618, N'sys', CAST(N'2019-01-25T19:00:48.000' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.000' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30619, N'sys', CAST(N'2019-01-25T19:00:48.000' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.000' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30620, N'sys', CAST(N'2019-01-25T19:00:48.000' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.000' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30621, N'sys', CAST(N'2019-01-25T19:00:48.003' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.003' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30622, N'sys', CAST(N'2019-01-25T19:00:48.003' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.003' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30623, N'sys', CAST(N'2019-01-25T19:00:48.023' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.023' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30624, N'sys', CAST(N'2019-01-25T19:00:48.023' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.023' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30625, N'sys', CAST(N'2019-01-25T19:00:48.027' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.027' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30626, N'sys', CAST(N'2019-01-25T19:00:48.027' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.027' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30627, N'sys', CAST(N'2019-01-25T19:00:48.027' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.027' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30628, N'sys', CAST(N'2019-01-25T19:00:48.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30629, N'sys', CAST(N'2019-01-25T19:00:48.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30630, N'sys', CAST(N'2019-01-25T19:00:48.047' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.047' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30631, N'sys', CAST(N'2019-01-25T19:00:48.047' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.047' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30632, N'sys', CAST(N'2019-01-25T19:00:48.050' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.050' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30633, N'sys', CAST(N'2019-01-25T19:00:48.050' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.050' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30634, N'sys', CAST(N'2019-01-25T19:00:48.050' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.050' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30635, N'sys', CAST(N'2019-01-25T19:00:48.053' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.053' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30636, N'sys', CAST(N'2019-01-25T19:00:48.053' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.053' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30637, N'sys', CAST(N'2019-01-25T19:00:48.053' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.053' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30638, N'sys', CAST(N'2019-01-25T19:00:48.057' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.057' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30639, N'sys', CAST(N'2019-01-25T19:00:48.057' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.057' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30640, N'sys', CAST(N'2019-01-25T19:00:48.060' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.060' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30641, N'sys', CAST(N'2019-01-25T19:00:48.060' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.060' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30642, N'sys', CAST(N'2019-01-25T19:00:48.060' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.060' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30643, N'sys', CAST(N'2019-01-25T19:00:48.063' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.063' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30644, N'sys', CAST(N'2019-01-25T19:00:48.063' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.063' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30645, N'sys', CAST(N'2019-01-25T19:00:48.063' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.063' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30646, N'sys', CAST(N'2019-01-25T19:00:48.067' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.067' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30647, N'sys', CAST(N'2019-01-25T19:00:48.067' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.067' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30648, N'sys', CAST(N'2019-01-25T19:00:48.070' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.070' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30649, N'sys', CAST(N'2019-01-25T19:00:48.070' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.070' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30650, N'sys', CAST(N'2019-01-25T19:00:48.070' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.070' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30651, N'sys', CAST(N'2019-01-25T19:00:48.070' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.070' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30652, N'sys', CAST(N'2019-01-25T19:00:48.073' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.073' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30653, N'sys', CAST(N'2019-01-25T19:00:48.073' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.073' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30654, N'sys', CAST(N'2019-01-25T19:00:48.077' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.077' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30655, N'sys', CAST(N'2019-01-25T19:00:48.077' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.077' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30656, N'sys', CAST(N'2019-01-25T19:00:48.077' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.077' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30657, N'sys', CAST(N'2019-01-25T19:00:48.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30658, N'sys', CAST(N'2019-01-25T19:00:48.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30659, N'sys', CAST(N'2019-01-25T19:00:48.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30660, N'sys', CAST(N'2019-01-25T19:00:48.083' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.083' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30661, N'sys', CAST(N'2019-01-25T19:00:48.083' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.083' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30662, N'sys', CAST(N'2019-01-25T19:00:48.083' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.083' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30663, N'sys', CAST(N'2019-01-25T19:00:48.087' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.087' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30664, N'sys', CAST(N'2019-01-25T19:00:48.087' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.087' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30665, N'sys', CAST(N'2019-01-25T19:00:48.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30666, N'sys', CAST(N'2019-01-25T19:00:48.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30667, N'sys', CAST(N'2019-01-25T19:00:48.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30668, N'sys', CAST(N'2019-01-25T19:00:48.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30669, N'sys', CAST(N'2019-01-25T19:00:48.093' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.093' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30670, N'sys', CAST(N'2019-01-25T19:00:48.093' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.093' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30671, N'sys', CAST(N'2019-01-25T19:00:48.097' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.097' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30672, N'sys', CAST(N'2019-01-25T19:00:48.097' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.097' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30673, N'sys', CAST(N'2019-01-25T19:00:48.100' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.100' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30674, N'sys', CAST(N'2019-01-25T19:00:48.100' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.100' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30675, N'sys', CAST(N'2019-01-25T19:00:48.100' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.100' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30676, N'sys', CAST(N'2019-01-25T19:00:48.100' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.100' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30677, N'sys', CAST(N'2019-01-25T19:00:48.103' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.103' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30678, N'sys', CAST(N'2019-01-25T19:00:48.103' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.103' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30679, N'sys', CAST(N'2019-01-25T19:00:48.107' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.107' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30680, N'sys', CAST(N'2019-01-25T19:00:48.107' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.107' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30681, N'sys', CAST(N'2019-01-25T19:00:48.107' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.107' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30682, N'sys', CAST(N'2019-01-25T19:00:48.110' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.110' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30683, N'sys', CAST(N'2019-01-25T19:00:48.110' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.110' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30684, N'sys', CAST(N'2019-01-25T19:00:48.110' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.110' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30685, N'sys', CAST(N'2019-01-25T19:00:48.113' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.113' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30686, N'sys', CAST(N'2019-01-25T19:00:48.113' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.113' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30687, N'sys', CAST(N'2019-01-25T19:00:48.113' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.113' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30688, N'sys', CAST(N'2019-01-25T19:00:48.117' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.117' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30689, N'sys', CAST(N'2019-01-25T19:00:48.117' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.117' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30690, N'sys', CAST(N'2019-01-25T19:00:48.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30691, N'sys', CAST(N'2019-01-25T19:00:48.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30692, N'sys', CAST(N'2019-01-25T19:00:48.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30693, N'sys', CAST(N'2019-01-25T19:00:48.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30694, N'sys', CAST(N'2019-01-25T19:00:48.123' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.123' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30695, N'sys', CAST(N'2019-01-25T19:00:48.123' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.123' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30696, N'sys', CAST(N'2019-01-25T19:00:48.127' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.127' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30697, N'sys', CAST(N'2019-01-25T19:00:48.127' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.127' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30698, N'sys', CAST(N'2019-01-25T19:00:48.127' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.127' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30699, N'sys', CAST(N'2019-01-25T19:00:48.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30700, N'sys', CAST(N'2019-01-25T19:00:48.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30701, N'sys', CAST(N'2019-01-25T19:00:48.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30702, N'sys', CAST(N'2019-01-25T19:00:48.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30703, N'sys', CAST(N'2019-01-25T19:00:48.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30704, N'sys', CAST(N'2019-01-25T19:00:48.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30705, N'sys', CAST(N'2019-01-25T19:00:48.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30706, N'sys', CAST(N'2019-01-25T19:00:48.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30707, N'sys', CAST(N'2019-01-25T19:00:48.140' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.140' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30708, N'sys', CAST(N'2019-01-25T19:00:48.140' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.140' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30709, N'sys', CAST(N'2019-01-25T19:00:48.140' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.140' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30710, N'sys', CAST(N'2019-01-25T19:00:48.143' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.143' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30711, N'sys', CAST(N'2019-01-25T19:00:48.143' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.143' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30712, N'sys', CAST(N'2019-01-25T19:00:48.143' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.143' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30713, N'sys', CAST(N'2019-01-25T19:00:48.147' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.147' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30714, N'sys', CAST(N'2019-01-25T19:00:48.147' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.147' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30715, N'sys', CAST(N'2019-01-25T19:00:48.150' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.150' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30716, N'sys', CAST(N'2019-01-25T19:00:48.150' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.150' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30717, N'sys', CAST(N'2019-01-25T19:00:48.150' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.150' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30718, N'sys', CAST(N'2019-01-25T19:00:48.150' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.150' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30719, N'sys', CAST(N'2019-01-25T19:00:48.153' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.153' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30720, N'sys', CAST(N'2019-01-25T19:00:48.153' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.153' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30721, N'sys', CAST(N'2019-01-25T19:00:48.157' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.157' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30722, N'sys', CAST(N'2019-01-25T19:00:48.157' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.157' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30723, N'sys', CAST(N'2019-01-25T19:00:48.157' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.157' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30724, N'sys', CAST(N'2019-01-25T19:00:48.160' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.160' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30725, N'sys', CAST(N'2019-01-25T19:00:48.160' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.160' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30726, N'sys', CAST(N'2019-01-25T19:00:48.160' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.160' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30727, N'sys', CAST(N'2019-01-25T19:00:48.163' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.163' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30728, N'sys', CAST(N'2019-01-25T19:00:48.163' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.163' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30729, N'sys', CAST(N'2019-01-25T19:00:48.163' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.163' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30730, N'sys', CAST(N'2019-01-25T19:00:48.167' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.167' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30731, N'sys', CAST(N'2019-01-25T19:00:48.167' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.167' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30732, N'sys', CAST(N'2019-01-25T19:00:48.170' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.170' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30733, N'sys', CAST(N'2019-01-25T19:00:48.170' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.170' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30734, N'sys', CAST(N'2019-01-25T19:00:48.170' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.170' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30735, N'sys', CAST(N'2019-01-25T19:00:48.173' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.173' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30736, N'sys', CAST(N'2019-01-25T19:00:48.173' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.173' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30737, N'sys', CAST(N'2019-01-25T19:00:48.173' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.173' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30738, N'sys', CAST(N'2019-01-25T19:00:48.177' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.177' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30739, N'sys', CAST(N'2019-01-25T19:00:48.177' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.177' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30740, N'sys', CAST(N'2019-01-25T19:00:48.177' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.177' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30741, N'sys', CAST(N'2019-01-25T19:00:48.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30742, N'sys', CAST(N'2019-01-25T19:00:48.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30743, N'sys', CAST(N'2019-01-25T19:00:48.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30744, N'sys', CAST(N'2019-01-25T19:00:48.183' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.183' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30745, N'sys', CAST(N'2019-01-25T19:00:48.183' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.183' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30746, N'sys', CAST(N'2019-01-25T19:00:48.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30747, N'sys', CAST(N'2019-01-25T19:00:48.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30748, N'sys', CAST(N'2019-01-25T19:00:48.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30749, N'sys', CAST(N'2019-01-25T19:00:48.190' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.190' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30750, N'sys', CAST(N'2019-01-25T19:00:48.190' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.190' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30751, N'sys', CAST(N'2019-01-25T19:00:48.190' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.190' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30752, N'sys', CAST(N'2019-01-25T19:00:48.193' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.193' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30753, N'sys', CAST(N'2019-01-25T19:00:48.193' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.193' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30754, N'sys', CAST(N'2019-01-25T19:00:48.193' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.193' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30755, N'sys', CAST(N'2019-01-25T19:00:48.197' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.197' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30756, N'sys', CAST(N'2019-01-25T19:00:48.197' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.197' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30757, N'sys', CAST(N'2019-01-25T19:00:48.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30758, N'sys', CAST(N'2019-01-25T19:00:48.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30759, N'sys', CAST(N'2019-01-25T19:00:48.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30760, N'sys', CAST(N'2019-01-25T19:00:48.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30761, N'sys', CAST(N'2019-01-25T19:00:48.203' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.203' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30762, N'sys', CAST(N'2019-01-25T19:00:48.203' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.203' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30763, N'sys', CAST(N'2019-01-25T19:00:48.207' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.207' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30764, N'sys', CAST(N'2019-01-25T19:00:48.207' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.207' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30765, N'sys', CAST(N'2019-01-25T19:00:48.207' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.207' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30766, N'sys', CAST(N'2019-01-25T19:00:48.210' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.210' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30767, N'sys', CAST(N'2019-01-25T19:00:48.210' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.210' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30768, N'sys', CAST(N'2019-01-25T19:00:48.210' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.210' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30769, N'sys', CAST(N'2019-01-25T19:00:48.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30770, N'sys', CAST(N'2019-01-25T19:00:48.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30771, N'sys', CAST(N'2019-01-25T19:00:48.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30772, N'sys', CAST(N'2019-01-25T19:00:48.217' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.217' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30773, N'sys', CAST(N'2019-01-25T19:00:48.217' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.217' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30774, N'sys', CAST(N'2019-01-25T19:00:48.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30775, N'sys', CAST(N'2019-01-25T19:00:48.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30776, N'sys', CAST(N'2019-01-25T19:00:48.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30777, N'sys', CAST(N'2019-01-25T19:00:48.223' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.223' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30778, N'sys', CAST(N'2019-01-25T19:00:48.223' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.223' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30779, N'sys', CAST(N'2019-01-25T19:00:48.223' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.223' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30780, N'sys', CAST(N'2019-01-25T19:00:48.227' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.227' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30781, N'sys', CAST(N'2019-01-25T19:00:48.227' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.227' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30782, N'sys', CAST(N'2019-01-25T19:00:48.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30783, N'sys', CAST(N'2019-01-25T19:00:48.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30784, N'sys', CAST(N'2019-01-25T19:00:48.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30785, N'sys', CAST(N'2019-01-25T19:00:48.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30786, N'sys', CAST(N'2019-01-25T19:00:48.233' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.233' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30787, N'sys', CAST(N'2019-01-25T19:00:48.233' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.233' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30788, N'sys', CAST(N'2019-01-25T19:00:48.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30789, N'sys', CAST(N'2019-01-25T19:00:48.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30790, N'sys', CAST(N'2019-01-25T19:00:48.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30791, N'sys', CAST(N'2019-01-25T19:00:48.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30792, N'sys', CAST(N'2019-01-25T19:00:48.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30793, N'sys', CAST(N'2019-01-25T19:00:48.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30794, N'sys', CAST(N'2019-01-25T19:00:48.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30795, N'sys', CAST(N'2019-01-25T19:00:48.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30796, N'sys', CAST(N'2019-01-25T19:00:48.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30797, N'sys', CAST(N'2019-01-25T19:00:48.247' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.247' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30798, N'sys', CAST(N'2019-01-25T19:00:48.247' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.247' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30799, N'sys', CAST(N'2019-01-25T19:00:48.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30800, N'sys', CAST(N'2019-01-25T19:00:48.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30801, N'sys', CAST(N'2019-01-25T19:00:48.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30802, N'sys', CAST(N'2019-01-25T19:00:48.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30803, N'sys', CAST(N'2019-01-25T19:00:48.253' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.253' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30804, N'sys', CAST(N'2019-01-25T19:00:48.253' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.253' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30805, N'sys', CAST(N'2019-01-25T19:00:48.253' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.253' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30806, N'sys', CAST(N'2019-01-25T19:00:48.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30807, N'sys', CAST(N'2019-01-25T19:00:48.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30808, N'sys', CAST(N'2019-01-25T19:00:48.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30809, N'sys', CAST(N'2019-01-25T19:00:48.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30810, N'sys', CAST(N'2019-01-25T19:00:48.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30811, N'sys', CAST(N'2019-01-25T19:00:48.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30812, N'sys', CAST(N'2019-01-25T19:00:48.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30813, N'sys', CAST(N'2019-01-25T19:00:48.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30814, N'sys', CAST(N'2019-01-25T19:00:48.267' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.267' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30815, N'sys', CAST(N'2019-01-25T19:00:48.267' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.267' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30816, N'sys', CAST(N'2019-01-25T19:00:48.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30817, N'sys', CAST(N'2019-01-25T19:00:48.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30818, N'sys', CAST(N'2019-01-25T19:00:48.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30819, N'sys', CAST(N'2019-01-25T19:00:48.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30820, N'sys', CAST(N'2019-01-25T19:00:48.273' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.273' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30821, N'sys', CAST(N'2019-01-25T19:00:48.273' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.273' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30822, N'sys', CAST(N'2019-01-25T19:00:48.273' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.273' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30823, N'sys', CAST(N'2019-01-25T19:00:48.277' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.277' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30824, N'sys', CAST(N'2019-01-25T19:00:48.277' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.277' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30825, N'sys', CAST(N'2019-01-25T19:00:48.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30826, N'sys', CAST(N'2019-01-25T19:00:48.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30827, N'sys', CAST(N'2019-01-25T19:00:48.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30828, N'sys', CAST(N'2019-01-25T19:00:48.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30829, N'sys', CAST(N'2019-01-25T19:00:48.283' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.283' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30830, N'sys', CAST(N'2019-01-25T19:00:48.287' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.287' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30831, N'sys', CAST(N'2019-01-25T19:00:48.287' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.287' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30832, N'sys', CAST(N'2019-01-25T19:00:48.287' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.287' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30833, N'sys', CAST(N'2019-01-25T19:00:48.290' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.290' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30834, N'sys', CAST(N'2019-01-25T19:00:48.290' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.290' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30835, N'sys', CAST(N'2019-01-25T19:00:48.290' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.290' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30836, N'sys', CAST(N'2019-01-25T19:00:48.293' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.293' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30837, N'sys', CAST(N'2019-01-25T19:00:48.293' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.293' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30838, N'sys', CAST(N'2019-01-25T19:00:48.293' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.293' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30839, N'sys', CAST(N'2019-01-25T19:00:48.297' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.297' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30840, N'sys', CAST(N'2019-01-25T19:00:48.297' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.297' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30841, N'sys', CAST(N'2019-01-25T19:00:48.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30842, N'sys', CAST(N'2019-01-25T19:00:48.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30843, N'sys', CAST(N'2019-01-25T19:00:48.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30844, N'sys', CAST(N'2019-01-25T19:00:48.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30845, N'sys', CAST(N'2019-01-25T19:00:48.303' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.303' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30846, N'sys', CAST(N'2019-01-25T19:00:48.303' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.303' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30847, N'sys', CAST(N'2019-01-25T19:00:48.307' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.307' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30848, N'sys', CAST(N'2019-01-25T19:00:48.307' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.307' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30849, N'sys', CAST(N'2019-01-25T19:00:48.307' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.307' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30850, N'sys', CAST(N'2019-01-25T19:00:48.310' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.310' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30851, N'sys', CAST(N'2019-01-25T19:00:48.310' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.310' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30852, N'sys', CAST(N'2019-01-25T19:00:48.310' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.310' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30853, N'sys', CAST(N'2019-01-25T19:00:48.313' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.313' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30854, N'sys', CAST(N'2019-01-25T19:00:48.313' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.313' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30855, N'sys', CAST(N'2019-01-25T19:00:48.317' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.317' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30856, N'sys', CAST(N'2019-01-25T19:00:48.317' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.317' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30857, N'sys', CAST(N'2019-01-25T19:00:48.317' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.317' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30858, N'sys', CAST(N'2019-01-25T19:00:48.320' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.320' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30859, N'sys', CAST(N'2019-01-25T19:00:48.320' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.320' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30860, N'sys', CAST(N'2019-01-25T19:00:48.320' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.320' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30861, N'sys', CAST(N'2019-01-25T19:00:48.323' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.323' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30862, N'sys', CAST(N'2019-01-25T19:00:48.323' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.323' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30863, N'sys', CAST(N'2019-01-25T19:00:48.327' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.327' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30864, N'sys', CAST(N'2019-01-25T19:00:48.327' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.327' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30865, N'sys', CAST(N'2019-01-25T19:00:48.327' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.327' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30866, N'sys', CAST(N'2019-01-25T19:00:48.330' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.330' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30867, N'sys', CAST(N'2019-01-25T19:00:48.330' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.330' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30868, N'sys', CAST(N'2019-01-25T19:00:48.330' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.330' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30869, N'sys', CAST(N'2019-01-25T19:00:48.333' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.333' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30870, N'sys', CAST(N'2019-01-25T19:00:48.333' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.333' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30871, N'sys', CAST(N'2019-01-25T19:00:48.333' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.333' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30872, N'sys', CAST(N'2019-01-25T19:00:48.337' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.337' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30873, N'sys', CAST(N'2019-01-25T19:00:48.337' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.337' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30874, N'sys', CAST(N'2019-01-25T19:00:48.340' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.340' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30875, N'sys', CAST(N'2019-01-25T19:00:48.340' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.340' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30876, N'sys', CAST(N'2019-01-25T19:00:48.340' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.340' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30877, N'sys', CAST(N'2019-01-25T19:00:48.340' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.340' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30878, N'sys', CAST(N'2019-01-25T19:00:48.343' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.343' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30879, N'sys', CAST(N'2019-01-25T19:00:48.343' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.343' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30880, N'sys', CAST(N'2019-01-25T19:00:48.347' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.347' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30881, N'sys', CAST(N'2019-01-25T19:00:48.347' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.347' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30882, N'sys', CAST(N'2019-01-25T19:00:48.347' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.347' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30883, N'sys', CAST(N'2019-01-25T19:00:48.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30884, N'sys', CAST(N'2019-01-25T19:00:48.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30885, N'sys', CAST(N'2019-01-25T19:00:48.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30886, N'sys', CAST(N'2019-01-25T19:00:48.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30887, N'sys', CAST(N'2019-01-25T19:00:48.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30888, N'sys', CAST(N'2019-01-25T19:00:48.357' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.357' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30889, N'sys', CAST(N'2019-01-25T19:00:48.357' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.357' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30890, N'sys', CAST(N'2019-01-25T19:00:48.357' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.357' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30891, N'sys', CAST(N'2019-01-25T19:00:48.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30892, N'sys', CAST(N'2019-01-25T19:00:48.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30893, N'sys', CAST(N'2019-01-25T19:00:48.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30894, N'sys', CAST(N'2019-01-25T19:00:48.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30895, N'sys', CAST(N'2019-01-25T19:00:48.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30896, N'sys', CAST(N'2019-01-25T19:00:48.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30897, N'sys', CAST(N'2019-01-25T19:00:48.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30898, N'sys', CAST(N'2019-01-25T19:00:48.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30899, N'sys', CAST(N'2019-01-25T19:00:48.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30900, N'sys', CAST(N'2019-01-25T19:00:48.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30901, N'sys', CAST(N'2019-01-25T19:00:48.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30902, N'sys', CAST(N'2019-01-25T19:00:48.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30903, N'sys', CAST(N'2019-01-25T19:00:48.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30904, N'sys', CAST(N'2019-01-25T19:00:48.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30905, N'sys', CAST(N'2019-01-25T19:00:48.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30906, N'sys', CAST(N'2019-01-25T19:00:48.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30907, N'sys', CAST(N'2019-01-25T19:00:48.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30908, N'sys', CAST(N'2019-01-25T19:00:48.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30909, N'sys', CAST(N'2019-01-25T19:00:48.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30910, N'sys', CAST(N'2019-01-25T19:00:48.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30911, N'sys', CAST(N'2019-01-25T19:00:48.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30912, N'sys', CAST(N'2019-01-25T19:00:48.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30913, N'sys', CAST(N'2019-01-25T19:00:48.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30914, N'sys', CAST(N'2019-01-25T19:00:48.387' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.387' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30915, N'sys', CAST(N'2019-01-25T19:00:48.387' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.387' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30916, N'sys', CAST(N'2019-01-25T19:00:48.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30917, N'sys', CAST(N'2019-01-25T19:00:48.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30918, N'sys', CAST(N'2019-01-25T19:00:48.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30919, N'sys', CAST(N'2019-01-25T19:00:48.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30920, N'sys', CAST(N'2019-01-25T19:00:48.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30921, N'sys', CAST(N'2019-01-25T19:00:48.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30922, N'sys', CAST(N'2019-01-25T19:00:48.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30923, N'sys', CAST(N'2019-01-25T19:00:48.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30924, N'sys', CAST(N'2019-01-25T19:00:48.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30925, N'sys', CAST(N'2019-01-25T19:00:48.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30926, N'sys', CAST(N'2019-01-25T19:00:48.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30927, N'sys', CAST(N'2019-01-25T19:00:48.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30928, N'sys', CAST(N'2019-01-25T19:00:48.403' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.403' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30929, N'sys', CAST(N'2019-01-25T19:00:48.403' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.403' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30930, N'sys', CAST(N'2019-01-25T19:00:48.407' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.407' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30931, N'sys', CAST(N'2019-01-25T19:00:48.407' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.407' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30932, N'sys', CAST(N'2019-01-25T19:00:48.407' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.407' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30933, N'sys', CAST(N'2019-01-25T19:00:48.410' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.410' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30934, N'sys', CAST(N'2019-01-25T19:00:48.410' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.410' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30935, N'sys', CAST(N'2019-01-25T19:00:48.410' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.410' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30936, N'sys', CAST(N'2019-01-25T19:00:48.413' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.413' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30937, N'sys', CAST(N'2019-01-25T19:00:48.413' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.413' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30938, N'sys', CAST(N'2019-01-25T19:00:48.413' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.413' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30939, N'sys', CAST(N'2019-01-25T19:00:48.417' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.417' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30940, N'sys', CAST(N'2019-01-25T19:00:48.417' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.417' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30941, N'sys', CAST(N'2019-01-25T19:00:48.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30942, N'sys', CAST(N'2019-01-25T19:00:48.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30943, N'sys', CAST(N'2019-01-25T19:00:48.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30944, N'sys', CAST(N'2019-01-25T19:00:48.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30945, N'sys', CAST(N'2019-01-25T19:00:48.423' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.423' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30946, N'sys', CAST(N'2019-01-25T19:00:48.423' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.423' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30947, N'sys', CAST(N'2019-01-25T19:00:48.427' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.427' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30948, N'sys', CAST(N'2019-01-25T19:00:48.427' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.427' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30949, N'sys', CAST(N'2019-01-25T19:00:48.427' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.427' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30950, N'sys', CAST(N'2019-01-25T19:00:48.430' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.430' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30951, N'sys', CAST(N'2019-01-25T19:00:48.430' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.430' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30952, N'sys', CAST(N'2019-01-25T19:00:48.430' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.430' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30953, N'sys', CAST(N'2019-01-25T19:00:48.433' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.433' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30954, N'sys', CAST(N'2019-01-25T19:00:48.433' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.433' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30955, N'sys', CAST(N'2019-01-25T19:00:48.437' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.437' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30956, N'sys', CAST(N'2019-01-25T19:00:48.437' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.437' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30957, N'sys', CAST(N'2019-01-25T19:00:48.437' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.437' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30958, N'sys', CAST(N'2019-01-25T19:00:48.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30959, N'sys', CAST(N'2019-01-25T19:00:48.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30960, N'sys', CAST(N'2019-01-25T19:00:48.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30961, N'sys', CAST(N'2019-01-25T19:00:48.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30962, N'sys', CAST(N'2019-01-25T19:00:48.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30963, N'sys', CAST(N'2019-01-25T19:00:48.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30964, N'sys', CAST(N'2019-01-25T19:00:48.447' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.447' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30965, N'sys', CAST(N'2019-01-25T19:00:48.447' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.447' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30966, N'sys', CAST(N'2019-01-25T19:00:48.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30967, N'sys', CAST(N'2019-01-25T19:00:48.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30968, N'sys', CAST(N'2019-01-25T19:00:48.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30969, N'sys', CAST(N'2019-01-25T19:00:48.453' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.453' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30970, N'sys', CAST(N'2019-01-25T19:00:48.453' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.453' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30971, N'sys', CAST(N'2019-01-25T19:00:48.453' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.453' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30972, N'sys', CAST(N'2019-01-25T19:00:48.457' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.457' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30973, N'sys', CAST(N'2019-01-25T19:00:48.457' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.457' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30974, N'sys', CAST(N'2019-01-25T19:00:48.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30975, N'sys', CAST(N'2019-01-25T19:00:48.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30976, N'sys', CAST(N'2019-01-25T19:00:48.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30977, N'sys', CAST(N'2019-01-25T19:00:48.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30978, N'sys', CAST(N'2019-01-25T19:00:48.463' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.463' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30979, N'sys', CAST(N'2019-01-25T19:00:48.463' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.463' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30980, N'sys', CAST(N'2019-01-25T19:00:48.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30981, N'sys', CAST(N'2019-01-25T19:00:48.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30982, N'sys', CAST(N'2019-01-25T19:00:48.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30983, N'sys', CAST(N'2019-01-25T19:00:48.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30984, N'sys', CAST(N'2019-01-25T19:00:48.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30985, N'sys', CAST(N'2019-01-25T19:00:48.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30986, N'sys', CAST(N'2019-01-25T19:00:48.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30987, N'sys', CAST(N'2019-01-25T19:00:48.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30988, N'sys', CAST(N'2019-01-25T19:00:48.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30989, N'sys', CAST(N'2019-01-25T19:00:48.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30990, N'sys', CAST(N'2019-01-25T19:00:48.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30991, N'sys', CAST(N'2019-01-25T19:00:48.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30992, N'sys', CAST(N'2019-01-25T19:00:48.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30993, N'sys', CAST(N'2019-01-25T19:00:48.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30994, N'sys', CAST(N'2019-01-25T19:00:48.483' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.483' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30995, N'sys', CAST(N'2019-01-25T19:00:48.483' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.483' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30996, N'sys', CAST(N'2019-01-25T19:00:48.483' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.483' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30997, N'sys', CAST(N'2019-01-25T19:00:48.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30998, N'sys', CAST(N'2019-01-25T19:00:48.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (30999, N'sys', CAST(N'2019-01-25T19:00:48.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31000, N'sys', CAST(N'2019-01-25T19:00:48.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31001, N'sys', CAST(N'2019-01-25T19:00:48.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31002, N'sys', CAST(N'2019-01-25T19:00:48.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31003, N'sys', CAST(N'2019-01-25T19:00:48.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31004, N'sys', CAST(N'2019-01-25T19:00:48.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31005, N'sys', CAST(N'2019-01-25T19:00:48.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31006, N'sys', CAST(N'2019-01-25T19:00:48.497' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.497' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31007, N'sys', CAST(N'2019-01-25T19:00:48.497' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.497' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31008, N'sys', CAST(N'2019-01-25T19:00:48.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31009, N'sys', CAST(N'2019-01-25T19:00:48.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31010, N'sys', CAST(N'2019-01-25T19:00:48.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31011, N'sys', CAST(N'2019-01-25T19:00:48.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31012, N'sys', CAST(N'2019-01-25T19:00:48.503' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.503' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31013, N'sys', CAST(N'2019-01-25T19:00:48.503' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.503' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31014, N'sys', CAST(N'2019-01-25T19:00:48.507' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.507' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31015, N'sys', CAST(N'2019-01-25T19:00:48.507' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.507' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31016, N'sys', CAST(N'2019-01-25T19:00:48.507' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.507' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31017, N'sys', CAST(N'2019-01-25T19:00:48.510' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.510' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31018, N'sys', CAST(N'2019-01-25T19:00:48.510' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.510' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31019, N'sys', CAST(N'2019-01-25T19:00:48.510' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.510' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31020, N'sys', CAST(N'2019-01-25T19:00:48.513' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.513' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31021, N'sys', CAST(N'2019-01-25T19:00:48.513' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.513' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31022, N'sys', CAST(N'2019-01-25T19:00:48.513' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.513' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31023, N'sys', CAST(N'2019-01-25T19:00:48.517' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.517' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31024, N'sys', CAST(N'2019-01-25T19:00:48.517' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.517' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31025, N'sys', CAST(N'2019-01-25T19:00:48.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31026, N'sys', CAST(N'2019-01-25T19:00:48.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31027, N'sys', CAST(N'2019-01-25T19:00:48.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31028, N'sys', CAST(N'2019-01-25T19:00:48.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31029, N'sys', CAST(N'2019-01-25T19:00:48.523' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.523' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31030, N'sys', CAST(N'2019-01-25T19:00:48.523' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.523' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31031, N'sys', CAST(N'2019-01-25T19:00:48.527' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.527' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31032, N'sys', CAST(N'2019-01-25T19:00:48.527' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.527' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31033, N'sys', CAST(N'2019-01-25T19:00:48.527' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.527' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31034, N'sys', CAST(N'2019-01-25T19:00:48.530' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.530' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31035, N'sys', CAST(N'2019-01-25T19:00:48.530' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.530' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31036, N'sys', CAST(N'2019-01-25T19:00:48.530' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.530' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31037, N'sys', CAST(N'2019-01-25T19:00:48.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31038, N'sys', CAST(N'2019-01-25T19:00:48.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31039, N'sys', CAST(N'2019-01-25T19:00:48.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31040, N'sys', CAST(N'2019-01-25T19:00:48.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31041, N'sys', CAST(N'2019-01-25T19:00:48.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31042, N'sys', CAST(N'2019-01-25T19:00:48.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31043, N'sys', CAST(N'2019-01-25T19:00:48.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31044, N'sys', CAST(N'2019-01-25T19:00:48.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31045, N'sys', CAST(N'2019-01-25T19:00:48.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31046, N'sys', CAST(N'2019-01-25T19:00:48.543' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.543' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31047, N'sys', CAST(N'2019-01-25T19:00:48.543' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.543' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31048, N'sys', CAST(N'2019-01-25T19:00:48.543' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.543' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31049, N'sys', CAST(N'2019-01-25T19:00:48.547' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.547' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31050, N'sys', CAST(N'2019-01-25T19:00:48.547' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.547' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31051, N'sys', CAST(N'2019-01-25T19:00:48.550' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.550' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31052, N'sys', CAST(N'2019-01-25T19:00:48.550' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.550' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31053, N'sys', CAST(N'2019-01-25T19:00:48.550' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.550' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31054, N'sys', CAST(N'2019-01-25T19:00:48.550' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.550' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31055, N'sys', CAST(N'2019-01-25T19:00:48.553' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.553' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31056, N'sys', CAST(N'2019-01-25T19:00:48.553' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.553' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31057, N'sys', CAST(N'2019-01-25T19:00:48.557' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.557' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31058, N'sys', CAST(N'2019-01-25T19:00:48.557' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.557' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31059, N'sys', CAST(N'2019-01-25T19:00:48.557' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.557' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31060, N'sys', CAST(N'2019-01-25T19:00:48.560' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.560' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31061, N'sys', CAST(N'2019-01-25T19:00:48.560' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.560' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31062, N'sys', CAST(N'2019-01-25T19:00:48.560' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.560' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31063, N'sys', CAST(N'2019-01-25T19:00:48.563' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.563' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31064, N'sys', CAST(N'2019-01-25T19:00:48.563' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.563' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31065, N'sys', CAST(N'2019-01-25T19:00:48.567' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.567' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31066, N'sys', CAST(N'2019-01-25T19:00:48.567' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.567' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31067, N'sys', CAST(N'2019-01-25T19:00:48.567' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.567' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31068, N'sys', CAST(N'2019-01-25T19:00:48.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31069, N'sys', CAST(N'2019-01-25T19:00:48.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31070, N'sys', CAST(N'2019-01-25T19:00:48.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31071, N'sys', CAST(N'2019-01-25T19:00:48.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31072, N'sys', CAST(N'2019-01-25T19:00:48.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31073, N'sys', CAST(N'2019-01-25T19:00:48.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31074, N'sys', CAST(N'2019-01-25T19:00:48.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31075, N'sys', CAST(N'2019-01-25T19:00:48.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31076, N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31077, N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31078, N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31079, N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31080, N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31081, N'sys', CAST(N'2019-01-25T19:00:48.583' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.583' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31082, N'sys', CAST(N'2019-01-25T19:00:48.587' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.587' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31083, N'sys', CAST(N'2019-01-25T19:00:48.587' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.587' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31084, N'sys', CAST(N'2019-01-25T19:00:48.587' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.587' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31085, N'sys', CAST(N'2019-01-25T19:00:48.590' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.590' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31086, N'sys', CAST(N'2019-01-25T19:00:48.590' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.590' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31087, N'sys', CAST(N'2019-01-25T19:00:48.590' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.590' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31088, N'sys', CAST(N'2019-01-25T19:00:48.590' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.590' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31089, N'sys', CAST(N'2019-01-25T19:00:48.593' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.593' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31090, N'sys', CAST(N'2019-01-25T19:00:48.593' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.593' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31091, N'sys', CAST(N'2019-01-25T19:00:48.593' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.593' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31092, N'sys', CAST(N'2019-01-25T19:00:48.597' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.597' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31093, N'sys', CAST(N'2019-01-25T19:00:48.597' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.597' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31094, N'sys', CAST(N'2019-01-25T19:00:48.600' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.600' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31095, N'sys', CAST(N'2019-01-25T19:00:48.600' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.600' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31096, N'sys', CAST(N'2019-01-25T19:00:48.600' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.600' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31097, N'sys', CAST(N'2019-01-25T19:00:48.603' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.603' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31098, N'sys', CAST(N'2019-01-25T19:00:48.603' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.603' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31099, N'sys', CAST(N'2019-01-25T19:00:48.603' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.603' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31100, N'sys', CAST(N'2019-01-25T19:00:48.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31101, N'sys', CAST(N'2019-01-25T19:00:48.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31102, N'sys', CAST(N'2019-01-25T19:00:48.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31103, N'sys', CAST(N'2019-01-25T19:00:48.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31104, N'sys', CAST(N'2019-01-25T19:00:48.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31105, N'sys', CAST(N'2019-01-25T19:00:48.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31106, N'sys', CAST(N'2019-01-25T19:00:48.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31107, N'sys', CAST(N'2019-01-25T19:00:48.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31108, N'sys', CAST(N'2019-01-25T19:00:48.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31109, N'sys', CAST(N'2019-01-25T19:00:48.617' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.617' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31110, N'sys', CAST(N'2019-01-25T19:00:48.617' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.617' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31111, N'sys', CAST(N'2019-01-25T19:00:48.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31112, N'sys', CAST(N'2019-01-25T19:00:48.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31113, N'sys', CAST(N'2019-01-25T19:00:48.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31114, N'sys', CAST(N'2019-01-25T19:00:48.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31115, N'sys', CAST(N'2019-01-25T19:00:48.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:00:48.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31116, N'sys', CAST(N'2019-01-25T19:01:13.113' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.113' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31117, N'sys', CAST(N'2019-01-25T19:01:13.117' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.117' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31118, N'sys', CAST(N'2019-01-25T19:01:13.117' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.117' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31119, N'sys', CAST(N'2019-01-25T19:01:13.117' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.117' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31120, N'sys', CAST(N'2019-01-25T19:01:13.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31121, N'sys', CAST(N'2019-01-25T19:01:13.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31122, N'sys', CAST(N'2019-01-25T19:01:13.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31123, N'sys', CAST(N'2019-01-25T19:01:13.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31124, N'sys', CAST(N'2019-01-25T19:01:13.123' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.123' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31125, N'sys', CAST(N'2019-01-25T19:01:13.123' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.123' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31126, N'sys', CAST(N'2019-01-25T19:01:13.123' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.123' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31127, N'sys', CAST(N'2019-01-25T19:01:13.127' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.127' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31128, N'sys', CAST(N'2019-01-25T19:01:13.127' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.127' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31129, N'sys', CAST(N'2019-01-25T19:01:13.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31130, N'sys', CAST(N'2019-01-25T19:01:13.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31131, N'sys', CAST(N'2019-01-25T19:01:13.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31132, N'sys', CAST(N'2019-01-25T19:01:13.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31133, N'sys', CAST(N'2019-01-25T19:01:13.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31134, N'sys', CAST(N'2019-01-25T19:01:13.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31135, N'sys', CAST(N'2019-01-25T19:01:13.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31136, N'sys', CAST(N'2019-01-25T19:01:13.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31137, N'sys', CAST(N'2019-01-25T19:01:13.140' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.140' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31138, N'sys', CAST(N'2019-01-25T19:01:13.140' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.140' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31139, N'sys', CAST(N'2019-01-25T19:01:13.143' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.143' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31140, N'sys', CAST(N'2019-01-25T19:01:13.143' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.143' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31141, N'sys', CAST(N'2019-01-25T19:01:13.147' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.147' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31142, N'sys', CAST(N'2019-01-25T19:01:13.147' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.147' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31143, N'sys', CAST(N'2019-01-25T19:01:13.147' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.147' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31144, N'sys', CAST(N'2019-01-25T19:01:13.150' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.150' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31145, N'sys', CAST(N'2019-01-25T19:01:13.150' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.150' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31146, N'sys', CAST(N'2019-01-25T19:01:13.153' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.153' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31147, N'sys', CAST(N'2019-01-25T19:01:13.153' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.153' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31148, N'sys', CAST(N'2019-01-25T19:01:13.153' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.153' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31149, N'sys', CAST(N'2019-01-25T19:01:13.157' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.157' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31150, N'sys', CAST(N'2019-01-25T19:01:13.157' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.157' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31151, N'sys', CAST(N'2019-01-25T19:01:13.160' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.160' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31152, N'sys', CAST(N'2019-01-25T19:01:13.160' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.160' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31153, N'sys', CAST(N'2019-01-25T19:01:13.160' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.160' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31154, N'sys', CAST(N'2019-01-25T19:01:13.163' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.163' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31155, N'sys', CAST(N'2019-01-25T19:01:13.163' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.163' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31156, N'sys', CAST(N'2019-01-25T19:01:13.167' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.167' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31157, N'sys', CAST(N'2019-01-25T19:01:13.167' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.167' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31158, N'sys', CAST(N'2019-01-25T19:01:13.170' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.170' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31159, N'sys', CAST(N'2019-01-25T19:01:13.170' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.170' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31160, N'sys', CAST(N'2019-01-25T19:01:13.170' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.170' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31161, N'sys', CAST(N'2019-01-25T19:01:13.173' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.173' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31162, N'sys', CAST(N'2019-01-25T19:01:13.173' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.173' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31163, N'sys', CAST(N'2019-01-25T19:01:13.177' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.177' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31164, N'sys', CAST(N'2019-01-25T19:01:13.177' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.177' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31165, N'sys', CAST(N'2019-01-25T19:01:13.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31166, N'sys', CAST(N'2019-01-25T19:01:13.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31167, N'sys', CAST(N'2019-01-25T19:01:13.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31168, N'sys', CAST(N'2019-01-25T19:01:13.183' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.183' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31169, N'sys', CAST(N'2019-01-25T19:01:13.183' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.183' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31170, N'sys', CAST(N'2019-01-25T19:01:13.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31171, N'sys', CAST(N'2019-01-25T19:01:13.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31172, N'sys', CAST(N'2019-01-25T19:01:13.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31173, N'sys', CAST(N'2019-01-25T19:01:13.190' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.190' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31174, N'sys', CAST(N'2019-01-25T19:01:13.190' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.190' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31175, N'sys', CAST(N'2019-01-25T19:01:13.193' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.193' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31176, N'sys', CAST(N'2019-01-25T19:01:13.193' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.193' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31177, N'sys', CAST(N'2019-01-25T19:01:13.197' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.197' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31178, N'sys', CAST(N'2019-01-25T19:01:13.197' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.197' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31179, N'sys', CAST(N'2019-01-25T19:01:13.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31180, N'sys', CAST(N'2019-01-25T19:01:13.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31181, N'sys', CAST(N'2019-01-25T19:01:13.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31182, N'sys', CAST(N'2019-01-25T19:01:13.203' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.203' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31183, N'sys', CAST(N'2019-01-25T19:01:13.203' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.203' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31184, N'sys', CAST(N'2019-01-25T19:01:13.203' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.203' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31185, N'sys', CAST(N'2019-01-25T19:01:13.207' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.207' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31186, N'sys', CAST(N'2019-01-25T19:01:13.210' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.210' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31187, N'sys', CAST(N'2019-01-25T19:01:13.210' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.210' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31188, N'sys', CAST(N'2019-01-25T19:01:13.210' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.210' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31189, N'sys', CAST(N'2019-01-25T19:01:13.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31190, N'sys', CAST(N'2019-01-25T19:01:13.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31191, N'sys', CAST(N'2019-01-25T19:01:13.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31192, N'sys', CAST(N'2019-01-25T19:01:13.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31193, N'sys', CAST(N'2019-01-25T19:01:13.217' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.217' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31194, N'sys', CAST(N'2019-01-25T19:01:13.217' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.217' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31195, N'sys', CAST(N'2019-01-25T19:01:13.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31196, N'sys', CAST(N'2019-01-25T19:01:13.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31197, N'sys', CAST(N'2019-01-25T19:01:13.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31198, N'sys', CAST(N'2019-01-25T19:01:13.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31199, N'sys', CAST(N'2019-01-25T19:01:13.223' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.223' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31200, N'sys', CAST(N'2019-01-25T19:01:13.223' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.223' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31201, N'sys', CAST(N'2019-01-25T19:01:13.223' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.223' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31202, N'sys', CAST(N'2019-01-25T19:01:13.227' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.227' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31203, N'sys', CAST(N'2019-01-25T19:01:13.227' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.227' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31204, N'sys', CAST(N'2019-01-25T19:01:13.227' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.227' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31205, N'sys', CAST(N'2019-01-25T19:01:13.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31206, N'sys', CAST(N'2019-01-25T19:01:13.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31207, N'sys', CAST(N'2019-01-25T19:01:13.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31208, N'sys', CAST(N'2019-01-25T19:01:13.233' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.233' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31209, N'sys', CAST(N'2019-01-25T19:01:13.233' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.233' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31210, N'sys', CAST(N'2019-01-25T19:01:13.233' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.233' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31211, N'sys', CAST(N'2019-01-25T19:01:13.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31212, N'sys', CAST(N'2019-01-25T19:01:13.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31213, N'sys', CAST(N'2019-01-25T19:01:13.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31214, N'sys', CAST(N'2019-01-25T19:01:13.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31215, N'sys', CAST(N'2019-01-25T19:01:13.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31216, N'sys', CAST(N'2019-01-25T19:01:13.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31217, N'sys', CAST(N'2019-01-25T19:01:13.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31218, N'sys', CAST(N'2019-01-25T19:01:13.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31219, N'sys', CAST(N'2019-01-25T19:01:13.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31220, N'sys', CAST(N'2019-01-25T19:01:13.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31221, N'sys', CAST(N'2019-01-25T19:01:13.247' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.247' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31222, N'sys', CAST(N'2019-01-25T19:01:13.247' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.247' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31223, N'sys', CAST(N'2019-01-25T19:01:13.247' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.247' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31224, N'sys', CAST(N'2019-01-25T19:01:13.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31225, N'sys', CAST(N'2019-01-25T19:01:13.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31226, N'sys', CAST(N'2019-01-25T19:01:13.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31227, N'sys', CAST(N'2019-01-25T19:01:13.253' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.253' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31228, N'sys', CAST(N'2019-01-25T19:01:13.253' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.253' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31229, N'sys', CAST(N'2019-01-25T19:01:13.253' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.253' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31230, N'sys', CAST(N'2019-01-25T19:01:13.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31231, N'sys', CAST(N'2019-01-25T19:01:13.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31232, N'sys', CAST(N'2019-01-25T19:01:13.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31233, N'sys', CAST(N'2019-01-25T19:01:13.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31234, N'sys', CAST(N'2019-01-25T19:01:13.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31235, N'sys', CAST(N'2019-01-25T19:01:13.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31236, N'sys', CAST(N'2019-01-25T19:01:13.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31237, N'sys', CAST(N'2019-01-25T19:01:13.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31238, N'sys', CAST(N'2019-01-25T19:01:13.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31239, N'sys', CAST(N'2019-01-25T19:01:13.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31240, N'sys', CAST(N'2019-01-25T19:01:13.267' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.267' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31241, N'sys', CAST(N'2019-01-25T19:01:13.267' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.267' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31242, N'sys', CAST(N'2019-01-25T19:01:13.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31243, N'sys', CAST(N'2019-01-25T19:01:13.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31244, N'sys', CAST(N'2019-01-25T19:01:13.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31245, N'sys', CAST(N'2019-01-25T19:01:13.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31246, N'sys', CAST(N'2019-01-25T19:01:13.273' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.273' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31247, N'sys', CAST(N'2019-01-25T19:01:13.273' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.273' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31248, N'sys', CAST(N'2019-01-25T19:01:13.273' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.273' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31249, N'sys', CAST(N'2019-01-25T19:01:13.277' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.277' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31250, N'sys', CAST(N'2019-01-25T19:01:13.347' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.347' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31251, N'sys', CAST(N'2019-01-25T19:01:13.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31252, N'sys', CAST(N'2019-01-25T19:01:13.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31253, N'sys', CAST(N'2019-01-25T19:01:13.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31254, N'sys', CAST(N'2019-01-25T19:01:13.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31255, N'sys', CAST(N'2019-01-25T19:01:13.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31256, N'sys', CAST(N'2019-01-25T19:01:13.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31257, N'sys', CAST(N'2019-01-25T19:01:13.357' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.357' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31258, N'sys', CAST(N'2019-01-25T19:01:13.357' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.357' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31259, N'sys', CAST(N'2019-01-25T19:01:13.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31260, N'sys', CAST(N'2019-01-25T19:01:13.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31261, N'sys', CAST(N'2019-01-25T19:01:13.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31262, N'sys', CAST(N'2019-01-25T19:01:13.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31263, N'sys', CAST(N'2019-01-25T19:01:13.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31264, N'sys', CAST(N'2019-01-25T19:01:13.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31265, N'sys', CAST(N'2019-01-25T19:01:13.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31266, N'sys', CAST(N'2019-01-25T19:01:13.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31267, N'sys', CAST(N'2019-01-25T19:01:13.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31268, N'sys', CAST(N'2019-01-25T19:01:13.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31269, N'sys', CAST(N'2019-01-25T19:01:13.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31270, N'sys', CAST(N'2019-01-25T19:01:13.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31271, N'sys', CAST(N'2019-01-25T19:01:13.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31272, N'sys', CAST(N'2019-01-25T19:01:13.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31273, N'sys', CAST(N'2019-01-25T19:01:13.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31274, N'sys', CAST(N'2019-01-25T19:01:13.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31275, N'sys', CAST(N'2019-01-25T19:01:13.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31276, N'sys', CAST(N'2019-01-25T19:01:13.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31277, N'sys', CAST(N'2019-01-25T19:01:13.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31278, N'sys', CAST(N'2019-01-25T19:01:13.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31279, N'sys', CAST(N'2019-01-25T19:01:13.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31280, N'sys', CAST(N'2019-01-25T19:01:13.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31281, N'sys', CAST(N'2019-01-25T19:01:13.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31282, N'sys', CAST(N'2019-01-25T19:01:13.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31283, N'sys', CAST(N'2019-01-25T19:01:13.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31284, N'sys', CAST(N'2019-01-25T19:01:13.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31285, N'sys', CAST(N'2019-01-25T19:01:13.387' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.387' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31286, N'sys', CAST(N'2019-01-25T19:01:13.387' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.387' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31287, N'sys', CAST(N'2019-01-25T19:01:13.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31288, N'sys', CAST(N'2019-01-25T19:01:13.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31289, N'sys', CAST(N'2019-01-25T19:01:13.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31290, N'sys', CAST(N'2019-01-25T19:01:13.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31291, N'sys', CAST(N'2019-01-25T19:01:13.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31292, N'sys', CAST(N'2019-01-25T19:01:13.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31293, N'sys', CAST(N'2019-01-25T19:01:13.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31294, N'sys', CAST(N'2019-01-25T19:01:13.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31295, N'sys', CAST(N'2019-01-25T19:01:13.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31296, N'sys', CAST(N'2019-01-25T19:01:13.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31297, N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31298, N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31299, N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31300, N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31301, N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31302, N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31303, N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31304, N'sys', CAST(N'2019-01-25T19:01:13.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31305, N'sys', CAST(N'2019-01-25T19:01:13.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31306, N'sys', CAST(N'2019-01-25T19:01:13.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31307, N'sys', CAST(N'2019-01-25T19:01:13.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31308, N'sys', CAST(N'2019-01-25T19:01:13.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31309, N'sys', CAST(N'2019-01-25T19:01:13.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31310, N'sys', CAST(N'2019-01-25T19:01:13.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31311, N'sys', CAST(N'2019-01-25T19:01:13.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31312, N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31313, N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31314, N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31315, N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31316, N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31317, N'sys', CAST(N'2019-01-25T19:01:13.483' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.483' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31318, N'sys', CAST(N'2019-01-25T19:01:13.483' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.483' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31319, N'sys', CAST(N'2019-01-25T19:01:13.483' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.483' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31320, N'sys', CAST(N'2019-01-25T19:01:13.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31321, N'sys', CAST(N'2019-01-25T19:01:13.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31322, N'sys', CAST(N'2019-01-25T19:01:13.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31323, N'sys', CAST(N'2019-01-25T19:01:13.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31324, N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31325, N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31326, N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31327, N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31328, N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31329, N'sys', CAST(N'2019-01-25T19:01:13.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31330, N'sys', CAST(N'2019-01-25T19:01:13.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31331, N'sys', CAST(N'2019-01-25T19:01:13.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31332, N'sys', CAST(N'2019-01-25T19:01:13.497' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.497' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31333, N'sys', CAST(N'2019-01-25T19:01:13.497' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.497' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31334, N'sys', CAST(N'2019-01-25T19:01:13.497' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.497' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31335, N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31336, N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31337, N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31338, N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31339, N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31340, N'sys', CAST(N'2019-01-25T19:01:13.603' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.603' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31341, N'sys', CAST(N'2019-01-25T19:01:13.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31342, N'sys', CAST(N'2019-01-25T19:01:13.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31343, N'sys', CAST(N'2019-01-25T19:01:13.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31344, N'sys', CAST(N'2019-01-25T19:01:13.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31345, N'sys', CAST(N'2019-01-25T19:01:13.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31346, N'sys', CAST(N'2019-01-25T19:01:13.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31347, N'sys', CAST(N'2019-01-25T19:01:13.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31348, N'sys', CAST(N'2019-01-25T19:01:13.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31349, N'sys', CAST(N'2019-01-25T19:01:13.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31350, N'sys', CAST(N'2019-01-25T19:01:13.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31351, N'sys', CAST(N'2019-01-25T19:01:13.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31352, N'sys', CAST(N'2019-01-25T19:01:13.617' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.617' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31353, N'sys', CAST(N'2019-01-25T19:01:13.617' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.617' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31354, N'sys', CAST(N'2019-01-25T19:01:13.617' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.617' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31355, N'sys', CAST(N'2019-01-25T19:01:13.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31356, N'sys', CAST(N'2019-01-25T19:01:13.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31357, N'sys', CAST(N'2019-01-25T19:01:13.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31358, N'sys', CAST(N'2019-01-25T19:01:13.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31359, N'sys', CAST(N'2019-01-25T19:01:13.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31360, N'sys', CAST(N'2019-01-25T19:01:13.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31361, N'sys', CAST(N'2019-01-25T19:01:13.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31362, N'sys', CAST(N'2019-01-25T19:01:13.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31363, N'sys', CAST(N'2019-01-25T19:01:13.627' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.627' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31364, N'sys', CAST(N'2019-01-25T19:01:13.627' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.627' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31365, N'sys', CAST(N'2019-01-25T19:01:13.627' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.627' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31366, N'sys', CAST(N'2019-01-25T19:01:13.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31367, N'sys', CAST(N'2019-01-25T19:01:13.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31368, N'sys', CAST(N'2019-01-25T19:01:13.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31369, N'sys', CAST(N'2019-01-25T19:01:13.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31370, N'sys', CAST(N'2019-01-25T19:01:13.633' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.633' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31371, N'sys', CAST(N'2019-01-25T19:01:13.633' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.633' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31372, N'sys', CAST(N'2019-01-25T19:01:13.633' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.633' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31373, N'sys', CAST(N'2019-01-25T19:01:13.637' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.637' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31374, N'sys', CAST(N'2019-01-25T19:01:13.637' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.637' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31375, N'sys', CAST(N'2019-01-25T19:01:13.637' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.637' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31376, N'sys', CAST(N'2019-01-25T19:01:13.637' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.637' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31377, N'sys', CAST(N'2019-01-25T19:01:13.640' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.640' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31378, N'sys', CAST(N'2019-01-25T19:01:13.640' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.640' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31379, N'sys', CAST(N'2019-01-25T19:01:13.640' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.640' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31380, N'sys', CAST(N'2019-01-25T19:01:13.640' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.640' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31381, N'sys', CAST(N'2019-01-25T19:01:13.643' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.643' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31382, N'sys', CAST(N'2019-01-25T19:01:13.643' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.643' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31383, N'sys', CAST(N'2019-01-25T19:01:13.647' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31384, N'sys', CAST(N'2019-01-25T19:01:13.647' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31385, N'sys', CAST(N'2019-01-25T19:01:13.710' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.710' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31386, N'sys', CAST(N'2019-01-25T19:01:13.710' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.710' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31387, N'sys', CAST(N'2019-01-25T19:01:13.710' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.710' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31388, N'sys', CAST(N'2019-01-25T19:01:13.713' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.713' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31389, N'sys', CAST(N'2019-01-25T19:01:13.713' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.713' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31390, N'sys', CAST(N'2019-01-25T19:01:13.713' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.713' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31391, N'sys', CAST(N'2019-01-25T19:01:13.713' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.713' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31392, N'sys', CAST(N'2019-01-25T19:01:13.717' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.717' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31393, N'sys', CAST(N'2019-01-25T19:01:13.717' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.717' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31394, N'sys', CAST(N'2019-01-25T19:01:13.717' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.717' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31395, N'sys', CAST(N'2019-01-25T19:01:13.717' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.717' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31396, N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31397, N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31398, N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31399, N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31400, N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.720' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31401, N'sys', CAST(N'2019-01-25T19:01:13.723' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.723' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31402, N'sys', CAST(N'2019-01-25T19:01:13.723' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.723' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31403, N'sys', CAST(N'2019-01-25T19:01:13.723' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.723' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31404, N'sys', CAST(N'2019-01-25T19:01:13.723' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.723' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31405, N'sys', CAST(N'2019-01-25T19:01:13.727' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.727' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31406, N'sys', CAST(N'2019-01-25T19:01:13.727' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.727' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31407, N'sys', CAST(N'2019-01-25T19:01:13.727' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.727' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31408, N'sys', CAST(N'2019-01-25T19:01:13.727' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.727' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31409, N'sys', CAST(N'2019-01-25T19:01:13.730' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.730' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31410, N'sys', CAST(N'2019-01-25T19:01:13.730' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.730' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31411, N'sys', CAST(N'2019-01-25T19:01:13.730' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.730' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31412, N'sys', CAST(N'2019-01-25T19:01:13.730' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.730' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31413, N'sys', CAST(N'2019-01-25T19:01:13.733' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.733' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31414, N'sys', CAST(N'2019-01-25T19:01:13.733' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.733' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31415, N'sys', CAST(N'2019-01-25T19:01:13.733' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.733' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31416, N'sys', CAST(N'2019-01-25T19:01:13.737' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.737' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31417, N'sys', CAST(N'2019-01-25T19:01:13.737' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.737' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31418, N'sys', CAST(N'2019-01-25T19:01:13.737' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.737' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31419, N'sys', CAST(N'2019-01-25T19:01:13.740' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.740' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31420, N'sys', CAST(N'2019-01-25T19:01:13.740' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.740' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31421, N'sys', CAST(N'2019-01-25T19:01:13.740' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.740' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31422, N'sys', CAST(N'2019-01-25T19:01:13.743' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.743' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31423, N'sys', CAST(N'2019-01-25T19:01:13.743' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.743' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31424, N'sys', CAST(N'2019-01-25T19:01:13.743' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.743' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31425, N'sys', CAST(N'2019-01-25T19:01:13.747' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.747' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31426, N'sys', CAST(N'2019-01-25T19:01:13.747' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.747' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31427, N'sys', CAST(N'2019-01-25T19:01:13.747' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.747' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31428, N'sys', CAST(N'2019-01-25T19:01:13.750' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.750' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31429, N'sys', CAST(N'2019-01-25T19:01:13.750' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.750' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31430, N'sys', CAST(N'2019-01-25T19:01:13.890' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.890' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31431, N'sys', CAST(N'2019-01-25T19:01:13.893' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.893' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31432, N'sys', CAST(N'2019-01-25T19:01:13.893' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.893' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31433, N'sys', CAST(N'2019-01-25T19:01:13.897' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.897' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31434, N'sys', CAST(N'2019-01-25T19:01:13.897' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.897' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31435, N'sys', CAST(N'2019-01-25T19:01:13.900' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.900' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31436, N'sys', CAST(N'2019-01-25T19:01:13.900' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.900' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31437, N'sys', CAST(N'2019-01-25T19:01:13.900' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.900' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31438, N'sys', CAST(N'2019-01-25T19:01:13.903' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.903' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31439, N'sys', CAST(N'2019-01-25T19:01:13.903' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.903' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31440, N'sys', CAST(N'2019-01-25T19:01:13.907' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.907' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31441, N'sys', CAST(N'2019-01-25T19:01:13.907' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.907' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31442, N'sys', CAST(N'2019-01-25T19:01:13.910' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.910' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31443, N'sys', CAST(N'2019-01-25T19:01:13.910' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.910' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31444, N'sys', CAST(N'2019-01-25T19:01:13.910' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.910' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31445, N'sys', CAST(N'2019-01-25T19:01:13.913' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.913' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31446, N'sys', CAST(N'2019-01-25T19:01:13.913' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.913' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31447, N'sys', CAST(N'2019-01-25T19:01:13.913' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.913' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31448, N'sys', CAST(N'2019-01-25T19:01:13.917' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.917' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31449, N'sys', CAST(N'2019-01-25T19:01:13.917' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.917' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31450, N'sys', CAST(N'2019-01-25T19:01:13.920' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.920' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31451, N'sys', CAST(N'2019-01-25T19:01:13.920' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.920' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31452, N'sys', CAST(N'2019-01-25T19:01:13.920' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.920' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31453, N'sys', CAST(N'2019-01-25T19:01:13.923' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.923' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31454, N'sys', CAST(N'2019-01-25T19:01:13.923' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.923' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31455, N'sys', CAST(N'2019-01-25T19:01:13.927' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.927' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31456, N'sys', CAST(N'2019-01-25T19:01:13.927' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.927' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31457, N'sys', CAST(N'2019-01-25T19:01:13.930' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.930' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31458, N'sys', CAST(N'2019-01-25T19:01:13.930' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.930' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31459, N'sys', CAST(N'2019-01-25T19:01:13.930' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.930' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31460, N'sys', CAST(N'2019-01-25T19:01:13.933' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.933' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31461, N'sys', CAST(N'2019-01-25T19:01:13.933' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.933' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31462, N'sys', CAST(N'2019-01-25T19:01:13.937' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.937' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31463, N'sys', CAST(N'2019-01-25T19:01:13.937' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.937' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31464, N'sys', CAST(N'2019-01-25T19:01:13.940' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.940' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31465, N'sys', CAST(N'2019-01-25T19:01:13.940' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.940' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31466, N'sys', CAST(N'2019-01-25T19:01:13.940' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.940' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31467, N'sys', CAST(N'2019-01-25T19:01:13.943' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.943' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31468, N'sys', CAST(N'2019-01-25T19:01:13.943' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.943' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31469, N'sys', CAST(N'2019-01-25T19:01:13.943' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.943' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31470, N'sys', CAST(N'2019-01-25T19:01:13.947' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.947' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31471, N'sys', CAST(N'2019-01-25T19:01:13.947' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.947' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31472, N'sys', CAST(N'2019-01-25T19:01:13.950' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.950' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31473, N'sys', CAST(N'2019-01-25T19:01:13.950' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.950' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31474, N'sys', CAST(N'2019-01-25T19:01:13.950' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:13.950' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31475, N'sys', CAST(N'2019-01-25T19:01:14.017' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.017' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31476, N'sys', CAST(N'2019-01-25T19:01:14.017' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.017' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31477, N'sys', CAST(N'2019-01-25T19:01:14.020' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.020' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31478, N'sys', CAST(N'2019-01-25T19:01:14.020' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.020' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31479, N'sys', CAST(N'2019-01-25T19:01:14.023' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.023' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31480, N'sys', CAST(N'2019-01-25T19:01:14.023' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.023' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31481, N'sys', CAST(N'2019-01-25T19:01:14.023' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.023' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31482, N'sys', CAST(N'2019-01-25T19:01:14.027' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.027' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31483, N'sys', CAST(N'2019-01-25T19:01:14.027' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.027' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31484, N'sys', CAST(N'2019-01-25T19:01:14.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31485, N'sys', CAST(N'2019-01-25T19:01:14.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31486, N'sys', CAST(N'2019-01-25T19:01:14.030' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.030' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31487, N'sys', CAST(N'2019-01-25T19:01:14.033' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.033' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31488, N'sys', CAST(N'2019-01-25T19:01:14.033' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.033' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31489, N'sys', CAST(N'2019-01-25T19:01:14.037' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.037' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31490, N'sys', CAST(N'2019-01-25T19:01:14.037' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.037' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31491, N'sys', CAST(N'2019-01-25T19:01:14.040' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.040' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31492, N'sys', CAST(N'2019-01-25T19:01:14.040' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.040' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31493, N'sys', CAST(N'2019-01-25T19:01:14.040' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.040' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31494, N'sys', CAST(N'2019-01-25T19:01:14.043' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.043' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31495, N'sys', CAST(N'2019-01-25T19:01:14.043' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.043' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31496, N'sys', CAST(N'2019-01-25T19:01:14.047' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.047' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31497, N'sys', CAST(N'2019-01-25T19:01:14.047' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.047' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31498, N'sys', CAST(N'2019-01-25T19:01:14.047' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.047' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31499, N'sys', CAST(N'2019-01-25T19:01:14.050' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.050' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31500, N'sys', CAST(N'2019-01-25T19:01:14.050' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.050' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31501, N'sys', CAST(N'2019-01-25T19:01:14.053' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.053' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31502, N'sys', CAST(N'2019-01-25T19:01:14.053' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.053' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31503, N'sys', CAST(N'2019-01-25T19:01:14.057' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.057' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31504, N'sys', CAST(N'2019-01-25T19:01:14.057' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.057' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31505, N'sys', CAST(N'2019-01-25T19:01:14.057' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.057' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31506, N'sys', CAST(N'2019-01-25T19:01:14.060' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.060' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31507, N'sys', CAST(N'2019-01-25T19:01:14.060' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.060' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31508, N'sys', CAST(N'2019-01-25T19:01:14.060' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.060' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31509, N'sys', CAST(N'2019-01-25T19:01:14.063' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.063' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31510, N'sys', CAST(N'2019-01-25T19:01:14.063' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.063' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31511, N'sys', CAST(N'2019-01-25T19:01:14.067' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.067' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31512, N'sys', CAST(N'2019-01-25T19:01:14.067' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.067' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31513, N'sys', CAST(N'2019-01-25T19:01:14.070' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.070' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31514, N'sys', CAST(N'2019-01-25T19:01:14.070' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.070' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31515, N'sys', CAST(N'2019-01-25T19:01:14.070' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.070' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31516, N'sys', CAST(N'2019-01-25T19:01:14.073' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.073' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31517, N'sys', CAST(N'2019-01-25T19:01:14.073' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.073' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31518, N'sys', CAST(N'2019-01-25T19:01:14.077' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.077' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31519, N'sys', CAST(N'2019-01-25T19:01:14.077' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.077' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31520, N'sys', CAST(N'2019-01-25T19:01:14.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31521, N'sys', CAST(N'2019-01-25T19:01:14.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31522, N'sys', CAST(N'2019-01-25T19:01:14.080' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.080' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31523, N'sys', CAST(N'2019-01-25T19:01:14.083' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.083' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31524, N'sys', CAST(N'2019-01-25T19:01:14.083' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.083' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31525, N'sys', CAST(N'2019-01-25T19:01:14.087' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.087' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31526, N'sys', CAST(N'2019-01-25T19:01:14.087' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.087' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31527, N'sys', CAST(N'2019-01-25T19:01:14.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31528, N'sys', CAST(N'2019-01-25T19:01:14.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31529, N'sys', CAST(N'2019-01-25T19:01:14.090' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.090' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31530, N'sys', CAST(N'2019-01-25T19:01:14.093' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.093' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31531, N'sys', CAST(N'2019-01-25T19:01:14.093' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.093' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31532, N'sys', CAST(N'2019-01-25T19:01:14.097' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.097' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31533, N'sys', CAST(N'2019-01-25T19:01:14.097' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.097' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31534, N'sys', CAST(N'2019-01-25T19:01:14.100' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.100' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31535, N'sys', CAST(N'2019-01-25T19:01:14.100' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.100' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31536, N'sys', CAST(N'2019-01-25T19:01:14.100' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.100' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31537, N'sys', CAST(N'2019-01-25T19:01:14.103' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.103' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31538, N'sys', CAST(N'2019-01-25T19:01:14.103' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.103' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31539, N'sys', CAST(N'2019-01-25T19:01:14.107' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.107' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31540, N'sys', CAST(N'2019-01-25T19:01:14.107' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.107' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31541, N'sys', CAST(N'2019-01-25T19:01:14.107' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.107' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31542, N'sys', CAST(N'2019-01-25T19:01:14.110' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.110' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31543, N'sys', CAST(N'2019-01-25T19:01:14.110' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.110' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31544, N'sys', CAST(N'2019-01-25T19:01:14.113' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.113' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31545, N'sys', CAST(N'2019-01-25T19:01:14.113' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.113' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31546, N'sys', CAST(N'2019-01-25T19:01:14.113' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.113' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31547, N'sys', CAST(N'2019-01-25T19:01:14.117' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.117' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31548, N'sys', CAST(N'2019-01-25T19:01:14.117' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.117' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31549, N'sys', CAST(N'2019-01-25T19:01:14.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31550, N'sys', CAST(N'2019-01-25T19:01:14.120' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.120' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31551, N'sys', CAST(N'2019-01-25T19:01:14.123' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.123' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31552, N'sys', CAST(N'2019-01-25T19:01:14.123' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.123' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31553, N'sys', CAST(N'2019-01-25T19:01:14.123' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.123' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31554, N'sys', CAST(N'2019-01-25T19:01:14.127' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.127' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31555, N'sys', CAST(N'2019-01-25T19:01:14.127' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.127' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31556, N'sys', CAST(N'2019-01-25T19:01:14.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31557, N'sys', CAST(N'2019-01-25T19:01:14.130' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.130' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31558, N'sys', CAST(N'2019-01-25T19:01:14.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31559, N'sys', CAST(N'2019-01-25T19:01:14.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31560, N'sys', CAST(N'2019-01-25T19:01:14.133' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.133' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31561, N'sys', CAST(N'2019-01-25T19:01:14.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31562, N'sys', CAST(N'2019-01-25T19:01:14.137' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.137' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31563, N'sys', CAST(N'2019-01-25T19:01:14.140' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.140' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31564, N'sys', CAST(N'2019-01-25T19:01:14.140' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.140' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31565, N'sys', CAST(N'2019-01-25T19:01:14.143' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.143' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31566, N'sys', CAST(N'2019-01-25T19:01:14.143' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.143' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31567, N'sys', CAST(N'2019-01-25T19:01:14.143' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.143' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31568, N'sys', CAST(N'2019-01-25T19:01:14.147' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.147' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31569, N'sys', CAST(N'2019-01-25T19:01:14.147' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.147' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31570, N'sys', CAST(N'2019-01-25T19:01:14.150' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.150' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31571, N'sys', CAST(N'2019-01-25T19:01:14.150' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.150' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31572, N'sys', CAST(N'2019-01-25T19:01:14.150' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.150' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31573, N'sys', CAST(N'2019-01-25T19:01:14.153' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.153' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31574, N'sys', CAST(N'2019-01-25T19:01:14.153' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.153' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31575, N'sys', CAST(N'2019-01-25T19:01:14.157' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.157' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31576, N'sys', CAST(N'2019-01-25T19:01:14.157' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.157' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31577, N'sys', CAST(N'2019-01-25T19:01:14.160' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.160' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31578, N'sys', CAST(N'2019-01-25T19:01:14.160' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.160' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31579, N'sys', CAST(N'2019-01-25T19:01:14.160' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.160' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31580, N'sys', CAST(N'2019-01-25T19:01:14.163' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.163' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31581, N'sys', CAST(N'2019-01-25T19:01:14.163' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.163' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31582, N'sys', CAST(N'2019-01-25T19:01:14.167' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.167' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31583, N'sys', CAST(N'2019-01-25T19:01:14.167' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.167' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31584, N'sys', CAST(N'2019-01-25T19:01:14.170' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.170' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31585, N'sys', CAST(N'2019-01-25T19:01:14.170' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.170' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31586, N'sys', CAST(N'2019-01-25T19:01:14.170' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.170' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31587, N'sys', CAST(N'2019-01-25T19:01:14.173' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.173' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31588, N'sys', CAST(N'2019-01-25T19:01:14.173' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.173' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31589, N'sys', CAST(N'2019-01-25T19:01:14.177' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.177' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31590, N'sys', CAST(N'2019-01-25T19:01:14.177' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.177' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31591, N'sys', CAST(N'2019-01-25T19:01:14.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31592, N'sys', CAST(N'2019-01-25T19:01:14.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31593, N'sys', CAST(N'2019-01-25T19:01:14.180' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.180' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31594, N'sys', CAST(N'2019-01-25T19:01:14.183' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.183' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31595, N'sys', CAST(N'2019-01-25T19:01:14.183' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.183' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31596, N'sys', CAST(N'2019-01-25T19:01:14.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31597, N'sys', CAST(N'2019-01-25T19:01:14.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31598, N'sys', CAST(N'2019-01-25T19:01:14.187' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.187' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31599, N'sys', CAST(N'2019-01-25T19:01:14.190' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.190' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31600, N'sys', CAST(N'2019-01-25T19:01:14.190' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.190' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31601, N'sys', CAST(N'2019-01-25T19:01:14.190' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.190' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31602, N'sys', CAST(N'2019-01-25T19:01:14.193' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.193' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31603, N'sys', CAST(N'2019-01-25T19:01:14.193' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.193' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31604, N'sys', CAST(N'2019-01-25T19:01:14.197' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.197' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31605, N'sys', CAST(N'2019-01-25T19:01:14.197' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.197' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31606, N'sys', CAST(N'2019-01-25T19:01:14.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31607, N'sys', CAST(N'2019-01-25T19:01:14.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31608, N'sys', CAST(N'2019-01-25T19:01:14.200' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.200' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31609, N'sys', CAST(N'2019-01-25T19:01:14.203' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.203' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31610, N'sys', CAST(N'2019-01-25T19:01:14.203' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.203' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31611, N'sys', CAST(N'2019-01-25T19:01:14.207' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.207' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31612, N'sys', CAST(N'2019-01-25T19:01:14.207' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.207' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31613, N'sys', CAST(N'2019-01-25T19:01:14.210' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.210' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31614, N'sys', CAST(N'2019-01-25T19:01:14.210' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.210' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31615, N'sys', CAST(N'2019-01-25T19:01:14.210' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.210' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31616, N'sys', CAST(N'2019-01-25T19:01:14.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31617, N'sys', CAST(N'2019-01-25T19:01:14.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31618, N'sys', CAST(N'2019-01-25T19:01:14.213' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.213' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31619, N'sys', CAST(N'2019-01-25T19:01:14.217' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.217' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31620, N'sys', CAST(N'2019-01-25T19:01:14.217' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.217' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31621, N'sys', CAST(N'2019-01-25T19:01:14.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31622, N'sys', CAST(N'2019-01-25T19:01:14.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31623, N'sys', CAST(N'2019-01-25T19:01:14.220' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.220' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31624, N'sys', CAST(N'2019-01-25T19:01:14.223' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.223' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31625, N'sys', CAST(N'2019-01-25T19:01:14.223' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.223' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31626, N'sys', CAST(N'2019-01-25T19:01:14.227' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.227' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31627, N'sys', CAST(N'2019-01-25T19:01:14.227' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.227' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31628, N'sys', CAST(N'2019-01-25T19:01:14.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31629, N'sys', CAST(N'2019-01-25T19:01:14.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31630, N'sys', CAST(N'2019-01-25T19:01:14.230' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.230' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31631, N'sys', CAST(N'2019-01-25T19:01:14.233' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.233' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31632, N'sys', CAST(N'2019-01-25T19:01:14.233' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.233' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31633, N'sys', CAST(N'2019-01-25T19:01:14.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31634, N'sys', CAST(N'2019-01-25T19:01:14.237' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.237' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31635, N'sys', CAST(N'2019-01-25T19:01:14.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31636, N'sys', CAST(N'2019-01-25T19:01:14.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31637, N'sys', CAST(N'2019-01-25T19:01:14.240' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.240' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31638, N'sys', CAST(N'2019-01-25T19:01:14.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31639, N'sys', CAST(N'2019-01-25T19:01:14.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31640, N'sys', CAST(N'2019-01-25T19:01:14.243' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.243' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31641, N'sys', CAST(N'2019-01-25T19:01:14.247' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.247' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31642, N'sys', CAST(N'2019-01-25T19:01:14.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31643, N'sys', CAST(N'2019-01-25T19:01:14.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31644, N'sys', CAST(N'2019-01-25T19:01:14.250' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.250' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31645, N'sys', CAST(N'2019-01-25T19:01:14.253' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.253' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31646, N'sys', CAST(N'2019-01-25T19:01:14.253' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.253' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31647, N'sys', CAST(N'2019-01-25T19:01:14.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31648, N'sys', CAST(N'2019-01-25T19:01:14.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31649, N'sys', CAST(N'2019-01-25T19:01:14.257' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.257' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31650, N'sys', CAST(N'2019-01-25T19:01:14.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31651, N'sys', CAST(N'2019-01-25T19:01:14.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31652, N'sys', CAST(N'2019-01-25T19:01:14.260' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.260' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31653, N'sys', CAST(N'2019-01-25T19:01:14.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31654, N'sys', CAST(N'2019-01-25T19:01:14.263' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.263' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31655, N'sys', CAST(N'2019-01-25T19:01:14.267' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.267' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31656, N'sys', CAST(N'2019-01-25T19:01:14.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31657, N'sys', CAST(N'2019-01-25T19:01:14.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31658, N'sys', CAST(N'2019-01-25T19:01:14.270' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.270' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31659, N'sys', CAST(N'2019-01-25T19:01:14.273' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.273' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31660, N'sys', CAST(N'2019-01-25T19:01:14.273' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.273' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31661, N'sys', CAST(N'2019-01-25T19:01:14.277' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.277' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31662, N'sys', CAST(N'2019-01-25T19:01:14.277' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.277' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31663, N'sys', CAST(N'2019-01-25T19:01:14.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31664, N'sys', CAST(N'2019-01-25T19:01:14.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31665, N'sys', CAST(N'2019-01-25T19:01:14.280' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.280' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31666, N'sys', CAST(N'2019-01-25T19:01:14.283' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.283' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31667, N'sys', CAST(N'2019-01-25T19:01:14.283' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.283' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31668, N'sys', CAST(N'2019-01-25T19:01:14.283' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.283' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31669, N'sys', CAST(N'2019-01-25T19:01:14.287' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.287' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31670, N'sys', CAST(N'2019-01-25T19:01:14.287' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.287' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31671, N'sys', CAST(N'2019-01-25T19:01:14.290' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.290' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31672, N'sys', CAST(N'2019-01-25T19:01:14.290' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.290' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31673, N'sys', CAST(N'2019-01-25T19:01:14.290' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.290' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31674, N'sys', CAST(N'2019-01-25T19:01:14.293' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.293' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31675, N'sys', CAST(N'2019-01-25T19:01:14.293' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.293' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31676, N'sys', CAST(N'2019-01-25T19:01:14.297' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.297' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31677, N'sys', CAST(N'2019-01-25T19:01:14.297' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.297' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31678, N'sys', CAST(N'2019-01-25T19:01:14.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31679, N'sys', CAST(N'2019-01-25T19:01:14.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31680, N'sys', CAST(N'2019-01-25T19:01:14.300' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.300' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31681, N'sys', CAST(N'2019-01-25T19:01:14.303' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.303' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31682, N'sys', CAST(N'2019-01-25T19:01:14.303' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.303' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31683, N'sys', CAST(N'2019-01-25T19:01:14.307' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.307' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31684, N'sys', CAST(N'2019-01-25T19:01:14.307' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.307' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31685, N'sys', CAST(N'2019-01-25T19:01:14.310' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.310' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31686, N'sys', CAST(N'2019-01-25T19:01:14.310' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.310' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31687, N'sys', CAST(N'2019-01-25T19:01:14.310' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.310' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31688, N'sys', CAST(N'2019-01-25T19:01:14.313' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.313' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31689, N'sys', CAST(N'2019-01-25T19:01:14.313' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.313' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31690, N'sys', CAST(N'2019-01-25T19:01:14.317' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.317' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31691, N'sys', CAST(N'2019-01-25T19:01:14.317' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.317' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31692, N'sys', CAST(N'2019-01-25T19:01:14.320' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.320' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31693, N'sys', CAST(N'2019-01-25T19:01:14.320' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.320' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31694, N'sys', CAST(N'2019-01-25T19:01:14.320' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.320' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31695, N'sys', CAST(N'2019-01-25T19:01:14.323' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.323' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31696, N'sys', CAST(N'2019-01-25T19:01:14.323' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.323' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31697, N'sys', CAST(N'2019-01-25T19:01:14.327' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.327' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31698, N'sys', CAST(N'2019-01-25T19:01:14.327' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.327' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31699, N'sys', CAST(N'2019-01-25T19:01:14.327' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.327' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31700, N'sys', CAST(N'2019-01-25T19:01:14.330' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.330' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31701, N'sys', CAST(N'2019-01-25T19:01:14.330' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.330' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31702, N'sys', CAST(N'2019-01-25T19:01:14.333' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.333' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31703, N'sys', CAST(N'2019-01-25T19:01:14.333' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.333' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31704, N'sys', CAST(N'2019-01-25T19:01:14.333' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.333' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31705, N'sys', CAST(N'2019-01-25T19:01:14.337' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.337' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31706, N'sys', CAST(N'2019-01-25T19:01:14.337' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.337' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31707, N'sys', CAST(N'2019-01-25T19:01:14.340' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.340' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31708, N'sys', CAST(N'2019-01-25T19:01:14.340' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.340' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31709, N'sys', CAST(N'2019-01-25T19:01:14.340' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.340' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31710, N'sys', CAST(N'2019-01-25T19:01:14.343' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.343' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31711, N'sys', CAST(N'2019-01-25T19:01:14.343' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.343' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31712, N'sys', CAST(N'2019-01-25T19:01:14.347' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.347' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31713, N'sys', CAST(N'2019-01-25T19:01:14.347' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.347' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31714, N'sys', CAST(N'2019-01-25T19:01:14.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31715, N'sys', CAST(N'2019-01-25T19:01:14.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31716, N'sys', CAST(N'2019-01-25T19:01:14.350' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.350' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31717, N'sys', CAST(N'2019-01-25T19:01:14.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31718, N'sys', CAST(N'2019-01-25T19:01:14.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31719, N'sys', CAST(N'2019-01-25T19:01:14.353' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.353' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31720, N'sys', CAST(N'2019-01-25T19:01:14.357' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.357' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31721, N'sys', CAST(N'2019-01-25T19:01:14.357' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.357' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31722, N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31723, N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31724, N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31725, N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31726, N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31727, N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.360' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31728, N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31729, N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31730, N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31731, N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31732, N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31733, N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.363' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31734, N'sys', CAST(N'2019-01-25T19:01:14.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31735, N'sys', CAST(N'2019-01-25T19:01:14.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31736, N'sys', CAST(N'2019-01-25T19:01:14.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31737, N'sys', CAST(N'2019-01-25T19:01:14.367' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.367' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31738, N'sys', CAST(N'2019-01-25T19:01:14.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31739, N'sys', CAST(N'2019-01-25T19:01:14.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31740, N'sys', CAST(N'2019-01-25T19:01:14.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31741, N'sys', CAST(N'2019-01-25T19:01:14.370' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.370' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31742, N'sys', CAST(N'2019-01-25T19:01:14.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31743, N'sys', CAST(N'2019-01-25T19:01:14.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31744, N'sys', CAST(N'2019-01-25T19:01:14.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31745, N'sys', CAST(N'2019-01-25T19:01:14.373' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.373' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31746, N'sys', CAST(N'2019-01-25T19:01:14.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31747, N'sys', CAST(N'2019-01-25T19:01:14.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31748, N'sys', CAST(N'2019-01-25T19:01:14.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31749, N'sys', CAST(N'2019-01-25T19:01:14.377' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.377' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31750, N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31751, N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31752, N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31753, N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31754, N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.380' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31755, N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31756, N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31757, N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31758, N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31759, N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.383' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31760, N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31761, N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31762, N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31763, N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31764, N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.387' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31765, N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31766, N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31767, N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31768, N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31769, N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31770, N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.390' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31771, N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31772, N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31773, N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31774, N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31775, N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31776, N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.393' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31777, N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31778, N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31779, N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31780, N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31781, N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.397' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31782, N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31783, N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31784, N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31785, N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31786, N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31787, N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.400' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31788, N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31789, N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31790, N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31791, N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31792, N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.403' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31793, N'sys', CAST(N'2019-01-25T19:01:14.407' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.407' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31794, N'sys', CAST(N'2019-01-25T19:01:14.407' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.407' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31795, N'sys', CAST(N'2019-01-25T19:01:14.407' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.407' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31796, N'sys', CAST(N'2019-01-25T19:01:14.407' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.407' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31797, N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31798, N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31799, N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31800, N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31801, N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31802, N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.410' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31803, N'sys', CAST(N'2019-01-25T19:01:14.413' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.413' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31804, N'sys', CAST(N'2019-01-25T19:01:14.413' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.413' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31805, N'sys', CAST(N'2019-01-25T19:01:14.413' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.413' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31806, N'sys', CAST(N'2019-01-25T19:01:14.413' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.413' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31807, N'sys', CAST(N'2019-01-25T19:01:14.417' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.417' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31808, N'sys', CAST(N'2019-01-25T19:01:14.417' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.417' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31809, N'sys', CAST(N'2019-01-25T19:01:14.417' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.417' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31810, N'sys', CAST(N'2019-01-25T19:01:14.417' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.417' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31811, N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31812, N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31813, N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31814, N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31815, N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31816, N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31817, N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31818, N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.420' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31819, N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31820, N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31821, N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31822, N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31823, N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.423' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31824, N'sys', CAST(N'2019-01-25T19:01:14.427' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.427' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31825, N'sys', CAST(N'2019-01-25T19:01:14.427' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.427' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31826, N'sys', CAST(N'2019-01-25T19:01:14.427' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.427' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31827, N'sys', CAST(N'2019-01-25T19:01:14.430' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.430' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31828, N'sys', CAST(N'2019-01-25T19:01:14.430' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.430' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31829, N'sys', CAST(N'2019-01-25T19:01:14.430' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.430' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31830, N'sys', CAST(N'2019-01-25T19:01:14.430' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.430' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31831, N'sys', CAST(N'2019-01-25T19:01:14.433' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.433' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31832, N'sys', CAST(N'2019-01-25T19:01:14.433' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.433' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31833, N'sys', CAST(N'2019-01-25T19:01:14.433' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.433' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31834, N'sys', CAST(N'2019-01-25T19:01:14.437' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.437' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31835, N'sys', CAST(N'2019-01-25T19:01:14.437' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.437' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31836, N'sys', CAST(N'2019-01-25T19:01:14.437' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.437' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31837, N'sys', CAST(N'2019-01-25T19:01:14.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31838, N'sys', CAST(N'2019-01-25T19:01:14.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31839, N'sys', CAST(N'2019-01-25T19:01:14.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31840, N'sys', CAST(N'2019-01-25T19:01:14.440' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.440' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31841, N'sys', CAST(N'2019-01-25T19:01:14.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31842, N'sys', CAST(N'2019-01-25T19:01:14.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31843, N'sys', CAST(N'2019-01-25T19:01:14.443' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.443' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31844, N'sys', CAST(N'2019-01-25T19:01:14.447' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.447' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31845, N'sys', CAST(N'2019-01-25T19:01:14.447' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.447' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31846, N'sys', CAST(N'2019-01-25T19:01:14.447' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.447' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31847, N'sys', CAST(N'2019-01-25T19:01:14.447' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.447' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31848, N'sys', CAST(N'2019-01-25T19:01:14.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31849, N'sys', CAST(N'2019-01-25T19:01:14.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31850, N'sys', CAST(N'2019-01-25T19:01:14.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31851, N'sys', CAST(N'2019-01-25T19:01:14.450' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.450' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31852, N'sys', CAST(N'2019-01-25T19:01:14.453' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.453' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31853, N'sys', CAST(N'2019-01-25T19:01:14.453' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.453' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31854, N'sys', CAST(N'2019-01-25T19:01:14.453' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.453' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31855, N'sys', CAST(N'2019-01-25T19:01:14.457' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.457' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31856, N'sys', CAST(N'2019-01-25T19:01:14.457' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.457' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31857, N'sys', CAST(N'2019-01-25T19:01:14.457' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.457' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31858, N'sys', CAST(N'2019-01-25T19:01:14.457' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.457' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31859, N'sys', CAST(N'2019-01-25T19:01:14.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31860, N'sys', CAST(N'2019-01-25T19:01:14.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31861, N'sys', CAST(N'2019-01-25T19:01:14.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31862, N'sys', CAST(N'2019-01-25T19:01:14.460' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.460' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31863, N'sys', CAST(N'2019-01-25T19:01:14.463' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.463' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31864, N'sys', CAST(N'2019-01-25T19:01:14.463' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.463' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31865, N'sys', CAST(N'2019-01-25T19:01:14.463' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.463' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31866, N'sys', CAST(N'2019-01-25T19:01:14.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31867, N'sys', CAST(N'2019-01-25T19:01:14.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31868, N'sys', CAST(N'2019-01-25T19:01:14.467' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.467' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31869, N'sys', CAST(N'2019-01-25T19:01:14.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31870, N'sys', CAST(N'2019-01-25T19:01:14.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31871, N'sys', CAST(N'2019-01-25T19:01:14.470' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.470' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31872, N'sys', CAST(N'2019-01-25T19:01:14.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31873, N'sys', CAST(N'2019-01-25T19:01:14.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31874, N'sys', CAST(N'2019-01-25T19:01:14.473' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.473' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31875, N'sys', CAST(N'2019-01-25T19:01:14.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31876, N'sys', CAST(N'2019-01-25T19:01:14.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31877, N'sys', CAST(N'2019-01-25T19:01:14.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31878, N'sys', CAST(N'2019-01-25T19:01:14.477' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.477' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31879, N'sys', CAST(N'2019-01-25T19:01:14.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31880, N'sys', CAST(N'2019-01-25T19:01:14.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31881, N'sys', CAST(N'2019-01-25T19:01:14.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31882, N'sys', CAST(N'2019-01-25T19:01:14.480' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.480' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31883, N'sys', CAST(N'2019-01-25T19:01:14.483' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.483' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31884, N'sys', CAST(N'2019-01-25T19:01:14.483' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.483' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31885, N'sys', CAST(N'2019-01-25T19:01:14.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31886, N'sys', CAST(N'2019-01-25T19:01:14.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31887, N'sys', CAST(N'2019-01-25T19:01:14.487' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.487' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31888, N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31889, N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31890, N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31891, N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31892, N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.490' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31893, N'sys', CAST(N'2019-01-25T19:01:14.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31894, N'sys', CAST(N'2019-01-25T19:01:14.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31895, N'sys', CAST(N'2019-01-25T19:01:14.493' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.493' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31896, N'sys', CAST(N'2019-01-25T19:01:14.497' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.497' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31897, N'sys', CAST(N'2019-01-25T19:01:14.497' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.497' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31898, N'sys', CAST(N'2019-01-25T19:01:14.497' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.497' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31899, N'sys', CAST(N'2019-01-25T19:01:14.497' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.497' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31900, N'sys', CAST(N'2019-01-25T19:01:14.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31901, N'sys', CAST(N'2019-01-25T19:01:14.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31902, N'sys', CAST(N'2019-01-25T19:01:14.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31903, N'sys', CAST(N'2019-01-25T19:01:14.500' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.500' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31904, N'sys', CAST(N'2019-01-25T19:01:14.503' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.503' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31905, N'sys', CAST(N'2019-01-25T19:01:14.503' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.503' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31906, N'sys', CAST(N'2019-01-25T19:01:14.507' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.507' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31907, N'sys', CAST(N'2019-01-25T19:01:14.507' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.507' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31908, N'sys', CAST(N'2019-01-25T19:01:14.507' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.507' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31909, N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31910, N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31911, N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31912, N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31913, N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.510' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31914, N'sys', CAST(N'2019-01-25T19:01:14.513' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.513' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31915, N'sys', CAST(N'2019-01-25T19:01:14.513' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.513' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31916, N'sys', CAST(N'2019-01-25T19:01:14.513' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.513' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31917, N'sys', CAST(N'2019-01-25T19:01:14.517' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.517' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31918, N'sys', CAST(N'2019-01-25T19:01:14.517' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.517' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31919, N'sys', CAST(N'2019-01-25T19:01:14.517' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.517' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31920, N'sys', CAST(N'2019-01-25T19:01:14.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31921, N'sys', CAST(N'2019-01-25T19:01:14.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31922, N'sys', CAST(N'2019-01-25T19:01:14.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31923, N'sys', CAST(N'2019-01-25T19:01:14.520' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.520' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31924, N'sys', CAST(N'2019-01-25T19:01:14.523' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.523' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31925, N'sys', CAST(N'2019-01-25T19:01:14.523' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.523' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31926, N'sys', CAST(N'2019-01-25T19:01:14.523' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.523' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31927, N'sys', CAST(N'2019-01-25T19:01:14.527' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.527' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31928, N'sys', CAST(N'2019-01-25T19:01:14.527' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.527' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31929, N'sys', CAST(N'2019-01-25T19:01:14.527' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.527' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31930, N'sys', CAST(N'2019-01-25T19:01:14.530' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.530' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31931, N'sys', CAST(N'2019-01-25T19:01:14.530' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.530' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31932, N'sys', CAST(N'2019-01-25T19:01:14.530' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.530' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31933, N'sys', CAST(N'2019-01-25T19:01:14.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31934, N'sys', CAST(N'2019-01-25T19:01:14.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31935, N'sys', CAST(N'2019-01-25T19:01:14.533' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.533' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31936, N'sys', CAST(N'2019-01-25T19:01:14.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31937, N'sys', CAST(N'2019-01-25T19:01:14.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31938, N'sys', CAST(N'2019-01-25T19:01:14.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31939, N'sys', CAST(N'2019-01-25T19:01:14.537' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.537' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31940, N'sys', CAST(N'2019-01-25T19:01:14.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31941, N'sys', CAST(N'2019-01-25T19:01:14.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31942, N'sys', CAST(N'2019-01-25T19:01:14.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31943, N'sys', CAST(N'2019-01-25T19:01:14.540' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.540' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31944, N'sys', CAST(N'2019-01-25T19:01:14.543' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.543' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31945, N'sys', CAST(N'2019-01-25T19:01:14.543' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.543' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31946, N'sys', CAST(N'2019-01-25T19:01:14.543' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.543' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31947, N'sys', CAST(N'2019-01-25T19:01:14.547' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.547' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31948, N'sys', CAST(N'2019-01-25T19:01:14.547' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.547' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31949, N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31950, N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31951, N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31952, N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31953, N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.550' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31954, N'sys', CAST(N'2019-01-25T19:01:14.553' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.553' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31955, N'sys', CAST(N'2019-01-25T19:01:14.553' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.553' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31956, N'sys', CAST(N'2019-01-25T19:01:14.553' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.553' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31957, N'sys', CAST(N'2019-01-25T19:01:14.557' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.557' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31958, N'sys', CAST(N'2019-01-25T19:01:14.557' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.557' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31959, N'sys', CAST(N'2019-01-25T19:01:14.557' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.557' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31960, N'sys', CAST(N'2019-01-25T19:01:14.560' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.560' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31961, N'sys', CAST(N'2019-01-25T19:01:14.560' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.560' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31962, N'sys', CAST(N'2019-01-25T19:01:14.560' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.560' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31963, N'sys', CAST(N'2019-01-25T19:01:14.563' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.563' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31964, N'sys', CAST(N'2019-01-25T19:01:14.563' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.563' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31965, N'sys', CAST(N'2019-01-25T19:01:14.563' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.563' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31966, N'sys', CAST(N'2019-01-25T19:01:14.563' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.563' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31967, N'sys', CAST(N'2019-01-25T19:01:14.567' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.567' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31968, N'sys', CAST(N'2019-01-25T19:01:14.567' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.567' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31969, N'sys', CAST(N'2019-01-25T19:01:14.567' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.567' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31970, N'sys', CAST(N'2019-01-25T19:01:14.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31971, N'sys', CAST(N'2019-01-25T19:01:14.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31972, N'sys', CAST(N'2019-01-25T19:01:14.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31973, N'sys', CAST(N'2019-01-25T19:01:14.570' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.570' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31974, N'sys', CAST(N'2019-01-25T19:01:14.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31975, N'sys', CAST(N'2019-01-25T19:01:14.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31976, N'sys', CAST(N'2019-01-25T19:01:14.573' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.573' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31977, N'sys', CAST(N'2019-01-25T19:01:14.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31978, N'sys', CAST(N'2019-01-25T19:01:14.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31979, N'sys', CAST(N'2019-01-25T19:01:14.577' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.577' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31980, N'sys', CAST(N'2019-01-25T19:01:14.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31981, N'sys', CAST(N'2019-01-25T19:01:14.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31982, N'sys', CAST(N'2019-01-25T19:01:14.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31983, N'sys', CAST(N'2019-01-25T19:01:14.580' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.580' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31984, N'sys', CAST(N'2019-01-25T19:01:14.583' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.583' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31985, N'sys', CAST(N'2019-01-25T19:01:14.583' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.583' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31986, N'sys', CAST(N'2019-01-25T19:01:14.583' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.583' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31987, N'sys', CAST(N'2019-01-25T19:01:14.587' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.587' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31988, N'sys', CAST(N'2019-01-25T19:01:14.587' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.587' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31989, N'sys', CAST(N'2019-01-25T19:01:14.587' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.587' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31990, N'sys', CAST(N'2019-01-25T19:01:14.590' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.590' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31991, N'sys', CAST(N'2019-01-25T19:01:14.590' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.590' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31992, N'sys', CAST(N'2019-01-25T19:01:14.590' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.590' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31993, N'sys', CAST(N'2019-01-25T19:01:14.590' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.590' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31994, N'sys', CAST(N'2019-01-25T19:01:14.593' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.593' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31995, N'sys', CAST(N'2019-01-25T19:01:14.593' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.593' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31996, N'sys', CAST(N'2019-01-25T19:01:14.593' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.593' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31997, N'sys', CAST(N'2019-01-25T19:01:14.597' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.597' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31998, N'sys', CAST(N'2019-01-25T19:01:14.597' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.597' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (31999, N'sys', CAST(N'2019-01-25T19:01:14.597' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.597' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32000, N'sys', CAST(N'2019-01-25T19:01:14.600' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.600' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32001, N'sys', CAST(N'2019-01-25T19:01:14.600' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.600' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32002, N'sys', CAST(N'2019-01-25T19:01:14.600' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.600' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32003, N'sys', CAST(N'2019-01-25T19:01:14.603' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.603' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32004, N'sys', CAST(N'2019-01-25T19:01:14.603' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.603' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32005, N'sys', CAST(N'2019-01-25T19:01:14.603' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.603' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32006, N'sys', CAST(N'2019-01-25T19:01:14.603' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.603' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32007, N'sys', CAST(N'2019-01-25T19:01:14.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32008, N'sys', CAST(N'2019-01-25T19:01:14.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32009, N'sys', CAST(N'2019-01-25T19:01:14.607' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.607' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32010, N'sys', CAST(N'2019-01-25T19:01:14.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32011, N'sys', CAST(N'2019-01-25T19:01:14.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32012, N'sys', CAST(N'2019-01-25T19:01:14.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32013, N'sys', CAST(N'2019-01-25T19:01:14.610' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.610' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32014, N'sys', CAST(N'2019-01-25T19:01:14.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32015, N'sys', CAST(N'2019-01-25T19:01:14.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32016, N'sys', CAST(N'2019-01-25T19:01:14.613' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.613' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32017, N'sys', CAST(N'2019-01-25T19:01:14.617' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.617' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32018, N'sys', CAST(N'2019-01-25T19:01:14.617' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.617' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32019, N'sys', CAST(N'2019-01-25T19:01:14.617' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.617' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32020, N'sys', CAST(N'2019-01-25T19:01:14.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32021, N'sys', CAST(N'2019-01-25T19:01:14.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32022, N'sys', CAST(N'2019-01-25T19:01:14.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32023, N'sys', CAST(N'2019-01-25T19:01:14.620' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.620' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32024, N'sys', CAST(N'2019-01-25T19:01:14.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32025, N'sys', CAST(N'2019-01-25T19:01:14.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32026, N'sys', CAST(N'2019-01-25T19:01:14.623' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.623' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32027, N'sys', CAST(N'2019-01-25T19:01:14.627' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.627' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32028, N'sys', CAST(N'2019-01-25T19:01:14.627' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.627' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32029, N'sys', CAST(N'2019-01-25T19:01:14.627' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.627' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32030, N'sys', CAST(N'2019-01-25T19:01:14.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32031, N'sys', CAST(N'2019-01-25T19:01:14.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32032, N'sys', CAST(N'2019-01-25T19:01:14.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32033, N'sys', CAST(N'2019-01-25T19:01:14.630' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.630' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32034, N'sys', CAST(N'2019-01-25T19:01:14.633' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.633' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32035, N'sys', CAST(N'2019-01-25T19:01:14.633' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.633' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32036, N'sys', CAST(N'2019-01-25T19:01:14.633' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.633' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32037, N'sys', CAST(N'2019-01-25T19:01:14.637' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.637' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32038, N'sys', CAST(N'2019-01-25T19:01:14.637' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.637' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32039, N'sys', CAST(N'2019-01-25T19:01:14.637' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.637' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32040, N'sys', CAST(N'2019-01-25T19:01:14.640' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.640' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32041, N'sys', CAST(N'2019-01-25T19:01:14.640' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.640' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32042, N'sys', CAST(N'2019-01-25T19:01:14.640' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.640' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32043, N'sys', CAST(N'2019-01-25T19:01:14.640' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.640' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32044, N'sys', CAST(N'2019-01-25T19:01:14.643' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.643' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32045, N'sys', CAST(N'2019-01-25T19:01:14.643' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.643' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32046, N'sys', CAST(N'2019-01-25T19:01:14.643' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.643' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32047, N'sys', CAST(N'2019-01-25T19:01:14.647' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32048, N'sys', CAST(N'2019-01-25T19:01:14.647' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32049, N'sys', CAST(N'2019-01-25T19:01:14.647' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.647' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32050, N'sys', CAST(N'2019-01-25T19:01:14.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32051, N'sys', CAST(N'2019-01-25T19:01:14.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32052, N'sys', CAST(N'2019-01-25T19:01:14.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32053, N'sys', CAST(N'2019-01-25T19:01:14.650' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.650' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32054, N'sys', CAST(N'2019-01-25T19:01:14.653' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.653' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32055, N'sys', CAST(N'2019-01-25T19:01:14.653' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.653' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32056, N'sys', CAST(N'2019-01-25T19:01:14.653' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.653' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32057, N'sys', CAST(N'2019-01-25T19:01:14.657' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.657' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32058, N'sys', CAST(N'2019-01-25T19:01:14.657' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.657' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32059, N'sys', CAST(N'2019-01-25T19:01:14.657' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.657' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32060, N'sys', CAST(N'2019-01-25T19:01:14.660' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.660' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32061, N'sys', CAST(N'2019-01-25T19:01:14.660' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.660' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32062, N'sys', CAST(N'2019-01-25T19:01:14.660' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.660' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32063, N'sys', CAST(N'2019-01-25T19:01:14.660' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.660' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32064, N'sys', CAST(N'2019-01-25T19:01:14.663' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.663' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32065, N'sys', CAST(N'2019-01-25T19:01:14.663' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.663' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32066, N'sys', CAST(N'2019-01-25T19:01:14.663' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.663' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32067, N'sys', CAST(N'2019-01-25T19:01:14.667' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.667' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32068, N'sys', CAST(N'2019-01-25T19:01:14.667' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.667' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32069, N'sys', CAST(N'2019-01-25T19:01:14.667' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.667' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32070, N'sys', CAST(N'2019-01-25T19:01:14.670' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.670' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32071, N'sys', CAST(N'2019-01-25T19:01:14.670' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.670' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32072, N'sys', CAST(N'2019-01-25T19:01:14.670' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.670' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32073, N'sys', CAST(N'2019-01-25T19:01:14.670' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.670' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32074, N'sys', CAST(N'2019-01-25T19:01:14.673' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.673' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32075, N'sys', CAST(N'2019-01-25T19:01:14.673' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.673' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32076, N'sys', CAST(N'2019-01-25T19:01:14.673' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.673' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32077, N'sys', CAST(N'2019-01-25T19:01:14.677' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.677' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32078, N'sys', CAST(N'2019-01-25T19:01:14.677' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.677' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32079, N'sys', CAST(N'2019-01-25T19:01:14.677' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.677' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32080, N'sys', CAST(N'2019-01-25T19:01:14.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32081, N'sys', CAST(N'2019-01-25T19:01:14.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32082, N'sys', CAST(N'2019-01-25T19:01:14.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32083, N'sys', CAST(N'2019-01-25T19:01:14.680' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.680' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32084, N'sys', CAST(N'2019-01-25T19:01:14.683' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.683' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32085, N'sys', CAST(N'2019-01-25T19:01:14.683' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.683' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32086, N'sys', CAST(N'2019-01-25T19:01:14.683' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.683' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32087, N'sys', CAST(N'2019-01-25T19:01:14.687' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.687' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32088, N'sys', CAST(N'2019-01-25T19:01:14.687' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.687' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32089, N'sys', CAST(N'2019-01-25T19:01:14.687' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.687' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32090, N'sys', CAST(N'2019-01-25T19:01:14.690' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.690' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32091, N'sys', CAST(N'2019-01-25T19:01:14.690' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.690' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32092, N'sys', CAST(N'2019-01-25T19:01:14.690' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.690' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32093, N'sys', CAST(N'2019-01-25T19:01:14.690' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.690' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32094, N'sys', CAST(N'2019-01-25T19:01:14.693' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.693' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32095, N'sys', CAST(N'2019-01-25T19:01:14.693' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.693' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32096, N'sys', CAST(N'2019-01-25T19:01:14.693' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.693' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32097, N'sys', CAST(N'2019-01-25T19:01:14.697' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.697' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32098, N'sys', CAST(N'2019-01-25T19:01:14.697' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.697' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32099, N'sys', CAST(N'2019-01-25T19:01:14.697' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.697' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32100, N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32101, N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32102, N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32103, N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32104, N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.700' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32105, N'sys', CAST(N'2019-01-25T19:01:14.703' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.703' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32106, N'sys', CAST(N'2019-01-25T19:01:14.703' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.703' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32107, N'sys', CAST(N'2019-01-25T19:01:14.703' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.703' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32108, N'sys', CAST(N'2019-01-25T19:01:14.707' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.707' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32109, N'sys', CAST(N'2019-01-25T19:01:14.707' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.707' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32110, N'sys', CAST(N'2019-01-25T19:01:14.707' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.707' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32111, N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32112, N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32113, N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32114, N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32115, N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'sys', CAST(N'2019-01-25T19:01:14.710' AS DateTime), N'1         ', N'51', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32116, N'simo@simo.com', CAST(N'2019-01-28T21:57:38.937' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T21:57:38.937' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32117, N'simo@simo.com', CAST(N'2019-01-28T21:58:03.010' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T21:58:03.010' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32118, N'simo@simo.com', CAST(N'2019-01-28T21:59:27.560' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T21:59:27.560' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32119, N'simo@simo.com', CAST(N'2019-01-28T22:00:25.990' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T22:00:25.990' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32120, N'simo@simo.com', CAST(N'2019-01-28T22:01:16.453' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T22:01:16.453' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32121, N'simo@simo.com', CAST(N'2019-01-28T22:02:22.350' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T22:02:22.350' AS DateTime), N'1         ', N'48', 4)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32122, N'simo@simo.com', CAST(N'2019-01-28T22:02:52.010' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T22:02:52.060' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32123, N'simo@simo.com', CAST(N'2019-01-28T22:03:39.710' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T22:03:39.710' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32124, N'simo@simo.com', CAST(N'2019-01-28T22:05:20.500' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T22:05:20.500' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32125, N'simo@simo.com', CAST(N'2019-01-28T22:06:49.053' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T22:06:49.053' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32126, N'simo@simo.com', CAST(N'2019-01-28T22:07:08.367' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T22:07:08.367' AS DateTime), N'1         ', N'30049', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32127, N'simo@simo.com', CAST(N'2019-01-31T17:38:50.107' AS DateTime), N'simo@simo.com', CAST(N'2019-01-31T17:38:50.107' AS DateTime), N'1         ', N'30050', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32128, N'simo@simo.com', CAST(N'2019-01-31T17:38:59.273' AS DateTime), N'simo@simo.com', CAST(N'2019-01-31T17:57:02.863' AS DateTime), N'1         ', N'30050', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (32129, N'simo@simo.com', CAST(N'2019-01-31T17:56:54.903' AS DateTime), N'simo@simo.com', CAST(N'2019-01-31T17:56:54.903' AS DateTime), N'1         ', N'30050', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42116, N'simo@simo.com', CAST(N'2019-03-05T15:30:17.090' AS DateTime), N'simo@simo.com', CAST(N'2019-03-05T15:30:17.090' AS DateTime), N'1         ', N'48', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42117, N'simo@simo.com', CAST(N'2019-03-05T15:34:29.073' AS DateTime), N'simo@simo.com', CAST(N'2019-03-05T15:34:54.013' AS DateTime), N'1         ', N'48', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42118, N'simo@simo.com', CAST(N'2019-03-05T20:16:07.333' AS DateTime), N'simo@simo.com', CAST(N'2019-03-05T20:16:07.333' AS DateTime), N'1         ', N'48', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42119, N'simo@simo.com', CAST(N'2019-03-05T20:16:23.950' AS DateTime), N'simo@simo.com', CAST(N'2019-03-05T20:16:23.950' AS DateTime), N'1         ', N'48', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42120, N'simo@simo.com', CAST(N'2019-03-06T12:55:54.997' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T12:55:54.997' AS DateTime), N'step 1    ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42121, N'simo@simo.com', CAST(N'2019-03-06T12:56:09.623' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T12:56:09.623' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42122, N'simo@simo.com', CAST(N'2019-03-06T12:56:25.490' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T12:56:25.490' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42123, N'simo@simo.com', CAST(N'2019-03-06T12:56:41.850' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T12:56:41.850' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42124, N'simo@simo.com', CAST(N'2019-03-06T12:58:24.633' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T12:58:24.633' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42125, N'simo@simo.com', CAST(N'2019-03-06T13:04:56.487' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:56.487' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42126, N'simo@simo.com', CAST(N'2019-03-06T13:04:57.213' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:57.213' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42127, N'simo@simo.com', CAST(N'2019-03-06T13:04:57.527' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:57.527' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42128, N'simo@simo.com', CAST(N'2019-03-06T13:04:57.833' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:57.833' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42129, N'simo@simo.com', CAST(N'2019-03-06T13:04:58.140' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:58.140' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42130, N'simo@simo.com', CAST(N'2019-03-06T13:04:58.450' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:58.450' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42131, N'simo@simo.com', CAST(N'2019-03-06T13:04:58.780' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:58.780' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42132, N'simo@simo.com', CAST(N'2019-03-06T13:04:59.100' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:59.100' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42133, N'simo@simo.com', CAST(N'2019-03-06T13:04:59.407' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:59.407' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42134, N'simo@simo.com', CAST(N'2019-03-06T13:04:59.703' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:59.703' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42135, N'simo@simo.com', CAST(N'2019-03-06T13:04:59.987' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:04:59.987' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42136, N'simo@simo.com', CAST(N'2019-03-06T13:05:00.300' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:00.300' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42137, N'simo@simo.com', CAST(N'2019-03-06T13:05:00.610' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:00.610' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42138, N'simo@simo.com', CAST(N'2019-03-06T13:05:00.923' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:00.923' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42139, N'simo@simo.com', CAST(N'2019-03-06T13:05:01.227' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:01.227' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42140, N'simo@simo.com', CAST(N'2019-03-06T13:05:01.537' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:01.537' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42141, N'simo@simo.com', CAST(N'2019-03-06T13:05:01.847' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:01.847' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42142, N'simo@simo.com', CAST(N'2019-03-06T13:05:02.150' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:02.150' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42143, N'simo@simo.com', CAST(N'2019-03-06T13:05:02.480' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:02.480' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42144, N'simo@simo.com', CAST(N'2019-03-06T13:05:02.783' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:02.783' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42145, N'simo@simo.com', CAST(N'2019-03-06T13:05:03.143' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:03.143' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42146, N'simo@simo.com', CAST(N'2019-03-06T13:05:03.457' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:03.457' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42147, N'simo@simo.com', CAST(N'2019-03-06T13:05:03.777' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:03.777' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42148, N'simo@simo.com', CAST(N'2019-03-06T13:05:04.080' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:04.080' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42149, N'simo@simo.com', CAST(N'2019-03-06T13:05:04.390' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:04.390' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42150, N'simo@simo.com', CAST(N'2019-03-06T13:05:04.693' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:04.693' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42151, N'simo@simo.com', CAST(N'2019-03-06T13:05:04.997' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:04.997' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42152, N'simo@simo.com', CAST(N'2019-03-06T13:05:05.303' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:05.303' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42153, N'simo@simo.com', CAST(N'2019-03-06T13:05:05.620' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:05.620' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42154, N'simo@simo.com', CAST(N'2019-03-06T13:05:05.930' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:05.930' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42155, N'simo@simo.com', CAST(N'2019-03-06T13:05:06.250' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:06.250' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42156, N'simo@simo.com', CAST(N'2019-03-06T13:05:06.557' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:06.557' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42157, N'simo@simo.com', CAST(N'2019-03-06T13:05:06.863' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:06.863' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42158, N'simo@simo.com', CAST(N'2019-03-06T13:05:07.217' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:07.217' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42159, N'simo@simo.com', CAST(N'2019-03-06T13:05:07.807' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:07.807' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42160, N'simo@simo.com', CAST(N'2019-03-06T13:05:08.453' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:08.453' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42161, N'simo@simo.com', CAST(N'2019-03-06T13:05:09.040' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:09.040' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42162, N'simo@simo.com', CAST(N'2019-03-06T13:05:09.597' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:09.597' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42163, N'simo@simo.com', CAST(N'2019-03-06T13:05:10.177' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:10.177' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42164, N'simo@simo.com', CAST(N'2019-03-06T13:05:10.740' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:10.740' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42165, N'simo@simo.com', CAST(N'2019-03-06T13:05:11.320' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:11.320' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42166, N'simo@simo.com', CAST(N'2019-03-06T13:05:11.907' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:11.907' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42167, N'simo@simo.com', CAST(N'2019-03-06T13:05:12.493' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:12.493' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42168, N'simo@simo.com', CAST(N'2019-03-06T13:05:13.080' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:13.080' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42169, N'simo@simo.com', CAST(N'2019-03-06T13:05:13.627' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:13.627' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42170, N'simo@simo.com', CAST(N'2019-03-06T13:05:14.183' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:14.183' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42171, N'simo@simo.com', CAST(N'2019-03-06T13:05:14.503' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:14.503' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42172, N'simo@simo.com', CAST(N'2019-03-06T13:05:14.807' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:14.807' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42173, N'simo@simo.com', CAST(N'2019-03-06T13:05:15.117' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:15.117' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42174, N'simo@simo.com', CAST(N'2019-03-06T13:05:15.420' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:15.420' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42175, N'simo@simo.com', CAST(N'2019-03-06T13:05:15.750' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:15.750' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42176, N'simo@simo.com', CAST(N'2019-03-06T13:05:16.070' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:16.070' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42177, N'simo@simo.com', CAST(N'2019-03-06T13:05:16.377' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:16.377' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42178, N'simo@simo.com', CAST(N'2019-03-06T13:05:16.680' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:16.680' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42179, N'simo@simo.com', CAST(N'2019-03-06T13:05:16.990' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:16.990' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42180, N'simo@simo.com', CAST(N'2019-03-06T13:05:17.300' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:17.300' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42181, N'simo@simo.com', CAST(N'2019-03-06T13:05:17.670' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:17.670' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42182, N'simo@simo.com', CAST(N'2019-03-06T13:05:17.980' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:17.980' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42183, N'simo@simo.com', CAST(N'2019-03-06T13:05:18.297' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:18.297' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42184, N'simo@simo.com', CAST(N'2019-03-06T13:05:18.613' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:18.613' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42185, N'simo@simo.com', CAST(N'2019-03-06T13:05:18.933' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:18.933' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42186, N'simo@simo.com', CAST(N'2019-03-06T13:05:19.253' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:19.253' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42187, N'simo@simo.com', CAST(N'2019-03-06T13:05:19.567' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:19.567' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42188, N'simo@simo.com', CAST(N'2019-03-06T13:05:19.867' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:19.867' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42189, N'simo@simo.com', CAST(N'2019-03-06T13:05:20.177' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:20.177' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42190, N'simo@simo.com', CAST(N'2019-03-06T13:05:20.493' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:20.493' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42191, N'simo@simo.com', CAST(N'2019-03-06T13:05:20.790' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:20.790' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42192, N'simo@simo.com', CAST(N'2019-03-06T13:05:21.107' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:21.107' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42193, N'simo@simo.com', CAST(N'2019-03-06T13:05:21.410' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:21.410' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42194, N'simo@simo.com', CAST(N'2019-03-06T13:05:21.740' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:21.740' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42195, N'simo@simo.com', CAST(N'2019-03-06T13:05:22.060' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:22.060' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42196, N'simo@simo.com', CAST(N'2019-03-06T13:05:22.373' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:22.373' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42197, N'simo@simo.com', CAST(N'2019-03-06T13:05:22.693' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:22.693' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42198, N'simo@simo.com', CAST(N'2019-03-06T13:05:23.000' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:23.000' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42199, N'simo@simo.com', CAST(N'2019-03-06T13:05:23.327' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:23.327' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42200, N'simo@simo.com', CAST(N'2019-03-06T13:05:23.647' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:23.647' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42201, N'simo@simo.com', CAST(N'2019-03-06T13:05:23.973' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:23.973' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42202, N'simo@simo.com', CAST(N'2019-03-06T13:05:24.357' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:24.357' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42203, N'simo@simo.com', CAST(N'2019-03-06T13:05:24.887' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:24.887' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42204, N'simo@simo.com', CAST(N'2019-03-06T13:05:25.433' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:25.433' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42205, N'simo@simo.com', CAST(N'2019-03-06T13:05:25.933' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:25.933' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42206, N'simo@simo.com', CAST(N'2019-03-06T13:05:26.737' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:26.737' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42207, N'simo@simo.com', CAST(N'2019-03-06T13:05:27.330' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:27.330' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42208, N'simo@simo.com', CAST(N'2019-03-06T13:05:27.933' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:27.933' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42209, N'simo@simo.com', CAST(N'2019-03-06T13:05:28.237' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:28.237' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42210, N'simo@simo.com', CAST(N'2019-03-06T13:05:28.670' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:28.670' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42211, N'simo@simo.com', CAST(N'2019-03-06T13:05:29.003' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:29.003' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42212, N'simo@simo.com', CAST(N'2019-03-06T13:05:29.327' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:29.327' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42213, N'simo@simo.com', CAST(N'2019-03-06T13:05:29.690' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:29.690' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42214, N'simo@simo.com', CAST(N'2019-03-06T13:05:30.157' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:30.157' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42215, N'simo@simo.com', CAST(N'2019-03-06T13:05:30.670' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:30.670' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42216, N'simo@simo.com', CAST(N'2019-03-06T13:05:31.207' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:31.207' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42217, N'simo@simo.com', CAST(N'2019-03-06T13:05:31.777' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:31.777' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42218, N'simo@simo.com', CAST(N'2019-03-06T13:05:32.330' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:32.330' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42219, N'simo@simo.com', CAST(N'2019-03-06T13:05:32.867' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:32.867' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42220, N'simo@simo.com', CAST(N'2019-03-06T13:05:33.187' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:33.187' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42221, N'simo@simo.com', CAST(N'2019-03-06T13:05:33.607' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:33.607' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42222, N'simo@simo.com', CAST(N'2019-03-06T13:05:33.910' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:33.910' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42223, N'simo@simo.com', CAST(N'2019-03-06T13:05:34.217' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:34.217' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42224, N'simo@simo.com', CAST(N'2019-03-06T13:05:34.527' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:05:34.527' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42225, N'simo@simo.com', CAST(N'2019-03-06T13:10:08.617' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:11:36.727' AS DateTime), N'1         ', N'2', 1)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42226, N'simo@simo.com', CAST(N'2019-03-06T13:11:56.203' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:11:56.203' AS DateTime), N'valide    ', N'48', 6)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42227, N'simo@simo.com', CAST(N'2019-03-06T13:23:12.327' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:23:12.327' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42228, N'simo@simo.com', CAST(N'2019-03-06T13:31:27.123' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:31:27.123' AS DateTime), N'valide    ', N'48', 6)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42229, N'simo@simo.com', CAST(N'2019-03-06T13:31:54.987' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:31:54.987' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42230, N'simo@simo.com', CAST(N'2019-03-06T13:32:08.067' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:32:08.067' AS DateTime), N'valide    ', N'48', 6)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42231, N'simo@simo.com', CAST(N'2019-03-06T13:45:05.863' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:45:05.863' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42232, N'simo@simo.com', CAST(N'2019-03-06T13:45:16.843' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:45:16.843' AS DateTime), N'valide    ', N'48', 6)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42233, N'simo@simo.com', CAST(N'2019-03-06T13:52:16.213' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:52:16.213' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42234, N'simo@simo.com', CAST(N'2019-03-06T13:54:05.463' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:54:05.463' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42235, N'simo@simo.com', CAST(N'2019-03-06T13:54:07.327' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:54:07.327' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42236, N'simo@simo.com', CAST(N'2019-03-06T13:54:11.653' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:54:11.653' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42237, N'simo@simo.com', CAST(N'2019-03-06T13:54:17.673' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:54:17.673' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42238, N'simo@simo.com', CAST(N'2019-03-06T13:54:29.657' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:54:29.657' AS DateTime), N'valide    ', N'48', 6)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42239, N'simo@simo.com', CAST(N'2019-03-06T13:54:32.693' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:54:32.693' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42240, N'simo@simo.com', CAST(N'2019-03-06T13:56:28.663' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T13:56:28.663' AS DateTime), N'1         ', N'49', 5)
GO
INSERT [dbo].[BO] ([BO_ID], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_TYPE], [VERSION]) VALUES (42241, N'simo@simo.com', CAST(N'2019-03-06T14:00:06.663' AS DateTime), N'simo@simo.com', CAST(N'2019-03-06T14:00:06.663' AS DateTime), N'1         ', N'49', 5)
GO
SET IDENTITY_INSERT [dbo].[BO] OFF
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (7, 8, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (7, 9, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 11, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 12, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 13, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 14, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 15, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 16, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 17, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 18, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 19, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 20, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 21, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 22, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (10, 23, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (24, 25, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (24, 26, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (26, 28, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (26, 29, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (41, 43, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (41, 44, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (42, 47, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (45, 46, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (48, 50, N'1..*')
GO
INSERT [dbo].[BO_CHILDS] ([BO_PARENT_ID], [BO_CHILD_ID], [RELATION]) VALUES (82, 83, N'1..*')
GO
SET IDENTITY_INSERT [dbo].[BO_ROLE] ON 
GO
INSERT [dbo].[BO_ROLE] ([BO_ROLE_ID], [META_BO_ID], [ROLE_ID], [CAN_READ], [CAN_WRITE], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (1, 49, N'a7cfd5f5-9f3d-4d18-a028-28ff37ed97fe', 1, 0, NULL, CAST(N'2019-03-16T15:10:35.073' AS DateTime), NULL, CAST(N'2019-03-16T15:10:35.073' AS DateTime), NULL)
GO
SET IDENTITY_INSERT [dbo].[BO_ROLE] OFF
GO
SET IDENTITY_INSERT [dbo].[META_BO] ON 
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (1, N'META_BO', 1, N'admin', CAST(N'2018-11-11T13:06:41.347' AS DateTime), N'admin', CAST(N'2018-11-11T13:06:41.347' AS DateTime), N'-1', N'META_BO', NULL, NULL)
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (2, N'WORKFLOW', 1, N'admin', CAST(N'2018-12-18T13:06:41.347' AS DateTime), N'admin', CAST(N'2018-12-18T13:06:41.347' AS DateTime), N'-1', N'WORKFLOW', NULL, NULL)
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (48, N'FileTypes', 6, N'simo@simo.com', CAST(N'2019-01-07T11:45:14.147' AS DateTime), N'simo@simo.com', CAST(N'2019-03-05T20:46:54.310' AS DateTime), N'ACTIVE v6', N'FileTypes_BO_', N'form', N'{"TITLE":"Types de fichiers","GROUPE":"GED"}')
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (49, N'Files', 5, N'simo@simo.com', CAST(N'2019-01-07T11:45:51.583' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T15:41:07.573' AS DateTime), N'ACTIVE v5', N'Files_BO_', N'form', N'{"TITLE":"Files","GROUPE":"GED"}')
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (51, N'Emplacement par defaut', 1, N'simo@simo.com', CAST(N'2019-01-07T12:13:36.687' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:14:03.643' AS DateTime), N'ACTIVE v1', N'Emplacement_par_default_BO_', N'form', N'{"TITLE":null,"GROUPE":null}')
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (10048, N'New BO', 2, N'simo@simo.com', CAST(N'2019-01-11T16:57:16.110' AS DateTime), N'simo@simo.com', CAST(N'2019-01-13T18:27:22.523' AS DateTime), N'ACTIVE v2', N'New_BO_BO_', N'form', N'{"TITLE":"test reload","GROUPE":"REL"}')
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (20048, N'FileLibrary', 2, N'simo@simo.com', CAST(N'2019-01-17T15:32:59.163' AS DateTime), N'simo@simo.com', CAST(N'2019-01-21T11:08:09.470' AS DateTime), N'ACTIVE v2', N'FileLibrary_BO_', N'form', N'{"TITLE":"Librairie de fichiers","GROUPE":"GED"}')
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (30048, N'demande d''affectation', 1, N'simo@simo.com', CAST(N'2019-01-21T11:23:40.830' AS DateTime), N'simo@simo.com', CAST(N'2019-01-21T11:24:02.180' AS DateTime), N'ACTIVE v1', N'demande_daffectation_BO_', N'form', N'{"TITLE":null,"GROUPE":null}')
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (30049, N'Business object name', 1, N'simo@simo.com', CAST(N'2019-01-28T21:55:20.590' AS DateTime), N'simo@simo.com', CAST(N'2019-01-28T21:57:02.583' AS DateTime), N'ACTIVE v1', N'Business_object_name_BO_', N'form', N'{"TITLE":"Busniess object","GROUPE":null}')
GO
INSERT [dbo].[META_BO] ([META_BO_ID], [BO_NAME], [VERSION], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [BO_DB_NAME], [TYPE], [JSON_DATA]) VALUES (30050, N'testDate', 1, N'simo@simo.com', CAST(N'2019-01-31T17:38:27.857' AS DateTime), N'simo@simo.com', CAST(N'2019-01-31T17:38:37.963' AS DateTime), N'ACTIVE v1', N'testDate_BO_', N'form', N'{"TITLE":"Teste date","GROUPE":null}')
GO
SET IDENTITY_INSERT [dbo].[META_BO] OFF
GO
SET IDENTITY_INSERT [dbo].[META_FIELD] ON 
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (1, 1, N'META_BO_ID', N'bigint', 0, N'#', NULL, 0, N'', NULL, N'', NULL, 0, 0, NULL, NULL, N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'PK', NULL, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (2, 1, N'BO_NAME', N'varchar(100)', 1, N'Nom', NULL, 1, N'Nom', NULL, N'v-text', NULL, 1, 0, 0, NULL, N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'amdin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'LOCKED', NULL, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (3, 1, N'STATUS', N'varchar(50)', 1, N'Nom', NULL, 1, N'STATUS', NULL, N'v-label', NULL, 1, 0, NULL, N'PENDING', N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-11-11T13:10:28.673' AS DateTime), N'LOCKED', NULL, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (4, 1, N'TYPE', N'varchar(50)', 1, N'Type', N'{"fct":"Display","source":"TYPE"}', 1, N'Type', NULL, N'v-select', N'[{ "Value": "form", "Display": "FORM" }, { "Value": "subform", "Display": "SUB FORM" }]', 1, 0, NULL, N'form', N'admin', CAST(N'2018-12-03T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-03T13:10:28.673' AS DateTime), N'LOCKED', NULL, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (5, 2, N'LIBELLE', N'varchar(50)', 1, N'Libelle', N'', 1, N'Libelle', NULL, N'v-text', N'', 1, 0, NULL, N'form', N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'LOCKED', NULL, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (6, 2, N'ACTIVE', N'int', 1, N'Active', N'', 1, N'Active', NULL, N'v-checkbox', N'', 1, 0, NULL, N'form', N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'LOCKED', NULL, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (7, 2, N'additional.column', N'', 1, N'', N'{"type":"button", "color":"btn-success","icon":"add","action":"redirect", "data":"#workflow.home"}', 1, N'', NULL, N'', N'', 0, 0, NULL, N'form', N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'admin', CAST(N'2018-12-18T13:10:28.673' AS DateTime), N'LOCKED', NULL, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (100, 48, N'Nom', N'varchar(100)', 0, N'Nom', NULL, 1, N'Nom', NULL, N'v-text', NULL, 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V117', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (101, 49, N'Nom', N'varchar(100)', 0, N'Nom', NULL, 1, N'Nom', NULL, N'v-text', N'', 1, 0, 1, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-31T14:24:11.627' AS DateTime), N'COMMITED V119', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (102, 49, N'Type', N'varchar(100)', 1, N'Type', N'{"fct":"Display","source":"{\"source\":\"FileTypes_BO_\",\"value\":\"BO_ID\",\"display\":\"''''+'' ''+Emplacement+'' ''+Extension+'' ''+Nom\",\"filter\":\"\",\"parent\":\"\",\"link_field\":\"\",\"detail\":{\"Extension\":{\"checked\":true,\"label\":\"ext\",\"class\":\"col-md-6\",\"format\":\"\"},\"Emplacement\":{\"checked\":true,\"label\":\"Emplacement\",\"class\":\"col-md-6\",\"format\":\"{\\\"fct\\\":\\\"Display\\\",\\\"source\\\":\\\"{\\\\\\\"source\\\\\\\":\\\\\\\"Emplacement_par_default_BO_\\\\\\\",\\\\\\\"value\\\\\\\":\\\\\\\"BO_ID\\\\\\\",\\\\\\\"display\\\\\\\":\\\\\\\"Nom\\\\\\\",\\\\\\\"filter\\\\\\\":\\\\\\\"\\\\\\\",\\\\\\\"parent\\\\\\\":\\\\\\\"\\\\\\\",\\\\\\\"link_field\\\\\\\":\\\\\\\"\\\\\\\",\\\\\\\"detail\\\\\\\":{\\\\\\\"BO_ID\\\\\\\":{\\\\\\\"checked\\\\\\\":true,\\\\\\\"label\\\\\\\":\\\\\\\"\\\\\\\",\\\\\\\"class\\\\\\\":\\\\\\\"col-md-6\\\\\\\",\\\\\\\"format\\\\\\\":\\\\\\\"\\\\\\\"},\\\\\\\"Nom\\\\\\\":{\\\\\\\"checked\\\\\\\":true,\\\\\\\"label\\\\\\\":\\\\\\\"Nom emplacement\\\\\\\",\\\\\\\"class\\\\\\\":\\\\\\\"col-md-6\\\\\\\",\\\\\\\"format\\\\\\\":\\\\\\\"\\\\\\\"}}}\\\"}\"}}}"}', 1, N'Type', NULL, N'v-select', N'{"source":"FileTypes_BO_","value":"BO_ID","display":"Emplacement+'' ''+Extension+'' ''+Nom","filter":"","parent":"","link_field":"","detail":{"Extension":{"checked":true,"label":"ext","class":"col-md-6","format":""},"Emplacement":{"checked":true,"label":"Emplacement","class":"col-md-6","format":"{\"fct\":\"Display\",\"source\":\"{\\\"source\\\":\\\"Emplacement_par_default_BO_\\\",\\\"value\\\":\\\"BO_ID\\\",\\\"display\\\":\\\"Nom\\\",\\\"filter\\\":\\\"\\\",\\\"parent\\\":\\\"\\\",\\\"link_field\\\":\\\"\\\",\\\"detail\\\":{\\\"BO_ID\\\":{\\\"checked\\\":true,\\\"label\\\":\\\"\\\",\\\"class\\\":\\\"col-md-6\\\",\\\"format\\\":\\\"\\\"},\\\"Nom\\\":{\\\"checked\\\":true,\\\"label\\\":\\\"Nom emplacement\\\",\\\"class\\\":\\\"col-md-6\\\",\\\"format\\\":\\\"\\\"}}}\"}"}}}', 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-23T10:41:20.637' AS DateTime), N'COMMITED V119', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (103, 48, N'Extension', N'varchar(100)', 0, N'Extension', NULL, 1, N'Extension', NULL, N'v-text', NULL, 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V118', 2, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (104, 51, N'Nom', N'varchar(100)', 0, N'Nom', NULL, 1, N'Nom', NULL, N'v-text', N'', 1, 1, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-25T18:58:54.317' AS DateTime), N'COMMITED V122', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (105, 48, N'Emplacement', N'varchar(100)', 1, N'Emplacement', N'{"fct":"Display","source":"{\"source\":\"Emplacement_par_default_BO_\",\"value\":\"BO_ID\",\"display\":\"Nom\",\"filter\":\"\",\"parent\":\"\",\"link_field\":\"\",\"detail\":{\"BO_ID\":{\"checked\":true,\"label\":\"\",\"class\":\"col-md-6\",\"format\":\"\"},\"Nom\":{\"checked\":true,\"label\":\"Nom emplacement\",\"class\":\"col-md-6\",\"format\":\"\"}}}"}', 1, N'Emplacement', NULL, N'v-select', N'{"source":"Emplacement_par_default_BO_","value":"BO_ID","display":"Nom","filter":"","parent":"","link_field":"","detail":{"BO_ID":{"checked":true,"label":"","class":"col-md-6","format":""},"Nom":{"checked":true,"label":"Nom emplacement","class":"col-md-6","format":""}}}', 1, 1, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-22T11:09:48.300' AS DateTime), N'COMMITED V120', 3, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (10097, 10048, N'C1', N'varchar(100)', 1, N'C1', NULL, 1, N'C1', NULL, N'v-text', NULL, 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V10108', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (10098, 10048, N'emp', N'varchar(100)', 1, N'emp', N'{"fct":"Display","source":"{\"source\":\"Emplacement_par_default_BO_\",\"value\":\"BO_ID\",\"display\":\"Nom\",\"filter\":\"\",\"parent\":\"\",\"link_field\":\"\",\"detail\":{}}"}', 1, N'emp', NULL, N'v-select', N'{"source":"Emplacement_par_default_BO_","value":"BO_ID","display":"Nom","filter":"","parent":"","link_field":"","detail":{}}', 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V10109', 2, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (20097, 20048, N'Type_de_fichier', N'varchar(100)', 1, N'Type de fichier', N'{"fct":"Display","source":"{\"source\":\"FileTypes_BO_\",\"value\":\"BO_ID\",\"display\":\"Nom\",\"filter\":\"\",\"parent\":\"Emp\",\"link_field\":\"Emplacement\",\"detail\":{\"Emplacement\":{\"checked\":true,\"label\":\"Emplacement\",\"class\":\"col-md-12\",\"format\":\"{\\\"fct\\\":\\\"Display\\\",\\\"source\\\":\\\"{\\\\\\\"source\\\\\\\":\\\\\\\"Emplacement_par_default_BO_\\\\\\\",\\\\\\\"value\\\\\\\":\\\\\\\"BO_ID\\\\\\\",\\\\\\\"display\\\\\\\":\\\\\\\"Nom\\\\\\\",\\\\\\\"filter\\\\\\\":\\\\\\\"\\\\\\\",\\\\\\\"parent\\\\\\\":\\\\\\\"\\\\\\\",\\\\\\\"link_field\\\\\\\":\\\\\\\"\\\\\\\",\\\\\\\"detail\\\\\\\":{\\\\\\\"BO_ID\\\\\\\":{\\\\\\\"checked\\\\\\\":true,\\\\\\\"label\\\\\\\":\\\\\\\"#\\\\\\\",\\\\\\\"class\\\\\\\":\\\\\\\"col-md-6\\\\\\\",\\\\\\\"format\\\\\\\":\\\\\\\"\\\\\\\"},\\\\\\\"Nom\\\\\\\":{\\\\\\\"checked\\\\\\\":true,\\\\\\\"label\\\\\\\":\\\\\\\"Nom emplacement\\\\\\\",\\\\\\\"class\\\\\\\":\\\\\\\"col-md-6\\\\\\\",\\\\\\\"format\\\\\\\":\\\\\\\"\\\\\\\"}}}\\\"}\"},\"Extension\":{\"checked\":true,\"label\":\"Extension\",\"class\":\"col-md-12\",\"format\":\"\"}}}"}', 1, N'Type de fichier', NULL, N'v-select', N'{"source":"FileTypes_BO_","value":"BO_ID","display":"Nom","filter":"","parent":"Emp","link_field":"Emplacement","detail":{"Emplacement":{"checked":true,"label":"Emplacement","class":"col-md-12","format":"{\"fct\":\"Display\",\"source\":\"{\\\"source\\\":\\\"Emplacement_par_default_BO_\\\",\\\"value\\\":\\\"BO_ID\\\",\\\"display\\\":\\\"Nom\\\",\\\"filter\\\":\\\"\\\",\\\"parent\\\":\\\"\\\",\\\"link_field\\\":\\\"\\\",\\\"detail\\\":{\\\"BO_ID\\\":{\\\"checked\\\":true,\\\"label\\\":\\\"#\\\",\\\"class\\\":\\\"col-md-6\\\",\\\"format\\\":\\\"\\\"},\\\"Nom\\\":{\\\"checked\\\":true,\\\"label\\\":\\\"Nom emplacement\\\",\\\"class\\\":\\\"col-md-6\\\",\\\"format\\\":\\\"\\\"}}}\"}"},"Extension":{"checked":true,"label":"Extension","class":"col-md-12","format":""}}}', 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-21T11:07:25.617' AS DateTime), N'COMMITED V20108', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (20098, 20048, N'Fichier', N'varchar(100)', 1, N'Fichier', N'{"fct":"Display","source":"{\"source\":\"Files_BO_\",\"value\":\"BO_ID\",\"display\":\"Nom\",\"filter\":\"\",\"parent\":\"Type_de_fichier\",\"link_field\":\"Type\",\"detail\":{\"Nom\":{\"checked\":true,\"label\":\"Nom\",\"class\":\"col-md-12\",\"format\":\"\"}}}"}', 1, N'Fichier', NULL, N'v-select', N'{"source":"Files_BO_","value":"BO_ID","display":"Nom","filter":"","parent":"Type_de_fichier","link_field":"Type","detail":{"Nom":{"checked":true,"label":"Nom","class":"col-md-12","format":""}}}', 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-21T11:07:40.630' AS DateTime), N'COMMITED V20108', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30097, 20048, N'Emp', N'varchar(100)', 1, N'Emp', N'{"fct":"Display","source":"{\"source\":\"Emplacement_par_default_BO_\",\"value\":\"BO_ID\",\"display\":\"Nom\",\"filter\":\"\",\"parent\":\"\",\"link_field\":\"\",\"detail\":{}}"}', 1, N'Emp', NULL, N'v-select', N'{"source":"Emplacement_par_default_BO_","value":"BO_ID","display":"Nom","filter":"","parent":"","link_field":"","detail":{}}', 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V20109', 2, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30098, 30048, N'demandeur', N'varchar(100)', 1, N'demandeur', NULL, 1, N'demandeur', NULL, N'v-text', NULL, 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V30109', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30099, 48, N'rtrt', N'varchar(100)', 1, N'rtrt', N'{"fct":"Display","source":"{\"source\":\"demande_daffectation_BO_\",\"value\":\"BO_ID\",\"display\":\"demandeur\",\"filter\":\"\",\"parent\":\"\",\"link_field\":\"\",\"detail\":{\"demandeur\":{\"checked\":true,\"label\":\"\",\"class\":\"col-md-12\",\"format\":\"\"}}}"}', NULL, N'rtrt', NULL, N'v-select', N'{"source":"demande_daffectation_BO_","value":"BO_ID","display":"demandeur","filter":"","parent":"","link_field":"","detail":{"demandeur":{"checked":true,"label":"","class":"col-md-12","format":""}}}', 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'[deleted]COMMITED V125', 4, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30100, 49, N'Fichier', N'nvarchar(MAX)', 1, N'Fichier', NULL, 1, N'Fichier', NULL, N'v-file', NULL, 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V121', 2, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30101, 49, N'Comment', N'varchar(100)', 1, N'Comment', NULL, 1, N'Comment', NULL, N'v-text', N'', 1, 1, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-02-17T18:43:06.170' AS DateTime), N'COMMITED V30113', 4, N'{"DEFAULT":"FL_[+1]"}')
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30102, 49, N'Order', N'nvarchar(MAX)', 1, N'Order', NULL, 1, N'Order', NULL, N'v-number', N'', 1, 1, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V30114', 5, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30103, 30049, N'First name', N'varchar(100)', 1, N'First name', NULL, 1, N'First name', NULL, N'v-text', N'', 1, 0, 1, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-28T21:56:08.497' AS DateTime), N'COMMITED V30116', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30104, 30049, N'Last_name', N'varchar(100)', 1, N'Last name', NULL, 1, N'Last name', NULL, N'v-text', N'', 1, 0, 1, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V30116', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30105, 30049, N'Age', N'varchar(100)', 1, N'Age', N'', 1, N'Age', NULL, N'v-select', N'[{"Value":"1","Display":"1"},{"Value":"2","Display":"2"},{"Value":"3","Display":"3"},{"Value":"4","Display":"4"},{"Value":"5","Display":"5"},{"Value":"6","Display":"6"},{"Value":"7","Display":"7"},{"Value":"8","Display":"8"},{"Value":"9","Display":"9"}]', 1, 0, 1, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V30116', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30106, 30049, N'TestDT', N'DateTime', 1, N'TestDT', NULL, 1, N'TestDT', NULL, N'v-datepicker', N'', 1, 0, 1, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-31T17:37:20.183' AS DateTime), N'[deleted]NEW', NULL, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30107, 49, N'le', N'DateTime', 1, N'le', NULL, 1, N'le', NULL, N'v-datepicker', N'', 1, 0, 1, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'NEW', NULL, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (30108, 30050, N'le', N'DateTime', 1, N'le', N'{"fct":"date"}', 1, N'le', NULL, N'v-datepicker', N'', 1, 0, 1, NULL, N'simo@simo.com', NULL, N'simo@simo.com', NULL, N'COMMITED V30123', 1, NULL)
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (40103, 48, N'PlusSequence_tes', N'varchar(100)', 1, N'PlusSequence tes', NULL, 1, N'PlusSequence tes', NULL, N'v-text', N'', 1, 1, 1, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-03-05T20:44:15.150' AS DateTime), N'COMMITED V30111', 5, N'{"DEFAULT":"TP_[+1].ext"}')
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (40104, 49, N'test auto', N'varchar(100)', 1, N'test auto', NULL, 1, N'test auto', NULL, N'v-text', N'', 1, 1, 1, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-03-05T20:15:25.143' AS DateTime), N'NEW', NULL, N'{"DEFAULT":"file[+1].exe"}')
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (40105, 48, N'test_date', N'varchar(100)', 1, N'test date', NULL, 1, N'test date', NULL, N'v-datepicker', N'', 1, 1, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-03-05T20:49:45.570' AS DateTime), N'COMMITED V40116', 6, N'{"DEFAULT":"[d]"}')
GO
INSERT [dbo].[META_FIELD] ([META_FIELD_ID], [META_BO_ID], [DB_NAME], [DB_TYPE], [DB_NULL], [GRID_NAME], [GRID_FORMAT], [GRID_SHOW], [FORM_NAME], [FORM_FORMAT], [FORM_TYPE], [FORM_SOURCE], [FORM_SHOW], [FORM_OPTIONAL], [IS_FILTER], [FORM_DEFAULT], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS], [VERSION], [JSON_DATA]) VALUES (40106, 48, N'test_date_1', N'varchar(100)', 1, N'test date 1', NULL, 1, N'test date 1', NULL, N'v-datepicker', N'', 1, 0, 0, NULL, N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-03-05T20:49:50.483' AS DateTime), N'COMMITED V40116', 6, N'{"DEFAULT":"[d+7]"}')
GO
SET IDENTITY_INSERT [dbo].[META_FIELD] OFF
GO
SET IDENTITY_INSERT [dbo].[NOTIF] ON 
GO
INSERT [dbo].[NOTIF] ([ID_NOTIF], [VALIDATOR], [ETAT], [CREATED_DATE]) VALUES (1, N'simo@simo.com', 0, CAST(N'2019-03-06T12:55:55.390' AS DateTime))
GO
INSERT [dbo].[NOTIF] ([ID_NOTIF], [VALIDATOR], [ETAT], [CREATED_DATE]) VALUES (2, N'simo@simo.com', 0, CAST(N'2019-03-06T13:11:56.343' AS DateTime))
GO
INSERT [dbo].[NOTIF] ([ID_NOTIF], [VALIDATOR], [ETAT], [CREATED_DATE]) VALUES (3, N'simo@simo.com', 0, CAST(N'2019-03-06T13:31:27.660' AS DateTime))
GO
INSERT [dbo].[NOTIF] ([ID_NOTIF], [VALIDATOR], [ETAT], [CREATED_DATE]) VALUES (4, N'simo@simo.com', 0, CAST(N'2019-03-06T13:32:08.090' AS DateTime))
GO
INSERT [dbo].[NOTIF] ([ID_NOTIF], [VALIDATOR], [ETAT], [CREATED_DATE]) VALUES (5, N'simo@simo.com', 0, CAST(N'2019-03-06T13:45:16.873' AS DateTime))
GO
INSERT [dbo].[NOTIF] ([ID_NOTIF], [VALIDATOR], [ETAT], [CREATED_DATE]) VALUES (6, N'simo@simo.com', 0, CAST(N'2019-03-06T13:54:29.667' AS DateTime))
GO
SET IDENTITY_INSERT [dbo].[NOTIF] OFF
GO
SET IDENTITY_INSERT [dbo].[PAGE] ON 
GO
INSERT [dbo].[PAGE] ([PAGE_ID], [TITLE], [GROUPE], [STATUS], [LAYOUT], [CREATED_DATE], [CREATED_BY], [UPDATED_DATE], [UPDATED_BY]) VALUES (3, N'test', N'testjj', N'New', NULL, CAST(N'2019-02-10T17:58:20.813' AS DateTime), N'simo@simo.com', CAST(N'2019-02-10T18:27:03.467' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[PAGE] ([PAGE_ID], [TITLE], [GROUPE], [STATUS], [LAYOUT], [CREATED_DATE], [CREATED_BY], [UPDATED_DATE], [UPDATED_BY]) VALUES (4, N'tr', N'tr', N'New', N'', CAST(N'2019-02-10T18:26:59.723' AS DateTime), N'simo@simo.com', CAST(N'2019-02-10T18:26:59.723' AS DateTime), N'simo@simo.com')
GO
SET IDENTITY_INSERT [dbo].[PAGE] OFF
GO
SET IDENTITY_INSERT [dbo].[PlusSequence] ON 
GO
INSERT [dbo].[PlusSequence] ([SequenceID], [cle], [TableName], [StartValue], [StepBy], [CurrentValue]) VALUES (8, N'TP_.ext', N'FileTypes_BO_', 1, 1, 52)
GO
INSERT [dbo].[PlusSequence] ([SequenceID], [cle], [TableName], [StartValue], [StepBy], [CurrentValue]) VALUES (9, N'FL_', N'Files_BO_', 1, 1, 13)
GO
SET IDENTITY_INSERT [dbo].[PlusSequence] OFF
GO
SET IDENTITY_INSERT [dbo].[TASK] ON 
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (106, 42226, N'[{"email":"simo@simo.com","status":"new"}]', N'valide', 1, 1, N'VALIDATION', CAST(N'2019-03-06T13:11:56.330' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (107, 42226, N'{"value":49,"display":"Files","mapping":[{"parent":"Nom","link":"=","child":"Nom"},{"parent":"Extension","link":"=","child":"Comment"}]}', NULL, 1, 2, N'BO', CAST(N'2019-03-06T13:11:56.387' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (108, 42228, N'[{"email":"simo@simo.com","status":"new"}]', N'valide', 0, 1, N'VALIDATION', CAST(N'2019-03-06T13:31:27.647' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (109, 42228, N'{"value":49,"display":"Files","mapping":[{"parent":"Nom","link":"=","child":"Nom"},{"parent":"Extension","link":"=","child":"Comment"}]}', NULL, 0, 2, N'BO', CAST(N'2019-03-06T13:31:27.737' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (110, 42230, N'[{"email":"simo@simo.com","status":"new"}]', N'valide', 0, 1, N'VALIDATION', CAST(N'2019-03-06T13:32:08.090' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (111, 42230, N'{"value":49,"display":"Files","mapping":[{"parent":"Nom","link":"=","child":"Nom"},{"parent":"Extension","link":"=","child":"Comment"}]}', NULL, 0, 2, N'BO', CAST(N'2019-03-06T13:32:08.123' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (112, 42232, N'[{"email":"simo@simo.com","status":"new"}]', N'valide', 0, 1, N'VALIDATION', CAST(N'2019-03-06T13:45:16.873' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (113, 42232, N'{"value":49,"display":"Files","mapping":[{"parent":"Nom","link":"=","child":"Nom"},{"parent":"Extension","link":"=","child":"Comment"}]}', NULL, 0, 2, N'BO', CAST(N'2019-03-06T13:45:16.903' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (114, 42238, N'[{"email":"simo@simo.com","status":"new"}]', N'valide', 1, 1, N'VALIDATION', CAST(N'2019-03-06T13:54:29.663' AS DateTime), N'simo@simo.com')
GO
INSERT [dbo].[TASK] ([TASK_ID], [BO_ID], [JSON_DATA], [STATUS], [ETAT], [TASK_LEVEL], [TASK_TYPE], [CREATED_DATE], [CREATED_BY]) VALUES (115, 42238, N'{"value":49,"display":"Files","mapping":[{"parent":"Nom","link":"=","child":"Nom"},{"parent":"Extension","link":"=","child":"Comment"}]}', NULL, 1, 2, N'BO', CAST(N'2019-03-06T13:54:29.677' AS DateTime), N'simo@simo.com')
GO
SET IDENTITY_INSERT [dbo].[TASK] OFF
GO
SET IDENTITY_INSERT [dbo].[VERSIONS] ON 
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (117, 48, 1, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid={0};  DECLARE @meta_bo_id int set @meta_bo_id={4};    DECLARE @vnum int set @vnum={5};      if OBJECT_ID(''{1}'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''{1}'', ''{1}tmp'';  END;     CREATE TABLE {1} (  [BO_ID] bigint NOT NULL,  {2}  PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''{1}tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from {1}) = (select count(BO_ID) from {1}tmp) BEGIN    DROP TABLE {1}tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''{3}'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''{3}'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-07T11:48:58.323' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (118, 48, 2, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=117;  DECLARE @meta_bo_id int set @meta_bo_id=48;    DECLARE @vnum int set @vnum=1;      if OBJECT_ID(''FileTypes_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''FileTypes_BO_'', ''FileTypes_BO_tmp'';  END;     CREATE TABLE FileTypes_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''FileTypes_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from FileTypes_BO_) = (select count(BO_ID) from FileTypes_BO_tmp) BEGIN    DROP TABLE FileTypes_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-07T11:45:29.977' AS DateTime), N'simo@simo.com', CAST(N'2019-01-07T12:15:26.383' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (119, 49, 1, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid={0};  DECLARE @meta_bo_id int set @meta_bo_id={4};    DECLARE @vnum int set @vnum={5};      if OBJECT_ID(''{1}'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''{1}'', ''{1}tmp'';  END;     CREATE TABLE {1} (  [BO_ID] bigint NOT NULL,  {2}  PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''{1}tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from {1}) = (select count(BO_ID) from {1}tmp) BEGIN    DROP TABLE {1}tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''{3}'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''{3}'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-23T11:28:51.100' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (120, 48, 3, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=118;  DECLARE @meta_bo_id int set @meta_bo_id=48;    DECLARE @vnum int set @vnum=2;      if OBJECT_ID(''FileTypes_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''FileTypes_BO_'', ''FileTypes_BO_tmp'';  END;     CREATE TABLE FileTypes_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Extension] varchar(100)  NOT NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''FileTypes_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from FileTypes_BO_) = (select count(BO_ID) from FileTypes_BO_tmp) BEGIN    DROP TABLE FileTypes_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-07T11:48:58.323' AS DateTime), N'simo@simo.com', CAST(N'2019-01-21T12:48:20.383' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (121, 49, 2, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=119;  DECLARE @meta_bo_id int set @meta_bo_id=49;    DECLARE @vnum int set @vnum=1;      if OBJECT_ID(''Files_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''Files_BO_'', ''Files_BO_tmp'';  END;     CREATE TABLE Files_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Type] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''Files_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from Files_BO_) = (select count(BO_ID) from Files_BO_tmp) BEGIN    DROP TABLE Files_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-07T11:50:40.237' AS DateTime), N'simo@simo.com', CAST(N'2019-01-23T15:13:05.973' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (122, 51, 1, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid={0};  DECLARE @meta_bo_id int set @meta_bo_id={4};    DECLARE @vnum int set @vnum={5};      if OBJECT_ID(''{1}'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''{1}'', ''{1}tmp'';  END;     CREATE TABLE {1} (  [BO_ID] bigint NOT NULL,  {2}  PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''{1}tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from {1}) = (select count(BO_ID) from {1}tmp) BEGIN    DROP TABLE {1}tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''{3}'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''{3}'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-07T12:14:03.643' AS DateTime), N'ACTIVE')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (123, 51, 2, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=122;  DECLARE @meta_bo_id int set @meta_bo_id=51;    DECLARE @vnum int set @vnum=1;      if OBJECT_ID(''Emplacement_par_default_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''Emplacement_par_default_BO_'', ''Emplacement_par_default_BO_tmp'';  END;     CREATE TABLE Emplacement_par_default_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''Emplacement_par_default_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from Emplacement_par_default_BO_) = (select count(BO_ID) from Emplacement_par_default_BO_tmp) BEGIN    DROP TABLE Emplacement_par_default_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-07T12:14:03.643' AS DateTime), NULL, CAST(N'2019-01-07T12:14:03.643' AS DateTime), N'PENDING')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (125, 48, 4, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=120;  DECLARE @meta_bo_id int set @meta_bo_id=48;    DECLARE @vnum int set @vnum=3;      if OBJECT_ID(''FileTypes_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''FileTypes_BO_'', ''FileTypes_BO_tmp'';  END;     CREATE TABLE FileTypes_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Extension] varchar(100)  NOT NULL  ,  [Emplacement] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''FileTypes_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from FileTypes_BO_) = (select count(BO_ID) from FileTypes_BO_tmp) BEGIN    DROP TABLE FileTypes_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-07T12:15:26.383' AS DateTime), N'simo@simo.com', CAST(N'2019-03-05T13:47:40.703' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (10108, 10048, 1, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid={0};  DECLARE @meta_bo_id int set @meta_bo_id={4};    DECLARE @vnum int set @vnum={5};      if OBJECT_ID(''{1}'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''{1}'', ''{1}tmp'';  END;     CREATE TABLE {1} (  [BO_ID] bigint NOT NULL,  {2}  PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''{1}tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from {1}) = (select count(BO_ID) from {1}tmp) BEGIN    DROP TABLE {1}tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''{3}'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''{3}'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-13T18:27:22.523' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (10109, 10048, 2, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=10108;  DECLARE @meta_bo_id int set @meta_bo_id=10048;    DECLARE @vnum int set @vnum=1;      if OBJECT_ID(''New_BO_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''New_BO_BO_'', ''New_BO_BO_tmp'';  END;     CREATE TABLE New_BO_BO_ (  [BO_ID] bigint NOT NULL,   [C1] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''New_BO_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from New_BO_BO_) = (select count(BO_ID) from New_BO_BO_tmp) BEGIN    DROP TABLE New_BO_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-11T16:57:50.110' AS DateTime), N'simo@simo.com', CAST(N'2019-01-13T18:27:22.523' AS DateTime), N'ACTIVE')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (10110, 10048, 3, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=10109;  DECLARE @meta_bo_id int set @meta_bo_id=10048;    DECLARE @vnum int set @vnum=2;      if OBJECT_ID(''New_BO_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''New_BO_BO_'', ''New_BO_BO_tmp'';  END;     CREATE TABLE New_BO_BO_ (  [BO_ID] bigint NOT NULL,   [C1] varchar(100)  NULL  ,  [emp] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''New_BO_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from New_BO_BO_) = (select count(BO_ID) from New_BO_BO_tmp) BEGIN    DROP TABLE New_BO_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-13T18:27:22.523' AS DateTime), NULL, CAST(N'2019-01-13T18:27:22.523' AS DateTime), N'PENDING')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (20108, 20048, 1, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid={0};  DECLARE @meta_bo_id int set @meta_bo_id={4};    DECLARE @vnum int set @vnum={5};      if OBJECT_ID(''{1}'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''{1}'', ''{1}tmp'';  END;     CREATE TABLE {1} (  [BO_ID] bigint NOT NULL,  {2}  PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''{1}tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from {1}) = (select count(BO_ID) from {1}tmp) BEGIN    DROP TABLE {1}tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''{3}'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''{3}'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-21T11:08:09.470' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (20109, 20048, 2, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=20108;  DECLARE @meta_bo_id int set @meta_bo_id=20048;    DECLARE @vnum int set @vnum=1;      if OBJECT_ID(''FileLibrary_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''FileLibrary_BO_'', ''FileLibrary_BO_tmp'';  END;     CREATE TABLE FileLibrary_BO_ (  [BO_ID] bigint NOT NULL,   [Type_de_fichier] varchar(100)  NULL  ,  [Fichier] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''FileLibrary_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from FileLibrary_BO_) = (select count(BO_ID) from FileLibrary_BO_tmp) BEGIN    DROP TABLE FileLibrary_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-17T17:18:31.780' AS DateTime), N'simo@simo.com', CAST(N'2019-01-21T11:08:09.470' AS DateTime), N'ACTIVE')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30108, 20048, 3, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=20109;  DECLARE @meta_bo_id int set @meta_bo_id=20048;    DECLARE @vnum int set @vnum=2;      if OBJECT_ID(''FileLibrary_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''FileLibrary_BO_'', ''FileLibrary_BO_tmp'';  END;     CREATE TABLE FileLibrary_BO_ (  [BO_ID] bigint NOT NULL,   [Type_de_fichier] varchar(100)  NULL  ,  [Fichier] varchar(100)  NULL  ,  [Emp] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''FileLibrary_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from FileLibrary_BO_) = (select count(BO_ID) from FileLibrary_BO_tmp) BEGIN    DROP TABLE FileLibrary_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-21T11:08:09.470' AS DateTime), NULL, CAST(N'2019-01-21T11:08:09.470' AS DateTime), N'PENDING')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30109, 30048, 1, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid={0};  DECLARE @meta_bo_id int set @meta_bo_id={4};    DECLARE @vnum int set @vnum={5};      if OBJECT_ID(''{1}'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''{1}'', ''{1}tmp'';  END;     CREATE TABLE {1} (  [BO_ID] bigint NOT NULL,  {2}  PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''{1}tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from {1}) = (select count(BO_ID) from {1}tmp) BEGIN    DROP TABLE {1}tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''{3}'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''{3}'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-21T11:24:02.180' AS DateTime), N'ACTIVE')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30110, 30048, 2, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=30109;  DECLARE @meta_bo_id int set @meta_bo_id=30048;    DECLARE @vnum int set @vnum=1;      if OBJECT_ID(''demande_daffectation_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''demande_daffectation_BO_'', ''demande_daffectation_BO_tmp'';  END;     CREATE TABLE demande_daffectation_BO_ (  [BO_ID] bigint NOT NULL,   [demandeur] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''demande_daffectation_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from demande_daffectation_BO_) = (select count(BO_ID) from demande_daffectation_BO_tmp) BEGIN    DROP TABLE demande_daffectation_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-21T11:24:02.180' AS DateTime), NULL, CAST(N'2019-01-21T11:24:02.180' AS DateTime), N'PENDING')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30111, 48, 5, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=125;  DECLARE @meta_bo_id int set @meta_bo_id=48;    DECLARE @vnum int set @vnum=4;      if OBJECT_ID(''FileTypes_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''FileTypes_BO_'', ''FileTypes_BO_tmp'';  END;     CREATE TABLE FileTypes_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Extension] varchar(100)  NOT NULL  ,  [Emplacement] varchar(100)  NULL  ,  [rtrt] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''FileTypes_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from FileTypes_BO_) = (select count(BO_ID) from FileTypes_BO_tmp) BEGIN    DROP TABLE FileTypes_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-21T12:48:20.383' AS DateTime), N'simo@simo.com', CAST(N'2019-03-05T20:46:54.310' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30112, 49, 3, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=121;  DECLARE @meta_bo_id int set @meta_bo_id=49;    DECLARE @vnum int set @vnum=2;      if OBJECT_ID(''Files_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''Files_BO_'', ''Files_BO_tmp'';  END;     CREATE TABLE Files_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Type] varchar(100)  NULL  ,  [Fichier] varchar(MAX)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''Files_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from Files_BO_) = (select count(BO_ID) from Files_BO_tmp) BEGIN    DROP TABLE Files_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-23T11:28:51.100' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T15:26:17.737' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30113, 49, 4, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=30112;  DECLARE @meta_bo_id int set @meta_bo_id=49;    DECLARE @vnum int set @vnum=3;      if OBJECT_ID(''Files_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''Files_BO_'', ''Files_BO_tmp'';  END;     CREATE TABLE Files_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Type] varchar(100)  NULL  ,  [Fichier] nvarchar(MAX)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''Files_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from Files_BO_) = (select count(BO_ID) from Files_BO_tmp) BEGIN    DROP TABLE Files_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-23T15:13:05.973' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T15:41:07.573' AS DateTime), N'OLD')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30114, 49, 5, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=30113;  DECLARE @meta_bo_id int set @meta_bo_id=49;    DECLARE @vnum int set @vnum=4;      if OBJECT_ID(''Files_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''Files_BO_'', ''Files_BO_tmp'';  END;     CREATE TABLE Files_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Type] varchar(100)  NULL  ,  [Fichier] nvarchar(MAX)  NULL  ,  [Comment] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''Files_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from Files_BO_) = (select count(BO_ID) from Files_BO_tmp) BEGIN    DROP TABLE Files_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-24T15:26:17.737' AS DateTime), N'simo@simo.com', CAST(N'2019-01-24T15:41:07.573' AS DateTime), N'ACTIVE')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30115, 49, 6, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=30114;  DECLARE @meta_bo_id int set @meta_bo_id=49;    DECLARE @vnum int set @vnum=5;      if OBJECT_ID(''Files_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''Files_BO_'', ''Files_BO_tmp'';  END;     CREATE TABLE Files_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Type] varchar(100)  NULL  ,  [Fichier] nvarchar(MAX)  NULL  ,  [Comment] varchar(100)  NULL  ,  [Order] nvarchar(MAX)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''Files_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from Files_BO_) = (select count(BO_ID) from Files_BO_tmp) BEGIN    DROP TABLE Files_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-24T15:41:07.573' AS DateTime), NULL, CAST(N'2019-01-24T15:41:07.573' AS DateTime), N'PENDING')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30116, 30049, 1, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid={0};  DECLARE @meta_bo_id int set @meta_bo_id={4};    DECLARE @vnum int set @vnum={5};      if OBJECT_ID(''{1}'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''{1}'', ''{1}tmp'';  END;     CREATE TABLE {1} (  [BO_ID] bigint NOT NULL,  {2}  PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''{1}tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from {1}) = (select count(BO_ID) from {1}tmp) BEGIN    DROP TABLE {1}tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''{3}'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''{3}'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-28T21:57:02.583' AS DateTime), N'ACTIVE')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30117, 30049, 2, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=30116;  DECLARE @meta_bo_id int set @meta_bo_id=30049;    DECLARE @vnum int set @vnum=1;      if OBJECT_ID(''Business_object_name_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''Business_object_name_BO_'', ''Business_object_name_BO_tmp'';  END;     CREATE TABLE Business_object_name_BO_ (  [BO_ID] bigint NOT NULL,   [First name] varchar(100)  NULL  ,  [Last_name] varchar(100)  NULL  ,  [Age] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''Business_object_name_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from Business_object_name_BO_) = (select count(BO_ID) from Business_object_name_BO_tmp) BEGIN    DROP TABLE Business_object_name_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-28T21:57:02.583' AS DateTime), NULL, CAST(N'2019-01-28T21:57:02.583' AS DateTime), N'PENDING')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30123, 30050, 1, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid={0};  DECLARE @meta_bo_id int set @meta_bo_id={4};    DECLARE @vnum int set @vnum={5};      if OBJECT_ID(''{1}'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''{1}'', ''{1}tmp'';  END;     CREATE TABLE {1} (  [BO_ID] bigint NOT NULL,  {2}  PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''{1}tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from {1}) = (select count(BO_ID) from {1}tmp) BEGIN    DROP TABLE {1}tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''{3}'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''{3}'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''{3}'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', NULL, N'simo@simo.com', CAST(N'2019-01-31T17:38:37.963' AS DateTime), N'ACTIVE')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (30124, 30050, 2, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=30123;  DECLARE @meta_bo_id int set @meta_bo_id=30050;    DECLARE @vnum int set @vnum=1;      if OBJECT_ID(''testDate_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''testDate_BO_'', ''testDate_BO_tmp'';  END;     CREATE TABLE testDate_BO_ (  [BO_ID] bigint NOT NULL,   [le] DateTime  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''testDate_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from testDate_BO_) = (select count(BO_ID) from testDate_BO_tmp) BEGIN    DROP TABLE testDate_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-01-31T17:38:37.963' AS DateTime), NULL, CAST(N'2019-01-31T17:38:37.963' AS DateTime), N'PENDING')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (40116, 48, 6, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=30111;  DECLARE @meta_bo_id int set @meta_bo_id=48;    DECLARE @vnum int set @vnum=5;      if OBJECT_ID(''FileTypes_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''FileTypes_BO_'', ''FileTypes_BO_tmp'';  END;     CREATE TABLE FileTypes_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Extension] varchar(100)  NOT NULL  ,  [Emplacement] varchar(100)  NULL  ,  [rtrt] varchar(100)  NULL  ,  [PlusSequence_tes] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''FileTypes_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from FileTypes_BO_) = (select count(BO_ID) from FileTypes_BO_tmp) BEGIN    DROP TABLE FileTypes_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-03-05T13:47:40.707' AS DateTime), N'simo@simo.com', CAST(N'2019-03-05T20:46:54.310' AS DateTime), N'ACTIVE')
GO
INSERT [dbo].[VERSIONS] ([VERSIONS_ID], [META_BO_ID], [NUM], [SQLQUERY], [CREATED_BY], [CREATED_DATE], [UPDATED_BY], [UPDATED_DATE], [STATUS]) VALUES (40120, 48, 7, N'Begin tran tr_commit_version;   DECLARE @vid int set @vid=40116;  DECLARE @meta_bo_id int set @meta_bo_id=48;    DECLARE @vnum int set @vnum=6;      if OBJECT_ID(''FileTypes_BO_'', ''U'') IS NOT NULL  BEGIN   exec sp_rename ''FileTypes_BO_'', ''FileTypes_BO_tmp'';  END;     CREATE TABLE FileTypes_BO_ (  [BO_ID] bigint NOT NULL,   [Nom] varchar(100)  NOT NULL  ,  [Extension] varchar(100)  NOT NULL  ,  [Emplacement] varchar(100)  NULL  ,  [rtrt] varchar(100)  NULL  ,  [PlusSequence_tes] varchar(100)  NULL  ,  [test_date] varchar(100)  NULL  ,  [test_date_1] varchar(100)  NULL  ,   PRIMARY KEY ([BO_ID])  );    DECLARE @commit int set @commit = 1;  if OBJECT_ID(''FileTypes_BO_tmp'', ''U'') IS NOT NULL  BEGIN   exec MoveFromTmp @meta_bo_id;   IF (select count(BO_ID) from FileTypes_BO_) = (select count(BO_ID) from FileTypes_BO_tmp) BEGIN    DROP TABLE FileTypes_BO_tmp;   END   ELSE BEGIN    set @commit = 0;   END  END    update versions set STATUS=''OLD'', UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where META_BO_ID=@meta_bo_id and STATUS not in(''OLD'');  update versions set STATUS=''ACTIVE'' , UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate() where VERSIONS_ID = @vid;  update META_FIELD set STATUS=''COMMITED V'' + convert(varchar,@vid), [VERSION]=@vnum where META_BO_ID = @meta_bo_id and STATUS = ''NEW'';  update META_BO set [VERSION] = @vnum, UPDATED_BY=''simo@simo.com'', UPDATED_DATE=getdate(), STATUS = ''ACTIVE v'' + convert(varchar,@vnum) where META_BO_ID = @meta_bo_id;  insert into versions(META_BO_ID, NUM, SQLQUERY, CREATED_BY, CREATED_DATE, STATUS)      values(@meta_bo_id, @vnum+1, ''[SQLQUERY]'', ''simo@simo.com'', getdate(),''PENDING'');  IF @commit = 1  BEGIN  commit tran tr_commit_version; END ELSE BEGIN  rollback tran tr_commit_version; END', N'simo@simo.com', CAST(N'2019-03-05T20:46:54.310' AS DateTime), NULL, CAST(N'2019-03-05T20:46:54.310' AS DateTime), N'PENDING')
GO
SET IDENTITY_INSERT [dbo].[VERSIONS] OFF
GO
INSERT [dbo].[WORKFLOW] ([BO_ID], [LIBELLE], [ACTIVE], [ITEMS]) VALUES (42225, N'W1', 1, N'[{"type":"bo","status":"new","precedent":null,"next":1,"value":{"value":48,"display":"FileTypes"},"locked":true,"index":0},{"type":"validation","status":"new","precedent":0,"next":2,"index":1,"value":{"metaBoId":48,"rules":[{"logic":"AND","field":{"META_FIELD_ID":103,"META_BO_ID":48,"DB_NAME":"Extension","DB_TYPE":"varchar(100)","DB_NULL":0,"GRID_NAME":"Extension","GRID_FORMAT":null,"GRID_SHOW":1,"FORM_NAME":"Extension","FORM_FORMAT":null,"FORM_TYPE":"v-text","FORM_SOURCE":null,"FORM_SHOW":1,"FORM_OPTIONAL":0,"IS_FILTER":0,"FORM_DEFAULT":null,"CREATED_BY":"simo@simo.com","CREATED_DATE":null,"UPDATED_BY":"simo@simo.com","UPDATED_DATE":null,"STATUS":"COMMITED V118","VERSION":2,"JSON_DATA":null},"condition":"=","value":"exe","status":"new"}],"validators":[{"email":"simo@simo.com","status":"new"}],"status":"valide"}},{"type":"bo","status":"new","precedent":1,"next":null,"value":{"value":49,"display":"Files","mapping":[{"parent":"Nom","link":"=","child":"Nom"},{"parent":"Extension","link":"=","child":"Comment"}]},"index":2}]')
GO
ALTER TABLE [dbo].[BO] ADD  CONSTRAINT [DF__BO__CREATED_DATE__72C60C4A]  DEFAULT (getdate()) FOR [CREATED_DATE]
GO
ALTER TABLE [dbo].[BO] ADD  CONSTRAINT [DF__BO__UPDATED_DATE__73BA3083]  DEFAULT (getdate()) FOR [UPDATED_DATE]
GO
ALTER TABLE [dbo].[BO_ROLE] ADD  CONSTRAINT [DF_BO_ROLE__READ]  DEFAULT ((0)) FOR [CAN_READ]
GO
ALTER TABLE [dbo].[BO_ROLE] ADD  CONSTRAINT [DF_BO_ROLE__WRITE]  DEFAULT ((0)) FOR [CAN_WRITE]
GO
ALTER TABLE [dbo].[BO_ROLE] ADD  DEFAULT (getdate()) FOR [CREATED_DATE]
GO
ALTER TABLE [dbo].[BO_ROLE] ADD  DEFAULT (getdate()) FOR [UPDATED_DATE]
GO
ALTER TABLE [dbo].[META_BO] ADD  CONSTRAINT [DF__META_BO__CREATED__239E4DCF]  DEFAULT (getdate()) FOR [CREATED_DATE]
GO
ALTER TABLE [dbo].[META_BO] ADD  CONSTRAINT [DF__META_BO__UPDATED__24927208]  DEFAULT (getdate()) FOR [UPDATED_DATE]
GO
ALTER TABLE [dbo].[META_FIELD] ADD  CONSTRAINT [DF__META_FIEL__DB_NU__2F10007B]  DEFAULT ((1)) FOR [DB_NULL]
GO
ALTER TABLE [dbo].[META_FIELD] ADD  CONSTRAINT [DF__META_FIEL__GRID___300424B4]  DEFAULT ((1)) FOR [GRID_SHOW]
GO
ALTER TABLE [dbo].[META_FIELD] ADD  CONSTRAINT [DF__META_FIEL__FORM___30F848ED]  DEFAULT ((1)) FOR [FORM_SHOW]
GO
ALTER TABLE [dbo].[META_FIELD] ADD  CONSTRAINT [DF_META_FIELD_FORM_OPTIONAL]  DEFAULT ((0)) FOR [FORM_OPTIONAL]
GO
ALTER TABLE [dbo].[META_FIELD] ADD  CONSTRAINT [DF_META_FIELD_IS_FILTER]  DEFAULT ((0)) FOR [IS_FILTER]
GO
ALTER TABLE [dbo].[META_FIELD] ADD  CONSTRAINT [DF__META_FIEL__CREAT__31EC6D26]  DEFAULT (getdate()) FOR [CREATED_DATE]
GO
ALTER TABLE [dbo].[META_FIELD] ADD  CONSTRAINT [DF__META_FIEL__UPDAT__32E0915F]  DEFAULT (getdate()) FOR [UPDATED_DATE]
GO
ALTER TABLE [dbo].[META_FIELD] ADD  CONSTRAINT [DF_META_FIELD_STATUS]  DEFAULT ('ACTIVE') FOR [STATUS]
GO
ALTER TABLE [dbo].[VERSIONS] ADD  DEFAULT (getdate()) FOR [CREATED_DATE]
GO
ALTER TABLE [dbo].[VERSIONS] ADD  DEFAULT (getdate()) FOR [UPDATED_DATE]
GO
ALTER TABLE [dbo].[AspNetUserClaims]  WITH CHECK ADD  CONSTRAINT [FK_dbo.AspNetUserClaims_dbo.AspNetUsers_UserId] FOREIGN KEY([UserId])
REFERENCES [dbo].[AspNetUsers] ([Id])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[AspNetUserClaims] CHECK CONSTRAINT [FK_dbo.AspNetUserClaims_dbo.AspNetUsers_UserId]
GO
ALTER TABLE [dbo].[AspNetUserLogins]  WITH CHECK ADD  CONSTRAINT [FK_dbo.AspNetUserLogins_dbo.AspNetUsers_UserId] FOREIGN KEY([UserId])
REFERENCES [dbo].[AspNetUsers] ([Id])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[AspNetUserLogins] CHECK CONSTRAINT [FK_dbo.AspNetUserLogins_dbo.AspNetUsers_UserId]
GO
ALTER TABLE [dbo].[AspNetUserRoles]  WITH CHECK ADD  CONSTRAINT [FK_dbo.AspNetUserRoles_dbo.AspNetRoles_RoleId] FOREIGN KEY([RoleId])
REFERENCES [dbo].[AspNetRoles] ([Id])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[AspNetUserRoles] CHECK CONSTRAINT [FK_dbo.AspNetUserRoles_dbo.AspNetRoles_RoleId]
GO
ALTER TABLE [dbo].[AspNetUserRoles]  WITH CHECK ADD  CONSTRAINT [FK_dbo.AspNetUserRoles_dbo.AspNetUsers_UserId] FOREIGN KEY([UserId])
REFERENCES [dbo].[AspNetUsers] ([Id])
ON DELETE CASCADE
GO
ALTER TABLE [dbo].[AspNetUserRoles] CHECK CONSTRAINT [FK_dbo.AspNetUserRoles_dbo.AspNetUsers_UserId]
GO
ALTER TABLE [dbo].[META_FIELD]  WITH CHECK ADD  CONSTRAINT [FK__META_FIEL__META___33D4B598] FOREIGN KEY([META_BO_ID])
REFERENCES [dbo].[META_BO] ([META_BO_ID])
GO
ALTER TABLE [dbo].[META_FIELD] CHECK CONSTRAINT [FK__META_FIEL__META___33D4B598]
GO
ALTER TABLE [dbo].[VERSIONS]  WITH CHECK ADD  CONSTRAINT [FK__VERSIONS__META_B__4BAC3F29] FOREIGN KEY([META_BO_ID])
REFERENCES [dbo].[META_BO] ([META_BO_ID])
GO
ALTER TABLE [dbo].[VERSIONS] CHECK CONSTRAINT [FK__VERSIONS__META_B__4BAC3F29]
GO
/****** Object:  StoredProcedure [dbo].[cleanMetaBo]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--/****** Script de la commande SelectTopNRows à partir de SSMS  ******/
--SELECT * from VERSIONS where META_BO_ID=11


--select * from META_FIELD where META_BO_ID=11

--select * from VIEW_KA_BO_





CREATE procedure [dbo].[cleanMetaBo]
as
delete from META_FIELD where META_BO_ID not in (select META_BO_ID from META_BO where STATUS ='-1')
delete from VERSIONS where META_BO_ID not in (select META_BO_ID from META_BO where STATUS ='-1')
delete from META_BO where STATUS <>'-1'
delete from bo
GO
/****** Object:  StoredProcedure [dbo].[DYNAMIC_SELECT]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[DYNAMIC_SELECT]
	@META_BO_ID int
AS
DECLARE @selecta nvarchar(max) set @selecta = ' SELECT '
	+ ( select STRING_AGG(DB_NAME, ',')  	from META_FIELD  	where META_BO_ID=@META_BO_ID  	AND STATUS not like '%deleted%' )
	+ ' FROM ' 
	+ (select BO_DB_NAME from META_BO where META_BO_ID=@META_BO_ID);
exec sp_executesql @selecta
GO
/****** Object:  StoredProcedure [dbo].[InitMetaBo]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[InitMetaBo]
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
/****** Object:  StoredProcedure [dbo].[INSERT_BO_LIGNES]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[INSERT_BO_LIGNES]
	@nbrLignes int,
	@BO_NAME varchar(100)
AS

	Declare @req nvarchar(MAX);
	DECLARE @cnt INT = 0;
	DECLARE @BO_ID INT = 0;
	DECLARE @META_BO_ID int = 0;
		select @META_BO_ID = META_BO_ID from META_BO where META_BO.BO_DB_NAME = @BO_NAME;

	if @META_BO_ID = 0 BEGIN	
		set @nbrLignes = 0;
	END
	DECLARE @currentVersion int;
		select @currentVersion=[VERSION] from META_BO where META_BO_ID= @META_BO_ID;
		

	WHILE @cnt < @nbrLignes
	BEGIN

	   INSERT INTO [dbo].[BO]
			   ([CREATED_BY]
			   ,[CREATED_DATE]
			   ,[UPDATED_BY]
			   ,[UPDATED_DATE]
			   ,[STATUS]
			   ,[BO_TYPE]
			   ,[VERSION])
		 VALUES
			   ('sys'
			   ,getdate()
			   ,'sys'
			   ,getdate()
			   ,'1'
			   ,@META_BO_ID
			   ,@currentVersion
			   )
		
		SELECT @BO_ID = SCOPE_IDENTITY();  
		set @req = N'insert into ' + @BO_NAME + N'(BO_ID) values('+ convert(varchar,@BO_ID)+N') ';
		exec sp_executesql @req;
			   
	   SET @cnt = @cnt + 1;
END;


GO
/****** Object:  StoredProcedure [dbo].[MoveBoToCurrentVersion]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<SimoRML>
-- Create date: <02-12-2018>
-- Description:	<Move BO from old table version to the current version (FOR UPDATE) >
-- =============================================
CREATE PROCEDURE [dbo].[MoveBoToCurrentVersion]
	@BO_ID bigint
AS
BEGIN
	print '-----MoveBoToCurrentVersion-----';
	print '@BO_ID : ' + convert(varchar,@BO_ID);
	DECLARE @metBoId int;
	DECLARE @boVersion int;
		select @metBoId=BO_TYPE, @boVersion=[VERSION] from BO where BO_ID = @BO_ID;
	
	DECLARE @currentVersion int;
	DECLARE @boDbName varchar(100);
		select @boDbName = BO_DB_NAME, @currentVersion=[VERSION] from META_BO where META_BO_ID= @metBoId;
	DECLARE @currentTable varchar(100) set @currentTable = @boDbName + convert(varchar, @currentVersion);
	DECLARE @boTable varchar(100) set @boTable = @boDbName + convert(varchar, @boVersion);

	print '@metBoId : ' + convert(varchar,@metBoId);
	print '@boDbName : ' + @boDbName;
	print '@boVersion : ' + convert(varchar,@boVersion);
	print '@boTable : ' + @boTable;
	print '@currentVersion : ' + convert(varchar,@currentVersion);
	print '@currentTable : ' + @currentTable;

	IF @boVersion != @currentVersion BEGIN
		
		DECLARE @oneField varchar(100);
		DECLARE @fields varchar(MAX) set @fields = 'BO_ID';
		
		
		DECLARE fields_cursor CURSOR FOR 
			select DB_NAME from META_FIELD where META_BO_ID = @metBoId AND [VERSION] <= @boVersion AND FORM_TYPE not like 'subform-%';

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
			set @insertStatement = 'insert into ' + @currentTable + '('+@fields+') select * from '+@boTable+' where BO_ID=' + convert(varchar,@BO_ID);
		print '@@insertStatement : ' + @insertStatement;

		Declare @deleteStatement nvarchar(MAX);
			set @deleteStatement = 'delete from '+@boTable+' where BO_ID=' + convert(varchar,@BO_ID);
		print '@@deleteStatement  : ' + @deleteStatement ;

		BEGIN TRAN TR_SWITCH;
			exec sp_executesql @insertStatement;
			exec sp_executesql @deleteStatement;
			update BO set [VERSION]=@currentVersion where BO_ID = @BO_ID;
		COMMIT TRAN TR_SWITCH;
	END
	print '--------------------------------';
END
GO
/****** Object:  StoredProcedure [dbo].[MoveFromTmp]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<SimoRML>
-- Create date: <02-12-2018>
-- Description:	<Move BO from old table version to the current version (FOR UPDATE) >
-- =============================================
CREATE PROCEDURE [dbo].[MoveFromTmp]
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
/****** Object:  StoredProcedure [dbo].[PlusSequenceNextID]    Script Date: 16-Mar-19 16:09:24 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<SimoRML>
-- Create date: <08/02/2019>
-- Description:	<Identity by source (ex: BLABLA_513)>
-- =============================================
CREATE PROCEDURE [dbo].[PlusSequenceNextID]
	@cle varchar(500),
	@TableName varchar(500),
	@stepBy int
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

	update PlusSequence set CurrentValue = @CurrentValue where SequenceID = @SequenceID;

	select convert(varchar,@CurrentValue);
END
GO
