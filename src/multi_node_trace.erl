-module(multi_node_trace). 

-compile(export_all).

-spec(start([{node(), file:filename()}]) -> ok).
start(NodeTraceFilePairs) ->
    {Nodes, _Files} = lists:unzip(NodeTraceFilePairs),
    erlang:set_cookie(node(), secret),
    application:start(runtime_tools),
    {ok, Pid} = inviso:start(),
    io:format("Starting inviso ok: ~p~n", [Pid]),
    {ok, Result1} = inviso:add_nodes(Nodes, mytag),
    io:format("Adding nodes ok: ~p~n", [Result1]),
    InitTraceSetting = [{Node, [{trace, {file, TraceFile}}]}||
                        {Node, TraceFile}<-NodeTraceFilePairs],
    {ok, Result2} = inviso:init_tracing(InitTraceSetting),
    io:format("Initiate tracing ok:~p~n", [Result2]),
    {ok, Result3}=inviso:tf(Nodes, all, [send, 'receive']),
    io:format("Setting tracing flags ok:~p~n", [Result3]),
    {ok, Result4}=inviso:tf(all, [timestamp]),
    io:format("Setting tracing flags ok:~p~n", [Result4]),
    ok.

stop()->
    inviso:stop_tracing(),
    inviso:stop().
    
