%%%-------------------------------------------------------------------
%%% @doc 全类型覆盖 schema。
%%% 用于测试和演示所有 dbType、opts、erlType 组合。
%%%-------------------------------------------------------------------
-module(pg_types_schema).

-compile([export_all, nowarn_export_all]).

-include("pgdbSchema.hrl").

%%% ===================================================================
%%% numeric_samples — 覆盖所有数值类型
%%% ===================================================================
numeric_samples() ->
	#schema{
		repr = record,
		comment = "数值类型全覆盖",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "自增主键 bigserial"},
			#schField{name = tiny_id, dbType = ?pg_serial, comment = "自增 serial"},
			#schField{name = small_val, dbType = ?pg_smallint, default = 0, comment = "smallint 带默认值"},
			#schField{name = int_val, dbType = ?pg_integer, default = 42, comment = "integer 带默认值"},
			#schField{name = int_alias, dbType = ?pg_int, default = 0, comment = "int (integer 别名)"},
			#schField{name = big_val, dbType = ?pg_bigint, default = 0, erlType = "non_neg_integer()", comment = "bigint + 自定义 erlType"},
			#schField{name = float_val, dbType = ?pg_float, default = 0.0, comment = "float 单精度"},
			#schField{name = double_val, dbType = ?pg_double, default = 0.0, erlType = "float()", comment = "double 双精度 + erlType"},
			#schField{name = money, dbType = ?pg_numeric(12, 2), default = 0, erlType = "number()", comment = "numeric(12,2) 金额"},
			#schField{name = ratio, dbType = ?pg_numeric(5, 4), comment = "numeric(5,4) 比率"}
		]
	}.

%%% ===================================================================
%%% text_samples — 覆盖所有文本类型
%%% ===================================================================
text_samples() ->
	#schema{
		repr = record,
		comment = "文本类型全覆盖",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "主键"},
			#schField{name = content, dbType = ?pg_text, default = <<>>, comment = "text 无限长文本"},
			#schField{name = short_name, dbType = ?pg_varchar(32), opts = [?pg_not_null, ?pg_unique], comment = "varchar(32) 非空唯一"},
			#schField{name = long_desc, dbType = ?pg_varchar(2048), default = <<"">>, comment = "varchar(2048) 长描述"},
			#schField{name = country_code, dbType = ?pg_char(2), default = <<"CN">>, comment = "char(2) 国家代码"},
			#schField{name = fixed_code, dbType = ?pg_char(6), opts = [?pg_not_null], comment = "char(6) 定长编码"},
			#schField{name = trace_id, dbType = ?pg_uuid, erlType = "binary()", comment = "uuid 跟踪ID"},
			#schField{name = client_ip, dbType = ?pg_inet, erlType = "binary()", comment = "inet 客户端IP"}
		]
	}.

%%% ===================================================================
%%% time_samples — 覆盖所有时间日期类型
%%% ===================================================================
time_samples() ->
	#schema{
		repr = map,
		comment = "时间日期类型全覆盖 (map 表示)",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "主键"},
			#schField{name = table_name, dbType = ?pg_varchar(64), default = <<"time_samples">>, opts = [?pg_not_null], comment = "所属表名"},
			#schField{name = created_at, dbType = ?pg_timestamptz, comment = "timestamptz 含时区"},
			#schField{name = updated_at, dbType = ?pg_timestamp, comment = "timestamp 不含时区"},
			#schField{name = birth_date, dbType = ?pg_date, erlType = "binary()", comment = "date 仅日期"},
			#schField{name = alarm_time, dbType = ?pg_time, erlType = "binary()", comment = "time 仅时间"},
			#schField{name = expire_at, dbType = ?pg_timestamptz, erlType = "binary() | undefined", comment = "可空的时间戳 + erlType"}
		]
	}.

%%% ===================================================================
%%% json_binary_samples — 覆盖 json/jsonb/bytea 及 codec
%%% ===================================================================
json_binary_samples() ->
	#schema{
		repr = record,
		comment = "JSON与二进制类型覆盖",
		tbCache = #tbCache{},
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "主键"},
			#schField{name = config, dbType = ?pg_json, default = #{}, codec = ?codec_json, erlType = "map()", comment = "json 保留原始格式"},
			#schField{name = metadata, dbType = ?pg_jsonb, default = #{}, codec = ?codec_json, erlType = "map()", comment = "jsonb 支持索引"},
			#schField{name = payload, dbType = ?pg_jsonb, codec = ?codec_json, erlType = "map() | list()", comment = "jsonb 也可能是列表"},
			#schField{name = avatar, dbType = ?pg_bytea, erlType = "binary()", comment = "bytea 二进制头像"},
			#schField{name = snapshot, dbType = ?pg_bytea, default = <<>>, comment = "bytea 带默认空二进制"},
			#schField{name = settings, dbType = ?pg_jsonb, default = #{auto_login => true}, codec = ?codec_json, erlType = "#{atom() => term()}", comment = "jsonb 带复杂默认值 + 精确 erlType"},
			%% === codec 覆盖 ===
			#schField{name = json_as_text, dbType = ?pg_text, default = #{}, codec = ?codec_json, erlType = "map()", comment = "text 列存 JSON, codec_json 编解码"},
			#schField{name = term_readable, dbType = ?pg_text, codec = ?codec_term_str, erlType = "term()", comment = "text 列存 Erlang term 可读字符串, codec_term_str"},
			#schField{name = term_blob, dbType = ?pg_bytea, codec = ?codec_term_binary, erlType = "term()", comment = "bytea 列存 Erlang term 二进制, codec_term_binary"},
			#schField{name = status_name, dbType = ?pg_varchar(32), default = active, codec = ?codec_atom, erlType = "atom()", comment = "varchar 列存 atom, codec_atom 编解码"},
			#schField{name = runtime_cache, dbType = ?pg_bytea, default = #{dirty => false}, codec = ?codec_temp, erlType = "map()", comment = "仅应用层临时缓存字段, codec_temp 不入库"},
			#schField{name = custom_blob, dbType = ?pg_bytea, default = #{source => demo}, codec = ?codec_custom(ePgdb, demo_custom_codec, demo_tag), erlType = "map()", comment = "bytea 列使用 ePgdb:demo_custom_codec/5 做自定义编解码"},
			#schField{name = dirty_flag, dbType = ?pg_integer, default = 0, codec = ?codec_temp, erlType = "intrger()", comment = "仅应用层临时缓存字段, codec_temp 不入库"}
		]
	}.

%%% ===================================================================
%%% composite_samples — 覆盖数组、枚举类型
%%% ===================================================================
composite_samples() ->
	#schema{
		repr = record,
		comment = "复合类型覆盖: array, enum",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "主键"},
			#schField{name = tags, dbType = ?pg_array(?pg_text), default = [], comment = "text[] 文本数组"},
			#schField{name = scores, dbType = ?pg_array(?pg_integer), default = [], erlType = "[integer()]", comment = "integer[] + erlType"},
			#schField{name = matrix, dbType = ?pg_array(?pg_double), default = [], erlType = "[float()]", comment = "double[] 浮点数组"},
			#schField{name = uuids, dbType = ?pg_array(?pg_uuid), default = [], erlType = "[binary()]", comment = "uuid[] UUID 数组"},
			#schField{name = status, dbType = ?pg_enum_atom, default = active, codec = ?codec_atom, comment = "enum atom 模式"},
			#schField{name = role, dbType = ?pg_enum_binary, default = <<"user">>, comment = "enum binary 模式"},
			#schField{name = priority, dbType = ?pg_enum_atom, default = normal, codec = ?codec_atom, erlType = "low | normal | high | critical", comment = "enum atom + 联合 erlType"}
		]
	}.

%%% ===================================================================
%%% constraint_samples — 覆盖所有约束选项
%%% ===================================================================
constraint_samples() ->
	#schema{
		repr = map,
		comment = "约束选项全覆盖 (map 表示)",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "主键约束"},
			#schField{name = table_name, dbType = ?pg_varchar(64), default = <<"constraint_samples">>, opts = [?pg_not_null], comment = "所属表名"},
			#schField{name = owner_id, dbType = ?pg_bigint, opts = [?pg_not_null, ?pg_references(numeric_samples, id, cascade)], comment = "外键 + cascade"},
			#schField{name = group_id, dbType = ?pg_bigint, opts = [?pg_references(numeric_samples, id, set_null)], comment = "外键 + set_null"},
			#schField{name = ref_id, dbType = ?pg_bigint, opts = [?pg_references(numeric_samples, id)], comment = "外键 无级联 (默认 NO ACTION)"},
			#schField{name = email, dbType = ?pg_varchar(128), opts = [?pg_not_null, ?pg_unique, ?pg_index], comment = "非空 + 唯一 + 索引"},
			#schField{name = score, dbType = ?pg_integer, default = 0, opts = [?pg_check("score >= 0 AND score <= 99999")], comment = "check 约束"},
			#schField{name = level, dbType = ?pg_smallint, default = 1, opts = [?pg_not_null, ?pg_check("level >= 1"), ?pg_index], comment = "多约束组合: 非空+check+索引"},
			#schField{name = nickname, dbType = ?pg_varchar(64), opts = [?pg_index], comment = "仅索引"},
			#schField{name = data, dbType = ?pg_jsonb, default = #{}, codec = ?codec_json, erlType = "map()", comment = "jsonb 数据"}
		]
	}.

%%% ===================================================================
%%% erl_type_showcase — 专门展示各种 erlType 写法
%%% ===================================================================
erl_type_showcase() ->
	#schema{
		repr = record,
		comment = "erlType 赋值方式展示",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "主键"},
			%% 基础类型
			#schField{name = count, dbType = ?pg_integer, erlType = "non_neg_integer()", comment = "非负整数"},
			#schField{name = rate, dbType = ?pg_double, erlType = "float()", comment = "float"},
			#schField{name = flag, dbType = ?pg_boolean, erlType = "boolean()", comment = "布尔"},
			%% 联合类型
			#schField{name = value, dbType = ?pg_bigint, erlType = "integer() | undefined", comment = "可空整数"},
			#schField{name = label, dbType = ?pg_text, erlType = "binary() | <<>>", comment = "二进制或空串"},
			%% 复杂类型
			#schField{name = profile, dbType = ?pg_jsonb, codec = ?codec_json, erlType = "#{binary() => term()}", comment = "map 精确 key 类型"},
			#schField{name = history, dbType = ?pg_jsonb, codec = ?codec_json, erlType = "[map()]", comment = "map列表"},
			#schField{name = coords, dbType = ?pg_array(?pg_double), erlType = "[float()]", comment = "坐标浮点列表"},
			#schField{name = ids, dbType = ?pg_array(?pg_bigint), erlType = "[pos_integer()]", comment = "正整数列表"},
			%% 枚举精确类型
			#schField{name = state, dbType = ?pg_enum_atom, default = idle, codec = ?codec_atom, erlType = "idle | running | stopped", comment = "有限atom联合"},
			#schField{name = color, dbType = ?pg_enum_binary, default = <<"red">>, erlType = "binary()", comment = "有限binary联合"},
			%% 自定义 record / tuple 类型
			#schField{name = position, dbType = ?pg_jsonb, default = #{x => 0, y => 0}, codec = ?codec_json, erlType = "#{x => number(), y => number()}", comment = "坐标map类型"},
			#schField{name = extra, dbType = ?pg_jsonb, default = null, codec = ?codec_json, erlType = "term()", comment = "完全通用 term"}
		]
	}.
