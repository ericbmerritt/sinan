%% -*- mode: Erlang; fill-column: 75; comment-column: 50; -*-

{application, sinan,
 [{description, "Build system for erlang"},
  {vsn, "4.1.1"},
  {modules, []},
  {registered, [sin_sup]},
  {applications, [kernel, stdlib, compiler, erlware_commons,
                  edoc, syntax_tools, eunit, proper, tools,
                  xmerl, mnesia, erlware_commons,
                  cucumberl, joxa,
                  parsetools, getopt]}]}.
