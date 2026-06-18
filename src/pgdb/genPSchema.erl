%%%-------------------------------------------------------------------
%%% @doc Schema 代码生成器。
%%% 扫描 schema 目录下的所有 *_schema.erl 模块，生成：
%%%   1. 每个 *_schema.erl 对应一个 .hrl 文件（包含其中所有表的 record/type 声明）
%%%   2. 一个统一的静态 schema 模块（默认为 ttt.erl），提供 getTables/0, tableSchema/1, fieldSchema/2 等接口供运行时查询。
%%%   示例: genPSchema:generate("./src/schema", dbSchemaDef,  "./src/schema", "./include", "./include").
%%%-------------------------------------------------------------------
-module(genPSchema).

-include("pgdbSchema.hrl").

%% 一行的最大长度，用于对齐注释
-define(LineChar, 72).


-export([main/1, gen/0, gen/6]).

%%% ===================================================================
%%% escript 入口
%%% ===================================================================
main(Args) ->
	io:format("start gen schema: ~p~n", [Args]),
	{SchemaDir, SchemaMod, CacheMod, SrcDir, HrlDir, IncludeDirs} = parseArgs(Args),
	case gen(SchemaDir, SchemaMod, CacheMod, SrcDir, HrlDir, IncludeDirs) of
		ok -> ok;
		{error, Reason} ->
			io:format("Error: ~p~n", [Reason]),
			erlang:halt(1)
	end.

parseArgs([SchemaDir, SchemaModStr, CacheModStr, SrcDir, HrlDir | IncludeDirs]) ->
	{SchemaDir, list_to_atom(SchemaModStr), list_to_atom(CacheModStr), SrcDir, HrlDir, IncludeDirs};
parseArgs(_) ->
	{"./test/schema", dbSchemaDef, cacheTabDef, "./test", "./test", ["./include"]}.

gen() ->
	% 示例调用
	gen("./test/schema", dbSchemaDef, cacheTabDef, "./test", "./test", ["./include"]).

gen(SchemaDir, SchemaMod, CacheMod, SrcDir, HrlDir, IncludeDirs) ->
	AbsIncludes = [{i, filename:absname(IncludeDir)} || IncludeDir <- IncludeDirs],
	case collectAllSchemas(SchemaDir, AbsIncludes) of
		{ok, SchemaGroups} ->
			ok = generateHrlFiles(SchemaGroups, HrlDir),
			ok = generateSchemaModule(SchemaGroups, SchemaMod, SrcDir),
			CacheMod =/= undefined andalso (ok = generateCacheModule(SchemaGroups, CacheMod, SrcDir)),
			AllTables = lists:flatmap(fun(#{tables := Tables}) -> Tables end, SchemaGroups),
			io:format("Generated ~p tables from ~p schema files into ~s and ~s/~s.erl~n", [length(AllTables), length(SchemaGroups), HrlDir, SrcDir, SchemaMod]),
			ok;
		{error, _} = Err ->
			Err
	end.

%%% ===================================================================
%%% 收集所有 schema
%%% ===================================================================
collectAllSchemas(SchemaDir, AbsIncludes) ->
	Pattern = filename:join(SchemaDir, "*_schema.erl"),
	Files = filelib:wildcard(Pattern),
	collectFromFiles(Files, AbsIncludes, []).

collectFromFiles([], _AbsIncludes, Acc) ->
	{ok, lists:reverse(Acc)};
collectFromFiles([File | Rest], AbsIncludes, Acc) ->
	{ok, Module} = compileAndLoadSchema(File, AbsIncludes),
	Exports = Module:module_info(exports),
	HrlHead = getSchemaHead(Module, hrl_head, Exports),
	ErlHead = getSchemaHead(Module, erl_head, Exports),
	Tables = [{Table, Schema} || {Table, 0} <- Exports, Schema <- [Module:Table()], is_record(Schema, schema)],
	BaseName = filename:basename(File, ".erl"),
	Group = #{base_name => BaseName, tables => Tables, hrl_head => HrlHead, erl_head => ErlHead},
	collectFromFiles(Rest, AbsIncludes, [Group | Acc]).

getSchemaHead(Module, FunName, Exports) ->
	case lists:member({FunName, 0}, Exports) of
		true -> unicode:characters_to_binary(Module:FunName());
		false -> <<>>
	end.

compileAndLoadSchema(File, AbsIncludes) ->
	case compile:file(File, [binary, report] ++ AbsIncludes) of
		{ok, Module, Binary} ->
			loadAndExtract(Module, File, Binary);
		{ok, Module, Binary, _Warnings} ->
			loadAndExtract(Module, File, Binary);
		Error ->
			{error, {compile_failed, File, Error}}
	end.

loadAndExtract(Module, File, Binary) ->
	code:purge(Module),
	case code:load_binary(Module, File, Binary) of
		{module, Module} ->
			{ok, Module};
		{error, Reason} ->
			{error, {load_failed, Module, Reason}}
	end.

%%% ===================================================================
%%% 生成 .hrl 文件
%%% ===================================================================
generateHrlFiles(SchemaGroups, HrlDir) ->
	ok = filelib:ensure_dir(filename:join(HrlDir, "dummy")),
	[
		begin
			BaseName = maps:get(base_name, Group),
			Tables = maps:get(tables, Group),
			HrlHead = maps:get(hrl_head, Group),
			HrlFile = filename:join(HrlDir, BaseName ++ ".hrl"),
			Content = renderSchemaHrl(BaseName, Tables, HrlHead),
			file:write_file(HrlFile, unicode:characters_to_binary(Content))
		end || Group <- SchemaGroups
	],
	ok.

renderSchemaHrl(BaseName, Tables, HrlHead) ->
	Guard = string:uppercase(BaseName ++ "_HRL"),
	Header = io_lib:format(
		"%%%-------------------------------------------------------------------\n"
		"%%% @doc ~s 定义汇总\n"
		"%%% 此文件由 genPSchema 自动生成，请勿手动修改。\n"
		"%%%-------------------------------------------------------------------\n"
		"-ifndef(~s).\n"
		"-define(~s, true).\n\n", [BaseName, Guard, Guard]),
	Bodies = [renderOneTableDef(TableName, Schema) || {TableName, Schema} <- Tables],
	Footer = <<"\n-endif.\n">>,
	HrlHeadStr = case HrlHead of <<>> -> <<>>; _ -> <<HrlHead/binary, "\n\n">> end,
	[unicode:characters_to_binary(Header, utf8), HrlHeadStr, Bodies, Footer].

renderOneTableDef(TableName, #schema{repr = Repr, comment = Comment, fields = Fields}) ->
	CommentLine = unicode:characters_to_binary(Comment, utf8),
	Body = case Repr of record -> renderRecordDef(TableName, Fields); map -> [renderMapTypeDef(TableName, Fields), renderMapValueDef(TableName, Fields)] end,
	[<<"%%">>, CommentLine, "\n", Body].

renderRecordDef(TableName, Fields) ->
	<<_:56, FieldLines/binary>> = renderRecordFields(Fields),
	<<"-record(", (toBinary(TableName))/binary, ", {\n    ", FieldLines/binary, "\n}).\n\n">>.

renderRecordFields(Fields) ->
	<<<<(renderOneRecordField(OneField, Fields))/binary>> || OneField <- Fields>>.

renderOneRecordField(#schField{name = Name, default = Default, erlType = ErlType, dbType = DbType, comment = Comment}, Fields) ->
	IdDefStr =
		case Default of
			undefined -> <<"    , ", (toBinary(Name))/binary>>;
			_ -> <<"    , ", (toBinary(Name))/binary, " = ", (iolist_to_binary(io_lib:format("~0p", [Default])))/binary>>
		end,
	
	TypeStr =
		case ErlType == "" orelse ErlType == <<>> of
			true -> unicode:characters_to_binary(inferErlType(DbType), utf8);
			_ -> unicode:characters_to_binary(ErlType, utf8)
		end,
	
	CommentPart =
		case Comment of
			"" -> <<"">>;
			_ -> unicode:characters_to_binary(Comment, utf8)
		end,
	
	[#schField{name = FirstName} | _] = Fields,
	
	SpaceSize = max(4, ?LineChar - (byte_size(IdDefStr) + byte_size(TypeStr))) + case Name == FirstName of true -> 2; false -> 0 end,
	SpaceStr = list_to_binary(lists:duplicate(SpaceSize, " ")),
	<<"\n", IdDefStr/binary, " :: ", TypeStr/binary, SpaceStr/binary, "%% ", CommentPart/binary>>.

renderMapTypeDef(TableName, Fields) ->
	<<_:56, FieldLines/binary>> = renderMapFields(Fields),
	<<"-type ", (toBinary(TableName))/binary, "() :: #{\n    ", FieldLines/binary, "\n}.\n\n">>.

renderMapFields(Fields) ->
	<<<<(renderOneMapField(OneField, Fields))/binary>> || OneField <- Fields>>.

renderOneMapField(#schField{name = Name, erlType = ErlType, dbType = DbType, comment = Comment}, Fields) ->
	IdStr = <<"    , ", (toBinary(Name))/binary>>,
	
	TypeStr =
		case ErlType == "" orelse ErlType == <<>> of
			true -> unicode:characters_to_binary(inferErlType(DbType), utf8);
			_ -> unicode:characters_to_binary(ErlType, utf8)
		end,
	
	CommentPart =
		case Comment of
			"" -> <<"">>;
			_ -> unicode:characters_to_binary(Comment, utf8)
		end,
	
	[#schField{name = FirstName} | _] = Fields,
	SpaceSize = max(4, ?LineChar - (byte_size(IdStr) + byte_size(TypeStr))) + case Name == FirstName of true -> 2; false -> 0 end,
	SpaceStr = list_to_binary(lists:duplicate(SpaceSize, " ")),
	<<"\n", IdStr/binary, " => ", TypeStr/binary, SpaceStr/binary, "%% ", CommentPart/binary>>.

renderMapValueDef(TableName, Fields) ->
	<<_:56, FieldLines/binary>> = renderMapVFields(Fields),
	<<"-define(", (toBinary(TableName))/binary, "_map(), #{\n    ", FieldLines/binary, "\n}).\n\n">>.

renderMapVFields(Fields) ->
	<<<<(renderOneMapVField(OneField, Fields))/binary>> || OneField <- Fields>>.

renderOneMapVField(#schField{name = Name, default = Default, comment = Comment}, Fields) ->
	IdStr = <<"    , ", (toBinary(Name))/binary>>,
	
	DefaultStr =
		case Default of
			undefined -> <<"undefined">>;
			_ -> iolist_to_binary(io_lib:format("~0p", [Default]))
		end,
	
	CommentPart =
		case Comment of
			"" -> <<"">>;
			_ -> unicode:characters_to_binary(Comment, utf8)
		end,
	
	[#schField{name = FirstName} | _] = Fields,
	SpaceSize = max(4, ?LineChar - (byte_size(IdStr) + byte_size(DefaultStr))) + case Name == FirstName of true -> 2; false -> 0 end,
	SpaceStr = list_to_binary(lists:duplicate(SpaceSize, " ")),
	
	<<"\n", IdStr/binary, " => ", DefaultStr/binary, SpaceStr/binary, "%% ", CommentPart/binary>>.

%%% ===================================================================
%%% Erlang 类型推导
%%% ===================================================================

inferErlType(integer) -> "integer()";
inferErlType(int) -> "integer()";
inferErlType(bigint) -> "integer()";
inferErlType(smallint) -> "integer()";
inferErlType(serial) -> "integer()";
inferErlType(bigserial) -> "integer()";
inferErlType(float) -> "float()";
inferErlType(double) -> "float()";
inferErlType({numeric, _, _}) -> "number()";
inferErlType(text) -> "binary()";
inferErlType({varchar, _}) -> "binary()";
inferErlType({char, _}) -> "binary()";
inferErlType(uuid) -> "binary()";
inferErlType(inet) -> "binary()";
inferErlType(boolean) -> "boolean()";
inferErlType(bool) -> "boolean()";
inferErlType(json) -> "map()";
inferErlType(jsonb) -> "map()";
inferErlType(bytea) -> "binary()";
inferErlType(timestamp) -> "binary()";
inferErlType(timestamptz) -> "binary()";
inferErlType(date) -> "binary()";
inferErlType(time) -> "binary()";
inferErlType({enum, atom}) -> "atom()";
inferErlType({enum, binary}) -> "binary()";
inferErlType({array, Inner}) -> "[" ++ inferErlType(Inner) ++ "]";
inferErlType(_) -> "term()".

%%% ===================================================================
%%% 生成静态模块
%%% ===================================================================

generateSchemaModule(AllTables, Module, OutputDir) ->
	OutputFile = filename:join(OutputDir, atom_to_list(Module) ++ ".erl"),
	Content = renderSchemaModule(Module, AllTables),
	ok = filelib:ensure_dir(OutputFile),
	file:write_file(OutputFile, unicode:characters_to_binary(Content)).

renderSchemaModule(Module, SchemaGroups) ->
	ErlHead = renderSchemaModuleHead(SchemaGroups),
	GetTables = renderGetTables(SchemaGroups),
	TableFields = renderTableFields(SchemaGroups),
	InsertSql = renderInsertSql(SchemaGroups),
	ReplaceSql = renderReplaceSql(SchemaGroups),
	OnReplaceSql = renderOnReplaceSql(SchemaGroups),
	TableSchema = renderTableSchema(SchemaGroups),
	TableTablePrimaryKey = renderTablePrimaryKey(SchemaGroups),
	FieldSchema = renderFieldSchema(SchemaGroups),
	
	ModuleHead = io_lib:format(
		"%%%-------------------------------------------------------------------\n"
		"%%% @doc 此文件由 genPSchema 自动生成，请勿手动修改。\n"
		"%%%-------------------------------------------------------------------\n"
		"-module(~s).\n\n", [Module]),
	
	BaseDefHead =
		"-compile([nowarn_unused_record, nowarn_unused_function]).\n\n"
		"-export([getTables/0, tableFields/1, tableInsert/1, tableReplace/1, onReplace/1, tableSchema/1, tablePrimaryKey/1, fieldSchema/2, fieldCodec/2, fieldDefault/2]).\n\n"
		"-record(schema, {\n"
		"	repr = map,          %% record | map - Erlang 端数据表示方式\n"
		"	comment = \"\",        %% string()|binary() - 表注释\n"
		"	tbCache = undefined, %% undefined | #tbCache{}  缓存配置\n"
		"	fields = []          %% [#schField{}]\n"
		"})."
		"\n\n"
		"-record(schField, {\n"
		"	name,                %% atom()     - 字段名\n"
		"	dbType,              %% term()     - 数据库类型: integer | {varchar, 64} | jsonb | ...\n"
		"	default = undefined, %% term()     - 默认值, undefined 表示无默认值\n"
		"	opts = [],           %% [term()]   - 约束: [primary_key, not_null, unique, ...]\n"
		"	codec = undefined,   %% undefined | json | term_str | term_binary | atom - 编解码策略\n"
		"	erlType = \"\",        %% string()   - Erlang 类型声明字符串, \"\" 则从 dbType 推导\n"
		"	comment = \"\"         %% string()|binary() - 注释 (同时用于代码和数据库)\n"
		"})."
		"\n\n"
		"-record(tbCache, {\n"
		"	type = whole,         %% whole | hotData  whole- 全表缓存，启动时将整张表数据加载到 ETS  热数据缓存，仅缓存被访问过的数据，同时维护全量 keys ETS\n"
		"	ttl = 0,              %% non_neg_integer() hotData 缓存 TTL（秒），0=永不淘汰\n"
		"	saveMode = 300,       %% pos_integer() 如果需要立即存库的表 就把时间配置短一点 (单位毫秒)\n"
		"	saveType = whole,     %% whole | dirty whole落盘时写入整行数据（使用 upsert） dirty 落盘时仅写入脏字段（需配合 eCas:update/3 使用）\n"
		"	loadFun = undefined,  %% undefined | {M, F, A}  undefined  - 使用通用加载逻辑（全量扫描 DB） {M, F, A}  - 自定义初始化加载函数，调用 M:F(Table, A...) 如果是whole Data就是整条数据 否则就是KeyValue\n"
		"	flushLimit = 500,     %% non_neg_integer() 每轮落盘条数上限，infinity=全量 每轮 flush 最多处理的脏 key 数，infinity 表示一次性刷完整张状态表\n"
		"	isOrder = false       %% true 是否为order_set 可能有些表需要保持访问顺序，true 则使用 order_set 作为 ETS 类型，false 则使用 set\n"
		"})."
		"\n\n",
	
	FunConvert =
		"tableFields(Table) -> tableFields_(toAtom(Table)).\n"
		"tableInsert(Table) -> tableInsert_(toAtom(Table)).\n"
		"tableReplace(Table) -> tableReplace_(toAtom(Table)).\n"
		"onReplace(Table) -> onReplace_(toAtom(Table)).\n"
		"tableSchema(Table) -> tableSchema_(toAtom(Table)).\n"
		"tablePrimaryKey(Table) -> tablePrimaryKey_(toAtom(Table)).\n"
		"fieldSchema(Table, Field) -> fieldSchema_(toAtom(Table), toAtom(Field)).\n\n",
	
	FieldDef =
		"fieldCodec(Table, Field) ->\n"
		"	case fieldSchema_(toAtom(Table), toAtom(Field)) of\n"
		"		#schField{codec = Codec} -> Codec;\n"
		"	_ -> undefined\n"
		"end.\n\n"
		"fieldDefault(Table, Field) ->\n"
		"	case fieldSchema_(toAtom(Table), toAtom(Field)) of\n"
		"		#schField{default = Default} -> Default;\n"
		"	_ -> undefined\n"
		"end.\n\n"
		"toAtom(Value) when is_atom(Value) -> Value;\n"
		"toAtom(Value) when is_binary(Value) -> binary_to_atom(Value, utf8);\n"
		"toAtom(Value) when is_list(Value) -> list_to_atom(Value).\n\n",
	
	[ModuleHead, BaseDefHead, ErlHead, FunConvert, GetTables, TableFields, InsertSql, ReplaceSql, OnReplaceSql, TableSchema, TableTablePrimaryKey, FieldSchema, FieldDef].

renderSchemaModuleHead(SchemaGroups) ->
	Heads = [OHead || #{erl_head := OHead} <- SchemaGroups, OHead =/= <<>>],
	case Heads of
		[] -> <<>>;
		_ ->
			THead = <<<<Head/binary, "\n">> || Head <- Heads>>,
			<<THead/binary, "\n">>
	end.

renderGetTables(SchemaGroups) ->
	TAllTables = <<<<"\n        %", (toBinary(Module))/binary, "\n       ", (makeTableList(Tables))/binary>> || #{base_name := Module, tables := Tables} <- SchemaGroups, Tables /= []>>,
	AllTables =
		case TAllTables /= <<>> andalso binary:last(TAllTables) of
			$, ->
				binary:part(TAllTables, 0, byte_size(TAllTables) - 1);
			_ ->
				TAllTables
		end,
	<<"getTables() ->\n    [", AllTables/binary, "\n    ].\n\n">>.

makeTableList([]) -> <<>>;
makeTableList(Tables) ->
	iolist_to_binary(lists:join(",", [" " ++ atom_to_list(Table) || {Table, _} <- Tables]) ++ ",").

renderTableSchema(SchemaGroups) ->
	BodyStr = <<<<"tableSchema_(", (toBinary(Table))/binary, ") -> ", (renderOneTableSchema(Table, Schema))/binary, ";\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, Schema} <- TablesSchema>>,
	<<BodyStr/binary, "tableSchema_(_) -> undefined.\n\n">>.

renderOneTableSchema(Table, #schema{repr = Type, comment = TComment, fields = Fields}) ->
	SchemaHead = <<"\n\t#schema{\n\t\trepr = ", (toBinary(Type))/binary, ", comment = \"", (unicode:characters_to_binary(TComment))/binary, "\",\n\t\tfields = [">>,
	TSchemaFields = <<<<"\n\t\t\t#schField{name = ", (toBinary(Name))/binary, ", dbType = ", (iolist_to_binary(io_lib:format("~0p", [DbType])))/binary, ", default = ", (iolist_to_binary(io_lib:format("~0p", [Default])))/binary, ", opts = ", (dealOpts(Table, Name, Default, Codec, Opts))/binary, ", codec = ", (termToBinary(Codec))/binary, ", erlType = \"", (erlType(ErlType, DbType))/binary, "\", comment = \"", (unicode:characters_to_binary(Comment))/binary, "\"},">> || #schField{name = Name, dbType = DbType, erlType = ErlType, default = Default, opts = Opts, codec = Codec, comment = Comment} <- Fields>>,
	SchemaFields =
		case binary:last(TSchemaFields) of
			$, ->
				binary:part(TSchemaFields, 0, byte_size(TSchemaFields) - 1);
			_ ->
				TSchemaFields
		end,
	<<SchemaHead/binary, SchemaFields/binary, "\n\t\t]\n\t}">>.

renderTablePrimaryKey(SchemaGroups) ->
	BodyStr = <<<<"tablePrimaryKey_(", (toBinary(Table))/binary, ") -> ", (renderOneTablePrimaryKey(Fields))/binary, ";\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, #schema{fields = Fields}} <- TablesSchema>>,
	<<BodyStr/binary, "tablePrimaryKey_(_) -> [].\n\n">>.

getTabPrimaryKeys(Fields) ->
	[Name || #schField{name = Name, opts = FieldOpts} <- Fields, lists:member(primary_key, FieldOpts)].

renderOneTablePrimaryKey(Fields) ->
	PrimaryKeys = getTabPrimaryKeys(Fields),
	iolist_to_binary(io_lib:format("~0p", [PrimaryKeys])).

renderTableFields(SchemaGroups) ->
	BodyStr = <<<<"tableFields_(", (toBinary(Table))/binary, ") -> [", (renderOneTableFields(Table, Schema))/binary, "];\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, Schema} <- TablesSchema>>,
	<<BodyStr/binary, "tableFields_(_) -> [].\n\n">>.

renderOneTableFields(_Table, #schema{repr = Type, fields = Fields}) ->
	InitIndex = case Type of record -> 2; map -> 1 end,
	{_FieldIndex, FieldList} = lists:foldl(fun(#schField{name = Name}, {Index, Acc}) -> {Index + 1, [{Name, Index} | Acc]} end, {InitIndex, []}, Fields),
	<<_:8, TSchemaFields/binary>> = <<<<",{<<\"", (toBinary(Name))/binary, "\">>, ", (integer_to_binary(proplists:get_value(Name, FieldList)))/binary, ", ", (termToBinary(Codec))/binary, ", ", (toBinary(Name))/binary, "}">> || #schField{name = Name, codec = Codec} <- Fields>>,
	TSchemaFields.

renderInsertSql(SchemaGroups) ->
	BodyStr = <<<<"tableInsert_(", (toBinary(Table))/binary, ") -> <<\"", (renderOneInsertSql(Table, Schema))/binary, "\">>;\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, Schema} <- TablesSchema>>,
	<<BodyStr/binary, "tableInsert_(_) -> undefined.\n\n">>.

renderOneInsertSql(Table, #schema{fields = Fields}) ->
	TableSql = toBinary(Table),
	FieldCnt = length(Fields),
	<<_:16, VALUESArgs/binary>> = <<<<", $", (integer_to_binary(Index))/binary>> || Index <- lists:seq(1, FieldCnt)>>,
	<<"INSERT INTO \\\"", TableSql/binary, "\\\" VALUES (", VALUESArgs/binary, ")">>.

renderReplaceSql(SchemaGroups) ->
	BodyStr = <<<<"tableReplace_(", (toBinary(Table))/binary, ") -> <<\"", (renderOneReplaceSql(Table, Schema))/binary, "\">>;\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, Schema} <- TablesSchema>>,
	<<BodyStr/binary, "tableReplace_(_) -> undefined.\n\n">>.

renderOneReplaceSql(Table, #schema{fields = Fields}) ->
	TableSql = toBinary(Table),
	FieldCnt = length(Fields),
	<<_:16, VALUESArgs/binary>> = <<<<", $", (integer_to_binary(Index))/binary>> || Index <- lists:seq(1, FieldCnt)>>,
	PrimaryKeys = getTabPrimaryKeys(Fields),
	<<_:16, OnKeyFiled/binary>> = <<<<", ", (toBinary(OneKeyCol))/binary>> || OneKeyCol <- PrimaryKeys>>,
	UpdateCols = [Name || #schField{name = Name} <- Fields, not lists:member(Name, PrimaryKeys)],
	<<_:16, ExcludedSql/binary>> = <<<<", ", (toBinary(Col))/binary, " = EXCLUDED.", (toBinary(Col))/binary>> || Col <- UpdateCols>>,
	<<"INSERT INTO \\\"", TableSql/binary, "\\\" VALUES (", VALUESArgs/binary, ") ON CONFLICT(", OnKeyFiled/binary, ") DO UPDATE SET ", ExcludedSql/binary, " ">>.

renderOnReplaceSql(SchemaGroups) ->
	BodyStr = <<<<"onReplace_(", (toBinary(Table))/binary, ") -> <<\"", (renderOneOnReplaceSql(Table, Schema))/binary, "\">>;\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, Schema} <- TablesSchema>>,
	<<BodyStr/binary, "onReplace_(_) -> undefined.\n\n">>.

renderOneOnReplaceSql(_Table, #schema{fields = Fields}) ->
	PrimaryKeys = getTabPrimaryKeys(Fields),
	<<_:16, OnKeyFiled/binary>> = <<<<", ", (toBinary(OneKeyCol))/binary>> || OneKeyCol <- PrimaryKeys>>,
	UpdateCols = [Name || #schField{name = Name} <- Fields, not lists:member(Name, PrimaryKeys)],
	<<_:16, ExcludedSql/binary>> = <<<<", ", (toBinary(Col))/binary, " = EXCLUDED.", (toBinary(Col))/binary>> || Col <- UpdateCols>>,
	<<" ON CONFLICT(", OnKeyFiled/binary, ") DO UPDATE SET ", ExcludedSql/binary, " ">>.

renderFieldSchema(SchemaGroups) ->
	BodyStr = <<<<(renderOneFieldSchema(Table, Schema))/binary>> || #{tables := TablesSchema} <- SchemaGroups, {Table, Schema} <- TablesSchema>>,
	<<BodyStr/binary, "fieldSchema_(_, _) -> undefined.\n\n">>.

renderOneFieldSchema(Table, #schema{fields = Fields}) ->
	<<<<"fieldSchema_(", (toBinary(Table))/binary, ", ", (toBinary(Name))/binary, ") -> #schField{name = ", (toBinary(Name))/binary, ", dbType = ", (iolist_to_binary(io_lib:format("~0p", [DbType])))/binary, ", default = ", (iolist_to_binary(io_lib:format("~0p", [Default])))/binary, ", opts = ", (dealOpts(Table, Name, Default, Codec, Opts))/binary, ", codec = ", (termToBinary(Codec))/binary, ", erlType = \"", (erlType(ErlType, DbType))/binary, "\", comment = \"", (unicode:characters_to_binary(Comment))/binary, "\"};\n">> || #schField{name = Name, dbType = DbType, erlType = ErlType, default = Default, opts = Opts, codec = Codec, comment = Comment} <- Fields>>.

dealOpts(Table, Name, Default, Codec, Opts) ->
	iolist_to_binary(io_lib:format("~0p", [filterDdlOpts(maybeAddDefaultOpt(Table, Name, Default, Codec, Opts))])).

erlType(ErlType, DbType) ->
	case ErlType == "" orelse ErlType == <<>> of
		true -> unicode:characters_to_binary(inferErlType(DbType), utf8);
		_ -> unicode:characters_to_binary(ErlType, utf8)
	end.


toBinary(Value) when is_binary(Value) -> Value;
toBinary(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
toBinary(Value) when is_list(Value) -> iolist_to_binary(Value).

termToBinary(Term) ->
	unicode:characters_to_binary(io_lib:format("~0tp", [Term])).

%% @doc 过滤 DDL 列定义选项，只保留 PostgreSQL DDL 识别的约束。
filterDdlOpts(Opts) ->
	[Opt || Opt <- Opts, isDdlOpt(Opt)].

maybeAddDefaultOpt(_Table, _Name, undefined, _Codec, Opts) ->
	Opts;
maybeAddDefaultOpt(_Table, _Name, _Default, ?codec_temp, Opts) ->
	Opts;
maybeAddDefaultOpt(_Table, _Name, _Default, ?codec_custom(_M, _F, _A), Opts) ->
	Opts;
maybeAddDefaultOpt(Table, Name, Default, Codec, Opts) ->
	case lists:keyfind(default, 1, Opts) of
		false -> [{default, ePgdb:enCodecValue(Codec, Table, Name, Default)} | Opts];
		_ -> Opts
	end.

isDdlOpt(primary_key) -> true;
isDdlOpt(not_null) -> true;
isDdlOpt(unique) -> true;
isDdlOpt({default, _}) -> true;
isDdlOpt({references, _}) -> true;
isDdlOpt({check, _}) -> true;
isDdlOpt(_) -> false.

generateCacheModule(AllTables, Module, OutputDir) ->
	OutputFile = filename:join(OutputDir, atom_to_list(Module) ++ ".erl"),
	Content = renderCacheModule(Module, AllTables),
	ok = filelib:ensure_dir(OutputFile),
	file:write_file(OutputFile, unicode:characters_to_binary(Content)).

renderCacheModule(Module, SchemaGroups) ->
	CacheTables = renderCacheTables(SchemaGroups),
	TableCache = renderTableCache(SchemaGroups),
	TableFields = renderCacheFields(SchemaGroups),
	TableTablePrimaryKey = renderTablePrimaryKey(SchemaGroups),
	CacheType = renderCacheType(SchemaGroups),
	SaveType = renderSaveType(SchemaGroups),
	KeyValue = renderKeyValue(SchemaGroups),
	DirtyValue = renderDirtyValue(SchemaGroups),
	ModuleHead = io_lib:format(
		"%%%-------------------------------------------------------------------\n"
		"%%% @doc 此文件由 genPSchema 自动生成，请勿手动修改。\n"
		"%%%-------------------------------------------------------------------\n"
		"-module(~s).\n\n", [Module]),
	
	BaseDefHead =
		"-compile([nowarn_unused_record, nowarn_unused_function]).\n\n"
		"-export([getCaches/0, tableCache/1, tableFields/1, tablePrimaryKey/1, cacheType/1, saveType/1, keyValue/2, dirtyIndex/1]).\n\n"
		"-record(schema, {\n"
		"	repr = map,          %% record | map - Erlang 端数据表示方式\n"
		"	comment = \"\",        %% string()|binary() - 表注释\n"
		"	tbCache = undefined, %% undefined | #tbCache{}  缓存配置\n"
		"	fields = []          %% [#schField{}]\n"
		"})."
		"\n\n"
		"-record(schField, {\n"
		"	name,                %% atom()     - 字段名\n"
		"	dbType,              %% term()     - 数据库类型: integer | {varchar, 64} | jsonb | ...\n"
		"	default = undefined, %% term()     - 默认值, undefined 表示无默认值\n"
		"	opts = [],           %% [term()]   - 约束: [primary_key, not_null, unique, ...]\n"
		"	codec = undefined,   %% undefined | json | term_str | term_binary | atom - 编解码策略\n"
		"	erlType = \"\",        %% string()   - Erlang 类型声明字符串, \"\" 则从 dbType 推导\n"
		"	comment = \"\"         %% string()|binary() - 注释 (同时用于代码和数据库)\n"
		"})."
		"\n\n"
		"-record(tbCache, {\n"
		"	type = whole,         %% whole | hotData  whole- 全表缓存，启动时将整张表数据加载到 ETS  热数据缓存，仅缓存被访问过的数据，同时维护全量 keys ETS\n"
		"	ttl = 0,              %% non_neg_integer() hotData 缓存 TTL（秒），0=永不淘汰\n"
		"	saveMode = 300,       %% pos_integer() 如果需要立即存库的表 就把时间配置短一点 (单位毫秒)\n"
		"	saveType = whole,     %% whole | dirty whole落盘时写入整行数据（使用 upsert） dirty 落盘时仅写入脏字段（需配合 eCas:update/3 使用）\n"
		"	loadFun = undefined,  %% undefined | {M, F, A}  undefined  -  {M, F, A}  - 自定义初始化加载时对对每条数据执行的函数，调用 M:F(Data, A...) 如果是whole Data就是整条数据 否则就是KeyValue\n"
		"	flushLimit = 500,     %% non_neg_integer() 每轮落盘条数上限，infinity=全量 每轮 flush 最多处理的脏 key 数，infinity 表示一次性刷完整张状态表\n"
		"	isOrder = false       %% true 是否为order_set 可能有些表需要保持访问顺序，true 则使用 order_set 作为 ETS 类型，false 则使用 set\n"
		"})."
		"\n\n",
	
	FunConvert =
		"tableCache(Table) -> tableCache_(toAtom(Table)).\n"
		"tableFields(Table) -> tableFields_(toAtom(Table)).\n"
		"tablePrimaryKey(Table) -> tablePrimaryKey_(toAtom(Table)).\n"
		"cacheType(Table) -> cacheType_(toAtom(Table)).\n"
		"saveType(Table) -> saveType_(toAtom(Table)).\n"
		"keyValue(Table, Data) -> keyValue_(toAtom(Table), Data).\n"
		"dirtyIndex(Table) -> dirtyIndex_(toAtom(Table)).\n\n",
	
	FieldDef =
		"toAtom(Value) when is_atom(Value) -> Value;\n"
		"toAtom(Value) when is_binary(Value) -> binary_to_atom(Value, utf8);\n"
		"toAtom(Value) when is_list(Value) -> list_to_atom(Value).\n\n",
	
	[ModuleHead, BaseDefHead, FunConvert, CacheTables, TableCache, TableFields, TableTablePrimaryKey, CacheType, SaveType, KeyValue, DirtyValue, FieldDef].


renderCacheTables(SchemaGroups) ->
	TAllTables = <<<<"\n        %", (toBinary(Module))/binary, "\n       ", (makeTableList(CacheTabes))/binary>> || #{base_name := Module, tables := Tables} <- SchemaGroups, CacheTabes <- [[OneTable || {_Table, #schema{tbCache = TbCache}} = OneTable <- Tables, is_record(TbCache, tbCache)]], CacheTabes /= []>>,
	AllTables =
		case TAllTables /= <<>> andalso binary:last(TAllTables) of
			$, ->
				binary:part(TAllTables, 0, byte_size(TAllTables) - 1);
			_ ->
				TAllTables
		end,
	<<"getCaches() ->\n    [", AllTables/binary, "\n    ].\n\n">>.

renderTableCache(SchemaGroups) ->
	BodyStr = <<<<"tableCache_(", (toBinary(Table))/binary, ") -> ", (renderOneTableCache(TbCache))/binary>> || #{tables := TablesSchema} <- SchemaGroups, {Table, #schema{tbCache = TbCache}} <- TablesSchema, is_record(TbCache, tbCache)>>,
	<<BodyStr/binary, "tableCache_(_) -> undefined.\n\n">>.

renderOneTableCache(#tbCache{type = Type, ttl = TTL, saveMode = SaveMode, saveType = SaveType, loadFun = LoadFun, flushLimit = FlushLimit, isOrder = IsOrder}) ->
	<<"#tbCache{type = ", (toBinary(Type))/binary, ", ttl = ", (integer_to_binary(TTL))/binary, ", saveMode = ", (iolist_to_binary(io_lib:format("~0p", [SaveMode])))/binary, ", saveType = ", (iolist_to_binary(io_lib:format("~0p", [SaveType])))/binary, ", loadFun = ", (iolist_to_binary(io_lib:format("~0p", [LoadFun])))/binary, ", flushLimit = ", (iolist_to_binary(io_lib:format("~0p", [FlushLimit])))/binary, ", isOrder = ", (toBinary(IsOrder))/binary, "};\n">>.

renderCacheFields(SchemaGroups) ->
	BodyStr = <<<<"tableFields_(", (toBinary(Table))/binary, ") -> ", (renderOneCacheFields(Table, Schema))/binary, ";\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, #schema{tbCache = TbCache} = Schema} <- TablesSchema, is_record(TbCache, tbCache)>>,
	<<BodyStr/binary, "tableFields_(_) -> [].\n\n">>.

renderOneCacheFields(_Table, #schema{repr = Type, fields = Fields}) ->
	InitIndex = case Type of record -> 2; map -> 1 end,
	{_FieldIndex, FieldList} = lists:foldl(fun(#schField{name = Name}, {Index, Acc}) -> {Index + 1, [{Index, 1 bsl (Index - 1), Name} | Acc]} end, {InitIndex, []}, Fields),
	iolist_to_binary(io_lib:format("~0p", [lists:reverse(FieldList)])).

renderCacheType(SchemaGroups) ->
	BodyStr = <<<<"cacheType_(", (toBinary(Table))/binary, ") -> ", (atom_to_binary(TbCache#tbCache.type))/binary, ";\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, #schema{tbCache = TbCache}} <- TablesSchema, is_record(TbCache, tbCache)>>,
	<<BodyStr/binary, "cacheType_(_) -> undefined.\n\n">>.

renderSaveType(SchemaGroups) ->
	BodyStr = <<<<"saveType_(", (toBinary(Table))/binary, ") -> ", (atom_to_binary(TbCache#tbCache.saveType))/binary, ";\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, #schema{tbCache = TbCache}} <- TablesSchema, is_record(TbCache, tbCache)>>,
	<<BodyStr/binary, "saveType_(_) -> undefined.\n\n">>.


renderKeyValue(SchemaGroups) ->
	BodyStr = <<<<"keyValue_(", (toBinary(Table))/binary, ", Data) -> ", (renderOneTablePrimaryKey(Repr, Fields, 2))/binary, ";\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, #schema{repr = Repr, tbCache = TbCache, fields = Fields}} <- TablesSchema, is_record(TbCache, tbCache)>>,
	<<BodyStr/binary, "keyValue_(_, _) -> undefined.\n\n">>.

%% 只能查找第一个 primary_key 字段
renderOneTablePrimaryKey(Repr, Fields, Index) ->
	{FieldName, FieldIndex} = lookFirstPrimaryKey(Fields, Fields, Index),
	case Repr of
		record -> <<"element(", (integer_to_binary(FieldIndex))/binary, ", Data)">>;
		map -> <<"maps:get(", (toBinary(FieldName))/binary, ", Data)">>
	end.
lookFirstPrimaryKey([], AllFields, _Index) ->
	[#schField{name = Name} | _] = AllFields,
	{Name, 2};
lookFirstPrimaryKey([#schField{name = Name, opts = FieldOpts} | Fields], AllFields, Index) ->
	case lists:member(primary_key, FieldOpts) of
		false ->
			lookFirstPrimaryKey(Fields, AllFields, Index + 1);
		true ->
			{Name, Index}
	end.

renderDirtyValue(SchemaGroups) ->
	BodyStr = <<<<"dirtyIndex_(", (toBinary(Table))/binary, ") -> ", (renderOneDirtyValue(Repr, Fields, 2))/binary, ";\n">> || #{tables := TablesSchema} <- SchemaGroups, {Table, #schema{repr = Repr, tbCache = TbCache, fields = Fields}} <- TablesSchema, is_record(TbCache, tbCache)>>,
	<<BodyStr/binary, "dirtyIndex_(_) -> 0.\n\n">>.

%% 只能查找第一个 primary_key 字段
renderOneDirtyValue(_Repr, Fields, Index) ->
	DirtyIndex = lookDirtyValue(Fields, Fields, Index),
	integer_to_binary(DirtyIndex).

lookDirtyValue([], _AllFields, _Index) ->
	0;
lookDirtyValue([#schField{name = Name} | Fields], AllFields, Index) ->
	case dirty_flag == Name of
		true ->
			Index;
		_ ->
			lookDirtyValue(Fields, AllFields, Index + 1)
	end.
