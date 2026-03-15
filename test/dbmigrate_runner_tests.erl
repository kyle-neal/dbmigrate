-module(dbmigrate_runner_tests).

-include_lib("eunit/include/eunit.hrl").

%%% ===================================================================
%%% Mock adapter callbacks used by the runner
%%% ===================================================================

-export([transaction_begin/1, transaction_commit/1, migrations_upgrade/5,
         migrations_downgrade/2]).

transaction_begin(_) ->
    ok.

transaction_commit(_) ->
    ok.

migrations_upgrade(_, _, _, _, _) ->
    ok.

migrations_downgrade(_, _) ->
    ok.

%%% ===================================================================
%%% Helpers
%%% ===================================================================

noop_run(_Conn, _Version, _Path) ->
    ok.

base_ctx(Action, Selected) ->
    #{adapter => ?MODULE,
      conn => fake_conn,
      app => testapp,
      backend => testdb,
      app_version => undefined,
      skip_run => false,
      migrations_path => "/tmp",
      migration_run_fn => fun noop_run/3,
      rollback_run_fn => fun noop_run/3,
      action => Action,
      selected => Selected}.

%%% ===================================================================
%%% Tests
%%% ===================================================================

execute_migrate_empty_test() ->
    Ctx = base_ctx(migrate, []),
    ?assertEqual({ok, []}, dbmigrate_runner:execute(Ctx)).

execute_migrate_multiple_test() ->
    Ctx = base_ctx(migrate, ["m1", "m2", "m3"]),
    ?assertEqual({ok, ["m1", "m2", "m3"]}, dbmigrate_runner:execute(Ctx)).

execute_migrate_skip_run_test() ->
    Ctx = (base_ctx(migrate, ["m1", "m2"]))#{skip_run => true},
    ?assertEqual({ok, ["m1", "m2"]}, dbmigrate_runner:execute(Ctx)).

execute_rollback_empty_test() ->
    Ctx = base_ctx(rollback, []),
    ?assertEqual({ok, []}, dbmigrate_runner:execute(Ctx)).

execute_rollback_multiple_test() ->
    Ctx = base_ctx(rollback, ["m3", "m2"]),
    ?assertEqual({ok, ["m3", "m2"]}, dbmigrate_runner:execute(Ctx)).

execute_ordering_preserved_test() ->
    %% Runner should process in given order.
    Ctx = base_ctx(migrate, ["z1", "a2", "m3"]),
    {ok, Result} = dbmigrate_runner:execute(Ctx),
    ?assertEqual(["z1", "a2", "m3"], Result).
