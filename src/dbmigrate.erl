-module(dbmigrate).

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

migration_run_fn() ->
    application:get_env(dbmigrate, migration_run_fn, fun migration_run/3).

rollback_run_fn() ->
    application:get_env(dbmigrate, rollback_run_fn, fun rollback_run/3).

%%%===================================================================
%%% anacl_adapter API
%%%===================================================================
start() ->
    reltool_util:application_start(?APP).

stop() ->
    reltool_util:application_stop(?APP).

gen_migration(App, Db, Name)
    when is_atom(App) andalso is_atom(Db) andalso is_list(Name) ->
    Adapter = init(App, Db),
    Path = migrations_path(App, Db),
    FileName = version() ++ "_" ++ underscore(string:to_lower(Name)) ++ ".erl",
    FilePath = filename:join(Path, FileName),
    ok = file:write_file(FilePath, Adapter:file_template(FileName)),
    {ok, FilePath}.

migrate([App, Db]) ->
    migrate(App, Db, []);
migrate([App, Db, Opts]) ->
    migrate(App, Db, Opts).

migrate(App, Db) when is_atom(App) andalso is_atom(Db) ->
    migrate(App, Db, []).

migrate(App, Db, Opts) when is_atom(App) andalso is_atom(Db) ->
    MigrationEnv0 = init_migration(App, Db, Opts),
    {ok, NewlyApplied, MigrationEnv} =
        with_transaction(MigrationEnv0, fun() -> migrations_apply_all(MigrationEnv0) end),
    logger:info("migrations_apply, success: ~p", [NewlyApplied]),
    ok = terminate_migration(MigrationEnv).

migrate_mark_as_applied([App, Db]) ->
    migrate(App, Db, [{skip_run, true}]).

migrate_one([App, Db]) ->
    migrate_one(App, Db).

migrate_one(App, Db) when is_atom(App) andalso is_atom(Db) ->
    MigrationEnv0 = init_migration(App, Db),
    {ok, NewlyApplied, MigrationEnv} =
        with_transaction(MigrationEnv0, fun() -> migrations_apply_one(MigrationEnv0) end),
    logger:info("migrated one: ~p", [NewlyApplied]),
    ok = terminate_migration(MigrationEnv).

migrate_n([App, Db, N]) ->
    migrate_n(App, Db, N).

migrate_n(App, Db, N) when is_atom(App) andalso is_atom(Db) ->
    MigrationEnv0 = init_migration(App, Db),
    {ok, NewlyApplied, MigrationEnv} =
        with_transaction(MigrationEnv0, fun() -> migrations_apply_n(MigrationEnv0, N) end),
    logger:info("migrated n (~p): ~p", [N, NewlyApplied]),
    ok = terminate_migration(MigrationEnv).

migrate_to([App, Db, To]) ->
    migrate_to(App, Db, To).

migrate_to(App, Db, To) when is_atom(App) andalso is_atom(Db) ->
    MigrationEnv0 = init_migration(App, Db),
    {ok, NewlyApplied, MigrationEnv} =
        with_transaction(MigrationEnv0, fun() -> migrations_apply_to(MigrationEnv0, To) end),
    logger:info("migrated to (~p): ~p", [To, NewlyApplied]),
    ok = terminate_migration(MigrationEnv).

migrate_specific([App, Db, Migration]) ->
    migrate_specific(App, Db, Migration).

migrate_specific(App, Db, Migration) when is_atom(App) andalso is_atom(Db) ->
    MigrationEnv0 = init_migration(App, Db),
    {ok, NewlyApplied, MigrationEnv} =
        with_transaction(MigrationEnv0,
                         fun() -> migrations_apply_specific(MigrationEnv0, Migration) end),
    logger:info("migrated specific ~p", [NewlyApplied]),
    ok = terminate_migration(MigrationEnv).

rollback_app_version([App, Db, AppVersion]) ->
    rollback_app_version(App, Db, AppVersion).

rollback_app_version(App, Db, AppVersion) when is_atom(App) andalso is_atom(Db) ->
    MigrationEnv0 = init_migration(App, Db, [{app_version, AppVersion}]),
    {ok, Rollback, MigrationEnv} =
        with_transaction(MigrationEnv0,
                         fun() -> migrations_rollback_app_version(MigrationEnv0) end),
    logger:info("rollback app version (~p): ~p", [AppVersion, Rollback]),
    ok = terminate_migration(MigrationEnv).

rollback_one([App, Db]) ->
    rollback_one(App, Db).

rollback_one(App, Db) when is_atom(App) andalso is_atom(Db) ->
    MigrationEnv0 = init_migration(App, Db),
    {ok, Rollback, MigrationEnv} =
        with_transaction(MigrationEnv0, fun() -> migrations_rollback_one(MigrationEnv0) end),
    logger:info("rollback one: ~p", [Rollback]),
    ok = terminate_migration(MigrationEnv).

rollback_n([App, Db, N]) ->
    rollback_n(App, Db, N).

rollback_n(App, Db, N) when is_atom(App) andalso is_atom(Db) ->
    MigrationEnv0 = init_migration(App, Db),
    {ok, Rollback, MigrationEnv} =
        with_transaction(MigrationEnv0, fun() -> migrations_rollback_n(MigrationEnv0, N) end),
    logger:info("rollback n (~p): ~p", [N, Rollback]),
    ok = terminate_migration(MigrationEnv).

rollback_to([App, Db, To]) ->
    rollback_to(App, Db, To).

rollback_to(App, Db, To) when is_atom(App) andalso is_atom(Db) ->
    MigrationEnv0 = init_migration(App, Db),
    {ok, Rollback, MigrationEnv} =
        with_transaction(MigrationEnv0, fun() -> migrations_rollback_to(MigrationEnv0, To) end),
    logger:info("rollback to (~p): ~p", [To, Rollback]),
    ok = terminate_migration(MigrationEnv).

%%%===================================================================
%%% Internal
%%%===================================================================
init_migration(App, Db) ->
    init_migration(App, Db, []).

init_migration(App, Db, Opts) ->
    Adapter = init(App, Db),
    Path = migrations_path(App, Db),
    Conn = Adapter:connect(App, Db),

    Available = migrations_available(Path),
    logger:info("migrations_available: ~p", [Available]),

    Applied = Adapter:migrations_applied(Conn, App, Db),
    logger:info("migrations_applied: ~p", [Applied]),

    NotApplied = migrations_not_applied(Available, Applied),
    logger:info("migrations_not_applied: ~p", [NotApplied]),

    AppVersion = proplists:get_value(app_version, Opts, undefined),
    AppliedByVersion =
        case AppVersion of
            undefined ->
                [];
            _ ->
                Adapter:migrations_applied_by_version(Conn, App, Db, AppVersion)
        end,

    #{adapter => Adapter,
      conn => Conn,
      skip_run => proplists:get_value(skip_run, Opts, false),
      application => App,
      application_version => AppVersion,
      migration_type => Db,
      migrations_path => Path,
      migrations_applied => Applied,
      migrations_applied_by_version => AppliedByVersion,
      migrations_not_applied => NotApplied}.

terminate_migration(#{adapter := Adapter, conn := Conn}) ->
    Adapter:close(Conn).

version() ->
    {{Y, M, D}, {H, MM, S}} =
        calendar:now_to_datetime(
            os:timestamp()),
    string_format("~.4.0w~.2.0w~.2.0w~.2.0w~.2.0w~.2.0w", [Y, M, D, H, MM, S]).

string_format(Pattern, Values) ->
    lists:flatten(
        io_lib:format(Pattern, Values)).

underscore(Name) ->
    re:replace(Name, "[\\s,-]+", "_", [global, {return, list}]).

migrations_available(Path) ->
    {ok, Listing0} = file:list_dir(Path),
    Listing = [F || F <- Listing0, filename:extension(F) =:= ".erl"],
    Res = lists:map(fun(FName) -> filename:rootname(FName) end, Listing),
    lists:sort(Res).

migrations_apply_all(Env) ->
    migrations_apply_all(Env, []).

migrations_apply_all(#{migrations_not_applied := []} = Env, NewlyApplied) ->
    {ok, lists:reverse(NewlyApplied), Env};
migrations_apply_all(Env0, Acc) ->
    {ok, [Applied], Env} = migrations_apply_one(Env0),
    migrations_apply_all(Env, [Applied | Acc]).

migrations_apply_n(Env, N) when is_list(N) ->
    migrations_apply_n(Env, list_to_integer(N));
migrations_apply_n(Env, N) when is_integer(N) ->
    migrations_apply_n(Env, N, []).

migrations_apply_n(#{migrations_not_applied := []} = Env, _N, NewlyApplied) ->
    {ok, lists:reverse(NewlyApplied), Env};
migrations_apply_n(Env, 0, NewlyApplied) ->
    {ok, lists:reverse(NewlyApplied), Env};
migrations_apply_n(Env0, N, Acc) when N > 0 ->
    {ok, [Applied], Env} = migrations_apply_one(Env0),
    migrations_apply_n(Env, N - 1, [Applied | Acc]).

migrations_apply_to(Env, To) when is_binary(To) ->
    migrations_apply_to(Env, binary_to_list(To));
migrations_apply_to(#{migrations_not_applied := NotApplied} = Env, To) when is_list(To) ->
    case lists:member(To, NotApplied) of
        true ->
            migrations_apply_to(Env, To, []);
        false ->
            {error, migration_not_found}
    end.

migrations_apply_to(#{migrations_not_applied := [LastMigration | _]} = Env0,
                    LastMigration,
                    Acc) ->
    {ok, [Applied], Env} = migrations_apply_one(Env0),
    {ok, lists:reverse([Applied | Acc]), Env};
migrations_apply_to(Env0, To, Acc) ->
    {ok, [Applied], Env} = migrations_apply_one(Env0),
    migrations_apply_to(Env, To, [Applied | Acc]).

migrations_apply_one(#{migrations_not_applied := []} = Env) ->
    {ok, [], Env};
migrations_apply_one(#{adapter := Adapter,
                       conn := Conn,
                       application := AppName,
                       application_version := AppVersion,
                       skip_run := true,
                       migration_type := Type,
                       migrations_not_applied := [Version | NotApplied],
                       migrations_applied := Applied} =
                         Env) ->
    ok = Adapter:migrations_upgrade(Conn, Version, AppName, Type, AppVersion),
    {ok,
     [Version],
     Env#{migrations_not_applied => NotApplied,
          migrations_applied => lists:sort([Version | Applied])}};
migrations_apply_one(#{adapter := Adapter,
                       conn := Conn,
                       application := AppName,
                       application_version := AppVersion,
                       skip_run := false,
                       migration_type := Type,
                       migrations_path := Path,
                       migrations_not_applied := [Version | NotApplied],
                       migrations_applied := Applied} =
                         Env) ->
        Run = migration_run_fn(),
        ok = Run(Conn, Version, Path),
    ok = Adapter:migrations_upgrade(Conn, Version, AppName, Type, AppVersion),
    {ok,
     [Version],
     Env#{migrations_not_applied => NotApplied,
          migrations_applied => lists:sort([Version | Applied])}}.

migrations_apply_specific(#{adapter := Adapter,
                            conn := Conn,
                            application := AppName,
                            application_version := AppVersion,
                            migration_type := Type,
                            migrations_path := Path} =
                              Env,
                          Migration) ->
    Run = migration_run_fn(),
    ok = Run(Conn, Migration, Path),
    ok = Adapter:migrations_upgrade(Conn, Migration, AppName, Type, AppVersion),
    {ok, [Migration], Env}.

migrations_rollback_one(#{migrations_applied := []} = Env) ->
    {ok, [], Env};
migrations_rollback_one(#{application_version := undefined,
                          migrations_applied := Applied0,
                          migrations_applied_by_version := AppliedByVersion0} =
                            Env) ->
    [Version | Applied] =
        lists:reverse(
            lists:sort(Applied0)),
    do_rollback(Env, Version, Applied, AppliedByVersion0);
migrations_rollback_one(#{application_version := _AppVersion,
                          migrations_applied := Applied0,
                          migrations_applied_by_version := AppliedByVersion0} =
                            Env) ->
    [Version | AppliedByVersion] =
        lists:reverse(
            lists:sort(AppliedByVersion0)),
    Applied = lists:delete(Version, Applied0),
    do_rollback(Env, Version, Applied, AppliedByVersion).

do_rollback(#{adapter := Adapter,
              conn := Conn,
              migrations_path := Path,
              migrations_not_applied := NotApplied} =
                Env,
            Version,
            Applied,
            AppliedByVersion) ->
    Run = rollback_run_fn(),
    ok = Run(Conn, Version, Path),
    ok = Adapter:migrations_downgrade(Conn, Version),
    {ok,
     [Version],
     Env#{migrations_not_applied => lists:sort([Version | NotApplied]),
          migrations_applied => lists:reverse(Applied),
          migrations_applied_by_version => lists:reverse(AppliedByVersion)}}.

migrations_rollback_app_version(Env) ->
    migrations_rollback_app_version(Env, []).

migrations_rollback_app_version(#{migrations_applied_by_version := []} = Env, Rollback) ->
    {ok, lists:reverse(Rollback), Env};
migrations_rollback_app_version(Env0, Acc) ->
    {ok, [Rollback], Env} = migrations_rollback_one(Env0),
    migrations_rollback_app_version(Env, [Rollback | Acc]).

migrations_rollback_n(Env, N) when is_list(N) ->
    migrations_rollback_n(Env, list_to_integer(N));
migrations_rollback_n(Env, N) when is_integer(N) ->
    migrations_rollback_n(Env, N, []).

migrations_rollback_n(#{migrations_applied := []} = Env, _N, Rollback) ->
    {ok, lists:reverse(Rollback), Env};
migrations_rollback_n(Env, 0, Rollback) ->
    {ok, lists:reverse(Rollback), Env};
migrations_rollback_n(Env0, N, Acc) when N > 0 ->
    {ok, [Rollback], Env} = migrations_rollback_one(Env0),
    migrations_rollback_n(Env, N - 1, [Rollback | Acc]).

migrations_rollback_to(Env, To) when is_binary(To) ->
    migrations_rollback_to(Env, binary_to_list(To));
migrations_rollback_to(#{migrations_applied := Applied} = Env, To) when is_list(To) ->
    case lists:member(To, Applied) of
        true ->
            migrations_rollback_to(Env, To, []);
        false ->
            {error, migration_not_found}
    end.

migrations_rollback_to(#{migrations_applied := Applied} = Env0, To, Acc) ->
    case lists:reverse(Applied) of
        [To | _] ->
            {ok, [Rollback], Env} = migrations_rollback_one(Env0),
            {ok, lists:reverse([Rollback | Acc]), Env};
        _ ->
            {ok, [Rollback], Env} = migrations_rollback_one(Env0),
            migrations_rollback_to(Env, To, [Rollback | Acc])
    end.

migrations_not_applied(Available, Applied) ->
    AvailableSet = sets:from_list(Available),
    AppliedSet = sets:from_list(Applied),
    lists:sort(
        sets:to_list(
            sets:subtract(AvailableSet, AppliedSet))).

migration_run(Conn, Version, Path) ->
    FilePath = filename:join([Path, Version ++ ".erl"]),
    {ok, Mod, Bin} = compile:file(FilePath, [binary, report]),
    {module, Mod} = code:load_binary(Mod, FilePath, Bin),
    ok = Mod:up(Conn),
    ok.

rollback_run(Conn, Version, Path) ->
    FilePath = filename:join([Path, Version ++ ".erl"]),
    {ok, Mod, Bin} = compile:file(FilePath, [binary, report]),
    {module, Mod} = code:load_binary(Mod, FilePath, Bin),
    ok = Mod:down(Conn),
    ok.

init(App, Db) ->
    _ = application:load(App),
    Adapter = adapter(App, Db),
    ok = Adapter:init(),
    ok = ensure_migration_path(App, Db),
    ok = ensure_repo(App, Db, Adapter),
    Adapter.

adapter(App, Db) ->
    AppDbOpts = dbmigrate_utils:app_db_opts(App, Db),
    proplists:get_value(adapter, AppDbOpts).

ensure_migration_path(App, Db) ->
    ok = filelib:ensure_dir(migrations_path(App, Db) ++ "/foo").

ensure_repo(App, Db, Adapter) ->
    ok = Adapter:ensure_repo(App, Db).

migrations_path(App, Db) ->
    AppDbOpts = dbmigrate_utils:app_db_opts(App, Db),
    case proplists:get_value(migrate_path, AppDbOpts) of
        undefined ->
            PrivDir = code:priv_dir(App),
            PrivDir ++ "/migrations/" ++ atom_to_list(Db) ++ "/";
        Path ->
            Path
    end.

with_transaction(#{adapter := Adapter, conn := Conn}, MigrationFun)
    when is_function(MigrationFun) ->
    ok = Adapter:transaction_start(Conn),
    Result = MigrationFun(),
    ok = Adapter:transaction_end(Conn),
    Result.
