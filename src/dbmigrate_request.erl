-module(dbmigrate_request).

%% Normalize legacy public API calls into structured request maps.
%%
%% Each public function in dbmigrate.erl delegates here to build a
%% uniform request that the planner and runner consume.

-export([build/1]).

-ifdef(TEST).

-compile([export_all]).

-endif.

%% @doc Build a normalised request map from a tagged tuple.
%%
%% The caller supplies {Action, Mode, App, Db, Opts} and receives back
%% a map that every downstream module can pattern-match on.

-spec build(tuple()) -> map().
build({gen_migration, App, Db, Name}) ->
    #{action => gen_migration,
      app => App,
      backend => Db,
      name => Name};
build({migrate, App, Db, Opts}) ->
    SkipRun = proplists:get_value(skip_run, Opts, false),
    AppVersion = proplists:get_value(app_version, Opts, undefined),
    #{action => migrate,
      mode => all,
      app => App,
      backend => Db,
      skip_run => SkipRun,
      app_version => AppVersion};
build({migrate_one, App, Db}) ->
    #{action => migrate,
      mode => {count, 1},
      app => App,
      backend => Db,
      skip_run => false,
      app_version => undefined};
build({migrate_n, App, Db, N}) ->
    #{action => migrate,
      mode => {count, ensure_integer(N)},
      app => App,
      backend => Db,
      skip_run => false,
      app_version => undefined};
build({migrate_to, App, Db, To}) ->
    #{action => migrate,
      mode => {to, ensure_list(To)},
      app => App,
      backend => Db,
      skip_run => false,
      app_version => undefined};
build({migrate_specific, App, Db, Migration}) ->
    #{action => migrate,
      mode => {specific, Migration},
      app => App,
      backend => Db,
      skip_run => false,
      app_version => undefined};
build({rollback_one, App, Db}) ->
    #{action => rollback,
      mode => {count, 1},
      app => App,
      backend => Db,
      app_version => undefined};
build({rollback_n, App, Db, N}) ->
    #{action => rollback,
      mode => {count, ensure_integer(N)},
      app => App,
      backend => Db,
      app_version => undefined};
build({rollback_to, App, Db, To}) ->
    #{action => rollback,
      mode => {to, ensure_list(To)},
      app => App,
      backend => Db,
      app_version => undefined};
build({rollback_app_version, App, Db, AppVersion}) ->
    #{action => rollback,
      mode => app_version,
      app => App,
      backend => Db,
      app_version => AppVersion}.

%%% -------------------------------------------------------------------
%%% Internal helpers
%%% -------------------------------------------------------------------

ensure_integer(N) when is_integer(N) ->
    N;
ensure_integer(N) when is_list(N) ->
    list_to_integer(N).

ensure_list(V) when is_list(V) ->
    V;
ensure_list(V) when is_binary(V) ->
    binary_to_list(V).
