-module(dbmigrate_plan_tests).

-include_lib("eunit/include/eunit.hrl").

%%% ===================================================================
%%% Helpers
%%% ===================================================================

base_state(Action, Mode, Available, Applied) ->
    #{action => Action,
      mode => Mode,
      migrations_available => Available,
      migrations_applied => Applied,
      migrations_applied_by_version => []}.

%%% ===================================================================
%%% Migrate tests
%%% ===================================================================

migrate_all_test() ->
    State = base_state(migrate, all, ["m1", "m2", "m3"], ["m1"]),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual(migrate, maps:get(action, Plan)),
    ?assertEqual(["m2", "m3"], maps:get(selected, Plan)),
    ?assertEqual([], maps:get(pending, Plan)).

migrate_all_nothing_pending_test() ->
    State = base_state(migrate, all, ["m1", "m2"], ["m1", "m2"]),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual([], maps:get(selected, Plan)).

migrate_count_test() ->
    State = base_state(migrate, {count, 2}, ["m1", "m2", "m3", "m4"], ["m1"]),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual(["m2", "m3"], maps:get(selected, Plan)),
    ?assertEqual(["m4"], maps:get(pending, Plan)).

migrate_count_more_than_available_test() ->
    State = base_state(migrate, {count, 10}, ["m1", "m2"], []),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual(["m1", "m2"], maps:get(selected, Plan)),
    ?assertEqual([], maps:get(pending, Plan)).

migrate_to_test() ->
    State = base_state(migrate, {to, "m3"}, ["m1", "m2", "m3", "m4"], ["m1"]),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual(["m2", "m3"], maps:get(selected, Plan)),
    ?assertEqual(["m4"], maps:get(pending, Plan)).

migrate_to_not_found_test() ->
    State = base_state(migrate, {to, "m99"}, ["m1", "m2"], []),
    ?assertEqual({error, migration_not_found}, dbmigrate_plan:resolve(State)).

migrate_specific_test() ->
    State = base_state(migrate, {specific, "m2"}, ["m1", "m2"], ["m1"]),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual(["m2"], maps:get(selected, Plan)).

%%% ===================================================================
%%% Rollback tests
%%% ===================================================================

rollback_count_one_test() ->
    State = base_state(rollback, {count, 1}, ["m1", "m2", "m3"], ["m1", "m2", "m3"]),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual(rollback, maps:get(action, Plan)),
    ?assertEqual(["m3"], maps:get(selected, Plan)),
    ?assertEqual(["m1", "m2"], maps:get(applied, Plan)).

rollback_count_two_test() ->
    State = base_state(rollback, {count, 2}, ["m1", "m2", "m3", "m4"],
                       ["m1", "m2", "m3", "m4"]),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual(["m4", "m3"], maps:get(selected, Plan)),
    ?assertEqual(["m1", "m2"], maps:get(applied, Plan)).

rollback_count_nothing_applied_test() ->
    State = base_state(rollback, {count, 1}, ["m1"], []),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual([], maps:get(selected, Plan)).

rollback_to_test() ->
    State = base_state(rollback, {to, "m3"}, ["m1", "m2", "m3", "m4"],
                       ["m1", "m2", "m3", "m4"]),
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual(["m4", "m3"], maps:get(selected, Plan)),
    ?assertEqual(["m1", "m2"], maps:get(applied, Plan)).

rollback_to_not_found_test() ->
    State = base_state(rollback, {to, "m99"}, ["m1", "m2"], ["m1", "m2"]),
    ?assertEqual({error, migration_not_found}, dbmigrate_plan:resolve(State)).

rollback_app_version_test() ->
    State = #{action => rollback,
              mode => app_version,
              migrations_available => ["m1", "m2", "m3"],
              migrations_applied => ["m1", "m2", "m3"],
              migrations_applied_by_version => ["m2", "m3"]},
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual(["m3", "m2"], maps:get(selected, Plan)),
    ?assertEqual(["m1"], maps:get(applied, Plan)).

rollback_app_version_empty_test() ->
    State = #{action => rollback,
              mode => app_version,
              migrations_available => ["m1", "m2"],
              migrations_applied => ["m1", "m2"],
              migrations_applied_by_version => []},
    {ok, Plan} = dbmigrate_plan:resolve(State),
    ?assertEqual([], maps:get(selected, Plan)),
    ?assertEqual(["m1", "m2"], maps:get(applied, Plan)).
