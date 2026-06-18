%%%-------------------------------------------------------------------
%%% @doc ePgdb schema 定义。
%%% Opts 约束:
%%%   primary_key
%%%   not_null
%%%   unique
%%%   {references, {Table, Column}}
%%%   {references, {Table, Column, OnDelete}}
%%%   {check, Expr}
%%%   {index, true}
%%%   {codec, {EncoderFun, DecoderFun}}
%%%
%%% OnDelete 可选值：cascade | set_null | restrict | no_action
%%%-------------------------------------------------------------------

-ifndef(PGDB_SCHEMA_HRL).
-define(PGDB_SCHEMA_HRL, true).

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
	codec = undefined,   %% undefined | json | term_str | term_binary | atom | temp | {custom, M, F, A}
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

%% === 约束选项 ===

%% 主键约束。每张表应有且仅有一个主键字段。
%% PostgreSQL: PRIMARY KEY
-define(pg_primary_key, primary_key).

%% 非空约束。字段不允许为 NULL。
%% PostgreSQL: NOT NULL
-define(pg_not_null, not_null).

%% 唯一约束。字段值在整张表中必须唯一（NULL 除外）。
%% PostgreSQL: UNIQUE
-define(pg_unique, unique).

%% 默认值。当 INSERT 未提供该字段时使用此值。
%% PostgreSQL: DEFAULT <Value>
%% 示例: ?pg_default(0), ?pg_default(<<"active">>), ?pg_default(false)
-define(pg_default(Value), {default, Value}).

%% 外键约束（不指定级联行为，默认 NO ACTION）。
%% PostgreSQL: REFERENCES <Table>(<Column>)
%% 示例: ?pg_references(players, id)
-define(pg_references(Table, Column), {references, {Table, Column}}).

%% 外键约束（指定级联行为）。
%% PostgreSQL: REFERENCES <Table>(<Column>) ON DELETE <OnDelete>
%% OnDelete 可选值: cascade | set_null | restrict | no_action
%% 示例: ?pg_references(players, id, cascade)
-define(pg_references(Table, Column, OnDelete), {references, {Table, Column, OnDelete}}).

%% CHECK 约束。字段值必须满足给定的 SQL 表达式。
%% PostgreSQL: CHECK (<Expr>)
%% 示例: ?pg_check("level >= 0 AND level <= 999")
-define(pg_check(Expr), {check, Expr}).

%% 索引标记。为该字段创建普通 B-tree 索引。
%% PostgreSQL: CREATE INDEX ON <table> (<column>)
-define(pg_index, {index, true}).

%% === 编解码策略 (codec) ===

%% 默认：按 dbType 走内置编解码逻辑，不做额外转换。
-define(codec_undefined, undefined).

%% JSON：字段实际存储为 text/bytea，Erlang 侧使用 map()/list()。
%% encode: jiffy:encode/1  decode: jiffy:decode/2
-define(codec_json, json).

%% Term 可读字符串：字段存储为 text，Erlang 侧使用任意 term()。
%% encode: io_lib:format("~tp")  decode: erl_scan + erl_parse
-define(codec_term_str, term_str).

%% Term 二进制：字段存储为 bytea，Erlang 侧使用任意 term()。
%% encode: term_to_binary/1  decode: binary_to_term/1
-define(codec_term_binary, term_binary).

%% Atom：字段存储为 text/varchar，Erlang 侧使用 atom()。
%% encode: atom_to_binary/2  decode: binary_to_existing_atom/2
-define(codec_atom, atom).

%% Temp：字段仅存在于 Erlang record/map 中，不参与建表、插入、更新等数据库路径。
-define(codec_temp, temp).

%% Custom：自定义编解码，声明格式 {custom, M, F, A}。
%% 要求 dbType = bytea，数据库默认值固定为 null，Erlang 默认值可自由指定。
%% encode/decode 会调用 M:F(encode/decode, Table, Field, A, Value)。
-define(codec_custom(M, F, A), {custom, M, F, A}).

%% =====================================================================
%% 数值类型
%% =====================================================================

%% 4 字节有符号整数，范围 -2,147,483,648 ~ 2,147,483,647。
%% PostgreSQL: INTEGER (别名 INT, INT4)
%% Erlang 映射: integer()
-define(pg_integer, integer).

%% integer 的别名。
-define(pg_int, int).

%% 8 字节有符号整数，范围 -9,223,372,036,854,775,808 ~ 9,223,372,036,854,775,807。
%% PostgreSQL: BIGINT (别名 INT8)
%% Erlang 映射: integer()
-define(pg_bigint, bigint).

%% 2 字节有符号整数，范围 -32,768 ~ 32,767。
%% PostgreSQL: SMALLINT (别名 INT2)
%% Erlang 映射: integer()
-define(pg_smallint, smallint).

%% 4 字节自增整数，自动创建序列，常用于主键。
%% PostgreSQL: SERIAL (等价于 INTEGER + 自增序列)
%% Erlang 映射: integer()
-define(pg_serial, serial).

%% 8 字节自增整数，自动创建序列，适用于大表主键。
%% PostgreSQL: BIGSERIAL (等价于 BIGINT + 自增序列)
%% Erlang 映射: integer()
-define(pg_bigserial, bigserial).

%% 4 字节单精度浮点数，约 6 位十进制精度。
%% PostgreSQL: REAL (别名 FLOAT4)
%% Erlang 映射: float()
-define(pg_float, float).

%% 8 字节双精度浮点数，约 15 位十进制精度。
%% PostgreSQL: DOUBLE PRECISION (别名 FLOAT8)
%% Erlang 映射: float()
-define(pg_double, double).

%% 精确数值类型，支持指定精度和小数位数，适合存储金额等精确数值。
%% PostgreSQL: NUMERIC(Precision, Scale)
%% Precision: 总位数，Scale: 小数位数
%% Erlang 映射: number()
%% 示例: ?pg_numeric(10, 2) → 最多 10 位数字，其中 2 位小数
-define(pg_numeric(Precision, Scale), {numeric, Precision, Scale}).

%% =====================================================================
%% 文本类型
%% =====================================================================

%% 变长文本，无长度限制。
%% PostgreSQL: TEXT
%% Erlang 映射: binary()
-define(pg_text, text).

%% 变长文本，最大长度为 Len 个字符。
%% PostgreSQL: VARCHAR(Len) (别名 CHARACTER VARYING)
%% Erlang 映射: binary()
%% 示例: ?pg_varchar(64)
-define(pg_varchar(Len), {varchar, Len}).

%% 定长文本，固定长度为 Len 个字符，不足部分用空格填充。
%% PostgreSQL: CHAR(Len) (别名 CHARACTER)
%% Erlang 映射: binary()
%% 示例: ?pg_char(2) → 固定 2 个字符的国家代码等
-define(pg_char(Len), {char, Len}).

%% UUID 类型，128 位通用唯一标识符，存储格式如 "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"。
%% PostgreSQL: UUID
%% Erlang 映射: binary() (36 字节的字符串形式)
-define(pg_uuid, uuid).

%% IPv4 或 IPv6 网络地址。
%% PostgreSQL: INET
%% epgsql 默认 Erlang 映射: inet:ip_address()
%% 推荐传值: {127,0,0,1} | {0,0,0,0,0,0,0,1}
-define(pg_inet, inet).

%% =====================================================================
%% 布尔类型
%% =====================================================================

%% 布尔值，true / false。
%% PostgreSQL: BOOLEAN
%% Erlang 映射: boolean() (true | false)
-define(pg_boolean, boolean).

%% =====================================================================
%% 时间日期类型
%% =====================================================================

%% 日期和时间，不含时区，精度到微秒。
%% PostgreSQL: TIMESTAMP (别名 TIMESTAMP WITHOUT TIME ZONE)
%% epgsql 默认 Erlang 映射: {{Year, Month, Day}, {Hour, Minute, SecondFloat}}
%% 也可传 erlang:timestamp() 三元组
-define(pg_timestamp, timestamp).

%% 日期和时间，含时区，精度到微秒。推荐优先使用此类型。
%% PostgreSQL: TIMESTAMPTZ (别名 TIMESTAMP WITH TIME ZONE)
%% epgsql 默认 Erlang 映射: {{Year, Month, Day}, {Hour, Minute, SecondFloat}}
%% 也可传 erlang:timestamp() 三元组
-define(pg_timestamptz, timestamptz).

%% 仅日期，无时间部分。
%% PostgreSQL: DATE
%% epgsql 默认 Erlang 映射: {Year, Month, Day}
-define(pg_date, date).

%% 仅时间，无日期部分。
%% PostgreSQL: TIME (别名 TIME WITHOUT TIME ZONE)
%% epgsql 默认 Erlang 映射: {Hour, Minute, SecondFloat}
-define(pg_time, time).

%% =====================================================================
%% JSON / 二进制类型
%% =====================================================================

%% JSON 文本存储，保留原始格式（空格、键序等）。
%% PostgreSQL: JSON
%% epgsql 默认返回: binary() JSON 文本
%% ePgdb 在 schema 命中该字段时会用 jiffy 编码/解码，业务侧通常可直接传 map() | list() | binary()
-define(pg_json, json).

%% JSON 二进制存储，解析后存储，支持索引和丰富的查询操作符。推荐优先使用。
%% PostgreSQL: JSONB
%% epgsql 默认返回: binary() JSON 文本
%% ePgdb 在 schema 命中该字段时会用 jiffy 编码/解码，业务侧通常可直接传 map() | list() | binary()
-define(pg_jsonb, jsonb).

%% 二进制字节串，用于存储文件、图片等原始二进制数据。
%% PostgreSQL: BYTEA
%% Erlang 映射: binary()
-define(pg_bytea, bytea).

%% =====================================================================
%% 复合类型
%% =====================================================================

%% 数组类型，元素类型由 InnerType 指定。
%% PostgreSQL: <InnerType>[] (如 TEXT[], INTEGER[])
%% Erlang 映射: [ErlType] (列表，元素类型由 InnerType 推导)
%% 示例: ?pg_array(?pg_text) → TEXT[]
%%        ?pg_array(?pg_integer) → INTEGER[]
-define(pg_array(InnerType), {array, InnerType}).

%% 枚举类型 (atom 模式)。存储为文本，解码时自动转为 Erlang atom。
%% PostgreSQL: TEXT (存储层面)
%% Erlang 映射: atom() (编码: atom_to_binary，解码: binary_to_existing_atom)
%% 注意: 解码依赖 binary_to_existing_atom，需确保目标 atom 已存在。
-define(pg_enum_atom, {enum, atom}).

%% 枚举类型 (binary 模式)。存储和使用均为二进制字符串。
%% PostgreSQL: TEXT (存储层面)
%% Erlang 映射: binary()
%% 示例: default = <<"idle">>, 值为 <<"active">>, <<"banned">> 等
-define(pg_enum_binary, {enum, binary}).

-endif.