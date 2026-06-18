%%%-------------------------------------------------------------------
%%% @doc ePgdb - 面向 Erlang 游戏服的灵活 PostgreSQL 工具库。
%%%
%%% 功能概览：
%%%   - DDL：建表、删表、字段增删改、索引管理
%%%   - CRUD：插入、查询、更新、删除、upsert
%%%   - 批量操作：batchInsert、batchUpdate
%%%   - 灵活条件：支持比较、IN、BETWEEN、LIKE、JSONB 查询、OR 分组
%%%   - 事务支持：自动提交与回滚
%%%   - 表结构同步：syncSchema
%%%   - JSONB 读写辅助
%%%   - Schema 自省
%%%   - 迁移系统
%%%-------------------------------------------------------------------
-module(ePgdb).

-include("ePgdb.hrl").
-include("pgdbSchema.hrl").

-define(pgdbPool, '$pgdbPool').
-define(migrationLockKey, 90421001).
-define(queryTimeOut, 60000).
-define(slowThreshold, 10000).

-export([
	%% 启动
	start/6,
	stop/0,
	poolStatus/0,

	%% 表操作
	createTable/1,
	createTable/2,
	dropTable/1,
	truncateTable/1,
	renameTable/2,
	syncCheckSchema/1,
	syncSchema/1,
	tableExists/1,
	schema/1,
	schemas/0,
	fieldSchema/2,

	%% 字段操作
	addColumn/3, addColumn/4,
	dropColumn/2,
	renameColumn/3,
	alterColumnType/3,
	getColumns/1,
	columnExists/2,

	%% 索引操作
	addIndex/2, addIndex/3,
	dropIndex/1,
	primaryKeys/1,
	uniqueKeys/1,
	foreignKeys/1,
	indexes/1,
	tableKeys/1,

	%% CRUD
	insert/1, insert/2, insertC/2, insertC/3, insertR/1, insertR/2, insertCR/2, insertCR/3,
	select/2, select/3, select/4, selectSql/3,
	selectPage/4, selectPage/5,
	get/2, get/3, get/4,
	update/3, update/4,
	delete/2, delete/3,
	upsert/3, upsert/4,

	%% 批量操作
	batchInsert/1, batchInsert/2, batchInsert/3,
	batchUpdate/1, batchUpdate/2,
	batchDelByKey/3, batchDelByKey/4,

	%% 聚合
	count/1, count/2,
	sum/2, sum/3,

	%% 分页扫描
	foreachRows/4, foreachRows/5,
	foldRows/5, foldRows/6,
	foreachByKey/5, foreachByKey/6,
	foldByKey/6, foldByKey/7,

	%% JSONB 辅助
	jsonbSet/4, jsonbSet/5,
	jsonbGet/3, jsonbGet/4,
	jsonbDelete/3, jsonbDelete/4,
	jsonbMerge/4,

	%% 事务与原生查询
	transaction/1, transaction/2,
	withConnection/1,
	ddl/1, ddl/2,
	query/1, query/2, query/3,

	%% 迁移与自省
	migrate/1,
	rollback/2,
	status/0, status/1,
	tables/0,
	describe/1,

	%% 调试/压测辅助
	rowToWholeData/2,
	rowToMap/3,
	decodeFields/2,
	testFawSync/1,

	%% 编码解码相关
	enCodecValue/4,
	deCodecValue/4,
	enWheres/2,
	demo_custom_codec/5
]).

%%%===================================================================
%% 启动
%%%===================================================================

%% @doc 启动 ePgdb 运行时依赖并创建数据库连接池。
%% Host/Port/User/Password/Database 为数据库连接参数；PoolArgs 同时承载 eFaw 参数和启动期控制项。
-spec start(dbHost(), dbPort(), dbUser(), dbPassword(), dbName(), [poolArg()]) -> {ok, pid()} | {error, term()}.
start(Host, Port, User, Password, Database, PoolArgs) when is_list(PoolArgs) ->
	maybe
		{ok, _Started} ?= application:ensure_all_started(ePgdb),
		ok ?= ensureDatabase(Host, Port, User, Password, Database, PoolArgs),
		{ok, Pid} ?= openPool(Host, Port, User, Password, Database, PoolArgs),
		FilterFun = pgdbUtils:getOpt(filterFun, PoolArgs, undefined),
		case syncCheckSchema(FilterFun) of
			ok ->
				SlowThreshold = pgdbUtils:getOpt(slowThreshold, PoolArgs, ?slowThreshold),
				persistent_term:put('$slowThreshold', SlowThreshold),
				FilterFun /= undefined andalso persistent_term:put('$filterFun', FilterFun),
				{ok, Pid};
			{error, Reason} ->
				eFaw:closeF(?pgdbPool),
				?PgErr("start the pgdb pool failed ~p~n", [Reason]),
				{error, {schemaSyncFailed, Reason}}
		end
	else
		Err ->
			?PgErr("start the pgdb pool error ~p~n", [Err]),
			{error, Err}
	end.

openPool(Host, Port, User, Password, Database, PoolArgs) ->
	WArgs = pgdbUtils:getOpt(wArgs, PoolArgs, []),
	LWArgs = [{host, Host}, {port, Port}, {database, Database}, {username, User}, {password, Password}, {timeout, 5000} | WArgs],
	LPoolArgs = lists:keystore(wMod, 1, lists:keystore(wArgs, 1, PoolArgs, {wArgs, LWArgs}), {wMod, pgdbWorker}),
	case erlang:whereis(?pgdbPool) of
		Pid when is_pid(Pid) ->
			{ok, Pid};
		undefined ->
			case eFaw:openPool(?pgdbPool, LPoolArgs) of
				{error, {already_started, Pid}} ->
					{ok, Pid};
				Other ->
					Other
			end
	end.

%% 保证目标数据库存在
ensureDatabase(Host, Port, User, Password, Database, PoolArgs) ->
	WArgs = pgdbUtils:getOpt(wArgs, PoolArgs, []),
	UseSsl = pgdbUtils:getOpt(ssl, WArgs, false),
	ConnOpts = #{host => Host, port => Port, database => "postgres", username => User, password => Password, timeout => 5000},
	ConnectOpts = case UseSsl of true -> ConnOpts#{ssl => true, ssl_opts => pgdbUtils:getOpt(sslOpts, WArgs, [])};_ -> ConnOpts end,
	DatabaseBin = pgdbUtils:makeName(Database),
	case epgsql:connect(ConnectOpts) of
		{ok, Conn} ->
			try
				case pgdbUtils:isValidName(DatabaseBin) of
					true ->
						case epgsql:equery(Conn, <<"SELECT 1 FROM pg_database WHERE datname = $1">>, [DatabaseBin]) of
							{ok, _, []} ->
								case epgsql:squery(Conn, [<<"CREATE DATABASE ">>, pgdbUtils:quoteIdent(DatabaseBin)]) of
									{ok, _, _} -> ok;
									{error, #{code := <<"42P04">>}} -> ok;
									{error, CreateErr} -> {error, {create_database_failed, CreateErr}}
								end;
							{ok, _, [_ | _]} ->
								ok;
							{error, QueryErr} ->
								{error, {check_database_exists_failed, QueryErr}}
						end;
					_ ->
						{error, {invalid_database_name, Database}}
				end
			after
				epgsql:close(Conn)
			end;
		{error, ConnErr} ->
			{error, {connect_database_failed, ConnErr}}
	end.


-spec stop() -> ok | {error, term()}.
stop() ->
	eFaw:closePool(?pgdbPool),
	application:stop(ePgdb).

%% @doc 查询连接池状态信息。
-spec poolStatus() -> {ok, map()} | {error, term()}.
poolStatus() ->
	try
		WorkerCount = ?pgdbPool:getV(wFCnt),
		Counts = supervisor:count_children(?pgdbPool),
		{_, ActiveWorkers} = lists:keyfind(workers, 1, Counts),
		{ok, #{
			fawName => ?pgdbPool,
			workerCount => WorkerCount,
			activeWorkers => ActiveWorkers
		}}
	catch
		Class:Reason ->
			{error, {poolNotStart, Class, Reason}}
	end.

%% @doc 表的同步 检查：确保所有 schema 定义的表都存在且字段类型匹配；表不存在则建表，字段缺失则补齐，类型不一致则变更。返回 {error, {schema_sync_failed, Table, Reason}} 以指示具体失败的表和原因。
-spec syncCheckSchema(term()) -> ok | {error, term()}.
syncCheckSchema(FilterFun) ->
	try
		Tables = dbSchemaDef:getTables(),
		[syncSchema(OneTable) || OneTable <- Tables, filterTable(FilterFun, OneTable)],
		ok
	catch C:R:S ->
		{error, {C, R, S}}
	end.

filterTable({M, F}, Table) -> M:F(Table);
filterTable(_, _Table) -> true.

%% @doc 保证表结构存在；表不存在则建表，字段缺失则补齐，类型不一致则变更。
-spec syncSchema(name()) -> ok | {error, term()}.
syncSchema(Table) ->
	#schema{fields = Fields} = dbSchemaDef:tableSchema(Table),
	case tableExists(Table) of
		true ->
			{ok, ExistingCols} = getColumnInfo(Table),
			case validateJustAppendOnly(Table, Fields, ExistingCols) of
				ok ->
					[
						begin
							FieldName = pgdbUtils:makeName(OFieldName),
							case lists:keyfind(FieldName, 1, ExistingCols) of
								false -> ?CASE(addColumn(Table, FieldName, ODbType, OOpts), ok, ok, Err, throw(Err));
								{FieldName, ExistingType} ->
									case pgTypeMatches(ODbType, ExistingType) of
										false -> ?CASE(ok == alterColumnType(Table, FieldName, ODbType), ok, throw({error, {alter_column_type_failed, Table, FieldName, ODbType, ExistingType}}));
										_ ->
											ok
									end
							end
						end || #schField{name = OFieldName, dbType = ODbType, opts = OOpts} <- Fields
					],
					ok;
				{error, Reason} ->
					throw({error, {validateJustAppendOnlyFailed, Table, Reason}})
			end;
		false ->
			createTable(Table);
		Err ->
			throw({error, {table_exists_failed, Table, Err}})
	end.

%%%===================================================================
%%% 表操作
%%%===================================================================

%% @doc 按字段定义创建表。
-spec createTable(name()) -> ok | {error, term()}.
createTable(Table) ->
	#schema{fields = Fields} = dbSchemaDef:tableSchema(Table),
	createTable(Table, Fields).

%% @doc 按给定字段列表创建表。
-spec createTable(name(), [#schField{}]) -> ok | {error, term()}.
createTable(Table, Fields) ->
	SQL = pgdbQuery:buildCreateTable(Table, Fields),
	case execDdl(SQL) of
		ok ->
			try autoCreateIndexes(Table, Fields)
			catch C:R:S ->
				{error, {auto_create_indexes_failed, Table, C, R, S}}
			end;
		{error, _} = Err -> Err
	end.

%% @doc 删除表。
-spec dropTable(name()) -> ok | {error, term()}.
dropTable(Table) ->
	SQL = [<<"DROP TABLE IF EXISTS ">>, pgdbUtils:makeName(Table), <<" CASCADE">>],
	execDdl(SQL).

%% @doc 清空表数据。
-spec truncateTable(name()) -> ok | {error, term()}.
truncateTable(Table) ->
	execDdl(pgdbQuery:buildTruncateTable(Table)).

%% @doc 重命名表。
-spec renameTable(name(), name()) -> ok | {error, term()}.
renameTable(Table, NewName) ->
	execDdl(pgdbQuery:buildRenameTable(Table, NewName)).

%% @doc 判断表是否存在。
-spec tableExists(name()) -> boolean().
tableExists(Table) ->
	SQL = <<"SELECT 1 FROM information_schema.tables WHERE table_name = $1 LIMIT 1">>,
	case equery(SQL, [pgdbUtils:makeName(Table)]) of
		{ok, _, []} -> false;
		{ok, _, [_ | _]} -> true;
		{error, _} = Err -> Err
	end.

%% @doc 获取表 schema。
-spec schema(name()) -> #schema{} | undefined.
schema(Table) ->
	dbSchemaDef:tableSchema(Table).

%% @doc 获取所有表 schema。
-spec schemas() -> [#schema{}].
schemas() ->
	[dbSchemaDef:tableSchema(Table) || Table <- dbSchemaDef:getTables()].

%% @doc 获取字段 schema。
-spec fieldSchema(name(), fieldName()) -> #schField{} | undefined.
fieldSchema(Table, Field) ->
	dbSchemaDef:fieldSchema(Table, Field).

%%%===================================================================
%%% 字段操作
%%%===================================================================

%% @doc 添加字段。
-spec addColumn(name(), fieldName(), term()) -> ok | {error, term()}.
addColumn(Table, ColName, Type) ->
	addColumn(Table, ColName, Type, []).

%% @doc 添加字段并附带默认值或约束。
-spec addColumn(name(), fieldName(), term(), [addColumnOpt()]) -> ok | {error, term()}.
addColumn(Table, ColName, Type, Opts) ->
	NormalizedOpts = normalizeAddColumnOpts(Opts),
	case execDdl(pgdbQuery:buildAddColumn(Table, ColName, Type, NormalizedOpts)) of
		ok -> ?CASE(ok == maybeCreateAddColumnIndex(Table, ColName, NormalizedOpts), ok, {error, {create_add_column_index_failed, Table, ColName}});
		{error, _} = Err -> {error, {addColumn, ColName, Type, Opts, Err}}
	end.

%% @doc 删除字段。
-spec dropColumn(name(), fieldName()) -> ok | {error, term()}.
dropColumn(Table, ColName) ->
	execDdl(pgdbQuery:buildDropColumn(Table, ColName)).

%% @doc 重命名字段。
-spec renameColumn(name(), fieldName(), fieldName()) -> ok | {error, term()}.
renameColumn(Table, OldName, NewName) ->
	execDdl(pgdbQuery:buildRenameColumn(Table, OldName, NewName)).

%% @doc 修改字段类型。
-spec alterColumnType(name(), fieldName(), term()) -> ok | {error, term()}.
alterColumnType(Table, ColName, NewType) ->
	execDdl(pgdbQuery:buildAlterColumnType(Table, ColName, NewType)).

%% @doc 查询表现有字段名 -> data_type 映射。
getColumnInfo(Table) ->
	SQL = <<"SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 ORDER BY ordinal_position">>,
	case equery(SQL, [pgdbUtils:makeName(Table)]) of
		{ok, _Cols, Rows} ->
			{ok, Rows};
		{error, Reason} ->
			throw({schema_introspection_failed, Table, column_info, Reason})
	end.

%% @doc 获取表字段信息。
-spec getColumns(name()) -> {ok, [rowMap()]} | {error, term()}.
getColumns(Table) ->
	SQL = <<"SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name = $1 ORDER BY ordinal_position">>,
	case equery(SQL, [pgdbUtils:makeName(Table)]) of
		{ok, _Cols, Rows} -> {ok, Rows};
		{error, _} = Err -> Err
	end.

%% @doc 判断字段是否存在。
-spec columnExists(name(), fieldName()) -> boolean().
columnExists(Table, ColName) ->
	SQL = <<"SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2)">>,
	case equery(SQL, [pgdbUtils:makeName(Table), pgdbUtils:makeName(ColName)]) of
		{ok, _, [{true}]} -> true;
		_ -> false
	end.

%%%===================================================================
%%% 索引操作
%%%===================================================================

%% @doc 为字段列表创建索引。
-spec addIndex(name(), [fieldName()]) -> ok | {error, term()}.
addIndex(Table, Columns) ->
	addIndex(Table, Columns, []).

%% @doc 带参数创建索引。
-spec addIndex(name(), [fieldName()], [indexOpt()]) -> ok | {error, term()}.
addIndex(Table, Columns, Opts) ->
	SQL = pgdbQuery:buildAddIndex(Table, Columns, Opts),
	execDdl(SQL).

%% @doc 删除索引。
-spec dropIndex(name()) -> ok | {error, term()}.
dropIndex(IndexName) ->
	SQL = [<<"DROP INDEX IF EXISTS ">>, pgdbUtils:makeName(IndexName)],
	execDdl(SQL).

%% @doc 返回主键字段列表。
-spec primaryKeys(name()) -> {ok, [binary()]} | {error, term()}.
primaryKeys(Table) ->
	SQL = <<"SELECT kcu.column_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema WHERE tc.table_schema = 'public' AND tc.table_name = $1 AND tc.constraint_type = 'PRIMARY KEY' ORDER BY kcu.ordinal_position">>,
	case equery(SQL, [pgdbUtils:makeName(Table)]) of
		{ok, _, Rows} -> {ok, [Column || {Column} <- Rows]};
		{error, _} = Err -> Err
	end.

%% @doc 返回唯一键约束列表。
-spec uniqueKeys(name()) -> {ok, [map()]} | {error, term()}.
uniqueKeys(Table) ->
	SQL = <<"SELECT tc.constraint_name, kcu.column_name FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema WHERE tc.table_schema = 'public' AND tc.table_name = $1 AND tc.constraint_type = 'UNIQUE' ORDER BY tc.constraint_name, kcu.ordinal_position">>,
	case equery(SQL, [pgdbUtils:makeName(Table)]) of
		{ok, _, Rows} -> {ok, groupNamedColumns(Rows)};
		{error, _} = Err -> Err
	end.

%% @doc 返回外键约束列表。
-spec foreignKeys(name()) -> {ok, [map()]} | {error, term()}.
foreignKeys(Table) ->
	SQL = <<"SELECT tc.constraint_name, kcu.column_name, ccu.table_name AS referenced_table, ccu.column_name AS referenced_column FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema WHERE tc.table_schema = 'public' AND tc.table_name = $1 AND tc.constraint_type = 'FOREIGN KEY' ORDER BY tc.constraint_name, kcu.ordinal_position">>,
	case equery(SQL, [pgdbUtils:makeName(Table)]) of
		{ok, _, Rows} -> {ok, groupForeignKeys(Rows)};
		{error, _} = Err -> Err
	end.

%% @doc 返回索引元数据。
-spec indexes(name()) -> {ok, [map()]} | {error, term()}.
indexes(Table) ->
	SQL = <<"SELECT i.relname AS index_name, ix.indisunique, ix.indisprimary, am.amname AS method, string_agg(a.attname, ',' ORDER BY cols.ord) AS columns FROM pg_class t JOIN pg_namespace n ON n.oid = t.relnamespace JOIN pg_index ix ON t.oid = ix.indrelid JOIN pg_class i ON i.oid = ix.indexrelid JOIN pg_am am ON am.oid = i.relam JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY AS cols(attnum, ord) ON true JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = cols.attnum WHERE n.nspname = 'public' AND t.relname = $1 GROUP BY i.relname, ix.indisunique, ix.indisprimary, am.amname ORDER BY i.relname">>,
	case equery(SQL, [pgdbUtils:makeName(Table)]) of
		{ok, _, Rows} ->
			{ok, [#{name => IndexName, unique => Unique, primary => Primary, method => Method, columns => splitCsvBinary(Columns)} || {IndexName, Unique, Primary, Method, Columns} <- Rows]};
		{error, _} = Err -> Err
	end.

%% @doc 返回表上的所有 key 元数据，包含主键、唯一键、外键和索引。
-spec tableKeys(name()) -> {ok, map()} | {error, term()}.
tableKeys(Table) ->
	case {primaryKeys(Table), uniqueKeys(Table), foreignKeys(Table), indexes(Table)} of
		{{ok, Primary}, {ok, Unique}, {ok, Foreign}, {ok, Indexes}} -> {ok, #{primary_keys => Primary, unique_keys => Unique, foreign_keys => Foreign, indexes => Indexes}};
		{{error, _} = Err, _, _, _} -> Err;
		{_, {error, _} = Err, _, _} -> Err;
		{_, _, {error, _} = Err, _} -> Err;
		{_, _, _, {error, _} = Err} -> Err
	end.

%%%===================================================================
%%% CRUD
%%%===================================================================

%% @doc 插入一条记录。
-spec insert(map() | tuple(), boolean()) -> ok | {error, term()}.
insert(Data) -> insert(Data, true).
insert(Data, IsDoUpdate) ->
	Table = ?CASE(is_tuple(Data), element(1, Data), maps:get(table_name, Data)),
	Params = enWholeData(Table, Data),
	SQL = case IsDoUpdate of true -> dbSchemaDef:tableReplace(Table); _ -> dbSchemaDef:tableInsert(Table) end,
	case equery(SQL, Params) of
		{ok, _} -> ok;
		{ok, _, _Cols, _Rows} -> ok;
		{error, _} = Err -> Err
	end.

%% @doc 在事务连接中插入一条记录。
-spec insertC(pid(), map() | tuple(), boolean()) -> ok | {error, term()}.
insertC(Conn, Data) -> insertC(Conn, Data, true).
insertC(Conn, Data, IsDoUpdate) ->
	Table = ?CASE(is_tuple(Data), element(1, Data), maps:get(table_name, Data)),
	Params = enWholeData(Table, Data),
	SQL = case IsDoUpdate of true -> dbSchemaDef:tableReplace(Table); _ -> dbSchemaDef:tableInsert(Table) end,
	case dbEquery(Conn, SQL, Params) of
		{ok, _} -> ok;
		{ok, _, _Cols, _Rows} -> ok;
		{error, _} = Err -> Err
	end.

-spec insertR(map() | tuple(), boolean()) -> {ok, rowMap()} | {error, term()}.
insertR(Data) -> insertR(Data, false).
insertR(Data, IsDoUpdate) ->
	Table = ?CASE(is_tuple(Data), element(1, Data), maps:get(table_name, Data)),
	Params = enWholeData(Table, Data),
	SQL = case IsDoUpdate of true -> dbSchemaDef:tableReplace(Table); _ -> dbSchemaDef:tableInsert(Table) end,
	case equery([SQL, <<" RETURNING *">>], Params) of
		{ok, _, _Cols, [Row]} -> {ok, rowToWholeData(Table, Row)};
		{error, _} = Err -> Err
	end.


-spec insertCR(pid(), map() | tuple(), boolean()) -> {ok, rowMap()} | {error, term()}.
insertCR(Conn, Data) -> insertCR(Conn, Data, true).
insertCR(Conn, Data, IsDoUpdate) ->
	Table = ?CASE(is_tuple(Data), element(1, Data), maps:get(table_name, Data)),
	Params = enWholeData(Table, Data),
	SQL = case IsDoUpdate of true -> dbSchemaDef:tableReplace(Table); _ -> dbSchemaDef:tableInsert(Table) end,
	case dbEquery(Conn, [SQL, <<" RETURNING *">>], Params) of
		{ok, _, _Cols, [Row]} -> {ok, rowToWholeData(Table, Row)};
		{error, _} = Err -> Err
	end.

%% @doc 查询多条记录。
-spec select(name(), whereClause()) -> {ok, [rowMap()]} | {error, term()}.
select(Table, Where) ->
	select(Table, Where, []).

-spec select(name(), whereClause(), [selectOpt()]) -> {ok, [rowMap()]} | {error, term()}.

select(Table, Where, Opts) ->
	EnWheres = enWheres(Table, Where),
	{SQL, Params, IsWhole} = pgdbQuery:buildSelect(Table, EnWheres, Opts),
	case equery(SQL, Params) of
		{ok, Cols, Rows} -> decodeSelectRows(Table, IsWhole, Cols, Rows);
		{error, _} = Err -> Err
	end.

select(Conn, Table, Where, Opts) ->
	EnWheres = enWheres(Table, Where),
	{SQL, Params, IsWhole} = pgdbQuery:buildSelect(Table, EnWheres, Opts),
	case dbEquery(Conn, SQL, Params) of
		{ok, Cols, Rows} -> decodeSelectRows(Table, IsWhole, Cols, Rows);
		{error, _} = Err -> Err
	end.

selectSql(Table, Where, Opts) ->
	EnWheres = enWheres(Table, Where),
	{SQL, Params, _IsWhole} = pgdbQuery:buildSelect(Table, EnWheres, Opts),
	{iolist_to_binary(SQL), Params}.

decodeSelectRows(Table, IsWhole, Cols, Rows) ->
	case IsWhole andalso dbSchemaDef:tableSchema(Table) of
		#schema{repr = Type, fields = Fields} ->
			case Type of
				map ->
					{ok, [loopDeMapData(Fields, Row, 1, Table, #{}) || Row <- Rows]};
				record ->
					TableAtom = pgdbUtils:toAtom(Table),
					{ok, [loopDeRecordData(Fields, Row, 1, Table, 2, [{1, TableAtom}]) || Row <- Rows]}
			end;
		_ ->
			DecodeFields = decodeFields(Table, Cols),
			{ok, [loopRowsToMap(DecodeFields, Row, 1, Table, #{}) || Row <- Rows]}
	end.

%% @doc 查询指定页的数据，返回分页元信息和结果集。
-spec selectPage(name(), whereClause(), pos_integer(), pos_integer()) -> {ok, pageResult()} | {error, term()}.
selectPage(Table, Where, Page, PageSize) ->
	selectPage(Table, Where, Page, PageSize, []).

-spec selectPage(name(), whereClause(), pos_integer(), pos_integer(), [pageOpt()]) -> {ok, pageResult()} | {error, term()}.
selectPage(_Table, _Where, Page, PageSize, _Opts) when Page =< 0; PageSize =< 0 ->
	{error, invalid_page_args};
selectPage(Table, Where, Page, PageSize, Opts) ->
	CountTotal = proplists:get_value(count_total, Opts, false),
	Offset = (Page - 1) * PageSize,
	QueryOpts = setOpt(offset, Offset, setOpt(limit, PageSize, removeOpt(count_total, Opts))),
	case select(Table, Where, QueryOpts) of
		{ok, Rows0} ->
			case CountTotal of
				true ->
					case count(Table, Where) of
						{ok, Total} ->
							TotalPages = calcTotalPages(Total, PageSize),
							{ok, #{page => Page, page_size => PageSize, total => Total, total_pages => TotalPages, has_next => Page < TotalPages, rows => Rows0}};
						{error, _} = Err -> Err
					end;
				_ ->
					RowLen = length(Rows0),
					HasNext = RowLen >= PageSize,
					{ok, #{page => Page, page_size => PageSize, total => undefined, total_pages => undefined, has_next => HasNext, rows => Rows0}}
			end;
		{error, _} = Err -> Err
	end.

%% @doc 获取满足条件的完整记录列表。
-spec get(name(), whereClause()) -> {ok, [rowMap()]} | {error, term()}.
get(Table, Where) ->
	get(Table, Where, []).

-spec get(name(), whereClause(), [selectOpt()]) -> {ok, [rowMap()]} | {error, term()}.
get(Table, Where, Opts) ->
	select(Table, Where, setOpt(fields, [], Opts)).

get(Conn, Table, Where, Opts) ->
	select(Conn, Table, Where, setOpt(fields, [], Opts)).

%% @doc 按条件更新记录。
-spec update(map() | tuple(), [fieldName() | pos_integer()], whereClause()) -> {ok, integer()} | {error, term()}.
update(SetData, SetColsOrDirtyMask, Where) ->
	IsTuple = is_tuple(SetData),
	Table = ?CASE(IsTuple, element(1, SetData), maps:get(table_name, SetData)),
	TableFields = dbSchemaDef:tableFields(Table),
	EncodedData = enFieldData(IsTuple, is_integer(SetColsOrDirtyMask), SetData, SetColsOrDirtyMask, Table, TableFields),
	EncodedWhere = enWheres(Table, Where),
	{SQL, Params} = pgdbQuery:buildUpdate(Table, EncodedData, EncodedWhere),
	case equery(SQL, Params) of
		{ok, Count} -> {ok, Count};
		{error, _} = Err -> Err
	end.

%% @doc 在事务连接中更新记录。
-spec update(pid(), map() | tuple(), [fieldName() | pos_integer()], whereClause()) -> {ok, integer()} | {error, term()}.
update(Conn, SetData, SetColsOrDirtyMask, Where) ->
	IsTuple = is_tuple(SetData),
	Table = ?CASE(IsTuple, element(1, SetData), maps:get(table_name, SetData)),
	TableFields = dbSchemaDef:tableFields(Table),
	EncodedData = enFieldData(IsTuple, is_integer(SetColsOrDirtyMask), SetData, SetColsOrDirtyMask, Table, TableFields),
	EncodedWhere = enWheres(Table, Where),
	{SQL, Params} = pgdbQuery:buildUpdate(Table, EncodedData, EncodedWhere),
	case dbEquery(Conn, SQL, Params) of
		{ok, Count} -> {ok, Count};
		{error, _} = Err -> Err
	end.

%% @doc 按条件删除记录。
-spec delete(name(), whereClause()) -> {ok, integer()} | {error, term()}.
delete(Table, Where) ->
	EncodedWhere = enWheres(Table, Where),
	{SQL, Params} = pgdbQuery:buildDelete(Table, EncodedWhere),
	case equery(SQL, Params) of
		{ok, Count} -> {ok, Count};
		{error, _} = Err -> Err
	end.

%% @doc 在事务连接中删除记录。
-spec delete(pid(), name(), whereClause()) -> {ok, integer()} | {error, term()}.
delete(Conn, Table, Where) ->
	EncodedWhere = enWheres(Table, Where),
	{SQL, Params} = pgdbQuery:buildDelete(Table, EncodedWhere),
	case dbEquery(Conn, SQL, Params) of
		{ok, Count} -> {ok, Count};
		{error, _} = Err -> Err
	end.

%% @doc upsert 一条记录；冲突时执行更新。
-spec upsert(map() | tuple(), [fieldName()], [fieldName()] | all) -> {ok, rowMap()} | {error, term()}.
upsert(Data, ConflictKeys, UpdateFields) ->
	Table = ?CASE(is_tuple(Data), element(1, Data), maps:get(table_name, Data)),
	EncodedData = enWholeColValues(Table, Data),
	{SQL, Params} = pgdbQuery:buildUpsert(Table, EncodedData, ConflictKeys, UpdateFields),
	case equery(SQL, Params) of
		{ok, 1, Cols, [Row]} -> {ok, rowToMap(Table, Cols, Row)};
		{ok, _, Cols, [Row]} -> {ok, rowToMap(Table, Cols, Row)};
		{error, _} = Err -> Err
	end.

%% @doc 在事务连接中执行 upsert。
-spec upsert(pid(), map() | tuple(), [fieldName()], [fieldName()] | all) -> {ok, rowMap()} | {error, term()}.
upsert(Conn, Data, ConflictKeys, UpdateFields) ->
	Table = ?CASE(is_tuple(Data), element(1, Data), maps:get(table_name, Data)),
	EncodedData = enWholeColValues(Table, Data),
	{SQL, Params} = pgdbQuery:buildUpsert(Table, EncodedData, ConflictKeys, UpdateFields),
	case dbEquery(Conn, SQL, Params) of
		{ok, 1, Cols, [Row]} -> {ok, rowToMap(Table, Cols, Row)};
		{ok, _, Cols, [Row]} -> {ok, rowToMap(Table, Cols, Row)};
		{error, _} = Err -> Err
	end.

%%%===================================================================
%%% 批量操作
%%%===================================================================

%% @doc 批量插入记录。



-spec batchInsert([map() | tuple()], boolean()) -> ok | {error, term()}.
batchInsert(Rows) -> batchInsert(Rows, false).
batchInsert([], _IsDoUpdate) -> ok;
batchInsert(Rows, IsDoUpdate) ->
	[First | _] = Rows,
	Table = ?CASE(is_tuple(First), element(1, First), maps:get(table_name, First)),
	EncodedRows = [enWholeData(Table, Row) || Row <- Rows],
	{SQL, Params} = pgdbQuery:buildBatchInsert(Table, EncodedRows, ?CASE(IsDoUpdate, dbSchemaDef:onReplace(Table), <<>>)),
	case equery(SQL, Params) of
		{ok, _} -> ok;
		{error, _} = Err -> Err
	end.

%% @doc 在事务连接中批量插入记录。 可选择主键冲突时整行覆盖。
-spec batchInsert(pid(), [map() | tuple()], boolean()) -> ok | {error, term()}.
batchInsert(_Conn, [], _IsDoUpdate) -> ok;
batchInsert(Conn, Rows, IsDoUpdate) ->
	[First | _] = Rows,
	Table = ?CASE(is_tuple(First), element(1, First), maps:get(table_name, First)),
	EncodedRows = [enWholeData(Table, Row) || Row <- Rows],
	{SQL, Params} = pgdbQuery:buildBatchInsert(Table, EncodedRows, ?CASE(IsDoUpdate, dbSchemaDef:onReplace(Table), <<>>)),
	case dbEquery(Conn, SQL, Params) of
		{ok, _} -> ok;
		{error, _} = Err -> Err
	end.

getKeyEnValue([{_Key, EnValue}], _KeyField) -> EnValue;
getKeyEnValue(Map, KeyField) -> maps:get(KeyField, Map).

getSqlCast(Table, Field) ->
	#schField{dbType = DbType} = dbSchemaDef:fieldSchema(Table, Field),
	pgdbQuery:sqlCast(DbType).

%% @doc 批量 patch 更新：{SetData, DirtyMask, Where} 列表（Where 须为单主键）。
-spec batchUpdate([{map() | tuple(), non_neg_integer(), whereClause()}]) -> ok | {error, term()}.
batchUpdate([]) -> ok;
batchUpdate(Updates) ->
	[{First, _DirtyMask, _Where} | _] = Updates,
	IsTuple = is_tuple(First),
	Table = ?CASE(IsTuple, element(1, First), maps:get(table_name, First)),
	[KeyField] = dbSchemaDef:tablePrimaryKey(Table),
	TableFields = dbSchemaDef:tableFields(Table),
	{UpAllMask, UpItems} = lists:foldl(
		fun({SetData, DirtyMask, KeyWhere}, {AllMask, EncodeDataAcc}) ->
			EncodedData = enFieldData(IsTuple, is_integer(DirtyMask), SetData, DirtyMask, Table, TableFields),
			{AllMask bor DirtyMask, [{DirtyMask, EncodedData, getKeyEnValue(enWheres(Table, KeyWhere), KeyField)} | EncodeDataAcc]}
		end, {0, []}, Updates),
	case UpAllMask > 0 of
		true ->
			SetFields = [{Index, NameBin, getSqlCast(Table, NameAtom)} || {NameBin, Index, _Codec, NameAtom} <- TableFields, (UpAllMask band (1 bsl (Index - 1))) =/= 0],
			{SQL, Params} = pgdbQuery:buildBatchUpdate(Table, KeyField, getSqlCast(Table, KeyField), SetFields, UpItems),
			case equery(SQL, Params) of
				{ok, _} -> ok;
				{error, _} = Err -> Err
			end;
		_ ->
			ok
	end.

%% @doc 在连接上执行 {SetData, DirtyMask, Where} 列表。
-spec batchUpdate(pid(), [{map() | tuple(), non_neg_integer(), whereClause()}]) -> ok | {error, term()}.
batchUpdate(_Conn, []) -> ok;
batchUpdate(Conn, Updates) ->
	[{First, _DirtyMask, _Where} | _] = Updates,
	IsTuple = is_tuple(First),
	Table = ?CASE(IsTuple, element(1, First), maps:get(table_name, First)),
	[KeyField] = dbSchemaDef:tablePrimaryKey(Table),
	TableFields = dbSchemaDef:tableFields(Table),
	{UpAllMask, UpItems} = lists:foldl(
		fun({SetData, DirtyMask, KeyWhere}, {AllMask, EncodeDataAcc}) ->
			EncodedData = enFieldData(IsTuple, is_integer(DirtyMask), SetData, DirtyMask, Table, TableFields),
			{AllMask bor DirtyMask, [{DirtyMask, EncodedData, getKeyEnValue(enWheres(Table, KeyWhere), KeyField)} | EncodeDataAcc]}
		end, {0, []}, Updates),
	case UpAllMask > 0 of
		true ->
			SetFields = [{Index, NameBin, getSqlCast(Table, NameAtom)} || {NameBin, Index, _Codec, NameAtom} <- TableFields, (UpAllMask band (1 bsl (Index - 1))) =/= 0],
			{SQL, Params} = pgdbQuery:buildBatchUpdate(Table, KeyField, getSqlCast(Table, KeyField), SetFields, UpItems),
			case dbEquery(Conn, SQL, Params) of
				{ok, _} -> ok;
				{error, _} = Err -> Err
			end;
		_ ->
			ok
	end.

%%%===================================================================
%%% 批量删除
%%%===================================================================

%% @doc 按指定键字段的 IN 列表高效批量删除，返回实际删除行数。
-spec batchDelByKey(name(), fieldName(), [term()]) -> {ok, integer()} | {error, term()}.
batchDelByKey(_Table, _KeyField, []) ->
	{ok, 0};
batchDelByKey(Table, KeyField, Keys) ->
	case encodeBatchDeleteKeys(Table, KeyField, Keys) of
		{ok, EncodedKeys} ->
			{SQL, Params} = pgdbQuery:buildBatchDeleteByKey(Table, KeyField, EncodedKeys),
			case equery(SQL, Params) of
				{ok, Count} -> {ok, Count};
				{error, _} = Err -> Err
			end;
		{error, _} = Err -> Err
	end.

%% @doc 在事务连接中按指定键字段的 IN 列表高效批量删除。
-spec batchDelByKey(pid(), name(), fieldName(), [term()]) -> {ok, integer()} | {error, term()}.
batchDelByKey(_Conn, _Table, _KeyField, []) ->
	{ok, 0};
batchDelByKey(Conn, Table, KeyField, Keys) ->
	case encodeBatchDeleteKeys(Table, KeyField, Keys) of
		{ok, EncodedKeys} ->
			{SQL, Params} = pgdbQuery:buildBatchDeleteByKey(Table, KeyField, EncodedKeys),
			case dbEquery(Conn, SQL, Params) of
				{ok, Count} -> {ok, Count};
				{error, _} = Err -> Err
			end;
		{error, _} = Err -> Err
	end.

%% @doc 统计整张表的记录数。
-spec count(atom()) -> {ok, integer()} | {error, term()}.
count(Table) ->
	count(Table, #{}).

%% @doc 按条件统计记录数。
-spec count(name(), whereClause()) -> {ok, integer()} | {error, term()}.
count(Table, Where) ->
	EncodedWhere = enWheres(Table, Where),
	{WhereSql, WhereParams, _} = pgdbQuery:buildWhere(EncodedWhere, 1),
	SQL = [<<"SELECT COUNT(*) FROM ">>, pgdbUtils:makeName(Table), WhereSql],
	case equery(SQL, WhereParams) of
		{ok, _, [{N}]} -> {ok, N};
		{error, _} = Err -> Err
	end.

%% @doc 求和指定字段。
-spec sum(name(), fieldName()) -> {ok, term()} | {error, term()}.
sum(Table, Column) ->
	sum(Table, Column, #{}).

-spec sum(name(), fieldName(), whereClause()) -> {ok, term()} | {error, term()}.
sum(Table, Column, Where) ->
	EncodedWhere = enWheres(Table, Where),
	{WhereSql, WhereParams, _} = pgdbQuery:buildWhere(EncodedWhere, 1),
	SQL = [<<"SELECT COALESCE(SUM(">>, pgdbUtils:makeName(Column), <<"::numeric), 0) FROM ">>, pgdbUtils:makeName(Table), WhereSql],
	case equery(SQL, WhereParams) of
		{ok, _, [{N}]} -> {ok, toNumber(N)};
		{error, _} = Err -> Err
	end.

%%%===================================================================
%%% 分页扫描
%%%===================================================================

%% @doc 按 offset 分页遍历整批数据，对每条记录执行回调。
%% 回调形态为 fun(Row) -> term()，不做累积；如需传入初始 Acc 并返回新 Acc，请使用 foldRows/5,6。
-spec foreachRows(name(), whereClause(), pos_integer(), fun((rowMap()) -> term())) -> ok | {error, term()}.
foreachRows(Table, Where, PageSize, Fun) ->
	foreachRows(Table, Where, PageSize, [], Fun).

-spec foreachRows(name(), whereClause(), pos_integer(), [pageOpt()], fun((rowMap()) -> term())) -> ok | {error, term()}.
foreachRows(Table, Where, PageSize, Opts, Fun) ->
	case foldRows(Table, Where, PageSize, Opts, Fun, '$foreachFun') of
		{ok, _Acc} -> ok;
		{error, _} = Err -> Err
	end.

%% @doc 按 offset 分页遍历整批数据，并累积结果。
%% 回调形态为 fun(Row, AccIn) -> AccOut，InitAcc 会传入首行处理，并持续传递到后续每一行。
-spec foldRows(name(), whereClause(), pos_integer(), fun((rowMap(), term()) -> term()), term()) -> {ok, term()} | {error, term()}.
foldRows(Table, Where, PageSize, Fun, InitAcc) ->
	foldRows(Table, Where, PageSize, [], Fun, InitAcc).

-spec foldRows(name(), whereClause(), pos_integer(), [pageOpt()], fun((rowMap(), term()) -> term()), term()) -> {ok, term()} | {error, term()}.
foldRows(_Table, _Where, PageSize, _Opts, _Fun, _InitAcc) when PageSize =< 0 ->
	{error, invalid_page_args};
foldRows(Table, Where, PageSize, Opts, Fun, InitAcc) ->
	case normalizeOffsetScanOpts(Table, Opts) of
		{ok, ScanOpts} ->
			QueryOpts = setOpt(limit, PageSize, removeOpt(count_total, ScanOpts)),
			doFoldRows(Table, Where, 0, PageSize, QueryOpts, Fun, InitAcc);
		{error, _} = Err -> Err
	end.

%% @doc 按主键或任意有序字段做 keyset 扫描，对每条记录执行回调。
%% 回调形态为 fun(Row) -> term()，不做累积；如需传入初始 Acc 并返回新 Acc，请使用 foldByKey/6,7。
-spec foreachByKey(name(), whereClause(), fieldName(), pos_integer(), fun((rowMap()) -> term())) -> ok | {error, term()}.
foreachByKey(Table, Where, KeyField, PageSize, Fun) ->
	foreachByKey(Table, Where, KeyField, PageSize, [], Fun).

-spec foreachByKey(name(), whereClause(), fieldName(), pos_integer(), [pageOpt()], fun((rowMap()) -> term())) -> ok | {error, term()}.
foreachByKey(Table, Where, KeyField, PageSize, Opts, Fun) ->
	case foldByKey(Table, Where, KeyField, PageSize, Opts, Fun, '$foreachFun') of
		{ok, _Acc} -> ok;
		{error, _} = Err -> Err
	end.

%% @doc 按 keyset 扫描整表，并累积结果。
%% 回调形态为 fun(Row, AccIn) -> AccOut，InitAcc 会传入首行处理，并持续传递到后续每一行。
-spec foldByKey(name(), whereClause(), fieldName(), pos_integer(), term(), fun((rowMap(), term()) -> term())) -> {ok, term()} | {error, term()}.
foldByKey(Table, Where, KeyField, PageSize, Fun, InitAcc) ->
	foldByKey(Table, Where, KeyField, PageSize, [], Fun, InitAcc).

-spec foldByKey(name(), whereClause(), fieldName(), pos_integer(), [pageOpt()], fun((rowMap(), term()) -> term()), term()) -> {ok, term()} | {error, term()}.
foldByKey(_Table, _Where, _KeyField, PageSize, _Opts, _Fun, _InitAcc) when PageSize =< 0; PageSize > 1000 ->
	{error, invalid_page_args};
foldByKey(Table, Where, KeyField, PageSize, Opts, Fun, InitAcc) ->
	StartAfter = proplists:get_value(start_after, Opts, undefined),
	{ScanOpts, StripCursorField} = prepareKeysetScanOpts(KeyField, removeOpt(start_after, removeOpt(count_total, Opts))),
	QueryOpts = setOpt(limit, PageSize, ScanOpts),
	doFoldByKey(Table, Where, KeyField, StartAfter, PageSize, QueryOpts, StripCursorField, Fun, InitAcc).

%%%===================================================================
%%% JSONB 辅助
%%%===================================================================

%% @doc 更新 JSON/JSONB 字段中的指定路径值。
%% Column 为 JSON/JSONB 列名，或 text 列但 schema codec 为 json。
%% Path 为单层 key 或多层路径；Value 为 Erlang term，默认会编码成 JSON。
-spec jsonbSet(name(), fieldName(), jsonPath(), jsonInput()) -> {ok, integer()} | {error, term()}.
jsonbSet(Table, Column, Path, Value) ->
	jsonbSet(Table, Column, Path, Value, #{}).

-spec jsonbSet(name(), fieldName(), jsonPath(), jsonInput(), whereClause()) -> {ok, integer()} | {error, term()}.
jsonbSet(Table, Column, Path, Value, Where) ->
	case {jsonColumnStorage(Table, Column), normalizeJsonPath(Path), encodeJsonInput(Value)} of
		{{ok, Storage}, {ok, PathSegments}, {ok, JsonValue}} ->
			ColumnSql = pgdbUtils:makeName(Column),
			PathArray = jsonbPathArraySql(PathSegments),
			EncodedWhere = enWheres(Table, Where),
			{WhereSql, WhereParams, NextIdx} = pgdbQuery:buildWhere(EncodedWhere, 1),
			JsonExpr = [<<"jsonb_set(">>, jsonStorageExpr(Storage, ColumnSql), <<", ">>, PathArray,
				<<", $">>, integer_to_binary(NextIdx), <<"::jsonb, true)">>],
			SQL = [<<"UPDATE ">>, pgdbUtils:makeName(Table), <<" SET ">>, jsonAssignmentExpr(Storage, ColumnSql, JsonExpr), WhereSql],
			case equery(SQL, WhereParams ++ [JsonValue]) of
				{ok, Count} -> {ok, Count};
				{error, _} = Err -> Err
			end;
		{{error, _} = Err, _, _} -> Err;
		{_, {error, _} = Err, _} -> Err;
		{_, _, {error, _} = Err} -> Err
	end.

%% @doc 读取 JSON/JSONB 字段中指定路径的值，并解码为 Erlang term。
-spec jsonbGet(name(), fieldName(), jsonPath()) -> {ok, term()} | not_found | {error, term()}.
jsonbGet(Table, Column, Path) ->
	jsonbGet(Table, Column, Path, #{}).

-spec jsonbGet(name(), fieldName(), jsonPath(), whereClause()) -> {ok, term()} | not_found | {error, term()}.
jsonbGet(Table, Column, Path, Where) ->
	case {jsonColumnStorage(Table, Column), normalizeJsonPath(Path)} of
		{{ok, Storage}, {ok, PathSegments}} ->
			ColumnSql = pgdbUtils:makeName(Column),
			PathArray = jsonbPathArraySql(PathSegments),
			EncodedWhere = enWheres(Table, Where),
			{WhereSql, WhereParams, _} = pgdbQuery:buildWhere(EncodedWhere, 1),
			SQL = [<<"SELECT ">>, jsonStorageExpr(Storage, ColumnSql), <<" #> ">>, PathArray,
				<<" FROM ">>, pgdbUtils:makeName(Table), WhereSql, <<" LIMIT 1">>],
			case equery(SQL, WhereParams) of
				{ok, _, [{null} | _]} -> not_found;
				{ok, _, [{Val} | _]} -> decodeJsonGetValue(Val);
				{ok, _, []} -> not_found;
				{error, _} = Err -> Err
			end;
		{{error, _} = Err, _} -> Err;
		{_, {error, _} = Err} -> Err
	end.

%% @doc 删除 JSON/JSONB 字段中指定路径的键。
-spec jsonbDelete(name(), fieldName(), jsonPath()) -> {ok, integer()} | {error, term()}.
jsonbDelete(Table, Column, Path) ->
	jsonbDelete(Table, Column, Path, #{}).

%% @doc 按条件删除 JSON/JSONB 字段中指定路径的键。
-spec jsonbDelete(name(), fieldName(), jsonPath(), whereClause()) -> {ok, integer()} | {error, term()}.
jsonbDelete(Table, Column, Path, Where) ->
	case {jsonColumnStorage(Table, Column), normalizeJsonPath(Path)} of
		{{ok, Storage}, {ok, PathSegments}} ->
			ColumnSql = pgdbUtils:makeName(Column),
			PathArray = jsonbPathArraySql(PathSegments),
			EncodedWhere = enWheres(Table, Where),
			{WhereSql, WhereParams, _NextIdx} = pgdbQuery:buildWhere(EncodedWhere, 1),
			JsonExpr = [jsonStorageExpr(Storage, ColumnSql), <<" #- ">>, PathArray],
			SQL = [<<"UPDATE ">>, pgdbUtils:makeName(Table), <<" SET ">>, jsonAssignmentExpr(Storage, ColumnSql, JsonExpr), WhereSql],
			case equery(SQL, WhereParams) of
				{ok, Count} -> {ok, Count};
				{error, _} = Err -> Err
			end;
		{{error, _} = Err, _} -> Err;
		{_, {error, _} = Err} -> Err
	end.

%% @doc 合并值到 JSON/JSONB 字段上（顶层 merge）。
-spec jsonbMerge(name(), fieldName(), jsonInput(), whereClause()) -> {ok, integer()} | {error, term()}.
jsonbMerge(Table, Column, Value, Where) ->
	case {jsonColumnStorage(Table, Column), encodeJsonInput(Value)} of
		{{ok, Storage}, {ok, JsonValue}} ->
			ColumnSql = pgdbUtils:makeName(Column),
			EncodedWhere = enWheres(Table, Where),
			{WhereSql, WhereParams, NextIdx} = pgdbQuery:buildWhere(EncodedWhere, 1),
			JsonExpr = [jsonStorageExpr(Storage, ColumnSql), <<" || $">>, integer_to_binary(NextIdx), <<"::jsonb">>],
			SQL = [<<"UPDATE ">>, pgdbUtils:makeName(Table), <<" SET ">>, jsonAssignmentExpr(Storage, ColumnSql, JsonExpr), WhereSql],
			case equery(SQL, WhereParams ++ [JsonValue]) of
				{ok, Count} -> {ok, Count};
				{error, _} = Err -> Err
			end;
		{{error, _} = Err, _} -> Err;
		{_, {error, _} = Err} -> Err
	end.

%%%===================================================================
%%% 事务与查询
%%%===================================================================

%% @doc 在事务中执行 Fun，无超时限制。
%% Worker 内部调用 epgsql:with_transaction，自动发起 BEGIN / COMMIT / ROLLBACK。
%% Fun 接收连接 pid，可以用 query/3, ddl/2 等带 Conn 参数的函数执行 SQL。
%% 返回值：成功为 {ok, FunReturn}，失败为 {error, Reason}。
%% 若 Fun 内部抛出异常，异常会透传到调用方进程。
-spec transaction(fun((pid()) -> term())) -> {ok, term()} | {error, term()}.
transaction(Fun) ->
	dealQuery({transaction, Fun}, infinity).

%% @doc 带超时的事务执行，Timeout 单位毫秒。
%% 超时只限制等待 worker 应答的时间，不是 SQL 执行超时。
-spec transaction(fun((pid()) -> term()), timeout()) -> {ok, term()} | {error, term()}.
transaction(Fun, Timeout) ->
	dealQuery({transaction, Fun}, Timeout).

%% @doc 借用一个连接执行 Fun，不自动开启事务。
%%
%% 与 transaction/1 的区别：
%%   - 不发 BEGIN / COMMIT，Fun 自己控制是否提交。
%%   - Fun 的返回值直接原样返回给调用方（不再包一层 {ok, ...}）。
%%   - 若连接断开，返回 {error, disconnected}；Fun 内部异常会透传。
%%
%% 典型使用场景（这些场景必须持有同一个会话）：
%%   1. pg_advisory_lock / pg_advisory_unlock —— Advisory 锁生命周期绑定在会话上，
%%      换连接锁就丢了；
%%   2. LISTEN / NOTIFY —— 订阅只在当前连接有效；
%%   3. 跨多语句共享临时表或 SET LOCAL 变量；
%%   4. COPY 协议流式写入。
%%
%% 注意：Fun 执行期间该连接被独占，不要做长时间阻塞操作，否则连接池会被耗尽。
-spec withConnection(fun((pid()) -> term())) -> term() | {error, term()}.
withConnection(Fun) ->
	dealQuery({with_connection, Fun}, infinity).

%% @doc 执行不带参数的 DDL。
-spec ddl(iodata()) -> ok | {error, term()}.
ddl(SQL) ->
	execDdl(SQL).

%% @doc 在指定连接上执行 DDL，通常用于迁移事务。
-spec ddl(pid(), iodata()) -> ok | {error, term()}.
ddl(Conn, SQL) ->
	normalizeDdlResult(dbSquery(Conn, SQL)).

%% @doc 执行不带参数的原生 SQL。
-spec query(iodata()) -> term().
query(SQL) ->
	squery(SQL).

%% @doc 执行带参数的原生 SQL。
-spec query(iodata(), list()) -> term().
query(SQL, Params) ->
	equery(SQL, Params).

%% @doc 在指定事务连接上执行带参数 SQL。
-spec query(pid(), iodata(), list()) -> term().
query(Conn, SQL, Params) ->
	dbEquery(Conn, SQL, Params).

%%%===================================================================
%%% 迁移与自省
%%%===================================================================

%% @doc 执行未应用的迁移。
-spec migrate(list()) -> ok | {error, term()}.
migrate(Migrations) ->
	case validateMigrations(Migrations) of
		ok ->
			withMigrationLock(fun(Conn) ->
				case ensureMigrationTable(Conn) of
					ok ->
						case getAppliedVersions(Conn) of
							{ok, Applied} ->
								Pending = [{V, D, Up, Down} || {V, D, Up, Down} <- Migrations, not lists:member(V, Applied)],
								runMigrations(Conn, lists:keysort(1, Pending));
							{error, _} = Err ->
								Err
						end;
					{error, _} = Err ->
						Err
				end
			end);
		{error, _} = Err ->
			Err
	end.

%% @doc 回滚到指定版本。
-spec rollback(list(), integer()) -> ok | {error, term()}.
rollback(Migrations, TargetVersion) ->
	case validateMigrations(Migrations) of
		ok ->
			withMigrationLock(fun(Conn) ->
				case ensureMigrationTable(Conn) of
					ok ->
						case getAppliedVersions(Conn) of
							{ok, Applied} ->
								ToRollback = [{V, D, Up, Down} || {V, D, Up, Down} <- Migrations,
									V > TargetVersion,
									lists:member(V, Applied)],
								rollbackMigrations(Conn, lists:reverse(lists:keysort(1, ToRollback)));
							{error, _} = Err ->
								Err
						end;
					{error, _} = Err ->
						Err
				end
			end);
		{error, _} = Err ->
			Err
	end.

%% @doc 返回迁移状态列表。
-spec status() -> {ok, list()} | {error, term()}.
status() ->
	status([]).

-spec status(list()) -> {ok, list()} | {error, term()}.
status(Migrations) ->
	case validateMigrations(Migrations) of
		ok ->
			case ensureMigrationTable() of
				ok ->
					case getAppliedVersions() of
						{ok, Applied} ->
							MigrationStatus = lists:map(fun({V, D, _, _}) ->
								case lists:member(V, Applied) of
									true -> {V, D, applied};
									false -> {V, D, pending}
								end
							end, lists:keysort(1, Migrations)),
							{ok, MigrationStatus};
						{error, _} = Err ->
							Err
					end;
				{error, _} = Err ->
					Err
			end;
		{error, _} = Err ->
			Err
	end.

%% @doc 获取 public schema 下所有业务表。
-spec tables() -> {ok, [binary()]} | {error, term()}.
tables() ->
	SQL = <<"SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' AND table_name <> '_pgdb_migrations' ORDER BY table_name">>,
	case squery(SQL) of
		{ok, _, Rows} -> {ok, [T || {T} <- Rows]};
		{error, _} = Err -> Err
	end.

%% @doc 查看表结构详情。
-spec describe(name()) -> {ok, [rowMap()]} | {error, term()}.
describe(Table) ->
	SQL = <<"SELECT column_name, data_type, character_maximum_length, is_nullable, column_default FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 ORDER BY ordinal_position">>,
	case equery(SQL, [pgdbUtils:makeName(Table)]) of
		{ok, Cols, Rows} -> {ok, rawRowsToMaps(Cols, Rows)};
		{error, _} = Err -> Err
	end.

%%%===================================================================
%%% 内部函数
%%%===================================================================

rawRowsToMaps(Cols, Rows) ->
	[tupleRowToMap(Cols, 1, Row, #{}) || Row <- Rows].

enWholeData(Table, Data) when is_tuple(Data) ->
	[enCodecValue(Codec, Table, NameAtom, element(Index, Data)) || {_NameBin, Index, Codec, NameAtom} <- dbSchemaDef:tableFields(Table)];
enWholeData(Table, Data) ->
	[enCodecValue(Codec, Table, NameAtom, maps:get(NameAtom, Data, undefined)) || {_NameBin, _Index, Codec, NameAtom} <- dbSchemaDef:tableFields(Table)].

enWholeColValues(Table, Data) when is_tuple(Data) ->
	[{NameBin, enCodecValue(Codec, Table, NameAtom, element(Index, Data))} || {NameBin, Index, Codec, NameAtom} <- dbSchemaDef:tableFields(Table)];
enWholeColValues(Table, Data) ->
	[{NameBin, enCodecValue(Codec, Table, NameAtom, maps:get(NameAtom, Data, undefined))} || {NameBin, _Index, Codec, NameAtom} <- dbSchemaDef:tableFields(Table)].

enFieldData(true, true, Data, DirtyMask, Table, TableFields) ->
	[
		begin
			{NameBin, enCodecValue(Codec, Table, NameAtom, element(Index, Data))}
		end || {NameBin, Index, Codec, NameAtom} <- TableFields, (DirtyMask band (1 bsl (Index - 1))) =/= 0
	];
enFieldData(true, false, Data, SetCols, Table, TableFields) ->
	[
		begin
			{NameBin, Index, Codec, NameAtom} = lists:keyfind(Index, 2, TableFields),
			{NameBin, enCodecValue(Codec, Table, NameAtom, element(Index, Data))}
		end || Index <- SetCols
	];
enFieldData(false, true, Data, DirtyMask, Table, TableFields) ->
	[
		begin
			{NameBin, enCodecValue(Codec, Table, NameAtom, maps:get(NameAtom, Data, undefined))}
		end || {NameBin, Index, Codec, NameAtom} <- TableFields, (DirtyMask band (1 bsl (Index - 1))) =/= 0
	];
enFieldData(false, false, Data, SetCols, Table, TableFields) ->
	[
		begin
			{NameBin, _Index, Codec, NameAtom} = lists:keyfind(Field, 4, TableFields),
			{NameBin, enCodecValue(Codec, Table, NameAtom, maps:get(NameAtom, Data, undefined))}
		end || Field <- SetCols
	].

encodeBatchDeleteKeys(Table, KeyField, Keys) ->
	TableFields = dbSchemaDef:tableFields(Table),
	case lists:keyfind(KeyField, 4, TableFields) of
		{_NameBin, _Index, Codec, NameAtom} ->
			{ok, lists:usort([enCodecValue(Codec, Table, NameAtom, Key) || Key <- Keys])};
		false ->
			{error, {unknown_field, Table, KeyField}}
	end.

loopDeMapData([], _Row, _RowIndex, _Table, Acc) -> Acc;
loopDeMapData([#schField{name = Name, codec = Codec} | Fields], Row, RowIndex, Table, Acc) ->
	Value = element(RowIndex, Row),
	NewAcc = Acc#{Name => deCodecValue(Codec, Table, Name, Value)},
	loopDeMapData(Fields, Row, RowIndex + 1, Table, NewAcc).

loopDeRecordData([], _Row, _RowIndex, _Table, Index, Acc) -> erlang:make_tuple(Index - 1, undefined, Acc);
loopDeRecordData([#schField{name = Name, codec = Codec} | Fields], Row, RowIndex, Table, Index, Acc) ->
	Value = element(RowIndex, Row),
	NewAcc = [{Index, deCodecValue(Codec, Table, Name, Value)} | Acc],
	loopDeRecordData(Fields, Row, RowIndex + 1, Table, Index + 1, NewAcc).

rowToWholeData(Table, Row) ->
	#schema{repr = Type, fields = Fields} = dbSchemaDef:tableSchema(Table),
	case Type of
		map ->
			loopDeMapData(Fields, Row, 1, Table, #{});
		record ->
			loopDeRecordData(Fields, Row, 1, Table, 2, [{1, pgdbUtils:toAtom(Table)}])
	end.

loopRowsToMap([], _Row, _ColIndex, _Table, Acc) -> Acc;
loopRowsToMap([{FieldAtom, _Field, Codec} | Cols], Row, ColIndex, Table, Acc) ->
	Value = element(ColIndex, Row),
	NewAcc = Acc#{FieldAtom => deCodecValue(Codec, Table, FieldAtom, Value)},
	loopRowsToMap(Cols, Row, ColIndex + 1, Table, NewAcc).

decodeFields(Table, Cols) ->
	[
		begin
			Field = element(2, Col),
			FieldAtom = pgdbUtils:toAtom(Field),
			{FieldAtom, Field, dbSchemaDef:fieldCodec(Table, FieldAtom)}
		end || Col <- Cols
	].

rowToMap(Table, Cols, Row) ->
	DecodeFields = decodeFields(Table, Cols),
	loopRowsToMap(DecodeFields, Row, 1, Table, #{}).

jsonbPathArraySql(Path) when is_list(Path) ->
	Parts = <<<<", ", (iolist_to_binary(pgdbUtils:quoteLiteral(toText(P))))/binary>> || P <- Path>>,
	Joined = ?CASE(Parts, <<>>, <<>>, <<_:16, TParts/binary>>, TParts),
	[<<"ARRAY[">>, Joined, <<"]::text[]">>];
jsonbPathArraySql(Path) ->
	[<<"ARRAY[">>, pgdbUtils:quoteLiteral(toText(Path)), <<"]::text[]">>].

jsonColumnStorage(Table, Column) ->
	case dbSchemaDef:fieldSchema(Table, Column) of
		#schField{dbType = jsonb} -> {ok, jsonb};
		#schField{dbType = json} -> {ok, json};
		#schField{dbType = text, codec = ?codec_json} -> {ok, text_json};
		#schField{dbType = DbType} -> {error, {unsupported_json_column, Table, Column, DbType}};
		undefined -> {error, {unknown_field, Table, Column}}
	end.

jsonStorageExpr(jsonb, ColumnSql) ->
	ColumnSql;
jsonStorageExpr(json, ColumnSql) ->
	[<<"(">>, ColumnSql, <<")::jsonb">>];
jsonStorageExpr(text_json, ColumnSql) ->
	[<<"(">>, ColumnSql, <<")::jsonb">>].

jsonAssignmentExpr(jsonb, ColumnSql, JsonExpr) ->
	[ColumnSql, <<" = ">>, JsonExpr];
jsonAssignmentExpr(json, ColumnSql, JsonExpr) ->
	[ColumnSql, <<" = (">>, JsonExpr, <<")::json">>];
jsonAssignmentExpr(text_json, ColumnSql, JsonExpr) ->
	[ColumnSql, <<" = (">>, JsonExpr, <<")::text">>].

normalizeJsonPath(Path) when is_atom(Path); is_binary(Path); is_integer(Path) ->
	{ok, [toText(Path)]};
normalizeJsonPath([]) ->
	{error, invalid_json_path};
normalizeJsonPath(Path) when is_list(Path) ->
	case io_lib:printable_unicode_list(Path) of
		true -> {ok, [unicode:characters_to_binary(Path)]};
		false -> {ok, [toText(Segment) || Segment <- Path]}
	end;
normalizeJsonPath(_Path) ->
	{error, invalid_json_path}.

encodeJsonInput({raw_json, JsonBin}) when is_binary(JsonBin) ->
	{ok, JsonBin};
encodeJsonInput(Value) ->
	try
		{ok, jiffy:encode(Value)}
	catch
		Class:Reason -> {error, {invalid_json_value, Class, Reason, Value}}
	end.

decodeJsonGetValue(Value) when is_binary(Value) ->
	try
		{ok, jiffy:decode(Value, [return_maps])}
	catch
		_:_ -> {ok, Value}
	end;
decodeJsonGetValue(Value) ->
	{ok, Value}.

toText(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
toText(Value) when is_binary(Value) -> Value;
toText(Value) when is_list(Value) -> iolist_to_binary(Value);
toText(Value) when is_integer(Value) -> integer_to_binary(Value).

%% 将 PostgreSQL numeric/decimal 值统一转为 Erlang number
toNumber(N) when is_integer(N) -> N;
toNumber(N) when is_float(N) -> N;
toNumber(N) when is_binary(N) ->
	case binary:match(N, <<".">>) of
		nomatch -> binary_to_integer(N);
		_ -> binary_to_float(N)
	end;
toNumber({Prec, Scale, Digits}) when is_integer(Prec) ->
	%% epgsql decimal record fallback
	F = Digits / math:pow(10, Scale),
	case Scale of 0 -> round(F); _ -> F end;
toNumber(N) -> N.

normalizeDdlResult({ok, [], []}) -> ok;
normalizeDdlResult({ok, _, _}) -> ok;
normalizeDdlResult({error, _} = Err) -> Err.

ensureMigrationTable() ->
	ddl(
		<<"CREATE TABLE IF NOT EXISTS _pgdb_migrations (version BIGINT PRIMARY KEY, description TEXT, applied_at TIMESTAMPTZ DEFAULT NOW())">>
	).

ensureMigrationTable(Conn) ->
	ddl(
		Conn,
		<<"CREATE TABLE IF NOT EXISTS _pgdb_migrations (version BIGINT PRIMARY KEY, description TEXT, applied_at TIMESTAMPTZ DEFAULT NOW())">>
	).

getAppliedVersions() ->
	case equery(<<"SELECT version FROM _pgdb_migrations ORDER BY version">>, []) of
		{ok, _, Rows} -> {ok, [V || {V} <- Rows]};
		{error, _} = Err -> Err
	end.

getAppliedVersions(Conn) ->
	case dbEquery(Conn, <<"SELECT version FROM _pgdb_migrations ORDER BY version">>, []) of
		{ok, _, Rows} -> {ok, [V || {V} <- Rows]};
		{error, _} = Err -> Err
	end.

runMigrations(_Conn, []) -> ok;
runMigrations(Conn, [{Version, Desc, UpFun, _DownFun} | Rest]) ->
	case withTransactionOnConnection(Conn, fun(TxConn) ->
		ok = normalizeMigrationStepResult(UpFun(TxConn)),
		ok = normalizeMigrationQueryResult(query(TxConn,
			<<"INSERT INTO _pgdb_migrations (version, description) VALUES ($1, $2)">>,
			[Version, migrationDescriptionToBinary(Desc)]))
	end) of
		ok -> runMigrations(Conn, Rest);
		{error, Reason} -> {error, {migration_failed, Version, Reason}}
	end.

rollbackMigrations(_Conn, []) -> ok;
rollbackMigrations(Conn, [{Version, _Desc, _UpFun, DownFun} | Rest]) ->
	case withTransactionOnConnection(Conn, fun(TxConn) ->
		ok = normalizeMigrationStepResult(DownFun(TxConn)),
		ok = normalizeMigrationQueryResult(query(TxConn, <<"DELETE FROM _pgdb_migrations WHERE version = $1">>, [Version]))
	end) of
		ok -> rollbackMigrations(Conn, Rest);
		{error, Reason} -> {error, {rollback_failed, Version, Reason}}
	end.

withMigrationLock(Fun) ->
	withConnection(fun(Conn) ->
		case query(Conn, <<"SELECT pg_advisory_lock($1)">>, [?migrationLockKey]) of
			{ok, _, _} ->
				try
					Fun(Conn)
				after
					query(Conn, <<"SELECT pg_advisory_unlock($1)">>, [?migrationLockKey])
				end;
			{error, _} = Err -> Err
		end
	end).

withTransactionOnConnection(Conn, Fun) ->
	try
		case epgsql:with_transaction(Conn, Fun) of
			{rollback, Reason} -> {error, {transaction_rollback, Reason}};
			{error, _} = Err -> Err;
			_ -> ok
		end
	catch
		error:ErrorReason:ErrorStack -> {error, {transaction_failed, ErrorReason, ErrorStack}};
		throw:ThrowReason:ThrowStack -> {error, {transaction_thrown, ThrowReason, ThrowStack}};
		exit:ExitReason:ExitStack -> {error, {transaction_exit, ExitReason, ExitStack}}
	end.

normalizeMigrationStepResult({error, _} = Err) ->
	erlang:error(Err);
normalizeMigrationStepResult(_Result) ->
	ok.

normalizeMigrationQueryResult({ok, _}) ->
	ok;
normalizeMigrationQueryResult({ok, _, _}) ->
	ok;
normalizeMigrationQueryResult({ok, _, _, _}) ->
	ok;
normalizeMigrationQueryResult({error, _} = Err) ->
	erlang:error(Err).

migrationDescriptionToBinary(Desc) when is_binary(Desc) ->
	Desc;
migrationDescriptionToBinary(Desc) when is_atom(Desc) ->
	atom_to_binary(Desc, utf8);
migrationDescriptionToBinary(Desc) when is_integer(Desc) ->
	integer_to_binary(Desc);
migrationDescriptionToBinary(Desc) when is_list(Desc) ->
	iolist_to_binary(Desc).

doFoldRows(Table, Where, Offset, PageSize, Opts, Fun, Acc) ->
	QueryOpts = setOpt(offset, Offset, Opts),
	case select(Table, Where, QueryOpts) of
		{ok, []} ->
			{ok, Acc};
		{ok, Rows} ->
			case safeFoldRows(Acc, Rows, Fun) of
				{ok, NewAcc} ->
					case length(Rows) >= PageSize of
						true ->
							doFoldRows(Table, Where, Offset + PageSize, PageSize, Opts, Fun, NewAcc);
						_ ->
							{ok, NewAcc}
					end;
				{error, _} = Err -> Err
			end;
		{error, _} = Err -> Err
	end.

doFoldByKey(Table, Where, KeyField, LastKey, PageSize, Opts, _StripCursorField, Fun, Acc) ->
	QueryWhere = maybeAppendCursorWhere(Where, KeyField, LastKey),
	case select(Table, QueryWhere, Opts) of
		{ok, []} ->
			{ok, Acc};
		{ok, Rows} ->
			case safeFoldRows(Acc, Rows, Fun) of
				{ok, NewAcc} ->
					HasMore = length(Rows) >= PageSize,
					case HasMore andalso resolveNextKeyCursor(Table, Rows, KeyField) of
						{ok, NextCursor} ->
							doFoldByKey(Table, Where, KeyField, NextCursor, PageSize, Opts, _StripCursorField, Fun, NewAcc);
						false ->
							{ok, NewAcc};
						{error, _} = Err -> Err
					end;
				{error, _} = Err -> Err
			end;
		{error, _} = Err -> Err
	end.

normalizeOffsetScanOpts(Table, Opts) ->
	case proplists:get_value(order_by, Opts, undefined) of
		undefined ->
			case defaultScanOrder(Table) of
				undefined -> {error, missing_order_by};
				OrderBy -> {ok, setOpt(order_by, OrderBy, Opts)}
			end;
		_ ->
			{ok, Opts}
	end.

defaultScanOrder(Table) ->
	case scanPrimaryKeys(Table) of
		[] -> undefined;
		[KeyField] -> {KeyField, asc};
		KeyFields -> [{KeyField, asc} || KeyField <- KeyFields]
	end.

scanPrimaryKeys(Table) ->
	dbSchemaDef:tablePrimaryKey(Table).

prepareKeysetScanOpts(KeyField, Opts) ->
	OrderOpts = setOpt(order_by, {KeyField, asc}, Opts),
	KeyFieldAtom = pgdbUtils:toAtom(KeyField),
	case proplists:get_value(fields, OrderOpts, undefined) of
		undefined ->
			{OrderOpts, undefined};
		[] ->
			{OrderOpts, undefined};
		Fields ->
			case hasField(Fields, KeyField) of
				true -> {OrderOpts, undefined};
				false -> {setOpt(fields, [KeyField | Fields], OrderOpts), KeyFieldAtom}
			end
	end.

hasField(Fields, FieldName) ->
	FieldBin = pgdbUtils:makeName(FieldName),
	lists:any(fun(Field) -> pgdbUtils:makeName(Field) =:= FieldBin end, Fields).

resolveNextKeyCursor(Table, Rows, KeyField) ->
	case getRowFieldValue(Table, lists:last(Rows), KeyField) of
		undefined -> {error, {missing_key_field, KeyField}};
		Cursor -> {ok, Cursor}
	end.

getRowFieldValue(_Table, Row, FieldName) when is_map(Row) ->
	FieldAtom = pgdbUtils:toAtom(FieldName),
	{ok, Value} = maps:find(FieldAtom, Row),
	Value;
getRowFieldValue(Table, Row, FieldName) when is_tuple(Row) ->
	case lists:keyfind(FieldName, 4, dbSchemaDef:tableFields(Table)) of
		{_NameBin, Index, _Codec, _NameAtom} -> element(Index, Row);
		_ -> undefined
	end.

safeFoldRows('$foreachFun', Rows, Fun) ->
	try
		lists:foreach(Fun, Rows),
		{ok, '$foreachFun'}
	catch
		throw:{error, _} = Err -> Err;
		Class:Reason:Stack -> {error, {callback_failed, Class, Reason, Stack}}
	end;
safeFoldRows(Acc, Rows, Fun) ->
	try
		{ok, lists:foldl(Fun, Acc, Rows)}
	catch
		throw:{error, _} = Err -> Err;
		Class:Reason:Stack -> {error, {callback_failed, Class, Reason, Stack}}
	end.

maybeAppendCursorWhere(Where, _KeyField, undefined) ->
	Where;
maybeAppendCursorWhere(Where, KeyField, LastKey) ->
	toWhereList(Where) ++ [{KeyField, '>', LastKey}].

toWhereList(Where) when is_map(Where) ->
	maps:to_list(Where);
toWhereList(Where) when is_list(Where) ->
	Where.

setOpt(Key, Value, Opts) ->
	lists:keystore(Key, 1, Opts, {Key, Value}).

removeOpt(Key, Opts) ->
	proplists:delete(Key, Opts).

calcTotalPages(0, _PageSize) ->
	0;
calcTotalPages(Total, PageSize) ->
	(Total + PageSize - 1) div PageSize.

normalizeAddColumnOpts(Opts) ->
	lists:filtermap(
		fun
			(primary_key) -> {true, primary_key};
			(not_null) -> {true, not_null};
			(unique) -> {true, unique};
			({default, Value}) -> {true, {default, Value}};
			({not_null, true}) -> {true, not_null};
			({not_null, false}) -> false;
			({references, {_RefTable, _RefCol} = Ref}) -> {true, {references, Ref}};
			({references, {_RefTable, _RefCol, _OnDelete} = Ref}) -> {true, {references, Ref}};
			({check, Expr}) -> {true, {check, Expr}};
			({index, true}) -> {true, {index, true}};
			({index, false}) -> false;
			(_) -> false
		end, Opts).

maybeCreateAddColumnIndex(Table, ColName, Opts) ->
	case proplists:get_value(index, Opts, false) of
		true -> addIndex(Table, [ColName]);
		_ -> ok
	end.

groupNamedColumns(Rows) ->
	maps:values(lists:foldl(fun({ConstraintName, ColumnName}, Acc) ->
		maps:update_with(ConstraintName,
			fun(Item) -> Item#{columns := maps:get(columns, Item) ++ [ColumnName]} end,
			#{name => ConstraintName, columns => [ColumnName]},
			Acc) end, #{}, Rows)).

groupForeignKeys(Rows) ->
	maps:values(lists:foldl(fun({ConstraintName, ColumnName, RefTable, RefColumn}, Acc) ->
		maps:update_with(ConstraintName,
			fun(Item) -> Item#{columns := maps:get(columns, Item) ++ [ColumnName], referenced_columns := maps:get(referenced_columns, Item) ++ [RefColumn]} end,
			#{name => ConstraintName, columns => [ColumnName], referenced_table => RefTable,
				referenced_columns => [RefColumn]},
			Acc) end, #{}, Rows)).

splitCsvBinary(null) ->
	[];
splitCsvBinary(Value) when is_binary(Value) ->
	binary:split(Value, <<",">>, [global]).

tupleRowToMap([], _Index, _Row, Acc) ->
	Acc;
tupleRowToMap([Col | Cols], Index, Row, Acc) ->
	Field = element(2, Col),
	Value = element(Index, Row),
	NewAcc = Acc#{pgdbUtils:toAtom(Field) => Value},
	tupleRowToMap(Cols, Index + 1, Row, NewAcc).

validateMigrations(Migrations) ->
	Versions = [Version || {Version, _Desc, _UpFun, _DownFun} <- Migrations],
	case duplicateVersions(Versions, #{}, []) of
		[] -> ok;
		Duplicates -> {error, {duplicate_migration_versions, lists:reverse(Duplicates)}}
	end.

duplicateVersions([], _Seen, Duplicates) ->
	Duplicates;
duplicateVersions([Version | Rest], Seen, Duplicates) ->
	case maps:is_key(Version, Seen) of
		true ->
			case lists:member(Version, Duplicates) of
				true -> duplicateVersions(Rest, Seen, Duplicates);
				false -> duplicateVersions(Rest, Seen, [Version | Duplicates])
			end;
		false ->
			duplicateVersions(Rest, Seen#{Version => true}, Duplicates)
	end.

equery(SQL, Params) ->
	dealQuery({equery, SQL, Params}, ?queryTimeOut).

squery(SQL) ->
	dealQuery({squery, SQL}, ?queryTimeOut).

testFawSync(Thing) ->
	dealQuery({testSync, Thing}, ?queryTimeOut).

execDdl(SQL) ->
	normalizeDdlResult(squery(SQL)).

dbEquery(Conn, SQL, Params) ->
	epgsql:equery(Conn, SQL, Params).

dbSquery(Conn, SQL) ->
	epgsql:squery(Conn, SQL).

dealQuery(Query, Timeout) ->
	case persistent_term:get(?pgdbPool, undefined) of
		undefined ->
			{error, poolNotExist};
		{WaitPRef, IdleWRef} ->
			case eFaw:checkOut(?pgdbPool, WaitPRef, IdleWRef, Timeout) of
				{ok, WorkerPid} ->
					try
						Ret = executePoolQuery(WorkerPid, Query, Timeout),
						case Ret of
							{error, disconnected} ->
								fwPMgr:stopWorker(?pgdbPool, WorkerPid);
							_ ->
								eFaw:checkIn(WaitPRef, IdleWRef, WorkerPid)
						end,
						Ret
					catch C:R:S ->
						%% 无论成功还是失败，都必须把 worker 归还给进程池
						eFaw:checkIn(WaitPRef, IdleWRef, WorkerPid),
						{error, {C, R, S}}
					end;
				ErrRet ->
					ErrRet
			end
	end.

executePoolQuery(ConnPid, Query, _Timeout) ->
	Start = erlang:monotonic_time(millisecond),
	Ret = handlePoolTaskReply(ConnPid, doPoolTask(ConnPid, Query)),
	DurationMs = erlang:monotonic_time(millisecond) - Start,
	DurationMs > persistent_term:get('$slowThreshold', ?slowThreshold) andalso ?PgWarn("pgdbWorker slow task (~B ms): ~p return:~p~n", [DurationMs, Query, Ret]),
	Ret.

handlePoolTaskReply(_ConnPid, {raise, C, R, S}) ->
	{error, {C, R, S}};
handlePoolTaskReply(_ConnPid, {error, disconnected} = Reply) ->
	Reply;
handlePoolTaskReply(_ConnPid, Reply) ->
	Reply.

doPoolTask(ConnPid, {equery, SQL, Params}) ->
	normalizePoolDbResult(epgsql:equery(ConnPid, SQL, Params));
doPoolTask(ConnPid, {squery, SQL}) ->
	normalizePoolDbResult(epgsql:squery(ConnPid, SQL));
doPoolTask(ConnPid, {with_connection, Fun}) ->
	try
		normalizePoolDbResult(Fun(ConnPid))
	catch
		Class:WithConnReason:WithConnStack ->
			{raise, Class, WithConnReason, WithConnStack}
	end;
doPoolTask(ConnPid, {transaction, Fun}) ->
	try
		case epgsql:with_transaction(ConnPid, Fun) of
			{rollback, RollbackReason} ->
				{error, {transaction_rollback, RollbackReason}};
			Result ->
				normalizePoolTransactionResult(Result)
		end
	catch
		Class:TxReason:TxStack ->
			{raise, Class, TxReason, TxStack}
	end;
doPoolTask(_ConnPid, {testSync, Thing}) ->
	Thing;
doPoolTask(_ConnPid, _Task) ->
	{error, unknown_task}.

normalizePoolTransactionResult({error, _} = Result) ->
	normalizePoolDbResult(Result);
normalizePoolTransactionResult(Result) ->
	{ok, Result}.

normalizePoolDbResult({error, _} = Result) ->
	case isPoolDisconnError(Result) of
		true ->
			{error, disconnected};
		false ->
			Result
	end;
normalizePoolDbResult(Result) ->
	Result.

isPoolDisconnError({error, #{code := <<"57P01">>}}) ->
	true;
isPoolDisconnError({error, #{code := <<"57P03">>}}) ->
	true;
isPoolDisconnError({error, #{code := <<"08000">>}}) ->
	true;
isPoolDisconnError({error, #{code := <<"08001">>}}) ->
	true;
isPoolDisconnError({error, #{code := <<"08003">>}}) ->
	true;
isPoolDisconnError({error, #{code := <<"08004">>}}) ->
	true;
isPoolDisconnError({error, #{code := <<"08006">>}}) ->
	true;
isPoolDisconnError({error, disconnected}) ->
	true;
isPoolDisconnError({error, socket_closed}) ->
	true;
isPoolDisconnError(_) ->
	false.

validateJustAppendOnly(Table, SchFields, ExistingOrderedCols) ->
	SchemaOrderedNames = [pgdbUtils:makeName(FieldName) || #schField{name = FieldName} <- SchFields],
	ExistingOrderedNames = [OFieldName || {OFieldName, _ODbType} <- ExistingOrderedCols],
	ExistingLen = length(ExistingOrderedCols),
	case lists:sublist(SchemaOrderedNames, ExistingLen) of
		ExistingOrderedNames ->
			ok;
		SchemaPrefix ->
			{error, {non_append_only_column_change, #{table => Table, existing_order => ExistingOrderedNames, schema_order => SchemaOrderedNames, schema_prefix => SchemaPrefix}}}
	end.

%% @doc 判断 Schema 定义的类型是否与数据库实际 data_type 匹配。
%% 匹配返回 true，不匹配返回 false；未知类型保守返回 true（不触发 ALTER）。
pgTypeMatches(integer, <<"integer">>) -> true;
pgTypeMatches(int, <<"integer">>) -> true;
pgTypeMatches(bigint, <<"bigint">>) -> true;
pgTypeMatches(smallint, <<"smallint">>) -> true;
pgTypeMatches(serial, <<"integer">>) -> true;
pgTypeMatches(bigserial, <<"bigint">>) -> true;
pgTypeMatches(text, <<"text">>) -> true;
pgTypeMatches({varchar, _}, <<"character varying">>) -> true;
pgTypeMatches({char, _}, <<"character">>) -> true;
pgTypeMatches(boolean, <<"boolean">>) -> true;
pgTypeMatches(bool, <<"boolean">>) -> true;
pgTypeMatches(float, <<"real">>) -> true;
pgTypeMatches(double, <<"double precision">>) -> true;
pgTypeMatches(numeric, <<"numeric">>) -> true;
pgTypeMatches({numeric, _, _}, <<"numeric">>) -> true;
pgTypeMatches(json, <<"json">>) -> true;
pgTypeMatches(jsonb, <<"jsonb">>) -> true;
pgTypeMatches(bytea, <<"bytea">>) -> true;
pgTypeMatches(uuid, <<"uuid">>) -> true;
pgTypeMatches(inet, <<"inet">>) -> true;
pgTypeMatches(timestamp, <<"timestamp without time zone">>) -> true;
pgTypeMatches(timestamptz, <<"timestamp with time zone">>) -> true;
pgTypeMatches(date, <<"date">>) -> true;
pgTypeMatches(time, <<"time without time zone">>) -> true;
pgTypeMatches({array, _}, <<"ARRAY">>) -> true;
pgTypeMatches({enum, _}, <<"USER-DEFINED">>) -> true;
pgTypeMatches(Same, Same) -> true;
pgTypeMatches(_, _) -> false.

%% @doc 根据字段定义中的 {index, true} 选项自动创建索引。
autoCreateIndexes(Table, Fields) ->
	[
		begin
			case pgdbUtils:getOpt(index, Opts, false) of
				true -> ?CASE(ok == addIndex(Table, [Name]), ok, throw({error, {index_creation_failed, Table, Name}}));
				_ -> ok
			end

		end || #schField{name = Name, opts = Opts} <- Fields
	],
	ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%编码%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%===================================================================
%%% Codec 编解码（按 schField.codec 字段分派）
%%%===================================================================
%% @doc 按 codec 策略编码值。undefined 表示不做 codec 转换。
enCodecValue(_, _Table, _Field, null) -> null;
enCodecValue(_, _Table, _Field, undefined) -> null;
enCodecValue(?codec_temp, _Table, _Field, _Value) -> null;
enCodecValue(?codec_undefined, _Table, _Field, Value) -> Value;
enCodecValue(?codec_json, _Table, _Field, Value) -> jiffy:encode(Value);
enCodecValue(?codec_term_str, _Table, _Field, Value) -> term_to_string(Value);
enCodecValue(?codec_term_binary, _Table, _Field, Value) -> term_to_binary(Value);
enCodecValue(?codec_atom, _Table, _Field, Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
enCodecValue(?codec_custom(M, F, A), Table, Field, Value) ->
	try M:F(encode, Table, Field, A, Value)
	catch _:_ ->
		?PgErr("Custom codec:~p encode failed for ~p.~p with value: ~p", [{M, F, A}, Table, Field, Value]),
		null
	end;
enCodecValue(_, _Table, _Field, Value) -> Value.

%% @doc 按 codec 策略解码值。undefined 表示不做 codec 转换。
deCodecValue(_, Table, Field, null) -> dbSchemaDef:fieldDefault(Table, Field);
deCodecValue(?codec_undefined, _Table, _Field, Value) -> Value;
deCodecValue(?codec_temp, Table, Field, _Value) -> dbSchemaDef:fieldDefault(Table, Field);
deCodecValue(?codec_json, _Table, _Field, Value) when is_binary(Value) ->
	try jiffy:decode(Value, [return_maps])
	catch _:_ ->
		?PgErr("Custom codec:~p decode failed for ~p.~p with value: ~p", [?codec_json, _Table, _Field, Value]),
		Value
	end;
deCodecValue(?codec_term_str, _Table, _Field, Value) when is_binary(Value) ->
	case string_to_term(Value) of
		{ok, Term} -> Term;
		_ ->
			?PgErr("Custom codec:~p decode failed for ~p.~p with value: ~p", [?codec_term_str, _Table, _Field, Value]),
			Value
	end;
deCodecValue(?codec_term_binary, _Table, _Field, Value) when is_binary(Value) ->
	try binary_to_term(Value, [safe])
	catch _:_ ->
		?PgErr("Custom codec:~p decode failed for ~p.~p with value: ~p", [?codec_term_binary, _Table, _Field, Value]),
		Value
	end;
deCodecValue(?codec_atom, _Table, _Field, Value) when is_binary(Value) ->
	try binary_to_atom(Value, utf8)
	catch _:_ ->
		?PgErr("Custom codec:~p decode failed for ~p.~p with value: ~p", [?codec_atom, _Table, _Field, Value]),
		Value
	end;
deCodecValue(?codec_custom(M, F, A), Table, Field, Value) ->
	try M:F(decode, Table, Field, A, Value)
	catch _:_ ->
		?PgErr("Custom codec:~p decode failed for ~p.~p with value: ~p", [{M, F, A}, Table, Field, Value]),
		Value
	end;
deCodecValue(_, _Table, _Field, Value) -> Value.

enWheres(Table, Where) when is_map(Where) ->
	maps:fold(fun(Key, Value, Acc) -> Acc#{Key => enWhereValue(Table, Key, Value)} end, #{}, Where);
enWheres(Table, Where) when is_list(Where) ->
	[enWhereItem(Table, Item) || Item <- Where].

%%%===================================================================
%%% 内部函数
%%%===================================================================
enWhereItem(Table, {'or', OrConds}) ->
	{'or', [enWheres(Table, Cond) || Cond <- OrConds]};
enWhereItem(Table, {Key, Value}) ->
	{Key, enWhereValue(Table, Key, Value)};
enWhereItem(Table, {Key, Op, Value}) ->
	{Key, Op, enFieldValue(Table, Key, Value)}.

enWhereValue(Table, Key, Value) ->
	case Value of
		null -> null;
		not_null -> not_null;
		{raw, _} -> Value;
		{in, List} when is_list(List) -> {in, [enFieldValue(Table, Key, Item) || Item <- List]};
		{not_in, List} when is_list(List) -> {not_in, [enFieldValue(Table, Key, Item) || Item <- List]};
		{between, V1, V2} -> {between, enFieldValue(Table, Key, V1), enFieldValue(Table, Key, V2)};
		{jsonb_contains, JsonValue} -> {jsonb_contains, jiffy:encode(JsonValue)};
		{jsonb_key, Path, SubOp, V} -> {jsonb_key, Path, SubOp, V};
		{'>', V} -> {'>', enFieldValue(Table, Key, V)};
		{'>=', V} -> {'>=', enFieldValue(Table, Key, V)};
		{'<', V} -> {'<', enFieldValue(Table, Key, V)};
		{'<=', V} -> {'<=', enFieldValue(Table, Key, V)};
		{'!=', V} -> {'!=', enFieldValue(Table, Key, V)};
		{'<>', V} -> {'<>', enFieldValue(Table, Key, V)};
		{like, V} -> {like, enFieldValue(Table, Key, V)};
		{ilike, V} -> {ilike, enFieldValue(Table, Key, V)};
		_ -> enFieldValue(Table, Key, Value)
	end.

enFieldValue(Table, Field, Value) ->
	Codec = dbSchemaDef:fieldCodec(Table, Field),
	enCodecValue(Codec, Table, Field, Value).

%% term序列化, term转为string
term_to_string(Term) ->
	unicode:characters_to_binary(eFmt:formatIol("~0tp", [Term])).

%% term反序列化, string转换为term
string_to_term(String) ->
	Str = case is_binary(String) of true -> unicode:characters_to_list(String);  _ -> String end,

	case erl_scan:string(Str ++ ".") of
		{ok, Tokens, _} ->
			case erl_parse:parse_term(Tokens) of
				{ok, Term} -> {ok, Term};
				Error -> {error, Error}
			end;
		Error ->
			{error, Error}
	end.

%% @doc 自定义 codec 示例。
%% encode 时把 A 和 Value 一起序列化到 bytea；decode 时校验 A 后还原 Value。
demo_custom_codec(encode, _Table, _Field, Value, A) ->
	term_to_binary({A, Value});
demo_custom_codec(decode, _Table, _Field, Value, A) when is_binary(Value) ->
	try binary_to_term(Value, [safe]) of
		{A, Decoded} -> Decoded;
		Other -> Other
	catch error:badarg -> Value
	end;
demo_custom_codec(_Action, _Table, _Field, Value, _A) ->
	Value.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%编码%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
