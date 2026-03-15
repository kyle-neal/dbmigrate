-module(dbmigrate_tests).

-include_lib("eunit/include/eunit.hrl").

-export([init/0, connect/2, close/1, ensure_repo/2, file_template/1, transaction_start/1,
         migrations_upgrade/5, migrations_downgrade/2, transaction_end/1]).

init() ->
    ok.

connect(_, _) ->
    conn.

close(_) ->
    ok.

ensure_repo(_, _) ->
    ok.

file_template(FileName) ->
    dbmigrate_adapter_pgsql:file_template(FileName).

transaction_start(_) ->
    ok.

migrations_upgrade(_, _, _, _, _) ->
    ok.

migrations_downgrade(_, _) ->
    ok.

transaction_end(_) ->
    ok.

-define(env(Applied, NotApplied, AppVersion, SkipRun),
        #{adapter => ?MODULE,
          conn => conn,
          application => testapp,
          application_version => AppVersion,
          skip_run => SkipRun,
          migration_type => testtype,
          migrations_path => "",
          migrations_applied => Applied,
          migrations_applied_by_version => Applied,
          migrations_not_applied => NotApplied}).

migrate_test_() ->
    {setup,
     fun() ->
        ok = application:load(dbmigrate),
        ok = application:set_env(dbmigrate, migration_run_fn, fun migration_run/3),
        ok = application:set_env(dbmigrate, rollback_run_fn, fun rollback_run/3)
     end,
     fun(_) -> ok = application:unload(dbmigrate) end,
     fun(_) ->
        [{"Test apply all no app version",
          fun() ->
             Env0 = ?env([], ["m1", "m2"], undefined, false),
             {ok,
              ["m1", "m2"],
              #{migrations_applied := ["m1", "m2"],
                migrations_applied_by_version := [],
                migrations_not_applied := []}} =
                 dbmigrate:migrations_apply_all(Env0)
          end},
         {"Test apply all with app version",
          fun() ->
             Env0 = ?env([], ["m1", "m2"], "1.0.0", false),
             {ok,
              ["m1", "m2"],
              #{migrations_applied := ["m1", "m2"],
                migrations_applied_by_version := [],
                migrations_not_applied := []}} =
                 dbmigrate:migrations_apply_all(Env0)
          end},
         {"Test apply n",
          fun() ->
             Env0 = ?env([], ["m1", "m2", "m3", "m4"], undefined, false),
             {ok,
              ["m1", "m2"],
              #{migrations_applied := ["m1", "m2"], migrations_not_applied := ["m3", "m4"]}} =
                 dbmigrate:migrations_apply_n(Env0, 2)
          end},
         {"Test apply more than available",
          fun() ->
             Env0 = ?env([], ["m1", "m2", "m3", "m4"], undefined, false),
             {ok,
              ["m1", "m2", "m3", "m4"],
              #{migrations_applied := ["m1", "m2", "m3", "m4"], migrations_not_applied := []}} =
                 dbmigrate:migrations_apply_n(Env0, 5)
          end},
         {"Test apply to",
          fun() ->
             Env0 = ?env([], ["m1", "m2", "m3", "m4"], undefined, false),
             {ok,
              ["m1", "m2"],
              #{migrations_applied := ["m1", "m2"], migrations_not_applied := ["m3", "m4"]}} =
                 dbmigrate:migrations_apply_to(Env0, "m2")
          end},
         {"Test apply to - not found",
          fun() ->
             Env0 = ?env([], ["m1", "m2", "m3", "m4"], undefined, false),
             {error, migration_not_found} = dbmigrate:migrations_apply_to(Env0, "m5")
          end},
         {"Test apply one",
          fun() ->
             Env0 = ?env([], ["m1", "m2"], undefined, false),
             {ok, ["m1"], #{migrations_applied := ["m1"], migrations_not_applied := ["m2"]}} =
                 dbmigrate:migrations_apply_one(Env0)
          end},
         {"Test apply one - nothing to apply",
          fun() ->
             Env0 = ?env(["m1", "m2"], [], undefined, false),
             {ok, [], #{migrations_applied := ["m1", "m2"], migrations_not_applied := []}} =
                 dbmigrate:migrations_apply_one(Env0)
          end},
         {"Test rollback one no version",
          fun() ->
             Env0 = ?env(["m1", "m2"], [], undefined, false),
             {ok, ["m2"], #{migrations_applied := ["m1"], migrations_not_applied := ["m2"]}} =
                 dbmigrate:migrations_rollback_one(Env0)
          end},
         {"Test rollback one with version",
          fun() ->
             Env0 = ?env(["m1", "m2"], [], "1.0.0", false),
             {ok,
              ["m2"],
              #{migrations_applied := ["m1"],
                migrations_applied_by_version := ["m1"],
                migrations_not_applied := ["m2"]}} =
                 dbmigrate:migrations_rollback_one(Env0)
          end},
         {"Test rollback one - nothing to rollback",
          fun() ->
             Env0 = ?env([], ["m1", "m2"], undefined, false),
             {ok,
              [],
              #{migrations_applied := [],
                migrations_applied_by_version := [],
                migrations_not_applied := ["m1", "m2"]}} =
                 dbmigrate:migrations_rollback_one(Env0)
          end},
         {"Test rollback n",
          fun() ->
             Env0 = ?env(["m1", "m2", "m3", "m4"], [], undefined, false),
             {ok,
              ["m4", "m3"],
              #{migrations_applied := ["m1", "m2"], migrations_not_applied := ["m3", "m4"]}} =
                 dbmigrate:migrations_rollback_n(Env0, 2)
          end},
         {"Test rollback to",
          fun() ->
             Env0 = ?env(["m1", "m2", "m3", "m4"], [], undefined, false),
             {ok,
              ["m4", "m3"],
              #{migrations_applied := ["m1", "m2"], migrations_not_applied := ["m3", "m4"]}} =
                 dbmigrate:migrations_rollback_to(Env0, "m3")
          end},
         {"Test rollback to - not found",
          fun() ->
             Env0 = ?env(["m1", "m2", "m3", "m4"], [], undefined, false),
             {error, migration_not_found} = dbmigrate:migrations_rollback_to(Env0, "m5")
          end},
         {"Test rollback app version",
          fun() ->
             Env0 = ?env(["m1", "m2"], [], "1.0.0", false),
             {ok,
              ["m2", "m1"],
              #{migrations_applied := [],
                migrations_applied_by_version := [],
                migrations_not_applied := ["m1", "m2"]}} =
                 dbmigrate:migrations_rollback_app_version(Env0)
          end},
         {"Test skip apply",
          fun() ->
             Env0 = ?env([], ["m1", "m2"], undefined, true),
             {ok,
              ["m1", "m2"],
              #{migrations_applied := ["m1", "m2"],
                migrations_applied_by_version := [],
                migrations_not_applied := []}} =
                 dbmigrate:migrations_apply_all(Env0)
          end},
         {"Test migrate specific",
          fun() ->
             Env0 = ?env(["m1"], ["m2"], undefined, true),
             {ok, ["m1"], Env0} = dbmigrate:migrations_apply_specific(Env0, "m1")
          end}]
     end}.

gen_migration_in_dep_app_priv_dir_test_() ->
    {setup,
     fun() ->
        App = mmerl_core,
        BaseDir = filename:join(["_tmp", "gen_migration_dep_app"]),
        AppDir = filename:join(BaseDir, atom_to_list(App)),
        EbinDir = filename:join(AppDir, "ebin"),
        PrivDir = filename:join([AppDir, "priv", "migrations", "pgsql"]),
        ok =
            filelib:ensure_dir(
                filename:join(PrivDir, "placeholder")),

        AppFile = filename:join(EbinDir, atom_to_list(App) ++ ".app"),
        ok = filelib:ensure_dir(AppFile),
        AppFileBody = io_lib:format("{application, ~p, [{vsn, \"1.0.0\"}]}.~n", [App]),
        ok = file:write_file(AppFile, AppFileBody),

        true = code:add_patha(EbinDir),
        ok =
            application:set_env(App,
                                migrate,
                                [{pgsql,
                                  [{adapter, ?MODULE},
                                   {host, "localhost"},
                                   {port, 5432},
                                   {username, "user"},
                                   {password, "pass"},
                                   {database, "db"},
                                   {timeout, 5000}]}]),
        #{app => App,
          base_dir => BaseDir,
          ebin_dir => EbinDir,
          priv_dir => PrivDir}
     end,
     fun(#{app := App,
           base_dir := BaseDir,
           ebin_dir := EbinDir}) ->
        _ = application:unset_env(App, migrate),
        _ = application:unload(App),
        true = code:del_path(EbinDir),
        ok = file:del_dir_r(BaseDir)
     end,
     fun(#{app := App, priv_dir := PrivDir}) ->
        [{"Generate migration under dependent app priv path",
          fun() ->
             {ok, FilePath} = dbmigrate:gen_migration(App, pgsql, "add positions"),

             ?assert(filelib:is_file(FilePath)),
             ?assert(lists:prefix(PrivDir, FilePath)),
             ?assertEqual(".erl", filename:extension(FilePath)),
             ?assertEqual(match,
                          re:run(
                              filename:basename(FilePath),
                              "^[0-9]{14}_add_positions\\.erl$",
                              [{capture, none}]))
          end}]
     end}.

migration_run(_, _, _) ->
    ok.

rollback_run(_, _, _) ->
    ok.
