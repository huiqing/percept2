%% 
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 2007-2009. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%

%% @doc Interface for CGI request on graphs used by percept. The module exports two functions that 
%%are implementations for ESI callbacks used by the httpd server. 
%%See http://www.erlang.org//doc/apps/inets/index.html.

-module(percept2_smell_detection).

-compile(export_all).

-include("../include/percept2.hrl").

-spec large_process_entry_args(non_neg_integer())->[#information{}].
large_process_entry_args(Threshold) ->
    ets:select(pdb_info, 
               [{#information{entry={'$1', '$2', '$3'}, _ = '_'},
                 [{is_list, '$3'}, {'>', {size, '$3'} , Threshold}],
                 ['$_']}]).


large_messages(Threshold) ->
    ets:select(inter_proc,
               [{#inter_proc{msg_size='$1', _='_'},
                 [{'>', '$1' , Threshold}],
                 ['$_']}]).


very_short_lived_procs(Threshold) ->
    Procs=ets:select(pdb_info, [{#information{id='$0', entry='$1', start='$2', stop='$3', _='_'},
                                 [{'=/=', '$2', undefined}, {'=/=', '$3', undefined}],
                                 [{{'$0', '$1', '$2', '$3'}}]}]),
    [{Pid, Entry, StartTs, StopTs}||{Pid, Entry, StartTs, StopTs}<-Procs, 
                             timer:now_diff(StopTs,StartTs)=<Threshold].

unfinished_procs() ->
    ets:select(pdb_info, [{#information{id='$0', entry='$1', start='$2', stop='$3', _='_'},
                           [{'=/=', '$2', undefined}, {'==', '$3', undefined}],
                           [{{'$0', '$1', '$2', '$3'}}]}]).


over_parallel(Threshold) ->
    StartTs  = percept2_db:select({system, start_ts}),
    StopTs = percept2_db:select({system, stop_ts}),
    %% This needs to be fixed. What about if profiling was done
    %% on another machine with different number of cores?
    ProfileTime =timer:now_diff(StopTs, StartTs),
    Schedulers = erlang:system_info(schedulers),
    RatioList=[{Ts,Procs/Schedulers}||
              {Ts, {Procs, _}}
                  <-percept2_db:select(
                      {activity,{runnable_counts, [{id, procs}]}})],
    
    AboveRatioTime = calc_above_ratio(RatioList, Threshold, {StartTs, StopTs}, 0),
    AboveRatioTime/ProfileTime.

calc_above_ratio([], _Threshold, {_StartTs, _StopTs}, Acc) ->
    Acc;
calc_above_ratio([{Ts, Ratio}], Threshold, {_StartTs, StopTs}, Acc) 
  when  Ratio>=Threshold ->
     timer:now_diff(StopTs, Ts)+Acc;
calc_above_ratio([{_Ts, _Ratio}], _Threshold, {_StartTs, _StopTs}, Acc)-> 
    Acc;
calc_above_ratio([{_Ts1, Ratio1}, {Ts2, Ratio2}|Tail], Threshold, StarStopTs, Acc)
  when Ratio1<Threshold andalso  Ratio2<Threshold->
    calc_above_ratio([{Ts2, Ratio2}|Tail], Threshold, StarStopTs, Acc);
calc_above_ratio([{Ts1, Ratio1}, {Ts2, Ratio2}|Tail], Threshold, StarStopTs, Acc)
  when Ratio1<Threshold andalso  Ratio2>=Threshold->
    calc_above_ratio([{Ts2, Ratio2}|Tail], Threshold, StarStopTs, 
                     timer:now_diff(Ts2, Ts1) / 2 + Acc);
calc_above_ratio([{Ts1, Ratio1}, {Ts2, Ratio2}|Tail], Threshold, StarStopTs, Acc)
  when Ratio1>=Threshold andalso Ratio2>=Threshold ->
       calc_above_ratio([{Ts2, Ratio2}|Tail], Threshold, StarStopTs,
                        timer:now_diff(Ts2, Ts1) + Acc);
calc_above_ratio([{Ts1, Ratio1}, {Ts2, Ratio2}|Tail], Threshold, StarStopTs,  Acc)
  when Ratio1>=Threshold andalso Ratio2<Threshold ->
       calc_above_ratio([{Ts2, Ratio2}|Tail], Threshold, StarStopTs, 
                        timer:now_diff(Ts2, Ts1) / 2 + Acc).

   
under_parallel(Threshold) ->
    StartTs  = percept2_db:select({system, start_ts}),
    StopTs = percept2_db:select({system, stop_ts}),
    %% This needs to be fixed. What about if profiling was done
    %% on another machine with different number of cores?
    ProfileTime =timer:now_diff(StopTs, StartTs),
    Schedulers = erlang:system_info(schedulers),
    RatioList=[{TS,Procs/Schedulers}||
              {TS, {Procs, _}}
                  <-percept2_db:select(
                      {activity,{runnable_counts, [{id, procs}]}})],
    
    UnderRatioTime = calc_under_ratio(RatioList, Threshold, {StartTs, StopTs},0),
    UnderRatioTime/ProfileTime.
     
calc_under_ratio([], _Threshold, {_StartTs, _StopTs}, Acc) ->
    Acc;
calc_under_ratio([{Ts, Ratio}], Threshold, {_StartTs, StopTs}, Acc) 
  when Ratio=<Threshold ->
     timer:now_diff(StopTs, Ts)+Acc;
calc_under_ratio([{_Ts, _Ratio}], _Threshold, {_StartTs, _StopTs}, Acc)-> 
    Acc;
calc_under_ratio([{Ts1, Ratio1}, {Ts2, Ratio2}|Tail], Threshold, StarStopTs, Acc)
  when Ratio1<Threshold andalso  Ratio2<Threshold->
    calc_under_ratio([{Ts2, Ratio2}|Tail], Threshold, StarStopTs,  timer:now_diff(Ts2, Ts1)+Acc);
calc_under_ratio([{Ts1, Ratio1}, {Ts2, Ratio2}|Tail], Threshold, StarStopTs, Acc)
  when Ratio1<Threshold andalso  Ratio2>=Threshold->
    calc_under_ratio([{Ts2, Ratio2}|Tail], Threshold, StarStopTs, 
                     timer:now_diff(Ts2, Ts1) / 2 + Acc);
calc_under_ratio([{_Ts1, Ratio1}, {Ts2, Ratio2}|Tail], Threshold, StarStopTs, Acc)
  when Ratio1>=Threshold andalso Ratio2>=Threshold ->
       calc_under_ratio([{Ts2, Ratio2}|Tail], Threshold, StarStopTs,Acc);
calc_under_ratio([{Ts1, Ratio1}, {Ts2, Ratio2}|Tail], Threshold, StarStopTs,  Acc)
  when Ratio1>=Threshold andalso Ratio2<Threshold ->
       calc_under_ratio([{Ts2, Ratio2}|Tail], Threshold, StarStopTs, 
                        timer:now_diff(Ts2, Ts1) / 2 + Acc).


scheduler_utilisation() ->
    StartTs  = percept2_db:select({system, start_ts}),
    StopTs = percept2_db:select({system, stop_ts}),
    %% This needs to be fixed. What about if profiling was done
    %% on another machine with different number of cores?
    ProfileTime =timer:now_diff(StopTs, StartTs),
    Schedulers = erlang:system_info(schedulers),
    Acts = percept2_db:select({scheduler, []}),
    Acc=process_sched_acts(Acts, []),
    Times=[Time||{{_Id, accu_time}, Time}<-Acc],
    lists:sum(Times)/(Schedulers*ProfileTime).

process_sched_acts([], Acc) ->
    Acc;
process_sched_acts([{scheduler, Ts, Id, active,_}|Tail], Acc) ->
    Key = {Id, active_start},
    Acc1=lists:keystore({Id, active_start},1, Acc, {Key, Ts}),
    process_sched_acts(Tail, Acc1);
process_sched_acts([{scheduler, Ts, Id, inactive,_}|Tail], Acc) ->
    Key = {Id, active_start},
    case lists:keyfind(Key, 1, Acc) of 
        {Key, StartTs} ->
            Time = timer:now_diff(Ts, StartTs),
            Key1 = {Id, accu_time},
            Acc1=case lists:keyfind(Key1,1,Acc) of
                     {Key1, AccTime} ->
                         lists:keystore(Key1, 1, Acc, {Key1, AccTime+Time});
                     false ->
                         lists:keystore(Key1, 1, Acc, {Key1, Time})
                 end,
            process_sched_acts(Tail, Acc1);
        false ->
            process_sched_acts(Tail, Acc)
    end.
                       


para_cands()->
    %% StartTs  = percept2_db:select({system, start_ts}),
    %% StopTs = percept2_db:select({system, stop_ts}),
    %% %% This needs to be fixed. What about if profiling was done
    %% %% on another machine with different number of cores?
    %% ProfileTime =timer:now_diff(StopTs, StartTs),
    Schedulers = erlang:system_info(schedulers),
    Acts = percept2_db:select({scheduler, []}),
    Res=find_half_idle_intervals(Acts, round(Schedulers/2)),
    find_heavy_loaded_procs(lists:sublist(Res, 1)).

find_heavy_loaded_procs(TimeIntervals) ->    
    Res=[{StartTs, EndTs, find_heavy_loaded_procs_1(StartTs, EndTs)}||
            {StartTs, EndTs, _}<-TimeIntervals],
    [{Start, End, Pid, Time, get_active_funs(Pid, Start, End)}
     ||{Start, End, [{Pid, Time, _}]}<-Res].
    
find_heavy_loaded_procs_1(StartTs, EndTs) ->
    Acts=percept2_db:select({activity,[{ts_min, StartTs}, 
                                       {ts_max, EndTs}]}),
    find_heavy_loaded_procs_2(Acts,[]).
    
find_heavy_loaded_procs_2([], Acc) ->
    case lists:reverse(lists:keysort(2, Acc)) of 
        [] -> [];
        [Hd|_] -> [Hd]
    end;
find_heavy_loaded_procs_2(
  [A={activity, Ts, Pid, active, _Where, _Proc, _Ports, _InOuts}|Acts], Acc) when 
      not is_port(Pid) ->
    case lists:keyfind(Pid, 1, Acc) of 
        false ->
            Acc1=lists:keystore(Pid, 1, Acc, {Pid, 0, {active_start, Ts}}),
            find_heavy_loaded_procs_2(Acts, Acc1);
        {Pid,_AccTime, {active_start, Ts1}} ->
            find_heavy_loaded_procs_2(Acts, Acc);
        {Pid,AccTime, {inactive_start, Ts1}} ->
            Acc1 = lists:keystore(Pid, 1, Acc, {Pid, AccTime, {active_start, Ts}}),
            find_heavy_loaded_procs_2(Acts, Acc1)
    end;
find_heavy_loaded_procs_2(
  [A={activity, Ts, Pid, inactive, _Where, _Proc, _Ports, _InOuts}|Acts], Acc) when 
      not is_port(Pid) ->
    case lists:keyfind(Pid, 1, Acc) of 
        false ->
            Acc1=lists:keystore(Pid, 1, Acc, {Pid, 0, {inactive_start, Ts}}),
            find_heavy_loaded_procs_2(Acts, Acc1);
        {Pid,AccTime, {active_start, Ts1}} ->
            Time = timer:now_diff(Ts, Ts1),
            Acc1 = lists:keystore(Pid, 1, Acc, {Pid, AccTime+Time, {inactive_start, Ts}}),
            find_heavy_loaded_procs_2(Acts, Acc1);
        {Pid,_AccTime, _} ->
            find_heavy_loaded_procs_2(Acts, Acc)
    end;
find_heavy_loaded_procs_2([_A|Acts], Acc) ->
    find_heavy_loaded_procs_2(Acts, Acc).


find_half_idle_intervals(Acts, Scheds) ->
    Res=find_half_idle_intervals(Acts, Scheds, [], []),
    lists:reverse(lists:keysort(3, Res)).

find_half_idle_intervals([], _Scheds, [], Acc) ->
    lists:reverse(Acc);
find_half_idle_intervals([], _Scheds, Cur, Acc) ->
    [T1, T2] = Cur,
    TimeLength=timer:now_diff(T1, T2),
    lists:reverse([{T1, T2, TimeLength}|Acc]);
find_half_idle_intervals([{scheduler, Ts, _Id, _State, ActiveScheds}|Tail], 
                         Scheds, Cur,  Acc)    
  when ActiveScheds>Scheds ->
   case Cur of 
       [] ->
           find_half_idle_intervals(Tail,Scheds, [], Acc);  
       [T] -> 
           TimeLength=timer:now_diff(Ts, T),
           find_half_idle_intervals(Tail,Scheds, [], [{T, Ts,TimeLength}|Acc]);
       [_T1, T2]->
           TimeLength=timer:now_diff(Ts, T2),
           find_half_idle_intervals(Tail,Scheds, [], [{T2, Ts,TimeLength}|Acc])
   end;
find_half_idle_intervals([{scheduler, Ts, _Id, _State, ActiveScheds}|Tail], 
                         Scheds, Cur,  Acc) when  ActiveScheds=<Scheds ->
    Cur1 = case Cur of 
               [] -> [Ts];
               [T] -> [Ts, T];
               [_T1, T2] -> [Ts, T2]
           end,
    find_half_idle_intervals(Tail,Scheds, Cur1,Acc).

    
get_active_funs(Pid, StartTs, EndTs) ->
   ActiveFuns = percept2_db:select({code,[{ts_min, StartTs}, {ts_max, EndTs}
                                          ,{pids, [Pid]}]}),
   ActiveFuns.
    
   




    

    
    


%% max_message_queue_len() ->
%%     0.

%% message_leak() ->
%%     %% how to detect this? how do you know if 
%%     %% the message queue lenght eventualy reduce to 0 or not?


    
