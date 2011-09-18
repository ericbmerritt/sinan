%% -*- mode: Erlang; fill-column: 80; comment-column: 75; -*-
%%%%-------------------------------------------------------------------
%%% Copyright (c) 2007-2010 Erlware
%%%
%%% Permission is hereby granted, free of charge, to any
%%% person obtaining a copy of this software and associated
%%% documentation files (the "Software"), to deal in the
%%% Software without restriction, including without limitation
%%% the rights to use, copy, modify, merge, publish, distribute,
%%% sublicense, and/or sell copies of the Software, and to permit
%%% persons to whom the Software is furnished to do so, subject to
%%% the following conditions:
%%%
%%% The above copyright notice and this permission notice shall
%%% be included in all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%%% OTHER DEALINGS IN THE SOFTWARE.
%%%---------------------------------------------------------------------------
%%% @author Eric Merritt
%%% @doc
%%%  The module handles building the
%%% @end
%%% @copyright (C) 2007-2010 Erlware
%%%--------------------------------------------------------------------------
-module(sin_discover).

-include_lib("eunit/include/eunit.hrl").
-include("internal.hrl").

%% API
-export([discover/2,
         format_exception/1]).

-define(POSSIBLE_CONFIGS, ["sinan.cfg", "_build.cfg"]).

%%====================================================================
%% API
%%====================================================================

%% @doc Run the discover task.
-spec discover(StartDir::string(),
               Override::sin_config:config()) ->
    Config::sin_config:config().
discover(StartDir, Override) ->
    ProjectDir = find_project_root(Override, StartDir),
    Config = process_raw_config(ProjectDir,
                                find_config(ProjectDir, Override),
                                Override),
    AppDirs = look_for_app_dirs(Config,
                                sin_config:get_value(Config, "build.dir"),
                                ProjectDir),
    build_app_info(Config, AppDirs, []).


%% @doc Format an exception thrown by this module
-spec format_exception(sin_exceptions:exception()) ->
    string().
format_exception(Exception) ->
    sin_exceptions:format_exception(Exception).

%%====================================================================
%%% Internal functions
%%====================================================================

%% @doc This trys to find the build config if it can. If the config is found it
%% is parsed in the normal way and returned to the user.  however, if it is not
%% found then the system attempts to unuit the build config from the project
%% properties.
-spec find_config(ProjectDir::string(),
                  Override::sin_config:config()) -> sin_config:config().
find_config(ProjectDir, Override) ->
    case read_configs(ProjectDir, ?POSSIBLE_CONFIGS) of
        no_build_config ->
            intuit_build_config(ProjectDir, Override);
        Config ->
            Config
    end.

%% @doc Take a raw config and merge it with the default config information
-spec process_raw_config(ProjectDir::string(),
                         Config::sin_config:config(),
                         Override::sin_config:config()) ->
    sin_config:config().
process_raw_config(ProjectDir, Config, Override) ->
    DefaultConfig =
        sin_config:new(filename:join([code:priv_dir(sinan),
                                      "default_build"])),
    Config0 = sin_config:apply_flavor(sin_config:merge_configs(DefaultConfig,
                                                               Config)),
    Flavor = sin_config:get_value(Config0, "build.flavor"),
    BuildDir = sin_config:get_value(Config0, "build_dir", "_build"),
    Config1 = sin_config:store(Config0, [{"build.root", filename:join([ProjectDir,
                                                                       BuildDir])},
                                         {"build.dir", filename:join([ProjectDir,
                                                                      BuildDir,
                                                                      Flavor])},
                                         {"project.dir", ProjectDir}]),
    % The override overrides everything
    sin_config:merge_configs(Config1, Override).

%% @doc If this is a single app project then the config is generated from the
%% app name and version combined with the usual default config information. If
%% this is not a single app project then a build config cannot be intuited and
%% an exception is thrown.
-spec intuit_build_config(ProjectDir::string(),
                          Override::sin_config:override()) ->
    sin_config:config().
intuit_build_config(ProjectDir, Override) ->
    %% App name is always the same as the name of the project dir
    AppName = filename:basename(ProjectDir),
    try
        case file:consult(get_app_file(ProjectDir, AppName, Override)) of
            {error, _} ->
                ?SIN_RAISE(Override, unable_to_intuit_config,
                           "Unable to generate a project config");
            {ok, [{application, _, Rest}]} ->
                build_out_intuited_config(AppName, Rest)
        end
    catch
        throw:no_app_metadata_at_top_level ->
            intuit_from_override(Override)
    end.


%% @doc the app file could be in ebin or src/app.src. we need to
%% check for both
-spec get_app_file(string(), string(), sin_config:config()) ->
                          string().
get_app_file(ProjectDir, AppName, Config) ->
    EbinDir = filename:join([ProjectDir,
                             "ebin",
                             AppName ++ ".app"]),
    SrcDir = filename:join([ProjectDir,
                            "src",
                             AppName ++ ".app.src"]),
    case {sin_utils:file_exists(Config, EbinDir),
          sin_utils:file_exists(Config, SrcDir)} of
        {_, true} ->
            SrcDir;
        {true, _} ->
            EbinDir;
         _ ->
            throw(no_app_metadata_at_top_level)
    end.

%% @doc Given information from the app dir that was found, create a new full
%% populated correct build config.
-spec build_out_intuited_config(AppName::string(), Rest::[{atom(), term()}]) ->
    sin_config:config().
build_out_intuited_config(AppName, Rest) ->
   {value, {vsn, ProjectVsn}} = lists:keysearch(vsn, 1, Rest),
    sin_config:store(sin_config:new(),
                     [{"project.name", AppName},
                      {"project.vsn", ProjectVsn}]).

%% @doc The override is command line override values that are provided by the
%% user. If the user provides a project name and version we can use that
-spec intuit_from_override(Override::sin_config:config()) ->
    sin_config:config().
intuit_from_override(Override) ->
    Name = case sin_config:get_value(Override, "project.name") of
               undefined ->
                   ?SIN_RAISE(Override, unable_to_intuit_config);
               PName ->
                   PName
           end,
    Version = case sin_config:get_value(Override, "project.vsn") of
               undefined ->
                   ?SIN_RAISE(Override, unable_to_intuit_config);
               PVsn ->
                   PVsn
           end,
    sin_config:store(sin_config:new(),
                     [{"project.name",Name},
                      {"project.vsn", Version}]).

%% @doc Attempt to read the build configs into the system. If the config exists
%% read it in and return it. Otherwise try the next one. If no configs are found
%% then return no_build_config
-spec read_configs(ProjectDir::string(), PossibleBuildConfigs::[string()]) ->
    sin_config:config().
read_configs(ProjectDir, [PossibleConfig | Rest]) ->
    try
        sin_config:new(filename:join([ProjectDir, PossibleConfig]))
    catch
        throw:{pe, _, {_, _, {invalid_config_file, _}}} ->
            read_configs(ProjectDir, Rest);
        throw:{pe, _, {_, _, invalid_config_file}} ->
            read_configs(ProjectDir, Rest)
    end;
read_configs(_ProjectDir, []) ->
    no_build_config.

%% @doc Find the root of the project. The project root may be marked by a _build
%% dir, a build config (sinan.cfg, _build.cfg). If none of those are found then
%% just return the directory we started with.
-spec find_project_root(sin_config:config(), Dir::string()) -> string().
find_project_root(Config, Dir) ->
    try
        find_project_root_by_markers(Config, Dir, ["_build" | ?POSSIBLE_CONFIGS])
    catch
        throw:no_parent_dir ->
            %% If we couldn't find samething to indicate the project root we
            %% will use the current directory
            Dir
    end.

%% @doc Find the project root given a list of markers. We look for these markers
%% starting in the base dir and then working our way up to the parent dirs. If
%% we hit the top of the directory structure without finding anything we throw
%% an exception.
-spec find_project_root_by_markers(sin_config:config(), Dir::string(),
                                   RootMarkers::[string()]) -> string().
find_project_root_by_markers(Config, Dir, RootMarkers) ->
    case root_marker_exists(Config, Dir, RootMarkers) of
        true ->
            Dir;
        false ->
            find_project_root_by_markers(Config, parent_dir(Dir), RootMarkers)
    end.

%% @doc Check to see if the root marker exists in the directory specified.
-spec root_marker_exists(sin_config:config(),
                         Dir::string(), RootMarkers::string()) ->
    boolean().
root_marker_exists(Config, Dir, [RootMarker | Rest]) ->
    case has_root_marker(Config, Dir, RootMarker) of
        true ->
            true;
        false ->
            root_marker_exists(Config, Dir, Rest)
    end;
root_marker_exists(_, _Dir, []) ->
    false.

%% @doc Given a single root marker and a directory return a boolean indicating
%% if the root marker exists in that file.
-spec has_root_marker(sin_config:config(),
                      Dir::string(), RootMarker::string()) ->
    boolean().
has_root_marker(Config, Dir, RootMarker) ->
    sin_utils:file_exists(Config, filename:join(Dir, RootMarker)).

%% @doc Given a directory returns the name of the parent directory.
-spec parent_dir(Filename::string()) -> DirName::string().
parent_dir(Filename) ->
    parent_dir(filename:split(Filename), []).

%% @doc Given list of directories, splits the list and returns all dirs but the
%%  last as a path.
parent_dir([_H], []) ->
    throw(no_parent_dir);
parent_dir([], []) ->
    throw(no_parent_dir);
parent_dir([_H], Acc) ->
    filename:join(lists:reverse(Acc));
parent_dir([H | T], Acc) ->
    parent_dir(T, [H | Acc]).

%% @doc Given a list of app dirs retrieves the application names.
-spec build_app_info(Config::sin_config:config(),
                     List::list(),
                     Acc::list()) ->
    Config::sin_config:config().
build_app_info(Config, [H|T], Acc) ->
    {AppName, AppFile, AppDir} = get_app_info(H),
    case file:consult(AppFile) of
        {ok, [{application, Name, Details}]} ->
            Config2 = source_details(AppDir, AppName,
                        process_details("apps." ++ AppName ++ ".",
                                        [{"name", Name},
                                         {"dotapp", AppFile},
                                         {"basedir", AppDir} | Details],
                                        Config)),
            Config3 = sin_config:store(Config2, "apps." ++ AppName ++ ".base",
                                       Details),
            build_app_info(Config3,  T, [AppName | Acc]);
        {error, {_, Module, Desc}} ->
            Error = Module:format_error(Desc),
            ?SIN_RAISE(Config, {invalid_app_file, Error},
                       "*.app file is invalid for ~s at ~s",
                       [AppName, AppFile]);
        {error, Error} ->
            ?SIN_RAISE(Config, {no_app_file, Error},
                       "No *.app file found for ~s at ~s",
                       [AppName, AppFile])
    end;
build_app_info(Config, [], Acc) ->
    sin_config:store(Config, "project.applist", Acc).

-spec get_app_info({ebin | appsrc, string()}) -> {string(), string()}.
get_app_info({ebin, Dir}) ->
    AppName = filename:basename(Dir),
    AppFile = filename:join([Dir, "ebin", string:concat(AppName, ".app")]),
    {AppName, AppFile, Dir};
get_app_info({appsrc, Dir}) ->
    AppName = filename:basename(Dir),
    AppFile = filename:join([Dir, "src", string:concat(AppName, ".app.src")]),
    {AppName, AppFile, Dir}.

-spec source_details(string(), string(), sin_config:config()) ->
    sin_config:config().
source_details(Dir, AppName, Config) ->
    SrcDir = filename:join([Dir, "src"]),
    TestDir = filename:join([Dir, "test"]),

    SrcModules = gather_modules(SrcDir),
    TestModules = gather_modules(TestDir),
    C1 = sin_config:store(Config,
                          "apps." ++ AppName ++ ".modules", SrcModules),
    sin_config:store(C1, "apps." ++ AppName ++ ".all_modules",
                     SrcModules ++ TestModules).

%% @doc Convert the details list to something that fits into the config nicely.
-spec process_details(BaseKey::string(), List::list(), Config::dict()) ->
    NewConfig::sin_config:config().
process_details(BaseName, [{Key, Value} | T], Config) when is_atom(Key) ->
    process_details(BaseName, T, sin_config:store(Config,
                                                  BaseName ++ atom_to_list(Key),
                                            Value));
process_details(BaseName, [{Key, Value} | T], Config) when is_list(Key)->
    process_details(BaseName, T, sin_config:store(Config, BaseName ++ Key,
                                                  Value));
process_details(_, [], Config) ->
    Config.

%% @doc Roles through subdirectories of the build directory looking for
%% directories that have a src and an ebin subdir. When it finds one it stops
%% recursing and adds the directory to the list to return.
-spec look_for_app_dirs(Config::sin_config:config(),
                        BuildDir::string(),
                        ProjectDir::string()) ->
    AppDirs::[string()].
look_for_app_dirs(Config, BuildDir, ProjectDir) ->
    Ignorables = [BuildDir] ++ case dict:find("ignore_dirs", Config) of
                                   {ok, Value} -> Value;
                                   _ -> []
                               end,
    case process_possible_app_dir(Config, BuildDir, ProjectDir,
                                  Ignorables, []) of
        [] ->
            ?SIN_RAISE(Config, no_app_directories,
                       "Unable to find any application directories."
                       " aborting now");
        Else ->
            Else
    end.

%% @doc Process the app dir to see if it is an application directory.
-spec process_possible_app_dir(Config::sin_config:config(),
                               BuildDir::string(),
                               TargetDir::string(),
                               Ignorables::[string()], Acc::list()) ->
                                      ListOfDirs::[{ebin | appsrc, string()}].
process_possible_app_dir(Config, BuildDir, TargetDir, Ignorables, Acc) ->
    PossibleAppName = filename:basename(TargetDir),
    case filelib:is_dir(TargetDir) andalso not
        sin_utils:is_dir_ignorable(TargetDir, Ignorables) of
        true ->
            {ok, Dirs} = file:list_dir(TargetDir),
            Ebin = has_src_ebin_dotapp(Config, PossibleAppName,
                                       TargetDir, Dirs),
            AppSrc =  has_src_appsrc(Config, PossibleAppName,
                                     TargetDir, Dirs),
            case {AppSrc, Ebin} of
                {true, true} ->
                    ?SIN_RAISE(Config,
                               "conflict: ~s has both an ebin/*.app "
                               "and a src/*.app.src ", [TargetDir]);
                {true, _} ->
                    [{appsrc, TargetDir} | Acc];
                {_, true}  ->
                    [{ebin, TargetDir} | Acc];
                _ ->
                    lists:foldl(fun(Sub, NAcc) ->
                                        Dir = filename:join([TargetDir, Sub]),
                                        process_possible_app_dir(Config,
                                                                 BuildDir,
                                                                 Dir,

                                                                 Ignorables,
                                                                 NAcc)
                                end, Acc, Dirs)
            end;
        false ->
            Acc
    end.

-spec has_src_ebin_dotapp(sin_config:config(),
                          string(), string(), [string()]) ->
                                 boolean().
has_src_ebin_dotapp(Config, BaseName, BaseDir, SubDirs) ->
    lists:member("ebin", SubDirs) andalso
        lists:member("src", SubDirs) andalso
        sin_utils:file_exists(Config,
                              filename:join([BaseDir, "ebin",
                                             BaseName ++
                                                 ".app"])).

-spec has_src_appsrc(sin_config:config(),
                     string(), string(), [string()]) ->
                            boolean().
has_src_appsrc(Config, BaseName, BaseDir, SubDirs) ->
    lists:member("src", SubDirs) andalso
        sin_utils:file_exists(Config,
                              filename:join([BaseDir, "src",
                                             BaseName ++
                                                 ".app.src"])).


%% @doc Gather the list of modules that currently may need to be built.
gather_modules(SrcDir) ->
    case filelib:is_dir(SrcDir) of
        true ->
            filelib:fold_files(SrcDir,
                               "(.+\.erl|.+\.yrl|.+\.asn1|.+\.asn)$",
                   true, % Recurse into subdirectories of src
                   fun(File, Acc) ->
                           Ext = filename:extension(File),
                           AtomExt = list_to_atom(Ext),
                           TestImplementations =
                               case string:str(File, "_SUITE.erl") of
                                   0 ->
                                       [];
                                   _ ->
                                       [common_test]
                                end,
                           [{File, module_name(File), Ext, AtomExt,
                             TestImplementations} | Acc]
                   end, []);
        false ->
             []
     end.

%% @doc Extract the module name from the file name.
module_name(File) ->
    list_to_atom(filename:rootname(filename:basename(File))).

%%====================================================================
%% tests
%%====================================================================
find_project_root_test() ->
    ProjectRoot = filename:join(["test_data",
                                 "sin_discover",
                                 "find_project_root_by_markers"]),

    DirStart = filename:join(["test_data",
                              "sin_discover",
                              "find_project_root_by_markers",
                              "d1", "d2", "d3", "d4"]),

    ?assertMatch(ProjectRoot, find_project_root(sin_config:new(), DirStart)),
    ?assertMatch("/tmp", find_project_root(sin_config:new(), "/tmp")).

find_project_root_by_markers_test() ->
    ProjectRoot = filename:join(["test_data",
                                 "sin_discover",
                                 "find_project_root_by_markers"]),

    DirStart = filename:join(["test_data",
                              "sin_discover",
                              "find_project_root_by_markers",
                              "d1", "d2", "d3", "d4"]),
    ?assertMatch(ProjectRoot, find_project_root_by_markers(sin_config:new(),
                                                           DirStart,
                                                           ["_build",
                                                            "_build.cfg",
                                                            "sinan.cfg"])),
    ?assertException(throw, no_parent_dir,
                     find_project_root_by_markers(sin_config:new(),
                       "/tmp",
                       ["somethingthatshouldneverbefound",
                        "somethingelsethatshouldneverbefound"])).

root_marker_exists_test() ->
    DirT1 = filename:join(["test_data", "sin_discover",
                           "root_marker_exists", "m1"]),
    DirT2 = filename:join(["test_data", "sin_discover",
                           "root_marker_exists", "m2"]),
    ?assertMatch(true, root_marker_exists(sin_config:new(),
                                          DirT1, ["_build", "_build.cfg",
                                                "sinan.cfg"])),
    ?assertMatch(false, root_marker_exists(sin_config:new(),
                                           DirT2, ["_build", "_build.cfg",
                                                   "sinan.cfg"])).

has_root_marker_test() ->
    Dir = filename:join(["test_data", "sin_discover", "has_root_marker"]),
    ?assertMatch(true,
                has_root_marker(sin_config:new(),
                                Dir, "_build")),
    ?assertMatch(true,
                has_root_marker(sin_config:new(),
                                Dir, "_build.cfg")),
    ?assertMatch(true,
                has_root_marker(sin_config:new(),
                                Dir, "sinan.cfg")),
    ?assertMatch(false,
                has_root_marker(sin_config:new(),
                                Dir, "foobar")),
    ?assertMatch(false,
                 has_root_marker(sin_config:new(),
                                 Dir, "should_not_be_there")).

read_configs_test() ->
    DirGood = filename:join(["test_data", "sin_discover",
                             "read_configs", "good"]),
    DirBad = filename:join(["test_data", "sin_discover",
                            "read_configs", "bad"]),
    ?assertNot(no_build_config == read_configs(DirGood, ?POSSIBLE_CONFIGS)),
    ?assertMatch(no_build_config, read_configs(DirBad, ?POSSIBLE_CONFIGS)).

build_out_intuited_config_test() ->
    Config = build_out_intuited_config("test_proj",
                                       [{modules, [one, two, three]},
                                        {vsn, "0.2.0"}]),
    ?assertMatch("test_proj", sin_config:get_value(Config, "project.name")),
    ?assertMatch("0.2.0", sin_config:get_value(Config, "project.vsn")).

intuit_build_config_test() ->
    ProjectDir = filename:join(["test_data", "sin_discover",
                                "intuit_build_config",
                                "test_project"]),
    BadProjectDir = filename:join(["test_data", "sin_discover",
                                   "intuit_build_config",
                                   "test_project2"]),
    Config = intuit_build_config(ProjectDir, sin_config:new()),
    ?assertMatch("test_project", sin_config:get_value(Config, "project.name")),
    ?assertMatch("0.1.1", sin_config:get_value(Config, "project.vsn")),
    ?assertException(throw,
                     {pe, _, {_, _, unable_to_intuit_config}},
                     intuit_build_config(BadProjectDir, sin_config:new())),
    Override = sin_config:store(sin_config:new(), [{"project.name", "fobachu"},
                                                   {"project.vsn", "0.1.0"}]),
    OConfig = intuit_build_config(BadProjectDir, Override),
    ?assertMatch("fobachu", sin_config:get_value(OConfig, "project.name")),
    ?assertMatch("0.1.0", sin_config:get_value(OConfig, "project.vsn")).

process_raw_config_test() ->
    ProjectDir = filename:join(["test_data", "sin_discover",
                                "intuit_build_config",
                                "test_project"]),
    BuildRoot = filename:join([ProjectDir,
                              "_build"]),
    BuildDir = filename:join([ProjectDir,
                              "_build",
                               "development"]),
    Config =
        process_raw_config(ProjectDir,
                           intuit_build_config(ProjectDir, sin_config:new()),
                           sin_config:new()),
    ?assertMatch(BuildDir, sin_config:get_value(Config, "build.dir")),

    ?assertMatch(BuildRoot, sin_config:get_value(Config, "build.root")),
    ?assertMatch("development", sin_config:get_value(Config, "default_flavor")),
    ?assertMatch("build", sin_config:get_value(Config, "default_task")),

    Override = sin_config:store(sin_config:new(), [{"project.name", "fobachu"},
                                                   {"project.vsn", "0.1.0"}]),
    OConfig =
        process_raw_config(ProjectDir,
                           intuit_build_config(ProjectDir, sin_config:new()),
                           Override),
    ?assertMatch("fobachu", sin_config:get_value(OConfig, "project.name")),
    ?assertMatch("0.1.0", sin_config:get_value(OConfig, "project.vsn")).

find_config_test() ->
    IntuitProjectDir = filename:join(["test_data", "sin_discover",
                                      "find_config",
                                      "test_project"]),
    ConfigProjectDir = filename:join(["test_data", "sin_discover",
                                      "find_config",
                                      "test_project2"]),

    IntuitConfig = find_config(IntuitProjectDir, sin_config:new()),
    ?assertMatch("test_project", sin_config:get_value(IntuitConfig,
                                                      "project.name")),
    ?assertMatch("0.1.1", sin_config:get_value(IntuitConfig, "project.vsn")),

    ConfigConfig = find_config(ConfigProjectDir, sin_config:new()),
    ?assertMatch("foobar", sin_config:get_value(ConfigConfig,
                                                      "project.name")),
    ?assertMatch("0.0.0.1", sin_config:get_value(ConfigConfig, "project.vsn")).

