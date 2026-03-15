-module(dbmigrate_registry_tests).

-include_lib("eunit/include/eunit.hrl").

%%% ===================================================================
%%% These tests verify the registry delegates correctly.  We use a
%%% mock adapter module (this module itself) to capture calls.
%%% ===================================================================

-export([migrations_applied/3,
         migrations_applied_by_version/4,
         migrations_upgrade/5,
         migrations_downgrade/2]).

%% Mock implementations that return predictable values.

migrations_applied(_Conn, _App, _Backend) ->
    ["m1", "m2"].

migrations_applied_by_version(_Conn, _App, _Backend, _AppVersion) ->
    ["m2"].

migrations_upgrade(_Conn, _Version, _App, _Backend, _AppVersion) ->
    ok.

migrations_downgrade(_Conn, _Version) ->
    ok.

%%% ===================================================================
%%% Tests
%%% ===================================================================

fetch_applied_test() ->
    Result = dbmigrate_registry:fetch_applied(?MODULE, fake_conn, myapp, pgsql),
    ?assertEqual(["m1", "m2"], Result).

fetch_applied_by_version_test() ->
    Result = dbmigrate_registry:fetch_applied_by_version(?MODULE, fake_conn, myapp, pgsql, "1.0"),
    ?assertEqual(["m2"], Result).

record_applied_test() ->
    ?assertEqual(ok,
                 dbmigrate_registry:record_applied(?MODULE, fake_conn, "m3", myapp, pgsql, "1.0")).

record_removed_test() ->
    ?assertEqual(ok,
                 dbmigrate_registry:record_removed(?MODULE, fake_conn, "m2")).
