# ePgdb Schema 说明

本文档专门说明 ePgdb 的 Schema 定义格式、字段类型写法、字段选项以及基于 Schema 的编码/解码规则。

## 1. 为什么需要 Schema

在游戏服里，数据库字段的真实语义通常不应该由 Erlang 值的外观去猜。

例如：

- Erlang 的 map 可能是普通业务数据，也可能是 jsonb 字段
- Erlang 的 list 可能是字符串，也可能是数组，也可能只是一个普通列表
- 一个二进制可能是 uuid，也可能是文本，也可能是已经编码好的 JSON

所以 ePgdb 现在的设计是：

1. 先把 schema 生成进静态模块 dbSchemaDef
2. 在 insert / update / upsert / select / where 等路径上优先按字段 Schema 转换
3. 如果某个字段没有 Schema，再退回到较宽松的兜底转换

## 2. Schema 的基本格式

当前项目只有一套正式使用的 schema 源格式：schema 文件放在 `src/schema` 目录下，使用 `#schema{}` + `#schField{}` record 写法。

生成器 `genPSchema:gen/0,5` 只扫描 `*_schema.erl` 中的零参导出函数，并要求这些函数返回 `#schema{}`。因此，本仓库里**参与静态生成的
schema 源文件只应使用这一种格式**。

写法如下：

配合 [include/pgdbSchema.hrl](../include/pgdbSchema.hrl) 中的类型宏（`?pg_bigserial`、`?pg_varchar(N)` 等）和约束宏（
`?pg_primary_key`、`?pg_not_null` 等）：

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
            #schField{name = profile, dbType = ?pg_jsonb, erlType = "map()"},
            #schField{name = tags, dbType = ?pg_array(?pg_text), default = []},
            #schField{name = created_at, dbType = ?pg_timestamptz}
        ]
    }.
```

## 3. 推荐的组织方式

建议把表按领域拆成多个 `*_schema.erl` 模块，例如：

- `src/schema/pg_player_schema.erl`
- `src/schema/pg_bench_schema.erl`
- `src/schema/pg_types_schema.erl`

然后通过编译期生成把它们收敛成一个统一的静态模块 `dbSchemaDef`。

## 3. 编译期静态生成

调用生成器后，运行时所有 schema 查询都只依赖静态模块 dbSchemaDef。

调用方式：

```erlang
genPSchema:gen().
%% 等价于：
genPSchema:gen("./src/schema", dbSchemaDef, "./src/schema", "./include", "./include").
```

参数说明（`gen/5`）：

- 参数 1：包含 `*_schema.erl` 文件的目录
- 参数 2：输出的静态模块名（atom），默认 `dbSchemaDef`
- 参数 3：静态模块 `.erl` 输出目录
- 参数 4：生成的 `.hrl` 文件输出目录
- 参数 5：编译 schema 文件时的 include 目录

生成的静态模块提供以下 API：

```erlang
dbSchemaDef:getTables()           → [binary()]          %% 所有表名列表
dbSchemaDef:tableSchema(TableBin) → #schema{} | undefined  %% 表结构
dbSchemaDef:fieldSchema(T, F)     → #schField{} | undefined %% 字段结构
dbSchemaDef:fieldDefault(T, F)    → Default | undefined     %% 字段默认值
```

注意：静态模块内部存储的表名和字段名是 binary（如 `<<"players">>`），但对外封装函数会先做 `toBinary/1`，因此运行时通常既可传
atom，也可传 binary。

### schema 文件格式

用于静态生成的 schema 文件使用 `#schema{}` + `#schField{}` record 格式。每个零参导出函数代表一张表，函数名即表名。

例如 `src/schema/pg_player_schema.erl`：

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
            #schField{name = profile, dbType = ?pg_jsonb, erlType = "map()"}
        ]
    }.
```

约束：

- schema 模块只保留结构定义，不要写业务逻辑
- 不建议在静态 schema 文件里放匿名 fun

## 3.5 codec 编解码策略

`#schField{}` 的 `codec` 字段用于指定字段在 Erlang 与数据库之间的编解码策略。当 `dbType` 是通用类型（如 text/bytea）但
Erlang 侧需要特殊转换时特别有用。

### 可用的 codec 宏

```erlang
?codec_undefined    %% → undefined  默认，按 dbType 走内置逻辑
?codec_json         %% → json       text/bytea 列存 JSON
?codec_term_str     %% → term_str   text 列存 Erlang term 可读字符串
?codec_term_binary  %% → term_binary  bytea 列存 Erlang term 二进制
?codec_atom         %% → atom       text/varchar 列，Erlang 侧使用 atom
```

### codec 编解码规则

| codec         | dbType 建议      | encode (Erlang → DB)          | decode (DB → Erlang)                |
|---------------|----------------|-------------------------------|-------------------------------------|
| `undefined`   | 任意             | 按 dbType 走 `encodeTypedValue` | 按 dbType 走 `decodeTypedValue`       |
| `json`        | text / bytea   | `jiffy:encode/1`              | `jiffy:decode/2` (return_maps)      |
| `term_str`    | text           | `io_lib:format("~tp")`        | `erl_scan` + `erl_parse:parse_term` |
| `term_binary` | bytea          | `term_to_binary/1`            | `binary_to_term/2` ([safe])         |
| `atom`        | text / varchar | `atom_to_binary/2`            | `binary_to_atom/2`                  |

### 使用示例

```erlang
%% text 列存 JSON，Erlang 侧使用 map
#schField{name = config, dbType = ?pg_text, codec = ?codec_json, erlType = "map()"}

%% text 列存 Erlang term 可读字符串，用于调试友好的持久化
#schField{name = extra, dbType = ?pg_text, codec = ?codec_term_str, erlType = "term()"}

%% bytea 列存 Erlang term 二进制，性能更好但不可读
#schField{name = state, dbType = ?pg_bytea, codec = ?codec_term_binary, erlType = "term()"}

%% varchar 列存 atom，适合有限枚举值
#schField{name = item_type, dbType = ?pg_varchar(32), codec = ?codec_atom, erlType = "atom()"}
```

### 与 dbType 内置编解码的关系

- 当 `codec = undefined` 时，走 `encodeTypedValue(DbType, Value)` + `decodeTypedValue(DbType, Value)` 路径
- 当 `codec` 不为 `undefined` 时，**跳过** dbType 内置编解码，直接由 codec 函数全权负责转换
- `null` 值无论 codec 如何设置都会直通（保持 SQL NULL 语义）

### 安全注意事项

- `?codec_atom`：decode 使用 `binary_to_atom/2`，会创建新 atom，因此只适合值域受控、枚举规模有限且输入可信的字段
- `?codec_term_binary`：decode 使用 `binary_to_term(Value, [safe])`，不会创建新 atom，防止 atom 表耗尽
- `?codec_term_str`：decode 只支持数据 term（通过 `erl_parse:parse_term`），不会执行代码

## 3.6 宏写法

头文件 [include/pgdbSchema.hrl](../include/pgdbSchema.hrl) 提供了类型宏和约束宏，仅在 `#schField{}` record 格式中使用。

### 类型宏

数值类型：

```erlang
?pg_integer      %% → integer
?pg_int          %% → int (integer 别名)
?pg_bigint       %% → bigint
?pg_smallint     %% → smallint
?pg_serial       %% → serial
?pg_bigserial    %% → bigserial
?pg_float        %% → float
?pg_double       %% → double
?pg_numeric(P, S) %% → {numeric, P, S}
```

文本类型：

```erlang
?pg_text         %% → text
?pg_varchar(N)   %% → {varchar, N}
?pg_char(N)      %% → {char, N}
?pg_uuid         %% → uuid
?pg_inet         %% → inet
```

布尔和时间：

```erlang
?pg_boolean      %% → boolean
?pg_bool         %% → bool
?pg_timestamp    %% → timestamp
?pg_timestamptz  %% → timestamptz
?pg_date         %% → date
?pg_time         %% → time
```

JSON / 二进制 / 复合类型：

```erlang
?pg_json         %% → json
?pg_jsonb        %% → jsonb
?pg_bytea        %% → bytea
?pg_array(T)     %% → {array, T}，如 ?pg_array(?pg_text)
?pg_enum_atom    %% → {enum, atom}
?pg_enum_binary  %% → {enum, binary}
```

### 约束宏

```erlang
?pg_primary_key                       %% → primary_key
?pg_not_null                          %% → not_null
?pg_unique                            %% → unique
?pg_default(Value)                    %% → {default, Value}
?pg_references(Table, Column)         %% → {references, {Table, Column}}
?pg_references(Table, Column, OnDel)  %% → {references, {Table, Column, OnDel}}
?pg_check(Expr)                       %% → {check, Expr}
?pg_index                             %% → {index, true}
```

`OnDelete` 目前支持：

```erlang
cascade
set_null
restrict
no_action
```

### 编解码策略宏

```erlang
?codec_undefined    %% → undefined     默认，按 dbType 走内置逻辑
?codec_json         %% → json          text/bytea 列存 JSON
?codec_term_str     %% → term_str      text 列存 Erlang term 可读字符串
?codec_term_binary  %% → term_binary   bytea 列存 Erlang term 二进制
?codec_atom         %% → atom          text/varchar 列存 atom
```

## 4. 当前支持的字段类型

下面是当前项目里已经明确支持、并且会参与 Schema 编解码的字段类型。

### 4.1 数值型

```erlang
integer
int
bigint
smallint
serial
bigserial
numeric
{numeric, Precision, Scale}
float
double
```

这些类型当前主要保持原值透传，依赖 epgsql 和 PostgreSQL 自身处理。

### 4.2 文本型

```erlang
text
{varchar, N}
{char, N}
uuid
inet
```

这些类型在写入时会做文本归一化：

- atom 会转成 binary
- 字符串 list 会转成 binary
- binary 保持不变

### 4.3 布尔型

```erlang
boolean
bool
```

如果写入的是 atom `true` / `false`，会转成 PostgreSQL 可接受的布尔值。

### 4.4 时间相关

```erlang
timestamp
timestamptz
date
time
```

当前默认不做强制格式转换，按驱动与调用方提供的值传递。也就是说：

- 如果你已经用统一时间格式，例如 Unix 时间戳、二进制 ISO 时间字符串，可以直接存
- 如果你需要严格的业务时间格式转换，建议给字段加 `encoder/decoder`

### 4.5 JSON / JSONB

```erlang
json
jsonb
```

这是当前 Schema 参与最明显的类型：

- 写入时会编码成 JSON binary
- 查询返回时会尝试反解成 Erlang map/list

所以只要字段被声明为 `json` 或 `jsonb`，就不会再依赖“传入值是 map 所以猜它是 JSON”这种弱判断。

### 4.6 数组

```erlang
{array, InnerType}
```

示例：

```erlang
{tags, {array, text}, []}.
{reward_ids, {array, bigint}, []}.
{snapshots, {array, jsonb}, []}.
```

数组会递归按元素类型做编解码。

### 4.7 枚举扩展类型

当前项目新增了一个轻量枚举类型写法：

```erlang
{enum, atom}
{enum, binary}
```

含义：

- `{enum, atom}`：数据库存文本，业务层读出来转 atom
- `{enum, binary}`：数据库存文本，业务层保持 binary

例如：

```erlang
{status, {enum, atom}, []}
```

数据库里是 `<<"idle">>`，解码后可以得到 atom `idle`。

注意：`{enum, atom}` 会调用 `binary_to_atom/2`。如果这个值来自不受信任外部输入，不建议直接用 atom 枚举；更稳妥的是用
`{enum, binary}` 或自定义 decoder。

## 5. 字段选项格式

字段第三项 `FieldOpts` 同时承担两类职责：

1. DDL 选项
2. 编解码选项

### 5.1 DDL 选项

这些选项主要用于建表和改表：

```erlang
primary_key
not_null
unique
{default, Value}
{references, {RefTable, RefColumn}}
{references, {RefTable, RefColumn, cascade}}
{check, Expr}
```

### 5.2 编解码选项

字段的编解码策略现在通过 `#schField{}` 的 `codec` 字段指定（详见 3.5 节），不再使用 opts 中的 `{encoder, Fun}` /
`{decoder, Fun}` / `{codec, {E, D}}`。

```erlang
#schField{name = config, dbType = ?pg_text, codec = ?codec_json, erlType = "map()"}
```

优先级是：

1. 如果字段定义了 `codec`（非 undefined），由 codec 全权处理编解码
2. 否则按 `dbType` 做默认转换
3. 如果字段没有 Schema，再退回到兜底策略

## 6. 当前哪些 API 会用到 Schema

当前已经接入 Schema 的主要 API：

```erlang
ePgdb:insert/2, 3
ePgdb:batchInsert/2,3
ePgdb:update/3, 4
ePgdb:upsert/4, 5
ePgdb:select/2, 3
ePgdb:get/2, 3
ePgdb:selectPage/4, 5
ePgdb:delete/2, 3
ePgdb:count/1, 2
ePgdb:sum/2, 3
ePgdb:jsonbSet/4, 5
```

包括：

- 写入时参数编码
- where 条件参数编码
- 查询结果字段解码

## 7. Schema API 一览

```erlang
ePgdb:schema(Table).
ePgdb:schemas().
ePgdb:fieldSchema(Table, Field).
```

其中：

- `schema/1`：查看某张表的 schema
- `fieldSchema/2`：查看具体字段的 schema

## 8. 兜底转换规则

如果某个字段没有静态 Schema，目前的兜底规则仍然保留：

- map 会当作 JSON 编码
- 非字符串 list 会尝试当作 JSON 编码
- 字符串 list 保持文本语义

这保证旧代码不会一下子失效，但推荐新业务逐步都走显式 Schema。

## 9. 推荐实践

建议这样使用：

1. 把所有表定义集中在 1 到多个 schema 模块里
2. 构建或发布前执行 `genPSchema:gen/0,5` 生成最新静态 schema
3. 所有 JSON/枚举/特殊时间字段都显式声明类型
4. 复杂字段转换统一写到 `encoder/decoder`，不要散在业务代码里
5. 新增字段时同时改迁移和 schema 定义，保持一致

## 10. 后续可继续增强的方向

如果你后面要把这套继续做强，可以继续加：

1. 在构建流程里自动校验 schema 生成物是否最新
2. timestamp/date/time 的标准业务格式编解码
3. decimal/numeric 的高精度封装
4. enum 白名单校验
5. schema 与数据库实际结构一致性检查工具
