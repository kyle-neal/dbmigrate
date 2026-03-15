-module(dbmigrate_adapter_elasticsearch).

-behaviour(dbmigrate_adapter).

-include_lib("erlastic_search/include/erlastic_search.hrl").

-export([init/0, connect/2, close/1, ensure_repo/2, migrations_applied/3,
         migrations_applied_by_version/4, migrations_upgrade/5, migrations_downgrade/2,
         transaction_begin/1, transaction_commit/1, transaction_start/1, transaction_end/1,
         acquire_lock/1, release_lock/1, file_template/1]).

-record(es_info, {erls_params, index_name, type_name, migration_index}).

-define(DEFAULT_MIGRATIONS_INDEX, "schema_migrations").

-ifdef(TEST).

-export([configured_migration_index/1]).

-endif.

init() ->
    ok.

connect(App, DbName) ->
    {ok, _} = application:ensure_all_started(erlastic_search),
    AppOpts = dbmigrate_utils:app_db_opts(App, DbName),

    IndexName = proplists:get_value(index_name, AppOpts),
    TypeName = proplists:get_value(type_name, AppOpts),
    MigrationIndex = configured_migration_index(AppOpts),
    Host = proplists:get_value(host, AppOpts),
    Port = proplists:get_value(port, AppOpts),
    #es_info{erls_params = #erls_params{host = Host, port = Port},
             index_name = IndexName,
             type_name = TypeName,
             migration_index = MigrationIndex}.

close(_Conn) ->
    ok.

ensure_repo(App, Db) ->
    Conn =
        #es_info{erls_params = Params, migration_index = MigrationIndex} = connect(App, Db),
    case erlastic_search:index_exists(Params, MigrationIndex) of
        {ok, false} ->
            {ok, _} = erlastic_search:create_index(Params, MigrationIndex),
            ok;
        {ok, true} ->
            ok
    end,
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

migrations_upgrade(#es_info{erls_params = Params,
                            migration_index = MigrationIndex,
                            type_name = TypeName},
                   Version,
                   AppName,
                   Type,
                   AppVersionOverwrite) ->
    AppVsn = dbmigrate_utils:get_app_version(AppName, AppVersionOverwrite),
    Doc = [{app_version, list_to_binary(AppVsn)},
           {inserted_at,
            tic:epoch_secs_to_iso8601(
                tic:now_to_epoch_secs())},
           {version, list_to_binary(Version)},
           {app_name, AppName},
           {type, Type}],
    {ok, _} = erlastic_search:index_doc(Params, MigrationIndex, TypeName, Doc),

    ok.

migrations_downgrade(#es_info{erls_params = Params,
                              migration_index = MigrationIndex,
                              type_name = TypeName},
                     Version) ->
    Doc = [{query, [{match, [{version, Version}]}]}],
    {ok, _} = erlastic_search:delete_doc_by_query_doc(Params, MigrationIndex, TypeName, Doc),
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
     "%% Adapter: dbmigrate_adapter_elasticsearch\n\n",
     "-export([up/1, down/1]).\n\n",
     "-record(es_info,\n",
     "   {\n",
     "    erls_params,\n",
     "    index_name,\n",
     "    type_name,\n",
     "    migration_index\n",
     "   }).\n\n",
     "up(#es_info{erls_params=_Params, index_name=_IndexName, type_name=_TypeName}) ->\n",
     "    %% write queries here\n",
     "    %% e.g. {ok, #{<<\"acknowledged\">> := true}} = erlastic_search:put_mapping(Params, IndexName, TypeName,[{<<\"properties\">>, [{<<\"new_field\">>, [{<<\"type\">>, <<\"keyword\">>}]}]}]),\n",
     "    ok.\n\n",
     "down(_) ->\n",
     "    %% write queries here\n",
     "    ok.\n\n"].

%% ==================================
%% internals
%% ==================================

get_versions_sorted(Rows) ->
    Versions = [binary_to_list(maps:get(<<"version">>, Row)) || Row <- Rows],
    {ok, lists:sort(Versions)}.

configured_migration_index(AppOpts) ->
    normalize_repo_name(proplists:get_value(migrations_index,
                                            AppOpts,
                                            proplists:get_value(migrations_table,
                                                                AppOpts,
                                                                ?DEFAULT_MIGRATIONS_INDEX))).

get_all_migrations_applied(#es_info{erls_params = Params,
                                    migration_index = MigrationIndex}) ->
    {ok, Res} = erlastic_search:search(Params, MigrationIndex, [{from, 0}, {size, 1000}]),
    R1 = maps:get(<<"hits">>, Res),
    R2 = maps:get(<<"hits">>, R1),
    lists:map(fun(Rec) ->
                 Id = maps:get(<<"_id">>, Rec),
                 Source = maps:get(<<"_source">>, Rec),
                 Source#{<<"_id">> => Id}
              end,
              R2).

check_app_name_and_type_match(AppName, Type) ->
    fun(Elem) ->
       AppNameDb = maps:get(<<"app_name">>, Elem, null),
       TypeDb = maps:get(<<"type">>, Elem, null),
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
       case maps:get(<<"app_version">>, Elem, undefined) of
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
