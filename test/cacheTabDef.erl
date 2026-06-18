%%%-------------------------------------------------------------------
%%% @doc 此文件由 genPSchema 自动生成，请勿手动修改。
%%%-------------------------------------------------------------------
-module(cacheTabDef).

-compile([nowarn_unused_record, nowarn_unused_function]).

-export([getCaches/0, tableCache/1, tableFields/1, tablePrimaryKey/1, cacheType/1, keyValue/2, dirtyIndex/1]).

-record(schema, {
	repr = map,          %% record | map - Erlang 端数据表示方式
	comment = "",        %% string()|binary() - 表注释
	tbCache = undefined, %% undefined | #tbCache{}  缓存配置
	fields = []          %% [#schField{}]
}).

-record(schField, {
	name,                %% atom()     - 字段名
	dbType,              %% term()     - 数据库类型: integer | {varchar, 64} | jsonb | ...
	default = undefined, %% term()     - 默认值, undefined 表示无默认值
	opts = [],           %% [term()]   - 约束: [primary_key, not_null, unique, ...]
	codec = undefined,   %% undefined | json | term_str | term_binary | atom - 编解码策略
	erlType = "",        %% string()   - Erlang 类型声明字符串, "" 则从 dbType 推导
	comment = ""         %% string()|binary() - 注释 (同时用于代码和数据库)
}).

-record(tbCache, {
	type = whole,         %% whole | hotData  whole- 全表缓存，启动时将整张表数据加载到 ETS  热数据缓存，仅缓存被访问过的数据，同时维护全量 keys ETS
	ttl = 0,              %% non_neg_integer() hotData 缓存 TTL（秒），0=永不淘汰
	saveMode = 300,       %% pos_integer() 如果需要立即存库的表 就把时间配置短一点 (单位毫秒)
	saveType = whole,     %% whole | dirty whole落盘时写入整行数据（使用 upsert） dirty 落盘时仅写入脏字段（需配合 eCas:update/3 使用）
	loadFun = undefined,  %% undefined | {M, F, A}  undefined  -  {M, F, A}  - 自定义初始化加载时对对每条数据执行的函数，调用 M:F(Data, A...) 如果是whole Data就是整条数据 否则就是KeyValue
	flushLimit = 500,     %% non_neg_integer() 每轮落盘条数上限，infinity=全量 每轮 flush 最多处理的脏 key 数，infinity 表示一次性刷完整张状态表
	isOrder = false       %% true 是否为order_set 可能有些表需要保持访问顺序，true 则使用 order_set 作为 ETS 类型，false 则使用 set
}).

tableCache(Table) -> tableCache_(toAtom(Table)).
tableFields(Table) -> tableFields_(toAtom(Table)).
tablePrimaryKey(Table) -> tablePrimaryKey_(toAtom(Table)).
cacheType(Table) -> cacheType_(toAtom(Table)).
keyValue(Table, Data) -> keyValue_(toAtom(Table), Data).
dirtyIndex(Table) -> dirtyIndex_(toAtom(Table)).

getCaches() ->
	[
		%pg_player_schema
		players,
		%pg_types_schema
		json_binary_samples
	].

tableCache_(players) -> #tbCache{type = whole, ttl = 0, saveMode = 300, saveType = whole, loadFun = undefined, flushLimit = 500, isOrder = false};
tableCache_(json_binary_samples) -> #tbCache{type = whole, ttl = 0, saveMode = 300, saveType = whole, loadFun = undefined, flushLimit = 500, isOrder = false};
tableCache_(_) -> undefined.

tableFields_(players) -> [{2, id}, {3, name}, {4, level}, {5, gold}, {6, vip}, {7, status}, {8, profile}, {9, tags}, {10, created_at}];
tableFields_(json_binary_samples) -> [{2, id}, {3, config}, {4, metadata}, {5, payload}, {6, avatar}, {7, snapshot}, {8, settings}, {9, json_as_text}, {10, term_readable}, {11, term_blob}, {12, status_name}, {13, runtime_cache}, {14, custom_blob}, {15, dirty_flag}];
tableFields_(_) -> [].

tablePrimaryKey_(bench_users) -> [id];
tablePrimaryKey_(bench_orders) -> [id];
tablePrimaryKey_(bench_events) -> [id];
tablePrimaryKey_(bench_kv) -> [key];
tablePrimaryKey_(bench_blobs) -> [id];
tablePrimaryKey_(players) -> [id];
tablePrimaryKey_(items) -> [id];
tablePrimaryKey_(numeric_samples) -> [id];
tablePrimaryKey_(text_samples) -> [id];
tablePrimaryKey_(time_samples) -> [id];
tablePrimaryKey_(json_binary_samples) -> [id];
tablePrimaryKey_(composite_samples) -> [id];
tablePrimaryKey_(constraint_samples) -> [id];
tablePrimaryKey_(erl_type_showcase) -> [id];
tablePrimaryKey_(_) -> [].

cacheType_(players) -> whole;
cacheType_(json_binary_samples) -> whole;
cacheType_(_) -> undefined.

keyValue_(players, Data) -> element(2, Data);
keyValue_(json_binary_samples, Data) -> element(2, Data);
keyValue_(_, _) -> undefined.

dirtyIndex_(players) -> 0;
dirtyIndex_(json_binary_samples) -> 15;
dirtyIndex_(_) -> 0.

toAtom(Value) when is_atom(Value) -> Value;
toAtom(Value) when is_binary(Value) -> binary_to_atom(Value, utf8);
toAtom(Value) when is_list(Value) -> list_to_atom(Value).

