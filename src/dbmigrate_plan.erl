-module(dbmigrate_plan).

%% Migration planning.
%%
%% Given available migrations, already-applied migrations, and a request
%% mode, this module decides which migrations should be executed and in
%% what order — without touching any database.

-export([resolve/1]).

-ifdef(TEST).
-compile([export_all]).
-endif.

%% @doc Produce an execution plan from the current migration state.
%%
%% Input is a map that must contain at least:
%%   action            — migrate | rollback
%%   mode              — all | {count, N} | {to, V} | {specific, V} | app_version
%%   migrations_available     — sorted [string()]
%%   migrations_applied       — sorted [string()]
%%   migrations_applied_by_version — sorted [string()]  (only for app_version rollback)
%%
%% Returns:
%%   {ok, Plan} where Plan is #{action, selected, pending, applied}
%%   {error, Reason}

-spec resolve(map()) -> {ok, map()} | {error, term()}.

%% --- Migrate ---------------------------------------------------------

resolve(#{action := migrate, mode := all} = State) ->
    Pending = not_applied(State),
    {ok, #{action => migrate,
           selected => Pending,
           pending => [],
           applied => maps:get(migrations_applied, State)}};

resolve(#{action := migrate, mode := {count, N}} = State) ->
    Pending = not_applied(State),
    Selected = lists:sublist(Pending, N),
    Remaining = lists:nthtail(length(Selected), Pending),
    {ok, #{action => migrate,
           selected => Selected,
           pending => Remaining,
           applied => maps:get(migrations_applied, State)}};

resolve(#{action := migrate, mode := {to, Target}} = State) ->
    Pending = not_applied(State),
    case lists:member(Target, Pending) of
        false ->
            {error, migration_not_found};
        true ->
            Selected = take_up_to(Target, Pending),
            Remaining = lists:nthtail(length(Selected), Pending),
            {ok, #{action => migrate,
                   selected => Selected,
                   pending => Remaining,
                   applied => maps:get(migrations_applied, State)}}
    end;

resolve(#{action := migrate, mode := {specific, MigrationId}} = State) ->
    {ok, #{action => migrate,
           selected => [MigrationId],
           pending => [],
           applied => maps:get(migrations_applied, State)}};

%% --- Rollback --------------------------------------------------------

resolve(#{action := rollback, mode := {count, N}} = State) ->
    Applied = maps:get(migrations_applied, State),
    Reversed = lists:reverse(lists:sort(Applied)),
    Selected = lists:sublist(Reversed, N),
    Remaining = lists:nthtail(length(Selected), Reversed),
    {ok, #{action => rollback,
           selected => Selected,
           pending => [],
           applied => lists:reverse(Remaining)}};

resolve(#{action := rollback, mode := {to, Target}} = State) ->
    Applied = maps:get(migrations_applied, State),
    Sorted = lists:sort(Applied),
    case lists:member(Target, Sorted) of
        false ->
            {error, migration_not_found};
        true ->
            %% Roll back everything from the latest down to (and including) Target.
            Reversed = lists:reverse(Sorted),
            Selected = take_up_to(Target, Reversed),
            RemainingApplied = lists:sort(Applied -- Selected),
            {ok, #{action => rollback,
                   selected => Selected,
                   pending => [],
                   applied => RemainingApplied}}
    end;

resolve(#{action := rollback, mode := app_version} = State) ->
    AppliedByVersion = maps:get(migrations_applied_by_version, State),
    Reversed = lists:reverse(lists:sort(AppliedByVersion)),
    Applied = maps:get(migrations_applied, State),
    RemainingApplied = lists:sort(Applied -- Reversed),
    {ok, #{action => rollback,
           selected => Reversed,
           pending => [],
           applied => RemainingApplied}}.

%%% -------------------------------------------------------------------
%%% Internal helpers
%%% -------------------------------------------------------------------

%% Compute available minus applied, sorted.
not_applied(#{migrations_available := Available,
              migrations_applied := Applied}) ->
    AvailSet = sets:from_list(Available),
    AppliedSet = sets:from_list(Applied),
    lists:sort(sets:to_list(sets:subtract(AvailSet, AppliedSet))).

%% Return all elements up to and including Target.
take_up_to(Target, List) ->
    take_up_to(Target, List, []).

take_up_to(_Target, [], Acc) ->
    lists:reverse(Acc);
take_up_to(Target, [Target | _], Acc) ->
    lists:reverse([Target | Acc]);
take_up_to(Target, [H | T], Acc) ->
    take_up_to(Target, T, [H | Acc]).
