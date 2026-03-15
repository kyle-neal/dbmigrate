-module(dbmigrate_request_tests).

-include_lib("eunit/include/eunit.hrl").

%%% -------------------------------------------------------------------
%%% build/1 — migrate variants
%%% -------------------------------------------------------------------

build_gen_migration_test() ->
    Req = dbmigrate_request:build({gen_migration, myapp, pgsql, "add users"}),
    ?assertEqual(gen_migration, maps:get(action, Req)),
    ?assertEqual(myapp, maps:get(app, Req)),
    ?assertEqual(pgsql, maps:get(backend, Req)),
    ?assertEqual("add users", maps:get(name, Req)).

build_migrate_all_test() ->
    Req = dbmigrate_request:build({migrate, myapp, pgsql, []}),
    ?assertEqual(migrate, maps:get(action, Req)),
    ?assertEqual(all, maps:get(mode, Req)),
    ?assertEqual(false, maps:get(skip_run, Req)),
    ?assertEqual(undefined, maps:get(app_version, Req)).

build_migrate_skip_run_test() ->
    Req = dbmigrate_request:build({migrate, myapp, pgsql, [{skip_run, true}]}),
    ?assertEqual(true, maps:get(skip_run, Req)).

build_migrate_with_app_version_test() ->
    Req = dbmigrate_request:build({migrate, myapp, pgsql, [{app_version, "1.0.0"}]}),
    ?assertEqual("1.0.0", maps:get(app_version, Req)).

build_migrate_one_test() ->
    Req = dbmigrate_request:build({migrate_one, myapp, pgsql}),
    ?assertEqual(migrate, maps:get(action, Req)),
    ?assertEqual({count, 1}, maps:get(mode, Req)).

build_migrate_n_integer_test() ->
    Req = dbmigrate_request:build({migrate_n, myapp, pgsql, 5}),
    ?assertEqual({count, 5}, maps:get(mode, Req)).

build_migrate_n_string_test() ->
    Req = dbmigrate_request:build({migrate_n, myapp, pgsql, "3"}),
    ?assertEqual({count, 3}, maps:get(mode, Req)).

build_migrate_to_test() ->
    Req = dbmigrate_request:build({migrate_to, myapp, pgsql, "20260315120000"}),
    ?assertEqual({to, "20260315120000"}, maps:get(mode, Req)).

build_migrate_to_binary_test() ->
    Req = dbmigrate_request:build({migrate_to, myapp, pgsql, <<"20260315120000">>}),
    ?assertEqual({to, "20260315120000"}, maps:get(mode, Req)).

build_migrate_specific_test() ->
    Req = dbmigrate_request:build({migrate_specific, myapp, pgsql, "m1"}),
    ?assertEqual({specific, "m1"}, maps:get(mode, Req)).

%%% -------------------------------------------------------------------
%%% build/1 — rollback variants
%%% -------------------------------------------------------------------

build_rollback_one_test() ->
    Req = dbmigrate_request:build({rollback_one, myapp, pgsql}),
    ?assertEqual(rollback, maps:get(action, Req)),
    ?assertEqual({count, 1}, maps:get(mode, Req)).

build_rollback_n_test() ->
    Req = dbmigrate_request:build({rollback_n, myapp, pgsql, 4}),
    ?assertEqual({count, 4}, maps:get(mode, Req)).

build_rollback_to_test() ->
    Req = dbmigrate_request:build({rollback_to, myapp, pgsql, "m3"}),
    ?assertEqual({to, "m3"}, maps:get(mode, Req)).

build_rollback_app_version_test() ->
    Req = dbmigrate_request:build({rollback_app_version, myapp, pgsql, "2.0.0"}),
    ?assertEqual(rollback, maps:get(action, Req)),
    ?assertEqual(app_version, maps:get(mode, Req)),
    ?assertEqual("2.0.0", maps:get(app_version, Req)).
