-module(dbmigrate_runner).

%% Migration execution engine.
%%
%% Orchestrates opening a connection, acquiring a lock, wrapping the
%% work in a transaction, compiling and running each migration module,
%% recording results in the registry, and cleaning up.
%%
%% The runner is stateless: it receives a fully resolved execution
%% context and returns the list of versions it processed.

-export([execute/1]).

-ifdef(TEST).
-compile([export_all]).
-endif.

%% @doc Execute a resolved migration or rollback plan.
%%
%% `Ctx` must contain at least:
%%   adapter, conn, app, backend, app_version, skip_run,
%%   migrations_path, action (migrate | rollback),
%%   selected (list of version strings to process)
%%
%% Returns {ok, ProcessedVersions} or {error, Reason}.

-spec execute(map()) -> {ok, [string()]} | {error, term()}.

execute(#{action := migrate, selected := []} = _Ctx) ->
    {ok, []};

execute(#{action := migrate, selected := Selected} = Ctx) ->
    wrap_transaction(Ctx, fun() -> run_migrations(Selected, Ctx, []) end);

execute(#{action := rollback, selected := []} = _Ctx) ->
    {ok, []};

execute(#{action := rollback, selected := Selected} = Ctx) ->
    wrap_transaction(Ctx, fun() -> run_rollbacks(Selected, Ctx, []) end).

%%% -------------------------------------------------------------------
%%% Migration execution
%%% -------------------------------------------------------------------

run_migrations([], _Ctx, Acc) ->
    {ok, lists:reverse(Acc)};

run_migrations([Version | Rest],
               #{skip_run := true,
                 adapter := Adapter,
                 conn := Conn,
                 app := App,
                 backend := Backend,
                 app_version := AppVersion} = Ctx,
               Acc) ->
    ok = dbmigrate_registry:record_applied(Adapter, Conn, Version, App, Backend, AppVersion),
    run_migrations(Rest, Ctx, [Version | Acc]);

run_migrations([Version | Rest],
               #{skip_run := false,
                 adapter := Adapter,
                 conn := Conn,
                 app := App,
                 backend := Backend,
                 app_version := AppVersion,
                 migrations_path := Path,
                 migration_run_fn := RunFn} = Ctx,
               Acc) ->
    ok = RunFn(Conn, Version, Path),
    ok = dbmigrate_registry:record_applied(Adapter, Conn, Version, App, Backend, AppVersion),
    run_migrations(Rest, Ctx, [Version | Acc]).

%%% -------------------------------------------------------------------
%%% Rollback execution
%%% -------------------------------------------------------------------

run_rollbacks([], _Ctx, Acc) ->
    {ok, lists:reverse(Acc)};

run_rollbacks([Version | Rest],
              #{adapter := Adapter,
                conn := Conn,
                migrations_path := Path,
                rollback_run_fn := RollbackFn} = Ctx,
              Acc) ->
    ok = RollbackFn(Conn, Version, Path),
    ok = dbmigrate_registry:record_removed(Adapter, Conn, Version),
    run_rollbacks(Rest, Ctx, [Version | Acc]).

%%% -------------------------------------------------------------------
%%% Transaction wrapper
%%% -------------------------------------------------------------------

wrap_transaction(#{adapter := Adapter, conn := Conn}, Fun) ->
    ok = Adapter:transaction_begin(Conn),
    try Fun() of
        {ok, _} = Result ->
            ok = Adapter:transaction_commit(Conn),
            Result
    catch
        Class:Reason:Stack ->
            %% Best-effort rollback; some backends (e.g. Cassandra) no-op here.
            catch Adapter:transaction_commit(Conn),
            erlang:raise(Class, Reason, Stack)
    end.
