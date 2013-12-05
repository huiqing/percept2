-module(percept2_orbit). 

-compile(export_all).
 
%%command to run the the sd-orbit benchmark and trace message sending.
run_orbit_with_trace(N) ->
    Nodes=[list_to_atom("node"++integer_to_list(I)++"@127.0.0.1")
           ||I<-lists:seq(1,N)],
    percept2_dist:start(Nodes, {init_bench, main, [Nodes]}, new, [send], []).

analyze_orbit_data(N) ->
    Files=[list_to_atom("node"++integer_to_list(I)++"@127.0.0.1-ttb")
           ||I<-lists:seq(1,N)],
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


%% How to use: 
%% N: number of nodes.
%% Please modify the functions run_orbit_with_trace and 
%% run_oribit_with_trace if the nodes are named in 
%% a different way.

%% To profile:
%% In an Erlang node, run the command:
%% percept2_multi_node_trace:run_orbit_with_trace(N).

%% after profile.
%% In the same Erlang node:
%% 1) go to the directory which contains the trace data.
%% 2)run the command:
%%   percept2_multi_node_trace:analyze_orbit_data(N).

%% To see the profiling data:
%% 1)in the Erlang node, run the command:  percept2:start_webserver(8080).
%% 2)goto page localhost:8080.
%% 3)goto the 'processes' page to see the send/receive data.

