-module(dbmigrate_loader).

%% Migration discovery and compilation.
%%
%% Scans a migrations directory, compiles each .erl file on demand,
%% and returns a sorted list of migration version strings.

-export([migrations_path/2, available/1, compile_and_load/2, generate_version/0,
         underscore/1]).

-ifdef(TEST).

-compile([export_all]).

-endif.

%% @doc Resolve the filesystem path for migrations.
%%
%% Checks for an explicit `migrate_path` key first; otherwise falls
%% back to `<priv_dir>/migrations/<backend>/`.
-spec migrations_path(atom(), atom()) -> string().
migrations_path(App, Backend) ->
    AppDbOpts = dbmigrate_utils:app_db_opts(App, Backend),
    case proplists:get_value(migrate_path, AppDbOpts) of
        undefined ->
            PrivDir = code:priv_dir(App),
            PrivDir ++ "/migrations/" ++ atom_to_list(Backend) ++ "/";
        Path ->
            Path
    end.

%% @doc Return a sorted list of migration version strings found on disk.
-spec available(string()) -> [string()].
available(Path) ->
    {ok, Listing0} = file:list_dir(Path),
    ErlFiles = [F || F <- Listing0, filename:extension(F) =:= ".erl"],
    Versions = [filename:rootname(F) || F <- ErlFiles],
    lists:sort(Versions).

%% @doc Compile a migration file and load the resulting module.
%%
%% Returns {ok, Module} on success; crashes on compile error (by design,
%% since a broken migration file should halt execution).
-spec compile_and_load(string(), string()) -> {ok, module()}.
compile_and_load(Version, Path) ->
    FilePath = filename:join([Path, Version ++ ".erl"]),
    {ok, Mod, Bin} = compile:file(FilePath, [binary, report]),
    {module, Mod} = code:load_binary(Mod, FilePath, Bin),
    {ok, Mod}.

%% @doc Generate a 14-digit timestamp string for new migration filenames.
-spec generate_version() -> string().
generate_version() ->
    {{Y, M, D}, {H, MM, S}} =
        calendar:now_to_datetime(
            os:timestamp()),
    lists:flatten(
        io_lib:format("~.4.0w~.2.0w~.2.0w~.2.0w~.2.0w~.2.0w", [Y, M, D, H, MM, S])).

%% @doc Replace whitespace, hyphens, and commas with underscores.
-spec underscore(string()) -> string().
underscore(Name) ->
    re:replace(Name, "[\\s,-]+", "_", [global, {return, list}]).
