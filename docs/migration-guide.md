# ePgdb 迁移系统说明

本文档专门说明 ePgdb:migrate/1、ePgdb:rollback/2 和 ePgdb:status/0,1 的使用方式、执行流程以及生产环境建议。

## 1. 入口函数

对外入口在 ePgdb 模块：

```erlang
ePgdb:migrate(Migrations).
ePgdb:rollback(Migrations, TargetVersion).
ePgdb:status(Migrations).   %% 或 ePgdb:status() 查看所有
```

其中：

- ePgdb:migrate/1：执行未应用的迁移
- ePgdb:rollback/2：回滚到目标版本
- ePgdb:status/0,1：查看各版本状态

## 2. 迁移数据格式

每条迁移都是一个 4 元组：

```erlang
{Version, Description, UpFun, DownFun}
```

含义如下：

1. Version：迁移版本号，必须唯一，通常递增
2. Description：迁移描述，便于排查和记录，支持 binary、string/iolist 或 atom
3. UpFun：升级函数
4. DownFun：回滚函数

示例：

```erlang
Migrations = [
    {1, "创建 players 表",
        fun(_Conn) ->
            ePgdb:createTable(players, [
                {id, bigserial, [primary_key]},
                {name, {varchar, 64}, [not_null, unique]},
                {level, integer, [{default, 1}]}
            ])
        end,
        fun(_Conn) ->
            ePgdb:dropTable(players)
        end},

    {2, "给 players 增加 gold 字段",
        fun(_Conn) ->
            ePgdb:addColumn(players, gold, bigint, [{default, 0}])
        end,
        fun(_Conn) ->
            ePgdb:dropColumn(players, gold)
        end}
].
```

执行迁移：

```erlang
ok = ePgdb:migrate(Migrations).
```

## 3. 实际执行流程

当前实现的 run/1 会按下面的步骤执行：

1. 获取 PostgreSQL advisory lock，避免多节点重复跑迁移
2. 确保 _pgdb_migrations 表存在
3. 读取已执行过的版本号
4. 从传入列表中找出未执行版本
5. 按版本号从小到大执行
6. 每个版本单独开启事务
7. 成功后写入 _pgdb_migrations
8. 任一版本失败则立刻停止

锁和事务现在复用同一条数据库连接，因此在极小连接池配置下也不会因为“拿着锁再排队等第二条连接”而自阻塞。

这意味着：

- 已执行成功的旧版本不会重复执行
- 某一版本失败，只回滚该版本自身事务
- 前面已经成功的版本不会被整体回退

## 4. 返回值

成功：

```erlang
ok
```

失败：

```erlang
{error, {migration_failed, Version, Reason}}
```

例如：

```erlang
{error, {migration_failed, 3, Reason}}
```

表示第 3 个版本执行失败。

回滚失败时：

```erlang
{error, {rollback_failed, Version, Reason}}
```

## 5. 事务语义

每个 migration 是单独事务，不是整个迁移列表一个总事务。

例如：

1. 版本 1 成功并提交
2. 版本 2 成功并提交
3. 版本 3 失败并回滚

最终数据库会保留版本 1 和版本 2 的结果。

这种行为更适合实际线上服务，因为不会因为后面某一步失败，把已经成功的历史迁移全部撤销。

## 6. Conn 参数怎么用

UpFun 和 DownFun 的形参是事务连接：

```erlang
fun(Conn) ->
    ...
end
```

如果你只是调用 ePgdb:createTable/2、ePgdb:addColumn/4 这种普通 API，内部走的是连接池封装，不一定绑定到这个 Conn。

如果你希望某些 DDL 明确跑在当前事务连接上，当前项目已经新增了两个辅助能力：

```erlang
ePgdb:withConnection(Fun).
ePgdb:ddl(Conn, Sql).
```

推荐做法是结合 pgdbQuery 构建 SQL，再用 ddl/2 在迁移连接上执行：

```erlang
{CreateSql, _} = {pgdbQuery:buildCreateTable(players, [
    {id, bigserial, [primary_key]},
    {name, {varchar, 64}, [not_null]}
]), ok},
ok = ePgdb:ddl(Conn, CreateSql).
```

更直接一点可以写成：

```erlang
fun(Conn) ->
    CreateSql = pgdbQuery:buildCreateTable(players, [
        {id, bigserial, [primary_key]},
        {name, {varchar, 64}, [not_null]}
    ]),
    ok = ePgdb:ddl(Conn, CreateSql)
end
```

这个方式更适合需要“明确在迁移事务里执行 DDL”的场景。

## 7. 查看状态

可以用下面的方式查看迁移状态：

```erlang
{ok, Status} = ePgdb:status(Migrations).
```

返回示例：

```erlang
{ok, [
    {1, "创建 players 表", applied},
    {2, "给 players 增加 gold 字段", pending}
]}
```

状态值只有两个：

- applied：已执行
- pending：未执行

## 8. 回滚

调用方式：

```erlang
ePgdb:rollback(Migrations, TargetVersion).
```

例如：

```erlang
ok = ePgdb:rollback(Migrations, 1).
```

表示回滚所有版本号大于 1 的迁移。

执行顺序是从大到小逆序执行 DownFun，这样才符合依赖关系。

## 9. 服务启动时的推荐接入方式

建议在应用启动时执行迁移：

```erlang
initDb() ->
   Migrations = my_game_migrations:migrations(),
   case ePgdb:migrate(Migrations) of
      ok ->
         ok;
      {error, Reason} ->
         exit({db_migrate_failed, Reason})
   end.
```

这样能保证服务真正对外提供功能前，数据库结构已经到最新版本。

## 10. 生产环境建议

建议遵守下面这些规则：

1. 一个 migration 只做一件明确的事
2. version 必须单调递增，不能复用
3. 已上线的 migration 不要修改，只新增新版本
4. 数据修复和表结构变更尽量拆开写
5. DownFun 要尽量可逆，但不要为了可逆做危险删除

推荐拆分方式：

```erlang
{1, "创建 players 表", ...}
{2, "增加 gold 字段", ...}
{3, "补历史数据", ...}
{4, "增加索引", ...}
```

## 11. 当前项目里已经补上的优化

本项目目前已经针对迁移系统做了两项比较实用的增强：

1. 使用 advisory lock，避免多节点并发重复执行迁移
2. 提供 withConnection/1 和 ddl/2，便于在指定连接上执行迁移级 DDL

如果你后面要继续强化，可以再考虑：

1. 增加 migration checksum，防止同版本内容被篡改
2. 增加 dry-run 模式
3. 增加启动阶段统一迁移模块加载约定
