%% 
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2011. All Rights Reserved.
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


-module(percept2_sampling).

%%-compile(export_all).

-record(run_queue_info,
        {timestamp, 
         run_queue=0}).

-record(run_queues_info,
        {timestamp,
         run_queues}).

-record(scheduler_utilisation_info,
        {timestamp,
         scheduler_utilisation}).
   
-record(process_count_info, {
          timestamp,
          process_count}).

-record(schedulers_online_info, {
          timestamp,
          schedulers_online}).

-record(mem_info, {
          timestamp,  %%timestamp()
          total,      %%integer()
          processes,  %%integer()
          ets,        %%integer()
          atom,       %%integer()
          code,       %%integer()
          binary      %%integer()
         }).
 
-record(message_queue_len_info, {
          timestamp,
          message_queue_len}).

-define(INTERVAL, 100).

-define(seconds(EndTs,StartTs), timer:now_diff(EndTs, StartTs)/1000000).

-type sample_opts():: 'run_queue'|'run_queues'|'scheduler_utilisation'|
                      'process_count'| 'schedulers_online'|'mem_info'|
                      {'message_queue_len', pid()}.
       
-export([sample/2, sample/3, sample/4]).

-export([init/4]).

%%-define(debug, 9).
%%-define(debug, 0). 
-ifdef(debug). 
dbg(Level, F, A) when Level >= ?debug ->
    io:format(F, A),
    ok;
dbg(_, _, _) ->
    ok.
-define(dbg(Level, F, A), dbg((Level), (F), (A))).
-else.
-define(dbg(Level, F, A), ok).
-endif.


sample_opts()->
    ['run_queue','run_queues','scheduler_utilisation',
     'process_count', 'schedulers_online','mem_info',
     'message_queue_len'].

check_sample_opts([{'message_queue_len', _}|Items])->
    check_sample_opts(Items);
check_sample_opts([Item|Items]) ->
    case lists:member(Item, sample_opts()) of
        true ->
            check_sample_opts(Items);
        false ->
            error(lists:flatten(io_lib:format("Invalid option:~p", [Item])))
    end;
check_sample_opts([]) ->
    ok.

sample(Items, ForHowLong) when is_integer(ForHowLong)->
    sample(Items, ForHowLong, ?INTERVAL,
           fun(_) -> true end);
sample(Items, Entry={_Mod, _Fun, _Args}) ->
    sample(Items, Entry, ?INTERVAL, fun()-> true end).
                 
sample(Items, ForHowLong, TimeInterval) when is_integer(ForHowLong)->
    sample(Items, ForHowLong, TimeInterval,fun(_) -> true end);
sample(Items, Entry={_Mod, _Fun, _Args}, TimeInterval) ->
    sample(Items,Entry, TimeInterval, fun(_) ->true end).
   
   
sample(Items, _Entry={Mod, Fun, Args}, TimeInterval, FilterFun) ->
    ok=check_sample_opts(Items),
    create_ets_tables(Items),
    Pid = start_sampling(Items, TimeInterval, FilterFun),
    erlang:apply(Mod, Fun, Args),
    stop_sampling(Pid);
sample(Items, ForHowLong, TimeInterval, FilterFun) 
  when is_integer(ForHowLong)->
    ok=check_sample_opts(Items),
    create_ets_tables(Items),
    try 
        Pid=start_sampling(Items, TimeInterval, FilterFun),
        erlang:start_timer(ForHowLong, Pid, stop)
    catch
        throw:Term -> Term;
        exit:Reason -> {'EXIT',Reason};
        error:Reason -> {'EXIT',{Reason,erlang:get_stacktrace()}}
    end.

start_sampling(Items, TimeInterval, FilterFun) ->
    case lists:member('scheduler_utilisation', Items) of 
        true ->
            erlang:system_flag(scheduler_wall_time, true);
        _ -> ok
    end,
    spawn_link(?MODULE, init, [now(), Items, TimeInterval, FilterFun]).
   
stop_sampling(Pid) ->
    Pid!stop.

init(StartTs, Items, Interval, FilterFun) ->
    sampling_loop(StartTs, Interval, Items, FilterFun).
  
sampling_loop(StartTs, Interval, Items, FilterFun) ->
    receive
        stop -> 
            write_data(Items);
        {timeout, _TimerRef, stop} -> 
            write_data(Items)
    after Interval->
            do_sampling(Items,StartTs),
            sampling_loop(StartTs, Interval, Items, FilterFun)
    end.

do_sampling([{Item, Args}|Items],StartTs) ->
    do_sample({Item, Args},StartTs),
    do_sampling(Items,StartTs);
do_sampling([Item|Items],StartTs) ->
    do_sample(Item, StartTs),
    do_sampling(Items,StartTs);
do_sampling([],_) -> ok.
   
mk_ets_tab_name(Item)->
    list_to_atom(atom_to_list(Item)++"_tab").
mk_file_name(Item) ->
    "sample_"++atom_to_list(Item)++".dat".

create_ets_tables([{Item, _}|Items]) ->
    TabName = mk_ets_tab_name(Item),
    ets:new(TabName, [named_table, ordered_set, public, {keypos, 2}]),
    create_ets_tables(Items);
create_ets_tables([Item|Items]) ->
    TabName = mk_ets_tab_name(Item),
    ets:new(TabName, [named_table, ordered_set, public, {keypos, 2}]),
    create_ets_tables(Items);
create_ets_tables([]) ->
    ok.

do_sample(mem_info, StartTs) ->
    [{total, Total}, {processes, Processes}, {ets, ETS},
     {atom, Atom}, {code, Code}, {binary, Binary}] =
        erlang:memory([total, processes, ets, atom, code, binary]),
    Info=#mem_info{timestamp=?seconds(now(), StartTs),
                   total=to_megabytes(Total),
                   processes=to_megabytes(Processes),
                   ets=to_megabytes(ETS),
                   atom=to_megabytes(Atom),
                   code=to_megabytes(Code),
                   binary=to_megabytes(Binary)},
    ?dbg(0, "MemInfo:\n~p\n", [Info]),
    ets:insert(mk_ets_tab_name(mem_info), Info);
do_sample(run_queue, StartTs) ->
    RunQueue= erlang:statistics(run_queue),
    Info=#run_queue_info{timestamp=?seconds(now(), StartTs),
                         run_queue = RunQueue},
    ?dbg(0, "RunQueue:\n~p\n", [Info]),
    ets:insert(mk_ets_tab_name(run_queue), Info);
do_sample(run_queues,StartTs) ->
    RunQueues= erlang:statistics(run_queues),
    Info=#run_queues_info{timestamp=?seconds(now(), StartTs),
                         run_queues = RunQueues},
    ?dbg(0, "RunQueues:\n~p\n", [Info]),
    ets:insert(mk_ets_tab_name(run_queues), Info);
do_sample(scheduler_utilisation,StartTs) ->
    SchedulerWallTime=erlang:statistics(scheduler_wall_time),
    Info=#scheduler_utilisation_info{timestamp=?seconds(now(), StartTs),
                                     scheduler_utilisation = lists:usort(SchedulerWallTime)},
    ?dbg(0, "Scheduler walltime:\n~p\n", [Info]),
    ets:insert(mk_ets_tab_name(scheduler_utilisation), Info);
do_sample(schedulers_online,StartTs)->
    SchedulersOnline = erlang:system_info(schedulers_online),
    Info=#schedulers_online_info{timestamp=?seconds(now(), StartTs),
                                         schedulers_online = SchedulersOnline},
    ?dbg(0, "Schedulers online:\n~p\n", [Info]),
    ets:insert(mk_ets_tab_name(schedulers_online), Info);
do_sample(process_count, StartTs) ->
    ProcessCount = erlang:system_info(process_count),
    Info=#process_count_info{timestamp=?seconds(now(), StartTs),
                             process_count = ProcessCount},
    ?dbg(0, "Process count:\n~p\n", [Info]),
    ets:insert(mk_ets_tab_name(process_count), Info);
do_sample({message_queue_len,Pid},StartTs) ->
    [{message_queue_len, MsgQueueLen}] = erlang:process_info(Pid, [message_queue_len]),
    Info = #message_queue_len_info{timestamp=?seconds(now(), StartTs),
                                   message_queue_len = MsgQueueLen
                                  },
    ?dbg(0, "Message queue length:\n~p\n", [Info]),
    ets:insert(mk_ets_tab_name(message_queue_len), Info).

do_write_sample_info(Item) ->
    {ok, FD} = file:open(mk_file_name(Item), [write]),
    Tab = mk_ets_tab_name(Item),
    String=read_data_from_tab(Item),
    ok=file:write(FD, String),
    true = ets:delete(Tab),
    ok = file:close(FD).
read_data_from_tab(mem_info) ->
    Tab = mk_ets_tab_name(mem_info),
    lists:flatten(ets:foldr(fun(_Data={_, Secs, Total, Procs, ETS, Atom, Code, Binary}, Acc) ->
                      [io_lib:format("~p  ~p  ~p   ~p  ~p  ~p ~p \n",
                                     [Secs, Total, Procs, ETS, Atom, Code, Binary])|Acc]
              end,[],Tab));
read_data_from_tab(run_queue) ->
    Tab = mk_ets_tab_name(run_queue),
    lists:flatten(ets:foldr(fun(_Data={_, Secs, RunQueue}, Acc) ->
                             [io_lib:format("~p  ~p \n",
                                            [Secs,RunQueue])|Acc]
                     end, [], Tab));
read_data_from_tab(run_queues) ->
    Tab = mk_ets_tab_name(run_queues),
    lists:flatten(ets:foldr(fun(_Data={_, Secs, RunQueues}, Acc) ->
                                    {_, RunQueues1} = lists:foldl(
                                                   fun(Len, {Sum, RQAcc}) ->
                                                           {Len+Sum,[Len+Sum|RQAcc]}
                                                   end, {0, []}, tuple_to_list(RunQueues)),
                                    Str=lists:flatten([" "++integer_to_list(Len)++" "
                                                       ||Len<-RunQueues1]),
                                    [io_lib:format("~p  ~s \n",
                                                   [Secs,Str])|Acc]
                            end,[], Tab));
read_data_from_tab(scheduler_utilisation) ->
    Tab = mk_ets_tab_name(scheduler_utilisation),
    {_, Acc1}=ets:foldr(fun(_Data={_, Secs, SchedulerWallTime1}, {SchedulerWallTime0, Acc}) ->
                                case SchedulerWallTime0 of 
                                    none ->
                                        {SchedulerWallTime1, Acc};
                                    _ ->
                                        SchedUtilisation=[(A1 - A0)/(T1 - T0)||
                                                             {{I, A0, T0}, {I, A1, T1}}<-lists:zip(SchedulerWallTime0,
                                                                                                   SchedulerWallTime1)],
                                        {_, SchedUtilisation1} = lists:foldl(
                                                            fun(Util, {Sum, UtilAcc}) ->
                                                                    {Util+Sum,[Util+Sum|UtilAcc]}
                                                            end, {0, []}, SchedUtilisation),
                                        Str=[io_lib:format(" ~p", [Val])
                                             ||Val<-SchedUtilisation1],
                                        {SchedulerWallTime1,[io_lib:format("~p ",[Secs]), Str++"\n"|Acc]}
                                end
                        end,{none, []}, Tab),
    lists:flatten(Acc1);
read_data_from_tab(process_count) ->
    Tab = mk_ets_tab_name(process_count),
    lists:flatten(ets:foldr(fun(_Data={_, Secs, ProcsCount}, Acc) ->
                             [io_lib:format("~p  ~p \n",
                                            [Secs,ProcsCount])|Acc]
                     end,[], Tab));
read_data_from_tab(schedulers_online) ->
    Tab = mk_ets_tab_name(schedulers_online),
    lists:flatten(ets:foldr(fun(_Data={_, Secs, ProcsCount}, Acc) ->
                      [io_lib:format("~p  ~p \n",
                                     [Secs,ProcsCount])|Acc]
              end,[], Tab));
read_data_from_tab(message_queue_len) ->
    Tab = mk_ets_tab_name(message_queue_len),
    lists:flatten(ets:foldr(fun(_Data={_, Secs, MsgQueueLen}, Acc) ->
                                    [io_lib:format("~p  ~p \n",
                                                   [Secs, MsgQueueLen])|Acc]
                            end,[], Tab)).

write_data([{Item, _Args}|Items]) ->
    do_write_sample_info(Item),
    write_data(Items);
write_data([Item|Items]) ->
    do_write_sample_info(Item),
    write_data(Items);
write_data([]) ->
    ok.

to_megabytes(Bytes) ->
    Bytes/1000000.

 %% percept_sampling:start(none, {refac_sim_code_par_v0,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"],8]},1000, [all]).
%% > erlang:system_flag(scheduler_wall_time, true).
%% false
%% > Ts0 = lists:sort(erlang:statistics(scheduler_wall_time)), ok.
%% ok
%% > Ts1 = lists:sort(erlang:statistics(scheduler_wall_time)), ok.
%% ok
%% > lists:map(fun({{I, A0, T0}, {I, A1, T1}}) ->
%% 	{I, (A1 - A0)/(T1 - T0)} end, lists:zip(Ts0,Ts1)).
%% [{1,0.9743474730177548},
%%  {2,0.9744843782751444},
%%  {3,0.9995902361669045},
%%  {4,0.9738012596572161},
%%  {5,0.9717956667018103},
%%  {6,0.9739235846420741},
%%  {7,0.973237033077876},
%%  {8,0.9741297293248656}]

%% > {A, T} = lists:foldl(fun({{_, A0, T0}, {_, A1, T1}}, {Ai,Ti}) ->
%% 	{Ai + (A1 - A0), Ti + (T1 - T0)} end, {0, 0}, lists:zip(Ts0,Ts1)), A/T.
%% 0.9769136803764825


%% percept_sampling:sample( ['run_queue','run_queues','scheduler_utilisation',
%%                           'process_count', 'schedulers_online','mem_info'],
%%      {refac_sim_code_par_v0,sim_code_detection, [["c:/cygwin/home/hl/test"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/test"],8]}).
