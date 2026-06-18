%%%-------------------------------------------------------------------
%%% @doc ePgdb CRUD 功能集成测试。
%%%
%%% 覆盖功能点：
%%%   insert/1, insertR/1, get/2, get/3
%%%   update/3, delete/2, upsert/3
%%%   batchInsert/2, batchDeleteByKey/3
%%%   count/1-2, sum/2-3
%%%   transaction/1（提交与回滚）
%%%   foreachRows/4, foldRows/5
%%%   foreachByKey/5, foldByKey/6
%%%   selectPage/4-5（含 count_total）
%%%   jsonbSet/4-5, jsonbGet/3-4
%%%   jsonbDelete/3-4, jsonbMerge/4
%%%
%%% 运行：
%%%   rebar3 eunit --module=pgdb_crud_tests
%%%-------------------------------------------------------------------
-module(pgdb_crud_tests).

-include_lib("eunit/include/eunit.hrl").
-include("pg_player_schema.hrl").

-define(TABLE_PLAYERS, players).
-define(TABLE_ITEMS, items).
-define(TABLE_KV, bench_kv).

%%%===================================================================
%%% EUnit 入口 — 一次 setup，多个测试
%%%===================================================================

crud_all_test_() ->
	{setup,
		fun setup/0,
		fun teardown/1,
		{foreach,
			fun before_each/0,
			fun after_each/1,
			[
				test_case(fun insert_record_test/1),
				test_case(fun insert_return_test/1),
				test_case(fun insert_map_test/1),
				test_case(fun insert_player_map_test/1),
				test_case(fun insert_return_player_map_test/1),
				test_case(fun insertR_replace_test/1),
				test_case(fun insertR_no_replace_test/1),
				test_case(fun get_returns_all_rows_test/1),
				test_case(fun get_with_fields_test/1),
				test_case(fun update_by_id_test/1),
				test_case(fun update_multi_fields_test/1),
				test_case(fun update_returns_count_test/1),
				test_case(fun update_player_map_test/1),
				test_case(fun delete_by_id_test/1),
				test_case(fun delete_returns_count_test/1),
				test_case(fun delete_empty_where_test/1),
				test_case(fun upsert_insert_test/1),
				test_case(fun upsert_update_test/1),
				test_case(fun upsert_all_fields_test/1),
				test_case(fun batch_insert_test/1),
				test_case(fun batch_insert_player_maps_test/1),
				test_case(fun batch_insert_empty_test/1),
				test_case(fun batch_insert_replace_test/1),
				test_case(fun batch_insert_no_replace_test/1),
				test_case(fun batch_update_test/1),
				test_case(fun batch_update_empty_test/1),
				test_case(fun batch_update_skip_empty_fields_test/1),
				test_case(fun batch_delete_by_key_test/1),
				test_case(fun batch_delete_by_codec_key_test/1),
				test_case(fun batch_delete_empty_test/1),
				test_case(fun count_all_test/1),
				test_case(fun count_where_test/1),
				test_case(fun sum_all_test/1),
				test_case(fun sum_where_test/1),
				test_case(fun transaction_commit_test/1),
				test_case(fun transaction_commit_player_map_test/1),
				test_case(fun transaction_rollback_test/1),
				test_case(fun insertCR_test/1),
				test_case(fun insertCR_replace_test/1),
				test_case(fun insertCR_no_replace_test/1),
				test_case(fun batch_insert_conn_test/1),
				test_case(fun foreach_rows_test/1),
				test_case(fun fold_rows_test/1),
				test_case(fun foreach_by_key_test/1),
				test_case(fun fold_by_key_test/1),
				test_case(fun select_page_basic_test/1),
				test_case(fun select_page_with_total_test/1),
				test_case(fun select_page_invalid_args_test/1),
				test_case(fun jsonb_set_and_get_test/1),
				test_case(fun jsonb_nested_path_test/1),
				test_case(fun jsonb_delete_test/1),
				test_case(fun jsonb_merge_test/1),
				test_case(fun jsonb_set_with_where_test/1)
			]
		}
	}.

test_case(Fun) ->
	fun() -> Fun(ok) end.

%%%===================================================================
%%% Setup / Teardown
%%%===================================================================

setup() ->
	pgdb_test_helper:start().

teardown(_) ->
	pgdb_test_helper:stop().

before_each() ->
	pgdb_test_helper:truncate_all().

after_each(_) ->
	ok.

%%%===================================================================
%%% insert/1 — record 表 (players)
%%%===================================================================

insert_record_test(_Ctx) ->
	P = pgdb_test_helper:new_player(),
	Id = P#players.id,
	?assertEqual(ok, ePgdb:insert(P)),
	%% 验证数据已写入
	{ok, Rows} = ePgdb:get(?TABLE_PLAYERS, #{id => Id}),
	?assertEqual(1, length(Rows)).

insert_return_test(_Ctx) ->
	P = pgdb_test_helper:new_player(),
	{ok, Returned} = ePgdb:insertR(P),
	%% insertR 在 record 表返回 record tuple
	?assert(is_tuple(Returned)),
	?assertEqual(players, element(1, Returned)),
	%% 主键字段存在且与插入的一致
	?assertEqual(P#players.id, element(2, Returned)).

%%%===================================================================
%%% insert/1 — map 表 (bench_kv)
%%%===================================================================

insert_map_test(_Ctx) ->
	KV = pgdb_test_helper:new_kv(<<"key_map_test">>, #{score => 99}),
	?assertEqual(ok, ePgdb:insert(KV)),
	{ok, Rows} = ePgdb:get(?TABLE_KV, #{key => <<"key_map_test">>}),
	[Row | _] = Rows,
	%% JSON decode returns binary keys
	?assertEqual(#{<<"score">> => 99}, maps:get(value, Row)).

insert_player_map_test(_Ctx) ->
	Player = player_record_to_map(pgdb_test_helper:new_player()),
	?assertEqual(ok, ePgdb:insert(Player)),
	{ok, [Row]} = ePgdb:get(?TABLE_PLAYERS, #{id => maps:get(id, Player)}),
	?assert(is_tuple(Row)),
	?assertEqual(players, element(1, Row)),
	?assertEqual(maps:get(name, Player), element(#players.name, Row)),
	?assertEqual(maps:get(level, Player), element(#players.level, Row)).

insert_return_player_map_test(_Ctx) ->
	Player = player_record_to_map(pgdb_test_helper:new_player(#{profile => #{rank => 3}})),
	{ok, Returned} = ePgdb:insertR(Player),
	?assert(is_tuple(Returned)),
	?assertEqual(players, element(1, Returned)),
	?assertEqual(maps:get(id, Player), element(#players.id, Returned)),
	?assertEqual(#{<<"rank">> => 3}, element(#players.profile, Returned)).

%%%===================================================================
%%% insertR/2 — 带 IsDoUpdate 控制的 INSERT RETURNING
%%%===================================================================

insertR_replace_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{gold => 100, level => 5}),
	{ok, Returned} = ePgdb:insertR(P, true),
	?assertEqual(P#players.id, element(#players.id, Returned)),
	?assertEqual(100, element(#players.gold, Returned)),
	?assertEqual(5, element(#players.level, Returned)),
	P2 = P#players{gold = 999, level = 99},
	{ok, Returned2} = ePgdb:insertR(P2, true),
	?assertEqual(P#players.id, element(#players.id, Returned2)),
	?assertEqual(999, element(#players.gold, Returned2)),
	?assertEqual(99, element(#players.level, Returned2)),
	{ok, Count} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(1, Count).

insertR_no_replace_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{gold => 200, level => 10}),
	{ok, Returned} = ePgdb:insertR(P, false),
	?assertEqual(P#players.id, element(#players.id, Returned)),
	?assertEqual(200, element(#players.gold, Returned)),
	?assertEqual(10, element(#players.level, Returned)),
	{ok, Count} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(1, Count).

%%%===================================================================
%%% get/2-3
%%%===================================================================

get_returns_all_rows_test(_Ctx) ->
	%% 插入多条同 level 玩家，验证 get 全返回
	P1 = pgdb_test_helper:new_player(#{level => 77}),
	P2 = pgdb_test_helper:new_player(#{level => 77}),
	P3 = pgdb_test_helper:new_player(#{level => 88}),
	ok = ePgdb:insert(P1),
	ok = ePgdb:insert(P2),
	ok = ePgdb:insert(P3),
	{ok, Rows77} = ePgdb:get(?TABLE_PLAYERS, #{level => 77}),
	?assertEqual(2, length(Rows77)),
	{ok, Rows88} = ePgdb:get(?TABLE_PLAYERS, #{level => 88}),
	?assertEqual(1, length(Rows88)).

get_with_fields_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{level => 5, gold => 500}),
	ok = ePgdb:insert(P),
	{ok, [Row]} = ePgdb:select(?TABLE_PLAYERS, #{id => P#players.id}, [{fields, [id, level, gold]}]),
	?assertEqual(P#players.id, maps:get(id, Row)),
	?assertEqual(5, maps:get(level, Row)),
	?assertEqual(500, maps:get(gold, Row)),
	?assertNot(maps:is_key(name, Row)).

%%%===================================================================
%%% update/3
%%%===================================================================

update_by_id_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{level => 1, gold => 0}),
	ok = ePgdb:insert(P),
	{ok, _} = ePgdb:update(P#players{level = 10, gold = 9999},
		[#players.level, #players.gold],
		#{id => P#players.id}),
	{ok, [Row]} = ePgdb:select(?TABLE_PLAYERS, #{id => P#players.id},
		[{fields, [level, gold]}]),
	?assertEqual(10, maps:get(level, Row)),
	?assertEqual(9999, maps:get(gold, Row)).

update_multi_fields_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{vip => false, status => <<"idle">>}),
	ok = ePgdb:insert(P),
	P2 = P#players{vip = true, status = <<"online">>},
	{ok, _} = ePgdb:update(P2, [#players.vip, #players.status], #{id => P#players.id}),
	{ok, [Row]} = ePgdb:select(?TABLE_PLAYERS, #{id => P#players.id},
		[{fields, [vip, status]}]),
	?assertEqual(true, maps:get(vip, Row)),
	?assertEqual(<<"online">>, maps:get(status, Row)).

update_returns_count_test(_Ctx) ->
	P1 = pgdb_test_helper:new_player(#{level => 1}),
	P2 = pgdb_test_helper:new_player(#{level => 1}),
	ok = ePgdb:insert(P1),
	ok = ePgdb:insert(P2),
	{ok, Count} = ePgdb:update(P1#players{gold = 100}, [#players.gold], #{level => 1}),
	?assertEqual(2, Count).

update_player_map_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{vip => false, gold => 0}),
	ok = ePgdb:insert(P),
	PlayerMap = player_record_to_map(P),
	Updated = PlayerMap#{vip => true, gold => 888, profile => #{rank => 9}},
	{ok, 1} = ePgdb:update(Updated, [vip, gold, profile], #{id => P#players.id}),
	{ok, [Row]} = ePgdb:select(?TABLE_PLAYERS, #{id => P#players.id}, [{fields, [vip, gold, profile]}]),
	?assertEqual(true, maps:get(vip, Row)),
	?assertEqual(888, maps:get(gold, Row)),
	?assertEqual(#{<<"rank">> => 9}, maps:get(profile, Row)).

%%%===================================================================
%%% delete/2
%%%===================================================================

delete_by_id_test(_Ctx) ->
	P = pgdb_test_helper:new_player(),
	ok = ePgdb:insert(P),
	{ok, 1} = ePgdb:delete(?TABLE_PLAYERS, #{id => P#players.id}),
	{ok, Rows} = ePgdb:get(?TABLE_PLAYERS, #{id => P#players.id}),
	?assertEqual([], Rows).

delete_returns_count_test(_Ctx) ->
	P1 = pgdb_test_helper:new_player(#{level => 99}),
	P2 = pgdb_test_helper:new_player(#{level => 99}),
	ok = ePgdb:insert(P1),
	ok = ePgdb:insert(P2),
	{ok, 2} = ePgdb:delete(?TABLE_PLAYERS, #{level => 99}).

delete_empty_where_test(_Ctx) ->
	%% delete with empty map deletes all rows
	ok = ePgdb:insert(pgdb_test_helper:new_player()),
	ok = ePgdb:insert(pgdb_test_helper:new_player()),
	{ok, Count} = ePgdb:delete(?TABLE_PLAYERS, #{}),
	?assert(Count >= 2).

%%%===================================================================
%%% upsert/3
%%%===================================================================

upsert_insert_test(_Ctx) ->
	KV = pgdb_test_helper:new_kv(<<"upsert_key">>, 42),
	{ok, Row} = ePgdb:upsert(KV, [key], [value, version]),
	?assertEqual(42, maps:get(value, Row)).

upsert_update_test(_Ctx) ->
	KV = pgdb_test_helper:new_kv(<<"upsert_key2">>, <<"first">>),
	{ok, _} = ePgdb:upsert(KV, [key], [value]),
	KV2 = KV#{value => <<"second">>},
	{ok, Row} = ePgdb:upsert(KV2, [key], [value]),
	?assertEqual(<<"second">>, maps:get(value, Row)).

upsert_all_fields_test(_Ctx) ->
	KV = pgdb_test_helper:new_kv(<<"upsert_key3">>, #{abc => 1}),
	{ok, _} = ePgdb:upsert(KV, [key], [value]),
	KV2 = KV#{value => #{abc => 2}},
	{ok, Row} = ePgdb:upsert(KV2, [key], all),
	%% JSON decode returns binary keys
	?assertEqual(#{<<"abc">> => 2}, maps:get(value, Row)).

%%%===================================================================
%%% batchInsert/2
%%%===================================================================

batch_insert_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player() || _ <- lists:seq(1, 10)],
	ok = ePgdb:batchInsert(Players),
	{ok, Count} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(10, Count).

batch_insert_player_maps_test(_Ctx) ->
	Players = [player_record_to_map(pgdb_test_helper:new_player()) || _ <- lists:seq(1, 6)],
	ok = ePgdb:batchInsert(Players),
	{ok, Count} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(6, Count).

batch_insert_empty_test(_Ctx) ->
	?assertEqual(ok, ePgdb:batchInsert([])).

batch_insert_replace_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player(#{gold => 10, level => 1}) || _ <- lists:seq(1, 3)],
	ok = ePgdb:batchInsert(Players, true),
	{ok, Count1} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(3, Count1),
	UpdPlayers = [P#players{gold = 999, level = 99} || P <- Players],
	ok = ePgdb:batchInsert(UpdPlayers, true),
	{ok, Count2} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(3, Count2),
	lists:foreach(fun(P) ->
		{ok, [Row]} = ePgdb:get(?TABLE_PLAYERS, #{id => P#players.id}),
		?assertEqual(999, element(#players.gold, Row)),
		?assertEqual(99, element(#players.level, Row))
				  end, Players).

batch_insert_no_replace_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player(#{gold => 500}) || _ <- lists:seq(1, 3)],
	ok = ePgdb:batchInsert(Players, false),
	{ok, Count1} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(3, Count1),
	UpdPlayers = [P#players{gold = 888} || P <- Players],
	?assertMatch({error, _}, ePgdb:batchInsert(UpdPlayers, false)).

%%%===================================================================
%%% batchUpdate/1
%%%===================================================================

batch_update_test(_Ctx) ->
	P1 = pgdb_test_helper:new_player(#{level => 1, gold => 10}),
	P2 = pgdb_test_helper:new_player(#{level => 1, gold => 20}),
	ok = ePgdb:insert(P1),
	ok = ePgdb:insert(P2),
	Upd1 = player_record_to_map(P1#players{level = 11, gold = 110}),
	Upd2 = player_record_to_map(P2#players{level = 22, gold = 220}),
	Mask = pgdb_test_helper:dirty_mask(players, [level, gold]),
	ok = ePgdb:batchUpdate([
		{Upd1, Mask, #{id => P1#players.id}},
		{Upd2, Mask, #{id => P2#players.id}}
	]),
	{ok, [Row1]} = ePgdb:get(?TABLE_PLAYERS, #{id => P1#players.id}),
	{ok, [Row2]} = ePgdb:get(?TABLE_PLAYERS, #{id => P2#players.id}),
	?assertEqual(11, element(#players.level, Row1)),
	?assertEqual(110, element(#players.gold, Row1)),
	?assertEqual(22, element(#players.level, Row2)),
	?assertEqual(220, element(#players.gold, Row2)).

batch_update_empty_test(_Ctx) ->
	?assertEqual(ok, ePgdb:batchUpdate([])).

batch_update_skip_empty_fields_test(_Ctx) ->
	P1 = pgdb_test_helper:new_player(),
	ok = ePgdb:insert(P1),
	Upd1 = player_record_to_map(P1),
	?assertEqual(ok, ePgdb:batchUpdate([{Upd1, 0, #{id => P1#players.id}}])),
	{ok, [Row]} = ePgdb:get(?TABLE_PLAYERS, #{id => P1#players.id}),
	?assertEqual(P1#players.level, element(#players.level, Row)).

%%%===================================================================
%%% batchDeleteByKey/3
%%%===================================================================

batch_delete_by_key_test(_Ctx) ->
	P1 = pgdb_test_helper:new_player(),
	P2 = pgdb_test_helper:new_player(),
	P3 = pgdb_test_helper:new_player(),
	ok = ePgdb:insert(P1),
	ok = ePgdb:insert(P2),
	ok = ePgdb:insert(P3),
	{ok, Deleted} = ePgdb:batchDelByKey(?TABLE_PLAYERS, id,
		[P1#players.id, P2#players.id]),
	?assertEqual(2, Deleted),
	{ok, Rows} = ePgdb:get(?TABLE_PLAYERS, #{id => P3#players.id}),
	?assertEqual(1, length(Rows)).

batch_delete_by_codec_key_test(_Ctx) ->
	Player = pgdb_test_helper:new_player(),
	ok = ePgdb:insert(Player),
	Sword = #items{
		id = pgdb_test_helper:gen_id(),
		player_id = Player#players.id,
		item_type = sword,
		count = 1,
		attrs = #{slot => 1},
		state_data = #{durability => 100}
	},
	Shield = #items{
		id = pgdb_test_helper:gen_id(),
		player_id = Player#players.id,
		item_type = shield,
		count = 1,
		attrs = #{slot => 2},
		state_data = #{durability => 80}
	},
	Potion = #items{
		id = pgdb_test_helper:gen_id(),
		player_id = Player#players.id,
		item_type = potion,
		count = 5,
		attrs = #{slot => 3},
		state_data = #{durability => 1}
	},
	ok = ePgdb:insert(Sword),
	ok = ePgdb:insert(Shield),
	ok = ePgdb:insert(Potion),
	{ok, Deleted} = ePgdb:batchDelByKey(?TABLE_ITEMS, item_type, [sword, potion, sword]),
	?assertEqual(2, Deleted),
	{ok, Count} = ePgdb:count(?TABLE_ITEMS),
	?assertEqual(1, Count),
	{ok, [Row]} = ePgdb:select(?TABLE_ITEMS, #{player_id => Player#players.id}, [{fields, [item_type]}]),
	?assertEqual(shield, maps:get(item_type, Row)).

batch_delete_empty_test(_Ctx) ->
	?assertEqual({ok, 0}, ePgdb:batchDelByKey(?TABLE_PLAYERS, id, [])).

%%%===================================================================
%%% count/1-2, sum/2-3
%%%===================================================================

count_all_test(_Ctx) ->
	ok = ePgdb:insert(pgdb_test_helper:new_player()),
	ok = ePgdb:insert(pgdb_test_helper:new_player()),
	ok = ePgdb:insert(pgdb_test_helper:new_player()),
	{ok, N} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(3, N).

count_where_test(_Ctx) ->
	ok = ePgdb:insert(pgdb_test_helper:new_player(#{vip => true})),
	ok = ePgdb:insert(pgdb_test_helper:new_player(#{vip => true})),
	ok = ePgdb:insert(pgdb_test_helper:new_player(#{vip => false})),
	{ok, 2} = ePgdb:count(?TABLE_PLAYERS, #{vip => true}),
	{ok, 1} = ePgdb:count(?TABLE_PLAYERS, #{vip => false}).

sum_all_test(_Ctx) ->
	ok = ePgdb:insert(pgdb_test_helper:new_player(#{gold => 100})),
	ok = ePgdb:insert(pgdb_test_helper:new_player(#{gold => 200})),
	ok = ePgdb:insert(pgdb_test_helper:new_player(#{gold => 300})),
	{ok, Total} = ePgdb:sum(?TABLE_PLAYERS, gold),
	?assertEqual(600, Total).

sum_where_test(_Ctx) ->
	ok = ePgdb:insert(pgdb_test_helper:new_player(#{gold => 1000, vip => true})),
	ok = ePgdb:insert(pgdb_test_helper:new_player(#{gold => 500, vip => true})),
	ok = ePgdb:insert(pgdb_test_helper:new_player(#{gold => 9999, vip => false})),
	{ok, VipSum} = ePgdb:sum(?TABLE_PLAYERS, gold, #{vip => true}),
	?assertEqual(1500, VipSum).

%%%===================================================================
%%% transaction/1
%%%===================================================================

transaction_commit_test(_Ctx) ->
	P = pgdb_test_helper:new_player(),
	{ok, ok} = ePgdb:transaction(fun(Conn) ->
		ok = ePgdb:insertC(Conn, P),
		ok
								 end),
	{ok, Rows} = ePgdb:get(?TABLE_PLAYERS, #{id => P#players.id}),
	?assertEqual(1, length(Rows)).

transaction_commit_player_map_test(_Ctx) ->
	Player = player_record_to_map(pgdb_test_helper:new_player(#{gold => 10, profile => #{rank => 1}})),
	{ok, ok} = ePgdb:transaction(fun(Conn) ->
		ok = ePgdb:insertC(Conn, Player),
		{ok, 1} = ePgdb:update(Conn, Player#{gold => 777, profile => #{rank => 2}}, [gold, profile], #{id => maps:get(id, Player)}),
		ok
								 end),
	{ok, [Row]} = ePgdb:select(?TABLE_PLAYERS, #{id => maps:get(id, Player)}, [{fields, [gold, profile]}]),
	?assertEqual(777, maps:get(gold, Row)),
	?assertEqual(#{<<"rank">> => 2}, maps:get(profile, Row)).

transaction_rollback_test(_Ctx) ->
	P = pgdb_test_helper:new_player(),
	?assertMatch({error, _},
		ePgdb:transaction(fun(Conn) ->
			ok = ePgdb:insertC(Conn, P),
			%% 插入一个违反 not_null 约束的行来触发回滚
			error(force_rollback)
						  end)),
	%% 验证事务已回滚，玩家未被持久化
	{ok, Rows} = ePgdb:get(?TABLE_PLAYERS, #{id => P#players.id}),
	?assertEqual([], Rows).

%%%===================================================================
%%% insertCR/2, insertCR/3 — 事务内 INSERT RETURNING
%%%===================================================================

insertCR_test(_Ctx) ->
	ePgdb:transaction(fun(Conn) ->
		P = pgdb_test_helper:new_player(#{gold => 300, level => 20}),
		{ok, Returned} = ePgdb:insertCR(Conn, P),
		?assertEqual(P#players.id, element(#players.id, Returned)),
		?assertEqual(300, element(#players.gold, Returned)),
		?assertEqual(20, element(#players.level, Returned))
					  end).

insertCR_replace_test(_Ctx) ->
	ePgdb:transaction(fun(Conn) ->
		P = pgdb_test_helper:new_player(#{gold => 100, level => 5}),
		{ok, _} = ePgdb:insertCR(Conn, P, true),
		P2 = P#players{gold = 9999, level = 50},
		{ok, Returned} = ePgdb:insertCR(Conn, P2, true),
		?assertEqual(P#players.id, element(#players.id, Returned)),
		?assertEqual(9999, element(#players.gold, Returned)),
		?assertEqual(50, element(#players.level, Returned))
					  end),
	{ok, Count} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(1, Count).

insertCR_no_replace_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{gold => 400, level => 15}),
	{ok, _} = ePgdb:transaction(fun(Conn) ->
		{ok, Returned} = ePgdb:insertCR(Conn, P, false),
		?assertEqual(P#players.id, element(#players.id, Returned)),
		?assertEqual(400, element(#players.gold, Returned)),
		?assertEqual(15, element(#players.level, Returned)),
		Returned
								end),
	{ok, Count} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(1, Count),
	%% 重复主键的 INSERT 应失败（不产生新行）
	?assertMatch({error, _},
		ePgdb:transaction(fun(Conn) ->
			ePgdb:insertCR(Conn, P, false)
						  end)),
	{ok, Count2} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(1, Count2).

%%%===================================================================
%%% batchInsert/3 — 事务内批量插入
%%%===================================================================

batch_insert_conn_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player(#{gold => 50}) || _ <- lists:seq(1, 3)],
	{ok, _} = ePgdb:transaction(fun(Conn) ->
		ok = ePgdb:batchInsert(Conn, Players, false),
		UpdPlayers = [P#players{gold = 1000} || P <- Players],
		ok = ePgdb:batchInsert(Conn, UpdPlayers, true),
		ok
								end),
	{ok, Count} = ePgdb:count(?TABLE_PLAYERS),
	?assertEqual(3, Count),
	lists:foreach(fun(P) ->
		{ok, [Row]} = ePgdb:get(?TABLE_PLAYERS, #{id => P#players.id}),
		?assertEqual(1000, element(#players.gold, Row))
				  end, Players).

%%%===================================================================
%%% foreachRows/4, foldRows/5
%%%===================================================================

foreach_rows_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player() || _ <- lists:seq(1, 5)],
	ok = ePgdb:batchInsert(Players),
	Counter = counters:new(1, []),
	ok = ePgdb:foreachRows(?TABLE_PLAYERS, #{}, 2, fun(_Row) ->
		counters:add(Counter, 1, 1)
												   end),
	?assertEqual(5, counters:get(Counter, 1)).

fold_rows_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player(#{gold => 10 * I}) || I <- lists:seq(1, 6)],
	ok = ePgdb:batchInsert(Players),
	{ok, Total} = ePgdb:foldRows(?TABLE_PLAYERS, #{}, 2,
		fun(Row, Acc) ->
			%% players is record-repr; use element/2 to access fields
			Acc + element(#players.gold, Row)
		end, 0),
	?assertEqual(210, Total).  %% 10+20+30+40+50+60 = 210

%%%===================================================================
%%% foreachByKey/5, foldByKey/6 (keyset 扫描)
%%%===================================================================

foreach_by_key_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player() || _ <- lists:seq(1, 7)],
	ok = ePgdb:batchInsert(Players),
	Counter = counters:new(1, []),
	ok = ePgdb:foreachByKey(?TABLE_PLAYERS, #{}, id, 3, fun(_Row) ->
		counters:add(Counter, 1, 1)
														end),
	?assertEqual(7, counters:get(Counter, 1)).

fold_by_key_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player(#{level => 5}) || _ <- lists:seq(1, 5)],
	ok = ePgdb:batchInsert(Players),
	{ok, Ids} = ePgdb:foldByKey(?TABLE_PLAYERS, #{level => 5}, id, 2,
		fun(Row, Acc) ->
			%% players is record-repr; use element/2 to access fields
			[element(#players.id, Row) | Acc]
		end, []),
	?assertEqual(5, length(Ids)).

%%%===================================================================
%%% selectPage/4-5
%%%===================================================================

select_page_basic_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player() || _ <- lists:seq(1, 10)],
	ok = ePgdb:batchInsert(Players),
	{ok, Page1} = ePgdb:selectPage(?TABLE_PLAYERS, #{}, 1, 3),
	?assertEqual(1, maps:get(page, Page1)),
	?assertEqual(3, maps:get(page_size, Page1)),
	?assertEqual(3, length(maps:get(rows, Page1))),
	?assertEqual(true, maps:get(has_next, Page1)).

select_page_with_total_test(_Ctx) ->
	Players = [pgdb_test_helper:new_player() || _ <- lists:seq(1, 9)],
	ok = ePgdb:batchInsert(Players),
	{ok, Page} = ePgdb:selectPage(?TABLE_PLAYERS, #{}, 1, 4, [{count_total, true}]),
	?assertEqual(9, maps:get(total, Page)),
	?assertEqual(3, maps:get(total_pages, Page)),
	?assertEqual(4, length(maps:get(rows, Page))),
	?assertEqual(true, maps:get(has_next, Page)).

select_page_invalid_args_test(_Ctx) ->
	?assertEqual({error, invalid_page_args},
		ePgdb:selectPage(?TABLE_PLAYERS, #{}, 0, 10)),
	?assertEqual({error, invalid_page_args},
		ePgdb:selectPage(?TABLE_PLAYERS, #{}, 1, 0)).

%%%===================================================================
%%% jsonbSet / jsonbGet / jsonbDelete / jsonbMerge
%%%===================================================================

jsonb_set_and_get_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{profile => #{rank => 1, hp => 100}}),
	ok = ePgdb:insert(P),
	%% 修改 profile.rank 为 99
	{ok, 1} = ePgdb:jsonbSet(?TABLE_PLAYERS, profile, rank, 99,
		#{id => P#players.id}),
	{ok, 99} = ePgdb:jsonbGet(?TABLE_PLAYERS, profile, rank,
		#{id => P#players.id}).

jsonb_nested_path_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{profile => #{stats => #{atk => 10}}}),
	ok = ePgdb:insert(P),
	{ok, 1} = ePgdb:jsonbSet(?TABLE_PLAYERS, profile, [stats, atk], 999,
		#{id => P#players.id}),
	{ok, 999} = ePgdb:jsonbGet(?TABLE_PLAYERS, profile, [stats, atk],
		#{id => P#players.id}).

jsonb_delete_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{profile => #{rank => 1, extra => <<"delete_me">>}}),
	ok = ePgdb:insert(P),
	{ok, 1} = ePgdb:jsonbDelete(?TABLE_PLAYERS, profile, extra,
		#{id => P#players.id}),
	not_found = ePgdb:jsonbGet(?TABLE_PLAYERS, profile, extra,
		#{id => P#players.id}).

jsonb_merge_test(_Ctx) ->
	P = pgdb_test_helper:new_player(#{profile => #{rank => 1}}),
	ok = ePgdb:insert(P),
	{ok, 1} = ePgdb:jsonbMerge(?TABLE_PLAYERS, profile, #{vip_level => 3, guild => <<"phoenix">>},
		#{id => P#players.id}),
	{ok, VipLevel} = ePgdb:jsonbGet(?TABLE_PLAYERS, profile, vip_level,
		#{id => P#players.id}),
	?assertEqual(3, VipLevel).

jsonb_set_with_where_test(_Ctx) ->
	P1 = pgdb_test_helper:new_player(#{vip => true, profile => #{rank => 1}}),
	P2 = pgdb_test_helper:new_player(#{vip => false, profile => #{rank => 1}}),
	ok = ePgdb:insert(P1),
	ok = ePgdb:insert(P2),
	%% 只修改 vip=true 的玩家
	{ok, Updated} = ePgdb:jsonbSet(?TABLE_PLAYERS, profile, rank, 100, #{vip => true}),
	?assertEqual(1, Updated),
	{ok, 100} = ePgdb:jsonbGet(?TABLE_PLAYERS, profile, rank, #{id => P1#players.id}),
	{ok, 1} = ePgdb:jsonbGet(?TABLE_PLAYERS, profile, rank, #{id => P2#players.id}).

player_record_to_map(Player) ->
	#{
		table_name => players,
		id => Player#players.id,
		name => Player#players.name,
		level => Player#players.level,
		gold => Player#players.gold,
		vip => Player#players.vip,
		status => Player#players.status,
		profile => Player#players.profile,
		tags => Player#players.tags
	}.
