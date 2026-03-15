-module(dbmigrate_adapter).

%% Behaviour definition for database adapters.
%%
%% Each adapter implements backend-specific primitives for connection
%% management, schema tracking, transactions, and locking.

%% --- Connection lifecycle ---

-callback init() -> ok.

-callback connect(App :: atom(), Db :: atom()) -> Connection :: term().

-callback close(Connection :: term()) -> ok.

%% --- Schema table management ---

-callback ensure_repo(App :: atom(), Db :: atom()) -> ok.

%% --- Migration tracking ---

-callback migrations_applied(Connection :: term(),
                              AppName :: atom(),
                              Type :: atom()) -> [string()].

-callback migrations_applied_by_version(Connection :: term(),
                                         AppName :: atom(),
                                         Type :: atom(),
                                         AppVersion :: string()) -> [string()].

-callback migrations_upgrade(Connection :: term(),
                              Version :: string(),
                              AppName :: atom(),
                              Type :: atom(),
                              AppVersion :: string()) -> ok.

-callback migrations_downgrade(Connection :: term(),
                                Version :: string()) -> ok.

%% --- Transaction support ---

-callback transaction_begin(Connection :: term()) -> ok.

-callback transaction_commit(Connection :: term()) -> ok.

%% --- Advisory locking ---

-callback acquire_lock(Connection :: term()) -> ok | {error, term()}.

-callback release_lock(Connection :: term()) -> ok | {error, term()}.

%% --- Migration file scaffolding ---

-callback file_template(FileName :: string()) -> iolist().

%% Optional callbacks — adapters that don't support locking can skip these.
-optional_callbacks([acquire_lock/1, release_lock/1]).
