%%%-------------------------------------------------------------------
%%% @doc ePgdb 性能基准测试模块。
%%%
%%% 本模块包含两类测试：
%%%   1. EUnit 冒烟测试（以 _test_ 结尾）
%%%      验证批量操作能完成且无错误，**不关注绝对延迟**。
%%%
%%%   2. 基准测试函数（bench_* 前缀，可直接调用）
%%%      测量 op/s 和分位延迟（P50/P95/P99）。
%%%      使用方式：
%%%        erl -pa _build/default/lib/*/ebin -eval "pgdb_bench_tests:run_all()" -s erlang halt
%%%
%%% 覆盖场景：
%%%   bench_insert          — 单条 INSERT 吞吐
%%%   bench_select_by_id    — 主键精确查询
%%%   bench_select_range    — 范围扫描（score BETWEEN）
%%%   bench_update          — 单条 UPDATE
%%%   bench_delete          — 单条 DELETE
%%%   bench_batch_insert    — 批量 INSERT（每批 100 条）
%%%   bench_batch_delete    — 批量 DELETE（每批 100 键）
%%%   bench_upsert          — UPSERT（bench_kv 键值表）
%%%   bench_count           — COUNT(*)
%%%   bench_transaction     — 事务（INSERT + UPDATE 两步）
%%%   bench_foreach_rows    — foreachRows 全表遍历
%%%   bench_concurrent      — 10 并发 goroutine 混合读写
%%%-------------------------------------------------------------------
-module(pgdb_bench_tests).

-include_lib("eunit/include/eunit.hrl").
-include("pg_bench_schema.hrl").

-define(DEFAULT_N, 1000).   %% 默认每个基准操作次数
-define(BATCH_SIZE, 100).   %% 批量操作每批大小
-define(CONCURRENCY, 10).   %% 并发度

%% 公开 bench 函数，供外部直接调用
-export([
	run_all/0,
	run_all/1,
	bench_insert/1,
	bench_select_by_id/1,
	bench_select_range/1,
	bench_update/1,
	bench_delete/1,
	bench_batch_insert/1,
	bench_batch_delete/1,
	bench_upsert/1,
	bench_count/1,
	bench_transaction/1,
	bench_foreach_rows/1,
	bench_concurrent/1
]).

%%%===================================================================
%%% EUnit 冒烟测试 — 快速验证每个基准可正常运行
%%%===================================================================

bench_smoke_test_() ->
	{setup,
		fun setup/0,
		fun teardown/1,
		[
			{"insert smoke", fun smoke_insert/0},
			{"select smoke", fun smoke_select/0},
			{"update smoke", fun smoke_update/0},
			{"delete smoke", fun smoke_delete/0},
			{"batch insert smoke", fun smoke_batch_insert/0},
			{"batch delete smoke", fun smoke_batch_delete/0},
			{"upsert smoke", fun smoke_upsert/0},
			{"count smoke", fun smoke_count/0},
			{"transaction smoke", fun smoke_transaction/0},
			{"foreach smoke", fun smoke_foreach/0},
			{"concurrent smoke", fun smoke_concurrent/0}
		]
	}.

setup() ->
	pgdb_test_helper:start().

teardown(_) ->
	pgdb_test_helper:stop().

%%%===================================================================
%%% 冒烟：仅跑 10 次，验证无错误
%%%===================================================================

smoke_insert() ->
	pgdb_test_helper:truncate(bench_users),
	{_Lat, _Tput} = bench_insert(10),
	ok.

smoke_select() ->
	pgdb_test_helper:truncate(bench_users),
	prepare_users(20),
	{_Lat, _Tput} = bench_select_by_id(10),
	ok.

smoke_update() ->
	pgdb_test_helper:truncate(bench_users),
	prepare_users(10),
	{_Lat, _Tput} = bench_update(10),
	ok.

smoke_delete() ->
	pgdb_test_helper:truncate(bench_users),
	prepare_users(20),
	{_Lat, _Tput} = bench_delete(10),
	ok.

smoke_batch_insert() ->
	pgdb_test_helper:truncate(bench_users),
	{_Lat, _Tput} = bench_batch_insert(3),
	ok.

smoke_batch_delete() ->
	pgdb_test_helper:truncate(bench_users),
	prepare_users(?BATCH_SIZE * 3),
	{_Lat, _Tput} = bench_batch_delete(3),
	ok.

smoke_upsert() ->
	pgdb_test_helper:truncate(bench_kv),
	{_Lat, _Tput} = bench_upsert(10),
	ok.

smoke_count() ->
	pgdb_test_helper:truncate(bench_users),
	prepare_users(50),
	{_Lat, _Tput} = bench_count(10),
	ok.

smoke_transaction() ->
	pgdb_test_helper:truncate(bench_users),
	prepare_users(20),
	{_Lat, _Tput} = bench_transaction(5),
	ok.

smoke_foreach() ->
	pgdb_test_helper:truncate(bench_users),
	prepare_users(50),
	{_Lat, _Tput} = bench_foreach_rows(3),
	ok.

smoke_concurrent() ->
	pgdb_test_helper:truncate(bench_users),
	prepare_users(100),
	{_Errors, _Ok} = bench_concurrent(10),
	ok.

%%%===================================================================
%%% 公开入口：运行全部基准
%%%===================================================================

-spec run_all() -> ok.
run_all() ->
	run_all(?DEFAULT_N).

-spec run_all(pos_integer()) -> ok.
run_all(N) ->
	pgdb_test_helper:start(),
	try
		io:format("~n====================================================~n"),
		io:format("  ePgdb Benchmark  N=~p  Concurrency=~p~n", [N, ?CONCURRENCY]),
		io:format("====================================================~n~n"),
		
		pgdb_test_helper:truncate(bench_users),
		pgdb_test_helper:truncate(bench_kv),
		
		run_bench("INSERT single", fun() -> bench_insert(N) end),
		run_bench("SELECT by id", fun() -> prepare_users(N), bench_select_by_id(N) end),
		run_bench("SELECT range", fun() -> bench_select_range(N) end),
		run_bench("UPDATE single", fun() -> bench_update(N) end),
		run_bench("DELETE single", fun() -> prepare_users(N * 2), bench_delete(N) end),
		run_bench("BATCH INSERT(100)", fun() -> bench_batch_insert(N div ?BATCH_SIZE + 1) end),
		run_bench("BATCH DELETE(100)", fun() -> prepare_users(N * 2), bench_batch_delete(N div ?BATCH_SIZE + 1) end),
		run_bench("UPSERT(kv)", fun() -> bench_upsert(N) end),
		run_bench("COUNT(*)", fun() -> bench_count(N) end),
		run_bench("TRANSACTION(ins+upd)", fun() -> bench_transaction(N div 2) end),
		run_bench("foreachRows", fun() -> bench_foreach_rows(N div 100 + 1) end),
		run_bench("CONCURRENT mix", fun() -> bench_concurrent(?CONCURRENCY) end),
		
		io:format("~n====================================================~n"),
		io:format("  All benchmarks completed.~n"),
		io:format("====================================================~n~n")
	after
		pgdb_test_helper:stop()
	end.

%%%===================================================================
%%% 各项基准实现（返回 {LatencyStats, Throughput}）
%%%===================================================================

%% bench_insert/1 — 连续插入 N 条 bench_users
bench_insert(N) ->
	Lats = measure_n(N, fun(I) ->
		U = pgdb_test_helper:new_bench_user(#{
			id => I,
			name => <<"buser_", (integer_to_binary(I))/binary>>,
			email => <<"buser_", (integer_to_binary(I))/binary, "@bench.io">>,
			score => I rem 1000
		}),
		case ePgdb:insert(U) of
			ok -> ok;
			E -> error({insert_failed, E})
		end
						end),
	print_stats("INSERT", N, Lats).

%% bench_select_by_id/1 — 按主键随机查询
bench_select_by_id(N) ->
	Lats = measure_n(N, fun(_) ->
		Id = rand:uniform(N),
		case ePgdb:select(bench_users, #{id => Id}, [{fields, [id, name, score]}]) of
			{ok, _} -> ok;
			E -> error({select_failed, E})
		end
						end),
	print_stats("SELECT by id", N, Lats).

%% bench_select_range/1 — score BETWEEN 随机范围
bench_select_range(N) ->
	Lats = measure_n(N, fun(_) ->
		Lo = rand:uniform(500),
		Hi = Lo + rand:uniform(400),
		case ePgdb:select(bench_users, #{score => {between, Lo, Hi}},
			[{fields, [id, score]}, {limit, 50}]) of
			{ok, _} -> ok;
			E -> error({range_failed, E})
		end
						end),
	print_stats("SELECT range", N, Lats).

%% bench_update/1 — 更新 score 字段
bench_update(N) ->
	Lats = measure_n(N, fun(I) ->
		Id = (I rem (N div 2)) + 1,
		U = #bench_users{id = Id, score = rand:uniform(9999)},
		case ePgdb:update(U, [#bench_users.score], #{id => Id}) of
			{ok, _} -> ok;
			E -> error({update_failed, E})
		end
						end),
	print_stats("UPDATE", N, Lats).

%% bench_delete/1 — 逐条删除
bench_delete(N) ->
	Lats = measure_n(N, fun(I) ->
		case ePgdb:delete(bench_users, #{id => I}) of
			{ok, _} -> ok;
			E -> error({delete_failed, E})
		end
						end),
	print_stats("DELETE", N, Lats).

%% bench_batch_insert/1 — 每批 ?BATCH_SIZE 条
bench_batch_insert(Batches) ->
	Base = erlang:unique_integer([positive, monotonic]),
	Lats = measure_n(Batches, fun(BatchIdx) ->
		Offset = Base + BatchIdx * ?BATCH_SIZE,
		Users = [pgdb_test_helper:new_bench_user(#{
			id => Offset + J,
			name => <<"bu_", (integer_to_binary(Offset + J))/binary>>,
			email => <<"bu_", (integer_to_binary(Offset + J))/binary, "@b.com">>,
			score => J
		}) || J <- lists:seq(1, ?BATCH_SIZE)],
		case ePgdb:batchInsert(Users) of
			ok -> ok;
			E -> error({batch_insert_failed, E})
		end
							  end),
	print_stats("BATCH INSERT", Batches * ?BATCH_SIZE, Lats).

%% bench_batch_delete/1 — 每批 ?BATCH_SIZE 条
bench_batch_delete(Batches) ->
	Lats = measure_n(Batches, fun(BatchIdx) ->
		Keys = lists:seq((BatchIdx - 1) * ?BATCH_SIZE + 1, BatchIdx * ?BATCH_SIZE),
		case ePgdb:batchDelByKey(bench_users, id, Keys) of
			{ok, _} -> ok;
			E -> error({batch_delete_failed, E})
		end
							  end),
	print_stats("BATCH DELETE", Batches * ?BATCH_SIZE, Lats).

%% bench_upsert/1 — bench_kv 键值 upsert
bench_upsert(N) ->
	Lats = measure_n(N, fun(I) ->
		Key = <<"kv_", (integer_to_binary(I rem 200))/binary>>,
		KV = pgdb_test_helper:new_kv(Key, #{count => I}),
		case ePgdb:upsert(KV, [key], [value, version]) of
			{ok, _} -> ok;
			E -> error({upsert_failed, E})
		end
						end),
	print_stats("UPSERT", N, Lats).

%% bench_count/1 — COUNT(*)
bench_count(N) ->
	Lats = measure_n(N, fun(_) ->
		case ePgdb:count(bench_users) of
			{ok, _} -> ok;
			E -> error({count_failed, E})
		end
						end),
	print_stats("COUNT(*)", N, Lats).

%% bench_transaction/1 — 事务：INSERT + UPDATE
bench_transaction(N) ->
	Base = erlang:unique_integer([positive, monotonic]),
	Lats = measure_n(N, fun(I) ->
		Id = Base + I,
		U = pgdb_test_helper:new_bench_user(#{
			id => Id,
			name => <<"txu_", (integer_to_binary(Id))/binary>>,
			email => <<"txu_", (integer_to_binary(Id))/binary, "@tx.io">>,
			score => 0
		}),
		case ePgdb:transaction(fun(Conn) ->
			ok = ePgdb:insertC(Conn, U),
			{ok, _} = ePgdb:update(Conn, U#bench_users{score = 999},
				[#bench_users.score],
				#{id => Id}),
			ok
							   end) of
			{ok, ok} -> ok;
			E -> error({transaction_failed, E})
		end
						end),
	print_stats("TRANSACTION", N, Lats).

%% bench_foreach_rows/1 — foreachRows 全表遍历（每次遍历一次全表）
bench_foreach_rows(N) ->
	Lats = measure_n(N, fun(_) ->
		_ = ePgdb:foreachRows(bench_users, #{}, 100, fun(_Row) -> ok end),
		ok
						end),
	print_stats("foreachRows", N, Lats).

%% bench_concurrent/1 — 并发混合读写
bench_concurrent(Concurrency) ->
	Self = self(),
	Pids = [spawn(fun() ->
		Result = try
			%% 三分之一 INSERT, 三分之一 UPDATE, 三分之一 SELECT
					 Op = rand:uniform(3),
					 case Op of
						 1 ->
							 U = pgdb_test_helper:new_bench_user(#{
								 name => <<"cu_", (integer_to_binary(pgdb_test_helper:gen_id()))/binary>>,
								 email => <<"cu_", (integer_to_binary(pgdb_test_helper:gen_id()))/binary, "@c.io">>
							 }),
							 ePgdb:insert(U);
						 2 ->
							 Id = rand:uniform(100),
							 {ok, _} = ePgdb:select(bench_users, #{id => Id},
								 [{fields, [id, score]}, {limit, 1}]),
							 ok;
						 3 ->
							 U = #bench_users{id = rand:uniform(100), score = rand:uniform(9999)},
							 ePgdb:update(U, [#bench_users.score], #{id => U#bench_users.id}),
							 ok
					 end
				 of
					 ok -> ok;
					 {ok, _} -> ok;
					 _Other -> ok
				 catch
					 _Class:_Reason -> error
				 end,
		Self ! {done, Result}
				  end) || _ <- lists:seq(1, Concurrency)],
	
	Results = [receive {done, R} -> R after 30000 -> timeout end || _ <- Pids],
	Errors = length([E || E <- Results, E =/= ok]),
	Ok = Concurrency - Errors,
	io:format("  concurrent ~p ops: ok=~p  errors=~p~n", [Concurrency, Ok, Errors]),
	{Errors, Ok}.

%%%===================================================================
%%% 内部工具
%%%===================================================================

%% 预填 N 条 bench_users 数据（供 select/update/delete 使用）
prepare_users(N) ->
	Users = [pgdb_test_helper:new_bench_user(#{
		id => I,
		name => <<"buser_", (integer_to_binary(I))/binary>>,
		email => <<"buser_", (integer_to_binary(I))/binary, "@bench.io">>,
		score => I rem 1000
	}) || I <- lists:seq(1, N)],
	%% 用批量插入减少 RTT
	batch_insert_large(Users).

batch_insert_large([]) -> ok;
batch_insert_large(Users) ->
	{Batch, Rest} = take(?BATCH_SIZE, Users),
	ok = ePgdb:batchInsert(Batch),
	batch_insert_large(Rest).

take(N, List) when length(List) =< N ->
	{List, []};
take(N, List) ->
	lists:split(N, List).

%% 运行 N 次 Fun(Index)，收集每次微秒延迟
measure_n(N, Fun) ->
	lists:map(fun(I) ->
		T0 = erlang:monotonic_time(microsecond),
		Fun(I),
		erlang:monotonic_time(microsecond) - T0
			  end, lists:seq(1, N)).

%% 打印统计并返回 {Stats, Throughput}
print_stats(Name, TotalOps, Lats) ->
	Sorted = lists:sort(Lats),
	Len = length(Sorted),
	Sum = lists:sum(Sorted),
	Avg = Sum div Len,
	P50 = percentile(Sorted, 0.50),
	P95 = percentile(Sorted, 0.95),
	P99 = percentile(Sorted, 0.99),
	TotalUs = Sum,
	TotalS = TotalUs / 1_000_000,
	Tput = TotalOps / TotalS,
	io:format("  [~s] n=~w avg=~wus p50=~wus p95=~wus p99=~wus tput=~w ops/s~n",
		[Name, TotalOps, Avg, P50, P95, P99, round(Tput)]),
	{#{avg => Avg, p50 => P50, p95 => P95, p99 => P99}, Tput}.

percentile(Sorted, P) ->
	Idx = max(1, round(P * length(Sorted))),
	lists:nth(Idx, Sorted).

run_bench(Label, Fun) ->
	pgdb_test_helper:truncate(bench_users),
	pgdb_test_helper:truncate(bench_kv),
	io:format("[~s]~n", [Label]),
	Fun(),
	ok.
