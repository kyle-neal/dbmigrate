-module(dbmigrate_loader_tests).

-include_lib("eunit/include/eunit.hrl").

%%% ===================================================================
%%% generate_version/0
%%% ===================================================================

generate_version_format_test() ->
    V = dbmigrate_loader:generate_version(),
    %% Must be 14-digit numeric string
    ?assertEqual(14, length(V)),
    ?assertEqual(match,
                 re:run(V, "^[0-9]{14}$", [{capture, none}])).

%%% ===================================================================
%%% underscore/1
%%% ===================================================================

underscore_spaces_test() ->
    ?assertEqual("add_users_table", dbmigrate_loader:underscore("add users table")).

underscore_hyphens_test() ->
    ?assertEqual("drop_column", dbmigrate_loader:underscore("drop-column")).

underscore_commas_test() ->
    ?assertEqual("a_b_c", dbmigrate_loader:underscore("a,b,c")).

underscore_mixed_test() ->
    ?assertEqual("create_index_on_users", dbmigrate_loader:underscore("create index-on,users")).

%%% ===================================================================
%%% available/1
%%% ===================================================================

available_test_() ->
    {setup,
     fun() ->
        Dir = filename:join(["_tmp", "loader_test_avail"]),
        ok = filelib:ensure_dir(filename:join(Dir, "x")),
        ok = file:write_file(filename:join(Dir, "20260315_a.erl"), ""),
        ok = file:write_file(filename:join(Dir, "20260316_b.erl"), ""),
        ok = file:write_file(filename:join(Dir, "readme.txt"), ""),
        Dir
     end,
     fun(Dir) ->
        file:del_dir_r(Dir)
     end,
     fun(Dir) ->
        [{"Only .erl files returned, sorted",
          fun() ->
             Result = dbmigrate_loader:available(Dir),
             ?assertEqual(["20260315_a", "20260316_b"], Result)
          end}]
     end}.

%%% ===================================================================
%%% compile_and_load/2
%%% ===================================================================

compile_and_load_test_() ->
    {setup,
     fun() ->
        Dir = filename:join(["_tmp", "loader_test_compile"]),
        ok = filelib:ensure_dir(filename:join(Dir, "x")),
        ModSrc =
            "-module(test_mig_001).\n"
            "-export([up/1, down/1]).\n"
            "up(_) -> ok.\n"
            "down(_) -> ok.\n",
        ok = file:write_file(filename:join(Dir, "test_mig_001.erl"), ModSrc),
        Dir
     end,
     fun(Dir) ->
        code:purge(test_mig_001),
        code:delete(test_mig_001),
        file:del_dir_r(Dir)
     end,
     fun(Dir) ->
        [{"Compile and load a migration module",
          fun() ->
             {ok, Mod} = dbmigrate_loader:compile_and_load("test_mig_001", Dir),
             ?assertEqual(test_mig_001, Mod),
             ?assertEqual(ok, Mod:up(ignored)),
             ?assertEqual(ok, Mod:down(ignored))
          end}]
     end}.
