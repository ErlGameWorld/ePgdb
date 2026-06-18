%%%-------------------------------------------------------------------
%%% @doc pgdb 公共工具函数。
%%%-------------------------------------------------------------------
-module(pgdbUtils).

-export([
	isValidName/1,
	getOpt/3,
	makeName/1,
	toAtom/1,
	quoteIdent/1,
	quoteLiteral/1,
	buildColumnRefs/1
]).

%% @doc 数据库名或者表名/字段名的合法性检查：必须以字母或下划线开头，后续字符可以是字母、数字、下划线、点或连字符，长度限制 1-63 字节。
isValidName(Name) ->
	(is_binary(Name) andalso byte_size(Name) > 1 andalso byte_size(Name) =< 63) andalso re:run(Name, <<"^[a-z_][A-Za-z0-9_.-]*$">>, [{capture, none}]) =:= match.

%% @doc 将 atom/binary/iolist 统一转为裸 binary，不做任何转义。
%% 用于需要原始名称文本的场景，如拼接索引名。
makeName(Value) when is_atom(Value) -> atom_to_binary(Value, utf8);
makeName(Value) when is_binary(Value) -> Value;
makeName(Value) when is_list(Value) -> iolist_to_binary(Value).

toAtom(Value) when is_atom(Value) -> Value;
toAtom(Value) when is_binary(Value) -> binary_to_atom(Value);
toAtom(Value) when is_list(Value) -> list_to_atom(Value).

%% @doc 获取配置选项
getOpt(Key, Opts, Def) ->
	case lists:keyfind(Key, 1, Opts) of
		false ->
			Def;
		{_Key, Value} ->
			Value
	end.

%% @doc 将标识符（表名/字段名/数据库名）用双引号包裹并转义内部双引号。
%% 例: players -> <<"\"players\"">>, 防止标识符与 PostgreSQL 保留字冲突或含特殊字符。
%% 注意: schema 定义的表名/字段名是安全 atom，pgdbQuery 内部不需要调此函数；
%% 主要用于 CREATE DATABASE 等接受外部输入标识符的场景。
quoteIdent(Value) ->
	Bin = makeName(Value),
	<<$", (escapeIdent(Bin))/binary, $">>.

%% @doc 将字符串值用单引号包裹并转义，生成安全的 SQL 字面量。
%% 转义反斜杠和单引号，使用 E'' 语法。拒绝包含 \0 的输入。
%% 例: <<"hello'world">> -> [<<"E'">>, <<"hello''world">>, <<"'">>]
%% 用于 DDL DEFAULT 值、JSONB 路径字面值等直接拼入 SQL（非参数化）的场景。
quoteLiteral(Value) when is_binary(Value) ->
	ensureNoZeroByte(Value),
	EscapedBackslash = binary:replace(Value, <<$\\>>, <<$\\, $\\>>, [global]),
	Escaped = binary:replace(EscapedBackslash, <<$'>>, <<$', $'>>, [global]),
	[<<"E'">>, Escaped, <<"'">>];
quoteLiteral(Value) when is_list(Value) ->
	quoteLiteral(iolist_to_binary(Value)).

%% @doc 将 schema 字段列表转为 [{Index, ColumnName}] 的位置索引映射。
%% 用于按序号快速定位字段名，供结果行解码使用。
buildColumnRefs(Cols) ->
	buildColumnRefs(Cols, 1, []).

buildColumnRefs([], _Index, Acc) ->
	lists:reverse(Acc);
buildColumnRefs([Col | Rest], Index, Acc) ->
	buildColumnRefs(Rest, Index + 1, [{Index, makeName(element(2, Col))} | Acc]).

%% @doc 转义 SQL 标识符中的双引号: " -> ""。
escapeIdent(Bin) ->
	binary:replace(Bin, <<$">>, <<$", $">>, [global]).

%% @doc 检查 binary 是否含 \0 字节，有则报错（PostgreSQL 不接受字面值中的零字节）。
ensureNoZeroByte(Bin) ->
	case binary:match(Bin, <<0>>) of
		nomatch -> ok;
		_ -> erlang:error({invalid_sql_literal, zero_byte})
	end.
