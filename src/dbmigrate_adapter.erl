-module(dbmigrate_adapter).

-callback init() -> ok.
-callback connect(App :: atom(), Db :: atom()) -> Connection :: term().
-callback close(Connection :: term()) -> ok.
-callback ensure_repo(App :: atom(), Db :: atom()) -> ok.
-callback migrations_applied(Connection :: term(), AppName :: atom(), Type :: atom()) ->
                                [string()].
-callback migrations_upgrade(Connection :: term(),
                             Version :: string(),
                             AppName :: atom(),
                             Type :: atom(),
                             AppVersion :: string()) ->
                                ok.
-callback migrations_downgrade(Connection :: term(), Version :: string()) -> ok.
-callback transaction_start(Connection :: term()) -> ok.
-callback transaction_end(Connection :: term()) -> ok.
-callback file_template(FileName :: string()) -> iolist().
