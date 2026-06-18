%%%-------------------------------------------------------------------
%%% @doc pg_player_schema 定义汇总
%%% 此文件由 genPSchema 自动生成，请勿手动修改。
%%%-------------------------------------------------------------------
-ifndef(PG_PLAYER_SCHEMA_HRL).
-define(PG_PLAYER_SCHEMA_HRL, true).

%%玩家主表
-record(players, {
    id :: integer()                                                         %% 玩家唯一ID
    , name :: binary()                                                      %% 玩家名字
    , level = 1 :: integer()                                                %% 等级
    , gold = 0 :: integer()                                                 %% 金币
    , vip = false :: boolean()                                              %% 是否VIP
    , status = <<"idle">> :: binary()                                       %% 状态
    , profile = #{} :: map()                                                %% 玩家档案JSON
    , tags = [] :: [binary()]                                               %% 标签列表
    , created_at :: binary()                                                %% 创建时间
}).

%%道具表
-record(items, {
    id :: integer()                                                         %% 道具唯一ID
    , player_id :: integer()                                                %% 所属玩家ID
    , item_type :: atom()                                                   %% 道具类型 (atom: sword/shield/potion)
    , count = 1 :: integer()                                                %% 数量
    , attrs :: map()                                                        %% 扩展属性
    , state_data :: term()                                                  %% 道具状态 (Erlang term 二进制序列化)
}).


-endif.
