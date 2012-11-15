-module(multi_node_trace). 

-compile(export_all).

-spec(start([node()]) -> ok).
start(Nodes) ->
    _Res=ttb:tracer(Nodes),
    _Res1=ttb:p(all, [send, 'receive']), 
    ok.

stop()->
    ttb:stop().
   
