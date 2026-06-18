%%%-------------------------------------------------------------------
%%% @doc 测试公共辅助模块。
%%%
%%% 提供数据库连接启停、测试数据生成、表清空等功能，
%%% 供 pgdb_crud_tests / pgdb_select_tests / pgdb_bench_tests 共用。
%%%-------------------------------------------------------------------
-module(pgdb_test_helper).

-include("pg_player_schema.hrl").
-include("pg_bench_schema.hrl").

-export([
	%% 连接生命周期
	start/0,
	stop/0,
	
	%% 连接参数
	db_host/0, db_port/0, db_user/0, db_pass/0, db_name/0,
	
	%% 表清理
	truncate/1,
	truncate_all/0,
	
	%% ID 生成
	gen_id/0,
	gen_name/1,
	
	%% 测试数据工厂
	new_player/0,
	new_player/1,
	new_bench_user/0,
	new_bench_user/1,
	new_bench_order/2,
	new_bench_event/0,
	new_kv/2,

	%% DirtyMask 工具
	dirty_mask/2
]).

%%%===================================================================
%%% 连接参数（可通过环境变量覆盖）
%%%===================================================================
-define(db_cfg(), [{pg_host, "localhost"}, {pg_port, 5432}, {pg_user, "postgres"}, {pg_pass, "156736"}, {pg_table, "epgdb_test"}]).
% -define(db_cfg(), [{pg_host, "192.168.0.88"}, {pg_port, 5436}, {pg_user, "postgres"}, {pg_pass, "pg7193"}, {pg_table, "epgdb_test"}]).

-define(dbCfg(Key), proplists:get_value(Key, ?db_cfg())).
db_host() -> os:getenv("PGHOST", ?dbCfg(pg_host)).
db_port() -> case os:getenv("PGPORT") of false -> ?dbCfg(pg_port);P -> list_to_integer(P) end.
db_user() -> os:getenv("PGUSER", ?dbCfg(pg_user)).
db_pass() -> os:getenv("PGPASSWORD", ?dbCfg(pg_pass)).
db_name() -> os:getenv("PGDATABASE", ?dbCfg(pg_table)).

%%%===================================================================
%%% 连接生命周期
%%%===================================================================

start() ->
	application:ensure_all_started(jiffy),
	case ePgdb:start(db_host(), db_port(), db_user(), db_pass(), db_name(), [
		{wFCnt, 32},
		{wKeepTime, 1800000},
		{slowThreshold, 5000},
		{heartbeatInterval, 30000},
		{wArgs, [
			{timeout, 5000},
			{application_name, "ePgdb_test"},
			{tcp_opts, [
				{keepalive, true},
				{nodelay, true}
			]}
		]}
	]) of
		{ok, Pid} ->
			unlink(Pid),
			ok;
		{error, Reason} -> error({db_start_failed, Reason});
		%% ePgdb:start 的 else 分支在连接失败时返回裸 ok（来自 error_logger:error_msg 的返回值）
		ok -> error({db_start_failed, connection_refused_or_auth_error})
	end.

stop() ->
	try ePgdb:stop()
	catch _C:_R ->
		ignore
	end,
	ok.

%%%===================================================================
%%% 表清理（RESTART IDENTITY 重置序列，CASCADE 清级联外键数据）
%%%===================================================================

truncate(Table) when is_atom(Table) ->
	TBin = atom_to_binary(Table, utf8),
	ePgdb:query([<<"TRUNCATE TABLE \"">>, TBin, <<"\" RESTART IDENTITY CASCADE">>]);
truncate(Table) when is_binary(Table) ->
	ePgdb:query([<<"TRUNCATE TABLE \"">>, Table, <<"\" RESTART IDENTITY CASCADE">>]).

truncate_all() ->
	%% 注意顺序：先清有外键的子表，再清父表
	Tables = [items, bench_orders, bench_blobs, bench_events,
		bench_kv, players, bench_users],
	[truncate(T) || T <- Tables],
	ok.

%%%===================================================================
%%% ID / 名称生成
%%%===================================================================

%% 生成一个当前 VM 内唯一的正整数，用于手动指定 bigserial 字段。
%% 测试前已 TRUNCATE RESTART IDENTITY，故与序列无冲突。
gen_id() ->
	erlang:unique_integer([positive, monotonic]).

%% 生成唯一名称（带 Prefix 前缀）
gen_name(Prefix) when is_binary(Prefix) ->
	N = gen_id(),
	<<Prefix/binary, "_", (integer_to_binary(N rem 99999))/binary>>;
gen_name(Prefix) when is_atom(Prefix) ->
	gen_name(atom_to_binary(Prefix, utf8)).

now_timestamptz() ->
	{{Year, Month, Day}, {Hour, Minute, Second}} = calendar:universal_time(),
	{{Year, Month, Day}, {Hour, Minute, float(Second)}}.

%%%===================================================================
%%% 测试数据工厂
%%%===================================================================

%% 创建一个默认 players 记录（id 显式赋值，让 insert 不用依赖序列）
new_player() ->
	N = gen_id(),
	#players{
		id = N,
		name = <<"player_", (integer_to_binary(N rem 99999))/binary>>,
		level = 1,
		gold = 0,
		vip = false,
		status = <<"idle">>,
		profile = #{},
		tags = [],
		created_at = now_timestamptz()
	}.

%% 按 Opts map 覆盖默认值创建 players 记录
new_player(Opts) ->
	P = new_player(),
	maps:fold(fun
				  (id, V, R) -> R#players{id = V};
				  (name, V, R) -> R#players{name = V};
				  (level, V, R) -> R#players{level = V};
				  (gold, V, R) -> R#players{gold = V};
				  (vip, V, R) -> R#players{vip = V};
				  (status, V, R) -> R#players{status = V};
				  (profile, V, R) -> R#players{profile = V};
				  (tags, V, R) -> R#players{tags = V};
				  (created_at, V, R) -> R#players{created_at = V};
				  (_, _, R) -> R
			  end, P, Opts).

%% 创建一个默认 bench_users 记录
new_bench_user() ->
	N = gen_id(),
	#bench_users{
		id = N,
		name = <<"user_", (integer_to_binary(N rem 99999))/binary>>,
		email = <<"user_", (integer_to_binary(N rem 99999))/binary, "@test.com">>,
		age = 25,
		score = 100,
		balance = 50,
		is_active = true,
		profile = #{level => 1},
		tags = [<<"erlang">>, <<"test">>]
	}.

%% 按 Opts map 覆盖默认值创建 bench_users 记录
new_bench_user(Opts) ->
	U = new_bench_user(),
	maps:fold(fun
				  (id, V, R) -> R#bench_users{id = V};
				  (name, V, R) -> R#bench_users{name = V};
				  (email, V, R) -> R#bench_users{email = V};
				  (age, V, R) -> R#bench_users{age = V};
				  (score, V, R) -> R#bench_users{score = V};
				  (balance, V, R) -> R#bench_users{balance = V};
				  (is_active, V, R) -> R#bench_users{is_active = V};
				  (profile, V, R) -> R#bench_users{profile = V};
				  (tags, V, R) -> R#bench_users{tags = V};
				  (_, _, R) -> R
			  end, U, Opts).

%% 创建一个 bench_orders 记录
new_bench_order(UserId, OrderNo) ->
	N = gen_id(),
	#bench_orders{
		id = N,
		user_id = UserId,
		order_no = OrderNo,
		amount = 99,
		quantity = 1,
		status = <<"pending">>,
		items = [#{item => <<"sword">>, qty => 1}]
	}.

%% 创建一个 bench_events map（map repr 表）
new_bench_event() ->
	#{
		table_name => <<"bench_events">>,
		event_type => <<"login">>,
		source => system,
		level => 1,
		actor_id => gen_id() rem 9999,
		payload => #{action => <<"login">>},
		extra => {term, <<"extra_data">>},
		trace_id => undefined,
		client_ip => undefined,
		occurred_at => undefined
	}.

%% 创建一个 bench_kv map（map repr 表，key 为 varchar 主键）
new_kv(Key, Value) when is_binary(Key) ->
	#{
		table_name => <<"bench_kv">>,
		key => Key,
		value => Value,
		version => 1,
		ttl => 0,
		updated_at => undefined
	}.

%% @doc 将 players 字段 atom 列表转为 DirtyMask（位 N 对应 record 下标 N+1 的字段）。
dirty_mask(players, []) ->
	0;
dirty_mask(players, Fields) when is_list(Fields) ->
	lists:foldl(
		fun(Field, Acc) ->
			Acc bor (1 bsl (players_field_index(Field) - 1))
		end,
		0,
		Fields
	).

players_field_index(id) -> #players.id;
players_field_index(name) -> #players.name;
players_field_index(level) -> #players.level;
players_field_index(gold) -> #players.gold;
players_field_index(vip) -> #players.vip;
players_field_index(status) -> #players.status;
players_field_index(profile) -> #players.profile;
players_field_index(tags) -> #players.tags;
players_field_index(created_at) -> #players.created_at.
