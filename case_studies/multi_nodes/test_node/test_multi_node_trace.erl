-module(test_multi_node_trace).

-compile(export_all).

start() ->
    multi_node_trace:start(['server@hl-lt', 'client@hl-lt']).

stop() ->
    multi_node_trace:stop().
