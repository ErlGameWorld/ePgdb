%%%-------------------------------------------------------------------
%%% @doc ePgdb SELECT 全场景深度测试。
%%%
%%% 覆盖所有 whereClause / whereValue / selectOpt 组合：
%%%
%%%   whereValue 测试：
%%%     精确匹配  (=)
%%%     null / not_null
%%%     比较运算  '>' '>=' '<' '<=' '!=' '<>'
%%%     IN / NOT IN
%%%     BETWEEN
%%%     LIKE / ILIKE
%%%     jsonb_contains (@>)
%%%     jsonb_key 路径查询
%%%     raw（原样 SQL 片段）
%%%
%%%   whereClause 测试：
%%%     map 形式（纯 AND）
%%%     list 形式（支持 OR 分组）
%%%     {'or', [Map1, Map2]}
%%%     多条件组合
%%%
%%%   selectOpt 测试：
%%%     fields      字段投影
%%%     order_by    排序（asc/desc/多字段）
%%%     limit       行数限制
%%%     offset      偏移
%%%     group_by    分组
%%%     having      HAVING 过滤
%%%     for_update  行级锁
%%%
%%%   高阶函数 / 分页：
%%%     selectPage + count_total
%%%     foreachRows / foldRows
%%%     foreachByKey / foldByKey
%%%
%%% 运行：
%%%   rebar3 eunit --module=pgdb_select_tests
%%%-------------------------------------------------------------------
-module(pgdb_select_tests).

-include_lib("eunit/include/eunit.hrl").

-define(TABLE, bench_users).

%%%===================================================================
%%% EUnit 入口
%%%===================================================================

select_all_test_() ->
	{setup,
		fun setup/0,
		fun teardown/1,
		{foreach,
			fun insert_fixtures/0,
			fun(_) -> ok end,
			[
				%% ── 基础精确匹配 ──────────────────────────────────────────
				test_case(fun select_empty_where_test/1),
				test_case(fun select_exact_match_test/1),
				test_case(fun select_no_result_test/1),
				
				%% ── NULL / NOT NULL ───────────────────────────────────────
				test_case(fun select_null_test/1),
				test_case(fun select_not_null_test/1),
				
				%% ── 比较运算符 ────────────────────────────────────────────
				test_case(fun select_gt_test/1),
				test_case(fun select_gte_test/1),
				test_case(fun select_lt_test/1),
				test_case(fun select_lte_test/1),
				test_case(fun select_ne_test/1),
				test_case(fun select_ne_alt_test/1),
				
				%% ── IN / NOT IN ───────────────────────────────────────────
				test_case(fun select_in_test/1),
				test_case(fun select_not_in_test/1),
				test_case(fun select_in_single_test/1),
				
				%% ── BETWEEN ──────────────────────────────────────────────
				test_case(fun select_between_test/1),
				test_case(fun select_between_boundary_test/1),
				
				%% ── LIKE / ILIKE ──────────────────────────────────────────
				test_case(fun select_like_prefix_test/1),
				test_case(fun select_like_suffix_test/1),
				test_case(fun select_like_contains_test/1),
				test_case(fun select_ilike_test/1),
				
				%% ── JSONB ─────────────────────────────────────────────────
				test_case(fun select_jsonb_contains_test/1),
				test_case(fun select_jsonb_key_eq_test/1),
				test_case(fun select_jsonb_key_gt_test/1),
				
				%% ── 原始 SQL 片段 ─────────────────────────────────────────
				test_case(fun select_raw_fragment_test/1),
				
				%% ── OR 分组 ───────────────────────────────────────────────
				test_case(fun select_or_group_test/1),
				test_case(fun select_or_in_list_test/1),
				
				%% ── 多字段 AND 组合 ───────────────────────────────────────
				test_case(fun select_multi_field_and_test/1),
				test_case(fun select_list_form_and_test/1),
				
				%% ── selectOpt ─────────────────────────────────────────────
				test_case(fun select_fields_projection_test/1),
				test_case(fun select_order_asc_test/1),
				test_case(fun select_order_desc_test/1),
				test_case(fun select_order_multi_test/1),
				test_case(fun select_limit_test/1),
				test_case(fun select_offset_test/1),
				test_case(fun select_limit_and_offset_test/1),
				test_case(fun select_group_by_test/1),
				test_case(fun select_having_test/1),
				test_case(fun select_for_update_test/1),
				
				%% ── selectSql ─────────────────────────────────────────────
				test_case(fun select_sql_returns_binary_test/1),
				
				%% ── selectPage ────────────────────────────────────────────
				test_case(fun select_page_first_page_test/1),
				test_case(fun select_page_last_page_test/1),
				test_case(fun select_page_with_total_test/1),
				test_case(fun select_page_with_filter_test/1),
				test_case(fun select_page_empty_result_test/1),
				
				%% ── foreachRows / foldRows ────────────────────────────────
				test_case(fun foreach_rows_paged_test/1),
				test_case(fun fold_rows_collect_test/1),
				test_case(fun fold_rows_sum_test/1),
				
				%% ── foreachByKey / foldByKey ──────────────────────────────
				test_case(fun foreach_by_key_full_test/1),
				test_case(fun fold_by_key_ids_test/1),
				test_case(fun fold_by_key_with_where_test/1)
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

%% 每组测试前清空并写入固定 fixture
insert_fixtures() ->
	pgdb_test_helper:truncate(?TABLE),
	%% age 段：20~60
	%% score 段：100~1000
	%% is_active：前5条 true，后5条 false
	lists:foreach(fun(I) ->
		U = pgdb_test_helper:new_bench_user(#{
			id => I,
			name => <<"user_", (integer_to_binary(I))/binary>>,
			email => <<"user_", (integer_to_binary(I))/binary, "@example.com">>,
			age => 20 + I,         %% 21..30
			score => I * 100,        %% 100..1000
			balance => I * 50,         %% 50..500
			is_active => I =< 5,         %% 1-5: true, 6-10: false
			profile => #{level => I, tier => <<"gold">>},
			tags => [<<"erlang">>, <<"user_", (integer_to_binary(I))/binary>>]
		}),
		ok = ePgdb:insert(U)
				  end, lists:seq(1, 10)).

%%%===================================================================
%%% 基础精确匹配
%%%===================================================================

select_empty_where_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{}),
	?assertEqual(10, length(Rows)).

select_exact_match_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{id => 3}, [{fields, [id]}]),
	?assertEqual(1, length(Rows)),
	[R] = Rows,
	?assertEqual(3, maps:get(id, R)).

select_no_result_test(_Ctx) ->
	{ok, []} = ePgdb:select(?TABLE, #{id => 99999}).

%%%===================================================================
%%% NULL / NOT NULL
%%%===================================================================

select_null_test(_Ctx) ->
	%% login_at 默认 undefined，写入为 NULL
	{ok, Rows} = ePgdb:select(?TABLE, #{login_at => null}),
	?assertEqual(10, length(Rows)).

select_not_null_test(_Ctx) ->
	%% email 全部有值
	{ok, Rows} = ePgdb:select(?TABLE, #{email => not_null}),
	?assertEqual(10, length(Rows)).

%%%===================================================================
%%% 比较运算符
%%%===================================================================

select_gt_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{score => {'>', 500}}),
	%% score > 500: ids 6~10
	?assertEqual(5, length(Rows)).

select_gte_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{score => {'>=', 500}}),
	%% score >= 500: ids 5~10
	?assertEqual(6, length(Rows)).

select_lt_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{score => {'<', 300}}),
	%% score < 300: ids 1,2
	?assertEqual(2, length(Rows)).

select_lte_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{score => {'<=', 300}}),
	%% score <= 300: ids 1,2,3
	?assertEqual(3, length(Rows)).

select_ne_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{id => {'!=', 1}}),
	?assertEqual(9, length(Rows)).

select_ne_alt_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{id => {'<>', 10}}),
	?assertEqual(9, length(Rows)).

%%%===================================================================
%%% IN / NOT IN
%%%===================================================================

select_in_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{id => {in, [1, 3, 5]}}, [{fields, [id]}]),
	Ids = lists:sort([maps:get(id, R) || R <- Rows]),
	?assertEqual([1, 3, 5], Ids).

select_not_in_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{id => {not_in, [1, 2, 3]}}, [{fields, [id]}]),
	?assertEqual(7, length(Rows)),
	Ids = [maps:get(id, R) || R <- Rows],
	?assertNot(lists:member(1, Ids)),
	?assertNot(lists:member(2, Ids)).

select_in_single_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{age => {in, [21]}}),
	?assertEqual(1, length(Rows)).

%%%===================================================================
%%% BETWEEN
%%%===================================================================

select_between_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{score => {between, 300, 600}}),
	%% score 300~600: ids 3,4,5,6
	?assertEqual(4, length(Rows)).

select_between_boundary_test(_Ctx) ->
	%% 边界值应包含
	{ok, Rows} = ePgdb:select(?TABLE, #{score => {between, 100, 100}}, [{fields, [id]}]),
	?assertEqual(1, length(Rows)),
	[R] = Rows,
	?assertEqual(1, maps:get(id, R)).

%%%===================================================================
%%% LIKE / ILIKE
%%%===================================================================

select_like_prefix_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{name => {like, <<"user_%">>}}),
	?assertEqual(10, length(Rows)).

select_like_suffix_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{name => {like, <<"%_5">>}}, [{fields, [name]}]),
	?assertEqual(1, length(Rows)),
	[R] = Rows,
	?assertEqual(<<"user_5">>, maps:get(name, R)).

select_like_contains_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{email => {like, <<"%@example.com">>}}),
	?assertEqual(10, length(Rows)).

select_ilike_test(_Ctx) ->
	%% ILIKE 不区分大小写
	{ok, Rows} = ePgdb:select(?TABLE, #{name => {ilike, <<"USER_%">>}}),
	?assertEqual(10, length(Rows)).

%%%===================================================================
%%% JSONB 查询
%%%===================================================================

select_jsonb_contains_test(_Ctx) ->
	%% profile 包含指定子集
	{ok, Rows} = ePgdb:select(?TABLE, #{profile => {jsonb_contains, #{tier => <<"gold">>}}}),
	?assertEqual(10, length(Rows)).

select_jsonb_key_eq_test(_Ctx) ->
	%% profile->>'level' = '3' （jsonb_key 路径查询）
	{ok, Rows} = ePgdb:select(?TABLE, #{profile => {jsonb_key, level, '=', 3}}, [{fields, [id]}]),
	?assertEqual(1, length(Rows)),
	[R] = Rows,
	?assertEqual(3, maps:get(id, R)).

select_jsonb_key_gt_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{profile => {jsonb_key, level, '>', 7}}),
	%% level > 7: ids 8,9,10
	?assertEqual(3, length(Rows)).

%%%===================================================================
%%% 原始 SQL 片段 (raw)
%%%===================================================================

select_raw_fragment_test(_Ctx) ->
	%% raw 直接嵌入 SQL，用于框架内部或完全可信的静态 SQL
	{ok, Rows} = ePgdb:select(?TABLE, #{score => {raw, <<"score > 800">>}}),
	%% score > 800: ids 9,10
	?assertEqual(2, length(Rows)).

%%%===================================================================
%%% OR 分组
%%%===================================================================

select_or_group_test(_Ctx) ->
	%% (id = 1) OR (id = 10)
	{ok, Rows} = ePgdb:select(?TABLE, [{'or', [#{id => 1}, #{id => 10}]}], [{fields, [id]}]),
	Ids = lists:sort([maps:get(id, R) || R <- Rows]),
	?assertEqual([1, 10], Ids).

select_or_in_list_test(_Ctx) ->
	%% (is_active = true) OR (score >= 900)
	{ok, Rows} = ePgdb:select(?TABLE, [{'or', [
		#{is_active => true},
		#{score => {'>=', 900}}
	]}]),
	%% is_active=true: 1~5; score>=900: 9,10; 并集: 1~5,9,10 = 7
	?assertEqual(7, length(Rows)).

%%%===================================================================
%%% 多字段 AND 组合
%%%===================================================================

select_multi_field_and_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{is_active => true, score => {'>', 300}}),
	%% is_active=true(1~5) AND score>300(4~10) → 4,5
	?assertEqual(2, length(Rows)).

select_list_form_and_test(_Ctx) ->
	%% List 形式，支持三元组 {Field, Op, Value}
	Where = [{age, '>=', 25}, {score, '<', 800}],
	{ok, Rows} = ePgdb:select(?TABLE, Where),
	%% age >= 25: ids 5~10; score < 800: ids 1~7; 交集: 5,6,7
	?assertEqual(3, length(Rows)).

%%%===================================================================
%%% selectOpt
%%%===================================================================

select_fields_projection_test(_Ctx) ->
	{ok, [Row | _]} = ePgdb:select(?TABLE, #{id => 1}, [{fields, [id, name, score]}]),
	?assert(maps:is_key(id, Row)),
	?assert(maps:is_key(name, Row)),
	?assert(maps:is_key(score, Row)),
	?assertNot(maps:is_key(age, Row)),
	?assertNot(maps:is_key(email, Row)).

select_order_asc_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{}, [{fields, [score]}, {order_by, [{score, asc}]}]),
	Scores = [maps:get(score, R) || R <- Rows],
	?assertEqual(Scores, lists:sort(Scores)).

select_order_desc_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{}, [{fields, [score]}, {order_by, [{score, desc}]}]),
	Scores = [maps:get(score, R) || R <- Rows],
	?assertEqual(Scores, lists:reverse(lists:sort(Scores))).

select_order_multi_test(_Ctx) ->
	%% 多字段排序: is_active desc, score asc
	{ok, Rows} = ePgdb:select(?TABLE, #{}, [
		{fields, [is_active, score]},
		{order_by, [{is_active, desc}, {score, asc}]}
	]),
	%% 前5条应该是 is_active=true 且 score 升序
	First5 = lists:sublist(Rows, 5),
	?assert(lists:all(fun(R) -> maps:get(is_active, R) =:= true end, First5)),
	Scores5 = [maps:get(score, R) || R <- First5],
	?assertEqual(Scores5, lists:sort(Scores5)).

select_limit_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{}, [{limit, 3}]),
	?assertEqual(3, length(Rows)).

select_offset_test(_Ctx) ->
	{ok, AllRows} = ePgdb:select(?TABLE, #{}, [{fields, [id]}, {order_by, [{id, asc}]}]),
	{ok, OffsetRows} = ePgdb:select(?TABLE, #{}, [{fields, [id]}, {order_by, [{id, asc}]}, {offset, 5}]),
	AllIds = [maps:get(id, R) || R <- AllRows],
	OffsetIds = [maps:get(id, R) || R <- OffsetRows],
	?assertEqual(lists:nthtail(5, AllIds), OffsetIds).

select_limit_and_offset_test(_Ctx) ->
	{ok, Rows} = ePgdb:select(?TABLE, #{}, [{fields, [id]}, {order_by, [{id, asc}]}, {limit, 3}, {offset, 3}]),
	Ids = [maps:get(id, R) || R <- Rows],
	?assertEqual([4, 5, 6], Ids).

select_group_by_test(_Ctx) ->
	%% group by is_active，count 每组
	{ok, Rows} = ePgdb:select(?TABLE, #{}, [
		{fields, [is_active]},
		{group_by, [is_active]},
		{order_by, [{is_active, asc}]}
	]),
	?assertEqual(2, length(Rows)).

select_having_test(_Ctx) ->
	%% 按 is_active 分组，HAVING count(*) > 4
	{ok, Rows} = ePgdb:select(?TABLE, #{}, [
		{fields, [is_active]},
		{group_by, [is_active]},
		{having, <<"COUNT(*) > 4">>}
	]),
	?assertEqual(2, length(Rows)).

select_for_update_test(_Ctx) ->
	%% for_update 在事务中锁行
	{ok, _} = ePgdb:transaction(fun(_Conn) ->
		{ok, Rows} = ePgdb:select(?TABLE, #{id => 1}, [{for_update, true}]),
		?assertEqual(1, length(Rows)),
		ok
								end).

%%%===================================================================
%%% selectSql
%%%===================================================================

select_sql_returns_binary_test(_Ctx) ->
	{SQL, Params} = ePgdb:selectSql(?TABLE,
		#{score => {'>', 500}},
		[{limit, 5}, {order_by, [{score, asc}]}]),
	?assert(is_binary(SQL)),
	?assert(is_list(Params)).

%%%===================================================================
%%% selectPage
%%%===================================================================

select_page_first_page_test(_Ctx) ->
	{ok, Page} = ePgdb:selectPage(?TABLE, #{}, 1, 3, [{fields, [id]}, {order_by, [{id, asc}]}]),
	Rows = maps:get(rows, Page),
	?assertEqual(3, length(Rows)),
	Ids = [maps:get(id, R) || R <- Rows],
	?assertEqual([1, 2, 3], Ids).

select_page_last_page_test(_Ctx) ->
	{ok, Page} = ePgdb:selectPage(?TABLE, #{}, 4, 3, [{order_by, [{id, asc}]}]),
	Rows = maps:get(rows, Page),
	%% 第4页（每页3条）：10 共1条
	?assertEqual(1, length(Rows)),
	?assertEqual(false, maps:get(has_next, Page)).

select_page_with_total_test(_Ctx) ->
	{ok, Page} = ePgdb:selectPage(?TABLE, #{}, 2, 4, [{count_total, true}]),
	?assertEqual(10, maps:get(total, Page)),
	?assertEqual(3, maps:get(total_pages, Page)),
	?assertEqual(true, maps:get(has_next, Page)).

select_page_with_filter_test(_Ctx) ->
	{ok, Page} = ePgdb:selectPage(?TABLE, #{is_active => true}, 1, 3,
		[{count_total, true}]),
	?assertEqual(5, maps:get(total, Page)),
	?assertEqual(2, maps:get(total_pages, Page)).

select_page_empty_result_test(_Ctx) ->
	{ok, Page} = ePgdb:selectPage(?TABLE, #{id => 99999}, 1, 10,
		[{count_total, true}]),
	?assertEqual(0, maps:get(total, Page)),
	?assertEqual([], maps:get(rows, Page)).

%%%===================================================================
%%% foreachRows / foldRows
%%%===================================================================

foreach_rows_paged_test(_Ctx) ->
	%% PageSize=3，总10条，验证全部遍历
	Counter = counters:new(1, []),
	ok = ePgdb:foreachRows(?TABLE, #{}, 3, fun(_Row) ->
		counters:add(Counter, 1, 1)
										   end),
	?assertEqual(10, counters:get(Counter, 1)).

fold_rows_collect_test(_Ctx) ->
	%% 收集所有 id
	{ok, Ids} = ePgdb:foldRows(?TABLE, #{}, 4, [{fields, [id]}], fun(Row, Acc) ->
		[maps:get(id, Row) | Acc]
																 end, []),
	?assertEqual(10, length(Ids)).

fold_rows_sum_test(_Ctx) ->
	{ok, Total} = ePgdb:foldRows(?TABLE, #{}, 5, [{fields, [score]}], fun(Row, Acc) ->
		Acc + maps:get(score, Row)
																	  end, 0),
	%% sum(100..1000) = 5500
	?assertEqual(5500, Total).

%%%===================================================================
%%% foreachByKey / foldByKey (keyset 扫描)
%%%===================================================================

foreach_by_key_full_test(_Ctx) ->
	Counter = counters:new(1, []),
	ok = ePgdb:foreachByKey(?TABLE, #{}, id, 3, fun(_Row) ->
		counters:add(Counter, 1, 1)
												end),
	?assertEqual(10, counters:get(Counter, 1)).

fold_by_key_ids_test(_Ctx) ->
	{ok, Ids} = ePgdb:foldByKey(?TABLE, #{}, id, 3, [{fields, [id]}], fun(Row, Acc) ->
		[maps:get(id, Row) | Acc]
																	  end, []),
	?assertEqual(10, length(Ids)).

fold_by_key_with_where_test(_Ctx) ->
	%% 只扫 is_active=true 的行（5 条）
	{ok, Ids} = ePgdb:foldByKey(?TABLE, #{is_active => true}, id, 2, [{fields, [id]}], fun(Row, Acc) ->
		[maps:get(id, Row) | Acc]
																					   end, []),
	?assertEqual(5, length(Ids)),
	?assert(lists:all(fun(Id) -> Id =< 5 end, Ids)).

