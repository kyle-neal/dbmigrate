-module(dbmigrate_utils).

-export([app_db_opts/2, get_app_version/2]).

app_db_opts(App, Db) ->
    {ok, AppOpts} = application:get_env(App, migrate),
    proplists:get_value(Db, AppOpts).

get_app_version(AppName, AppVersionOverwrite) ->
    case AppVersionOverwrite of
        undefined ->
            {ok, ApplicationVsn} = application:get_key(AppName, vsn),
            ApplicationVsn;
        _ ->
            AppVersionOverwrite
    end.
