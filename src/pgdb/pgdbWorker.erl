%%%-------------------------------------------------------------------
%%% @doc ePgdb pool worker 启动入口。
%%% 直接启动一个 epgsql 连接进程，并把该连接 pid 交给 eFaw 作为 pool worker。
%%%-------------------------------------------------------------------
-module(pgdbWorker).

-export([start_link/3]).

start_link(_FName, _PoolWorkerTag, Args) ->
	connect(Args).

connect(Config) ->
	Host = pgdbUtils:getOpt(host, Config, "localhost"),
	Port = pgdbUtils:getOpt(port, Config, 5432),
	Database = pgdbUtils:getOpt(database, Config, "game_db"),
	Username = pgdbUtils:getOpt(username, Config, "postgres"),
	Password = pgdbUtils:getOpt(password, Config, "postgres"),
	Timeout = pgdbUtils:getOpt(timeout, Config, 5000),
	TcpOpts = pgdbUtils:getOpt(tcpOpts, Config, [{keepalive, true}]),
	BaseConnOpts = #{
		host => Host,
		port => Port,
		database => Database,
		username => Username,
		password => Password,
		timeout => Timeout,
		tcp_opts => TcpOpts
	},

	UseSsl = pgdbUtils:getOpt(ssl, Config, false),
	ConnOpts = case UseSsl of true -> BaseConnOpts#{ssl => true, ssl_opts => pgdbUtils:getOpt(sslOpts, Config, [])}; _ -> BaseConnOpts end,
	epgsql:connect(ConnOpts).
