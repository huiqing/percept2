-module(multi_node_trace). 

-compile(export_all).

start(NodeTraceFilePairs) ->
    {Nodes, _Files} = lists:unzip(NodeTraceFilePairs),
    erlang:set_cookie(node(), secret),
    application:start(runtime_tools),
    {ok, Pid} = inviso:start(),
    io:format("Pid:\n~p\n", [Pid]),
    {ok, Res1} = inviso:add_nodes(Nodes, mytag),
    io:format("Res1:\n~p\n", [Res1]),
    InitTraceSetting = [{Node, [{trace, {file, TraceFile}}]}||
                        {Node, TraceFile}<-NodeTraceFilePairs],
    {ok, Res2} = inviso:init_tracing(InitTraceSetting),
    io:format("Res2:\n~p\n", [Res2]),
    {ok, Res3}=inviso:tf(Nodes, all, [send, 'receive']),
    io:format("Res3:\n~p\n", [Res3]),
    {ok, Res4}=inviso:tf(all, [timestamp]),
    io:format("Res4:\n~p\n", [Res4]),
    ok.

 
stop()->
    inviso:stop_tracing(),
    inviso:stop().
    
%% fetch_logs(Nodes) ->
%%     [inviso:fetch_log(Node, ".", "")
%%      ||Node<-Nodes].


%% test_inviso_percept:start([{'server@hl-lt', "server_trace_log.dat"}, {'client@hl-lt', "client_trace_log.dat"}]).
