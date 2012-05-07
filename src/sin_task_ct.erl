%% -*- mode: Erlang; fill-column: 80; comment-column: 75; -*-
%%%---------------------------------------------------------------------------
%%% @author Eric Merritt
%%% @doc
%%% @end
%%% @copyright (C) 2012 Erlware
%%%---------------------------------------------------------------------------
-module(sin_task_ct).

-behaviour(sin_task).

-include_lib("sinan/include/sinan.hrl").

%% API
-export([description/0, do_task/2, format_exception/1]).

-define(TASK, ct).
-define(DEPS, [release]).

%%====================================================================
%% API
%%====================================================================

%% @doc provides a description of the sytem, for help and other reasons
-spec description() -> sin_task:task_description().
description() ->

    Desc = "
ct Task
=======

The ct task is a method of running the [Common Test
Framework](http://www.erlang.org/doc/apps/common_test/users_guide.html) on a the
project. You should be familiar with the common test framework to use this task.

This task allows you to setup 'configurations' and run those configurations
individually. It also allows specify a given configuration and echo a command
line that will allow you to run that configuration directly with the ct_run
application. This is useful when you want to do do things like step through a
debugger or add additional options that are not available in the options sinan
exposes.

To run `ct` you must have setup some named `ct` entry (more about that follows)
in the `sinan.config` and call Sinan with that ct entry.

    $> sinan ct -t my_entry

To get the command line for running common test echoed you should do the
following:

    $> sinan ct -t my_entry --echo


Configuration
-------------

In this case Sinan does not do *any* configuration for you outside of
setting up the proper code paths. Sinan does however give you several variables
that you can use in your options (at least those options that contain directory
specifications).

These exist to help you configure your tests. It is suggested that you put all
output under the 'build_dir' and no in your project itself. Otherwise sinan
clean will be *unable* to clean the project correctly. However, this is
completely up to you.

### Available Variables

These are the variables available in your configuration options.

*Project Dir*

This is the project directory. This should be the same as CWD, since Sinan sets
the projec directory to be the current directory.

    $project_dir$

*Build Root*

The build root points to the top level of the build directory. This usually
points `$project_dir$/_build`. You shouldn't put too much at this level directory,
because you can have multiple releases that may step on each other.

   $build_root$

*Build Dir*

Build dir points to the build output directory, that is the release directory
where all build output ends up.

   $build_dir$

*Release Name*

This is simply the name of the currently active release.

    $release_name$

*Release Version*

This is the currently set version of the *release*.

   $release_vsn$

*Apps Dir*

This points to the 'lib' dir of the release directory. This is equivalent to
`$apps_dir$/lib`.

   $apps_dir$

*Release Dir*

This points to the directory containing the release metadata. It is equivalent
to `$build_dir$/releases/$release_vsn$`

   $release_dir$

*Home Dir*

This is simply the user's home directory.

   $home_dir$

*Application Directory*

Lets say we had an application called foo. The variable `$foo_dir$` would point
to the root directory of that application. So in this model the ebin directory
of foo would look like '$foo_dir$/ebin'.

    $<app_name>_dir$

*Application Version*

The is similar to `$<app_name>_dir$` except contains the version of the
application instead of its dir. So for our foo example if we wanted the version
of foo we would do `$foo_vsn$`.

### Multiple Common Test Configurations

Sinan give you the ability to have multiple common test configurations. The
configurations are are specified as follows.

    {ct_config, [{config_name(), terms()}]}.

Lets say we had a configuration call alternate in our bar release. We might
configure it as follows.

    {ct_config, [{alternate, [{dir, \"$foo_dir$/test\"}]}]}.


To run that configuration you would simple call this from the command line

    $> sinan ct -t alternate

You could also have specified more then one configuration.

    {ct_config, [{alternate, [{dir, \"$foo_dir$/test\"}]}
                 {main, [{dir, \"$foo_dir$/test\"}]}.

then you could do one of the following.

    $> sinan ct -t alternate

or

    $> sinan ct -t main


If you don't want to specify the -t all the time you may, at your option,
specify a config option to give the default test to run. You may do that with
the following directive.

    {ct_default, TestName::atom()}.

So if we wanted the main spec to be the default we would do:

    {ct_default, main}.

and then run the test as

    $> sinan ct

This would then run the common test task with the `main` test spec. *NOTE* you
must have either a default specified or a name specified in the -t option.


### Available Configuration Options

These are exactly the same options taken by
[ct:run/1](http://www.erlang.org/doc/man/ct.html#run-1). Look there for the
common test documentation.

    {dir, TestDirs}                      % Variables Supported
    {suite, Suites}
    {group, Groups}
    {testcase, Cases}
    {spec, TestSpecs}
    {label, Label}
    {config, CfgFiles}                   % Variables Supported
    {userconfig, UserConfig}             % Variables Supported
    {allow_user_terms, Bool}
    {logdir, LogDir}                     % Variables Supported
    {silent_connections, Conns}
    {stylesheet, CSSFile}                % Variables Supported
    {cover, CoverSpecFile}               % Variables Supported
    {step, StepOpts}
    {event_handler, EventHandlers}
    {include, InclDirs}                  % Variables Supported
    {auto_compile, Bool}
    {create_priv_dir, CreatePrivDir}
    {multiply_timetraps, M}
    {scale_timetraps, Bool}
    {repeat, N}
    {duration, DurTime}
    {until, StopTime}
    {force_stop, Bool}
    {decrypt, DecryptKeyOrFile}          % Variables Supported
    {refresh_logs, LogDir}               % Variables Supported
    {logopts, LogOpts}
    {basic_html, Bool}
    {ct_hooks, CTHs}
    {enable_builtin_hooks, Bool}
",

    #task{name = ?TASK,
          task_impl = ?MODULE,
          bare = false,
          deps = ?DEPS,
          example = "ct",
          short_desc = "Invokes common test on the project",
          desc = Desc,
          opts = []}.

%% @doc Build a dist tarball for this project
-spec do_task(sin_config:matcher(), sin_state:state()) -> sin_state:state().
do_task(Config, State) ->
    Args = Config:match(additional_args),
    case getopt:parse(option_spec_list(), Args) of
        {ok, {Options, []}} ->
            process_spec(Config, State, get_test_name(Config, State, Options)),
            State;
        {error, {Reason, Data}} ->
            io:format("Error: ~s ~p~n~n", [Reason, Data]),
            usage(),
            ?SIN_RAISE(State, {failed_arg_parsing, Reason, Data})
    end.


%% @doc Format an exception thrown by this module
-spec format_exception(sin_exceptions:exception()) ->
    string().
format_exception(Exception) ->
    sin_exceptions:format_exception(Exception).

%%====================================================================
%%% Internal functions
%%====================================================================
create_sgte_env(State) ->
    [{project_dir, sin_state:get_value(project_dir, State)},
     {build_root, sin_state:get_value(build_root, State)},
     {build_dir, sin_state:get_value(build_dir, State)},
     {release_name, sin_state:get_value(release, State)},
     {release_vsn, sin_state:get_value(release_vsn, State)},
     {apps_dir, sin_state:get_value(apps_dir, State)},
     {release_dir, sin_state:get_value(release_dir, State)},
     {home_dir, sin_state:get_value(home_dir, State)}] ++
        lists:flatten(
          [[{erlang:atom_to_list(AppName) ++ "_dir", AppDir},
            {erlang:atom_to_list(AppName) ++  "_vsn", AppVsn}] ||
              #app{name=AppName, vsn=AppVsn, path=AppDir}
                  <- sin_state:get_value(project_apps, State)]).

rewrite_string(Str, Env) ->
    {ok, Compiled} = sgte:compile(Str),
    sgte:render(Compiled, Env).

rewrite_string_or_list(Element=[El | _], Env) ->
    if
        erlang:is_list(El) ->
            [rewrite_string(Str, Env) || Str <- Element];
        erlang:is_integer(El) ->
            rewrite_string(Element, Env)
    end.

rewrite_element({dir, TestDirs}, Env) ->
    {dir, rewrite_string_or_list(TestDirs, Env)};
rewrite_element({config, CfgFiles}, Env) ->
    {config, rewrite_string_or_list(CfgFiles, Env)};
rewrite_element({userconfig, {CallbackMod, CfgStrings}}, Env) ->
    {userconfig, {CallbackMod, rewrite_string_or_list(CfgStrings, Env)}};
rewrite_element({userconfig, UserConfig}, Env) ->
    {userconfig,
     [{CallbackMod, rewrite_string_or_list(CfgStrings, Env)}
      || {CallbackMod, CfgStrings} <- UserConfig]};
rewrite_element({logdir, LogDir}, Env) ->
    {logdir, rewrite_string(LogDir, Env)};
rewrite_element({stylesheet, CssFile}, Env) ->
    {stylesheet, rewrite_string(CssFile, Env)};
rewrite_element({cover, CoverSpecFile}, Env) ->
    {cover, rewrite_string(CoverSpecFile, Env)};
rewrite_element({include, InclDirs}, Env) ->
    {cover, rewrite_string_or_list(InclDirs, Env)};
rewrite_element({decrypt, {file, DecryptFile}}, Env) ->
    {decrypt, {file, rewrite_string(DecryptFile, Env)}};
rewrite_element(El, _) ->
    El.

rewrite_config(State, Config) ->
    Env = create_sgte_env(State),
    [rewrite_element(El, Env) || El <- Config].

should_echo(Options) ->
    case lists:keysearch(echo, 1, Options) of
        false ->
            false;
        {value, {echo, Bool}} ->
            Bool
    end.

write_as_cmd({dir, TestDirs=[El | _]}) ->
    [" -dir ", if
                 erlang:is_list(El) ->
                     [[" ", Dir] || Dir <- TestDirs];
                 erlang:is_integer(El) ->
                     TestDirs
             end];
write_as_cmd({suite, Suites=[El | _]}) ->
    [" -suite ", if
                     erlang:is_list(El) ->
                         [[" ", Suite] || Suite <- Suites];
                     true ->
                         Suites
               end];
write_as_cmd({group, Groups=[El | _]}) ->
    [" -group ", if
                   erlang:is_list(El) ->
                        [[" ", Group] || Group <- Groups];
                    true ->
                        Groups
                end];
write_as_cmd({testcase, Cases=[El | _]}) ->
    [" -case", if
                   erlang:is_list(El) ->
                       [[" ", Case] || Case <- Cases];
                   true ->
                       Cases
               end];
write_as_cmd({spec, TestSpecs=[El | _]}) ->
    [" -spec ", if
                   erlang:is_list(El) ->
                       [[" ", Spec] || Spec <- TestSpecs];
                   true ->
                       TestSpecs
               end];
write_as_cmd({label, Label}) ->
    [" -label ", Label];
write_as_cmd({config, ConfigDirs=[El | _]}) ->
    [" -config ", if
                      erlang:is_list(El) ->
                          [[" ", Config] || Config <- ConfigDirs];
                      true ->
                          ConfigDirs
                  end];
write_as_cmd({userconfig, UserConfigs=[_ | _]}) ->
    [" -userconfig ", [[" ", Cm1, " ", UC] ||
                         {Cm1, UC} <- UserConfigs]];
write_as_cmd({userconfig, {Cm1, UC}}) ->
    [" -userconfig ", Cm1, " ", UC];
write_as_cmd({allow_user_terms, true}) ->
    [" -allow_user_terms "];
write_as_cmd({allow_user_terms, false}) ->
    [];
write_as_cmd({logdir, LogDir}) ->
    [" -logdir ", LogDir];
write_as_cmd({silent_connectios, all}) ->
    [" -silent_connections all "];
write_as_cmd({silent_connections, Els}) ->
    [" -silent_connections ",
     [El || El <- Els]];
write_as_cmd({stylesheet, StyleSheet}) ->
    [" -stylesheet ", StyleSheet];
write_as_cmd({cover, SpecFile}) ->
    [" -cover ", SpecFile];
write_as_cmd({step, StepOpts}) ->
    [" -step ", [[" ", StepOpt] || StepOpt <- StepOpts]];
write_as_cmd({event_handler, EventHandlers}) ->









do_echo(Config) ->
    ok.


process_spec(Config, State, TestSpecName, Options) ->
    try
        Specs = Config:match(ct_config),
        case lists:keysearch(TestSpecName, 1, Specs) of
            false ->
                sin_log:normal(Config,
                               "No ct test spec ~p does not exist.",
                               [TestSpecName]),
                ?SIN_RAISE(State, {spec_does_not_exist, TestSpecName});
            {value, {TestSpecName, TestConfig0}} ->
                TestConfig1 = rewrite_config(State, TestConfig0),
                case should_echo(Options) of
                    true ->
                        do_echo(Config, State, TestConfig1);
                    false ->
                        do_common_test(Config, State, TestConfig1)
                end
        end
    catch
        throw:not_found ->
            sin_log:normal(Config, "No ct test spec ~p does not exist.",
                           [TestSpecName]),
            ?SIN_RAISE(State, {spec_does_not_exist, TestSpecName})
    end.

get_test_name(Config, State, Options) ->
    try
        case lists:keysearch(test, 1, Options) of
            false ->
                Config:match(ct_default);
            {value, {test, Val}} ->
                erlang:list_to_atom(Val)
        end
    catch
        throw:not_found ->
            sin_log:normal(Config, "No ct test spec name specified."),
            ?SIN_RAISE(State, no_spec_name)
    end.


usage() ->
    getopt:usage(option_spec_list(), "", "", []).

-spec option_spec_list() -> list().
option_spec_list() ->
    [{echo, $e, "echo", {boolean, false},
      "Echo the ct_run command to the command line"},
     {test, $t, "test-spec", string, "The name of the test spec to run"}].
