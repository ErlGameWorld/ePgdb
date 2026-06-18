%%%-------------------------------------------------------------------
%%% @doc pg_bench_schema 定义汇总
%%% 此文件由 genPSchema 自动生成，请勿手动修改。
%%%-------------------------------------------------------------------
-ifndef(PG_BENCH_SCHEMA_HRL).
-define(PG_BENCH_SCHEMA_HRL, true).

%%压测用户表
-record(bench_users, {
    id :: integer()                                                         %% 自增主键
    , name :: binary()                                                      %% 用户名
    , email :: binary()                                                     %% 邮箱
    , age = 0 :: integer()                                                  %% 年龄
    , score = 0 :: non_neg_integer()                                        %% 积分
    , balance = 0 :: number()                                               %% 余额
    , is_active = true :: boolean()                                         %% 是否活跃
    , profile = #{} :: map()                                                %% 画像数据
    , tags = [] :: [binary()]                                               %% 标签
    , login_at :: binary()                                                  %% 最后登录
    , created_at :: binary()                                                %% 创建时间
}).

%%压测订单表
-record(bench_orders, {
    id :: integer()                                                         %% 订单ID
    , user_id :: integer()                                                  %% 用户ID (外键+索引)
    , order_no :: binary()                                                  %% 订单号
    , amount = 0 :: number()                                                %% 金额
    , quantity = 1 :: integer()                                             %% 数量
    , status = <<"pending">> :: binary()                                    %% 状态: pending/paid/shipped/done
    , items = [] :: [map()]                                                 %% 订单明细 JSON 数组
    , paid_at :: binary() | undefined                                       %% 支付时间 (可空)
    , created_at :: binary()                                                %% 创建时间
}).

%%压测事件日志表 (map 表示)
-type bench_events() :: #{
    id => integer()                                                         %% 事件ID
    , table_name => binary()                                                %% 所属表名
    , event_type => binary()                                                %% 事件类型
    , source => system | user | cron | api                                  %% 事件来源
    , level => integer()                                                    %% 严重级别 0~5
    , actor_id => integer()                                                 %% 操作者ID
    , payload => map()                                                      %% 事件详情
    , extra => term()                                                       %% 扩展数据 (Erlang term 可读字符串)
    , trace_id => binary()                                                  %% 链路追踪ID
    , client_ip => binary()                                                 %% 客户端IP
    , occurred_at => binary()                                               %% 发生时间
}.

-define(bench_events_map(), #{
    id => undefined                                                         %% 事件ID
    , table_name => <<"bench_events">>                                      %% 所属表名
    , event_type => undefined                                               %% 事件类型
    , source => system                                                      %% 事件来源
    , level => 0                                                            %% 严重级别 0~5
    , actor_id => undefined                                                 %% 操作者ID
    , payload => #{}                                                        %% 事件详情
    , extra => undefined                                                    %% 扩展数据 (Erlang term 可读字符串)
    , trace_id => undefined                                                 %% 链路追踪ID
    , client_ip => undefined                                                %% 客户端IP
    , occurred_at => undefined                                              %% 发生时间
}).

%%压测KV表 (极简高频读写)
-type bench_kv() :: #{
    key => binary()                                                         %% 键
    , table_name => binary()                                                %% 所属表名
    , value => term()                                                       %% 值 (text 列存 JSON, codec_json)
    , version => integer()                                                  %% 乐观锁版本号
    , ttl => non_neg_integer()                                              %% TTL 秒数, 0=永不过期
    , updated_at => binary()                                                %% 更新时间
}.

-define(bench_kv_map(), #{
    key => undefined                                                        %% 键
    , table_name => <<"bench_kv">>                                          %% 所属表名
    , value => null                                                         %% 值 (text 列存 JSON, codec_json)
    , version => 1                                                          %% 乐观锁版本号
    , ttl => 0                                                              %% TTL 秒数, 0=永不过期
    , updated_at => undefined                                               %% 更新时间
}).

%%压测大对象表 (bytea 读写)
-record(bench_blobs, {
    id :: integer()                                                         %% 主键
    , name :: binary()                                                      %% 名称
    , mime_type = <<"application/octet-stream">> :: binary()                %% MIME 类型
    , size_bytes = 0 :: non_neg_integer()                                   %% 文件大小
    , data = <<>> :: binary()                                               %% 二进制数据
    , checksum :: binary()                                                  %% MD5 校验和
    , created_at :: binary()                                                %% 上传时间
}).


-endif.
