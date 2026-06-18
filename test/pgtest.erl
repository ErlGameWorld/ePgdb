-module(pgtest).
-include("ePgdb.hrl").
-compile([export_all, nowarn_export_all]).

-define(NS_PER_SEC, 1000000000).

query() ->
	Sql = "select * from bench_users where id = 1",
	ePgdb:query(Sql).

test(Cnt) ->

	Sql = "select * from bench_users where id = 1",
	utTc:tc(Cnt, ePgdb, query, [Sql]),
	utTc:tc(Cnt, ePgdb, get, [bench_users, #{id => 1}]),
	utTc:tc(Cnt, ePgdb, select, [bench_users, #{id => 1}, [{fields, [id]}]]),
	utTc:tc(Cnt, ePgdb, selectSql, [bench_users, #{id => 1}, [{fields, [id]}]]).


test_proto(Cnt) ->
	WholeSql = "select * from bench_users where id = 1",
	WholeParamSql = "select * from bench_users where id = $1",
	IdParamSql = "select id from bench_users where id = $1",
	utTc:tc(Cnt, ePgdb, query, [WholeSql]),
	utTc:tc(Cnt, ePgdb, query, [WholeParamSql, [1]]),
	utTc:tc(Cnt, ePgdb, query, [IdParamSql, [1]]),
	utTc:tc(Cnt, ePgdb, select, [bench_users, #{id => 1}, [{fields, [id]}]]),
	utTc:tc(Cnt, ePgdb, get, [bench_users, #{id => 1}]).


test_path(Cnt) ->
	utTc:tc(Cnt, pgtest, query_whole_param, []),
	utTc:tc(Cnt, pgtest, query_decode_whole, []),
	utTc:tc(Cnt, ePgdb, get, [bench_users, #{id => 1}]),
	utTc:tc(Cnt, pgtest, query_id_param, []),
	utTc:tc(Cnt, pgtest, query_decode_id, []),
	utTc:tc(Cnt, ePgdb, select, [bench_users, #{id => 1}, [{fields, [id]}]]).


test_decode(Cnt) ->
	{ok, WholeCols, [WholeRow]} = ePgdb:query("select * from bench_users where id = $1", [1]),
	{ok, IdCols, [IdRow]} = ePgdb:query("select id from bench_users where id = $1", [1]),
	utTc:tc(Cnt, ePgdb, rowToWholeData, [bench_users, WholeRow]),
	utTc:tc(Cnt, ePgdb, decodeFields, [bench_users, IdCols]),
	utTc:tc(Cnt, ePgdb, rowToMap, [bench_users, IdCols, IdRow]),
	{WholeCols, IdCols}.


test_row_helpers(Cnt) ->
	{ok, WholeCols, [WholeRow]} = ePgdb:query("select * from bench_users where id = $1", [1]),
	{ok, IdCols, [IdRow]} = ePgdb:query("select id, profile from bench_users where id = $1", [1]),
	utTc:tc(Cnt, ePgdb, rowToWholeData, [bench_users, WholeRow]),
	utTc:tc(Cnt, ePgdb, rowToMap, [bench_users, IdCols, IdRow]),
	{WholeCols, IdCols}.


%% 并发压测 ePgdb 接口吞吐时调用 test2/2、test_proto2/2、test_path2/2。
%% ProCnt 为并发进程数，Cnt 为每个进程执行次数。
test2(ProCnt, Cnt) ->
	Sql = "select * from bench_users where id = 1",

	utTc:tc(ProCnt, Cnt, ePgdb, query, [Sql]),
	utTc:tc(ProCnt, Cnt, ePgdb, get, [bench_users, #{id => 1}]),
	utTc:tc(ProCnt, Cnt, ePgdb, select, [bench_users, #{id => 1}, [{fields, [id]}]]),
	utTc:tc(ProCnt, Cnt, ePgdb, selectSql, [bench_users, #{id => 1}, [{fields, [id]}]]).


test_proto2(ProCnt, Cnt) ->
	WholeSql = "select * from bench_users where id = 1",
	WholeParamSql = "select * from bench_users where id = $1",
	IdParamSql = "select id from bench_users where id = $1",
	utTc:tc(ProCnt, Cnt, ePgdb, query, [WholeSql]),
	utTc:tc(ProCnt, Cnt, ePgdb, query, [WholeParamSql, [1]]),
	utTc:tc(ProCnt, Cnt, ePgdb, query, [IdParamSql, [1]]),
	utTc:tc(ProCnt, Cnt, ePgdb, select, [bench_users, #{id => 1}, [{fields, [id]}]]),
	utTc:tc(ProCnt, Cnt, ePgdb, get, [bench_users, #{id => 1}]).


test_path2(ProCnt, Cnt) ->
	utTc:tc(ProCnt, Cnt, pgtest, query_whole_param, []),
	utTc:tc(ProCnt, Cnt, pgtest, query_decode_whole, []),
	utTc:tc(ProCnt, Cnt, ePgdb, get, [bench_users, #{id => 1}]),
	utTc:tc(ProCnt, Cnt, pgtest, query_id_param, []),
	utTc:tc(ProCnt, Cnt, pgtest, query_decode_id, []),
	utTc:tc(ProCnt, Cnt, ePgdb, select, [bench_users, #{id => 1}, [{fields, [id]}]]).


test_decode2(ProCnt, Cnt) ->
	{ok, _WholeCols, [WholeRow]} = ePgdb:query("select * from bench_users where id = $1", [1]),
	{ok, IdCols, [IdRow]} = ePgdb:query("select id from bench_users where id = $1", [1]),
	utTc:tc(ProCnt, Cnt, ePgdb, rowToWholeData, [bench_users, WholeRow]),
	utTc:tc(ProCnt, Cnt, ePgdb, decodeFields, [bench_users, IdCols]),
	utTc:tc(ProCnt, Cnt, ePgdb, rowToMap, [bench_users, IdCols, IdRow]).


test_row_helpers2(ProCnt, Cnt) ->
	{ok, _WholeCols, [WholeRow]} = ePgdb:query("select * from bench_users where id = $1", [1]),
	{ok, IdCols, [IdRow]} = ePgdb:query("select id, profile from bench_users where id = $1", [1]),
	utTc:tc(ProCnt, Cnt, ePgdb, rowToWholeData, [bench_users, WholeRow]),
	utTc:tc(ProCnt, Cnt, ePgdb, rowToMap, [bench_users, IdCols, IdRow]).


query_whole_param() ->
	ePgdb:query("select * from bench_users where id = $1", [1]).


query_id_param() ->
	ePgdb:query("select id from bench_users where id = $1", [1]).


query_decode_whole() ->
	{ok, _Cols, [Row]} = query_whole_param(),
	ePgdb:rowToWholeData(bench_users, Row).


query_decode_id() ->
	{ok, Cols, [Row]} = query_id_param(),
	ePgdb:rowToMap(bench_users, Cols, Row).


%% 查看直连 PostgreSQL 的单连接 QPS 报告时调用 print_qps_report/1。
%% qps_report/1 仅返回结果 map，不打印；Cnt 为采样次数。
qps_report(Cnt) when is_integer(Cnt), Cnt > 0 ->
	WholeSql = "select * from bench_users where id = 1",
	ParamSql = "select * from bench_users where id = $1",
	with_direct_conn(fun(Conn) ->
		SimpleAvgNs = avg_ns(fun() -> epgsql:squery(Conn, WholeSql) end, Cnt),
		ParamAvgNs = avg_ns(fun() -> epgsql:equery(Conn, ParamSql, [1]) end, Cnt),
		SimpleServerNs = explain_total_ns(Conn, WholeSql),
		ParamServerNs = explain_total_ns(Conn, ParamSql, [1]),
		#{
			simple_query => qps_summary(SimpleAvgNs, SimpleServerNs),
			parameterized_query => qps_summary(ParamAvgNs, ParamServerNs)
		}
	end).


print_qps_report(Cnt) when is_integer(Cnt), Cnt > 0 ->
	Report = qps_report(Cnt),
	print_report_item(simple_query, maps:get(simple_query, Report)),
	print_report_item(parameterized_query, maps:get(parameterized_query, Report)),
	Report.


with_direct_conn(Fun) ->
	ConnOpts = #{
		host => pgdb_test_helper:db_host(),
		port => pgdb_test_helper:db_port(),
		database => pgdb_test_helper:db_name(),
		username => pgdb_test_helper:db_user(),
		password => pgdb_test_helper:db_pass(),
		timeout => 5000
	},
	{ok, Conn} = epgsql:connect(ConnOpts),
	try
		Fun(Conn)
	after
		epgsql:close(Conn)
	end.


avg_ns(Fun, Cnt) ->
	WarmupCnt = erlang:min(Cnt, 20),
	[assert_ok(Fun()) || _ <- lists:seq(1, WarmupCnt)],
	Start = erlang:monotonic_time(nanosecond),
	[assert_ok(Fun()) || _ <- lists:seq(1, Cnt)],
	Elapsed = erlang:monotonic_time(nanosecond) - Start,
	Elapsed div Cnt.


assert_ok({ok, _, _}) -> ok;
assert_ok({ok, _, _, _}) -> ok;
assert_ok(Other) -> error({unexpected_query_result, Other}).


explain_total_ns(Conn, Sql) ->
	explain_total_ns(Conn, Sql, []).


explain_total_ns(Conn, Sql, Params) ->
	ExplainSql = "EXPLAIN (ANALYZE, TIMING OFF, FORMAT TEXT) " ++ Sql,
	case epgsql:equery(Conn, ExplainSql, Params) of
		{ok, _Cols, Rows} ->
			parse_explain_total_ns(Rows);
		{ok, _Count, _Cols, Rows} ->
			parse_explain_total_ns(Rows);
		Other ->
			error({unexpected_explain_result, Other})
	end.


parse_explain_total_ns(Rows) ->
	PlanningNs = extract_explain_metric_ns("Planning Time", Rows),
	ExecutionNs = extract_explain_metric_ns("Execution Time", Rows),
	PlanningNs + ExecutionNs.


extract_explain_metric_ns(Label, Rows) ->
	Prefix = list_to_binary(Label ++ ": "),
	case lists:dropwhile(fun({Line}) -> binary:match(Line, Prefix) =:= nomatch end, Rows) of
		[{Line} | _] ->
			ValueSize = byte_size(Line) - byte_size(Prefix) - 3,
			ValueBin = binary:part(Line, byte_size(Prefix), ValueSize),
			round(binary_to_float(ValueBin) * 1000000);
		[] ->
			error({explain_metric_not_found, Label, Rows})
	end.


qps_summary(ClientAvgNs, ServerNs) ->
	#{
		client_avg_ns => ClientAvgNs,
		client_qps => round(?NS_PER_SEC / ClientAvgNs),
		server_total_ns => ServerNs,
		server_qps => round(?NS_PER_SEC / ServerNs),
		recommended_workers => ceil_div(ClientAvgNs, ServerNs),
		overhead_ns => ClientAvgNs - ServerNs
	}.


ceil_div(A, _B) when A =< 0 -> 0;
ceil_div(_A, B) when B =< 0 -> 1;
ceil_div(A, B) ->
	(A + B - 1) div B.


print_report_item(Name, Summary) ->
	io:format("~n=== ~p ===~n", [Name]),
	io:format("client_avg_ns       = ~p~n", [maps:get(client_avg_ns, Summary)]),
	io:format("client_qps          = ~p~n", [maps:get(client_qps, Summary)]),
	io:format("server_total_ns     = ~p~n", [maps:get(server_total_ns, Summary)]),
	io:format("server_qps          = ~p~n", [maps:get(server_qps, Summary)]),
	io:format("overhead_ns         = ~p~n", [maps:get(overhead_ns, Summary)]),
	io:format("recommended_workers = ~p~n", [maps:get(recommended_workers, Summary)]).

tt() ->
	?PgErr(<<"start the pgdb pool error ~p~n">>, [{error, {already_started, self()}}]),
	?PgErr("start the pgdb pool error11 ~p~n", [{error, {already_started, self()}}]).
	