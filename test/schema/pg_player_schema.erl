%%%-------------------------------------------------------------------
%%% @doc 游戏 schema 定义模块。
%%% 每个函数名即表名，返回 #schema{} record。
%%%-------------------------------------------------------------------
-module(pg_player_schema).

-compile([export_all, nowarn_export_all]).

-include("pgdbSchema.hrl").


players() ->
	#schema{
		repr = record,
		comment = "玩家主表",
		tbCache = #tbCache{},
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "玩家唯一ID"},
			#schField{name = name, dbType = ?pg_varchar(64), opts = [?pg_not_null, ?pg_unique], comment = "玩家名字"},
			#schField{name = level, dbType = ?pg_integer, default = 1, comment = "等级"},
			#schField{name = gold, dbType = ?pg_bigint, default = 0, comment = "金币"},
			#schField{name = vip, dbType = ?pg_boolean, default = false, comment = "是否VIP"},
			#schField{name = status, dbType = ?pg_enum_binary, default = <<"idle">>, comment = "状态"},
			#schField{name = profile, dbType = ?pg_jsonb, default = #{}, codec = ?codec_json, erlType = "map()", comment = "玩家档案JSON"},
			#schField{name = tags, dbType = ?pg_array(?pg_text), default = [], comment = "标签列表"},
			#schField{name = created_at, dbType = ?pg_timestamptz, comment = "创建时间"}
		]
	}.

items() ->
	#schema{
		repr = record,
		comment = "道具表",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key], comment = "道具唯一ID"},
			#schField{name = player_id, dbType = ?pg_bigint, opts = [?pg_not_null, ?pg_references(players, id, cascade)], comment = "所属玩家ID"},
			#schField{name = item_type, dbType = ?pg_varchar(32), opts = [?pg_not_null], codec = ?codec_atom, erlType = "atom()", comment = "道具类型 (atom: sword/shield/potion)"},
			#schField{name = count, dbType = ?pg_integer, default = 1, comment = "数量"},
			#schField{name = attrs, dbType = ?pg_jsonb, codec = ?codec_json, erlType = "map()", comment = "扩展属性"},
			#schField{name = state_data, dbType = ?pg_bytea, codec = ?codec_term_binary, erlType = "term()", comment = "道具状态 (Erlang term 二进制序列化)"}
		]
	}.