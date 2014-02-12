%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions are met:
%%     %% Redistributions of source code must retain the above copyright
%%       notice, this list of conditions and the following disclaimer.
%%     %% Redistributions in binary form must reproduce the above copyright
%%       notice, this list of conditions and the following disclaimer in the
%%       documentation and/or other materials provided with the distribution.
%%     %% Neither the name of the copyright holders nor the
%%       names of its contributors may be used to endorse or promote products
%%       derived from this software without specific prior written permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ''AS IS''
%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
%% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
%% BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
%% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
%% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
%% BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR 
%% OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF 
%% ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%% ======================================================================
%%
%% Author contact: hl@kent.ac.uk.
%% @private

-module(percept2_report).

-compile(export_all).

-include("../include/percept2.hrl").


%% Calculating the utilisation of each individual scheduler 
%% during profiling.
scheduler_utilisation()->                                  
    Acts = percept2_db:select({scheduler, []}),
    Acc=process_scheduler_data(Acts,[]),
    TotalProfTime = ?seconds((percept2_db:select({system, stop_ts})),
                             (percept2_db:select({system, start_ts}))),
    Result=[{Id, AccActTime/TotalProfTime}|| {Id, _, _, AccActTime}<-Acc],
    [lists:flatten(io_lib:format("Scheduler #~p: ~.2f%\n", [Id, Value*100]))||
        {Id, Value}<-lists:keysort(1, Result)].
   %% output_scheduler_utilisation(lists:keysort(1, Result)).

output_scheduler_utilisation([{Id, Value}|Res]) ->
    output_scheduler_utilisation(Res).

process_scheduler_data([], Acc) ->
    StopTs=percept2_db:select({system, stop_ts}),
    [case LastActTs>LastInActTs of
         true ->
             {SchedId, LastActTs, LastInActTs, 
              ?seconds(StopTs,LastActTs)+AccActTime};
         _ -> A
     end                
     ||A={SchedId, LastActTs, LastInActTs, AccActTime}<-Acc];

process_scheduler_data([{_,Ts, Id, inactive,_}], Acc)->
    [case SchedId of 
         Id -> {Id, LastActTs, Ts, ?seconds(Ts,LastActTs)+AccActTime};
         _  when LastActTs>LastInActTs ->
             {SchedId, Ts, LastInActTs, ?seconds(Ts,LastActTs)+AccActTime};
         _ -> A
     end                
     ||A={SchedId, LastActTs, LastInActTs, AccActTime}<-Acc];
process_scheduler_data([{_,Ts, Id, active,_}|Acts], Acc)->
    NewAcc=case lists:keyfind(Id, 1, Acc) of 
               {Id, _LastActTs, LastInActTs, AccActTime} ->
                   lists:keyreplace(Id, 1, Acc, {Id, Ts, LastInActTs,
                                                 AccActTime});
               false ->
                   [{Id, Ts, percept2_db:select({system, start_ts}), 0}|Acc]
           end,
    process_scheduler_data(Acts, NewAcc);    
process_scheduler_data([{_,Ts, Id, inactive,_}|Acts], Acc)->
    NewAcc=case lists:keyfind(Id, 1, Acc) of 
               {Id, LastActTs, _LastInActTs, AccActTime} ->
                   lists:keyreplace(Id, 1, Acc, {Id, LastActTs, Ts,
                                                 ?seconds(Ts,LastActTs)+AccActTime});
               false ->
                   StartTs=percept2_db:select({system, start_ts}),
                   [{Id, StartTs, Ts, ?seconds(Ts,StartTs)}|Acc]
           end,
    process_scheduler_data(Acts, NewAcc).


%% Calculating the percentage of time when the ration between the number of 
%% runnable processes and the number of avaiable schedulers is 
%% within/below/above the idea ratio.
%% runnable_scheduler_ratio(MinIdealRatio, MaxIdealRation)->
%%     Acts = percept2_db:select({activity, Options}).
 

%% Need to re-write the function to only traverse the list once.
process_report(Key, Num) ->
    ProfileStartTs=percept2_db:select({system, start_ts}),
    ProfileEndTs = percept2_db:select({system, stop_ts}),
    Pos = key_pos_map(Key),
    Procs=case Key of 
              msg_receive_size ->
                  lists:sort(fun(P1, P2) ->
                                     {Cnt1, Size1} =P1#information.msgs_received,
                                     {Cnt2, Size2} =P2#information.msgs_received,
                                     case Cnt1==0 orelse Cnt2==0 of 
                                         true -> false;
                                         false ->(Size1/Cnt1)>=(Size2/Cnt2)
                                     end
                             end, ets:tab2list(pdb_info));
              msg_send_size -> 
                  lists:sort(fun(P1, P2) ->
                                      {Cnt1, Size1} =P1#information.msgs_sent,
                                     {Cnt2, Size2} =P2#information.msgs_sent,
                                     case Cnt1==0 orelse Cnt2==0 of 
                                         true -> false;
                                         false ->(Size1/Cnt1)>=(Size2/Cnt2)
                                     end
                             end, ets:tab2list(pdb_info));
              _ ->lists:reverse(lists:keysort(Pos, ets:tab2list(pdb_info)))
          end,
    Procs1=[P||P<-Procs, is_normal_pid(P#information.id)],
    case lists:member(Key, [running, runnable, block, gc]) of 
        true ->
            [begin
                 LifeTime = process_life_time(Start, End, ProfileStartTs, ProfileEndTs),
                 {Pid,Name,Entry, LifeTime, {RunTime, RunTime/LifeTime}, 
                  {RunnableTime, RunnableTime/LifeTime}, {BlockTime, BlockTime/LifeTime}, 
                  {GC, GC/LifeTime}}
             end
             ||{information, Pid, _Node, Name, Entry,Start, 
                End, _Parent,_Ancestors, _RQ, _Children,
                _MsgRecv, _MsgSend,GC, RunTime, RunnableTime,
                _HiddenPids, _HiddenTrees, BlockTime}
                   <-lists:sublist(Procs1, Num)];
        false  ->
            case lists:member(Key, [msg_receive, msg_receive_size, 
                                    msg_send, msg_send_size]) of 
                true ->
                    [{Pid,Name,Entry, MsgRecv, MsgSend}
                     ||{information, Pid, _Node, Name, Entry, _Start, 
                        _End, _Parent,_Ancestors, _RQ, _Children,
                        MsgRecv, MsgSend, _GC, _RunTime, _RunnableTime,
                        _HiddenPids, _HiddenTrees, _BlockTime}
                           <-lists:sublist(Procs1, Num)];
                false -> []
            end
    end.
            


key_pos_map(running) -> #information.acc_runtime;
key_pos_map(runnable) -> #information.acc_runnable_time;
key_pos_map(block) -> #information.acc_waiting_time;
key_pos_map(gc) -> #information.gc_time;
key_pos_map(msg_receive) -> #information.msgs_received;
key_pos_map(msg_send) -> #information.msgs_sent;
key_pos_map(msg_receive_size) -> #information.msgs_received;
key_pos_map(msg_send_size) -> #information.msgs_sent.


process_life_time(undefined, undefined, ProfileStart, ProfileEnd)->
    timer:now_diff(ProfileEnd, ProfileStart);
process_life_time(undefined, End, ProfileStart, _ProfileEnd) ->
    timer:now_diff(End, ProfileStart);
process_life_time(Start, undefined, _ProfileStart, ProfileEnd) ->
    timer:now_diff(ProfileEnd, Start);
process_life_time(Start, End, _ProfileStart, _ProfileEnd) ->
    timer:now_diff(End, Start).
           
is_normal_pid({pid, {_, P2, _}}) ->
    not is_atom(P2);
is_normal_pid(_) -> false.

    
     
