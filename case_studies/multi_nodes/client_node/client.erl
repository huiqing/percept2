-module(client).

-compile(export_all).

init() -> init(server_node()).
init(Node) ->
    application:start(runtime_tools),
    net_kernel:connect_node(Node).
server_node() ->
    {ok,HostName} = inet:gethostname(),
    list_to_atom("server@" ++ HostName).
get_from_server() ->
    erlang:send({server,server_node()}, {get,self()}),
    receive {ok,Data} -> {ok,Data}
    after 1000   -> no_reply
    end.
put_to_server(Ting) ->
    erlang:send({server,server_node()}, {put,self(),Ting}),
    receive 
        Res-> Res
    after 1000 -> no_reply
    end.

test(InputFile) ->
    init(),
    case file:open(InputFile, [read]) of 
        {error, Reason} ->
            error(Reason);
        {ok, FD} ->
            test_loop(FD, 0)
    end.

test_loop(FD, Count) ->
    case Count rem 100 of 
        0 ->
            get_from_server();
        _ ->
            ok
    end,
    case file:read_line(FD) of 
        {ok, Data} ->
            put_to_server(Data),
            test_loop(FD, Count+1);
        _ ->
            io:format("Done. ~p lines read\n", [Count])
    end.
            
