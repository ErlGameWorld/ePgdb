-ifndef(ePgdb_h__).
-define(ePgdb_h__, true).

%%%===================================================================
%%% 类型定义
%%%===================================================================

%% @type name() :: atom() | binary() | string().
%% 通用名称类型，用于表名、字段名、数据库名等标识符。
%% 推荐使用 atom（如 players、id），内部会转为 binary 拼入 SQL。
-type name() :: atom() | binary() | string().

%% @type fieldName() :: name().
%% 字段名，等同于 name()。
-type fieldName() :: name().

%% @type jsonPathSegment() / jsonPath().
%% JSON 路径段支持字段名或数组下标。
%% 单层路径可直接传一个路径段；多层路径传路径段列表。
-type jsonPathSegment() :: name() | integer().
-type jsonPath() :: jsonPathSegment() | [jsonPathSegment()].

%% @type jsonInput().
%% JSON 写入值默认按 Erlang term 经 jiffy:encode 编码。
%% 如需传入已经编码好的原始 JSON 文本，可使用 {raw_json, Binary}。
-type jsonInput() :: term() | {raw_json, binary()}.

%% @type rowMap() :: map().
%% 查询结果行，通常 key 为字段 atom，value 为对应值。
%% 例: #{id => 1, name => <<"Alice">>}
-type rowMap() :: map().

%% @type compareOp().
%% WHERE 条件中支持的比较操作符。
%% '>'  大于 | '>=' 大于等于 | '<'  小于 | '<=' 小于等于
%% '!=' 不等于 | '<>' 不等于（同 !=）
%% like  模式匹配（区分大小写） | ilike 模式匹配（不区分大小写）
-type compareOp() :: '>' | '>=' | '<' | '<=' | '!=' | '<>' | like | ilike.

%% @type whereValue().
%% WHERE 条件中字段对应的值，支持以下形式：
%%
%%   term()                       - 精确匹配，生成 field = $N（参数化，安全）
%%   null                         - 生成 field IS NULL
%%   not_null                     - 生成 field IS NOT NULL
%%   {compareOp(), term()}        - 比较运算，如 {'>', 10} 生成 field > $N
%%   {in, [term()]}              - IN 查询，如 {in, [1,2,3]} 生成 field IN ($1,$2,$3)
%%   {not_in, [term()]}          - NOT IN 查询
%%   {between, term(), term()}   - 范围查询，生成 field BETWEEN $N AND $M
%%   {jsonb_contains, map()}     - JSONB 包含查询，生成 field @> $N::jsonb
%%   {jsonb_key, Path, Op, Val}  - JSONB 路径查询，Path 为 atom/binary/list
%%                                  如 {jsonb_key, <<"vip">>, '=', true}
%%                                  生成 field->>'vip' = $N
%%   {raw, iodata()}             - ⚠️ 危险：原样拼入 SQL，不做参数化！
%%                                  仅用于框架内部或完全可信的静态 SQL 片段。
%%                                  禁止将用户输入放入 raw。
%%
%% 除 raw 外，所有值都通过 $N 参数绑定发送，天然防止 SQL 注入。
-type whereValue() :: term()| null| not_null| {compareOp(), term()}| {in, [term()]}| {not_in, [term()]}| {between, term(), term()}| {jsonb_contains, map() | list() | binary()}| {jsonb_key, term(), atom(), term()}| {raw, iodata()}.

%% @type whereMap() :: #{fieldName() => whereValue()}.
%% map 形式的 WHERE 条件，多个键之间为 AND 关系。
%% 例: #{level => {'>=', 10}, vip => true}
%%   → WHERE level >= $1 AND vip = $2
-type whereMap() :: #{term() => whereValue()}.

%% @type whereItem().
%% list 形式 WHERE 条件中的单个元素，支持三种写法：
%%   {'or', [whereMap()]}           - OR 分组，多个 map 之间为 OR
%%   {fieldName(), whereValue()}    - 单字段条件（二元组）
%%   {fieldName(), atom(), term()}  - 单字段条件（三元组，如 {level, '>', 10}）
-type whereItem() :: {'or', [whereMap()]} | {fieldName(), whereValue()} | {fieldName(), atom(), term()}.

%% @type whereClause() :: whereMap() | [whereItem()].
%% 完整的 WHERE 条件，可以是 map（纯 AND）或 list（支持 OR 组合）。
-type whereClause() :: whereMap() | [whereItem()].

%% @type orderByItem().
%% 排序项：单字段名（默认升序）或 {字段, asc|desc}。
-type orderByItem() :: fieldName() | {fieldName(), asc | desc}.

%% @type selectOpt().
%% select/3 的查询选项：
%%   {fields, [fieldName()]}        - 只返回指定字段，默认 *
%%   {order_by, orderByItem()}      - 排序，支持单字段或多字段列表
%%   {limit, pos_integer()}         - 限制返回行数
%%   {offset, non_neg_integer()}    - 跳过前 N 行
%%   {group_by, fieldName()|list()} - GROUP BY 分组
%%   {having, whereClause()}        - HAVING 过滤（配合 group_by 使用）
%%   {for_update, boolean()}        - 加行锁（事务内使用）
-type selectOpt() :: {fields, [fieldName()]}| {order_by, orderByItem() | [orderByItem()]}| {limit, pos_integer()}| {offset, non_neg_integer()}| {group_by, fieldName() | [fieldName()]}| {having, whereClause()}| {for_update, boolean()}.

%% @type pageOpt().
%% selectPage/5、分页扫描接口的额外选项：
%%   继承 selectOpt() 的所有选项，另外支持：
%%   {count_total, boolean()}  - 是否额外查询总行数，默认 false。
%%                               true: 额外执行 count(*)，返回 total/total_pages，按 page_size 取数。
%%                               false: 不查总数，仅用多取的一条判断 has_next，
%%                                      返回结果仍最多只有 page_size 条，total/total_pages 为 undefined。
%%   {start_after, term()}     - keyset 分页：从此值之后开始扫描
-type pageOpt() :: selectOpt() | {count_total, boolean()} | {start_after, term()}.

%% @type addColumnOpt().
%% addColumn/4 的字段选项：
%%   primary_key                 - 主键约束
%%   not_null                    - 非空约束
%%   unique                      - 唯一约束
%%   {default, term()}           - 字段默认值
%%   {not_null, boolean()}       - 是否 NOT NULL
%%   {references, {T, C}}        - 外键约束
%%   {references, {T, C, D}}     - 带 ON DELETE 的外键约束
%%   {check, iodata()}           - CHECK 约束
%%   {index, boolean()}          - 自动创建单列索引
-type addColumnOpt() ::
primary_key |
not_null |
unique |
{default, term()} |
{not_null, boolean()} |
{references, {name(), fieldName()}} |
{references, {name(), fieldName(), cascade | set_null | restrict | no_action}} |
{check, iodata()} |
{index, boolean()}.

%% @type indexOpt().
%% addIndex/3 的索引选项：
%%   {unique, boolean()}               - 是否唯一索引
%%   {name, name()}                    - 自定义索引名（默认自动生成）
%%   {method, btree | gin | gist | hash} - 索引方法，默认 btree
%%                                        gin 用于 JSONB/数组，gist 用于地理/范围
-type indexOpt() :: {unique, boolean()} | {name, name()} | {method, btree | gin | gist | hash}.

%% @type pageResult().
%% selectPage 返回的分页结果：
%%   page        - 当前页码（从 1 开始）
%%   page_size   - 每页大小
%%   total       - 总行数（count_total=true 时有值，否则 undefined）
%%   total_pages - 总页数（同上）
%%   has_next    - 是否有下一页。count_total=true 时由 total/page_size 推导；
%%                 count_total=false 可能返回true没有下一页数据 此时最后一页数据刚好是满的时候会出现这样的问题。
%%   rows        - 当前页的数据行列表
-type pageResult() :: #{page := pos_integer(), page_size := pos_integer(), total := non_neg_integer() | undefined, total_pages := non_neg_integer() | undefined, has_next := boolean(), rows := [rowMap()]}.

%% @type dbHost() / dbPort() / dbUser() / dbPassword() / dbName().
%% 数据库连接参数类型。
-type dbHost() :: binary() | string().
-type dbPort() :: pos_integer().
-type dbUser() :: name().
-type dbPassword() :: binary() | string().
-type dbName() :: name().

%% @type poolArg().
%% eFaw 工厂启动参数（内部使用）。
-type poolArg() :: {wMod, atom()} | {wArgs, wArgs()} | {wFCnt, pos_integer()} | {wKeepTime, pos_integer()} | {slowThreshold, integer() | infinity} | {filterFun, {module(), atom()}}.  %% eFaw.hrl fawOtp().

%% @type wArgs().
%% worker 额外连接参数（内部使用）。
-type wArgs() :: {tcpOpts, list()} |{ssl, boolean()} |{sslOpts, list()}.

%% 三目元算符
-define(CASE(Cond, Then, That), case Cond of true -> Then; _ -> That end).
-define(CASE(Expr, Expect, Then, ExprRet, That), case Expr of Expect -> Then; ExprRet -> That end).

%% IF-DO表达式
-define(IF(IFTure, DoThat), (IFTure) andalso (DoThat)).

-define(PgErr(Format, Args), error_logger:error_msg(Format, Args)).
-define(PgWarn(Format, Args), error_logger:warning_msg(Format, Args)).

-endif.

