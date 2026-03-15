-module(dbmigrate_registry).

%% Migration tracking — reading, recording, and removing applied
%% migration entries via the adapter.
%%
%% This module shields the runner from the details of how each backend
%% stores its schema_migrations data.

-export([fetch_applied/4, fetch_applied_by_version/5, record_applied/6,
         record_removed/3]).

-ifdef(TEST).

-compile([export_all]).

-endif.

%% @doc Return a sorted list of version strings that have been applied.
-spec fetch_applied(module(), term(), atom(), atom()) -> [string()].
fetch_applied(Adapter, Conn, App, Backend) ->
    Adapter:migrations_applied(Conn, App, Backend).

%% @doc Return applied migrations filtered by a specific app version.
-spec fetch_applied_by_version(module(), term(), atom(), atom(), string()) -> [string()].
fetch_applied_by_version(Adapter, Conn, App, Backend, AppVersion) ->
    Adapter:migrations_applied_by_version(Conn, App, Backend, AppVersion).

%% @doc Record a migration as applied.
-spec record_applied(module(), term(), string(), atom(), atom(), string() | undefined) ->
                        ok.
record_applied(Adapter, Conn, Version, App, Backend, AppVersion) ->
    Adapter:migrations_upgrade(Conn, Version, App, Backend, AppVersion).

%% @doc Remove a migration record (rollback).
-spec record_removed(module(), term(), string()) -> ok.
record_removed(Adapter, Conn, Version) ->
    Adapter:migrations_downgrade(Conn, Version).
