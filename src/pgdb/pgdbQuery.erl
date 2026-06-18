%%%-------------------------------------------------------------------
%%% @doc SQL 构建器。
%%% 用 Erlang 数据结构生成参数化 SQL，内部统一采用 iolist 组装，
%%% 减少频繁使用 ++ 带来的拷贝开销。
%%%-------------------------------------------------------------------
-module(pgdbQuery).

-include("pgdbSchema.hrl").
-include("ePgdb.hrl").

-export([
	buildWhere/2,
	buildSelect/3,
	buildUpdate/3,
	buildDelete/2,
	buildUpsert/4,
	buildBatchInsert/2,
	buildBatchInsert/3,
	buildBatchUpdate/5,
	buildBatchDeleteByKey/3,
	buildCreateTable/2,
	buildAddColumn/3,
	buildAddColumn/4,
	buildDropColumn/2,
	buildTruncateTable/1,
	buildRenameTable/2,
	buildRenameColumn/3,
	buildAlterColumnType/3,
	buildAddIndex/3,
	sqlCast/1,
	typeToSql/1
]).

%%%===================================================================
%%% SELECT
%%%===================================================================

%% @doc 构建 SELECT 语句。
%% 选项支持：fields, order_by, limit, offset, group_by, having, for_update
buildSelect(Table, Where, Opts) ->
	Fields = pgdbUtils:getOpt(fields, Opts, []),
	FieldSql = buildField(Fields),
	{WhereSql, WhereParams, NextIdx} = buildWhere(Where, 1),
	OrderSql = buildOrderBy(pgdbUtils:getOpt(order_by, Opts, undefined)),
	GroupSql = buildGroupBy(pgdbUtils:getOpt(group_by, Opts, undefined)),
	{HavingSql, HavingParams, NextIdx2} = buildHaving(pgdbUtils:getOpt(having, Opts, undefined), NextIdx),
	{LimitSql, LimitParams, NextIdx3} = buildLimit(pgdbUtils:getOpt(limit, Opts, undefined), NextIdx2),
	{OffsetSql, OffsetParams, _NextIdx4} = buildOffset(pgdbUtils:getOpt(offset, Opts, undefined), NextIdx3),
	ForUpdateSql = ?CASE(pgdbUtils:getOpt(for_update, Opts, false), <<" FOR UPDATE">>, <<>>),
	SQL = [<<"SELECT ">>, FieldSql, <<" FROM ">>, pgdbUtils:makeName(Table), WhereSql, GroupSql, HavingSql, OrderSql, LimitSql, OffsetSql, ForUpdateSql],
	Params = WhereParams ++ HavingParams ++ LimitParams ++ OffsetParams,
	{SQL, Params, Fields == []}.

%%%===================================================================
%%% BATCH INSERT
%%%===================================================================

buildBatchInsert(Table, Rows) ->
	buildBatchInsert(Table, Rows, <<>>).

%% OnConflictSql: 主键冲突时的 ON CONFLICT 子句（含前导空格），无则传 <<>>。
buildBatchInsert(Table, Rows, OnConflictSql) when is_binary(OnConflictSql) ->
	{PlaceholderAcc, _} = buildBatchValueRows(Rows, 1),
	SQL = [<<"INSERT INTO ">>, pgdbUtils:makeName(Table), <<" VALUES ">>, PlaceholderAcc, OnConflictSql],
	{SQL, lists:append(Rows)}.

%%%===================================================================
%%% UPDATE
%%%===================================================================

buildUpdate(Table, SetData, Where) ->
	{SetCols, SetVals} = lists:unzip(SetData),
	{SetSql, NextIdx} = buildSetClause(SetCols, 1),
	{WhereSql, WhereParams, _} = buildWhere(Where, NextIdx),
	SQL = [<<"UPDATE ">>, pgdbUtils:makeName(Table), <<" SET ">>, SetSql, WhereSql],
	{SQL, SetVals ++ WhereParams}.

%% @doc 按主键批量 patch 更新：每行可更新不同列；列在 Items 中出现即写入（含 NULL）。
%% UpItems: [{DirtyMask, [{NameBin, EnValue}], KeyEnValue}]
%% SetFields: [{Index, NameBin, SqlCast}]
%% RowCasts: VALUES 每行占位符的 PG cast 片段，由调用方按 schema dbType 生成（见 sqlCast/1），
%%   顺序为 [KeyCast, Col1SetCast, Col1Cast, Col2SetCast, Col2Cast, ...]，长度 = 1 + 2 * length(SetFields)。
buildBatchUpdate(Table, KeyField, KeyCast, SetFields, UpItems) ->
	KeyBin = pgdbUtils:makeName(KeyField),
	AsSql = <<<<", ", (pgdbUtils:makeName(Field))/binary, "_set, ", (pgdbUtils:makeName(Field))/binary>> || {_SetIndex, Field, _SqlCast} <- SetFields>>,
	TSetSql = <<<<", ", (pgdbUtils:makeName(Field))/binary, " = CASE WHEN v.", (pgdbUtils:makeName(Field))/binary, "_set THEN v.", (pgdbUtils:makeName(Field))/binary, " ELSE t.", (pgdbUtils:makeName(Field))/binary, " END">> || {_SetIndex, Field, _SqlCast} <- SetFields>>,
	SetSql = ?CASE(TSetSql, <<>>, <<>>, <<_:16, TTSetSql/binary>>, TTSetSql),
	{<<_:16, ValuesSql/binary>>, _ValueIndex, Params} = lists:foldl(
		fun({OneDirtyMask, OneUpItems, OneEnKeyValue}, {ValuesSqlAcc, ValueIndexAcc, ParamsAcc}) ->
			{ValuePlaceholders, NewValueIndexAcc} = buildTypedPlaceholdersKey([{0, KeyBin, KeyCast} | SetFields], ValueIndexAcc, <<>>),
			UpParams = packParamValues(SetFields, OneUpItems, OneDirtyMask, [OneEnKeyValue]),
			{<<ValuesSqlAcc/binary, ", (", ValuePlaceholders/binary, ")">>, NewValueIndexAcc, UpParams ++ ParamsAcc}
		end, {<<>>, 1, []}, UpItems),
	SQL = [<<"UPDATE ">>, pgdbUtils:makeName(Table), <<" AS t SET ">>, SetSql, <<" FROM (VALUES ">>, ValuesSql, <<") AS v(">>, KeyBin, AsSql, <<") WHERE t.">>, KeyBin, <<" = v.">>, KeyBin],
	{SQL, Params}.

packParamValues([], _Items, _DirtyMask, Acc) -> lists:reverse(Acc);
packParamValues([{Index, NameBin, _SqlCast} | SetFields], UpItems, DirtyMask, Acc) ->
	case DirtyMask band (1 bsl (Index - 1)) of
		0 ->
			packParamValues(SetFields, UpItems, DirtyMask, [null, false | Acc]);
		_ ->
			[{NameBin, EnValue} | LeftUpItems] = UpItems,
			packParamValues(SetFields, LeftUpItems, DirtyMask, [EnValue, true | Acc])
	end.

%%%===================================================================
%%% DELETE
%%%===================================================================

buildDelete(Table, Where) ->
	{WhereSql, WhereParams, _} = buildWhere(Where, 1),
	{[<<"DELETE FROM ">>, pgdbUtils:makeName(Table), WhereSql], WhereParams}.

%% @doc 按主键 IN 列表批量删除。
buildBatchDeleteByKey(Table, KeyField, Keys) when is_list(Keys), length(Keys) > 0 ->
	{Placeholders, _NextIdx} = buildPlaceholders(length(Keys), 1, <<>>),
	SQL = [<<"DELETE FROM ">>, pgdbUtils:makeName(Table), <<" WHERE ">>, pgdbUtils:makeName(KeyField), <<" IN (">>, Placeholders, <<")">>],
	{SQL, Keys}.

%%%===================================================================
%%% UPSERT
%%%===================================================================

buildUpsert(Table, Data, ConflictKeys, UpdateFields) ->
	{Columns, Values} = lists:unzip(Data),
	ColSql = buildField(Columns),
	{Placeholders, _NextIdx} = buildPlaceholders(length(Values), 1, <<>>),
	ConflictSql = buildField(ConflictKeys),
	SQL = [<<"INSERT INTO ">>, pgdbUtils:makeName(Table), <<" (">>, ColSql,
		<<") VALUES (">>, Placeholders, <<") ON CONFLICT (">>, ConflictSql,
		<<") ">>, buildUpsertActionSql(Columns, ConflictKeys, UpdateFields), <<" RETURNING *">>],
	{SQL, Values}.

%%%===================================================================
%%% 建表与改表
%%%===================================================================

buildCreateTable(Table, Fields) ->
	ColSqls = [buildColumnDef(Name, DbType, Opts) || #schField{name = Name, dbType = DbType, opts = Opts} <- Fields],
	TParts = <<<<",\n  ", (iolist_to_binary(Col))/binary>> || Col <- ColSqls>>,
	Joined = ?CASE(TParts, <<>>, <<>>, <<_:32, TTParts/binary>>, TTParts),
	[<<"CREATE TABLE IF NOT EXISTS ">>, pgdbUtils:makeName(Table), <<" (\n  ">>, Joined, <<"\n)">>].

buildColumnDef(Name, Type, Opts) ->
	[pgdbUtils:makeName(Name), <<" ">>, typeToSql(Type), buildColumnOpts(Opts)].

buildColumnOpts([]) ->
	<<>>;
buildColumnOpts(Opts) ->
	DdlOpts = [Opt || Opt <- Opts, isDdlColumnOpt(Opt)],
	case DdlOpts of
		[] -> <<>>;
		_ ->
			TParts = <<<<" ", (iolist_to_binary(columnOptToSql(Opt)))/binary>> || Opt <- DdlOpts>>,
			OptSql = ?CASE(TParts, <<>>, <<>>, <<_:8, TTParts/binary>>, TTParts),
			[<<" ">>, OptSql]
	end.

isDdlColumnOpt(primary_key) -> true;
isDdlColumnOpt(not_null) -> true;
isDdlColumnOpt(unique) -> true;
isDdlColumnOpt({default, _}) -> true;
isDdlColumnOpt({references, _}) -> true;
isDdlColumnOpt({check, _}) -> true;
isDdlColumnOpt(_) -> false.

columnOptToSql(primary_key) -> <<"PRIMARY KEY">>;
columnOptToSql(not_null) -> <<"NOT NULL">>;
columnOptToSql(unique) -> <<"UNIQUE">>;
columnOptToSql({default, now}) -> <<"DEFAULT NOW()">>;
columnOptToSql({default, Value}) when is_integer(Value) -> [<<"DEFAULT ">>, integer_to_binary(Value)];
columnOptToSql({default, Value}) when is_float(Value) -> [<<"DEFAULT ">>, float_to_list(Value, [{decimals, 10}, compact])];
columnOptToSql({default, true}) -> <<"DEFAULT TRUE">>;
columnOptToSql({default, false}) -> <<"DEFAULT FALSE">>;
columnOptToSql({default, null}) -> <<"DEFAULT NULL">>;
columnOptToSql({default, {raw, SQL}}) -> [<<"DEFAULT ">>, SQL];
columnOptToSql({default, []}) -> <<"DEFAULT '{}'">>;
columnOptToSql({default, Value}) when is_map(Value) -> [<<"DEFAULT '">>, jiffy:encode(Value), <<"'::jsonb">>];
columnOptToSql({default, Value}) when is_list(Value) -> [<<"DEFAULT ">>, pgdbUtils:quoteLiteral(Value)];
columnOptToSql({default, Value}) when is_binary(Value) -> [<<"DEFAULT ">>, pgdbUtils:quoteLiteral(Value)];
columnOptToSql({references, {RefTable, RefCol}}) ->
	[<<"REFERENCES ">>, pgdbUtils:makeName(RefTable), <<"(">>, pgdbUtils:makeName(RefCol), <<")">>];
columnOptToSql({references, {RefTable, RefCol, OnDelete}}) ->
	[<<"REFERENCES ">>, pgdbUtils:makeName(RefTable), <<"(">>, pgdbUtils:makeName(RefCol),
		<<") ON DELETE ">>, onActionToSql(OnDelete)];
columnOptToSql({check, Expr}) -> [<<"CHECK (">>, Expr, <<")">>].

onActionToSql(cascade) -> <<"CASCADE">>;
onActionToSql(set_null) -> <<"SET NULL">>;
onActionToSql(restrict) -> <<"RESTRICT">>;
onActionToSql(no_action) -> <<"NO ACTION">>.

buildAddColumn(Table, ColName, Type) ->
	[<<"ALTER TABLE ">>, pgdbUtils:makeName(Table), <<" ADD COLUMN IF NOT EXISTS ">>, pgdbUtils:makeName(ColName), <<" ">>, typeToSql(Type)].

buildAddColumn(Table, ColName, Type, Opts) ->
	[buildAddColumn(Table, ColName, Type), buildColumnOpts(Opts)].

buildDropColumn(Table, ColName) ->
	[<<"ALTER TABLE ">>, pgdbUtils:makeName(Table), <<" DROP COLUMN IF EXISTS ">>, pgdbUtils:makeName(ColName)].

buildTruncateTable(Table) ->
	[<<"TRUNCATE TABLE ">>, pgdbUtils:makeName(Table)].

buildRenameTable(Table, NewName) ->
	[<<"ALTER TABLE ">>, pgdbUtils:makeName(Table), <<" RENAME TO ">>, pgdbUtils:makeName(NewName)].

buildRenameColumn(Table, OldName, NewName) ->
	[<<"ALTER TABLE ">>, pgdbUtils:makeName(Table), <<" RENAME COLUMN ">>, pgdbUtils:makeName(OldName), <<" TO ">>, pgdbUtils:makeName(NewName)].

buildAlterColumnType(Table, ColName, NewType) ->
	[<<"ALTER TABLE ">>, pgdbUtils:makeName(Table), <<" ALTER COLUMN ">>, pgdbUtils:makeName(ColName), <<" TYPE ">>, typeToSql(NewType)].

%%%===================================================================
%%% 索引
%%%===================================================================

buildAddIndex(Table, Columns, Opts) ->
	Unique = pgdbUtils:getOpt(unique, Opts, false),
	IndexName = pgdbUtils:getOpt(name, Opts, defaultIndexName(Table, Columns)),
	Method = pgdbUtils:getOpt(method, Opts, btree),
	UniqueSql = case Unique of true -> <<"UNIQUE ">>; _ -> <<>> end,
	MethodSql = case Method of
					btree -> <<>>;
					gin -> <<" USING gin">>;
					gist -> <<" USING gist">>;
					hash -> <<" USING hash">>
				end,
	TParts = <<<<", ", (pgdbUtils:makeName(Col))/binary>> || Col <- Columns>>,
	ColsSql = ?CASE(TParts, <<>>, <<>>, <<_:16, TTParts/binary>>, TTParts),
	[<<"CREATE ">>, UniqueSql, <<"INDEX IF NOT EXISTS ">>, pgdbUtils:makeName(IndexName), <<" ON ">>, pgdbUtils:makeName(Table), MethodSql, <<" (">>, ColsSql, <<")">>].

%%%===================================================================
%%% WHERE 条件
%%%===================================================================
buildWhere(Conditions, StartIdx) ->
	{ClauseSql, Params, NextIdx} = buildConditionGroup(Conditions, StartIdx),
	case ClauseSql of
		<<>> -> {<<>>, Params, NextIdx};
		_ -> {[<<" WHERE ">>, ClauseSql], Params, NextIdx}
	end.

buildConditionGroup(Conditions, StartIdx) when is_map(Conditions) ->
	Fun =
		fun(Key, Value, {ClauseAcc, ParamAcc, Idx}) ->
			{Clause, Param, NewIdx} = buildCondition(Key, Value, Idx),
			{<<ClauseAcc/binary, " AND ", Clause/binary>>, Param ++ ParamAcc, NewIdx}
		end,
	{TClauses, Params, NextIdx} = maps:fold(Fun, {<<>>, [], StartIdx}, Conditions),
	Clauses = ?CASE(TClauses, <<>>, <<>>, <<_:40, TTClauses/binary>>, TTClauses),
	{Clauses, lists:reverse(Params), NextIdx};
buildConditionGroup(Conditions, StartIdx) when is_list(Conditions) ->
	buildWhereList(Conditions, StartIdx).

buildWhereList([], StartIdx) ->
	{<<>>, [], StartIdx};
buildWhereList(Conditions, StartIdx) ->
	FunOr =
		fun(Cond, {OrClauseAcc, OrParamAcc, OrIdx}) ->
			{Clause, Params, TempIdx} = buildConditionGroup(Cond, OrIdx),
			{<<OrClauseAcc/binary, " OR ", Clause/binary>>, lists:reverse(Params) ++ OrParamAcc, TempIdx}
		end,
	Fun =
		fun
			({'or', OrConds}, {ClauseAcc, ParamAcc, Idx}) ->
				{TOrClauses, OrParams, NewIdx} = lists:foldl(FunOr, {<<>>, [], Idx}, OrConds),
				OrClauses = ?CASE(TOrClauses, <<>>, <<>>, <<_:32, TTOrClauses/binary>>, TTOrClauses),
				{<<ClauseAcc/binary, " AND ", "(", OrClauses/binary, ")">>, OrParams ++ ParamAcc, NewIdx};
			({Key, Value}, {ClauseAcc, ParamAcc, Idx}) ->
				{Clause, Param, NewIdx} = buildCondition(Key, Value, Idx),
				{<<ClauseAcc/binary, " AND ", Clause/binary>>, Param ++ ParamAcc, NewIdx};
			({Key, Op, Value}, {ClauseAcc, ParamAcc, Idx}) ->
				{Clause, Param, NewIdx} = buildCondition(Key, {Op, Value}, Idx),
				{<<ClauseAcc/binary, " AND ", Clause/binary>>, Param ++ ParamAcc, NewIdx}
		end,
	{TClauses, Params, NextIdx} = lists:foldl(Fun, {<<>>, [], StartIdx}, Conditions),
	Clauses = ?CASE(TClauses, <<>>, <<>>, <<_:40, TTClauses/binary>>, TTClauses),
	{Clauses, lists:reverse(Params), NextIdx}.

buildCondition(Key, Value, Idx) ->
	Col = pgdbUtils:makeName(Key),
	case Value of
		null -> {<<Col/binary, " IS NULL">>, [], Idx};
		not_null -> {<<Col/binary, " IS NOT NULL">>, [], Idx};
		{'>', V} -> buildValueCondition(Col, <<" > ">>, V, Idx);
		{'>=', V} -> buildValueCondition(Col, <<" >= ">>, V, Idx);
		{'<', V} -> buildValueCondition(Col, <<" < ">>, V, Idx);
		{'<=', V} -> buildValueCondition(Col, <<" <= ">>, V, Idx);
		{'!=', V} -> buildValueCondition(Col, <<" != ">>, V, Idx);
		{'<>', V} -> buildValueCondition(Col, <<" <> ">>, V, Idx);
		{like, V} -> buildValueCondition(Col, <<" LIKE ">>, V, Idx);
		{ilike, V} -> buildValueCondition(Col, <<" ILIKE ">>, V, Idx);
		{in, List} when is_list(List) ->
			{Placeholders, NewIdx} = buildPlaceholders(length(List), Idx, <<>>),
			{<<Col/binary, " IN (", Placeholders/binary, ")">>, lists:reverse(List), NewIdx};
		{not_in, List} when is_list(List) ->
			{Placeholders, NewIdx} = buildPlaceholders(length(List), Idx, <<>>),
			{<<Col/binary, " NOT IN (", Placeholders/binary, ")">>, lists:reverse(List), NewIdx};
		{between, V1, V2} ->
			{<<Col/binary, " BETWEEN $", (integer_to_binary(Idx))/binary, " AND $", (integer_to_binary(Idx + 1))/binary>>, [V2, V1], Idx + 2};
		{jsonb_contains, V} ->
			{<<Col/binary, " @> $", (integer_to_binary(Idx))/binary, "::jsonb">>, [V], Idx + 1};
		{jsonb_key, Path, SubOp, V} ->
			JsonPath = [Col, buildJsonPath(Path)],
			buildJsonConditionValue(JsonPath, SubOp, V, Idx);
		{raw, RawSql} -> {iolist_to_binary(RawSql), [], Idx};
		_ -> buildValueCondition(Col, <<" = ">>, Value, Idx)
	end.

buildValueCondition(ColExpr, Op, Value, Idx) ->
	{<<ColExpr/binary, Op/binary, "$", (integer_to_binary(Idx))/binary>>, [Value], Idx + 1}.

buildConditionValue(ColExpr, '=', V, Idx) ->
	{iolist_to_binary([ColExpr, <<" = $">>, integer_to_binary(Idx)]), [V], Idx + 1};
buildConditionValue(ColExpr, Op, V, Idx) ->
	{iolist_to_binary([ColExpr, <<" ">>, atom_to_binary(Op, utf8), <<" $">>, integer_to_binary(Idx)]), [V], Idx + 1}.

buildJsonConditionValue(ColExpr, Op, V, Idx) when is_integer(V) ->
	buildConditionValue(castJsonTextExpr(ColExpr, <<"bigint">>), Op, V, Idx);
buildJsonConditionValue(ColExpr, Op, V, Idx) when is_float(V) ->
	buildConditionValue(castJsonTextExpr(ColExpr, <<"double precision">>), Op, V, Idx);
buildJsonConditionValue(ColExpr, Op, true, Idx) ->
	buildConditionValue(castJsonTextExpr(ColExpr, <<"boolean">>), Op, true, Idx);
buildJsonConditionValue(ColExpr, Op, false, Idx) ->
	buildConditionValue(castJsonTextExpr(ColExpr, <<"boolean">>), Op, false, Idx);
buildJsonConditionValue(ColExpr, Op, V, Idx) when is_atom(V) ->
	buildConditionValue(ColExpr, Op, atom_to_binary(V, utf8), Idx);
buildJsonConditionValue(ColExpr, Op, V, Idx) when is_list(V) ->
	case io_lib:printable_unicode_list(V) of
		true -> buildConditionValue(ColExpr, Op, unicode:characters_to_binary(V), Idx);
		false -> buildConditionValue(ColExpr, Op, encodeJson(V), Idx)
	end;
buildJsonConditionValue(ColExpr, Op, V, Idx) when is_map(V) ->
	buildConditionValue(ColExpr, Op, encodeJson(V), Idx);
buildJsonConditionValue(ColExpr, Op, V, Idx) ->
	buildConditionValue(ColExpr, Op, V, Idx).

castJsonTextExpr(ColExpr, Type) ->
	iolist_to_binary([<<"(">>, ColExpr, <<")::">>, Type]).

buildJsonPath(Path) when is_atom(Path) ->
	iolist_to_binary([<<"->>">>, jsonPathLiteral(atom_to_binary(Path, utf8))]);
buildJsonPath(Path) when is_binary(Path) ->
	iolist_to_binary([<<"->>">>, jsonPathLiteral(Path)]);
buildJsonPath(Path) when is_list(Path) ->
	Last = lists:last(Path),
	{Init, _} = lists:split(length(Path) - 1, Path),
	Prefix = lists:map(fun(Segment) -> [<<"->">>, jsonPathLiteral(toText(Segment))] end, Init),
	iolist_to_binary([Prefix, <<"->>">>, jsonPathLiteral(toText(Last))]).

jsonPathLiteral(Value) ->
	pgdbUtils:quoteLiteral(Value).

%%%===================================================================
%%% 辅助函数
%%%===================================================================
buildPlaceholders(0, Idx, Acc) -> {?CASE(Acc, <<>>, Acc, <<_:16, TAcc/binary>>, TAcc), Idx};
buildPlaceholders(Count, Idx, Acc) ->
	buildPlaceholders(Count - 1, Idx + 1, <<Acc/binary, ", $", (integer_to_binary(Idx))/binary>>).

%% FROM (VALUES ...) 需标注类型，否则 PG 推断为 text；复用 typeToSql，写法比上一版精简。
buildTypedPlaceholdersKey([{_FIdx, _FieldBin, SqlCast} | Casts], Idx, Acc) ->
	buildTypedPlaceholdersField(Casts, Idx + 1, <<Acc/binary, "$", (integer_to_binary(Idx))/binary, SqlCast/binary>>).

buildTypedPlaceholdersField([], Idx, Acc) ->
	{Acc, Idx};
buildTypedPlaceholdersField([{_FIdx, _FieldBin, SqlCast} | Casts], Idx, Acc) ->
	buildTypedPlaceholdersField(Casts, Idx + 2, <<Acc/binary, ", $", (integer_to_binary(Idx))/binary, "::boolean, $", (integer_to_binary(Idx + 1))/binary, SqlCast/binary>>).

%%%===================================================================
%%% 类型转换
%%%===================================================================
%% 与 typeToSql 不同：CAST 用 PG 可接受的类型名（小写、serial→bigint）。
%% dbType 须与 pgdbSchema.hrl 中 ?pg_* 宏一致；调用方用 fieldSchema/2 取 dbType 后传入 buildBatchUpdate/5。
sqlCast(?pg_bigserial) -> <<"::bigint">>;
sqlCast(?pg_serial) -> <<"::bigint">>;
sqlCast(?pg_integer) -> <<"::integer">>;
sqlCast(?pg_int) -> <<"::integer">>;
sqlCast(?pg_bigint) -> <<"::bigint">>;
sqlCast(?pg_smallint) -> <<"::smallint">>;
sqlCast(?pg_float) -> <<"::real">>;
sqlCast(?pg_double) -> <<"::double precision">>;
sqlCast(?pg_numeric(P, S)) -> [<<"::numeric(">>, integer_to_binary(P), <<",">>, integer_to_binary(S), <<")">>];
sqlCast(?pg_text) -> <<"::text">>;
sqlCast(?pg_varchar(_Len)) -> <<"::text">>;
sqlCast(?pg_char(_Len)) -> <<"::text">>;
sqlCast(?pg_uuid) -> <<"::uuid">>;
sqlCast(?pg_inet) -> <<"::inet">>;
sqlCast(?pg_boolean) -> <<"::boolean">>;
sqlCast(?pg_timestamp) -> <<"::timestamp">>;
sqlCast(?pg_timestamptz) -> <<"::timestamptz">>;
sqlCast(?pg_date) -> <<"::date">>;
sqlCast(?pg_time) -> <<"::time">>;
sqlCast(?pg_json) -> <<"::json">>;
sqlCast(?pg_jsonb) -> <<"::jsonb">>;
sqlCast(?pg_bytea) -> <<"::bytea">>;
sqlCast(?pg_array(Inner)) -> [sqlCast(Inner), <<"[]">>];
sqlCast(?pg_enum_atom) -> <<"::text">>;
sqlCast(?pg_enum_binary) -> <<"::text">>;
sqlCast(Other) when is_binary(Other) -> [<<"::">>, Other];
sqlCast(Other) when is_atom(Other) ->
	iolist_to_binary([<<"::">>, atom_to_binary(Other, utf8)]).

%% dbType 须与 pgdbSchema.hrl 中 ?pg_* 宏一致（DDL 用大写 PG 类型名）。
typeToSql(?pg_bigserial) -> <<"BIGSERIAL">>;
typeToSql(?pg_serial) -> <<"SERIAL">>;
typeToSql(?pg_integer) -> <<"INTEGER">>;
typeToSql(?pg_int) -> <<"INTEGER">>;
typeToSql(?pg_bigint) -> <<"BIGINT">>;
typeToSql(?pg_smallint) -> <<"SMALLINT">>;
typeToSql(?pg_float) -> <<"REAL">>;
typeToSql(?pg_double) -> <<"DOUBLE PRECISION">>;
typeToSql(numeric) -> <<"NUMERIC">>; %% 无 ?pg_numeric 无参宏，保留裸 numeric 兜底
typeToSql(?pg_numeric(P, S)) -> [<<"NUMERIC(">>, integer_to_binary(P), <<",">>, integer_to_binary(S), <<")">>];
typeToSql(?pg_text) -> <<"TEXT">>;
typeToSql(?pg_varchar(N)) -> [<<"VARCHAR(">>, integer_to_binary(N), <<")">>];
typeToSql(?pg_char(N)) -> [<<"CHAR(">>, integer_to_binary(N), <<")">>];
typeToSql(?pg_uuid) -> <<"UUID">>;
typeToSql(?pg_inet) -> <<"INET">>;
typeToSql(?pg_boolean) -> <<"BOOLEAN">>;
typeToSql(?pg_timestamp) -> <<"TIMESTAMP">>;
typeToSql(?pg_timestamptz) -> <<"TIMESTAMPTZ">>;
typeToSql(?pg_date) -> <<"DATE">>;
typeToSql(?pg_time) -> <<"TIME">>;
typeToSql(?pg_json) -> <<"JSON">>;
typeToSql(?pg_jsonb) -> <<"JSONB">>;
typeToSql(?pg_bytea) -> <<"BYTEA">>;
typeToSql(?pg_array(InnerType)) -> [typeToSql(InnerType), <<"[]">>];
typeToSql(?pg_enum_binary) -> <<"TEXT">>;
typeToSql(?pg_enum_atom) -> <<"TEXT">>;
typeToSql(Other) when is_list(Other) -> iolist_to_binary(Other);
typeToSql(Other) when is_binary(Other) -> Other;
typeToSql(Other) when is_atom(Other) -> iolist_to_binary(string:uppercase(atom_to_list(Other))).

buildSetClause(Columns, StartIdx) ->
	Fun =
		fun(Col, {Acc, Idx}) ->
			{<<Acc/binary, ", ", (pgdbUtils:makeName(Col))/binary, " = $", (integer_to_binary(Idx))/binary>>, Idx + 1}
		end,
	{TParts, NextIdx} = lists:foldl(Fun, {<<>>, StartIdx}, Columns),
	Parts = ?CASE(TParts, <<>>, <<>>, <<_:16, TTParts/binary>>, TTParts),
	{Parts, NextIdx}.

buildField([]) -> <<"*">>;
buildField(Fields) ->
	<<_:16, FieldsBin/binary>> = <<<<", ", (pgdbUtils:makeName(Field))/binary>> || Field <- Fields>>,
	FieldsBin.

buildOrderBy(undefined) -> <<>>;
buildOrderBy({Field, Dir}) -> [<<" ORDER BY ">>, pgdbUtils:makeName(Field), <<" ">>, dirToSql(Dir)];
buildOrderBy(OrderList) when is_list(OrderList) ->
	TParts = <<<<", ", (pgdbUtils:makeName(Field))/binary, " ", (dirToSql(Dir))/binary>> || {Field, Dir} <- OrderList>>,
	Parts = ?CASE(TParts, <<>>, <<>>, <<_:16, TTParts/binary>>, TTParts),
	[<<" ORDER BY ">>, Parts];
buildOrderBy(Field) when is_atom(Field) -> [<<" ORDER BY ">>, pgdbUtils:makeName(Field)].

buildGroupBy(undefined) -> <<>>;
buildGroupBy(Fields) when is_list(Fields) ->
	TGroup = <<<<", ", (pgdbUtils:makeName(Field))/binary>> || Field <- Fields>>,
	Group = ?CASE(TGroup, <<>>, <<>>, <<_:16, TTGroup/binary>>, TTGroup),
	[<<" GROUP BY ">>, Group];
buildGroupBy(Field) when is_atom(Field) -> [<<" GROUP BY ">>, pgdbUtils:makeName(Field)].

buildHaving(undefined, Idx) -> {<<>>, [], Idx};
buildHaving(Having, Idx) when is_binary(Having) ->
	{[<<" HAVING ">>, Having], [], Idx};
buildHaving(Having, Idx) ->
	{HavingClauseSql, Params, NextIdx} = buildConditionGroup(Having, Idx),
	case HavingClauseSql of
		<<>> -> {<<>>, [], NextIdx};
		_ -> {[<<" HAVING ">>, HavingClauseSql], Params, NextIdx}
	end.

buildLimit(undefined, Idx) -> {<<>>, [], Idx};
buildLimit(N, Idx) -> {[<<" LIMIT $">>, integer_to_binary(Idx)], [N], Idx + 1}.

buildOffset(undefined, Idx) -> {<<>>, [], Idx};
buildOffset(N, Idx) -> {[<<" OFFSET $">>, integer_to_binary(Idx)], [N], Idx + 1}.

dirToSql(asc) -> <<"ASC">>;
dirToSql(desc) -> <<"DESC">>.

encodeJson(Map) when is_map(Map) ->
	jiffy:encode(Map);
encodeJson(List) when is_list(List) ->
	jiffy:encode(List);
encodeJson(Bin) when is_binary(Bin) ->
	Bin.

toText(V) when is_atom(V) -> atom_to_binary(V, utf8);
toText(V) when is_binary(V) -> V;
toText(V) when is_list(V) -> iolist_to_binary(V);
toText(V) when is_integer(V) -> integer_to_binary(V);
toText(V) when is_float(V) -> list_to_binary(float_to_list(V, [{decimals, 10}, compact])).

defaultIndexName(Table, Columns) ->
	TParts = <<<<"_", (pgdbUtils:makeName(Col))/binary>> || Col <- Columns>>,
	ColsPart = ?CASE(TParts, <<>>, <<>>, <<_:8, TTParts/binary>>, TTParts),
	iolist_to_binary([pgdbUtils:makeName(Table), <<"_">>, ColsPart, <<"_idx">>]).

buildBatchValueRows(Rows, StartIdx) ->
	[First | _] = Rows,
	RowCnt = length(First),
	{TRows, LInx} =
		lists:foldl(
			fun(_Row, {RowAcc, Idx}) ->
				{Placeholders, NextIdx} = buildPlaceholders(RowCnt, Idx, <<>>),
				{<<RowAcc/binary, ", (", Placeholders/binary, ")">>, NextIdx}
			end,
			{<<>>, StartIdx},
			Rows
		),
	<<_:16, TRow/binary>> = TRows,
	{TRow, LInx}.
buildUpsertActionSql(Columns, TConflictKeys, UpdateFields) ->
	ConflictKeys = [pgdbUtils:makeName(OneC) || OneC <- TConflictKeys],
	UpdateCols =
		case UpdateFields of
			all -> [Col || Col <- Columns, not lists:member(Col, ConflictKeys)];
			Fields -> Fields
		end,
	case UpdateCols of
		[] ->
			<<"DO NOTHING">>;
		_ ->
			<<_:16, ExcludedSql/binary>> = <<<<", ", (pgdbUtils:makeName(Col))/binary, " = EXCLUDED.", (pgdbUtils:makeName(Col))/binary>> || Col <- UpdateCols>>,
			[<<"DO UPDATE SET ">>, ExcludedSql]
	end.


