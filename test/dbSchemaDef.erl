%%%-------------------------------------------------------------------
%%% @doc 此文件由 genPSchema 自动生成，请勿手动修改。
%%%-------------------------------------------------------------------
-module(dbSchemaDef).

-compile([nowarn_unused_record, nowarn_unused_function]).

-export([getTables/0, tableFields/1, tableInsert/1, tableReplace/1, onReplace/1, tableSchema/1, tablePrimaryKey/1, fieldSchema/2, fieldCodec/2, fieldDefault/2]).

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
	loadFun = undefined,  %% undefined | {M, F, A}  undefined  - 使用通用加载逻辑（全量扫描 DB） {M, F, A}  - 自定义初始化加载函数，调用 M:F(Table, A...) 如果是whole Data就是整条数据 否则就是KeyValue
	flushLimit = 500,     %% non_neg_integer() 每轮落盘条数上限，infinity=全量 每轮 flush 最多处理的脏 key 数，infinity 表示一次性刷完整张状态表
	isOrder = false       %% true 是否为order_set 可能有些表需要保持访问顺序，true 则使用 order_set 作为 ETS 类型，false 则使用 set
}).

tableFields(Table) -> tableFields_(toAtom(Table)).
tableInsert(Table) -> tableInsert_(toAtom(Table)).
tableReplace(Table) -> tableReplace_(toAtom(Table)).
onReplace(Table) -> onReplace_(toAtom(Table)).
tableSchema(Table) -> tableSchema_(toAtom(Table)).
tablePrimaryKey(Table) -> tablePrimaryKey_(toAtom(Table)).
fieldSchema(Table, Field) -> fieldSchema_(toAtom(Table), toAtom(Field)).

getTables() ->
	[
		%pg_bench_schema
		bench_users, bench_orders, bench_events, bench_kv, bench_blobs,
		%pg_player_schema
		players, items,
		%pg_types_schema
		numeric_samples, text_samples, time_samples, json_binary_samples, composite_samples, constraint_samples, erl_type_showcase
	].

tableFields_(bench_users) -> [{<<"id">>, 2, undefined, id}, {<<"name">>, 3, undefined, name}, {<<"email">>, 4, undefined, email}, {<<"age">>, 5, undefined, age}, {<<"score">>, 6, undefined, score}, {<<"balance">>, 7, undefined, balance}, {<<"is_active">>, 8, undefined, is_active}, {<<"profile">>, 9, json, profile}, {<<"tags">>, 10, undefined, tags}, {<<"login_at">>, 11, undefined, login_at}, {<<"created_at">>, 12, undefined, created_at}];
tableFields_(bench_orders) -> [{<<"id">>, 2, undefined, id}, {<<"user_id">>, 3, undefined, user_id}, {<<"order_no">>, 4, undefined, order_no}, {<<"amount">>, 5, undefined, amount}, {<<"quantity">>, 6, undefined, quantity}, {<<"status">>, 7, undefined, status}, {<<"items">>, 8, json, items}, {<<"paid_at">>, 9, undefined, paid_at}, {<<"created_at">>, 10, undefined, created_at}];
tableFields_(bench_events) -> [{<<"id">>, 1, undefined, id}, {<<"table_name">>, 2, undefined, table_name}, {<<"event_type">>, 3, undefined, event_type}, {<<"source">>, 4, atom, source}, {<<"level">>, 5, undefined, level}, {<<"actor_id">>, 6, undefined, actor_id}, {<<"payload">>, 7, json, payload}, {<<"extra">>, 8, term_str, extra}, {<<"trace_id">>, 9, undefined, trace_id}, {<<"client_ip">>, 10, undefined, client_ip}, {<<"occurred_at">>, 11, undefined, occurred_at}];
tableFields_(bench_kv) -> [{<<"key">>, 1, undefined, key}, {<<"table_name">>, 2, undefined, table_name}, {<<"value">>, 3, json, value}, {<<"version">>, 4, undefined, version}, {<<"ttl">>, 5, undefined, ttl}, {<<"updated_at">>, 6, undefined, updated_at}];
tableFields_(bench_blobs) -> [{<<"id">>, 2, undefined, id}, {<<"name">>, 3, undefined, name}, {<<"mime_type">>, 4, undefined, mime_type}, {<<"size_bytes">>, 5, undefined, size_bytes}, {<<"data">>, 6, undefined, data}, {<<"checksum">>, 7, undefined, checksum}, {<<"created_at">>, 8, undefined, created_at}];
tableFields_(players) -> [{<<"id">>, 2, undefined, id}, {<<"name">>, 3, undefined, name}, {<<"level">>, 4, undefined, level}, {<<"gold">>, 5, undefined, gold}, {<<"vip">>, 6, undefined, vip}, {<<"status">>, 7, undefined, status}, {<<"profile">>, 8, json, profile}, {<<"tags">>, 9, undefined, tags}, {<<"created_at">>, 10, undefined, created_at}];
tableFields_(items) -> [{<<"id">>, 2, undefined, id}, {<<"player_id">>, 3, undefined, player_id}, {<<"item_type">>, 4, atom, item_type}, {<<"count">>, 5, undefined, count}, {<<"attrs">>, 6, json, attrs}, {<<"state_data">>, 7, term_binary, state_data}];
tableFields_(numeric_samples) -> [{<<"id">>, 2, undefined, id}, {<<"tiny_id">>, 3, undefined, tiny_id}, {<<"small_val">>, 4, undefined, small_val}, {<<"int_val">>, 5, undefined, int_val}, {<<"int_alias">>, 6, undefined, int_alias}, {<<"big_val">>, 7, undefined, big_val}, {<<"float_val">>, 8, undefined, float_val}, {<<"double_val">>, 9, undefined, double_val}, {<<"money">>, 10, undefined, money}, {<<"ratio">>, 11, undefined, ratio}];
tableFields_(text_samples) -> [{<<"id">>, 2, undefined, id}, {<<"content">>, 3, undefined, content}, {<<"short_name">>, 4, undefined, short_name}, {<<"long_desc">>, 5, undefined, long_desc}, {<<"country_code">>, 6, undefined, country_code}, {<<"fixed_code">>, 7, undefined, fixed_code}, {<<"trace_id">>, 8, undefined, trace_id}, {<<"client_ip">>, 9, undefined, client_ip}];
tableFields_(time_samples) -> [{<<"id">>, 1, undefined, id}, {<<"table_name">>, 2, undefined, table_name}, {<<"created_at">>, 3, undefined, created_at}, {<<"updated_at">>, 4, undefined, updated_at}, {<<"birth_date">>, 5, undefined, birth_date}, {<<"alarm_time">>, 6, undefined, alarm_time}, {<<"expire_at">>, 7, undefined, expire_at}];
tableFields_(json_binary_samples) -> [{<<"id">>, 2, undefined, id}, {<<"config">>, 3, json, config}, {<<"metadata">>, 4, json, metadata}, {<<"payload">>, 5, json, payload}, {<<"avatar">>, 6, undefined, avatar}, {<<"snapshot">>, 7, undefined, snapshot}, {<<"settings">>, 8, json, settings}, {<<"json_as_text">>, 9, json, json_as_text}, {<<"term_readable">>, 10, term_str, term_readable}, {<<"term_blob">>, 11, term_binary, term_blob}, {<<"status_name">>, 12, atom, status_name}, {<<"runtime_cache">>, 13, temp, runtime_cache}, {<<"custom_blob">>, 14, {custom, ePgdb, demo_custom_codec, demo_tag}, custom_blob}, {<<"dirty_flag">>, 15, temp, dirty_flag}];
tableFields_(composite_samples) -> [{<<"id">>, 2, undefined, id}, {<<"tags">>, 3, undefined, tags}, {<<"scores">>, 4, undefined, scores}, {<<"matrix">>, 5, undefined, matrix}, {<<"uuids">>, 6, undefined, uuids}, {<<"status">>, 7, atom, status}, {<<"role">>, 8, undefined, role}, {<<"priority">>, 9, atom, priority}];
tableFields_(constraint_samples) -> [{<<"id">>, 1, undefined, id}, {<<"table_name">>, 2, undefined, table_name}, {<<"owner_id">>, 3, undefined, owner_id}, {<<"group_id">>, 4, undefined, group_id}, {<<"ref_id">>, 5, undefined, ref_id}, {<<"email">>, 6, undefined, email}, {<<"score">>, 7, undefined, score}, {<<"level">>, 8, undefined, level}, {<<"nickname">>, 9, undefined, nickname}, {<<"data">>, 10, json, data}];
tableFields_(erl_type_showcase) -> [{<<"id">>, 2, undefined, id}, {<<"count">>, 3, undefined, count}, {<<"rate">>, 4, undefined, rate}, {<<"flag">>, 5, undefined, flag}, {<<"value">>, 6, undefined, value}, {<<"label">>, 7, undefined, label}, {<<"profile">>, 8, json, profile}, {<<"history">>, 9, json, history}, {<<"coords">>, 10, undefined, coords}, {<<"ids">>, 11, undefined, ids}, {<<"state">>, 12, atom, state}, {<<"color">>, 13, undefined, color}, {<<"position">>, 14, json, position}, {<<"extra">>, 15, json, extra}];
tableFields_(_) -> [].

tableInsert_(bench_users) -> <<"INSERT INTO \"bench_users\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)">>;
tableInsert_(bench_orders) -> <<"INSERT INTO \"bench_orders\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)">>;
tableInsert_(bench_events) -> <<"INSERT INTO \"bench_events\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)">>;
tableInsert_(bench_kv) -> <<"INSERT INTO \"bench_kv\" VALUES ($1, $2, $3, $4, $5, $6)">>;
tableInsert_(bench_blobs) -> <<"INSERT INTO \"bench_blobs\" VALUES ($1, $2, $3, $4, $5, $6, $7)">>;
tableInsert_(players) -> <<"INSERT INTO \"players\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)">>;
tableInsert_(items) -> <<"INSERT INTO \"items\" VALUES ($1, $2, $3, $4, $5, $6)">>;
tableInsert_(numeric_samples) -> <<"INSERT INTO \"numeric_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)">>;
tableInsert_(text_samples) -> <<"INSERT INTO \"text_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8)">>;
tableInsert_(time_samples) -> <<"INSERT INTO \"time_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7)">>;
tableInsert_(json_binary_samples) -> <<"INSERT INTO \"json_binary_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)">>;
tableInsert_(composite_samples) -> <<"INSERT INTO \"composite_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8)">>;
tableInsert_(constraint_samples) -> <<"INSERT INTO \"constraint_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)">>;
tableInsert_(erl_type_showcase) -> <<"INSERT INTO \"erl_type_showcase\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)">>;
tableInsert_(_) -> undefined.

tableReplace_(bench_users) -> <<"INSERT INTO \"bench_users\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) ON CONFLICT(id) DO UPDATE SET name = EXCLUDED.name, email = EXCLUDED.email, age = EXCLUDED.age, score = EXCLUDED.score, balance = EXCLUDED.balance, is_active = EXCLUDED.is_active, profile = EXCLUDED.profile, tags = EXCLUDED.tags, login_at = EXCLUDED.login_at, created_at = EXCLUDED.created_at ">>;
tableReplace_(bench_orders) -> <<"INSERT INTO \"bench_orders\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) ON CONFLICT(id) DO UPDATE SET user_id = EXCLUDED.user_id, order_no = EXCLUDED.order_no, amount = EXCLUDED.amount, quantity = EXCLUDED.quantity, status = EXCLUDED.status, items = EXCLUDED.items, paid_at = EXCLUDED.paid_at, created_at = EXCLUDED.created_at ">>;
tableReplace_(bench_events) -> <<"INSERT INTO \"bench_events\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) ON CONFLICT(id) DO UPDATE SET table_name = EXCLUDED.table_name, event_type = EXCLUDED.event_type, source = EXCLUDED.source, level = EXCLUDED.level, actor_id = EXCLUDED.actor_id, payload = EXCLUDED.payload, extra = EXCLUDED.extra, trace_id = EXCLUDED.trace_id, client_ip = EXCLUDED.client_ip, occurred_at = EXCLUDED.occurred_at ">>;
tableReplace_(bench_kv) -> <<"INSERT INTO \"bench_kv\" VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT(key) DO UPDATE SET table_name = EXCLUDED.table_name, value = EXCLUDED.value, version = EXCLUDED.version, ttl = EXCLUDED.ttl, updated_at = EXCLUDED.updated_at ">>;
tableReplace_(bench_blobs) -> <<"INSERT INTO \"bench_blobs\" VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT(id) DO UPDATE SET name = EXCLUDED.name, mime_type = EXCLUDED.mime_type, size_bytes = EXCLUDED.size_bytes, data = EXCLUDED.data, checksum = EXCLUDED.checksum, created_at = EXCLUDED.created_at ">>;
tableReplace_(players) -> <<"INSERT INTO \"players\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) ON CONFLICT(id) DO UPDATE SET name = EXCLUDED.name, level = EXCLUDED.level, gold = EXCLUDED.gold, vip = EXCLUDED.vip, status = EXCLUDED.status, profile = EXCLUDED.profile, tags = EXCLUDED.tags, created_at = EXCLUDED.created_at ">>;
tableReplace_(items) -> <<"INSERT INTO \"items\" VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT(id) DO UPDATE SET player_id = EXCLUDED.player_id, item_type = EXCLUDED.item_type, count = EXCLUDED.count, attrs = EXCLUDED.attrs, state_data = EXCLUDED.state_data ">>;
tableReplace_(numeric_samples) -> <<"INSERT INTO \"numeric_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) ON CONFLICT(id) DO UPDATE SET tiny_id = EXCLUDED.tiny_id, small_val = EXCLUDED.small_val, int_val = EXCLUDED.int_val, int_alias = EXCLUDED.int_alias, big_val = EXCLUDED.big_val, float_val = EXCLUDED.float_val, double_val = EXCLUDED.double_val, money = EXCLUDED.money, ratio = EXCLUDED.ratio ">>;
tableReplace_(text_samples) -> <<"INSERT INTO \"text_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT(id) DO UPDATE SET content = EXCLUDED.content, short_name = EXCLUDED.short_name, long_desc = EXCLUDED.long_desc, country_code = EXCLUDED.country_code, fixed_code = EXCLUDED.fixed_code, trace_id = EXCLUDED.trace_id, client_ip = EXCLUDED.client_ip ">>;
tableReplace_(time_samples) -> <<"INSERT INTO \"time_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT(id) DO UPDATE SET table_name = EXCLUDED.table_name, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at, birth_date = EXCLUDED.birth_date, alarm_time = EXCLUDED.alarm_time, expire_at = EXCLUDED.expire_at ">>;
tableReplace_(json_binary_samples) -> <<"INSERT INTO \"json_binary_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) ON CONFLICT(id) DO UPDATE SET config = EXCLUDED.config, metadata = EXCLUDED.metadata, payload = EXCLUDED.payload, avatar = EXCLUDED.avatar, snapshot = EXCLUDED.snapshot, settings = EXCLUDED.settings, json_as_text = EXCLUDED.json_as_text, term_readable = EXCLUDED.term_readable, term_blob = EXCLUDED.term_blob, status_name = EXCLUDED.status_name, runtime_cache = EXCLUDED.runtime_cache, custom_blob = EXCLUDED.custom_blob, dirty_flag = EXCLUDED.dirty_flag ">>;
tableReplace_(composite_samples) -> <<"INSERT INTO \"composite_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8) ON CONFLICT(id) DO UPDATE SET tags = EXCLUDED.tags, scores = EXCLUDED.scores, matrix = EXCLUDED.matrix, uuids = EXCLUDED.uuids, status = EXCLUDED.status, role = EXCLUDED.role, priority = EXCLUDED.priority ">>;
tableReplace_(constraint_samples) -> <<"INSERT INTO \"constraint_samples\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) ON CONFLICT(id) DO UPDATE SET table_name = EXCLUDED.table_name, owner_id = EXCLUDED.owner_id, group_id = EXCLUDED.group_id, ref_id = EXCLUDED.ref_id, email = EXCLUDED.email, score = EXCLUDED.score, level = EXCLUDED.level, nickname = EXCLUDED.nickname, data = EXCLUDED.data ">>;
tableReplace_(erl_type_showcase) -> <<"INSERT INTO \"erl_type_showcase\" VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14) ON CONFLICT(id) DO UPDATE SET count = EXCLUDED.count, rate = EXCLUDED.rate, flag = EXCLUDED.flag, value = EXCLUDED.value, label = EXCLUDED.label, profile = EXCLUDED.profile, history = EXCLUDED.history, coords = EXCLUDED.coords, ids = EXCLUDED.ids, state = EXCLUDED.state, color = EXCLUDED.color, position = EXCLUDED.position, extra = EXCLUDED.extra ">>;
tableReplace_(_) -> undefined.

onReplace_(bench_users) -> <<" ON CONFLICT(id) DO UPDATE SET name = EXCLUDED.name, email = EXCLUDED.email, age = EXCLUDED.age, score = EXCLUDED.score, balance = EXCLUDED.balance, is_active = EXCLUDED.is_active, profile = EXCLUDED.profile, tags = EXCLUDED.tags, login_at = EXCLUDED.login_at, created_at = EXCLUDED.created_at ">>;
onReplace_(bench_orders) -> <<" ON CONFLICT(id) DO UPDATE SET user_id = EXCLUDED.user_id, order_no = EXCLUDED.order_no, amount = EXCLUDED.amount, quantity = EXCLUDED.quantity, status = EXCLUDED.status, items = EXCLUDED.items, paid_at = EXCLUDED.paid_at, created_at = EXCLUDED.created_at ">>;
onReplace_(bench_events) -> <<" ON CONFLICT(id) DO UPDATE SET table_name = EXCLUDED.table_name, event_type = EXCLUDED.event_type, source = EXCLUDED.source, level = EXCLUDED.level, actor_id = EXCLUDED.actor_id, payload = EXCLUDED.payload, extra = EXCLUDED.extra, trace_id = EXCLUDED.trace_id, client_ip = EXCLUDED.client_ip, occurred_at = EXCLUDED.occurred_at ">>;
onReplace_(bench_kv) -> <<" ON CONFLICT(key) DO UPDATE SET table_name = EXCLUDED.table_name, value = EXCLUDED.value, version = EXCLUDED.version, ttl = EXCLUDED.ttl, updated_at = EXCLUDED.updated_at ">>;
onReplace_(bench_blobs) -> <<" ON CONFLICT(id) DO UPDATE SET name = EXCLUDED.name, mime_type = EXCLUDED.mime_type, size_bytes = EXCLUDED.size_bytes, data = EXCLUDED.data, checksum = EXCLUDED.checksum, created_at = EXCLUDED.created_at ">>;
onReplace_(players) -> <<" ON CONFLICT(id) DO UPDATE SET name = EXCLUDED.name, level = EXCLUDED.level, gold = EXCLUDED.gold, vip = EXCLUDED.vip, status = EXCLUDED.status, profile = EXCLUDED.profile, tags = EXCLUDED.tags, created_at = EXCLUDED.created_at ">>;
onReplace_(items) -> <<" ON CONFLICT(id) DO UPDATE SET player_id = EXCLUDED.player_id, item_type = EXCLUDED.item_type, count = EXCLUDED.count, attrs = EXCLUDED.attrs, state_data = EXCLUDED.state_data ">>;
onReplace_(numeric_samples) -> <<" ON CONFLICT(id) DO UPDATE SET tiny_id = EXCLUDED.tiny_id, small_val = EXCLUDED.small_val, int_val = EXCLUDED.int_val, int_alias = EXCLUDED.int_alias, big_val = EXCLUDED.big_val, float_val = EXCLUDED.float_val, double_val = EXCLUDED.double_val, money = EXCLUDED.money, ratio = EXCLUDED.ratio ">>;
onReplace_(text_samples) -> <<" ON CONFLICT(id) DO UPDATE SET content = EXCLUDED.content, short_name = EXCLUDED.short_name, long_desc = EXCLUDED.long_desc, country_code = EXCLUDED.country_code, fixed_code = EXCLUDED.fixed_code, trace_id = EXCLUDED.trace_id, client_ip = EXCLUDED.client_ip ">>;
onReplace_(time_samples) -> <<" ON CONFLICT(id) DO UPDATE SET table_name = EXCLUDED.table_name, created_at = EXCLUDED.created_at, updated_at = EXCLUDED.updated_at, birth_date = EXCLUDED.birth_date, alarm_time = EXCLUDED.alarm_time, expire_at = EXCLUDED.expire_at ">>;
onReplace_(json_binary_samples) -> <<" ON CONFLICT(id) DO UPDATE SET config = EXCLUDED.config, metadata = EXCLUDED.metadata, payload = EXCLUDED.payload, avatar = EXCLUDED.avatar, snapshot = EXCLUDED.snapshot, settings = EXCLUDED.settings, json_as_text = EXCLUDED.json_as_text, term_readable = EXCLUDED.term_readable, term_blob = EXCLUDED.term_blob, status_name = EXCLUDED.status_name, runtime_cache = EXCLUDED.runtime_cache, custom_blob = EXCLUDED.custom_blob, dirty_flag = EXCLUDED.dirty_flag ">>;
onReplace_(composite_samples) -> <<" ON CONFLICT(id) DO UPDATE SET tags = EXCLUDED.tags, scores = EXCLUDED.scores, matrix = EXCLUDED.matrix, uuids = EXCLUDED.uuids, status = EXCLUDED.status, role = EXCLUDED.role, priority = EXCLUDED.priority ">>;
onReplace_(constraint_samples) -> <<" ON CONFLICT(id) DO UPDATE SET table_name = EXCLUDED.table_name, owner_id = EXCLUDED.owner_id, group_id = EXCLUDED.group_id, ref_id = EXCLUDED.ref_id, email = EXCLUDED.email, score = EXCLUDED.score, level = EXCLUDED.level, nickname = EXCLUDED.nickname, data = EXCLUDED.data ">>;
onReplace_(erl_type_showcase) -> <<" ON CONFLICT(id) DO UPDATE SET count = EXCLUDED.count, rate = EXCLUDED.rate, flag = EXCLUDED.flag, value = EXCLUDED.value, label = EXCLUDED.label, profile = EXCLUDED.profile, history = EXCLUDED.history, coords = EXCLUDED.coords, ids = EXCLUDED.ids, state = EXCLUDED.state, color = EXCLUDED.color, position = EXCLUDED.position, extra = EXCLUDED.extra ">>;
onReplace_(_) -> undefined.

tableSchema_(bench_users) ->
	#schema{
		repr = record, comment = "压测用户表",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "自增主键"},
			#schField{name = name, dbType = {varchar, 64}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "用户名"},
			#schField{name = email, dbType = {varchar, 128}, default = undefined, opts = [unique], codec = undefined, erlType = "binary()", comment = "邮箱"},
			#schField{name = age, dbType = smallint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "integer()", comment = "年龄"},
			#schField{name = score, dbType = bigint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "non_neg_integer()", comment = "积分"},
			#schField{name = balance, dbType = {numeric, 14, 2}, default = 0, opts = [{default, 0}], codec = undefined, erlType = "number()", comment = "余额"},
			#schField{name = is_active, dbType = boolean, default = true, opts = [{default, true}], codec = undefined, erlType = "boolean()", comment = "是否活跃"},
			#schField{name = profile, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "画像数据"},
			#schField{name = tags, dbType = {array, text}, default = [], opts = [{default, []}], codec = undefined, erlType = "[binary()]", comment = "标签"},
			#schField{name = login_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "最后登录"},
			#schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "创建时间"}
		]
	};
tableSchema_(bench_orders) ->
	#schema{
		repr = record, comment = "压测订单表",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "订单ID"},
			#schField{name = user_id, dbType = bigint, default = undefined, opts = [not_null, {references, {bench_users, id, cascade}}], codec = undefined, erlType = "integer()", comment = "用户ID (外键+索引)"},
			#schField{name = order_no, dbType = {varchar, 32}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "订单号"},
			#schField{name = amount, dbType = {numeric, 12, 2}, default = 0, opts = [{default, 0}], codec = undefined, erlType = "number()", comment = "金额"},
			#schField{name = quantity, dbType = integer, default = 1, opts = [{default, 1}], codec = undefined, erlType = "integer()", comment = "数量"},
			#schField{name = status, dbType = {enum, binary}, default = <<"pending">>, opts = [{default, <<"pending">>}], codec = undefined, erlType = "binary()", comment = "状态: pending/paid/shipped/done"},
			#schField{name = items, dbType = jsonb, default = [], opts = [{default, <<"[]">>}], codec = json, erlType = "[map()]", comment = "订单明细 JSON 数组"},
			#schField{name = paid_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary() | undefined", comment = "支付时间 (可空)"},
			#schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "创建时间"}
		]
	};
tableSchema_(bench_events) ->
	#schema{
		repr = map, comment = "压测事件日志表 (map 表示)",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "事件ID"},
			#schField{name = table_name, dbType = {varchar, 64}, default = <<"bench_events">>, opts = [{default, <<"bench_events">>}, not_null], codec = undefined, erlType = "binary()", comment = "所属表名"},
			#schField{name = event_type, dbType = {varchar, 32}, default = undefined, opts = [not_null], codec = undefined, erlType = "binary()", comment = "事件类型"},
			#schField{name = source, dbType = {enum, atom}, default = system, opts = [{default, <<"system">>}], codec = atom, erlType = "system | user | cron | api", comment = "事件来源"},
			#schField{name = level, dbType = smallint, default = 0, opts = [{default, 0}, {check, "level >= 0 AND level <= 5"}], codec = undefined, erlType = "integer()", comment = "严重级别 0~5"},
			#schField{name = actor_id, dbType = bigint, default = undefined, opts = [], codec = undefined, erlType = "integer()", comment = "操作者ID"},
			#schField{name = payload, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "事件详情"},
			#schField{name = extra, dbType = text, default = undefined, opts = [], codec = term_str, erlType = "term()", comment = "扩展数据 (Erlang term 可读字符串)"},
			#schField{name = trace_id, dbType = uuid, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "链路追踪ID"},
			#schField{name = client_ip, dbType = inet, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "客户端IP"},
			#schField{name = occurred_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "发生时间"}
		]
	};
tableSchema_(bench_kv) ->
	#schema{
		repr = map, comment = "压测KV表 (极简高频读写)",
		fields = [
			#schField{name = key, dbType = {varchar, 128}, default = undefined, opts = [primary_key], codec = undefined, erlType = "binary()", comment = "键"},
			#schField{name = table_name, dbType = {varchar, 64}, default = <<"bench_kv">>, opts = [{default, <<"bench_kv">>}, not_null], codec = undefined, erlType = "binary()", comment = "所属表名"},
			#schField{name = value, dbType = text, default = null, opts = [{default, null}], codec = json, erlType = "term()", comment = "值 (text 列存 JSON, codec_json)"},
			#schField{name = version, dbType = integer, default = 1, opts = [{default, 1}, not_null, {check, "version > 0"}], codec = undefined, erlType = "integer()", comment = "乐观锁版本号"},
			#schField{name = ttl, dbType = integer, default = 0, opts = [{default, 0}], codec = undefined, erlType = "non_neg_integer()", comment = "TTL 秒数, 0=永不过期"},
			#schField{name = updated_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "更新时间"}
		]
	};
tableSchema_(bench_blobs) ->
	#schema{
		repr = record, comment = "压测大对象表 (bytea 读写)",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"},
			#schField{name = name, dbType = {varchar, 64}, default = undefined, opts = [not_null], codec = undefined, erlType = "binary()", comment = "名称"},
			#schField{name = mime_type, dbType = {varchar, 64}, default = <<"application/octet-stream">>, opts = [{default, <<"application/octet-stream">>}], codec = undefined, erlType = "binary()", comment = "MIME 类型"},
			#schField{name = size_bytes, dbType = bigint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "non_neg_integer()", comment = "文件大小"},
			#schField{name = data, dbType = bytea, default = <<>>, opts = [{default, <<>>}], codec = undefined, erlType = "binary()", comment = "二进制数据"},
			#schField{name = checksum, dbType = {char, 32}, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "MD5 校验和"},
			#schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "上传时间"}
		]
	};
tableSchema_(players) ->
	#schema{
		repr = record, comment = "玩家主表",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "玩家唯一ID"},
			#schField{name = name, dbType = {varchar, 64}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "玩家名字"},
			#schField{name = level, dbType = integer, default = 1, opts = [{default, 1}], codec = undefined, erlType = "integer()", comment = "等级"},
			#schField{name = gold, dbType = bigint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "integer()", comment = "金币"},
			#schField{name = vip, dbType = boolean, default = false, opts = [{default, false}], codec = undefined, erlType = "boolean()", comment = "是否VIP"},
			#schField{name = status, dbType = {enum, binary}, default = <<"idle">>, opts = [{default, <<"idle">>}], codec = undefined, erlType = "binary()", comment = "状态"},
			#schField{name = profile, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "玩家档案JSON"},
			#schField{name = tags, dbType = {array, text}, default = [], opts = [{default, []}], codec = undefined, erlType = "[binary()]", comment = "标签列表"},
			#schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "创建时间"}
		]
	};
tableSchema_(items) ->
	#schema{
		repr = record, comment = "道具表",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "道具唯一ID"},
			#schField{name = player_id, dbType = bigint, default = undefined, opts = [not_null, {references, {players, id, cascade}}], codec = undefined, erlType = "integer()", comment = "所属玩家ID"},
			#schField{name = item_type, dbType = {varchar, 32}, default = undefined, opts = [not_null], codec = atom, erlType = "atom()", comment = "道具类型 (atom: sword/shield/potion)"},
			#schField{name = count, dbType = integer, default = 1, opts = [{default, 1}], codec = undefined, erlType = "integer()", comment = "数量"},
			#schField{name = attrs, dbType = jsonb, default = undefined, opts = [], codec = json, erlType = "map()", comment = "扩展属性"},
			#schField{name = state_data, dbType = bytea, default = undefined, opts = [], codec = term_binary, erlType = "term()", comment = "道具状态 (Erlang term 二进制序列化)"}
		]
	};
tableSchema_(numeric_samples) ->
	#schema{
		repr = record, comment = "数值类型全覆盖",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "自增主键 bigserial"},
			#schField{name = tiny_id, dbType = serial, default = undefined, opts = [], codec = undefined, erlType = "integer()", comment = "自增 serial"},
			#schField{name = small_val, dbType = smallint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "integer()", comment = "smallint 带默认值"},
			#schField{name = int_val, dbType = integer, default = 42, opts = [{default, 42}], codec = undefined, erlType = "integer()", comment = "integer 带默认值"},
			#schField{name = int_alias, dbType = int, default = 0, opts = [{default, 0}], codec = undefined, erlType = "integer()", comment = "int (integer 别名)"},
			#schField{name = big_val, dbType = bigint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "non_neg_integer()", comment = "bigint + 自定义 erlType"},
			#schField{name = float_val, dbType = float, default = 0.0, opts = [{default, 0.0}], codec = undefined, erlType = "float()", comment = "float 单精度"},
			#schField{name = double_val, dbType = double, default = 0.0, opts = [{default, 0.0}], codec = undefined, erlType = "float()", comment = "double 双精度 + erlType"},
			#schField{name = money, dbType = {numeric, 12, 2}, default = 0, opts = [{default, 0}], codec = undefined, erlType = "number()", comment = "numeric(12,2) 金额"},
			#schField{name = ratio, dbType = {numeric, 5, 4}, default = undefined, opts = [], codec = undefined, erlType = "number()", comment = "numeric(5,4) 比率"}
		]
	};
tableSchema_(text_samples) ->
	#schema{
		repr = record, comment = "文本类型全覆盖",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"},
			#schField{name = content, dbType = text, default = <<>>, opts = [{default, <<>>}], codec = undefined, erlType = "binary()", comment = "text 无限长文本"},
			#schField{name = short_name, dbType = {varchar, 32}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "varchar(32) 非空唯一"},
			#schField{name = long_desc, dbType = {varchar, 2048}, default = <<>>, opts = [{default, <<>>}], codec = undefined, erlType = "binary()", comment = "varchar(2048) 长描述"},
			#schField{name = country_code, dbType = {char, 2}, default = <<"CN">>, opts = [{default, <<"CN">>}], codec = undefined, erlType = "binary()", comment = "char(2) 国家代码"},
			#schField{name = fixed_code, dbType = {char, 6}, default = undefined, opts = [not_null], codec = undefined, erlType = "binary()", comment = "char(6) 定长编码"},
			#schField{name = trace_id, dbType = uuid, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "uuid 跟踪ID"},
			#schField{name = client_ip, dbType = inet, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "inet 客户端IP"}
		]
	};
tableSchema_(time_samples) ->
	#schema{
		repr = map, comment = "时间日期类型全覆盖 (map 表示)",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"},
			#schField{name = table_name, dbType = {varchar, 64}, default = <<"time_samples">>, opts = [{default, <<"time_samples">>}, not_null], codec = undefined, erlType = "binary()", comment = "所属表名"},
			#schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "timestamptz 含时区"},
			#schField{name = updated_at, dbType = timestamp, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "timestamp 不含时区"},
			#schField{name = birth_date, dbType = date, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "date 仅日期"},
			#schField{name = alarm_time, dbType = time, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "time 仅时间"},
			#schField{name = expire_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary() | undefined", comment = "可空的时间戳 + erlType"}
		]
	};
tableSchema_(json_binary_samples) ->
	#schema{
		repr = record, comment = "JSON与二进制类型覆盖",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"},
			#schField{name = config, dbType = json, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "json 保留原始格式"},
			#schField{name = metadata, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "jsonb 支持索引"},
			#schField{name = payload, dbType = jsonb, default = undefined, opts = [], codec = json, erlType = "map() | list()", comment = "jsonb 也可能是列表"},
			#schField{name = avatar, dbType = bytea, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "bytea 二进制头像"},
			#schField{name = snapshot, dbType = bytea, default = <<>>, opts = [{default, <<>>}], codec = undefined, erlType = "binary()", comment = "bytea 带默认空二进制"},
			#schField{name = settings, dbType = jsonb, default = #{auto_login => true}, opts = [{default, <<"{\"auto_login\":true}">>}], codec = json, erlType = "#{atom() => term()}", comment = "jsonb 带复杂默认值 + 精确 erlType"},
			#schField{name = json_as_text, dbType = text, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "text 列存 JSON, codec_json 编解码"},
			#schField{name = term_readable, dbType = text, default = undefined, opts = [], codec = term_str, erlType = "term()", comment = "text 列存 Erlang term 可读字符串, codec_term_str"},
			#schField{name = term_blob, dbType = bytea, default = undefined, opts = [], codec = term_binary, erlType = "term()", comment = "bytea 列存 Erlang term 二进制, codec_term_binary"},
			#schField{name = status_name, dbType = {varchar, 32}, default = active, opts = [{default, <<"active">>}], codec = atom, erlType = "atom()", comment = "varchar 列存 atom, codec_atom 编解码"},
			#schField{name = runtime_cache, dbType = bytea, default = #{dirty => false}, opts = [], codec = temp, erlType = "map()", comment = "仅应用层临时缓存字段, codec_temp 不入库"},
			#schField{name = custom_blob, dbType = bytea, default = #{source => demo}, opts = [], codec = {custom, ePgdb, demo_custom_codec, demo_tag}, erlType = "map()", comment = "bytea 列使用 ePgdb:demo_custom_codec/5 做自定义编解码"},
			#schField{name = dirty_flag, dbType = integer, default = 0, opts = [], codec = temp, erlType = "intrger()", comment = "仅应用层临时缓存字段, codec_temp 不入库"}
		]
	};
tableSchema_(composite_samples) ->
	#schema{
		repr = record, comment = "复合类型覆盖: array, enum",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"},
			#schField{name = tags, dbType = {array, text}, default = [], opts = [{default, []}], codec = undefined, erlType = "[binary()]", comment = "text[] 文本数组"},
			#schField{name = scores, dbType = {array, integer}, default = [], opts = [{default, []}], codec = undefined, erlType = "[integer()]", comment = "integer[] + erlType"},
			#schField{name = matrix, dbType = {array, double}, default = [], opts = [{default, []}], codec = undefined, erlType = "[float()]", comment = "double[] 浮点数组"},
			#schField{name = uuids, dbType = {array, uuid}, default = [], opts = [{default, []}], codec = undefined, erlType = "[binary()]", comment = "uuid[] UUID 数组"},
			#schField{name = status, dbType = {enum, atom}, default = active, opts = [{default, <<"active">>}], codec = atom, erlType = "atom()", comment = "enum atom 模式"},
			#schField{name = role, dbType = {enum, binary}, default = <<"user">>, opts = [{default, <<"user">>}], codec = undefined, erlType = "binary()", comment = "enum binary 模式"},
			#schField{name = priority, dbType = {enum, atom}, default = normal, opts = [{default, <<"normal">>}], codec = atom, erlType = "low | normal | high | critical", comment = "enum atom + 联合 erlType"}
		]
	};
tableSchema_(constraint_samples) ->
	#schema{
		repr = map, comment = "约束选项全覆盖 (map 表示)",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键约束"},
			#schField{name = table_name, dbType = {varchar, 64}, default = <<"constraint_samples">>, opts = [{default, <<"constraint_samples">>}, not_null], codec = undefined, erlType = "binary()", comment = "所属表名"},
			#schField{name = owner_id, dbType = bigint, default = undefined, opts = [not_null, {references, {numeric_samples, id, cascade}}], codec = undefined, erlType = "integer()", comment = "外键 + cascade"},
			#schField{name = group_id, dbType = bigint, default = undefined, opts = [{references, {numeric_samples, id, set_null}}], codec = undefined, erlType = "integer()", comment = "外键 + set_null"},
			#schField{name = ref_id, dbType = bigint, default = undefined, opts = [{references, {numeric_samples, id}}], codec = undefined, erlType = "integer()", comment = "外键 无级联 (默认 NO ACTION)"},
			#schField{name = email, dbType = {varchar, 128}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "非空 + 唯一 + 索引"},
			#schField{name = score, dbType = integer, default = 0, opts = [{default, 0}, {check, "score >= 0 AND score <= 99999"}], codec = undefined, erlType = "integer()", comment = "check 约束"},
			#schField{name = level, dbType = smallint, default = 1, opts = [{default, 1}, not_null, {check, "level >= 1"}], codec = undefined, erlType = "integer()", comment = "多约束组合: 非空+check+索引"},
			#schField{name = nickname, dbType = {varchar, 64}, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "仅索引"},
			#schField{name = data, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "jsonb 数据"}
		]
	};
tableSchema_(erl_type_showcase) ->
	#schema{
		repr = record, comment = "erlType 赋值方式展示",
		fields = [
			#schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"},
			#schField{name = count, dbType = integer, default = undefined, opts = [], codec = undefined, erlType = "non_neg_integer()", comment = "非负整数"},
			#schField{name = rate, dbType = double, default = undefined, opts = [], codec = undefined, erlType = "float()", comment = "float"},
			#schField{name = flag, dbType = boolean, default = undefined, opts = [], codec = undefined, erlType = "boolean()", comment = "布尔"},
			#schField{name = value, dbType = bigint, default = undefined, opts = [], codec = undefined, erlType = "integer() | undefined", comment = "可空整数"},
			#schField{name = label, dbType = text, default = undefined, opts = [], codec = undefined, erlType = "binary() | <<>>", comment = "二进制或空串"},
			#schField{name = profile, dbType = jsonb, default = undefined, opts = [], codec = json, erlType = "#{binary() => term()}", comment = "map 精确 key 类型"},
			#schField{name = history, dbType = jsonb, default = undefined, opts = [], codec = json, erlType = "[map()]", comment = "map列表"},
			#schField{name = coords, dbType = {array, double}, default = undefined, opts = [], codec = undefined, erlType = "[float()]", comment = "坐标浮点列表"},
			#schField{name = ids, dbType = {array, bigint}, default = undefined, opts = [], codec = undefined, erlType = "[pos_integer()]", comment = "正整数列表"},
			#schField{name = state, dbType = {enum, atom}, default = idle, opts = [{default, <<"idle">>}], codec = atom, erlType = "idle | running | stopped", comment = "有限atom联合"},
			#schField{name = color, dbType = {enum, binary}, default = <<"red">>, opts = [{default, <<"red">>}], codec = undefined, erlType = "binary()", comment = "有限binary联合"},
			#schField{name = position, dbType = jsonb, default = #{y => 0, x => 0}, opts = [{default, <<"{\"x\":0,\"y\":0}">>}], codec = json, erlType = "#{x => number(), y => number()}", comment = "坐标map类型"},
			#schField{name = extra, dbType = jsonb, default = null, opts = [{default, null}], codec = json, erlType = "term()", comment = "完全通用 term"}
		]
	};
tableSchema_(_) -> undefined.

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

fieldSchema_(bench_users, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "自增主键"};
fieldSchema_(bench_users, name) -> #schField{name = name, dbType = {varchar, 64}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "用户名"};
fieldSchema_(bench_users, email) -> #schField{name = email, dbType = {varchar, 128}, default = undefined, opts = [unique], codec = undefined, erlType = "binary()", comment = "邮箱"};
fieldSchema_(bench_users, age) -> #schField{name = age, dbType = smallint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "integer()", comment = "年龄"};
fieldSchema_(bench_users, score) -> #schField{name = score, dbType = bigint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "non_neg_integer()", comment = "积分"};
fieldSchema_(bench_users, balance) -> #schField{name = balance, dbType = {numeric, 14, 2}, default = 0, opts = [{default, 0}], codec = undefined, erlType = "number()", comment = "余额"};
fieldSchema_(bench_users, is_active) -> #schField{name = is_active, dbType = boolean, default = true, opts = [{default, true}], codec = undefined, erlType = "boolean()", comment = "是否活跃"};
fieldSchema_(bench_users, profile) -> #schField{name = profile, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "画像数据"};
fieldSchema_(bench_users, tags) -> #schField{name = tags, dbType = {array, text}, default = [], opts = [{default, []}], codec = undefined, erlType = "[binary()]", comment = "标签"};
fieldSchema_(bench_users, login_at) -> #schField{name = login_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "最后登录"};
fieldSchema_(bench_users, created_at) -> #schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "创建时间"};
fieldSchema_(bench_orders, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "订单ID"};
fieldSchema_(bench_orders, user_id) -> #schField{name = user_id, dbType = bigint, default = undefined, opts = [not_null, {references, {bench_users, id, cascade}}], codec = undefined, erlType = "integer()", comment = "用户ID (外键+索引)"};
fieldSchema_(bench_orders, order_no) -> #schField{name = order_no, dbType = {varchar, 32}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "订单号"};
fieldSchema_(bench_orders, amount) -> #schField{name = amount, dbType = {numeric, 12, 2}, default = 0, opts = [{default, 0}], codec = undefined, erlType = "number()", comment = "金额"};
fieldSchema_(bench_orders, quantity) -> #schField{name = quantity, dbType = integer, default = 1, opts = [{default, 1}], codec = undefined, erlType = "integer()", comment = "数量"};
fieldSchema_(bench_orders, status) -> #schField{name = status, dbType = {enum, binary}, default = <<"pending">>, opts = [{default, <<"pending">>}], codec = undefined, erlType = "binary()", comment = "状态: pending/paid/shipped/done"};
fieldSchema_(bench_orders, items) -> #schField{name = items, dbType = jsonb, default = [], opts = [{default, <<"[]">>}], codec = json, erlType = "[map()]", comment = "订单明细 JSON 数组"};
fieldSchema_(bench_orders, paid_at) -> #schField{name = paid_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary() | undefined", comment = "支付时间 (可空)"};
fieldSchema_(bench_orders, created_at) -> #schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "创建时间"};
fieldSchema_(bench_events, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "事件ID"};
fieldSchema_(bench_events, table_name) -> #schField{name = table_name, dbType = {varchar, 64}, default = <<"bench_events">>, opts = [{default, <<"bench_events">>}, not_null], codec = undefined, erlType = "binary()", comment = "所属表名"};
fieldSchema_(bench_events, event_type) -> #schField{name = event_type, dbType = {varchar, 32}, default = undefined, opts = [not_null], codec = undefined, erlType = "binary()", comment = "事件类型"};
fieldSchema_(bench_events, source) -> #schField{name = source, dbType = {enum, atom}, default = system, opts = [{default, <<"system">>}], codec = atom, erlType = "system | user | cron | api", comment = "事件来源"};
fieldSchema_(bench_events, level) -> #schField{name = level, dbType = smallint, default = 0, opts = [{default, 0}, {check, "level >= 0 AND level <= 5"}], codec = undefined, erlType = "integer()", comment = "严重级别 0~5"};
fieldSchema_(bench_events, actor_id) -> #schField{name = actor_id, dbType = bigint, default = undefined, opts = [], codec = undefined, erlType = "integer()", comment = "操作者ID"};
fieldSchema_(bench_events, payload) -> #schField{name = payload, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "事件详情"};
fieldSchema_(bench_events, extra) -> #schField{name = extra, dbType = text, default = undefined, opts = [], codec = term_str, erlType = "term()", comment = "扩展数据 (Erlang term 可读字符串)"};
fieldSchema_(bench_events, trace_id) -> #schField{name = trace_id, dbType = uuid, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "链路追踪ID"};
fieldSchema_(bench_events, client_ip) -> #schField{name = client_ip, dbType = inet, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "客户端IP"};
fieldSchema_(bench_events, occurred_at) -> #schField{name = occurred_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "发生时间"};
fieldSchema_(bench_kv, key) -> #schField{name = key, dbType = {varchar, 128}, default = undefined, opts = [primary_key], codec = undefined, erlType = "binary()", comment = "键"};
fieldSchema_(bench_kv, table_name) -> #schField{name = table_name, dbType = {varchar, 64}, default = <<"bench_kv">>, opts = [{default, <<"bench_kv">>}, not_null], codec = undefined, erlType = "binary()", comment = "所属表名"};
fieldSchema_(bench_kv, value) -> #schField{name = value, dbType = text, default = null, opts = [{default, null}], codec = json, erlType = "term()", comment = "值 (text 列存 JSON, codec_json)"};
fieldSchema_(bench_kv, version) -> #schField{name = version, dbType = integer, default = 1, opts = [{default, 1}, not_null, {check, "version > 0"}], codec = undefined, erlType = "integer()", comment = "乐观锁版本号"};
fieldSchema_(bench_kv, ttl) -> #schField{name = ttl, dbType = integer, default = 0, opts = [{default, 0}], codec = undefined, erlType = "non_neg_integer()", comment = "TTL 秒数, 0=永不过期"};
fieldSchema_(bench_kv, updated_at) -> #schField{name = updated_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "更新时间"};
fieldSchema_(bench_blobs, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"};
fieldSchema_(bench_blobs, name) -> #schField{name = name, dbType = {varchar, 64}, default = undefined, opts = [not_null], codec = undefined, erlType = "binary()", comment = "名称"};
fieldSchema_(bench_blobs, mime_type) -> #schField{name = mime_type, dbType = {varchar, 64}, default = <<"application/octet-stream">>, opts = [{default, <<"application/octet-stream">>}], codec = undefined, erlType = "binary()", comment = "MIME 类型"};
fieldSchema_(bench_blobs, size_bytes) -> #schField{name = size_bytes, dbType = bigint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "non_neg_integer()", comment = "文件大小"};
fieldSchema_(bench_blobs, data) -> #schField{name = data, dbType = bytea, default = <<>>, opts = [{default, <<>>}], codec = undefined, erlType = "binary()", comment = "二进制数据"};
fieldSchema_(bench_blobs, checksum) -> #schField{name = checksum, dbType = {char, 32}, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "MD5 校验和"};
fieldSchema_(bench_blobs, created_at) -> #schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "上传时间"};
fieldSchema_(players, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "玩家唯一ID"};
fieldSchema_(players, name) -> #schField{name = name, dbType = {varchar, 64}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "玩家名字"};
fieldSchema_(players, level) -> #schField{name = level, dbType = integer, default = 1, opts = [{default, 1}], codec = undefined, erlType = "integer()", comment = "等级"};
fieldSchema_(players, gold) -> #schField{name = gold, dbType = bigint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "integer()", comment = "金币"};
fieldSchema_(players, vip) -> #schField{name = vip, dbType = boolean, default = false, opts = [{default, false}], codec = undefined, erlType = "boolean()", comment = "是否VIP"};
fieldSchema_(players, status) -> #schField{name = status, dbType = {enum, binary}, default = <<"idle">>, opts = [{default, <<"idle">>}], codec = undefined, erlType = "binary()", comment = "状态"};
fieldSchema_(players, profile) -> #schField{name = profile, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "玩家档案JSON"};
fieldSchema_(players, tags) -> #schField{name = tags, dbType = {array, text}, default = [], opts = [{default, []}], codec = undefined, erlType = "[binary()]", comment = "标签列表"};
fieldSchema_(players, created_at) -> #schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "创建时间"};
fieldSchema_(items, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "道具唯一ID"};
fieldSchema_(items, player_id) -> #schField{name = player_id, dbType = bigint, default = undefined, opts = [not_null, {references, {players, id, cascade}}], codec = undefined, erlType = "integer()", comment = "所属玩家ID"};
fieldSchema_(items, item_type) -> #schField{name = item_type, dbType = {varchar, 32}, default = undefined, opts = [not_null], codec = atom, erlType = "atom()", comment = "道具类型 (atom: sword/shield/potion)"};
fieldSchema_(items, count) -> #schField{name = count, dbType = integer, default = 1, opts = [{default, 1}], codec = undefined, erlType = "integer()", comment = "数量"};
fieldSchema_(items, attrs) -> #schField{name = attrs, dbType = jsonb, default = undefined, opts = [], codec = json, erlType = "map()", comment = "扩展属性"};
fieldSchema_(items, state_data) -> #schField{name = state_data, dbType = bytea, default = undefined, opts = [], codec = term_binary, erlType = "term()", comment = "道具状态 (Erlang term 二进制序列化)"};
fieldSchema_(numeric_samples, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "自增主键 bigserial"};
fieldSchema_(numeric_samples, tiny_id) -> #schField{name = tiny_id, dbType = serial, default = undefined, opts = [], codec = undefined, erlType = "integer()", comment = "自增 serial"};
fieldSchema_(numeric_samples, small_val) -> #schField{name = small_val, dbType = smallint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "integer()", comment = "smallint 带默认值"};
fieldSchema_(numeric_samples, int_val) -> #schField{name = int_val, dbType = integer, default = 42, opts = [{default, 42}], codec = undefined, erlType = "integer()", comment = "integer 带默认值"};
fieldSchema_(numeric_samples, int_alias) -> #schField{name = int_alias, dbType = int, default = 0, opts = [{default, 0}], codec = undefined, erlType = "integer()", comment = "int (integer 别名)"};
fieldSchema_(numeric_samples, big_val) -> #schField{name = big_val, dbType = bigint, default = 0, opts = [{default, 0}], codec = undefined, erlType = "non_neg_integer()", comment = "bigint + 自定义 erlType"};
fieldSchema_(numeric_samples, float_val) -> #schField{name = float_val, dbType = float, default = 0.0, opts = [{default, 0.0}], codec = undefined, erlType = "float()", comment = "float 单精度"};
fieldSchema_(numeric_samples, double_val) -> #schField{name = double_val, dbType = double, default = 0.0, opts = [{default, 0.0}], codec = undefined, erlType = "float()", comment = "double 双精度 + erlType"};
fieldSchema_(numeric_samples, money) -> #schField{name = money, dbType = {numeric, 12, 2}, default = 0, opts = [{default, 0}], codec = undefined, erlType = "number()", comment = "numeric(12,2) 金额"};
fieldSchema_(numeric_samples, ratio) -> #schField{name = ratio, dbType = {numeric, 5, 4}, default = undefined, opts = [], codec = undefined, erlType = "number()", comment = "numeric(5,4) 比率"};
fieldSchema_(text_samples, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"};
fieldSchema_(text_samples, content) -> #schField{name = content, dbType = text, default = <<>>, opts = [{default, <<>>}], codec = undefined, erlType = "binary()", comment = "text 无限长文本"};
fieldSchema_(text_samples, short_name) -> #schField{name = short_name, dbType = {varchar, 32}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "varchar(32) 非空唯一"};
fieldSchema_(text_samples, long_desc) -> #schField{name = long_desc, dbType = {varchar, 2048}, default = <<>>, opts = [{default, <<>>}], codec = undefined, erlType = "binary()", comment = "varchar(2048) 长描述"};
fieldSchema_(text_samples, country_code) -> #schField{name = country_code, dbType = {char, 2}, default = <<"CN">>, opts = [{default, <<"CN">>}], codec = undefined, erlType = "binary()", comment = "char(2) 国家代码"};
fieldSchema_(text_samples, fixed_code) -> #schField{name = fixed_code, dbType = {char, 6}, default = undefined, opts = [not_null], codec = undefined, erlType = "binary()", comment = "char(6) 定长编码"};
fieldSchema_(text_samples, trace_id) -> #schField{name = trace_id, dbType = uuid, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "uuid 跟踪ID"};
fieldSchema_(text_samples, client_ip) -> #schField{name = client_ip, dbType = inet, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "inet 客户端IP"};
fieldSchema_(time_samples, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"};
fieldSchema_(time_samples, table_name) -> #schField{name = table_name, dbType = {varchar, 64}, default = <<"time_samples">>, opts = [{default, <<"time_samples">>}, not_null], codec = undefined, erlType = "binary()", comment = "所属表名"};
fieldSchema_(time_samples, created_at) -> #schField{name = created_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "timestamptz 含时区"};
fieldSchema_(time_samples, updated_at) -> #schField{name = updated_at, dbType = timestamp, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "timestamp 不含时区"};
fieldSchema_(time_samples, birth_date) -> #schField{name = birth_date, dbType = date, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "date 仅日期"};
fieldSchema_(time_samples, alarm_time) -> #schField{name = alarm_time, dbType = time, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "time 仅时间"};
fieldSchema_(time_samples, expire_at) -> #schField{name = expire_at, dbType = timestamptz, default = undefined, opts = [], codec = undefined, erlType = "binary() | undefined", comment = "可空的时间戳 + erlType"};
fieldSchema_(json_binary_samples, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"};
fieldSchema_(json_binary_samples, config) -> #schField{name = config, dbType = json, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "json 保留原始格式"};
fieldSchema_(json_binary_samples, metadata) -> #schField{name = metadata, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "jsonb 支持索引"};
fieldSchema_(json_binary_samples, payload) -> #schField{name = payload, dbType = jsonb, default = undefined, opts = [], codec = json, erlType = "map() | list()", comment = "jsonb 也可能是列表"};
fieldSchema_(json_binary_samples, avatar) -> #schField{name = avatar, dbType = bytea, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "bytea 二进制头像"};
fieldSchema_(json_binary_samples, snapshot) -> #schField{name = snapshot, dbType = bytea, default = <<>>, opts = [{default, <<>>}], codec = undefined, erlType = "binary()", comment = "bytea 带默认空二进制"};
fieldSchema_(json_binary_samples, settings) -> #schField{name = settings, dbType = jsonb, default = #{auto_login => true}, opts = [{default, <<"{\"auto_login\":true}">>}], codec = json, erlType = "#{atom() => term()}", comment = "jsonb 带复杂默认值 + 精确 erlType"};
fieldSchema_(json_binary_samples, json_as_text) -> #schField{name = json_as_text, dbType = text, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "text 列存 JSON, codec_json 编解码"};
fieldSchema_(json_binary_samples, term_readable) -> #schField{name = term_readable, dbType = text, default = undefined, opts = [], codec = term_str, erlType = "term()", comment = "text 列存 Erlang term 可读字符串, codec_term_str"};
fieldSchema_(json_binary_samples, term_blob) -> #schField{name = term_blob, dbType = bytea, default = undefined, opts = [], codec = term_binary, erlType = "term()", comment = "bytea 列存 Erlang term 二进制, codec_term_binary"};
fieldSchema_(json_binary_samples, status_name) -> #schField{name = status_name, dbType = {varchar, 32}, default = active, opts = [{default, <<"active">>}], codec = atom, erlType = "atom()", comment = "varchar 列存 atom, codec_atom 编解码"};
fieldSchema_(json_binary_samples, runtime_cache) -> #schField{name = runtime_cache, dbType = bytea, default = #{dirty => false}, opts = [], codec = temp, erlType = "map()", comment = "仅应用层临时缓存字段, codec_temp 不入库"};
fieldSchema_(json_binary_samples, custom_blob) -> #schField{name = custom_blob, dbType = bytea, default = #{source => demo}, opts = [], codec = {custom, ePgdb, demo_custom_codec, demo_tag}, erlType = "map()", comment = "bytea 列使用 ePgdb:demo_custom_codec/5 做自定义编解码"};
fieldSchema_(json_binary_samples, dirty_flag) -> #schField{name = dirty_flag, dbType = integer, default = 0, opts = [], codec = temp, erlType = "intrger()", comment = "仅应用层临时缓存字段, codec_temp 不入库"};
fieldSchema_(composite_samples, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"};
fieldSchema_(composite_samples, tags) -> #schField{name = tags, dbType = {array, text}, default = [], opts = [{default, []}], codec = undefined, erlType = "[binary()]", comment = "text[] 文本数组"};
fieldSchema_(composite_samples, scores) -> #schField{name = scores, dbType = {array, integer}, default = [], opts = [{default, []}], codec = undefined, erlType = "[integer()]", comment = "integer[] + erlType"};
fieldSchema_(composite_samples, matrix) -> #schField{name = matrix, dbType = {array, double}, default = [], opts = [{default, []}], codec = undefined, erlType = "[float()]", comment = "double[] 浮点数组"};
fieldSchema_(composite_samples, uuids) -> #schField{name = uuids, dbType = {array, uuid}, default = [], opts = [{default, []}], codec = undefined, erlType = "[binary()]", comment = "uuid[] UUID 数组"};
fieldSchema_(composite_samples, status) -> #schField{name = status, dbType = {enum, atom}, default = active, opts = [{default, <<"active">>}], codec = atom, erlType = "atom()", comment = "enum atom 模式"};
fieldSchema_(composite_samples, role) -> #schField{name = role, dbType = {enum, binary}, default = <<"user">>, opts = [{default, <<"user">>}], codec = undefined, erlType = "binary()", comment = "enum binary 模式"};
fieldSchema_(composite_samples, priority) -> #schField{name = priority, dbType = {enum, atom}, default = normal, opts = [{default, <<"normal">>}], codec = atom, erlType = "low | normal | high | critical", comment = "enum atom + 联合 erlType"};
fieldSchema_(constraint_samples, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键约束"};
fieldSchema_(constraint_samples, table_name) -> #schField{name = table_name, dbType = {varchar, 64}, default = <<"constraint_samples">>, opts = [{default, <<"constraint_samples">>}, not_null], codec = undefined, erlType = "binary()", comment = "所属表名"};
fieldSchema_(constraint_samples, owner_id) -> #schField{name = owner_id, dbType = bigint, default = undefined, opts = [not_null, {references, {numeric_samples, id, cascade}}], codec = undefined, erlType = "integer()", comment = "外键 + cascade"};
fieldSchema_(constraint_samples, group_id) -> #schField{name = group_id, dbType = bigint, default = undefined, opts = [{references, {numeric_samples, id, set_null}}], codec = undefined, erlType = "integer()", comment = "外键 + set_null"};
fieldSchema_(constraint_samples, ref_id) -> #schField{name = ref_id, dbType = bigint, default = undefined, opts = [{references, {numeric_samples, id}}], codec = undefined, erlType = "integer()", comment = "外键 无级联 (默认 NO ACTION)"};
fieldSchema_(constraint_samples, email) -> #schField{name = email, dbType = {varchar, 128}, default = undefined, opts = [not_null, unique], codec = undefined, erlType = "binary()", comment = "非空 + 唯一 + 索引"};
fieldSchema_(constraint_samples, score) -> #schField{name = score, dbType = integer, default = 0, opts = [{default, 0}, {check, "score >= 0 AND score <= 99999"}], codec = undefined, erlType = "integer()", comment = "check 约束"};
fieldSchema_(constraint_samples, level) -> #schField{name = level, dbType = smallint, default = 1, opts = [{default, 1}, not_null, {check, "level >= 1"}], codec = undefined, erlType = "integer()", comment = "多约束组合: 非空+check+索引"};
fieldSchema_(constraint_samples, nickname) -> #schField{name = nickname, dbType = {varchar, 64}, default = undefined, opts = [], codec = undefined, erlType = "binary()", comment = "仅索引"};
fieldSchema_(constraint_samples, data) -> #schField{name = data, dbType = jsonb, default = #{}, opts = [{default, <<"{}">>}], codec = json, erlType = "map()", comment = "jsonb 数据"};
fieldSchema_(erl_type_showcase, id) -> #schField{name = id, dbType = bigserial, default = undefined, opts = [primary_key], codec = undefined, erlType = "integer()", comment = "主键"};
fieldSchema_(erl_type_showcase, count) -> #schField{name = count, dbType = integer, default = undefined, opts = [], codec = undefined, erlType = "non_neg_integer()", comment = "非负整数"};
fieldSchema_(erl_type_showcase, rate) -> #schField{name = rate, dbType = double, default = undefined, opts = [], codec = undefined, erlType = "float()", comment = "float"};
fieldSchema_(erl_type_showcase, flag) -> #schField{name = flag, dbType = boolean, default = undefined, opts = [], codec = undefined, erlType = "boolean()", comment = "布尔"};
fieldSchema_(erl_type_showcase, value) -> #schField{name = value, dbType = bigint, default = undefined, opts = [], codec = undefined, erlType = "integer() | undefined", comment = "可空整数"};
fieldSchema_(erl_type_showcase, label) -> #schField{name = label, dbType = text, default = undefined, opts = [], codec = undefined, erlType = "binary() | <<>>", comment = "二进制或空串"};
fieldSchema_(erl_type_showcase, profile) -> #schField{name = profile, dbType = jsonb, default = undefined, opts = [], codec = json, erlType = "#{binary() => term()}", comment = "map 精确 key 类型"};
fieldSchema_(erl_type_showcase, history) -> #schField{name = history, dbType = jsonb, default = undefined, opts = [], codec = json, erlType = "[map()]", comment = "map列表"};
fieldSchema_(erl_type_showcase, coords) -> #schField{name = coords, dbType = {array, double}, default = undefined, opts = [], codec = undefined, erlType = "[float()]", comment = "坐标浮点列表"};
fieldSchema_(erl_type_showcase, ids) -> #schField{name = ids, dbType = {array, bigint}, default = undefined, opts = [], codec = undefined, erlType = "[pos_integer()]", comment = "正整数列表"};
fieldSchema_(erl_type_showcase, state) -> #schField{name = state, dbType = {enum, atom}, default = idle, opts = [{default, <<"idle">>}], codec = atom, erlType = "idle | running | stopped", comment = "有限atom联合"};
fieldSchema_(erl_type_showcase, color) -> #schField{name = color, dbType = {enum, binary}, default = <<"red">>, opts = [{default, <<"red">>}], codec = undefined, erlType = "binary()", comment = "有限binary联合"};
fieldSchema_(erl_type_showcase, position) -> #schField{name = position, dbType = jsonb, default = #{y => 0, x => 0}, opts = [{default, <<"{\"x\":0,\"y\":0}">>}], codec = json, erlType = "#{x => number(), y => number()}", comment = "坐标map类型"};
fieldSchema_(erl_type_showcase, extra) -> #schField{name = extra, dbType = jsonb, default = null, opts = [{default, null}], codec = json, erlType = "term()", comment = "完全通用 term"};
fieldSchema_(_, _) -> undefined.

fieldCodec(Table, Field) ->
	case fieldSchema_(toAtom(Table), toAtom(Field)) of
		#schField{codec = Codec} -> Codec;
		_ -> undefined
	end.

fieldDefault(Table, Field) ->
	case fieldSchema_(toAtom(Table), toAtom(Field)) of
		#schField{default = Default} -> Default;
		_ -> undefined
	end.

toAtom(Value) when is_atom(Value) -> Value;
toAtom(Value) when is_binary(Value) -> binary_to_atom(Value, utf8);
toAtom(Value) when is_list(Value) -> list_to_atom(Value).

