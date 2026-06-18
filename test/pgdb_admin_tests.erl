%%%-------------------------------------------------------------------
%%% @doc ePgdb 管理面/自省/迁移测试。
%%%
%%% 覆盖功能点：
%%%   schema/1, schemas/0, fieldSchema/2, syncSchema/1, syncCheckSchema/0
%%%   createTable/2, dropTable/1, truncateTable/1, renameTable/2
%%%   addColumn/3-4, dropColumn/2, renameColumn/3, alterColumnType/3
%%%   getColumns/1, columnExists/2
%%%   addIndex/2-3, dropIndex/1, primaryKeys/1, uniqueKeys/1
%%%   foreignKeys/1, indexes/1, tableKeys/1
%%%   withConnection/1, ddl/1-2, query/1-3, transaction/2
%%%   tables/0, describe/1, migrate/1, rollback/2, status/1
%%%-------------------------------------------------------------------
-module(pgdb_admin_tests).

-include_lib("eunit/include/eunit.hrl").
-include("pgdbSchema.hrl").

-define(TABLE_USERS, bench_users).

admin_all_test_() ->
	{setup,
		fun setup/0,
		fun teardown/1,
		{foreach,
			fun before_each/0,
			fun after_each/1,
			[
				test_case(fun schema_metadata_test/1),
				test_case(fun ddl_column_lifecycle_test/1),
				test_case(fun rename_truncate_drop_test/1),
				test_case(fun index_and_key_metadata_test/1),
				test_case(fun raw_api_and_describe_test/1),
				test_case(fun migration_flow_test/1),
				test_case(fun migration_duplicate_versions_test/1)
			]
		}
	}.

test_case(Fun) ->
	fun() -> Fun(ok) end.

setup() ->
	pgdb_test_helper:start().

teardown(_) ->
	pgdb_test_helper:stop().

before_each() ->
	pgdb_test_helper:truncate_all().

after_each(_) ->
	ok.

schema_metadata_test(_Ctx) ->
	?assertMatch(#schema{repr = record}, ePgdb:schema(?TABLE_USERS)),
	?assertMatch(#schField{name = score, dbType = bigint}, ePgdb:fieldSchema(?TABLE_USERS, score)),
	Schemas = ePgdb:schemas(),
	?assertEqual(length(dbSchemaDef:getTables()), length(Schemas)),
	?assert(lists:any(fun(#schema{comment = <<"压测用户表"/utf8>>}) -> true;
		(#schema{comment = "压测用户表"}) -> true;
		(_) -> false
					  end, Schemas)),
	?assertEqual(ok, ePgdb:syncSchema(?TABLE_USERS)),
	?assertEqual(ok, ePgdb:syncCheckSchema()).

ddl_column_lifecycle_test(_Ctx) ->
	Table = temp_name("ddl_lifecycle"),
	Fields = [
		#schField{name = id, dbType = bigint, opts = [primary_key]},
		#schField{name = name, dbType = {varchar, 64}, opts = [not_null]},
		#schField{name = score, dbType = integer, opts = [{default, 0}]}
	],
	try
		?assertEqual(ok, ePgdb:createTable(Table, Fields)),
		?assertEqual(true, ePgdb:tableExists(Table)),
		?assertEqual(false, ePgdb:columnExists(Table, extra)),
		?assertEqual(ok, ePgdb:addColumn(Table, extra, text)),
		?assertEqual(true, ePgdb:columnExists(Table, extra)),
		?assertEqual(ok, ePgdb:renameColumn(Table, extra, extra_text)),
		?assertEqual(true, ePgdb:columnExists(Table, extra_text)),
		?assertEqual(ok, ePgdb:alterColumnType(Table, score, bigint)),
		{ok, Cols} = ePgdb:getColumns(Table),
		?assert(lists:any(fun
							  ({<<"score">>, <<"bigint">>, _, _}) -> true;
							  (_) -> false
						  end, Cols)),
		?assertEqual(ok, ePgdb:dropColumn(Table, extra_text)),
		?assertEqual(false, ePgdb:columnExists(Table, extra_text))
	after
		ePgdb:dropTable(Table)
	end.

rename_truncate_drop_test(_Ctx) ->
	Table = temp_name("rename_ops"),
	NewTable = temp_name("rename_ops_new"),
	Fields = [
		#schField{name = id, dbType = bigint, opts = [primary_key]},
		#schField{name = note, dbType = text, opts = []}
	],
	try
		?assertEqual(ok, ePgdb:createTable(Table, Fields)),
		?assertMatch({ok, 1}, ePgdb:query([
			<<"INSERT INTO ">>, quote_ident(Table), <<" (id, note) VALUES ($1, $2)">>
		], [1, <<"hello">>])),
		?assertMatch({ok, _, [{<<"1">>}]}, ePgdb:query([
			<<"SELECT COUNT(*) FROM ">>, quote_ident(Table)
		])),
		?assertEqual(ok, ePgdb:truncateTable(Table)),
		?assertMatch({ok, _, [{<<"0">>}]}, ePgdb:query([
			<<"SELECT COUNT(*) FROM ">>, quote_ident(Table)
		])),
		?assertEqual(ok, ePgdb:renameTable(Table, NewTable)),
		?assertEqual(false, ePgdb:tableExists(Table)),
		?assertEqual(true, ePgdb:tableExists(NewTable)),
		?assertEqual(ok, ePgdb:dropTable(NewTable)),
		?assertEqual(false, ePgdb:tableExists(NewTable))
	after
		ePgdb:dropTable(Table),
		ePgdb:dropTable(NewTable)
	end.

index_and_key_metadata_test(_Ctx) ->
	Table = temp_name("index_meta"),
	IndexName = <<Table/binary, "_score_idx">>,
	Fields = [
		#schField{name = id, dbType = bigint, opts = [primary_key]},
		#schField{name = email, dbType = {varchar, 64}, opts = [unique]},
		#schField{name = player_id, dbType = bigint, opts = [{references, {players, id}}]},
		#schField{name = score, dbType = integer, opts = []}
	],
	try
		?assertEqual(ok, ePgdb:createTable(Table, Fields)),
		?assertEqual(ok, ePgdb:addIndex(Table, [score], [{name, IndexName}])),
		{ok, Primary} = ePgdb:primaryKeys(Table),
		?assertEqual([<<"id">>], Primary),
		{ok, Unique} = ePgdb:uniqueKeys(Table),
		?assert(lists:any(fun(#{columns := [<<"email">>]}) -> true; (_) -> false end, Unique)),
		{ok, Foreign} = ePgdb:foreignKeys(Table),
		?assert(lists:any(fun(#{columns := [<<"player_id">>], referenced_table := <<"players">>}) -> true; (_) -> false end, Foreign)),
		{ok, Indexes0} = ePgdb:indexes(Table),
		?assert(lists:any(fun(#{name := Name, columns := Cols}) -> Name =:= IndexName andalso lists:member(<<"score">>, Cols) end, Indexes0)),
		{ok, Keys} = ePgdb:tableKeys(Table),
		?assertEqual([<<"id">>], maps:get(primary_keys, Keys)),
		?assertEqual(ok, ePgdb:dropIndex(IndexName)),
		{ok, Indexes1} = ePgdb:indexes(Table),
		?assertNot(lists:any(fun(#{name := Name}) -> Name =:= IndexName end, Indexes1))
	after
		ePgdb:dropTable(Table)
	end.

raw_api_and_describe_test(_Ctx) ->
	Table = temp_name("raw_api"),
	QTable = quote_ident(Table),
	Key = <<"admin_api_key">>,
	try
		?assertMatch({ok, _, _}, ePgdb:query(<<"SELECT 1">>)),
		?assertMatch({ok, _, [{<<"1">>}]}, ePgdb:query(<<"SELECT $1">>, [1])),
		?assertEqual(ok, ePgdb:ddl([
			<<"CREATE TABLE ">>, QTable, <<" (id BIGINT PRIMARY KEY, note TEXT)">>
		])),
		?assertEqual(ok, ePgdb:withConnection(fun(Conn) ->
			?assertMatch({ok, 1}, ePgdb:query(Conn, [
				<<"INSERT INTO ">>, QTable, <<" (id, note) VALUES ($1, $2)">>
			], [1, <<"conn">>])),
			?assertMatch({ok, _, [{<<"conn">>}]}, ePgdb:query(Conn, [
				<<"SELECT note FROM ">>, QTable, <<" WHERE id = $1">>
			], [1])),
			ok
											  end)),
		{ok, ok} = ePgdb:transaction(fun(Conn) ->
			ok = ePgdb:insertC(Conn, pgdb_test_helper:new_kv(Key, #{value => 1})),
			ok
									 end, 5000),
		{ok, [Row]} = ePgdb:get(bench_kv, #{key => Key}),
		?assertEqual(#{<<"value">> => 1}, maps:get(value, Row)),
		{ok, Tables} = ePgdb:tables(),
		?assert(lists:member(<<"bench_users">>, Tables)),
		{ok, Desc} = ePgdb:describe(bench_users),
		?assert(length(Desc) > 0),
		?assert(lists:all(fun(Item) -> is_map(Item) andalso maps:size(Item) > 0 end, Desc))
	after
		ePgdb:dropTable(Table),
		ePgdb:delete(bench_kv, #{key => Key})
	end.

migration_flow_test(_Ctx) ->
	Base = erlang:unique_integer([positive, monotonic]),
	Table = temp_name("migration_case"),
	QTable = quote_ident(Table),
	V1 = Base,
	V2 = Base + 1,
	Migrations = [
		{V1, <<"create migration table">>,
			fun(Conn) ->
				ePgdb:ddl(Conn, [<<"CREATE TABLE ">>, QTable, <<" (id BIGINT PRIMARY KEY, note TEXT)">>])
			end,
			fun(Conn) ->
				ePgdb:ddl(Conn, [<<"DROP TABLE IF EXISTS ">>, QTable])
			end},
		{V2, <<"seed migration row">>,
			fun(Conn) ->
				case ePgdb:query(Conn, [<<"INSERT INTO ">>, QTable, <<" (id, note) VALUES ($1, $2)">>], [1, <<"seed">>]) of
					{ok, 1} -> ok;
					Other -> erlang:error({unexpected_query_result, Other})
				end
			end,
			fun(Conn) ->
				case ePgdb:query(Conn, [<<"DELETE FROM ">>, QTable, <<" WHERE id = $1">>], [1]) of
					{ok, 1} -> ok;
					{ok, 0} -> ok;
					Other -> erlang:error({unexpected_query_result, Other})
				end
			end}
	],
	try
		{ok, Status0} = ePgdb:status(Migrations),
		?assert(lists:all(fun({Version, _Desc, pending}) -> Version =:= V1 orelse Version =:= V2 end, Status0)),
		?assertEqual(ok, ePgdb:migrate(Migrations)),
		?assertEqual(true, ePgdb:tableExists(Table)),
		?assertMatch({ok, _, [{<<"1">>}]}, ePgdb:query([<<"SELECT COUNT(*) FROM ">>, QTable])),
		{ok, Status1} = ePgdb:status(Migrations),
		?assert(lists:all(fun({_Version, _Desc, applied}) -> true; (_) -> false end, Status1)),
		?assertEqual(ok, ePgdb:rollback(Migrations, V1 - 1)),
		?assertEqual(false, ePgdb:tableExists(Table)),
		{ok, Status2} = ePgdb:status(Migrations),
		?assert(lists:all(fun({_Version, _Desc, pending}) -> true; (_) -> false end, Status2))
	after
		cleanup_migration_versions([V1, V2]),
		ePgdb:dropTable(Table)
	end.

migration_duplicate_versions_test(_Ctx) ->
	Version = erlang:unique_integer([positive, monotonic]),
	Migrations = [
		{Version, <<"dup one">>, fun(_Conn) -> ok end, fun(_Conn) -> ok end},
		{Version, <<"dup two">>, fun(_Conn) -> ok end, fun(_Conn) -> ok end}
	],
	?assertMatch({error, {duplicate_migration_versions, [_]}}, ePgdb:migrate(Migrations)).

temp_name(Prefix) ->
	iolist_to_binary(io_lib:format("~s_~p", [Prefix, erlang:unique_integer([positive, monotonic])])).

quote_ident(Name) ->
	[<<"\"">>, Name, <<"\"">>].

cleanup_migration_versions([]) ->
	ok;
cleanup_migration_versions(Versions) ->
	lists:foreach(fun(Version) ->
		?assertMatch({ok, _}, ePgdb:query(
			<<"DELETE FROM _pgdb_migrations WHERE version = $1">>,
			[Version]
		))
				  end, Versions),
	ok.
