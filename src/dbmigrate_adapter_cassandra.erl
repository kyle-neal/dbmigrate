-module(dbmigrate_adapter_cassandra).

-behaviour(dbmigrate_adapter).

-export([init/0, connect/2, close/1, ensure_repo/2, migrations_applied/3,
         migrations_applied_by_version/4, migrations_upgrade/5, migrations_downgrade/2,
         transaction_begin/1, transaction_commit/1, transaction_start/1, transaction_end/1,
         acquire_lock/1, release_lock/1, file_template/1]).

-include_lib("cqerl/include/cqerl.hrl").

-define(DEFAULT_MIGRATIONS_TABLE, "schema_migrations").

-ifdef(TEST).

-export([configured_migrations_table/1, migrations_table_name/1, store_migrations_table/2,
         erase_migrations_table/1]).

-endif.

init() ->
    {ok, _} = application:ensure_all_started(cqerl),
    ok.

connect(App, DbName) ->
    AppOpts = dbmigrate_utils:app_db_opts(App, DbName),
    Host = proplists:get_value(host, AppOpts),
    Port = proplists:get_value(port, AppOpts),
    Keyspace = proplists:get_value(keyspace, AppOpts),
    MigrationsTable = configured_migrations_table(AppOpts),
    {ok, Client} = cqerl:get_client({Host, Port}, [{keyspace, Keyspace}]),
    ok = store_migrations_table(Client, MigrationsTable),
    Client.

close(Conn) ->
    ok = erase_migrations_table(Conn),
    ok.

ensure_repo(App, Db) ->
    Conn = connect(App, Db),
    MigrationsTable = migrations_table_name(Conn),
    {ok, _} =
        cqerl:run_query(Conn,
                        lists:flatten(["CREATE TABLE IF NOT EXISTS ",
                                       MigrationsTable,
                                       " ("
                                       " version text PRIMARY KEY,"
                                       " inserted_at TIMESTAMP,"
                                       " app_name text,"
                                       " app_version text,"
                                       " type text)"])),
    close(Conn).

migrations_applied(Conn, AppName, Type) ->
    AllRows = get_all_migrations_applied(Conn),
    AppNameBin = atom_to_binary(AppName, utf8),
    TypeBin = atom_to_binary(Type, utf8),

    FilteredRows =
        filter_by_fns(AllRows, [check_app_name_and_type_match(AppNameBin, TypeBin)]),

    {ok, Versions} = get_versions_sorted(FilteredRows),
    Versions.

migrations_applied_by_version(Conn, AppName, Type, AppVersion) ->
    AllRows = get_all_migrations_applied(Conn),
    AppVersionBin = list_to_binary(AppVersion),
    AppNameBin = atom_to_binary(AppName, utf8),
    TypeBin = atom_to_binary(Type, utf8),

    FilteredRows =
        filter_by_fns(AllRows,
                      [check_app_name_and_type_match(AppNameBin, TypeBin),
                       check_app_version_match(AppVersionBin)]),

    {ok, Versions} = get_versions_sorted(FilteredRows),
    Versions.

migrations_upgrade(Conn, Version, AppName, Type, AppVersionOverwrite) ->
    AppVsn = dbmigrate_utils:get_app_version(AppName, AppVersionOverwrite),
    MigrationsTable = migrations_table_name(Conn),
    CqlQuery =
        #cql_query{statement =
                       ["INSERT INTO ",
                        MigrationsTable,
                        " (version, inserted_at, app_name, app_version, type)",
                        " VALUES(?, toTimestamp(now()), ?, ?, ?);"],
                   values =
                       [{version, Version},
                        {app_name, atom_to_list(AppName)},
                        {app_version, AppVsn},
                        {type, atom_to_list(Type)}]},
    {ok, void} = cqerl:run_query(Conn, CqlQuery),
    ok.

migrations_downgrade(Conn, Version) ->
    MigrationsTable = migrations_table_name(Conn),
    CqlQuery =
        #cql_query{statement = ["DELETE FROM ", MigrationsTable, " WHERE version = ?;"],
                   values = [{version, Version}]},
    {ok, void} = cqerl:run_query(Conn, CqlQuery),
    ok.

transaction_begin(_Conn) ->
    ok.

transaction_commit(_Conn) ->
    ok.

transaction_start(_Conn) ->
    ok.

transaction_end(_Conn) ->
    ok.

acquire_lock(_Conn) ->
    ok.

release_lock(_Conn) ->
    ok.

file_template(FileName) ->
    ["-module('",
     filename:basename(FileName, ".erl"),
     "').\n",
     "%% Adapter: dbmigrate_adapter_cassandra\n\n",
     "-export([up/1, down/1]).\n\n",
     "up(Conn) ->\n",
     "    %% write queries here\n"
     "    %% e.g. {ok, _} = cqerl:run_query(Conn, \"here goes CQL query\"),\n"
     "    ok.\n\n"
     "down(Conn) ->\n",
     "    %% write queries here\n"
     "    ok.\n\n"].

%% ==================================
%% internals
%% ==================================

get_versions_sorted(Rows) ->
    Versions = [binary_to_list(proplists:get_value(version, Row)) || Row <- Rows],
    {ok, lists:sort(Versions)}.

configured_migrations_table(AppOpts) ->
    normalize_repo_name(proplists:get_value(migrations_table,
                                            AppOpts,
                                            ?DEFAULT_MIGRATIONS_TABLE)).

migrations_table_name(Conn) ->
    case get({?MODULE, migrations_table, Conn}) of
        undefined ->
            ?DEFAULT_MIGRATIONS_TABLE;
        MigrationsTable ->
            MigrationsTable
    end.

store_migrations_table(Conn, MigrationsTable) ->
    put({?MODULE, migrations_table, Conn}, normalize_repo_name(MigrationsTable)),
    ok.

erase_migrations_table(Conn) ->
    erase({?MODULE, migrations_table, Conn}),
    ok.

get_all_migrations_applied(Conn) ->
    MigrationsTable = migrations_table_name(Conn),
    {ok, CqlResult} =
        cqerl:run_query(Conn,
                        lists:flatten(["SELECT version, app_name, type, app_version FROM ",
                                       MigrationsTable])),
    do_get_all_migrations_applied(cqerl:all_rows(CqlResult), CqlResult).

do_get_all_migrations_applied([], _CqlResult) ->
    [];
do_get_all_migrations_applied(Rows, CqlResult) ->
    case cqerl:has_more_pages(CqlResult) of
        true ->
            {ok, NCqlResult} = cqerl:fetch_more(CqlResult),
            NRows = cqerl:all_rows(NCqlResult),
            do_get_all_migrations_applied(lists:append(Rows, NRows), NCqlResult);
        false ->
            Rows
    end.

check_app_name_and_type_match(AppName, Type) ->
    fun(Elem) ->
       AppNameDb = proplists:get_value(app_name, Elem),
       TypeDb = proplists:get_value(type, Elem),
       case {AppNameDb, TypeDb} of
           {AppName, Type} ->
               true;
           {null, null} ->
               true;
           _ ->
               false
       end
    end.

check_app_version_match(AppVersion) ->
    fun(Elem) ->
       case proplists:get_value(app_version, Elem) of
           AppVersion ->
               true;
           _ ->
               false
       end
    end.

filter_by_fns(Rows, Fns) ->
    lists:filter(fun(Row) -> lists:all(fun(Fn) -> Fn(Row) end, Fns) end, Rows).

normalize_repo_name(Name) when is_binary(Name) ->
    binary_to_list(Name);
normalize_repo_name(Name) when is_atom(Name) ->
    atom_to_list(Name);
normalize_repo_name(Name) ->
    Name.
