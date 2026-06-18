%%%-------------------------------------------------------------------
%%% @doc 压测用表 schema 定义。
%%% 用于 pgdb_bench 等性能测试场景。
%%%-------------------------------------------------------------------
-module(pg_bench_schema).

-compile([export_all, nowarn_export_all]).

-include("pgdbSchema.hrl").

%%% ===================================================================
%%% bench_users — 用户压测表，模拟大量读写
%%% ===================================================================
bench_users() ->
	#schema{
		repr = record,
		comment = "压测用户表",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "自增主键"},
			#schField{name = name, dbType = ?pg_varchar(64), opts = [?pg_not_null, ?pg_unique, ?pg_index], comment = "用户名"},
			#schField{name = email, dbType = ?pg_varchar(128), opts = [?pg_unique, ?pg_index], comment = "邮箱"},
			#schField{name = age, dbType = ?pg_smallint, default = 0, comment = "年龄"},
			#schField{name = score, dbType = ?pg_bigint, default = 0, erlType = "non_neg_integer()", comment = "积分"},
			#schField{name = balance, dbType = ?pg_numeric(14, 2), default = 0, erlType = "number()", comment = "余额"},
			#schField{name = is_active, dbType = ?pg_boolean, default = true, comment = "是否活跃"},
			#schField{name = profile, dbType = ?pg_jsonb, default = #{}, codec = ?codec_json, erlType = "map()", comment = "画像数据"},
			#schField{name = tags, dbType = ?pg_array(?pg_text), default = [], erlType = "[binary()]", comment = "标签"},
			#schField{name = login_at, dbType = ?pg_timestamptz, comment = "最后登录"},
			#schField{name = created_at, dbType = ?pg_timestamptz, comment = "创建时间"}
		]
	}.

%%% ===================================================================
%%% bench_orders — 订单压测表，模拟事务与关联查询
%%% ===================================================================
bench_orders() ->
	#schema{
		repr = record,
		comment = "压测订单表",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "订单ID"},
			#schField{name = user_id, dbType = ?pg_bigint, opts = [?pg_not_null, ?pg_references(bench_users, id, cascade), ?pg_index], comment = "用户ID (外键+索引)"},
			#schField{name = order_no, dbType = ?pg_varchar(32), opts = [?pg_not_null, ?pg_unique], comment = "订单号"},
			#schField{name = amount, dbType = ?pg_numeric(12, 2), default = 0, erlType = "number()", comment = "金额"},
			#schField{name = quantity, dbType = ?pg_integer, default = 1, comment = "数量"},
			#schField{name = status, dbType = ?pg_enum_binary, default = <<"pending">>, comment = "状态: pending/paid/shipped/done"},
			#schField{name = items, dbType = ?pg_jsonb, default = [], codec = ?codec_json, erlType = "[map()]", comment = "订单明细 JSON 数组"},
			#schField{name = paid_at, dbType = ?pg_timestamptz, erlType = "binary() | undefined", comment = "支付时间 (可空)"},
			#schField{name = created_at, dbType = ?pg_timestamptz, comment = "创建时间"}
		]
	}.

%%% ===================================================================
%%% bench_events — 事件日志压测表，模拟高频写入
%%% ===================================================================
bench_events() ->
	#schema{
		repr = map,
		comment = "压测事件日志表 (map 表示)",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "事件ID"},
			#schField{name = table_name, dbType = ?pg_varchar(64), default = <<"bench_events">>, opts = [?pg_not_null], comment = "所属表名"},
			#schField{name = event_type, dbType = ?pg_varchar(32), opts = [?pg_not_null, ?pg_index], comment = "事件类型"},
			#schField{name = source, dbType = ?pg_enum_atom, default = system, codec = ?codec_atom, erlType = "system | user | cron | api", comment = "事件来源"},
			#schField{name = level, dbType = ?pg_smallint, default = 0, opts = [?pg_check("level >= 0 AND level <= 5")], comment = "严重级别 0~5"},
			#schField{name = actor_id, dbType = ?pg_bigint, opts = [?pg_index], comment = "操作者ID"},
			#schField{name = payload, dbType = ?pg_jsonb, default = #{}, codec = ?codec_json, erlType = "map()", comment = "事件详情"},
			#schField{name = extra, dbType = ?pg_text, codec = ?codec_term_str, erlType = "term()", comment = "扩展数据 (Erlang term 可读字符串)"},
			#schField{name = trace_id, dbType = ?pg_uuid, erlType = "binary()", comment = "链路追踪ID"},
			#schField{name = client_ip, dbType = ?pg_inet, erlType = "binary()", comment = "客户端IP"},
			#schField{name = occurred_at, dbType = ?pg_timestamptz, comment = "发生时间"}
		]
	}.

%%% ===================================================================
%%% bench_kv — 简单KV压测表，模拟缓存/热点读写
%%% ===================================================================
bench_kv() ->
	#schema{
		repr = map,
		comment = "压测KV表 (极简高频读写)",
		fields = [
			#schField{name = key, dbType = ?pg_varchar(128), opts = [?pg_primary_key], comment = "键"},
			#schField{name = table_name, dbType = ?pg_varchar(64), default = <<"bench_kv">>, opts = [?pg_not_null], comment = "所属表名"},
			#schField{name = value, dbType = ?pg_text, default = null, codec = ?codec_json, erlType = "term()", comment = "值 (text 列存 JSON, codec_json)"},
			#schField{name = version, dbType = ?pg_integer, default = 1, opts = [?pg_not_null, ?pg_check("version > 0")], comment = "乐观锁版本号"},
			#schField{name = ttl, dbType = ?pg_integer, default = 0, erlType = "non_neg_integer()", comment = "TTL 秒数, 0=永不过期"},
			#schField{name = updated_at, dbType = ?pg_timestamptz, comment = "更新时间"}
		]
	}.

%%% ===================================================================
%%% bench_blobs — 大二进制压测表
%%% ===================================================================
bench_blobs() ->
	#schema{
		repr = record,
		comment = "压测大对象表 (bytea 读写)",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "主键"},
			#schField{name = name, dbType = ?pg_varchar(64), opts = [?pg_not_null], comment = "名称"},
			#schField{name = mime_type, dbType = ?pg_varchar(64), default = <<"application/octet-stream">>, comment = "MIME 类型"},
			#schField{name = size_bytes, dbType = ?pg_bigint, default = 0, erlType = "non_neg_integer()", comment = "文件大小"},
			#schField{name = data, dbType = ?pg_bytea, default = <<>>, erlType = "binary()", comment = "二进制数据"},
			#schField{name = checksum, dbType = ?pg_char(32), erlType = "binary()", comment = "MD5 校验和"},
			#schField{name = created_at, dbType = ?pg_timestamptz, comment = "上传时间"}
		]
	}.
