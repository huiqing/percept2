-module(percept2_multi_node_trace). 

-compile(export_all).

-include("../include/percept2.hrl").

-spec(start([node()]) -> ok).
start(Nodes) ->
    _Res=ttb:tracer(Nodes),
    _Res1=ttb:p(all, [send, 'receive']), 
    ok.

stop()->
    ttb:stop().
   


%% command to run the orbit-int benchmark and trace message sending.
run_orbit_with_trace() ->
    Nodes = ['node1@127.0.0.1', 'node2@127.0.0.1', 'node3@127.0.0.1',
             'node4@127.0.0.1', 'node5@127.0.0.1', 'node6@127.0.0.1',
             'node7@127.0.0.1', 'node8@127.0.0.1', 'node9@127.0.0.1',
             'node10@127.0.0.1', 'node11@127.0.0.1', 'node12@127.0.0.1'],
    _Res = ttb:tracer(Nodes),
    _Res1=ttb:p(all, [send]),
    bench:dist_seq(fun bench:g124/1, 1000000, 8,
                   Nodes),
    ttb:stop().


analyze_orbit_data() ->
    Files = ["node1@127.0.0.1-ttb","node2@127.0.0.1-ttb",
             "node3@127.0.0.1-ttb","node4@127.0.0.1-ttb",
             "node5@127.0.0.1-ttb","node6@127.0.0.1-ttb",
             "node7@127.0.0.1-ttb","node8@127.0.0.1-ttb",
             "node9@127.0.0.1-ttb","node10@127.0.0.1-ttb",
             "node10@127.0.0.1-ttb","node12@127.0.0.1-ttb"],
    percept2:analyze(Files).
    
%% timestamped event data.
process_orbit_data()->
    {{Meg, Sec, Mic},_,_} = ets:first(inter_proc),
    StartTs = {Meg, Sec, Mic-1},
    Data = [io_lib:format("~p.\n", [{round(now_diff(Ts, StartTs)/1000), 
                                    short_node_name(From), 
                                    short_node_name(To), Size}])
            ||{_, {Ts, From,_},{To,_},Size}<-ets:tab2list(inter_proc),
              From /= nonode, To/=nonode],
    Str = lists:flatten(Data),
    file:write_file("inter_node.txt", list_to_binary(Str)).          

process_orbit_data_sum()->
    {{Meg, Sec, Mic},_,_} = ets:first(inter_proc),
    StartTs = {Meg, Sec, Mic-1},
    Data = [{round(now_diff(Ts, StartTs)/1000), 
             short_node_name(From), 
             short_node_name(To), Size}||
               {_, {Ts, From,_},{To,_},Size}
                   <-ets:tab2list(inter_proc), 
               From/=nonode,
               To/=nonode],
    Data1=process_orbit_data_sum_1(Data, 0, [], []),
    Str=lists:flatten([io_lib:format("~p.\n", [E])||E<-Data1]),
    file:write_file("inter_node_sum.txt", list_to_binary(Str)).
    
    
%% summary data every 200 millisecods.    
process_orbit_data_sum_1([],StartTime, Cur, Acc) ->
    lists:reverse([{StartTime+200, Cur}|Acc]);
process_orbit_data_sum_1([{Time, From, To, MsgSize}|Data], 
                         StartTime, Cur, Acc) ->
    NextStartTime = StartTime +200,
    {Node1, Node2} =if From < To -> {From, To};
                       true -> {To, From}
                    end,
    if Time=< NextStartTime ->
            NewCur=case lists:keyfind({Node1, Node2}, 1, Cur) of 
                       {{Node1, Node2}, Cnt, SumSize} -> 
                           lists:keyreplace({Node1, Node2}, 1, Cur, 
                                            {{Node1, Node2}, Cnt+1, 
                                             MsgSize+SumSize});
                       false ->
                           [{{Node1,Node2}, 1, MsgSize}|Cur]
                   end,
            process_orbit_data_sum_1(Data, StartTime, NewCur, Acc);
       true ->
            process_orbit_data_sum_1(Data, NextStartTime, 
                                     [{{Node1, Node2}, 1, MsgSize}], 
                                     [{NextStartTime,Cur}|Acc])
    end.

  
now_diff(EndTS,StartTS) ->
    try timer:now_diff(EndTS, StartTS)
    catch _E1:_E2 -> 0
    end.
   

short_node_name(NodeName) ->
    Str = atom_to_list(NodeName),
    Index = string:chr(Str, $@),
    if Index ==0 ->
            NodeName;
       true -> list_to_atom(string:substr(Str,1, Index-1))
    end.

%% c("../../git_repos/percept2/src/percept2_multi_node_trace.erl").
