-module(dbmigrate).

%% Public API facade.
%%
%% This module is a thin entry point that keeps the legacy export
%% surface intact.  Every function normalises its arguments into a
%% request map (via dbmigrate_request), resolves which migrations to
%% run (via dbmigrate_plan), and hands execution to dbmigrate_runner.

-export([start/0, stop/0]).
-export([gen_migration/3, migrate/1, migrate/2, migrate/3, migrate_n/1, migrate_n/3,
         migrate_one/1, migrate_one/2, migrate_to/1, migrate_to/3, migrate_specific/1,
         migrate_specific/3, migrate_mark_as_applied/1, rollback_app_version/1,
         rollback_app_version/3, rollback_one/1, rollback_one/2, rollback_n/1, rollback_n/3,
         rollback_to/1, rollback_to/3]).

-ifdef(TEST).
-compile([export_all]).
-endif.

-define(APP, ?MODULE).

%%%===================================================================
%%% Application lifecycle
%%%===================================================================

start() ->
    reltool_util:application_start(?APP).

stop() ->
    reltool_util:application_stop(?APP).

%%%===================================================================
%%% Migration generation
%%%===================================================================

gen_migration(App, Db, Name)
    when is_atom(App) andalso is_atom(Db) andalso is_list(Name) ->
    Adapter = init_backend(App, Db),
    Path = dbmigrate_loader:migrations_path(App, Db),
    FileName = dbmigrate_loader:generate_version()
               ++ "_"
               ++ dbmigrate_loader:underscore(string:to_lower(Name))
               ++ ".erl",
    FilePath = filename:join(Path, FileName),
    ok = file:write_file(FilePath, Adapter:file_template(FileName)),
    {ok, FilePath}.

%%%===================================================================
%%% Migrate
%%%===================================================================

migrate([App, Db]) ->
    migrate(App, Db, []);
migrate([App, Db, Opts]) ->
    migrate(App, Db, Opts).

migrate(App, Db) when is_atom(App) andalso is_atom(Db) ->
    migrate(App, Db, []).

migrate(App, Db, Opts) when is_atom(App) andalso is_atom(Db) ->
    Req = dbmigrate_request:build({migrate, App, Db, Opts}),
    {ok, Applied} = run_request(Req),
    logger:info("migrations_apply, success: ~p", [Applied]),
    ok.

migrate_mark_as_applied([App, Db]) ->
    migrate(App, Db, [{skip_run, true}]).

migrate_one([App, Db]) ->
    migrate_one(App, Db).

migrate_one(App, Db) when is_atom(App) andalso is_atom(Db) ->
    Req = dbmigrate_request:build({migrate_one, App, Db}),
    {ok, Applied} = run_request(Req),
    logger:info("migrated one: ~p", [Applied]),
    ok.

migrate_n([App, Db, N]) ->
    migrate_n(App, Db, N).

migrate_n(App, Db, N) when is_atom(App) andalso is_atom(Db) ->
    Req = dbmigrate_request:build({migrate_n, App, Db, N}),
    {ok, Applied} = run_request(Req),
    logger:info("migrated n (~p): ~p", [N, Applied]),
    ok.

migrate_to([App, Db, To]) ->
    migrate_to(App, Db, To).

migrate_to(App, Db, To) when is_atom(App) andalso is_atom(Db) ->
    Req = dbmigrate_request:build({migrate_to, App, Db, To}),
    {ok, Applied} = run_request(Req),
    logger:info("migrated to (~p): ~p", [To, Applied]),
    ok.

migrate_specific([App, Db, Migration]) ->
    migrate_specific(App, Db, Migration).

migrate_specific(App, Db, Migration) when is_atom(App) andalso is_atom(Db) ->
    Req = dbmigrate_request:build({migrate_specific, App, Db, Migration}),
    {ok, Applied} = run_request(Req),
    logger:info("migrated specific ~p", [Applied]),
    ok.

%%%===================================================================
%%% Rollback
%%%===================================================================

rollback_app_version([App, Db, AppVersion]) ->
    rollback_app_version(App, Db, AppVersion).

rollback_app_version(App, Db, AppVersion) when is_atom(App) andalso is_atom(Db) ->
    Req = dbmigrate_request:build({rollback_app_version, App, Db, AppVersion}),
    {ok, Rolled} = run_request(Req),
    logger:info("rollback app version (~p): ~p", [AppVersion, Rolled]),
    ok.

rollback_one([App, Db]) ->
    rollback_one(App, Db).

rollback_one(App, Db) when is_atom(App) andalso is_atom(Db) ->
    Req = dbmigrate_request:build({rollback_one, App, Db}),
    {ok, Rolled} = run_request(Req),
    logger:info("rollback one: ~p", [Rolled]),
    ok.

rollback_n([App, Db, N]) ->
    rollback_n(App, Db, N).

rollback_n(App, Db, N) when is_atom(App) andalso is_atom(Db) ->
    Req = dbmigrate_request:build({rollback_n, App, Db, N}),
    {ok, Rolled} = run_request(Req),
    logger:info("rollback n (~p): ~p", [N, Rolled]),
    ok.

rollback_to([App, Db, To]) ->
    rollback_to(App, Db, To).

rollback_to(App, Db, To) when is_atom(App) andalso is_atom(Db) ->
    Req = dbmigrate_request:build({rollback_to, App, Db, To}),
    {ok, Rolled} = run_request(Req),
    logger:info("rollback to (~p): ~p", [To, Rolled]),
    ok.

%%%===================================================================
%%% Internal — orchestration pipeline
%%%===================================================================

%% @doc Full pipeline: init → gather state → plan → execute → teardown.
run_request(#{app := App, backend := Backend} = Req) ->
    Adapter = init_backend(App, Backend),
    Path = dbmigrate_loader:migrations_path(App, Backend),
    Conn = Adapter:connect(App, Backend),
    try
        Available = dbmigrate_loader:available(Path),
        Applied = dbmigrate_registry:fetch_applied(Adapter, Conn, App, Backend),
        AppVersion = maps:get(app_version, Req, undefined),
        AppliedByVersion = fetch_versioned_applied(Adapter, Conn, App, Backend, AppVersion),

        PlanInput = Req#{migrations_available => Available,
                         migrations_applied => Applied,
                         migrations_applied_by_version => AppliedByVersion},

        {ok, Plan} = dbmigrate_plan:resolve(PlanInput),

        RunCtx = #{adapter => Adapter,
                   conn => Conn,
                   app => App,
                   backend => Backend,
                   app_version => AppVersion,
                   skip_run => maps:get(skip_run, Req, false),
                   migrations_path => Path,
                   migration_run_fn => migration_run_fn(),
                   rollback_run_fn => rollback_run_fn(),
                   action => maps:get(action, Plan),
                   selected => maps:get(selected, Plan)},

        dbmigrate_runner:execute(RunCtx)
    after
        Adapter:close(Conn)
    end.

%% Optionally query version-scoped applied migrations.
fetch_versioned_applied(_Adapter, _Conn, _App, _Backend, undefined) ->
    [];
fetch_versioned_applied(Adapter, Conn, App, Backend, AppVersion) ->
    dbmigrate_registry:fetch_applied_by_version(Adapter, Conn, App, Backend, AppVersion).

%%%===================================================================
%%% Internal — backend initialisation
%%%===================================================================

init_backend(App, Db) ->
    _ = application:load(App),
    Adapter = resolve_adapter(App, Db),
    ok = Adapter:init(),
    ok = filelib:ensure_dir(dbmigrate_loader:migrations_path(App, Db) ++ "/foo"),
    ok = Adapter:ensure_repo(App, Db),
    Adapter.

resolve_adapter(App, Db) ->
    AppDbOpts = dbmigrate_utils:app_db_opts(App, Db),
    proplists:get_value(adapter, AppDbOpts).

%%%===================================================================
%%% Internal — compile-and-run helpers
%%%===================================================================

migration_run_fn() ->
    application:get_env(dbmigrate, migration_run_fn, fun migration_run/3).

rollback_run_fn() ->
    application:get_env(dbmigrate, rollback_run_fn, fun rollback_run/3).

migration_run(Conn, Version, Path) ->
    {ok, Mod} = dbmigrate_loader:compile_and_load(Version, Path),
    ok = Mod:up(Conn),
    ok.

rollback_run(Conn, Version, Path) ->
    {ok, Mod} = dbmigrate_loader:compile_and_load(Version, Path),
    ok = Mod:down(Conn),
    ok.

%%%===================================================================
%%% Legacy internal API — kept for backward-compatible eunit tests
%%% (exported only when compiled with TEST)
%%%===================================================================

-ifdef(TEST).

migrations_apply_all(Env) ->
    dispatch_legacy(migrate, all, Env).

migrations_apply_one(Env) ->
    dispatch_legacy(migrate, {count, 1}, Env).

migrations_apply_n(Env, N0) ->
    N = ensure_integer(N0),
    dispatch_legacy(migrate, {count, N}, Env).

migrations_apply_to(Env, To0) ->
    To = ensure_list(To0),
    dispatch_legacy(migrate, {to, To}, Env).

migrations_apply_specific(Env, Migration) ->
    dispatch_legacy(migrate, {specific, Migration}, Env).

migrations_rollback_one(Env) ->
    dispatch_legacy(rollback, {count, 1}, Env).

migrations_rollback_n(Env, N0) ->
    N = ensure_integer(N0),
    dispatch_legacy(rollback, {count, N}, Env).

migrations_rollback_to(Env, To0) ->
    To = ensure_list(To0),
    dispatch_legacy(rollback, {to, To}, Env).

migrations_rollback_app_version(Env) ->
    dispatch_legacy(rollback, app_version, Env).

%% Translate the old env map into the new plan/runner flow and return
%% the same {ok, Versions, UpdatedEnv} shape that the tests expect.
dispatch_legacy(Action, Mode, Env) ->
    #{adapter := Adapter,
      conn := Conn,
      application := App,
      application_version := AppVersion,
      skip_run := SkipRun,
      migration_type := Backend,
      migrations_path := Path,
      migrations_applied := Applied,
      migrations_not_applied := NotApplied,
      migrations_applied_by_version := AppliedByVersion} = Env,

    PlanInput = #{action => Action,
                  mode => Mode,
                  migrations_available => lists:sort(Applied ++ NotApplied),
                  migrations_applied => Applied,
                  migrations_applied_by_version => AppliedByVersion},

    case dbmigrate_plan:resolve(PlanInput) of
        {error, _} = Err ->
            Err;
        {ok, #{selected := Selected}} ->
            RunCtx = #{adapter => Adapter,
                       conn => Conn,
                       app => App,
                       backend => Backend,
                       app_version => AppVersion,
                       skip_run => SkipRun,
                       migrations_path => Path,
                       migration_run_fn => migration_run_fn(),
                       rollback_run_fn => rollback_run_fn(),
                       action => Action,
                       selected => Selected},

            {ok, Processed} = dbmigrate_runner:execute(RunCtx),

            %% Rebuild the env to match what old tests assert.
            %% For 'specific' mode, the original code did not modify the env maps.
            case Mode of
                {specific, _} ->
                    {ok, Processed, Env};
                _ ->
                    NewApplied = case Action of
                                     migrate ->
                                         lists:sort(Applied ++ Processed);
                                     rollback ->
                                         lists:sort(Applied -- Processed)
                                 end,
                    NewNotApplied = case Action of
                                        migrate ->
                                            lists:sort(NotApplied -- Processed);
                                        rollback ->
                                            lists:sort(NotApplied ++ Processed)
                                    end,
                    NewByVersion = case Action of
                                       migrate -> AppliedByVersion;
                                       rollback -> lists:sort(AppliedByVersion -- Processed)
                                   end,

                    {ok, Processed,
                     Env#{migrations_applied => NewApplied,
                          migrations_not_applied => NewNotApplied,
                          migrations_applied_by_version => NewByVersion}}
            end
    end.

ensure_integer(N) when is_integer(N) -> N;
ensure_integer(N) when is_list(N) -> list_to_integer(N).

ensure_list(V) when is_list(V) -> V;
ensure_list(V) when is_binary(V) -> binary_to_list(V).

-endif.
