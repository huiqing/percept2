%% Copyright (c) 2012, Huiqing Li
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

%%@author  Huiqing Li <H.Li@kent.ac.uk>
%%
%%@doc 
%% This module provides a collection of functions for reporting information 
%% regarding memory usage, garbage collection, scheduler utilization, and 
%% message/run queue length, etc. This is done by sampling-based profiling, i.e.
%% the profiler probes the running Erlang system at regular intervals. Sampling
%% profiling is typically less numerically accurate and specific, but has less 
%% impact on the system. Data collected by the profiler are stored in files, 
%% and the Gnuplot tool can be used for graph visualisation of the data. 
%%
%% The following Erlang functions are used for the purpose of data collection
%% <a href="http://www.erlang.org/doc/man/erlang.html#statistics-1">erlang:statistics/1</a>, 
%% <a href="http://www.erlang.org/doc/man/erlang.html#memory-1">erlang:memory/1</a>,
%% <a href="http://www.erlang.org/doc/man/erlang.html#system_info-1">erlang:system_info/1</a> 
%% and <a href="http://www.erlang.org/doc/man/erlang.html#process_info-2">erlang:process_info/1</a>.

-module(percept2_sampling).

-export([sample/3, sample/4, sample/5]).

-export([init/5]).

%%@hidden
-type sample_items():: 
        'run_queue'|'run_queues'|'scheduler_utilisation'|
        'process_count'| 'schedulers_online'|'mem_info'|
        {'message_queue_len', pid()|regname()}.

-type entry_mfa() :: {atom(), atom(),list()}.
-type regname() :: atom().
-type milliseconds()::non_neg_integer().

-record(run_queue_info,
        {timestamp::float(), 
         run_queue=0::non_neg_integer()
        }).

-record(run_queues_info,
        {timestamp::float(),
         run_queues::non_neg_integer()
        }).

-record(scheduler_utilisation_info,
        {timestamp::float(),
         scheduler_utilisation::float()
        }).
   
-record(process_count_info, {
          timestamp::float(),
          process_count::non_neg_integer()}).

-record(schedulers_online_info, {
          timestamp::float(),
          schedulers_online::non_neg_integer()}).

-record(mem_info, {
          timestamp   ::float(),
          total       ::float(),
          processes   ::float(),
          ets         ::float(),
          atom        ::float(),
          code        ::float(),
          binary      ::float()
         }).
 
-record(message_queue_len_info, {
          timestamp ::float(),
          message_queue_len ::non_neg_integer()}).


-define(INTERVAL, 100). % in milliseconds

-define(seconds(EndTs,StartTs), 
        timer:now_diff(EndTs, StartTs)/1000000).

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

%%@hidden
-spec(sample_items()->[atom()]).
sample_items()->
    ['run_queue',
     'run_queues',
     'scheduler_utilisation',
     'process_count',
     'schedulers_online',
     'mem_info',
     'message_queue_len'].

%%@hidden
-spec(check_sample_items([sample_items()]) -> ok).
check_sample_items([{'message_queue_len', _}|Items])->
    check_sample_items(Items);
check_sample_items([Item|Items]) ->
    case lists:member(Item, sample_items()) of
        true ->
            check_sample_items(Items);
        false ->
            error(lists:flatten(io_lib:format("Invalid option:~p", [Item])))
    end;
check_sample_items([]) ->
    ok.


check_out_dir(Dir) ->
    case filelib:is_dir(Dir) of 
        false -> error(lists:flatten(
                         io_lib:format(
                           "Invalid directory:~p", [Dir])));
        true -> ok
    end.
    
%%@doc Start the profiler and collects information about the system.
%%
%% The type of information collected is specified by `Items': 
%%<ul>
%% `run_queue': returns the sum length of all run queues, that is, the total number of processes that are ready to run.
%%</ul>
%%<ul>
%% `run_queues': returns the length of each run queue, that is, the number of processes that are ready to run in each run queue.
%%</ul>
%%<ul>
%% `scheduler_utilisation': returns the scheduler-utilisation rate per scheduler.
%%</ul>
%%<ul>
%% `schedulers_online': returns the amount of schedulers online.
%%</ul>
%%<ul>
%% `process_count': returns the number of processes currently existing at the local node as an integer.
%%</ul>
%%<ul>
%% `mem_info': returns information about memory dynamically allocated by the Erlang emulator. Information 
%% about the following memory types is collected:
%% processes, ets, atom, code and binary. See <a href="http://www.erlang.org/doc/man/erlang.html#memory-1">erlang:memory/1</a>.
%%</ul>
%%<ul>
%% `message_queue_len': returns the number of messages currently in the message queue of the process.
%%</ul>
%%If an entry function is specified, this function profiles the system 
%% for the whole duration until the entry function returns; otherwise it profiles 
%% the system for the time period specified. The system is probed at the default 
%% time intervals, which is 100 milliseconds.
%%
%% `OutDir' tells the profiler where to put the data files generated. A data file is generated 
%% for each type of information in `Items'. For an item `A', the name of the data file could be 
%% `sample_A.dat'. Profiling data is formatted in the way so that the graph plotting tool `Gnuplot' 
%%  can be used for visualisation. A pre-defined plotting script is available for each type of 
%%  information collected, and these scripts are in the `percept2/gplt' directory. To use the 
%%  one of the pre-defined plotting scripts to viusalise the data collected, the following steps
%%  can be followed. We assume Gnuplot is already installed, otherwise install it first.
%%
%% 1) start the Gnuplot tool.
%%
%% 2) in gnuplot, go to the `OutDir' directory, in which the data files are stored. 
%%
%% 3) load the corresponding gnuplot script for the data to be visualised. For 
%%    example, to visualise the memory usage data in file `sample_mem_info.dat', 
%%    the gnuplot script to load is `/path/to/sample_mem_info.plt'. The snapshot
%%    next shows an example output the memory usage graph.
%%
%%  <img src="percept2_sample_mem.png"
%%  alt="the front page of Percept2"  width="850" height="500"> </img>

-spec(sample(Items::[any()],  %%[sample_items()],
             EntryOrTime::entry_mfa()|milliseconds(),
             OutDir::file:filename())
      ->ok).
sample(Items, Time, OutDir) when is_integer(Time)->
    sample(Items, Time, ?INTERVAL,
           fun(_) -> true end, OutDir);
sample(Items, Entry={_Mod, _Fun, _Args},OutDir) ->
    sample(Items, Entry, ?INTERVAL, fun()-> true end,OutDir).

%%@doc Start the profiler and collects information about the system.
%%
%% Different from <a href="percept2_sampling.html#sample-2">sample/2</a>,
%% the function allows the user to specify the time interval.
-spec(sample(Items::[any()],  %%[sample_items()],
             EntryOrTime::entry_mfa()|milliseconds(),
             TimeInterval::milliseconds(), OutDir::file:filename())->ok).         
sample(Items, Time, TimeInterval, OutDir) when is_integer(Time)->
    sample(Items, Time, TimeInterval,fun(_) -> true end, OutDir);
sample(Items, Entry={_Mod, _Fun, _Args}, TimeInterval, OutDir) ->
    sample(Items,Entry, TimeInterval, fun(_) ->true end,OutDir).
   
%%@doc Start the profiler and collects information about the system.
%%
%% Apart from allowing the user to specify the time interval, this 
%% function also allows the user to supply a filter function, so that 
%% only those data that satisfy certain condition are logged.
%% See <a href="percept2_sampling.html#sample-2">sample/2</a>.
-spec(sample(Items::[any()],  %%[sample_items()],
             EntryOrTime::entry_mfa()|milliseconds(),
             TimeInterval::milliseconds(),
             fun((_)-> boolean()),
                OutDir::file:filename()) -> ok).
sample(Items, _Entry={Mod, Fun, Args}, TimeInterval, FilterFun, OutDir) ->
    ok=check_out_dir(OutDir),
    ok=check_sample_items(Items),
    Pid = start_sampling(Items, TimeInterval, FilterFun, OutDir),
    erlang:apply(Mod, Fun, Args),
    stop_sampling(Pid);
sample(Items, Time, TimeInterval, FilterFun, OutDir) 
  when is_integer(Time)->
    ok=check_out_dir(OutDir),
    ok=check_sample_items(Items),
    try 
        Pid=start_sampling(Items, TimeInterval, FilterFun, OutDir),
        erlang:start_timer(Time, Pid, stop)
    catch
        throw:Term -> Term;
        exit:Reason -> {'EXIT',Reason};
        error:Reason -> {'EXIT',{Reason,erlang:get_stacktrace()}}
    end.


%%%----------------------------%%%
%%%  Internal functions        %%%
%%%----------------------------%%%

start_sampling(Items, TimeInterval, FilterFun, OutDir) ->
    case lists:member('scheduler_utilisation', Items) of 
        true ->
            erlang:system_flag(scheduler_wall_time, true);
        _ -> ok
    end,
    spawn_link(?MODULE, init, [now(), Items, TimeInterval, FilterFun, OutDir]).
   
stop_sampling(Pid) ->
    Pid!stop,
    ok.

%%@private
init(StartTs, Items, Interval, FilterFun, OutDir) ->
    create_ets_tables(Items),
    sampling_loop(StartTs, Interval, Items, FilterFun, OutDir).
  
sampling_loop(StartTs, Interval, Items, FilterFun, OutDir) ->
    receive
        stop -> 
            write_data(Items, OutDir);
        {timeout, _TimerRef, stop} -> 
            write_data(Items, OutDir)
    after Interval->
            do_sampling(Items,StartTs),
            sampling_loop(StartTs, Interval, Items, FilterFun, OutDir)
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
    ets:new(TabName, [named_table, ordered_set, protected, {keypos, 2}]),
    create_ets_tables(Items);
create_ets_tables([Item|Items]) ->
    TabName = mk_ets_tab_name(Item),
    ets:new(TabName, [named_table, ordered_set, protected, {keypos, 2}]),
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
    Info=#scheduler_utilisation_info{
      timestamp=?seconds(now(), StartTs),
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
do_sample({message_queue_len, RegName}, StartTs) when is_atom(RegName) ->
    case whereis(RegName) of 
        undefined ->ok;
        Pid -> 
            do_sample({message_queue_len,Pid},StartTs) 
    end;
do_sample({message_queue_len,Pid},StartTs) ->
    [{message_queue_len, MsgQueueLen}] = erlang:process_info(Pid, [message_queue_len]),
    Info = #message_queue_len_info{timestamp=?seconds(now(), StartTs),
                                   message_queue_len = MsgQueueLen
                                  },
    ?dbg(0, "Message queue length:\n~p\n", [Info]),
    ets:insert(mk_ets_tab_name(message_queue_len), Info).

do_write_sample_info(Item, OutDir) ->
    OutFile = filename:join(OutDir, mk_file_name(Item)),
    {ok, FD} = file:open(OutFile, [write]),
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
    {_, Acc1}=ets:foldr(
                fun(_Data={_, Secs, SchedulerWallTime1}, {SchedulerWallTime0, Acc}) ->
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

write_data([{Item, _Args}|Items], OutDir) ->
    do_write_sample_info(Item, OutDir),
    write_data(Items,OutDir);
write_data([Item|Items], OutDir) ->
    do_write_sample_info(Item, OutDir),
    write_data(Items, OutDir);
write_data([], _) ->
    ok.

to_megabytes(Bytes) ->
    Bytes/1000000.

%% Example commands
%% percept2_sampling:sample( ['run_queue','run_queues','scheduler_utilisation',
%%                            'process_count', 'schedulers_online','mem_info'],
%%                          {refac_sim_code_par_v3,sim_code_detection, [["c:/cygwin/home/hl/test"], 5, 40, 2, 4, 0.8, 
%%                                                                      ["c:/cygwin/home/hl/test"],8]},"../profile_data").
%% percept2_sampling:sample(['run_queue','run_queues','scheduler_utilisation',
%%                            'process_count', 'schedulers_online','mem_info', {'message_queue_len', 'percept_db'}], {percept2, analyze, [["sim_code.dat"]]}, ".").
