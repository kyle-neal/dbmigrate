-module(dbmigrate_SUITE).

%% API
-export([all/0]).
%% test cases
-export([t_start_stop/1]).

-include_lib("common_test/include/ct.hrl").

all() ->
    [t_start_stop].

t_start_stop(_Config) ->
    ok = dbmigrate:start(),
    ok = dbmigrate:stop().
