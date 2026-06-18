# ePgdb 性能测试结果与分析

本文档记录两组关键对照测试结果：

1. `tcPgdb:compare_direct_vs_epgdb/1`：裸数据库 vs ePgdb 全链路
2. `tcPgdb:compare_write_patterns/2`：单条写 vs 批量写 vs 单事务多条写

并据此给出对 `43 QPS` 这类写入结果的工程解释。

## 1. 测试目的

本次测试的目的不是单纯看 ePgdb 的绝对吞吐，而是拆开两层成本：

1. 裸数据库成本：直接使用 `epgsql` 访问 PostgreSQL。
2. ePgdb 全链路成本：经过 `schema + queue + worker + codec` 的完整路径。

对照测试入口：

```erlang
tcPgdb:compare_direct_vs_epgdb(1000).
```

补充的写路径对照入口：

```erlang
tcPgdb:compare_write_patterns(300).
tcPgdb:compare_write_patterns(300, 100).
```

这组测试专门量化 3 种最关键的生产写法：

1. 单条 autocommit 写
2. 单 SQL 批量写入
3. 单事务内多条 insert

输出会同时打印：

- `op_qps`：每秒能完成多少次“写操作/事务/批次”
- `row_qps`：按每次操作包含的行数折算后的真实写入行吞吐

这样可以直接看出“单条同步提交”到“批量或合并事务”之间到底有多少优化空间。

## 2. 测试口径

当前对照测试在同一份预置数据上分别测量：

- `DIRECT DB`：直接 `epgsql:squery/2`、`epgsql:equery/3`、直接事务。
- `EPGDB FULL PATH`：走 ePgdb 的 `query/get/select/insert/update/transaction`。

注意：

- 读测试是单条查询/点查。
- 写测试是**单条同步写**或**单事务同步提交**。
- 这里的写入结果不等同于“生产系统总写入上限”，它更接近“当前环境下单条同步提交路径的平均能力”。

## 3. 本次测试结果

原始命令：

```erlang
tcPgdb:compare_direct_vs_epgdb(1000).
```

结果摘要如下：

### 3.1 DIRECT DB | 裸数据库直连

| 项目 | avg_ns | qps | server_ns | server_qps |
| --- | ---: | ---: | ---: | ---: |
| simple query (squery) | 278528 | 3590 | 30000 | 33333 |
| parameterized query (equery) | 515481 | 1940 | 28000 | 35714 |
| insert bench_kv | 23184691 | 43 | - | - |
| update bench_kv | 23503155 | 43 | - | - |
| transaction bench_kv | 23186534 | 43 | - | - |

### 3.2 EPGDB FULL PATH | schema + queue + worker + codec

| 项目 | avg_ns | qps |
| --- | ---: | ---: |
| ePgdb query(SQL with params) | 793292 | 1261 |
| ePgdb get(by primary key) | 568217 | 1760 |
| ePgdb select(fields) | 535449 | 1868 |
| ePgdb insert bench_kv | 23150387 | 43 |
| ePgdb update bench_kv | 23237120 | 43 |
| ePgdb transaction bench_kv | 23580364 | 42 |

### 3.3 DELTA | 全链路相对裸数据库放大倍数

| 项目 | slowdown | direct_qps | full_qps | qps_gap |
| --- | ---: | ---: | ---: | ---: |
| query with params | 1.54x | 1940 | 1261 | 679 |
| get by primary key | 1.10x | 1940 | 1760 | 180 |
| select by primary key | 1.04x | 1940 | 1868 | 72 |
| insert bench_kv | 1.00x | 43 | 43 | 0 |
| update bench_kv | 0.99x | 43 | 43 | 0 |
| transaction bench_kv | 1.02x | 43 | 42 | 1 |

### 3.4 写路径模式对照结果

原始命令：

```erlang
tcPgdb:compare_write_patterns(300, 100).
```

这组测试固定 `RowsPerWrite = 100`，也就是每次“批量写”或“单事务多条写”都处理 100 行。

#### 3.4.1 DIRECT DB | 裸数据库直连

| 项目 | avg_ns | op_qps | rows/op | row_qps |
| --- | ---: | ---: | ---: | ---: |
| single row autocommit | 23586792 | 42 | 1 | 42 |
| batch insert | 23658813 | 42 | 100 | 4200 |
| single tx multi insert | 82325421 | 12 | 100 | 1200 |

#### 3.4.2 EPGDB FULL PATH | schema + queue + worker + codec

| 项目 | avg_ns | op_qps | rows/op | row_qps |
| --- | ---: | ---: | ---: | ---: |
| single row autocommit | 24079336 | 42 | 1 | 42 |
| batch insert | 23498045 | 43 | 100 | 4300 |
| single tx multi insert | 81577902 | 12 | 100 | 1200 |

#### 3.4.3 写路径增益解读

| 维度 | direct db | ePgdb full path | 结论 |
| --- | ---: | ---: | --- |
| batch insert vs single | 100.00x | 102.38x | 几乎不增加单次提交耗时，但把每次提交承载的行数放大到 100 行 |
| single tx multi vs single | 28.57x | 28.57x | 合并提交明显有效，但 100 次单独 insert 的协议和执行开销依然存在 |
| ePgdb vs direct(single) | 1.02x slowdown | - | 单条写几乎没有额外框架损耗 |
| ePgdb vs direct(batch) | 0.99x slowdown | - | 批量写路径和裸库几乎等价 |
| ePgdb vs direct(tx_multi) | 0.99x slowdown | - | 单事务多条写路径和裸库几乎等价 |

## 4. 结果解读

### 4.1 读路径结论

读路径里，ePgdb 的额外开销存在，但不算大：

- `query(SQL with params)` 相比裸 `equery` 慢约 `1.54x`
- `get(by primary key)` 慢约 `1.10x`
- `select(fields)` 慢约 `1.04x`

这说明：

1. ePgdb 的主业务读路径已经比较接近裸库。
2. 额外开销主要来自通用 query 路径，而不是简单点查。
3. `schema` 查找、codec、worker 分发会带来一些成本，但并没有把读路径拖垮。

另外，裸数据库读测试里：

- `server_ns` 只有 `28000 ~ 30000 ns`
- 但 `client_avg_ns` 却是 `278528 ~ 515481 ns`

这说明 SQL 本身在 PostgreSQL 里执行很快，更多时间消耗在：

- 客户端和数据库往返
- 驱动协议开销
- 结果解码
- Erlang 调度
- ePgdb 的通用包装层

### 4.2 写路径结论

写路径里最重要的结论是：

**ePgdb 几乎不是瓶颈。**

因为：

- direct insert/update/transaction 基本都在 `43 QPS`
- ePgdb insert/update/transaction 也仍然是 `42 ~ 43 QPS`

也就是说，单条写慢的主要原因不在 ePgdb，而在数据库单条同步提交本身。

这类单条写通常会包含：

1. 事务提交
2. WAL 写入
3. 磁盘刷盘 / fsync
4. 索引更新

所以这组结果更像是：

> 当前环境下，PostgreSQL 单条同步写提交路径大约就是 `23ms` 级别。

### 4.3 写入模式优化空间已经量化出来了

新增的 `compare_write_patterns(300, 100)` 结果把写路径优化空间直接定量化了：

1. **单条 autocommit 写**
   - direct db: `42 row_qps`
   - ePgdb full path: `42 row_qps`

2. **单 SQL 批量写 100 行**
   - direct db: `4200 row_qps`
   - ePgdb full path: `4300 row_qps`
   - 相对单条写提升约 `100x`

3. **单事务内顺序执行 100 次 insert**
   - direct db: `1200 row_qps`
   - ePgdb full path: `1200 row_qps`
   - 相对单条写提升约 `28.57x`

这说明两个非常关键的事实：

1. **真正决定写吞吐的第一因素，是一次提交里装了多少行。**
2. **如果可以改写模型，优先级最高的是“单 SQL 批量写”，其次才是“单事务多条单独 insert”。**

因为从这次结果看：

- `batch insert` 和 `single row autocommit` 的单次耗时几乎一样，都是约 `23ms`
- 但 `batch insert` 一次提交里装了 `100` 行，所以真实行吞吐直接提升到 `4200 ~ 4300 row_qps`
- `single tx multi insert` 虽然也只提交一次事务，但它内部仍然执行了 `100` 次独立 insert，导致单次平均耗时上升到约 `81 ~ 82ms`

结论很直接：

> 如果业务允许把 100 条写合成 1 条批量 SQL，那么它几乎等于白拿了 100 倍量级的写吞吐提升。

而这部分收益并不是 ePgdb 特有能力，也不是 ePgdb 的限制；它来自写模型本身。

## 5. “43 QPS 会不会太低，生产环境能不能用？”

### 5.1 先说结论

**单看 `43 QPS` 这个数字，不能直接得出“不能上生产”的结论。**

关键要看你的生产写入模型是什么：

1. 如果你的业务是“高频单条强同步提交”，那 `43 QPS/连接` 的确偏低，需要优化。
2. 如果你的业务是“读多写少”，或者写入可以合并、批量、异步，那完全可能够用。
3. 如果你的线上部署环境比当前测试环境更强，写入吞吐通常还会明显高于这次测试结果。

### 5.2 为什么不能直接拿 43 当系统总能力

这里的 `43 QPS` 是：

- 单类操作
- 单条同步写
- 当前测试环境
- 当前表结构和索引条件下

它并不等于：

- 整个系统总 QPS
- 混合读写总吞吐
- 批量写入能力
- 多 worker 并发后的总写入上限

也不等于“游戏服整体能承受的玩家数”。

### 5.3 什么时候它会真的不够用

如果你的线上请求模型接近下面这种：

- 每个请求都立刻触发一次 PostgreSQL 单条同步写
- 不做批量，不做合并，不做异步落库
- 热点请求集中到少量表或少量行

那 `43 QPS/连接` 当然会成为瓶颈。

例如：

- 每秒几百次玩家属性更新，而且每次都必须即时提交数据库
- 每个请求都要单独 `insert/update` 一条记录并强一致返回

这种场景里，应该优先优化写模型，而不是先怀疑 ePgdb。

### 5.4 什么时候它是可用的

如果你的业务更接近下面这种：

- 读远多于写
- 写操作可以合并到事务中
- 日志类、事件类写入可以批量化
- 非关键路径写入允许异步化或缓冲
- 热点状态先放内存 / ETS / Redis，定时刷库

那这套系统完全可以用于生产。

对游戏服来说，常见合理模型往往是：

- 核心状态以内存为主
- PostgreSQL 负责持久化和关键查询
- 单条同步写只留给确实需要强一致的少数路径
- 其余写入尽量批量化或延迟落库

## 6. 这组结果真正说明了什么

### 6.1 已经确认的事实

1. ePgdb 对读路径有额外开销，但量级可接受。
2. ePgdb 对单条写路径几乎没有额外损失。
3. 当前环境里的主要瓶颈是 PostgreSQL 单条同步写提交，而不是 ePgdb 封装层。

### 6.2 当前最值得做的优化方向

如果目标是提升写吞吐，优先级建议如下：

1. **先优化写入模式**
   - 优先把高频单条写改成 `batch insert`
   - 如果暂时做不到单 SQL 批量，也至少先合并成“单事务多条写”
   - 减少每次请求都单条 autocommit

2. **再优化 PostgreSQL 部署和参数**
   - 存储性能
   - `synchronous_commit`
   - `fsync`
   - WAL 相关参数
   - 部署环境是否为生产级 Linux + SSD

3. **最后才是继续抠 ePgdb 的封装层成本**
   - 这一步更适合优化 query 通用路径，而不是写路径

## 7. 推荐后续测试

为了把写路径上限继续拆清楚，建议继续做下面几类对照：

1. 不同 `RowsPerWrite` 下的批量写曲线，例如 `10 / 50 / 100 / 500`
2. 不同 worker 数下的总写吞吐
3. 不同 PostgreSQL 参数下的写延迟变化
4. Windows 开发环境 vs Linux 生产环境的对比
5. 带索引、带冲突更新、带返回字段场景下的批量写退化情况

## 8. 最终结论

如果只看本次结果，可以得到一个很明确的工程判断：

> 当前系统的问题不是 ePgdb 把写拖慢了，而是 PostgreSQL 单条同步写本来就慢；而最有效的优化手段也已经测出来了，就是减少提交次数、增加每次提交承载的行数。

所以，“43 QPS 太低是不是不能生产用”的答案是：

- **如果你打算把生产写模型建立在大量单条同步提交上，那确实不够。**
- **如果你采用游戏服常见的内存主状态 + 批量/事务/异步落库模式，这个结果不仅说明可以用于生产，而且已经明确显示出 `28x ~ 100x` 量级的写路径优化空间。**

换句话说，是否能上生产，决定因素不是 ePgdb 本身，而是你怎么设计写入路径。