%%%-------------------------------------------------------------------
%%% @doc pg_types_schema 定义汇总
%%% 此文件由 genPSchema 自动生成，请勿手动修改。
%%%-------------------------------------------------------------------
-ifndef(PG_TYPES_SCHEMA_HRL).
-define(PG_TYPES_SCHEMA_HRL, true).

%%数值类型全覆盖
-record(numeric_samples, {
    id :: integer()                                                         %% 自增主键 bigserial
    , tiny_id :: integer()                                                  %% 自增 serial
    , small_val = 0 :: integer()                                            %% smallint 带默认值
    , int_val = 42 :: integer()                                             %% integer 带默认值
    , int_alias = 0 :: integer()                                            %% int (integer 别名)
    , big_val = 0 :: non_neg_integer()                                      %% bigint + 自定义 erlType
    , float_val = 0.0 :: float()                                            %% float 单精度
    , double_val = 0.0 :: float()                                           %% double 双精度 + erlType
    , money = 0 :: number()                                                 %% numeric(12,2) 金额
    , ratio :: number()                                                     %% numeric(5,4) 比率
}).

%%文本类型全覆盖
-record(text_samples, {
    id :: integer()                                                         %% 主键
    , content = <<>> :: binary()                                            %% text 无限长文本
    , short_name :: binary()                                                %% varchar(32) 非空唯一
    , long_desc = <<>> :: binary()                                          %% varchar(2048) 长描述
    , country_code = <<"CN">> :: binary()                                   %% char(2) 国家代码
    , fixed_code :: binary()                                                %% char(6) 定长编码
    , trace_id :: binary()                                                  %% uuid 跟踪ID
    , client_ip :: binary()                                                 %% inet 客户端IP
}).

%%时间日期类型全覆盖 (map 表示)
-type time_samples() :: #{
    id => integer()                                                         %% 主键
    , table_name => binary()                                                %% 所属表名
    , created_at => binary()                                                %% timestamptz 含时区
    , updated_at => binary()                                                %% timestamp 不含时区
    , birth_date => binary()                                                %% date 仅日期
    , alarm_time => binary()                                                %% time 仅时间
    , expire_at => binary() | undefined                                     %% 可空的时间戳 + erlType
}.

-define(time_samples_map(), #{
    id => undefined                                                         %% 主键
    , table_name => <<"time_samples">>                                      %% 所属表名
    , created_at => undefined                                               %% timestamptz 含时区
    , updated_at => undefined                                               %% timestamp 不含时区
    , birth_date => undefined                                               %% date 仅日期
    , alarm_time => undefined                                               %% time 仅时间
    , expire_at => undefined                                                %% 可空的时间戳 + erlType
}).

%%JSON与二进制类型覆盖
-record(json_binary_samples, {
    id :: integer()                                                         %% 主键
    , config = #{} :: map()                                                 %% json 保留原始格式
    , metadata = #{} :: map()                                               %% jsonb 支持索引
    , payload :: map() | list()                                             %% jsonb 也可能是列表
    , avatar :: binary()                                                    %% bytea 二进制头像
    , snapshot = <<>> :: binary()                                           %% bytea 带默认空二进制
    , settings = #{auto_login => true} :: #{atom() => term()}               %% jsonb 带复杂默认值 + 精确 erlType
    , json_as_text = #{} :: map()                                           %% text 列存 JSON, codec_json 编解码
    , term_readable :: term()                                               %% text 列存 Erlang term 可读字符串, codec_term_str
    , term_blob :: term()                                                   %% bytea 列存 Erlang term 二进制, codec_term_binary
    , status_name = active :: atom()                                        %% varchar 列存 atom, codec_atom 编解码
    , runtime_cache = #{dirty => false} :: map()                            %% 仅应用层临时缓存字段, codec_temp 不入库
    , custom_blob = #{source => demo} :: map()                              %% bytea 列使用 ePgdb:demo_custom_codec/5 做自定义编解码
    , dirty_flag = 0 :: intrger()                                           %% 仅应用层临时缓存字段, codec_temp 不入库
}).

%%复合类型覆盖: array, enum
-record(composite_samples, {
    id :: integer()                                                         %% 主键
    , tags = [] :: [binary()]                                               %% text[] 文本数组
    , scores = [] :: [integer()]                                            %% integer[] + erlType
    , matrix = [] :: [float()]                                              %% double[] 浮点数组
    , uuids = [] :: [binary()]                                              %% uuid[] UUID 数组
    , status = active :: atom()                                             %% enum atom 模式
    , role = <<"user">> :: binary()                                         %% enum binary 模式
    , priority = normal :: low | normal | high | critical                   %% enum atom + 联合 erlType
}).

%%约束选项全覆盖 (map 表示)
-type constraint_samples() :: #{
    id => integer()                                                         %% 主键约束
    , table_name => binary()                                                %% 所属表名
    , owner_id => integer()                                                 %% 外键 + cascade
    , group_id => integer()                                                 %% 外键 + set_null
    , ref_id => integer()                                                   %% 外键 无级联 (默认 NO ACTION)
    , email => binary()                                                     %% 非空 + 唯一 + 索引
    , score => integer()                                                    %% check 约束
    , level => integer()                                                    %% 多约束组合: 非空+check+索引
    , nickname => binary()                                                  %% 仅索引
    , data => map()                                                         %% jsonb 数据
}.

-define(constraint_samples_map(), #{
    id => undefined                                                         %% 主键约束
    , table_name => <<"constraint_samples">>                                %% 所属表名
    , owner_id => undefined                                                 %% 外键 + cascade
    , group_id => undefined                                                 %% 外键 + set_null
    , ref_id => undefined                                                   %% 外键 无级联 (默认 NO ACTION)
    , email => undefined                                                    %% 非空 + 唯一 + 索引
    , score => 0                                                            %% check 约束
    , level => 1                                                            %% 多约束组合: 非空+check+索引
    , nickname => undefined                                                 %% 仅索引
    , data => #{}                                                           %% jsonb 数据
}).

%%erlType 赋值方式展示
-record(erl_type_showcase, {
    id :: integer()                                                         %% 主键
    , count :: non_neg_integer()                                            %% 非负整数
    , rate :: float()                                                       %% float
    , flag :: boolean()                                                     %% 布尔
    , value :: integer() | undefined                                        %% 可空整数
    , label :: binary() | <<>>                                              %% 二进制或空串
    , profile :: #{binary() => term()}                                      %% map 精确 key 类型
    , history :: [map()]                                                    %% map列表
    , coords :: [float()]                                                   %% 坐标浮点列表
    , ids :: [pos_integer()]                                                %% 正整数列表
    , state = idle :: idle | running | stopped                              %% 有限atom联合
    , color = <<"red">> :: binary()                                         %% 有限binary联合
    , position = #{y => 0,x => 0} :: #{x => number(), y => number()}        %% 坐标map类型
    , extra = null :: term()                                                %% 完全通用 term
}).


-endif.
