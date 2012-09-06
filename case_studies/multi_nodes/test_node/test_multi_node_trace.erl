-module(test_multi_node_trace).

-compile(export_all).

start() ->
    multi_node_trace:start([{'server@hl-lt', "server_trace_log.dat"},
                            {'client@hl-lt', "client_trace_log.dat"}]).
