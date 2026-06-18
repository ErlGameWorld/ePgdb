# ePgdb - Erlang 游戏服 PostgreSQL 工具库

灵活的 PostgreSQL 数据库操作库，专为 Erlang 游戏服务器设计。

它的核心目标不是再包一层数据库驱动，而是把游戏服里最烦、最容易长期失控的那部分数据库维护成本压下去：

- 不需要业务层到处手写和维护 SQL
- 不需要每次字段调整都去补一串手写 `ALTER TABLE`
- 不需要在 Erlang 记录、map 结构、表字段定义之间反复做人肉同步
- 不需要在 JSON、atom、term、array 这些字段上手写重复的编解码逻辑

你更接近的工作方式是：先把数据结构写清楚，再让 ePgdb 负责把它稳定地落到 PostgreSQL 上。

## 为什么适合游戏服

- **免手写 SQL**：大部分日常 CRUD、分页、条件过滤、JSONB 操作都直接走 API，不必维护成片 SQL 模板。
- **表结构跟着代码演进**：字段定义写在 schema 中，新增字段、调整字段类型、补默认值时，运行时可以按 schema 自动同步，而不是手工追一堆
  DDL 脚本。
- **数据结构自适应**：同一套 schema 同时服务 record/map、where 条件编码、结果解码、JSON/term/atom
  转换，减少“代码字段变了，数据库读写逻辑忘了改”的漂移。
- **适合频繁迭代**：策划和程序经常改表、加字段、改 JSON 结构时，不需要每轮都先回头梳理一遍 SQL 层。
- **更适合长期维护**：项目表一多、字段一多，真正贵的不是写一条 SQL，而是保证几个月后还有人能安全改动。ePgdb 把这部分重复劳动前置进
  schema 和统一 API。

## 适用场景 / 不适用场景

### 更适合的场景

- **游戏服主业务表**：玩家、背包、邮件、任务、排行榜快照、活动状态这类结构相对稳定、字段持续演进、又需要长期维护的业务表。
- **Schema 和代码要一起演进的项目**：开发期经常加字段、改默认值、补 JSON 结构，希望表结构调整能直接跟着代码走，而不是额外维护一套
  DDL 脚本体系。
- **业务数据类型不只是纯标量**：表里有 JSON、atom、term、array、枚举值，需要统一编解码，不想把这些细节散落在每个查询点。
- **团队更在意长期维护成本**：不是追求把单条 SQL 写到最极限，而是希望半年后还敢安全改表、改字段、改查询。
- **中后台或起服加载也走同一套数据层**：分页扫描、批量装载、事务更新、自省和迁移都希望复用同一层 API。

### 不太适合的场景

- **把它当成通用 ORM**：ePgdb 不是那种面向任意业务域、自动推断关系、自动生成所有查询的全功能 ORM。它更像一套面向游戏服场景的
  schema 驱动数据库工具。
- **复杂报表和重分析 SQL**：多层 CTE、窗口函数、复杂聚合、跨多张大表的分析查询，通常还是直接写原生 SQL 更清晰。
- **高度异构、字段完全不可控的数据模型**：如果表结构本身没有稳定 schema，或者业务方不愿意维护字段定义，这套方案的优势会明显下降。
- **已经有成熟迁移链路的大型通用平台**：如果团队已经围绕 Flyway / Liquibase / 自研 DDL 平台形成严格流程，ePgdb
  的自动同步未必应该替代那套体系。
- **外部输入直接决定枚举 atom 的场景**：当前 atom codec 使用 `binary_to_atom/2`，值域必须受控，不适合把不可信开放输入直接映射成
  atom 字段。

### 这套方案的缺点

- **需要维护 schema**：你少维护了很多 SQL 和 DDL，但前提是愿意把字段定义、默认值、codec 认真写进 schema。
- **抽象不是零成本**：简单 CRUD 会更省事，但一旦遇到特别复杂的查询，还是要回到原生 SQL。
- **自动同步要有边界意识**：它适合开发期和明确受控的发版流程，不代表任何场景下都应该无脑在线改表。
- **团队需要接受 schema 驱动思路**：如果开发习惯完全是“先写 SQL、后补代码结构”，那这套方式需要一点迁移成本。

## 为什么比手写 SQL 更省维护成本

手写 SQL 真正昂贵的地方，通常不是第一次写出来，而是后续持续演进时的维护链条。

### 手写 SQL 的常见维护链条

假设玩家表新增一个 `last_login_at` 字段，传统方式通常要同时改这些地方：

1. 建表 SQL 或迁移脚本。
2. 可能存在的 `ALTER TABLE` 发版脚本。
3. insert SQL。
4. update SQL。
5. select 字段列表。
6. where 条件里的字段转换。
7. 返回结果解码。
8. 相关 record/map 结构。

如果字段还有 JSON、atom、数组或 term 编解码，维护点会继续增加。最容易出问题的不是“不会写 SQL”，而是改漏一个点，最后出现：

- 表字段已经加了，但 insert 没带上
- update 改了，但查询解码没改
- 写入按 binary，查询按 atom
- 业务 record 已变更，但 where 条件编码仍沿用旧逻辑

### ePgdb 想减少的就是这类重复维护

在 ePgdb 里，这些信息尽量收拢在 schema：

- 字段定义
- 默认值
- 类型信息
- codec 规则
- record / map 表示

然后由统一 API 去复用它：

- `syncSchema/1` 负责结构补齐
- `insert/update/upsert` 负责写入编码
- `select/get` 负责结果解码
- `where` 条件负责按字段类型做参数转换

也就是说，加一个字段时，主要工作会尽量收敛成：

1. 改 schema。
2. 重新生成 `dbSchemaDef`。
3. 在受控流程中执行 `syncSchema/1` 或迁移。
4. 业务代码直接使用新字段。

这并不意味着“以后完全不需要 SQL”，而是把最常见、最重复、最容易漂移的那部分维护成本从散点改动，收敛成以 schema 为中心的一条链路。

### 不是说手写 SQL 不好，而是维护目标不一样

- 如果你在写特别复杂的查询，原生 SQL 往往更直接。
- 如果你在维护一套会长期演进的游戏服业务表，schema 驱动通常更省人。

所以 ePgdb 的定位不是“替代所有 SQL”，而是尽量把**高频业务表的长期维护成本**压下来。

## 特性

- **工厂工人调度** - 基于 eFaw 工厂模式分发数据库任务，worker 持久持有连接并自动重连
- **Schema 驱动开发** - 直接在 Erlang 代码中定义表结构、字段类型、默认值、codec 和 Erlang 类型
- **免手写 SQL 的日常开发路径** - insert / select / update / delete / upsert / jsonb 操作都可直接走 API
- **动态 DDL 与自动同步** - 运行时添加/删除/重命名字段、修改类型，并可按 schema 自动补齐缺失结构
- **统一 Query Builder** - 支持 `=, >, <, >=, <=, !=, IN, BETWEEN, LIKE, ILIKE, IS NULL, OR` 等条件组合
- **字段级编解码** - JSONB、atom、term_binary、term_str、array 等字段按 schema 统一编码/解码
- **事务支持** - 自动提交/回滚，并支持显式事务连接回调
- **批量操作** - batchInsert、batchDeleteByKey
- **分页加载** - selectPage, foreachRows, foldRows, foreachByKey, foldByKey
- **Schema 迁移** - 版本化数据库迁移（前进/回滚）
- **Schema 自省** - 查看表列表、表结构、主键、唯一键、外键、索引

## 文档

- 迁移系统详解见 docs/migration-guide.md
- Schema 格式、字段类型和转换规则见 docs/schema-guide.md
- pgdbSchema 类型与 epgsql 返回/传参对照见 docs/epgsql-type-mapping.md
- epgsql 连接参数透传与 ePgdb 启动参数约定见 docs/epgsql-connect-options.md
- 性能测试结果与分析见 docs/performance-analysis.md

## 典型游戏服开发流程

下面用一个比较贴近游戏服的例子，把这套工具最常见的使用路径串起来。

### 第 1 步：先把表结构写成 schema

假设你要落玩家主表和玩家道具表。和传统方式先写 SQL 不一样，这里先把数据结构写在 Erlang schema 里：

```erlang
-module(pg_player_schema).
-include("pgdbSchema.hrl").
-compile([export_all, nowarn_export_all]).

players() ->
	#schema{
		repr = record,
		comment = "玩家主表",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key]},
			#schField{name = name, dbType = ?pg_varchar(64), opts = [?pg_not_null, ?pg_unique]},
			#schField{name = level, dbType = ?pg_integer, default = 1},
			#schField{name = gold, dbType = ?pg_bigint, default = 0},
			#schField{name = vip, dbType = ?pg_boolean, default = false},
			#schField{name = profile, dbType = ?pg_jsonb, default = #{}, codec = ?codec_json, erlType = "map()"}
		]
	}.

items() ->
	#schema{
		repr = record,
		comment = "玩家道具表",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key]},
			#schField{name = player_id, dbType = ?pg_bigint, opts = [?pg_not_null, ?pg_references(players, id, cascade)]},
			#schField{name = item_type, dbType = ?pg_varchar(32), opts = [?pg_not_null], codec = ?codec_atom, erlType = "atom()"},
			#schField{name = count, dbType = ?pg_integer, default = 1},
			#schField{name = attrs, dbType = ?pg_jsonb, default = #{}, codec = ?codec_json, erlType = "map()"}
		]
	}.
```

这一步的重点不是“换个地方写字段定义”，而是把下面这些信息都集中起来：

- 字段类型
- 默认值
- 主键/唯一键/外键约束
- Erlang 侧的数据表示方式
- JSON、atom、term 等字段的编解码策略

也就是说，后面不管是建表、查表、更新、解码结果，都会复用这一份 schema，而不是在多个文件里手工同步。

### 第 2 步：生成静态 schema 模块

```erlang
genPSchema:gen().
```

生成后会得到静态模块 `dbSchemaDef`，运行时 insert/select/update/delete/upsert 和 where 条件编码都会优先走这份静态 schema。

这一步的价值在于：后续业务代码不必自己判断“这个字段到底该当 binary、json 还是 atom 来处理”，而是统一按字段定义走。

### 第 3 步：服务启动时同步表结构

你可以在应用启动阶段，把 schema 同步到数据库：

```erlang
init_db() ->
	{ok, _Pid} = ePgdb:start("127.0.0.1", 5432, "postgres", "postgres", "game_db", [
		{wFCnt, 10},
		{wTCnt, 20}
	]),
	ok = ePgdb:syncSchema(players),
	ok = ePgdb:syncSchema(items).
```

如果后面你在 `players()` 里新增了一个字段：

```erlang
#schField{name = last_login_at, dbType = ?pg_timestamptz}
```

重新生成 `dbSchemaDef` 后，再次执行：

```erlang
ok = ePgdb:syncSchema(players).
```

缺失字段就会自动补齐。这个流程的意义就是你刚才提到的那一点：日常加字段时，不需要再回头维护一堆分散的 `ALTER TABLE`
脚本来追平代码结构。

### 第 4 步：业务代码里直接按数据结构读写

建表和同步之后，日常业务就可以直接围绕 record/map 操作，不用先回到 SQL 层拼语句。

插入一个玩家：

```erlang
ok = ePgdb:insert(#{
table_name => players,
name => <<"Alice">>,
level => 12,
gold => 8800,
vip => true,
profile => #{rank => 3, server => <<"s1">>}
}).
```

按主键读取：

```erlang
{ok, [Player]} = ePgdb:get(players, #{id => 1}),
#{name := Name, profile := Profile} = Player.
```

按条件查询：

```erlang
{ok, Rows} = ePgdb:select(players, #{vip => true, level => {'>=', 10}}, [
{fields, [id, name, level, profile]},
{order_by, [{level, desc}, {id, asc}]},
{limit, 100}
]).
```

更新字段：

```erlang
{ok, 1} = ePgdb:update(#{
table_name => players,
gold => 9900,
profile => #{rank => 4, server => <<"s1">>}
}, [gold, profile], #{id => 1}).
```

插入道具时，`item_type` 会按 schema 自动做 atom/binary 转换：

```erlang
ok = ePgdb:insert(#{
table_name => items,
player_id => 1,
item_type => sword,
count => 1,
attrs => #{star => 5, bind => true}
}).
```

这里的关键好处是：

- `profile` / `attrs` 这类 JSON 字段不用你手工 `jiffy:encode`
- `item_type` 这类 atom 字段不用你在业务层手工 `atom_to_binary`
- where 条件和返回结果也会复用同一套字段定义，不容易出现“写入一套规则、查询另一套规则”的漂移

### 第 5 步：结构变更时，继续只改 schema

比如策划说玩家表要加一个段位字段、道具表要增加耐久值：

```erlang
#schField{name = tier, dbType = ?pg_varchar(16), default = <<"bronze">>}
#schField{name = durability, dbType = ?pg_integer, default = 100}
```

你需要做的通常只有：

1. 修改 schema
2. 重新执行 `genPSchema:gen()`
3. 启动时或发版时跑 `syncSchema/1`
4. 在业务层直接开始使用新字段

这就是 ePgdb 最实际的价值之一：把“字段定义”“编解码规则”“数据库结构同步”“业务读写”尽量收拢进一条线，而不是散落在 schema
文档、SQL 文件、CRUD 代码和人工约定里。

例如：

```erlang
genPSchema:gen().
%% 或自定义路径：
genPSchema:gen("./src/schema", dbSchemaDef, "./src/schema", "./include", "./include").
```

参数说明：

- 参数 1：包含 `*_schema.erl` 文件的目录
- 参数 2：输出的静态模块名
- 参数 3：静态模块 `.erl` 输出目录
- 参数 4：生成的 `.hrl` 文件输出目录
- 参数 5：编译 schema 时的 include 目录

## Schema 定义放哪里

现在项目里的 schema 以静态生成的 dbSchemaDef 为准，不再依赖运行时注册中心。

### 1. 当前正确用法

当前 schema 源文件的正确写法只有一套：把 schema 写成独立的 `*_schema.erl` 模块，放在 `src/schema` 目录下，由零参导出函数返回
`#schema{}`，字段列表使用 `#schField{}`。

也就是说，**参与 `genPSchema:gen/0,5` 的 schema 源文件应统一使用 `#schema{}` + `#schField{}` 格式**。

```erlang
-module(pg_player_schema).
-include("pgdbSchema.hrl").
-compile([export_all, nowarn_export_all]).

players() ->
	#schema{
		repr = record,
		comment = "玩家主表",
		fields = [
			#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key]},
			#schField{name = name, dbType = ?pg_varchar(64), opts = [?pg_not_null, ?pg_unique]},
			#schField{name = level, dbType = ?pg_integer, default = 1},
			#schField{name = gold, dbType = ?pg_bigint, default = 0},
			#schField{name = data, dbType = ?pg_jsonb, erlType = "map()"},
			#schField{name = item_type, dbType = ?pg_varchar(32), codec = ?codec_atom, erlType = "atom()"},
			#schField{name = created_at, dbType = ?pg_timestamptz}
		]
	}.
```

正式运行前建议统一生成静态模块：

```erlang
genPSchema:gen().
```

### 2. 现在 schema 会实际参与什么

生成后的静态 schema 会参与下面这些路径的字段级转换：

- `insert` / `batchInsert` / `update` / `upsert`
- `select` / `get` / `selectPage`
- `count` / `sum` 的 where 条件
- `delete` 的 where 条件
- 返回结果行的字段解码

例如：

- `json` / `jsonb` 字段会按字段类型编码/解码，而不是单纯看到 Erlang map 就当 JSON
- `varchar` / `text` / `uuid` / `inet` 这类文本型字段会按字段定义做文本归一化
- `array` 字段会按元素类型递归处理

这就是你说的那个核心点：**转换优先依据表字段 schema，而不是依据 Erlang 值长得像什么。**

### 3. 相关 API

```erlang
ePgdb:schema(Table).
ePgdb:schemas().
ePgdb:fieldSchema(Table, Field).
```

### 4. Schema 后端

当前项目只保留编译期静态生成方式：通过 `genPSchema:gen/0,5`，扫描 `*_schema.erl` 文件生成静态模块 `dbSchemaDef`。

Schema 的完整格式、字段类型支持和 codec 编解码策略见 docs/schema-guide.md。

## 快速开始

### 1. 启动参数

当前主入口是 `ePgdb:start/6`：

```erlang
{ok, _Pid} = ePgdb:start("127.0.0.1", 5432, "postgres", "postgres", "game_db", [
	{wFCnt, 10},
	{wTCnt, 20},
	{fTLfl, infinity},
	{wArgs, [
		{tcpOpts, [{keepalive, true}]},
		{slowThreshold, 1000}
	]}
]).
```

当前代码实际使用的启动参数主要分两类：

- `wFCnt`: 常驻 worker 数，也就是常驻数据库连接数
- `wTCnt`: 临时 worker 上限，负载上来时可额外创建的临时连接数
- `fTLfl`: eFaw 队列长度限制；`infinity` 表示不限制
- `fTMax`: eFaw 任务相关上限，按 eFaw 原生语义透传
- `wArgs`: 传给 `pgdbWorker` 的连接参数和扩展选项

`wArgs` 里当前实际用到的是：

- `tcpOpts`: 透传给 epgsql/gen_tcp 的 TCP 选项，默认是 `[{keepalive, true}]`
- `ssl`: 是否启用 SSL
- `sslOpts`: SSL 选项
- `slowThreshold`: 慢查询阈值，单位毫秒；超过后 worker 会打印慢任务告警

补充说明：

- 启动时会先连接 PostgreSQL 的 `postgres` 维护库，必要时自动创建目标数据库
- 随后会打开 eFaw 工厂，并自动执行 `syncCheckSchema/0` 同步静态 schema
- README 旧版本里提到的 `worker_count`、`temp_worker_count`、`create_database_if_missing`、`maintenance_database` 等
  map/config 风格字段，不是当前主路径接口

### 2. 编译 & 运行

```bash
rebar3 compile
rebar3 shell
```

说明：当前 `rebar.config` 中的 `eFaw` 和 `jiffy` 依赖源是内部 Git 镜像。如果你的环境不能访问这些地址，需要改成你自己的镜像或可访问的上游源。

### 2.1 功能测试

```bash
rebar3 eunit --module=pgdb_admin_tests --verbose
rebar3 eunit --module=pgdb_crud_tests --verbose
rebar3 eunit --module=pgdb_select_tests --verbose
rebar3 eunit --module=pgdb_bench_tests --verbose
```

其中：

- `pgdb_admin_tests`: schema/DDL/迁移/自省接口验证
- `pgdb_crud_tests`: CRUD、事务、分页扫描、jsonb 写路径验证
- `pgdb_select_tests`: where/select 组合与分页查询验证
- `pgdb_bench_tests`: EUnit 冒烟测试，并内置较轻量的 bench 函数

### 2.2 性能基准

仓库当前有两套和性能相关的入口：

- `pgdb_bench_tests`: 偏 EUnit / bench 风格，适合功能冒烟后快速看一组基准统计
- `tcPgdb`: 专门的吞吐与场景压测模块，覆盖 CRUD、批量、不同数据结构、事务、扫描、混合读写等场景

如果要手工跑完整压测，推荐直接使用 test profile shell 进入 `tcPgdb`：

```bash
rebar3 compile
rebar3 as test shell
```

```erlang
%% 跑整套压测
tcPgdb:main().

%% 指定并发和循环次数
tcPgdb:main("", 4, 500).

%% 结果追加到文件
tcPgdb:main("tc_pgdb_bench.log", 4, 500).

%% 单独跑某一组
tcPgdb:crud_performance_test(1, 1000).
tcPgdb:query_performance_test(1, 200).
tcPgdb:mixed_workload_performance_test(4, 500).
```

`tcPgdb` 当前覆盖：

- 基础 CRUD 性能测试
- 批量操作性能测试
- 不同数据结构性能对比
- 查询与扫描性能测试
- 事务与直连回调性能测试
- 混合读写性能测试

推荐参数：

- 开发机 quick 跑法：`tcPgdb:main("", 1, 100).`
- 单项基线：`tcPgdb:crud_performance_test(1, 200).`
- 单机正式压测：先 `1` 并发，再逐步提高到 `4`、`8`，`LoopCnt` 建议从 `1000` 起。

`tcPgdb` 的详细调用方式和参数建议已经写在 [test/src/tcPgdb.erl](src/tcPgdb.erl) 模块头部注释里，打开文件即可直接照抄。

## 还建议补充的测试

当前功能正确性已经比较完整，但还有几类测试值得继续补：

- 心跳与断线重连测试：主动断开 PostgreSQL 连接后，验证 worker 能否自动恢复
- 队列溢出测试：把 `fTLfl` 这类队列限制参数压到很小，验证 overflow 行为是否符合预期
- 高并发热点更新测试：多进程同时更新同一批主键，观察事务冲突和尾延迟
- 大结果集扫描测试：验证 `foreachRows/foldRows/foreachByKey` 在十万级数据量下的分页稳定性
- 长事务占用测试：验证少量慢事务是否会拖垮整个工厂队列

## 还建议优化的点

- 细分数据库执行时间和工厂排队时间，区分 PostgreSQL 慢与队列阻塞
- 增加断线重连压测，验证 worker 自动恢复后的尾延迟
- 增加热点行更新冲突测试，观察事务冲突和重试成本
- 增加更大数据量下的分页扫描基准，验证 `foreachRows/foldRows/foreachByKey` 的稳定性

### 3. 建表

```erlang
-include("pgdbSchema.hrl").

%% 创建玩家表
ePgdb:createTable(players, [
#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key]},
#schField{name = name, dbType = ?pg_varchar(64), opts = [?pg_not_null, ?pg_unique]},
#schField{name = level, dbType = ?pg_integer, default = 1},
#schField{name = gold, dbType = ?pg_bigint, default = 0},
#schField{name = vip, dbType = ?pg_boolean, default = false},
#schField{name = data, dbType = ?pg_jsonb, default = #{}, codec = ?codec_json},
#schField{name = created_at, dbType = ?pg_timestamptz, opts = [{default, now}]}
]).

%% 创建物品表（带外键）
ePgdb:createTable(items, [
#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key]},
#schField{name = player_id, dbType = ?pg_bigint, opts = [?pg_not_null, ?pg_references(players, id, cascade)]},
#schField{name = item_type, dbType = ?pg_varchar(32), opts = [?pg_not_null], codec = ?codec_atom},
#schField{name = count, dbType = ?pg_integer, default = 1},
#schField{name = attrs, dbType = ?pg_jsonb, default = #{}, codec = ?codec_json}
]).

%% 添加索引
ePgdb:addIndex(items, [player_id]).
ePgdb:addIndex(players, [name], [{unique, true}]).
ePgdb:addIndex(items, [attrs], [{method, gin}]).  %% GIN 索引支持 JSONB 查询
```

如果你希望项目里所有表结构都集中定义，不在建表时分散写，建议直接维护 schema 模块并生成静态 dbSchemaDef：

```erlang
genPSchema:gen().
```

后续 `insert/select/update/upsert` 就会优先按静态 schema 做字段级转换。

### 4. 动态修改表结构

```erlang
%% 添加字段
ePgdb:addColumn(players, email, {varchar, 128}).

%% 带默认值和约束
ePgdb:addColumn(players, score, integer, [{default, 0}, {not_null, true}]).

%% 删除字段
ePgdb:dropColumn(players, email).

%% 重命名字段
ePgdb:renameColumn(players, name, nickname).

%% 修改字段类型
ePgdb:alterColumnType(players, gold, bigint).
```

### 5. CRUD 操作

```erlang
%% ===== 插入 =====
ok = ePgdb:insert(#{
table_name => players,
name => <<"Alice">>,
level => 10,
gold => 500
}).

%% ===== 查询单条 =====
{ok, [P]} = ePgdb:get(players, #{id => 1}).

%% ===== 查询多条 =====
{ok, Players} = ePgdb:select(players, #{level => {'>=', 10}}).

%% 带排序、分页
{ok, TopPlayers} = ePgdb:select(players, #{level => {'>=', 5}}, [
{order_by, {level, desc}},
{limit, 10},
{offset, 0}
]).

%% 指定返回字段
{ok, Names} = ePgdb:select(players, #{}, [
{fields, [id, name, level]}
]).

%% 分页查询
{ok, #{rows := PageRows, total := Total}} = ePgdb:selectPage(players, #{vip => true}, 1, 200).

%% ===== 更新 =====
{ok, 1} = ePgdb:update(#{
table_name => players,
level => 11,
gold => 600
}, [level, gold], #{id => 1}).

%% ===== 删除 =====
{ok, 1} = ePgdb:delete(players, #{id => 999}).

%% ===== Upsert (存在则更新，不存在则插入) =====
{ok, P2} = ePgdb:upsert(
#{table_name => players, id => 1, name => <<"Alice">>, level => 15},
[id],
[name, level]
).
%% 也可以用 'all' 更新所有非冲突字段
{ok, P3} = ePgdb:upsert(
#{table_name => players, id => 1, name => <<"Alice">>, level => 20, gold => 1000},
[id],
all
).
```

### 6. 高级 WHERE 条件

```erlang
%% 等于
ePgdb:select(players, #{name => <<"Alice">>}).

%% 比较
ePgdb:select(players, #{level => {'>=', 10}}).
ePgdb:select(players, #{gold => {'>', 100}}).

%% IN 查询
ePgdb:select(players, #{id => {in, [1, 2, 3]}}).
ePgdb:select(players, #{name => {not_in, [<<"Bot1">>, <<"Bot2">>]}}).

%% BETWEEN
ePgdb:select(players, #{level => {between, 10, 50}}).

%% LIKE / ILIKE (不区分大小写)
ePgdb:select(players, #{name => {like, <<"Ali%">>}}).
ePgdb:select(players, #{name => {ilike, <<"%alice%">>}}).

%% IS NULL / IS NOT NULL
ePgdb:select(players, #{email => null}).
ePgdb:select(players, #{email => not_null}).

%% JSONB 包含查询
ePgdb:select(players, #{data => {jsonb_contains, #{<<"vip">> => true}}}).

%% OR 条件 (使用 list 形式)
ePgdb:select(players, [
{'or', [
#{level => {'>=', 50}},
#{vip => true}
]}
], []).
```

### 6.1 Opts 参数说明

`select/3`、`get/3`、`selectPage/5`、分页扫描接口都支持一部分查询选项。常用值如下：

```erlang
[
{fields, [id, name, level]},
{order_by, {level, desc}},
{order_by, [{level, desc}, {id, asc}]},
{limit, 100},
{offset, 200},
{group_by, [guild_id]},
{having, #{member_count => {'>', 10}}},
{for_update, true}
].
```

说明：

- `fields`: 只返回指定字段
- `order_by`: 支持单字段或多字段排序
- `limit` / `offset`: 传统分页
- `group_by` / `having`: 聚合查询
- `for_update`: 在事务里对结果加行锁
- `count_total`: 仅 `selectPage/5` 使用，默认 `false`，设为 `true` 可额外查询总数统计
- `start_after`: 仅 `foldByKey/7` / `foreachByKey/6` 使用，表示从某个 key 之后继续扫描

`addColumn/4` 支持的 `Opts`：

```erlang
[{default, 0}, {not_null, true}]
```

`addIndex/3` 支持的 `Opts`：

```erlang
[{unique, true}].
[{name, player_level_idx}].
[{method, gin}].
```

### 7. JSONB 灵活数据

```erlang
%% 存入 JSONB 数据
ok = ePgdb:insert(#{
table_name => players,
name => <<"Bob">>,
data => #{
<<"vip">> => true,
<<"last_login">> => <<"2025-01-01">>,
<<"settings">> => #{<<"lang">> => <<"zh">>}
}
}).

%% 更新 JSONB 中的某个路径
ePgdb:jsonbSet(players, data, [<<"vip">>], false, #{id => 1}).
ePgdb:jsonbSet(players, data, [<<"settings">>, <<"lang">>], <<"en">>, #{id => 1}).

%% 读取 JSONB 中的值
{ok, Vip} = ePgdb:jsonbGet(players, data, <<"vip">>, #{id => 1}).
```

### 8. 批量操作

```erlang
%% 批量插入
ok = ePgdb:batchInsert([
#{table_name => players, name => <<"P1">>, level => 1},
#{table_name => players, name => <<"P2">>, level => 2},
#{table_name => players, name => <<"P3">>, level => 3}
]).

%% tuple/record 会用记录名推导表名；map 必须显式带上 table_name

%% 按指定键字段批量删除
{ok, Deleted} = ePgdb:batchDeleteByKey(players, id, [1, 2, 3]).
```

### 9. 事务

```erlang
%% 自动提交/回滚
{ok, Result} = ePgdb:transaction(fun(Conn) ->
{ok, Player} = ePgdb:insertR(Conn, #{table_name => players, name => <<"NewPlayer">>}),
PlayerId = element(2, Player),
ok = ePgdb:insert(Conn, #{
table_name => items,
player_id => PlayerId,
item_type => sword,
count => 1
}),
{ok, 1} = ePgdb:update(Conn, #{
table_name => players,
gold => 100
}, [gold], #{id => PlayerId}),
Player
end).
%% 如果任何操作抛出异常，整个事务自动回滚
```

### 10. Schema 迁移

迁移系统的详细说明、执行流程、事务限制、生产建议和完整示例见 docs/migration-guide.md。

```erlang
%% 定义迁移列表
Migrations = [
{1, "create players table",
fun(_Conn) ->
ePgdb:createTable(players, [
#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key]},
#schField{name = name, dbType = ?pg_varchar(64), opts = [?pg_not_null, ?pg_unique]},
#schField{name = level, dbType = ?pg_integer, default = 1}
])
end,
fun(_Conn) ->
ePgdb:dropTable(players)
end},
{2, "add gold column",
fun(_Conn) ->
ePgdb:addColumn(players, gold, bigint, [{default, 0}])
end,
fun(_Conn) ->
ePgdb:dropColumn(players, gold)
end},
{3, "add items table",
fun(_Conn) ->
ok = ePgdb:createTable(items, [
#schField{name = id, dbType = ?pg_bigserial, opts = [?pg_primary_key]},
#schField{name = player_id, dbType = ?pg_bigint, opts = [?pg_not_null]},
#schField{name = item_type, dbType = ?pg_varchar(32), opts = [?pg_not_null]},
#schField{name = count, dbType = ?pg_integer, default = 1}
]),
ePgdb:addIndex(items, [player_id])
end,
fun(_Conn) ->
ePgdb:dropTable(items)
end}
],

%% 执行迁移（只运行未执行过的）
ePgdb:migrate(Migrations).

%% 回滚到版本 1（回滚版本 3 和 2）
ePgdb:rollback(Migrations, 1).

%% 查看迁移状态
{ok, Status} = ePgdb:status(Migrations).
```

### 11. Schema 自动同步

```erlang
%% 修改 schema 后重新生成 dbSchemaDef
genPSchema:gen().

%% 然后按表同步结构
ok = ePgdb:syncSchema(players).
ok = ePgdb:syncSchema(items).
```

### 12. 聚合 & 自省

```erlang
%% 统计
{ok, Total} = ePgdb:count(players).
{ok, VipCount} = ePgdb:count(players, #{vip => true}).
{ok, TotalGold} = ePgdb:sum(players, gold).
{ok, VipGold} = ePgdb:sum(players, gold, #{vip => true}).

%% 查看所有表
{ok, Tables} = ePgdb:tables().

%% 查看表结构
{ok, Columns} = ePgdb:describe(players).

%% 查看表上的 key 和索引元数据
{ok, PrimaryKeys} = ePgdb:primaryKeys(players).
{ok, UniqueKeys} = ePgdb:uniqueKeys(players).
{ok, ForeignKeys} = ePgdb:foreignKeys(items).
{ok, Indexes} = ePgdb:indexes(players).
{ok, KeyInfo} = ePgdb:tableKeys(players).

%% 检查表/字段是否存在
true = ePgdb:tableExists(players).
true = ePgdb:columnExists(players, name).
```

### 13. 游戏服启动加载示例

这几个接口是给起服预热缓存、分批装载 ETS、避免一次性全表读爆内存用的。

```erlang
%% 1. 传统 offset 分页读取
{ok, #{rows := Players}} = ePgdb:selectPage(players, #{}, 1, 500, [
{order_by, {id, asc}},
{count_total, false}
]).

%% 2. 分页遍历，每条写入 ETS
ok = ePgdb:foreachRows(players, #{}, 500, [
{order_by, {id, asc}}
], fun(Row) ->
PlayerId = maps:get(id, Row),
ets:insert(player_cache, {PlayerId, Row})
end).

%% 3. 分页 fold，边扫边构建聚合缓存
{ok, GuildPlayers} = ePgdb:foldRows(players, #{}, 500, #{},
fun(Row, Acc) ->
GuildId = maps:get(guild_id, Row, 0),
maps:update_with(GuildId, fun(List) -> [Row | List] end, [Row], Acc)
end).

%% 4. 按主键做 keyset 扫描，更适合大表起服加载
ok = ePgdb:foreachByKey(players, #{}, id, 1000, fun(Row) ->
PlayerId = maps:get(id, Row),
ets:insert(player_cache, {PlayerId, Row})
end).

%% 5. 断点续扫，例如上次扫到 id=500000
ok = ePgdb:foreachByKey(players, #{vip => true}, id, 1000, [
{start_after, 500000}
], fun(Row) ->
ets:insert(vip_player_cache, {maps:get(id, Row), Row})
end).
```

### 14. 原生 SQL

```erlang
%% 简单查询
ePgdb:query("SELECT version()").

%% 参数化查询（防 SQL 注入）
ePgdb:query("SELECT * FROM players WHERE level > $1 AND gold > $2", [10, 100]).

%% 事务中使用原生 SQL
ePgdb:transaction(fun(Conn) ->
ePgdb:query(Conn, "LOCK TABLE players IN EXCLUSIVE MODE", []),
ePgdb:query(Conn, "UPDATE players SET gold = gold + $1 WHERE level >= $2", [100, 50])
end).
```

## SQL 注入防护

ePgdb 在两个层面防止 SQL 注入：

### 参数化查询（主要防线）

所有 CRUD 接口（`insert`, `select`, `update`, `delete`, `upsert`, `batchInsert` 等）内部都使用 `$1, $2, ...`
占位符，用户传入的值永远作为**绑定参数**发送给 PostgreSQL，不会拼入 SQL 文本。这是最安全的方式，也是绝大多数场景下的默认行为。

```erlang
%% 用户输入 name 作为参数绑定，不存在注入风险
ePgdb:select(players, #{name => UserInput}).
%% 生成: SELECT * FROM players WHERE name = $1   参数: [UserInput]

%% 原生 SQL 也走参数化
ePgdb:query("SELECT * FROM players WHERE level > $1", [Level]).
```

### 字面量转义（DDL / 非参数化场景）

少数场景下，值必须直接拼入 SQL 文本，不能走参数化——例如 DDL 语句中的 `DEFAULT` 值、JSONB 路径字面量等。此时通过 `pgdbUtils`
模块的转义函数保障安全：

#### `pgdbUtils:quoteLiteral/1`

将字符串值包裹为安全的 SQL 字面量。转义反斜杠 `\` 和单引号 `'`，使用 PostgreSQL 的 `E'...'` 语法，并拒绝包含 `\0`（零字节）的输入。

```erlang
pgdbUtils:quoteLiteral(<<"hello'world">>).
%% => [<<"E'">>, <<"hello''world">>, <<"'">>]
%% 拼入 SQL 后: E'hello''world'
```

**使用场景：**

| 场景                     | 示例                                                                    |
|------------------------|-----------------------------------------------------------------------|
| DDL DEFAULT 字符串值       | `ePgdb:createTable(t, [{name, text, [{default, <<"guest">>}]}])`      |
| JSONB 路径查询字面量          | `ePgdb:select(players, #{data => {jsonb_key, <<"vip">>, '=', true}})` |
| jsonbSet / jsonbGet 路径 | `ePgdb:jsonbSet(players, data, [<<"settings">>, <<"lang">>], ...)`    |

#### `pgdbUtils:quoteIdent/1`

将标识符（表名、字段名、数据库名）用双引号包裹并转义内部双引号。

```erlang
pgdbUtils:quoteIdent(<<"my-table">>).
%% => <<"\"my-table\"">>
```

**使用场景：**

仅用于接受**外部输入**标识符的地方，如 `CREATE DATABASE`。schema 中定义的表名和字段名均为安全的 Erlang atom，SQL 构建器
`pgdbQuery` 内部不再调用 `quoteIdent`，直接输出裸名称以减少开销。

### 安全约定

1. **用户数据一律走参数化**——使用 `ePgdb:select/2,3`、`ePgdb:insert/2`、`ePgdb:query/2` 等带参数的接口，不要手动拼 SQL 字符串。
2. **表名和字段名来自 schema atom**——不接受用户输入作为标识符。如果确实需要动态标识符，必须经过 `quoteIdent` 转义或白名单校验。
3. **DDL 字符串默认值自动转义**——`columnOptToSql({default, Value})` 内部调用 `quoteLiteral`，无需手动处理。
4. **`{raw, SQL}` 是逃生舱**——`{default, {raw, ...}}` 和 `{raw, ...}` 条件会原样拼入 SQL，使用时务必确保内容安全可信。

## 架构

```text
ePgdb_app          -- OTP Application
  └── ePgdb_sup    -- Supervisor (管理 eFaw 工厂)
        └── eFaw factory (pgdb_factory)
                            └── pgdbWorker × N  -- 每个 worker 持有一个 epgsql 连接

ePgdb.erl              -- 主 API (CRUD, DDL, 事务, JSONB, 迁移)
dbSchemaDef.erl        -- 静态 schema 定义与字段元数据
genPSchema.erl        -- Schema 静态代码生成器
pgdbCodec.erl          -- 字段级编解码
pgdbQuery.erl          -- SQL 查询构建器
pgdbWorker.erl         -- eFaw 工厂 worker (自动重连/心跳)
```

## 依赖

- [epgsql](https://github.com/epgsql/epgsql) - PostgreSQL 驱动
- [eFaw](https://sismaker.dy.takin.cc/SisMaker/eFaw) - 工厂工人调度框架（连接池）
- [jiffy](https://github.com/davisp/jiffy) - JSON 编解码 (JSONB 支持)

## License

Apache-2.0
