-module(tcPgdb).

-compile([export_all, nowarn_export_all]).

-include("pg_bench_schema.hrl").

-define(BATCH_SIZES, [10, 100, 500]).
-define(SCAN_ROW_COUNT, 5000).
-define(SCAN_PAGE_SIZE, 200).
-define(SMALL_BLOB, binary:copy(<<"a">>, 1024)).
-define(MEDIUM_BLOB, binary:copy(<<"b">>, 64 * 1024)).
-define(LARGE_BLOB, binary:copy(<<"c">>, 256 * 1024)).

%% tc = throughput check.
%% 这个模块复用 utTc 的统计输出，专门从 ePgdb API 视角做性能测试。
%%
%% 推荐进入 test shell 后执行：
%%   rebar3 as test shell
%%
%% 整套测试入口：
%%   tcPgdb:main().
%%   tcPgdb:main("", 1, 1000).
%%   tcPgdb:main("tc_pgdb_bench.log", 4, 500).
%%
%% 单独跑某一组：
%%   tcPgdb:crud_performance_test(1, 1000).
%%   tcPgdb:batch_performance_test(1, 300).
%%   tcPgdb:structure_performance_test(1, 300).
%%   tcPgdb:query_performance_test(1, 200).
%%   tcPgdb:transaction_performance_test(1, 300).
%%   tcPgdb:mixed_workload_performance_test(4, 500).
%%   tcPgdb:compare_direct_vs_epgdb(1000).
%%   tcPgdb:compare_write_patterns(300).
%%   tcPgdb:compare_write_patterns(300, 100).
%%
%% 裸数据库 vs ePgdb 全链路对照测试：
%%   tcPgdb:compare_direct_vs_epgdb(1000).
%%   tcPgdb:compare_direct_vs_epgdb(5000).
%%
%% 单条写 vs 批量写 vs 单事务多条写：
%%   tcPgdb:compare_write_patterns(300).
%%   tcPgdb:compare_write_patterns(300, 100).
%%   tcPgdb:compare_write_patterns(1000, 200).
%%
%% 这组测试会把输出明确分成 3 段：
%%   1) DIRECT DB
%%      直接使用 epgsql 测 PostgreSQL 裸性能。
%%   2) EPGDB FULL PATH
%%      走 ePgdb 的 schema + queue + worker + codec 全链路。
%%   3) DELTA
%%      对比全链路相对裸数据库的放大倍数和 QPS 差值。
%%
%% 对照测试推荐用法：
%%   1) 先跑一次小样本快速看趋势:
%%      tcPgdb:compare_direct_vs_epgdb(1000).
%%   2) 再跑一轮大样本看稳定值:
%%      tcPgdb:compare_direct_vs_epgdb(5000).
%%   3) 如果改了 codec / query builder / worker 调度，优先重跑这组对照测试看额外开销是否变化。
%%
%% 参数说明：
%%   ProcessCnt = 并发进程数。
%%   LoopCnt    = 每个进程的执行次数。
%%
%% 开发机 quick 跑法：
%%   目标：快速看趋势、确认功能和大致耗时，不追求极限稳定性。
%%   推荐参数：
%%     1) 全量冒烟: tcPgdb:main("", 1, 100).
%%     2) 单项基线: tcPgdb:crud_performance_test(1, 200).
%%     3) 轻并发:   tcPgdb:mixed_workload_performance_test(2, 100).
%%     4) 查询扫描: tcPgdb:query_performance_test(1, 100).
%%   说明：
%%     - 单进程优先，避免本机 CPU 抢占把结果放大失真。
%%     - LoopCnt 建议先控制在 100 到 300，结果出来更快。
%%     - 适合改完 SQL、codec、query builder、worker 调度后做回归对比。
%%
%% 单机正式压测跑法：
%%   目标：在一台机器上相对稳定地比较不同实现、参数、schema 设计差异。
%%   推荐步骤：
%%     1) 预热:     tcPgdb:crud_performance_test(1, 300).
%%     2) 单进程基线: tcPgdb:main("single_baseline.log", 1, 1000).
%%     3) 轻并发:   tcPgdb:main("concurrency_4.log", 4, 1000).
%%     4) 中并发:   tcPgdb:main("concurrency_8.log", 8, 1000).
%%     5) 混合负载: tcPgdb:mixed_workload_performance_test(8, 1500).
%%   说明：
%%     - ProcessCnt 建议从 1、4、8 逐步拉高，不建议一开始直接上很大并发。
%%     - LoopCnt 建议 1000 起步；如果想看更稳的分位值，可提升到 2000 或 3000。
%%     - 正式比较时尽量固定 PostgreSQL 配置、连接池参数、数据量和机器负载。
%%     - 如需保留输出，建议给 main/3 传日志文件名，便于后续横向对比。
%%
%% 注意：
%%   - 每组测试都会自行启动/停止 ePgdb，并清理压测表。
%%   - query_performance_test/2、transaction_performance_test/2、mixed_workload_performance_test/2
%%     会预填部分数据，因此更适合看真实读写路径的成本。
%%   - 如果要做更严格的数据库压测，建议把 PostgreSQL 和 Erlang 节点部署在稳定独占环境下重复多轮执行。

main() ->
	main("", 1, 1000).

main(FileName, ProcessCnt, LoopCnt) ->
	{GL, Fd} =
		case FileName of
			"" ->
				{undefined, undefined};
			_ ->
				GL0 = group_leader(),
				{ok, F} = file:open(FileName, [append, {encoding, utf8}]),
				group_leader(F, self()),
				{GL0, F}
		end,
	try
		io:format("========================================~n"),
		io:format("         ePgdb 性能测试套件            ~n"),
		io:format("========================================~n"),
		io:format("ProcessCnt=~p LoopCnt=~p~n~n", [ProcessCnt, LoopCnt]),
		lists:foreach(
			fun({Fun, Name}) ->
				io:format("运行测试: ~ts~n", [Name]),
				try
					apply(?MODULE, Fun, [ProcessCnt, LoopCnt]),
					io:format("✓ ~ts 完成~n~n", [Name])
				catch
					Class:Reason:Stack ->
						io:format("✗ ~ts 失败: ~p:~p~n~p~n~n", [Name, Class, Reason, Stack])
				end
			end,
			[
				{crud_performance_test, "基础 CRUD 性能测试"},
				{batch_performance_test, "批量操作性能测试"},
				{structure_performance_test, "不同数据结构性能对比"},
				{query_performance_test, "查询与扫描性能测试"},
				{transaction_performance_test, "事务与直连回调性能测试"},
				{mixed_workload_performance_test, "混合读写性能测试"}
			]),
		io:format("========================================~n"),
		io:format("       所有性能测试运行完成           ~n"),
		io:format("========================================~n")
	after
		case FileName of
			"" ->
				ok;
			_ ->
				group_leader(GL, self()),
				file:close(Fd)
		end
	end.

crud_performance_test(ProcessCnt, LoopCnt) ->
	with_bench_env(fun() ->
		io:format("=== 基础 CRUD 性能测试 ===~n"),
		run_case("insert bench_users(record)", ProcessCnt, LoopCnt, insert_user, {fun generate_insert_user_args/0, []}),
		run_case("get bench_users by primary key", ProcessCnt, LoopCnt, get_user, {fun generate_get_user_args/0, []}),
		run_case("select bench_users by unique email", ProcessCnt, LoopCnt, select_user_by_email, {fun generate_select_user_by_email_args/0, []}),
		run_case("update bench_users score/profile", ProcessCnt, LoopCnt, update_user_score, {fun generate_update_user_score_args/0, []}),
		run_case("delete bench_users by primary key", ProcessCnt, LoopCnt, delete_user, {fun generate_delete_user_args/0, []}),
		io:format("=== 基础 CRUD 性能测试完成 ===~n")
				   end).

batch_performance_test(ProcessCnt, LoopCnt) ->
	with_bench_env(fun() ->
		io:format("=== 批量操作性能测试 ===~n"),
		[
			begin
				io:format("批量大小: ~p~n", [BatchSize]),
				run_case("batchInsert bench_users", ProcessCnt, LoopCnt, batch_insert_users, {fun generate_batch_insert_users_args/1, [BatchSize]}),
				run_case("batchDeleteByKey bench_users", ProcessCnt, LoopCnt, batch_delete_users, {fun generate_batch_delete_users_args/1, [BatchSize]}),
				run_case("batchInsert bench_events(map)", ProcessCnt, LoopCnt, batch_insert_events, {fun generate_batch_insert_events_args/1, [BatchSize]})
			end
			|| BatchSize <- ?BATCH_SIZES
		],
		io:format("=== 批量操作性能测试完成 ===~n")
				   end).

structure_performance_test(ProcessCnt, LoopCnt) ->
	with_bench_env(fun() ->
		io:format("=== 不同数据结构性能对比 ===~n"),
		run_case("record insert bench_users", ProcessCnt, LoopCnt, insert_user, {fun generate_insert_user_args/0, []}),
		run_case("map insert bench_events", ProcessCnt, LoopCnt, insert_event, {fun generate_insert_event_args/0, []}),
		run_case("map upsert bench_kv(existing key)", ProcessCnt, LoopCnt, upsert_kv_existing, {fun generate_upsert_kv_existing_args/0, []}),
		run_case("jsonbSet bench_users.profile", ProcessCnt, LoopCnt, jsonb_set_user_profile, {fun generate_jsonb_set_user_profile_args/0, []}),
		run_case("jsonbGet bench_users.profile", ProcessCnt, LoopCnt, jsonb_get_user_profile, {fun generate_jsonb_get_user_profile_args/0, []}),
		[
			begin
				io:format("blob 大小: ~ts~n", [Label]),
				run_case("insert bench_blobs(bytea)", ProcessCnt, LoopCnt, insert_blob, {fun generate_insert_blob_args/2, [Label, Blob]})
			end
			|| {Label, Blob} <- [{"1KB", ?SMALL_BLOB}, {"64KB", ?MEDIUM_BLOB}, {"256KB", ?LARGE_BLOB}]
		],
		io:format("=== 不同数据结构性能对比完成 ===~n")
				   end).

query_performance_test(ProcessCnt, LoopCnt) ->
	with_bench_env(fun() ->
		io:format("=== 查询与扫描性能测试 ===~n"),
		prepare_users(?SCAN_ROW_COUNT),
		run_case("get bench_users existing row", ProcessCnt, LoopCnt, get_existing_user, {fun generate_existing_user_id_args/1, [?SCAN_ROW_COUNT]}),
		run_case("query SQL by id", ProcessCnt, LoopCnt, query_user_sql, {fun generate_existing_user_id_args/1, [?SCAN_ROW_COUNT]}),
		run_case("selectPage bench_users", ProcessCnt, LoopCnt, select_user_page, {fun generate_select_user_page_args/0, []}),
		run_case("foreachByKey bench_users", ProcessCnt, LoopCnt, foreach_users_by_key, [?SCAN_PAGE_SIZE]),
		run_case("foldRows bench_users", ProcessCnt, LoopCnt, fold_user_rows, [?SCAN_PAGE_SIZE]),
		run_case("select profile jsonb_contains", ProcessCnt, LoopCnt, select_user_by_json_profile, {fun generate_select_user_by_json_profile_args/0, []}),
		io:format("=== 查询与扫描性能测试完成 ===~n")
				   end).

transaction_performance_test(ProcessCnt, LoopCnt) ->
	with_bench_env(fun() ->
		io:format("=== 事务与直连回调性能测试 ===~n"),
		prepare_users(?SCAN_ROW_COUNT),
		run_case("transaction insert order and update user", ProcessCnt, LoopCnt, transaction_insert_order_and_update_user, {fun generate_transaction_insert_order_args/0, []}),
		run_case("withConnection get by id", ProcessCnt, LoopCnt, with_connection_get_user, {fun generate_existing_user_id_args/1, [?SCAN_ROW_COUNT]}),
		run_case("withConnection direct squery", ProcessCnt, LoopCnt, with_connection_direct_squery, []),
		io:format("=== 事务与直连回调性能测试完成 ===~n")
				   end).

mixed_workload_performance_test(ProcessCnt, LoopCnt) ->
	with_bench_env(fun() ->
		io:format("=== 混合读写性能测试 ===~n"),
		prepare_users(?SCAN_ROW_COUNT),
		prepare_kv(1000),
		run_case("mixed read/write workload", ProcessCnt, LoopCnt, mixed_read_write_once, {fun generate_mixed_read_write_args/1, [?SCAN_ROW_COUNT]}),
		io:format("=== 混合读写性能测试完成 ===~n")
				   end).

compare_direct_vs_epgdb(Cnt) when is_integer(Cnt), Cnt > 0 ->
	with_bench_env(fun() ->
		CompareUserId = 1,
		seed_compare_fixture(CompareUserId),
		io:format("========================================~n"),
		io:format("  数据库裸性能 vs ePgdb 全链路 对照测试  ~n"),
		io:format("========================================~n"),
		io:format("样本次数(Cnt)=~p~n", [Cnt]),
		io:format("说明: direct db 为直接 epgsql, ePgdb full path 为 schema + queue + worker + codec 全链路。~n~n", []),
		DirectRead = pgtest:qps_report(Cnt),
		DirectWrite = direct_write_report(Cnt),
		FullRead = full_chain_read_report(Cnt, CompareUserId),
		FullWrite = full_chain_write_report(Cnt),
		print_direct_compare_section(DirectRead, DirectWrite),
		print_full_path_compare_section(FullRead, FullWrite),
		print_compare_delta_section(DirectRead, DirectWrite, FullRead, FullWrite),
		#{
			direct_db => #{read => DirectRead, write => DirectWrite},
			ePgdb_full_path => #{read => FullRead, write => FullWrite}
		}
				   end).

compare_write_patterns(Cnt) when is_integer(Cnt), Cnt > 0 ->
	compare_write_patterns(Cnt, 100).

compare_write_patterns(Cnt, RowsPerWrite)
	when is_integer(Cnt), Cnt > 0, is_integer(RowsPerWrite), RowsPerWrite > 1 ->
	with_bench_env(fun() ->
		io:format("========================================~n"),
		io:format("   写路径对照: 单条写 / 批量写 / 单事务多条写   ~n"),
		io:format("========================================~n"),
		io:format("样本次数(Cnt)=~p RowsPerWrite=~p~n", [Cnt, RowsPerWrite]),
		io:format("说明: single 为单条自动提交, batch 为单 SQL 多行写入, tx_multi 为单事务内多条 insert。~n~n", []),
		Direct = direct_write_patterns_report(Cnt, RowsPerWrite),
		pgdb_test_helper:truncate(bench_kv),
		Full = full_chain_write_patterns_report(Cnt, RowsPerWrite),
		print_write_patterns_section("DIRECT DB | 裸数据库直连", Direct),
		print_write_patterns_section("EPGDB FULL PATH | schema + queue + worker + codec", Full),
		print_write_pattern_gain_section("DIRECT DB 增益", Direct),
		print_write_pattern_gain_section("EPGDB FULL PATH 增益", Full),
		print_write_pattern_delta_section(Direct, Full),
		#{
			direct_db => Direct,
			ePgdb_full_path => Full,
			rows_per_write => RowsPerWrite,
			sample_count => Cnt
		}
				   end).

with_bench_env(Fun) ->
	seed_rand(),
	pgdb_test_helper:start(),
	try
		pgdb_test_helper:truncate_all(),
		Fun()
	after
		pgdb_test_helper:stop()
	end.

run_case(Label, ProcessCnt, LoopCnt, FunName, ArgsSpec) when ProcessCnt =< 1 ->
	io:format("~n--- ~ts ---~n", [Label]),
	utTc:tc(LoopCnt, ?MODULE, FunName, ArgsSpec);
run_case(Label, ProcessCnt, LoopCnt, FunName, ArgsSpec) ->
	io:format("~n--- ~ts ---~n", [Label]),
	utTc:tc(ProcessCnt, LoopCnt, ?MODULE, FunName, ArgsSpec).

seed_rand() ->
	rand:seed(exsplus, {
		erlang:phash2(node()),
		erlang:unique_integer([positive]),
		erlang:phash2(self())
	}).

insert_user(User) ->
	assert_ok(ePgdb:insert(User)).

get_user(Id) ->
	assert_rows(ePgdb:get(bench_users, #{id => Id})).

select_user_by_email(Email) ->
	assert_rows(ePgdb:select(bench_users, #{email => Email}, [{fields, [id, email, score]}, {limit, 1}])).

update_user_score(User, Fields, Where) ->
	assert_count(ePgdb:update(User, Fields, Where)).

delete_user(Id) ->
	assert_count(ePgdb:delete(bench_users, #{id => Id})).

batch_insert_users(Users) ->
	assert_ok(ePgdb:batchInsert(Users)).

batch_delete_users(Keys) ->
	assert_count(ePgdb:batchDelByKey(bench_users, id, Keys)).

batch_insert_events(Events) ->
	assert_ok(ePgdb:batchInsert(Events)).

insert_event(Event) ->
	assert_ok(ePgdb:insert(Event)).

upsert_kv_existing(Kv) ->
	case ePgdb:upsert(Kv, [key], [value, version, ttl]) of
		{ok, _Row} -> ok;
		Other -> error({unexpected_upsert_result, Other})
	end.

jsonb_set_user_profile(Id, Path, Value) ->
	assert_count(ePgdb:jsonbSet(bench_users, profile, Path, Value, #{id => Id})).

jsonb_get_user_profile(Id, Path) ->
	case ePgdb:jsonbGet(bench_users, profile, Path, #{id => Id}) of
		{ok, _Value} -> ok;
		Other -> error({unexpected_jsonb_get_result, Other})
	end.

insert_blob(Blob) ->
	assert_ok(ePgdb:insert(Blob)).

get_existing_user(Id) ->
	assert_rows(ePgdb:get(bench_users, #{id => Id})).

query_user_sql(Id) ->
	case ePgdb:query("select id, name, score from bench_users where id = $1", [Id]) of
		{ok, _Cols, [_Row]} -> ok;
		{ok, _Count, _Cols, [_Row]} -> ok;
		Other -> error({unexpected_query_result, Other})
	end.

select_user_page(PageNo, PageSize) ->
	case ePgdb:selectPage(bench_users, #{}, PageNo, PageSize, [{fields, [id, score]}, {order_by, [{id, asc}]}, {count_total, true}]) of
		{ok, _Page} -> ok;
		Other -> error({unexpected_select_page_result, Other})
	end.

foreach_users_by_key(PageSize) ->
	case ePgdb:foreachByKey(bench_users, #{}, id, PageSize, fun(_Row) -> ok end) of
		ok -> ok;
		Other -> error({unexpected_foreach_by_key_result, Other})
	end.

fold_user_rows(PageSize) ->
	case ePgdb:foldRows(bench_users, #{}, PageSize, fun(_Row, Acc) -> Acc + 1 end, 0) of
		{ok, Count} when Count > 0 -> ok;
		Other -> error({unexpected_fold_rows_result, Other})
	end.

select_user_by_json_profile(Level) ->
	case ePgdb:select(bench_users, #{profile => {jsonb_key, level, '=', Level}}, [{fields, [id]}, {limit, 10}]) of
		{ok, [_ | _]} -> ok;
		Other -> error({unexpected_json_select_result, Other})
	end.

transaction_insert_order_and_update_user(User, Order, UserId) ->
	case ePgdb:transaction(fun(Conn) ->
		ok = ePgdb:insertC(Conn, User),
		ok = ePgdb:insertC(Conn, Order),
		{ok, 1} = ePgdb:update(Conn, User#bench_users{score = User#bench_users.score + 10}, [#bench_users.score], #{id => UserId}),
		ok
						   end) of
		{ok, ok} -> ok;
		Other -> error({unexpected_transaction_result, Other})
	end.

with_connection_get_user(Id) ->
	case ePgdb:withConnection(fun(Conn) -> ePgdb:get(Conn, bench_users, #{id => Id}, []) end) of
		{ok, [_ | _]} -> ok;
		Other -> error({unexpected_with_connection_result, Other})
	end.

with_connection_direct_squery() ->
	case ePgdb:withConnection(fun(Conn) -> epgsql:squery(Conn, "SELECT 1") end) of
		{ok, _Cols, _Rows} -> ok;
		{ok, _Count, _Cols, _Rows} -> ok;
		Other -> error({unexpected_direct_squery_result, Other})
	end.

mixed_read_write_once(MaxId) ->
	case rand:uniform(5) of
		1 ->
			Id = random_existing_id(MaxId),
			assert_rows(ePgdb:get(bench_users, #{id => Id}));
		2 ->
			Id = random_existing_id(MaxId),
			User = #bench_users{id = Id, score = rand:uniform(100000), profile = #{level => rand:uniform(60), mood => <<"hot">>}},
			assert_count(ePgdb:update(User, [#bench_users.score, #bench_users.profile], #{id => Id}));
		3 ->
			assert_ok(ePgdb:insert(make_user(erlang:unique_integer([positive, monotonic]))));
		4 ->
			Key = <<"kv_", (integer_to_binary(rand:uniform(1000)))/binary>>,
			case ePgdb:upsert(pgdb_test_helper:new_kv(Key, #{tick => erlang:unique_integer([positive])}), [key], [value, version]) of
				{ok, _} -> ok;
				Other -> error({unexpected_mixed_upsert_result, Other})
			end;
		5 ->
			Id = random_existing_id(MaxId),
			assert_count(ePgdb:jsonbSet(bench_users, profile, [stress, tick], erlang:unique_integer([positive]), #{id => Id}))
	end.

generate_insert_user_args() ->
	[make_user(erlang:unique_integer([positive, monotonic]))].

generate_get_user_args() ->
	User = make_user(erlang:unique_integer([positive, monotonic])),
	ok = ePgdb:insert(User),
	[User#bench_users.id].

generate_select_user_by_email_args() ->
	User = make_user(erlang:unique_integer([positive, monotonic])),
	ok = ePgdb:insert(User),
	[User#bench_users.email].

generate_update_user_score_args() ->
	User = make_user(erlang:unique_integer([positive, monotonic])),
	ok = ePgdb:insert(User),
	Updated = User#bench_users{score = User#bench_users.score + 1, profile = #{level => 9, tier => <<"diamond">>}},
	[Updated, [#bench_users.score, #bench_users.profile], #{id => User#bench_users.id}].

generate_delete_user_args() ->
	User = make_user(erlang:unique_integer([positive, monotonic])),
	ok = ePgdb:insert(User),
	[User#bench_users.id].

generate_batch_insert_users_args(BatchSize) ->
	[make_user_batch(BatchSize)].

generate_batch_delete_users_args(BatchSize) ->
	Users = make_user_batch(BatchSize),
	ok = ePgdb:batchInsert(Users),
	[[User#bench_users.id || User <- Users]].

generate_batch_insert_events_args(BatchSize) ->
	[[make_event(erlang:unique_integer([positive, monotonic])) || _ <- lists:seq(1, BatchSize)]].

generate_insert_event_args() ->
	[make_event(erlang:unique_integer([positive, monotonic]))].

generate_upsert_kv_existing_args() ->
	Id = erlang:unique_integer([positive, monotonic]),
	Key = <<"kv_", (integer_to_binary(Id))/binary>>,
	Base = pgdb_test_helper:new_kv(Key, #{version => 1, payload => <<"cold">>}),
	ok = ePgdb:insert(Base),
	[Base#{value => #{version => 2, payload => <<"hot">>}, version => 2, ttl => 60}].

generate_jsonb_set_user_profile_args() ->
	User = make_user(erlang:unique_integer([positive, monotonic])),
	ok = ePgdb:insert(User),
	[User#bench_users.id, [stats, atk], 999].

generate_jsonb_get_user_profile_args() ->
	Id = erlang:unique_integer([positive, monotonic]),
	User = make_user(Id, #{level => 11, stats => #{atk => 88, hp => 1200}}),
	ok = ePgdb:insert(User),
	[Id, [stats, atk]].

generate_insert_blob_args(_Label, BlobData) ->
	[make_blob(erlang:unique_integer([positive, monotonic]), BlobData)].

generate_existing_user_id_args(MaxId) ->
	[random_existing_id(MaxId)].

generate_select_user_page_args() ->
	PageCnt = max(1, ?SCAN_ROW_COUNT div ?SCAN_PAGE_SIZE),
	[rand:uniform(PageCnt), ?SCAN_PAGE_SIZE].

generate_select_user_by_json_profile_args() ->
	[rand:uniform(10)].

generate_transaction_insert_order_args() ->
	Id = erlang:unique_integer([positive, monotonic]),
	User = make_user(Id),
	Order = pgdb_test_helper:new_bench_order(Id, <<"order_", (integer_to_binary(Id))/binary>>),
	[User, Order, Id].

generate_mixed_read_write_args(MaxId) ->
	[MaxId].

prepare_users(Count) ->
	Users = [make_user_with_profile(I) || I <- lists:seq(1, Count)],
	insert_in_batches(Users).

prepare_kv(Count) ->
	Kvs = [pgdb_test_helper:new_kv(<<"kv_", (integer_to_binary(I))/binary>>, #{seed => I}) || I <- lists:seq(1, Count)],
	insert_in_batches(Kvs).

seed_compare_fixture(CompareUserId) ->
	CompareUser = pgdb_test_helper:new_bench_user(#{
		id => CompareUserId,
		name => <<"compare_user">>,
		email => <<"compare_user@tc.io">>,
		profile => #{level => 7, tier => <<"gold">>, stats => #{atk => 99, hp => 8888}}
	}),
	CompareUpdateKv = pgdb_test_helper:new_kv(<<"cmp_update">>, #{source => direct_compare, tick => 0}),
	ok = ePgdb:insert(CompareUser),
	ok = ePgdb:insert(CompareUpdateKv),
	ok.

insert_in_batches([]) ->
	ok;
insert_in_batches(Rows) ->
	{Batch, Rest} = take_batch(200, Rows),
	ok = ePgdb:batchInsert(Batch),
	insert_in_batches(Rest).

take_batch(N, Rows) when length(Rows) =< N ->
	{Rows, []};
take_batch(N, Rows) ->
	lists:split(N, Rows).

make_user(Id) ->
	make_user(Id, #{level => Id rem 10 + 1, tier => <<"gold">>}).

make_user(Id, Profile) ->
	pgdb_test_helper:new_bench_user(#{
		id => Id,
		name => <<"bench_user_", (integer_to_binary(Id))/binary>>,
		email => <<"bench_user_", (integer_to_binary(Id))/binary, "@tc.io">>,
		score => Id rem 10000,
		balance => Id rem 500,
		profile => Profile,
		tags => [<<"bench">>, <<"pgdb">>, integer_to_binary(Id rem 5)]
	}).

make_user_with_profile(Id) ->
	make_user(Id, #{level => Id rem 10 + 1, tier => <<"gold">>, stats => #{atk => Id rem 100 + 1, hp => 1000 + Id}}).

make_user_batch(BatchSize) ->
	Base = erlang:unique_integer([positive, monotonic]) * 1000,
	[make_user(Base + Offset) || Offset <- lists:seq(1, BatchSize)].

make_event(Id) ->
	(pgdb_test_helper:new_bench_event())#{
		id => Id,
		event_type => <<"login_", (integer_to_binary(Id rem 7))/binary>>,
		source => user,
		level => Id rem 5,
		actor_id => Id,
		payload => #{level => Id rem 10 + 1, scene => <<"arena">>, score => Id rem 1000},
		extra => {trace, Id, #{from => shell}},
		trace_id => make_trace_id(Id),
		client_ip => {127, 0, 0, 1}
	}.

make_blob(Id, BlobData) ->
	#bench_blobs{
		id = Id,
		name = <<"blob_", (integer_to_binary(Id))/binary>>,
		mime_type = <<"application/octet-stream">>,
		size_bytes = byte_size(BlobData),
		data = BlobData,
		checksum = checksum_hex(BlobData)
	}.

checksum_hex(Data) ->
	binary:encode_hex(erlang:md5(Data)).

make_trace_id(Id) ->
	<<"550e8400-e29b-41d4-a716-", (list_to_binary(io_lib:format("~12.16.0b", [Id rem 16#ffffffffffff])))/binary>>.

random_existing_id(MaxId) ->
	rand:uniform(MaxId).

assert_ok(ok) ->
	ok;
assert_ok(Other) ->
	error({unexpected_ok_result, Other}).

assert_rows({ok, [_ | _]}) ->
	ok;
assert_rows(Other) ->
	error({unexpected_rows_result, Other}).

assert_count({ok, Count}) when Count > 0 ->
	ok;
assert_count(Other) ->
	error({unexpected_count_result, Other}).

direct_write_report(Cnt) ->
	pgtest:with_direct_conn(fun(Conn) ->
		InsertAvgNs = avg_ns_ok(fun() -> direct_insert_kv_once(Conn) end, Cnt),
		UpdateAvgNs = avg_ns_ok(fun() -> direct_update_kv_once(Conn) end, Cnt),
		TransactionAvgNs = avg_ns_ok(fun() -> direct_transaction_kv_once(Conn) end, Cnt),
		#{
			direct_insert_kv => basic_summary(InsertAvgNs),
			direct_update_kv => basic_summary(UpdateAvgNs),
			direct_transaction_kv => basic_summary(TransactionAvgNs)
		}
							end).

direct_write_patterns_report(Cnt, RowsPerWrite) ->
	pgtest:with_direct_conn(fun(Conn) ->
		SingleAvgNs = avg_ns_ok(fun() -> direct_insert_kv_once(Conn) end, Cnt),
		BatchAvgNs = avg_ns_ok(fun() -> direct_batch_insert_kv_once(Conn, RowsPerWrite) end, Cnt),
		TxAvgNs = avg_ns_ok(fun() -> direct_transaction_multi_insert_kv_once(Conn, RowsPerWrite) end, Cnt),
		#{
			single_row_autocommit => write_pattern_summary(SingleAvgNs, 1),
			batch_insert => write_pattern_summary(BatchAvgNs, RowsPerWrite),
			tx_multi_insert => write_pattern_summary(TxAvgNs, RowsPerWrite)
		}
							end).

full_chain_read_report(Cnt, CompareUserId) ->
	QueryAvgNs = avg_ns_ok(fun() -> full_chain_query_once(CompareUserId) end, Cnt),
	GetAvgNs = avg_ns_ok(fun() -> full_chain_get_once(CompareUserId) end, Cnt),
	SelectAvgNs = avg_ns_ok(fun() -> full_chain_select_once(CompareUserId) end, Cnt),
	#{
		ePgdb_query_param => basic_summary(QueryAvgNs),
		ePgdb_get_by_id => basic_summary(GetAvgNs),
		ePgdb_select_by_id => basic_summary(SelectAvgNs)
	}.

full_chain_write_report(Cnt) ->
	InsertAvgNs = avg_ns_ok(fun() -> full_chain_insert_kv_once() end, Cnt),
	UpdateAvgNs = avg_ns_ok(fun() -> full_chain_update_kv_once() end, Cnt),
	TransactionAvgNs = avg_ns_ok(fun() -> full_chain_transaction_kv_once() end, Cnt),
	#{
		ePgdb_insert_kv => basic_summary(InsertAvgNs),
		ePgdb_update_kv => basic_summary(UpdateAvgNs),
		ePgdb_transaction_kv => basic_summary(TransactionAvgNs)
	}.

full_chain_write_patterns_report(Cnt, RowsPerWrite) ->
	SingleAvgNs = avg_ns_ok(fun() -> full_chain_insert_kv_once() end, Cnt),
	BatchAvgNs = avg_ns_ok(fun() -> full_chain_batch_insert_kv_once(RowsPerWrite) end, Cnt),
	TxAvgNs = avg_ns_ok(fun() -> full_chain_transaction_multi_insert_kv_once(RowsPerWrite) end, Cnt),
	#{
		single_row_autocommit => write_pattern_summary(SingleAvgNs, 1),
		batch_insert => write_pattern_summary(BatchAvgNs, RowsPerWrite),
		tx_multi_insert => write_pattern_summary(TxAvgNs, RowsPerWrite)
	}.

direct_insert_kv_once(Conn) ->
	Id = erlang:unique_integer([positive, monotonic]),
	Key = <<"cmp_insert_", (integer_to_binary(Id))/binary>>,
	Value = jiffy:encode(#{source => direct_db, tick => Id}),
	assert_direct_result(epgsql:equery(
		Conn,
		"insert into bench_kv(key, table_name, value, version, ttl, updated_at) values ($1, $2, $3, $4, $5, $6)",
		[Key, <<"bench_kv">>, Value, 1, 0, null]
	)).

direct_update_kv_once(Conn) ->
	Tick = erlang:unique_integer([positive, monotonic]),
	Value = jiffy:encode(#{source => direct_db, tick => Tick}),
	assert_direct_result(epgsql:equery(
		Conn,
		"update bench_kv set value = $1, version = version + 1 where key = $2",
		[Value, <<"cmp_update">>]
	)).

direct_transaction_kv_once(Conn) ->
	Id = erlang:unique_integer([positive, monotonic]),
	Key = <<"cmp_tx_", (integer_to_binary(Id))/binary>>,
	Value = jiffy:encode(#{source => direct_tx, tick => Id}),
	case epgsql:with_transaction(Conn, fun(TxConn) ->
		assert_direct_result(epgsql:equery(
			TxConn,
			"insert into bench_kv(key, table_name, value, version, ttl, updated_at) values ($1, $2, $3, $4, $5, $6)",
			[Key, <<"bench_kv">>, Value, 1, 0, null]
		)),
		assert_direct_result(epgsql:equery(
			TxConn,
			"update bench_kv set value = $1, version = version + 1 where key = $2",
			[Value, <<"cmp_update">>]
		)),
		ok
									   end) of
		ok -> ok;
		Other -> error({unexpected_direct_transaction_result, Other})
	end.

direct_batch_insert_kv_once(Conn, RowsPerWrite) ->
	Rows = [make_direct_kv_params(<<"cmp_batch_">>, direct_batch, Id) || Id <- unique_ids(RowsPerWrite)],
	{SQL, Params} = build_direct_batch_insert_sql(Rows),
	assert_direct_result(epgsql:equery(Conn, SQL, Params)).

direct_transaction_multi_insert_kv_once(Conn, RowsPerWrite) ->
	Ids = unique_ids(RowsPerWrite),
	case epgsql:with_transaction(Conn, fun(TxConn) ->
		lists:foreach(fun(Id) ->
			assert_direct_result(epgsql:equery(
				TxConn,
				"insert into bench_kv(key, table_name, value, version, ttl, updated_at) values ($1, $2, $3, $4, $5, $6)",
				make_direct_kv_params(<<"cmp_txm_">>, direct_tx_multi, Id)
			))
					  end, Ids),
		ok
									   end) of
		ok -> ok;
		Other -> error({unexpected_direct_transaction_multi_result, Other})
	end.

full_chain_query_once(CompareUserId) ->
	case ePgdb:query("select * from bench_users where id = $1", [CompareUserId]) of
		{ok, _Cols, [_Row]} -> ok;
		{ok, _Count, _Cols, [_Row]} -> ok;
		Other -> error({unexpected_full_chain_query_result, Other})
	end.

full_chain_get_once(CompareUserId) ->
	assert_rows(ePgdb:get(bench_users, #{id => CompareUserId})).

full_chain_select_once(CompareUserId) ->
	assert_rows(ePgdb:select(bench_users, #{id => CompareUserId}, [{fields, [id, name, score]}])).

full_chain_insert_kv_once() ->
	Id = erlang:unique_integer([positive, monotonic]),
	Key = <<"cmp_insert_", (integer_to_binary(Id))/binary>>,
	assert_ok(ePgdb:insert(pgdb_test_helper:new_kv(Key, #{source => ePgdb_full_path, tick => Id}))).

full_chain_batch_insert_kv_once(RowsPerWrite) ->
	Rows = [
		pgdb_test_helper:new_kv(
			<<"cmp_batch_", (integer_to_binary(Id))/binary>>,
			#{source => ePgdb_full_path_batch, tick => Id}
		)
		|| Id <- unique_ids(RowsPerWrite)
	],
	assert_ok(ePgdb:batchInsert(Rows)).

full_chain_update_kv_once() ->
	Tick = erlang:unique_integer([positive, monotonic]),
	assert_count(ePgdb:update(#{
		table_name => <<"bench_kv">>,
		value => #{source => ePgdb_full_path, tick => Tick}
	}, [value], #{key => <<"cmp_update">>})).

full_chain_transaction_kv_once() ->
	Id = erlang:unique_integer([positive, monotonic]),
	Key = <<"cmp_tx_", (integer_to_binary(Id))/binary>>,
	case ePgdb:transaction(fun(Conn) ->
		ok = ePgdb:insertC(Conn, pgdb_test_helper:new_kv(Key, #{source => ePgdb_full_path_tx, tick => Id})),
		{ok, 1} = ePgdb:update(Conn, #{
			table_name => <<"bench_kv">>,
			value => #{source => ePgdb_full_path_tx, tick => Id}
		}, [value], #{key => <<"cmp_update">>}),
		ok
						   end) of
		{ok, ok} -> ok;
		Other -> error({unexpected_full_chain_transaction_result, Other})
	end.

full_chain_transaction_multi_insert_kv_once(RowsPerWrite) ->
	Ids = unique_ids(RowsPerWrite),
	case ePgdb:transaction(fun(Conn) ->
		lists:foreach(fun(Id) ->
			ok = ePgdb:insertC(
				Conn,
				pgdb_test_helper:new_kv(
					<<"cmp_txm_", (integer_to_binary(Id))/binary>>,
					#{source => ePgdb_full_path_tx_multi, tick => Id}
				)
			)
					  end, Ids),
		ok
						   end) of
		{ok, ok} -> ok;
		Other -> error({unexpected_full_chain_transaction_multi_result, Other})
	end.

basic_summary(ClientAvgNs) ->
	#{
		client_avg_ns => ClientAvgNs,
		client_qps => round(1000000000 / ClientAvgNs)
	}.

write_pattern_summary(ClientAvgNs, RowsPerWrite) ->
	OpsQps = round(1000000000 / ClientAvgNs),
	#{
		client_avg_ns => ClientAvgNs,
		client_qps => OpsQps,
		rows_per_write => RowsPerWrite,
		row_qps => OpsQps * RowsPerWrite
	}.

avg_ns_ok(Fun, Cnt) ->
	WarmupCnt = erlang:min(Cnt, 20),
	[assert_ok_result(Fun()) || _ <- lists:seq(1, WarmupCnt)],
	Start = erlang:monotonic_time(nanosecond),
	[assert_ok_result(Fun()) || _ <- lists:seq(1, Cnt)],
	Elapsed = erlang:monotonic_time(nanosecond) - Start,
	Elapsed div Cnt.

print_direct_compare_section(DirectRead, DirectWrite) ->
	io:format("[DIRECT DB | 裸数据库直连]~n", []),
	print_summary_item("simple query (squery)", maps:get(simple_query, DirectRead)),
	print_summary_item("parameterized query (equery)", maps:get(parameterized_query, DirectRead)),
	print_summary_item("insert bench_kv", maps:get(direct_insert_kv, DirectWrite)),
	print_summary_item("update bench_kv", maps:get(direct_update_kv, DirectWrite)),
	print_summary_item("transaction bench_kv", maps:get(direct_transaction_kv, DirectWrite)),
	io:format("~n", []).

print_full_path_compare_section(FullRead, FullWrite) ->
	io:format("[EPGDB FULL PATH | schema + queue + worker + codec]~n", []),
	print_summary_item("ePgdb query(SQL with params)", maps:get(ePgdb_query_param, FullRead)),
	print_summary_item("ePgdb get(by primary key)", maps:get(ePgdb_get_by_id, FullRead)),
	print_summary_item("ePgdb select(fields)", maps:get(ePgdb_select_by_id, FullRead)),
	print_summary_item("ePgdb insert bench_kv", maps:get(ePgdb_insert_kv, FullWrite)),
	print_summary_item("ePgdb update bench_kv", maps:get(ePgdb_update_kv, FullWrite)),
	print_summary_item("ePgdb transaction bench_kv", maps:get(ePgdb_transaction_kv, FullWrite)),
	io:format("~n", []).

print_compare_delta_section(DirectRead, DirectWrite, FullRead, FullWrite) ->
	io:format("[DELTA | 全链路相对裸数据库放大倍数]~n", []),
	print_delta_item("query with params", maps:get(parameterized_query, DirectRead), maps:get(ePgdb_query_param, FullRead)),
	print_delta_item("get by primary key", maps:get(parameterized_query, DirectRead), maps:get(ePgdb_get_by_id, FullRead)),
	print_delta_item("select by primary key", maps:get(parameterized_query, DirectRead), maps:get(ePgdb_select_by_id, FullRead)),
	print_delta_item("insert bench_kv", maps:get(direct_insert_kv, DirectWrite), maps:get(ePgdb_insert_kv, FullWrite)),
	print_delta_item("update bench_kv", maps:get(direct_update_kv, DirectWrite), maps:get(ePgdb_update_kv, FullWrite)),
	print_delta_item("transaction bench_kv", maps:get(direct_transaction_kv, DirectWrite), maps:get(ePgdb_transaction_kv, FullWrite)),
	io:format("========================================~n", []).

print_write_patterns_section(Title, SummaryMap) ->
	io:format("[~ts]~n", [Title]),
	print_write_pattern_item("single row autocommit", maps:get(single_row_autocommit, SummaryMap)),
	print_write_pattern_item("batch insert", maps:get(batch_insert, SummaryMap)),
	print_write_pattern_item("single tx multi insert", maps:get(tx_multi_insert, SummaryMap)),
	io:format("~n", []).

print_write_pattern_gain_section(Title, SummaryMap) ->
	Single = maps:get(single_row_autocommit, SummaryMap),
	Batch = maps:get(batch_insert, SummaryMap),
	TxMulti = maps:get(tx_multi_insert, SummaryMap),
	io:format("[~ts]~n", [Title]),
	print_write_gain_item("batch insert vs single", Single, Batch),
	print_write_gain_item("single tx multi vs single", Single, TxMulti),
	io:format("~n", []).

print_write_pattern_delta_section(Direct, Full) ->
	io:format("[WRITE PATTERN DELTA | ePgdb 相对裸数据库]~n", []),
	print_delta_item("single row autocommit", maps:get(single_row_autocommit, Direct), maps:get(single_row_autocommit, Full)),
	print_delta_item("batch insert", maps:get(batch_insert, Direct), maps:get(batch_insert, Full)),
	print_delta_item("single tx multi insert", maps:get(tx_multi_insert, Direct), maps:get(tx_multi_insert, Full)),
	io:format("========================================~n", []).

print_summary_item(Label, Summary) ->
	io:format("  ~-32ts avg_ns=~14B qps=~10B", [Label, maps:get(client_avg_ns, Summary), maps:get(client_qps, Summary)]),
	case maps:get(server_total_ns, Summary, undefined) of
		undefined ->
			io:format("~n", []);
		ServerNs ->
			io:format(" server_ns=~14B server_qps=~10B~n", [ServerNs, maps:get(server_qps, Summary)])
	end.

print_delta_item(Label, DirectSummary, FullSummary) ->
	DirectAvg = maps:get(client_avg_ns, DirectSummary),
	FullAvg = maps:get(client_avg_ns, FullSummary),
	Ratio = FullAvg / DirectAvg,
	QpsDelta = maps:get(client_qps, DirectSummary) - maps:get(client_qps, FullSummary),
	io:format("  ~-32ts slowdown=~8.2fx direct_qps=~10B full_qps=~10B qps_gap=~10B~n", [
		Label,
		Ratio,
		maps:get(client_qps, DirectSummary),
		maps:get(client_qps, FullSummary),
		QpsDelta
	]).

print_write_pattern_item(Label, Summary) ->
	io:format(
		"  ~-32ts avg_ns=~14B op_qps=~10B rows/op=~6B row_qps=~12B~n",
		[
			Label,
			maps:get(client_avg_ns, Summary),
			maps:get(client_qps, Summary),
			maps:get(rows_per_write, Summary),
			maps:get(row_qps, Summary)
		]
	).

print_write_gain_item(Label, BaseSummary, BetterSummary) ->
	BaseRowQps = maps:get(row_qps, BaseSummary),
	BetterRowQps = maps:get(row_qps, BetterSummary),
	Gain = BetterRowQps / BaseRowQps,
	LatencyRatio = maps:get(client_avg_ns, BetterSummary) / maps:get(client_avg_ns, BaseSummary),
	io:format(
		"  ~-32ts row_gain=~8.2fx base_row_qps=~12B target_row_qps=~12B avg_ns_ratio=~8.2fx~n",
		[Label, Gain, BaseRowQps, BetterRowQps, LatencyRatio]
	).

unique_ids(Count) ->
	[erlang:unique_integer([positive, monotonic]) || _ <- lists:seq(1, Count)].

make_direct_kv_params(Prefix, Source, Id) ->
	[
		<<Prefix/binary, (integer_to_binary(Id))/binary>>,
		<<"bench_kv">>,
		jiffy:encode(#{source => Source, tick => Id}),
		1,
		0,
		null
	].

build_direct_batch_insert_sql(Rows) ->
	PlaceholderGroups = build_placeholder_groups(length(Rows), 6),
	SQL = [
		"insert into bench_kv(key, table_name, value, version, ttl, updated_at) values ",
		string:join(PlaceholderGroups, ",")
	],
	{SQL, lists:append(Rows)}.

build_placeholder_groups(RowCnt, ColCnt) ->
	[
		[$(, string:join([[$$, integer_to_list(I)] || I <- lists:seq((RowIdx - 1) * ColCnt + 1, RowIdx * ColCnt)], ","), $)]
		|| RowIdx <- lists:seq(1, RowCnt)
	].

assert_direct_result({ok, 1}) ->
	ok;
assert_direct_result({ok, Count}) when is_integer(Count), Count > 0 ->
	ok;
assert_direct_result({ok, _, _}) ->
	ok;
assert_direct_result({ok, _, _, _}) ->
	ok;
assert_direct_result(Other) ->
	error({unexpected_direct_result, Other}).

assert_ok_result(ok) ->
	ok;
assert_ok_result(Other) ->
	error({unexpected_benchmark_result, Other}).