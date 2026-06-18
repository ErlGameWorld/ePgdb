# pgdbSchema 类型与 epgsql 数据表示对照

本文专门说明 [include/pgdbSchema.hrl](../include/pgdbSchema.hrl) 里列出的字段类型，在当前项目里和 epgsql 驱动之间是如何传值与回值的。

重点先说清楚两件事：

1. ePgdb 业务查询主路径走的是 epgsql:equery/3，而不是 epgsql:squery/2。
2. 当前项目连接 epgsql 时没有配置自定义 codecs，所以默认遵循 epgsql
   自带的数据表示；只有少数字段会再经过 [src/pgdb/pgdbCodec.erl](../src/pgdb/pgdbCodec.erl) 做二次转换。

因此，下面每个类型都分成三层来理解：

- epgsql 原始返回值：epgsql:equery/3 默认解码后给 Erlang 的值
- 推荐传入值：你在 Erlang 里更稳妥地传给 ePgdb / epgsql 的值
- ePgdb 二次处理：schema 已注册时，ePgdb 额外做的 encode/decode

## 1. 总规则

### 1.1 equery 和 squery 的区别

- epgsql:equery/3 使用 PostgreSQL 扩展查询协议，整数会返回 integer()，浮点会返回 float()，布尔返回 true/false，日期时间返回
  tuple，文本返回 binary()。
- epgsql:squery/2 使用简单查询协议，结果行基本都是 binary() / null。除非你明确在走 squery，否则不要用 squery 的返回格式来理解
  ePgdb 的常规行为。

### 1.2 NULL

- epgsql 默认把数据库 NULL 解码成 atom null。
- 传参时 null 和 undefined 默认都会被当成 SQL NULL。
- ePgdb 的 encodeTypedValue/2 也保留了 null 直通。

### 1.3 当前项目没有启用 epgsql JSON codec

- epgsql 默认 json/jsonb 返回 binary() JSON 文本。
- 当前 ePgdb 没有在 connect 时传 codecs 选项，所以不是 epgsql 直接把 JSON 解成 map，而是 ePgdb 在 schema 命中 json/jsonb
  时再调用 jiffy:decode/2。

## 2. 按 pgdbSchema.hrl 类型对照

### 2.1 数值类型

| pgdbSchema.hrl 宏  | PostgreSQL 类型             | epgsql 原始返回值                                    | 推荐传入值                                               | ePgdb 二次处理 / 注意事项                                                                                |
|-------------------|---------------------------|-------------------------------------------------|-----------------------------------------------------|--------------------------------------------------------------------------------------------------|
| ?pg_smallint      | SMALLINT / int2           | integer()                                       | integer()                                           | 无额外转换                                                                                            |
| ?pg_integer       | INTEGER / int4            | integer()                                       | integer()                                           | 无额外转换                                                                                            |
| ?pg_int           | INTEGER / int4            | integer()                                       | integer()                                           | int 只是 integer 别名                                                                                |
| ?pg_bigint        | BIGINT / int8             | integer()                                       | integer()                                           | 无额外转换                                                                                            |
| ?pg_serial        | SERIAL                    | integer()                                       | 通常不要主动传；插入时省略字段或用默认值                                | 本质仍按 int4 读写                                                                                     |
| ?pg_bigserial     | BIGSERIAL                 | integer()                                       | 通常不要主动传；插入时省略字段或用默认值                                | 本质仍按 int8 读写                                                                                     |
| ?pg_float         | REAL / float4             | float() 或 nan / plus_infinity / minus_infinity  | float()；也可传 integer()                               | epgsql 会把 integer() 自动转成 float4                                                                  |
| ?pg_double        | DOUBLE PRECISION / float8 | float() 或 nan / plus_infinity / minus_infinity  | float()；也可传 integer()                               | epgsql 会把 integer() 自动转成 float8                                                                  |
| ?pg_numeric(P, S) | NUMERIC(P, S)             | 当前项目按 integer() \| float() \| binary() 三种情况兼容处理 | 优先传 integer() 或 float()；对金额等精度敏感场景，建议业务侧先统一精度策略后再入库 | ePgdb 会在 decode 阶段把 binary 形式的 numeric 尽量转成 integer/float；这也是 pgdbCodec 里单独有 decodeNumeric/1 的原因 |

说明：

- epgsql README 的默认映射表没有把 numeric 单独列出来，但 ePgdb 已经明确按“numeric 可能返回 binary”做兼容处理。
- 如果你需要严格十进制精度，不能只依赖 float()。这属于业务精度策略问题，不是 ePgdb 当前自动解决的范围。

### 2.2 文本类型

| pgdbSchema.hrl 宏 | PostgreSQL 类型          | epgsql 原始返回值                                            | 推荐传入值                             | ePgdb 二次处理 / 注意事项                                                               |
|------------------|------------------------|---------------------------------------------------------|-----------------------------------|---------------------------------------------------------------------------------|
| ?pg_text         | TEXT                   | binary()                                                | binary()；也可传字符串 list() 或 atom()   | ePgdb 会把 atom() 转成 UTF-8 binary，把字符串 list 转成 binary                             |
| ?pg_varchar(N)   | VARCHAR(N)             | binary()                                                | binary()；也可传字符串 list() 或 atom()   | 同上                                                                              |
| ?pg_char(N)      | CHAR(N) / CHARACTER(N) | binary()                                                | binary()；也可传字符串 list() 或 atom()   | 同上；数据库层面会自己做定长填充                                                                |
| ?pg_uuid         | UUID                   | binary()，格式如 <<"550e8400-e29b-41d4-a716-446655440000">> | 标准 UUID binary()；也可传同格式字符串 list() | 这是 epgsql 原生 uuid codec，最稳妥就是传标准 UUID 字符串形式                                     |
| ?pg_inet         | INET                   | inet:ip_address()，如 {127,0,0,1} 或 {0,0,0,0,0,0,0,1}     | 推荐直接传 inet:ip_address() tuple     | pgdbSchema.hrl 里把它写成 binary 注释并不准确；epgsql 的原生 codec 是 Erlang IP tuple，不是 IP 字符串 |

说明：

- ?pg_inet 如果你传 <<"127.0.0.1">> 这种 binary，不能把它当成 epgsql 的原生安全输入格式。推荐先自己转成 {127,0,0,1} 再传。

### 2.3 布尔类型

| pgdbSchema.hrl 宏 | PostgreSQL 类型 | epgsql 原始返回值  | 推荐传入值         | ePgdb 二次处理 / 注意事项                |
|------------------|---------------|---------------|---------------|----------------------------------|
| ?pg_boolean      | BOOLEAN       | true \| false | true \| false | ePgdb 对 atom true/false 会显式转成布尔值 |
| ?pg_bool         | BOOLEAN       | true \| false | true \| false | bool 只是 boolean 别名               |

### 2.4 时间日期类型

| pgdbSchema.hrl 宏 | PostgreSQL 类型 | epgsql 原始返回值                                      | 推荐传入值                                                                        | ePgdb 二次处理 / 注意事项              |
|------------------|---------------|---------------------------------------------------|------------------------------------------------------------------------------|--------------------------------|
| ?pg_date         | DATE          | {Year, Month, Day}                                | {Year, Month, Day}                                                           | 无额外转换                          |
| ?pg_time         | TIME          | {Hour, Minute, SecondFloat}                       | {Hour, Minute, SecondFloat}                                                  | 无额外转换                          |
| ?pg_timestamp    | TIMESTAMP     | {{Year, Month, Day}, {Hour, Minute, SecondFloat}} | {{Year, Month, Day}, {Hour, Minute, SecondFloat}}；也可传 erlang:timestamp() 三元组 | epgsql 原生支持 erlang:now() 风格三元组 |
| ?pg_timestamptz  | TIMESTAMPTZ   | {{Year, Month, Day}, {Hour, Minute, SecondFloat}} | {{Year, Month, Day}, {Hour, Minute, SecondFloat}}；也可传 erlang:timestamp() 三元组 | 返回时不会保留原始时区字符串，而是标准日期时间 tuple  |

说明：

- 这里是 pgdbSchema.hrl 当前最容易误导的部分。头文件注释把 date/time/timestamp/timestamptz 都写成了 binary 示例，但 epgsql
  的默认二进制 codec 实际返回的是 tuple。
- 写入时也不建议传 <<"2026-04-08 12:30:00">> 这种 binary；更稳妥的是直接传 tuple。

### 2.5 JSON / 二进制类型

| pgdbSchema.hrl 宏 | PostgreSQL 类型 | epgsql 原始返回值         | 推荐传入值                                                                                           | ePgdb 二次处理 / 注意事项                                                                       |
|------------------|---------------|----------------------|-------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------|
| ?pg_json         | JSON          | binary()，内容是 JSON 文本 | 如果走 ePgdb 且字段 schema 已注册，可传 map() / list() / binary()；如果绕过 ePgdb 直接调 epgsql，最稳妥是传 JSON binary() | ePgdb encode 时会对非 binary 值调用 jiffy:encode；decode 时会对 binary 调 jiffy:decode(return_maps) |
| ?pg_jsonb        | JSONB         | binary()，内容是 JSON 文本 | 同 ?pg_json                                                                                      | 当前项目没有启用 epgsql 的 json codec，map/list 是 ePgdb 自己做的，不是 epgsql 默认行为                       |
| ?pg_bytea        | BYTEA         | binary()             | binary()                                                                                        | 无额外转换                                                                                   |

说明：

- 对 json/jsonb 来说，站在 ePgdb API 使用者角度，最常见的输入是 map() 或 list()；但站在“epgsql 默认行为”角度，它本身默认还是按
  binary JSON 文本处理。
- 如果 JSON 解析失败，ePgdb decodeJson/1 会把原始 binary 原样返回，而不是抛异常。

### 2.6 复合类型

| pgdbSchema.hrl 宏     | PostgreSQL 类型 | epgsql 原始返回值        | 推荐传入值                           | ePgdb 二次处理 / 注意事项                                                           |
|----------------------|---------------|---------------------|---------------------------------|-----------------------------------------------------------------------------|
| ?pg_array(InnerType) | InnerType[]   | list()，元素按内层类型表示    | list()，元素值按内层类型传                | ePgdb 会递归调用 encodeTypedValue/decodeTypedValue 处理内层元素                        |
| ?pg_enum_atom        | 项目约定的枚举字段     | 原始值通常仍是 binary() 文本 | atom() 优先，也可传 binary()          | ePgdb encode 时 atom() 会转成 binary；decode 时使用 binary_to_atom/2，因此只适合有限且可信的枚举值 |
| ?pg_enum_binary      | 项目约定的枚举字段     | 原始值通常仍是 binary() 文本 | binary()；也可传字符串 list() / atom() | ePgdb 最终会把文本归一化成 binary                                                     |

说明：

- ?pg_array(?pg_text) 这类文本数组，推荐元素直接用 binary()。虽然 ePgdb 会把字符串 list 转成 binary，但 binary 更稳。
- ?pg_enum_atom 和 ?pg_enum_binary 不是 epgsql README 里的原生基础类型映射，它们是 ePgdb 基于 schema 增加的约定层。
- ?pg_enum_atom 的 decode 使用的是 binary_to_atom/2，这意味着数据库中的新值会创建新
  atom；因此这类字段只适合有限枚举、受控写入的场景，不适合直接承载外部开放输入。

## 3. 目前 ePgdb 额外做了哪些转换

当前 [src/pgdb/pgdbCodec.erl](../src/pgdb/pgdbCodec.erl) 明确做了这些事：

- json/jsonb：写入时 jiffy:encode，读取时 jiffy:decode(return_maps)
- text/varchar/char/uuid/enum_binary：把 atom 或字符串 list 归一化为 binary
- boolean：把 atom true/false 归一化为布尔值
- array：递归处理内部元素
- enum_atom：写入时 atom_to_binary，读取时转 binary_to_atom
- numeric：读取时把 binary 形式尽量转成 integer/float

下面这些类型当前没有额外 codec 修正，基本完全依赖 epgsql 默认表示：

- integer / int / bigint / smallint / serial / bigserial
- float / double
- bytea
- date / time / timestamp / timestamptz
- inet

### 3.1 codec 编解码层

除了上面按 `dbType` 做的内置转换，`pgdbCodec` 还支持通过 `#schField.codec` 字段指定额外的编解码策略。当 `codec` 不为
`undefined` 时，**完全跳过** dbType 的内置编解码，由 codec 函数全权负责。

| codec         | 写入时 (Erlang → DB)    | 读取时 (DB → Erlang)            | 典型场景                            |
|---------------|----------------------|------------------------------|---------------------------------|
| `undefined`   | 走上面的 dbType 规则       | 走上面的 dbType 规则               | 默认                              |
| `json`        | jiffy:encode/1       | jiffy:decode/2 (return_maps) | text/bytea 列存 JSON 数据           |
| `term_str`    | io_lib:format("~tp") | erl_scan + erl_parse         | text 列存可读的 Erlang term          |
| `term_binary` | term_to_binary/1     | binary_to_term/2 ([safe])    | bytea 列存 Erlang term 二进制        |
| `atom`        | atom_to_binary/2     | binary_to_atom/2             | text/varchar 列, Erlang 侧使用 atom |

使用方式：在 `*_schema.erl` 的 `#schField{}` 中指定 `codec = ?codec_json` 等宏。

注意：`null` 值无论 codec 如何设置都会直通保持 SQL NULL 语义。

## 4. 推荐实践

如果你是在 ePgdb 上层写业务代码，推荐直接按下面的风格传值：

- 文本类：统一传 UTF-8 binary()
- UUID：统一传标准 UUID binary()
- INET：统一传 Erlang IP tuple，例如 {127,0,0,1}
- JSON / JSONB：统一传 map() / list()，让 ePgdb 去做 jiffy 编解码
- 日期时间：统一传 tuple，不要传格式化字符串
- 数组：统一传 Erlang list()，元素按内层类型准备好
- enum atom 模式：保证 atom 已预先存在，避免 decode 时退回 binary

如果你是绕过 ePgdb 直接调用 epgsql，就应该按 epgsql 默认 codec 的原生表示来传，不要参考 pgdbSchema.hrl 里那些偏“业务注释化”的
Erlang 映射说明。
