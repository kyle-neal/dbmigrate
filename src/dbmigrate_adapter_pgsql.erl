-module(dbmigrate_adapter_pgsql).

-behaviour(dbmigrate_adapter).

%% API
-export([init/0, connect/2, close/1, ensure_repo/2, migrations_applied/3,
         migrations_applied_by_version/4, migrations_upgrade/5, migrations_downgrade/2,
         transaction_begin/1, transaction_commit/1, transaction_start/1, transaction_end/1,
         acquire_lock/1, release_lock/1, file_template/1]).

-define(DEFAULT_MIGRATIONS_TABLE, "schema_migrations").

-ifdef(TEST).

-export([configured_migrations_table/1, migrations_table_name/1, store_migrations_table/2,
         erase_migrations_table/1]).

-endif.

%%%===================================================================
%%% API
%%%===================================================================
init() ->
    ok.

connect(App, DbName) ->
    AppOpts = dbmigrate_utils:app_db_opts(App, DbName),

    Host = proplists:get_value(host, AppOpts),
    Port = proplists:get_value(port, AppOpts),
    User = proplists:get_value(username, AppOpts),
    Pass = proplists:get_value(password, AppOpts),
    Db = proplists:get_value(database, AppOpts),
    Timeout = proplists:get_value(timeout, AppOpts),
    MigrationsTable = configured_migrations_table(AppOpts),
    Opts0 = [{port, Port}, {database, Db}, {timeout, Timeout}],

    %% SSL detection and forwarding
    SslFlag = proplists:get_value(ssl, AppOpts, false),
    SslConnectOpts =
        case SslFlag of
            false ->
                [];
            true ->
                %% Build ssl_opts only when SSL is enabled
                SslOpts1 =
                    case proplists:get_value(verify, AppOpts) of
                        undefined ->
                            [];
                        V ->
                            [{verify, V}]
                    end,
                SslOpts2 =
                    case proplists:get_value(cacertfile, AppOpts) of
                        undefined ->
                            SslOpts1;
                        CF when is_binary(CF) ->
                            [{cacertfile, binary_to_list(CF)} | SslOpts1];
                        CF ->
                            [{cacertfile, CF} | SslOpts1]
                    end,
                SslOpts3 =
                    case proplists:get_value(depth, AppOpts) of
                        undefined ->
                            SslOpts2;
                        D ->
                            [{depth, D} | SslOpts2]
                    end,
                %% Default SNI to Host if not provided
                HostSNI =
                    case Host of
                        H when is_binary(H) ->
                            binary_to_list(H);
                        H ->
                            H
                    end,
                SslOpts =
                    case proplists:get_value(server_name_indication, AppOpts) of
                        undefined ->
                            [{server_name_indication, HostSNI} | SslOpts3];
                        SNI when is_binary(SNI) ->
                            [{server_name_indication, binary_to_list(SNI)} | SslOpts3];
                        SNI ->
                            [{server_name_indication, SNI} | SslOpts3]
                    end,
                [{ssl, true} | SslOpts];
            required ->
                SslOpts1r =
                    case proplists:get_value(verify, AppOpts) of
                        undefined ->
                            [];
                        V ->
                            [{verify, V}]
                    end,
                SslOpts2r =
                    case proplists:get_value(cacertfile, AppOpts) of
                        undefined ->
                            SslOpts1r;
                        CF when is_binary(CF) ->
                            [{cacertfile, binary_to_list(CF)} | SslOpts1r];
                        CF ->
                            [{cacertfile, CF} | SslOpts1r]
                    end,
                SslOpts3r =
                    case proplists:get_value(depth, AppOpts) of
                        undefined ->
                            SslOpts2r;
                        D ->
                            [{depth, D} | SslOpts2r]
                    end,
                HostSNIr =
                    case Host of
                        H when is_binary(H) ->
                            binary_to_list(H);
                        H ->
                            H
                    end,
                SslOptsr =
                    case proplists:get_value(server_name_indication, AppOpts) of
                        undefined ->
                            [{server_name_indication, HostSNIr} | SslOpts3r];
                        SNI when is_binary(SNI) ->
                            [{server_name_indication, binary_to_list(SNI)} | SslOpts3r];
                        SNI ->
                            [{server_name_indication, SNI} | SslOpts3r]
                    end,
                [{ssl, required} | SslOptsr]
        end,

    Opts = Opts0 ++ SslConnectOpts,
    {ok, Conn} = epgsql:connect(Host, User, Pass, Opts),
    ok = store_migrations_table(Conn, MigrationsTable),
    Conn.

close(Conn) ->
    ok = erase_migrations_table(Conn),
    epgsql:close(Conn).

ensure_repo(App, Db) ->
    Conn = connect(App, Db),
    MigrationsTable = migrations_table_name(Conn),
    {ok, _, _} = epgsql:squery(Conn, "SET search_path TO public"),
    {ok, _, _} =
        epgsql:squery(Conn,
                      lists:flatten(["CREATE TABLE IF NOT EXISTS ",
                                     MigrationsTable,
                                     " ("
                                     "  version character varying PRIMARY KEY,"
                                     "  inserted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,"
                                     "  app_name character varying NULL,"
                                     "  app_version character varying NULL,"
                                     "  type character varying NULL)"])),
    close(Conn).

migrations_applied(Conn, AppName, Type) ->
    MigrationsTable = migrations_table_name(Conn),
    {ok, _, Res} =
        epgsql:equery(Conn,
                      "SELECT version::text"
                      " FROM "
                      ++ MigrationsTable
                      ++ " "
                         " WHERE (app_name = $1 OR app_name IS NULL) "
                         "   AND (type = $2 OR type IS NULL)",
                      [AppName, Type]),
    Versions = lists:map(fun({V}) -> binary_to_list(V) end, Res),
    lists:sort(Versions).

migrations_applied_by_version(Conn, AppName, Type, AppVersion) ->
    MigrationsTable = migrations_table_name(Conn),
    {ok, _, Res} =
        epgsql:equery(Conn,
                      "SELECT version::text"
                      " FROM "
                      ++ MigrationsTable
                      ++ " "
                         " WHERE (app_name = $1 OR app_name IS NULL) "
                         "   AND (type = $2 OR type IS NULL)"
                         "   AND app_version = $3",
                      [AppName, Type, AppVersion]),
    Versions = lists:map(fun({V}) -> binary_to_list(V) end, Res),
    lists:sort(Versions).

migrations_upgrade(Conn, Version, AppName, Type, AppVersionOverwrite) ->
    AppVsn = dbmigrate_utils:get_app_version(AppName, AppVersionOverwrite),
    MigrationsTable = migrations_table_name(Conn),
    {ok, _} =
        epgsql:equery(Conn,
                      "INSERT INTO "
                      ++ MigrationsTable
                      ++ "  (version, inserted_at, app_name, app_version, type)"
                         "  VALUES ($1, current_timestamp, $2, $3, $4)",
                      [Version, AppName, AppVsn, Type]),
    ok.

migrations_downgrade(Conn, Version) ->
    MigrationsTable = migrations_table_name(Conn),
    {ok, _} =
        epgsql:equery(Conn,
                      "DELETE FROM " ++ MigrationsTable ++ "  WHERE version = $1",
                      [Version]),
    ok.

transaction_begin(Conn) ->
    {ok, _, _} = epgsql:squery(Conn, "BEGIN;"),
    ok.

transaction_commit(Conn) ->
    {ok, _, _} = epgsql:squery(Conn, "COMMIT;"),
    ok.

transaction_start(_Conn) ->
    ok.

transaction_end(_Conn) ->
    ok.

%% Advisory lock using a fixed key derived from 'dbmigrate'.
acquire_lock(Conn) ->
    {ok, _, [{true}]} = epgsql:squery(Conn, "SELECT pg_advisory_lock(73571);"),
    ok.

release_lock(Conn) ->
    {ok, _, [{true}]} = epgsql:squery(Conn, "SELECT pg_advisory_unlock(73571);"),
    ok.

file_template(FileName) ->
    ["-module('",
     filename:basename(FileName, ".erl"),
     "').\n",
     "%% Adapter: dbmigrate_adapter_pgsql\n\n",
     "-export([up/1, down/1]).\n\n",
     "up(Conn) ->\n",
     "    %% write queries here\n"
     "    ok.\n\n"
     "down(Conn) ->\n",
     "    %% write queries here\n"
     "    ok.\n\n"].

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

normalize_repo_name(Name) when is_binary(Name) ->
    binary_to_list(Name);
normalize_repo_name(Name) when is_atom(Name) ->
    atom_to_list(Name);
normalize_repo_name(Name) ->
    Name.
