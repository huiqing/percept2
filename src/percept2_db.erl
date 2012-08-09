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

%% 
%% @doc Percept database.
%%	
%% 
-module(percept2_db).

-export([
        start/1,
        stop/1,
        insert/2,
	select/2,
	select/1,
	consolidate_db/1
	]).
 
-export([gen_process_tree/0,
         gen_fun_info/0,
         gen_callgraph_img/1]).
         
-include("../include/percept2.hrl").

-define(STOP_TIMEOUT, 1000).

-compile(export_all).

%%==========================================================================
%%
%% 		Type definitions 
%%
%%==========================================================================

%% @type activity_option() = 
%%	{ts_min, timestamp()} | 
%%	{ts_max, timestamp()} | 
%%	{ts_exact, bool()} |  
%%	{mfa, {atom(), atom(), byte()}} | 
%%	{state, active | inactive} | 
%%	{id, all | procs | ports | pid() | port()}

%% @type scheduler_option() =
%%	{ts_min, timestamp()} | 
%%	{ts_max, timestamp()} |
%%	{ts_exact, bool()} |
%%	{id, scheduler_id()}

%% @type system_option() = start_ts | stop_ts

%% @type information_option() =
%%	all | procs | ports | pid() | port()

-type filename() :: string()|binary().
%%==========================================================================
%%
%% 		Interface functions
%%
%%==========================================================================

%% @spec start() -> ok | {started, Pid} | {restarted, Pid}
%%	Pid = pid()
%% @doc Starts or restarts the percept database.
-spec start([filename()]) ->{started, [{filename(), pid()}]} | 
                            {restarted, [{filename(), pid()}]}.
start(TraceFileNames) ->
    case erlang:whereis(percept_db) of
    	undefined ->
	    {started, do_start(TraceFileNames)};
	PerceptDB ->
	    {restarted, restart(TraceFileNames,PerceptDB)}
    end.

%% @spec restart(pid()) -> pid()
%% @private
%% @doc restarts the percept database.

-spec restart([filename()],pid())-> [{filename(), pid()}].
restart(TraceFileNames, PerceptDB)->
    true=stop_sync(PerceptDB),
    do_start(TraceFileNames).

%% @spec do_start() -> pid()
%% @private
%% @doc starts the percept database.

-spec do_start([filename()])->{pid(), [{filename(), pid()}]}.
do_start(TraceFileNames)->
    Parent = self(),
    Pid =spawn_link(fun() -> init_percept_db(Parent, TraceFileNames) end),
    io:format("percept db pid:\n~p\n",[Pid]),
    percept2_utils:rm_tmp_files(),
    receive
        {percept_db, started, FileNameSubDBPairs} ->
            FileNameSubDBPairs
    end.
    
%% @spec stop() -> not_started | {stopped, Pid}
%%	Pid = pid()|regname()
%% @doc Stops the percept database.

-spec stop(pid()|atom()) -> 'not_started' | {'stopped', pid()}.

stop(Pid) when is_pid(Pid) ->
    Pid! {action, stop},
    {stopped, Pid};
stop(ProcRegName) ->
    case erlang:whereis(ProcRegName) of
        undefined -> 
            not_started;
        Pid -> 
            Pid ! {action, stop},
            {stopped, Pid}
    end.

%% @spec stop_sync(pid()) -> true
%% @private
%% @doc Stops the percept database, with a synchronous call.

-spec stop_sync(pid())-> true.

stop_sync(Pid)->
    MonitorRef = erlang:monitor(process, Pid),
    case stop(Pid) of 
        not_started -> true;
        {stopped, Pid1} ->
            io:format("Pid1:\n~p\n", [Pid1]),
            receive
                {'DOWN', MonitorRef, _Type, Pid1, _Info}->
                    true;
                {'EXIT', Pid1, _Info} ->
                    true
            after ?STOP_TIMEOUT->
                    io:format("TIME OUT\n"),
                    erlang:demonitor(MonitorRef, [flush]),
                    exit(Pid1, kill)
            end
    end.


stop_percept_sub_dbs(FileNameSubDBPairs) ->
    percept2_utils:pforeach(fun({_FileName, SubDB}) ->
                          true=stop_sync(SubDB)
                  end, FileNameSubDBPairs).
    
  
%% @spec insert(tuple()) -> ok
%% @doc Inserts a trace or profile message to the database.  

insert(SubDB, Trace) -> 
    SubDB ! {insert, Trace},
    ok.


%% @spec select({atom(), Options}) -> Result
%% @doc Synchronous call. Selects information based on a query.
%% 
%% <p>Queries:</p>
%% <pre>
%% {system, Option}
%%	Option = system_option()
%%	Result = timestamp() 
%% {information, Options}
%%	Options = [information_option()]
%%	Result = [#information{}] 
%% {scheduler, Options}
%%	Options = [sceduler_option()]
%%	Result = [#activity{}]
%% {activity, Options}
%%	Options = [activity_option()]
%%	Result = [#activity{}]
%% </pre>
%% <p>
%% Note: selection of Id's are always OR all other options are considered AND.
%% </p>

select(Query) -> %% MSG PASSING, BAD idea? 
  %%  io:format("Query:\n~p\n", [Query]),
    percept_db ! {select, self(), Query},
    receive {result, Match} ->
            Match 
    end.
        

%% @spec select(atom(), list()) -> Result
%% @equiv select({Table,Options}) 

select(Table, Options) -> 
    percept_db ! {select, self(), {Table, Options}},
    receive {result, Match} -> Match end.

%% @spec consolidate([{filename(), pid()}]) -> Result
%% @doc Checks timestamp and state-flow inconsistencies in the
%%	the database.

consolidate(FileNameSubDBPairs) ->
    io:format("consolidate starts\n"),
    percept_db ! {action, self(), {consolidate, FileNameSubDBPairs}},
    receive
        {percept_db, consolidate_done} -> ok;
        Others -> io:format("Consolidate receive:~p\n", [Others])                  
    end.
    

%%==========================================================================
 %%
%% 		Database loop 
%%
%%==========================================================================

init_percept_db(Parent, TraceFileNames) ->
    process_flag(trap_exit, true),
    register(percept_db, self()),
    ets:new(pdb_warnings, [named_table, public, {keypos, 1}, ordered_set]),
    ets:new(pdb_info, [named_table, public, {keypos, #information.id}, set]),
    ets:new(pdb_system, [named_table, public, {keypos, 1}, set]),
    ets:new(funcall_info, [named_table, public, {keypos, #funcall_info.id}, ordered_set,
                           {read_concurrency,true}]),
    ets:new(fun_calltree, [named_table, public, {keypos, #fun_calltree.id}, ordered_set,
                           {read_concurrency,true}]),
    ets:new(fun_info, [named_table, public, {keypos, #fun_info.id}, 
                       ordered_set,{read_concurrency, true}]),
    ets:new(history_html, [named_table, public, {keypos, #history_html.id},
                              ordered_set]),
    io:format("ets tables create\n"),
    FileNameSubDBPairs=start_percept_sub_dbs(TraceFileNames),
    io:format("subdbs started\n"),
    put(debug, 0),
    Parent!{percept_db, started, FileNameSubDBPairs},
    loop_percept_db(FileNameSubDBPairs).

start_percept_sub_dbs(TraceFileNames) ->
    Self = self(),
    IndexList = lists:seq(1, length(TraceFileNames)),
    IndexedTraceFileNames = lists:zip(IndexList, TraceFileNames),
    io:format("IndexedTraceFileNames:\n~p\n", [IndexedTraceFileNames]),
    lists:map(fun({Index, FileName})->
                      SubDBPid = spawn_link(fun()->
                                               start_a_percept_sub_db(Self, {Index, FileName})
                                            end),
                      io:format("SubDBPid:\n~p\n", [SubDBPid]),
                      receive
                          {percept_sub_db_started, {FileName, SubDBPid}} ->
                              {FileName, SubDBPid}
                      end                      
              end, IndexedTraceFileNames).


start_a_percept_sub_db(Parent, {Index, TraceFileName}) ->
    process_flag(trap_exit, true),
    Scheduler = list_to_atom("pdb_scheduler"++integer_to_list(Index)),
    Activity = list_to_atom("pdb_activity"++integer_to_list(Index)),
    ProcessInfo = list_to_atom("pdb_info"++integer_to_list(Index)),
    System = list_to_atom("pdb_system"++integer_to_list(Index)),
    FuncInfo = list_to_atom("pdb_func"++integer_to_list(Index)),
    Warnings = list_to_atom("pdb_warnings"++integer_to_list(Index)),
    io:format("starting a percept_sub_db...\n"),
    start_child_process(Scheduler, fun init_pdb_scheduler/2),
    start_child_process(Activity, fun init_pdb_activity/2),
    start_child_process(ProcessInfo, fun init_pdb_info/2),
    start_child_process(System, fun init_pdb_system/2),
    start_child_process(FuncInfo, fun init_pdb_func/2),
    start_child_process(Warnings, fun init_pdb_warnings/2),
    io:format("starting a percept sub db, children processes created.\n"),
    Parent ! {percept_sub_db_started, {TraceFileName, self()}},
    loop_percept_sub_db(Index).


loop_percept_sub_db(SubDBIndex) ->
    receive
        {insert, Trace} ->
            insert_trace(SubDBIndex,clean_trace(Trace)),
            loop_percept_sub_db(SubDBIndex);
        {select, Pid, Query} ->
            io:format("loop_percept_sub_db query:~p\n", [Query]),
            Pid ! {self(), percept_sub_db_select_query(SubDBIndex, Query)},
            loop_percept_sub_db(SubDBIndex);
        {action, stop} ->
            stop_a_percept_sub_db(SubDBIndex);
        Msg ->
            io:format("loop_percept_sub_db:~p\n", [Msg]),
            loop_percept_sub_db(SubDBIndex)
    end.

stop_a_percept_sub_db(SubDBIndex) ->
    Scheduler = list_to_atom("pdb_scheduler" ++ integer_to_list(SubDBIndex)),
    Activity = list_to_atom("pdb_activity" ++ integer_to_list(SubDBIndex)),
    ProcessInfo = list_to_atom("pdb_info" ++ integer_to_list(SubDBIndex)),
    System = list_to_atom("pdb_system" ++ integer_to_list(SubDBIndex)),
    FuncInfo = list_to_atom("pdb_func" ++ integer_to_list(SubDBIndex)),
    Warnings = list_to_atom("pdb_warnings" ++ integer_to_list(SubDBIndex)),
    case ets:info(Scheduler) of 
        undefined -> 
            io:format("Table does not exist\n"),
            ok;
        _ ->                     
            ets:delete(Scheduler)
    end,
    case ets:info(Activity) of 
        undefined -> ok;
        _ -> ets:delete(Activity)
    end,
    true = stop_sync(Scheduler),
    true = stop_sync(Activity),
    true = stop_sync(ProcessInfo),
    true = stop_sync(System),
    true = stop_sync(FuncInfo),
    true = stop_sync(Warnings).      
    
    


loop_percept_db(FileNameSubDBPairs) ->
    receive
     	{select, Pid, Query} ->
          %%  io:format("received query:\n~p\n", [Query]),
            Res = percept_db_select_query(FileNameSubDBPairs, Query),
            %%io:format("loop percept db query result length:\n~p\n",[length(Res)]), 
	    Pid ! {result, Res},
	    loop_percept_db(FileNameSubDBPairs);
	{action, stop} ->
            stop_percept_db(FileNameSubDBPairs);
	{action, From, {consolidate, FileNameSubDBPairs}} ->
            consolidate_db(FileNameSubDBPairs),
            From ! {percept_db, consolidate_done},
	    loop_percept_db(FileNameSubDBPairs);
        {operate, Pid, {Table, {Fun, Start}}} ->
	    Result = ets:foldl(Fun, Start, Table),
	    Pid ! {result, Result},
	    loop_percept_db(FileNameSubDBPairs);
	Unhandled -> 
	    io:format("loop_percept_db, unhandled query: ~p~n", [Unhandled]),
	    loop_percept_db(FileNameSubDBPairs)
    end.

stop_percept_db(FileNameSubDBPairs) ->
    io:format("Stop percept db:\n~p\n", [FileNameSubDBPairs]),
    ok = stop_percept_sub_dbs(FileNameSubDBPairs),
    ets:delete(pdb_warnings),
    ets:delete(pdb_info),
    ets:delete(pdb_system),
    ets:delete(funcall_info),
    ets:delete(fun_calltree),
    ets:delete(fun_info),
    ets:delete(history_html),
    stopped.

%%==========================================================================
%%
%% 		Auxiliary functions 
%%
%%==========================================================================

%% cleans trace messages from external pids

clean_trace(Trace) ->
    list_to_tuple([clean_trace_1(E)||E<-tuple_to_list(Trace)]).

clean_trace_1(Trace) when is_pid(Trace) ->
    PidStr = pid_to_list(Trace),
    [_,P2,P3p] = string:tokens(PidStr,"."),
    P3 = lists:sublist(P3p, 1, length(P3p) - 1),
    erlang:list_to_pid("<0." ++ P2 ++ "." ++ P3 ++ ">");
clean_trace_1(Trace) -> Trace.

insert_trace(SubDBIndex,Trace) ->
    case element(1, Trace) of
        trace_ts -> 
            Type=element(3, Trace),
            case Type of 
                call -> ok;
                return_to -> ok;
                _ ->
                    FunName = list_to_atom("trace_"++atom_to_list(Type)),
                    ?MODULE:FunName(SubDBIndex, Trace)
            end;
        _ ->
            insert_profile_trace(SubDBIndex,Trace)
    end.                  

insert_profile_trace(SubDBIndex,Trace) ->
    case Trace of
        {profile_start, Ts} ->
            SystemProcRegName =list_to_atom("pdb_system"++integer_to_list(SubDBIndex)),
            update_system_start_ts(SystemProcRegName,Ts);
        {profile_stop, Ts} ->
            SystemProcRegName =list_to_atom("pdb_system"++integer_to_list(SubDBIndex)),
            update_system_stop_ts(SystemProcRegName,Ts);
        {profile, Id, State, Mfa, TS} when is_pid(Id) ->
            ActivityProcRegName = list_to_atom("pdb_activity"++integer_to_list(SubDBIndex)),
            insert_profile_trace_1(ActivityProcRegName,Id,State,Mfa,TS,procs);
        {profile, Id, State, Mfa, TS} when is_port(Id) ->
            ActivityProcRegName = list_to_atom("pdb_activity"++integer_to_list(SubDBIndex)),
            insert_profile_trace_1(ActivityProcRegName, Id, State, Mfa, TS, ports);
        {profile, scheduler, Id, State, NoScheds, Ts} ->
            Act= #activity{
              id = {scheduler, Id},
              state = State,
              timestamp = Ts,
              where = NoScheds},
              % insert scheduler activity
            SchedulerProcRegName = list_to_atom("pdb_scheduler"++integer_to_list(SubDBIndex)),
            update_scheduler(SchedulerProcRegName, Act);
        _Unhandled ->
            io:format("unhandled trace: ~p~n", [_Unhandled])
    end.

insert_profile_trace_1(ProcRegName,Id,State,Mfa,TS,_Type) ->
    case check_activity_consistency({ProcRegName, Id}, State) of
        invalid_state ->
           %% io:format("Invalidate state\n"),
            ok;  %% ingnored.
        ok ->
            % Update registered procs;insert proc activity
          %%  Rc = get_runnable_count(ProcRegName, Type, State),
            update_activity(ProcRegName, #activity{
                              id = Id,
                              state = State,
                              timestamp = TS,
                              where = Mfa})
    end.

trace_spawn(SubDBIndex, _Trace={trace_ts, Parent, spawn, Pid, Mfa, TS}) ->
    ProcRegName = list_to_atom("pdb_info"++integer_to_list(SubDBIndex)),
    InformativeMfa = mfa2informative(Mfa),
    update_information(ProcRegName,
                       #information{id = Pid, start = TS,
                                    parent = Parent, entry = InformativeMfa}),
    update_information_child(ProcRegName, Parent, Pid).

trace_exit(SubDBIndex,_Trace= {trace_ts, Pid, exit, _Reason, TS})->
    ProcRegName = list_to_atom("pdb_info"++integer_to_list(SubDBIndex)),
    update_information(ProcRegName, #information{id = Pid, stop = TS}).

trace_register(SubDBIndex,_Trace={trace_ts, Pid, register, Name, _Ts})->
    case is_pid(Pid) of 
        true ->
            ProcRegName = list_to_atom("pdb_info"++integer_to_list(SubDBIndex)),
            update_information(ProcRegName, #information{id = Pid, name = Name});
        _ -> ok
    end.

trace_unregister(_SubDBIndex, _Trace)->
    ok.  % Not implemented.

trace_getting_unlinked(_SubDBIndex, _Trace) ->
    ok.

trace_getting_linked(_SubDBIndex, _Trace) ->
    ok.
trace_link(_SubDBIndex,_Trace) ->
    ok.

trace_unlink(_SubDBIndex, _Trace) ->
    ok.

trace_in(SubDBIndex, _Trace={trace_ts, Pid, in, Rq,  _MFA, Ts})->
    if is_pid(Pid) ->
            ProcRegName = list_to_atom("pdb_info"++integer_to_list(SubDBIndex)),
            update_information_rq(ProcRegName, Pid, {Ts, Rq});
       true -> ok
    end;
trace_in(_SubDBIndex, _Trace={trace_ts, _Pid, in, _MFA, _Ts}) ->
    ok.


             
trace_out(_SubDBIndex, _Trace={trace_ts, Pid, out, _Rq,  _MFA, _Ts}) when is_pid(Pid) ->
    %% case erlang:get(Pid) of 
    %%     undefined -> io:format("No In time\n");
    %%     InTime ->
    %%         Elapsed = elapsed(InTime, Ts),
    %%         erlang:erase(Pid),
    %%         ets:update_counter(pdb_info, Pid, {13, Elapsed})
    %% end;
    ok;
trace_out(_SubDBIndex, _Trace={trace_ts, Pid, out, _MFA, _Ts}) when is_pid(Pid) ->
    ok;
trace_out(_, _) ->
    ok.

trace_out_exited(_SubDBIndex, _Trace={trace_ts, _Pid, out_exited, _, _Ts}) ->
    ok.

trace_out_exiting(_SubDBIndex, _Trace={trace_ts, _Pid, out_exiting, _, _Ts}) ->
    ok.

trace_in_exiting(_SubDBIndex, _Trace={trace_ts, _Pid, in_exiting, _, _Ts}) ->
    ok.

trace_receive(SubDBIndex, _Trace={trace_ts, Pid, 'receive', MsgSize, _Ts}) ->
    if is_pid(Pid) ->
            ProcRegName = list_to_atom("pdb_info"++integer_to_list(SubDBIndex)),
            update_information_received(ProcRegName, Pid, erlang:external_size(MsgSize));
       true ->
            ok
    end.

trace_send(SubDBIndex,_Trace= {trace_ts, Pid, send, MsgSize, To, _Ts}) ->
    if is_pid(Pid) ->
            ProcRegName = list_to_atom("pdb_info"++integer_to_list(SubDBIndex)),
            update_information_sent(ProcRegName, Pid, erlang:external_size(MsgSize), To);
       true ->
            ok
    end.

trace_send_to_non_existing_process(SubDBIndex,
  _Trace={trace_ts, Pid, send_to_non_existing_process, Msg, _To, _Ts})->
    if is_pid(Pid) ->
            ProcRegName = list_to_atom("pdb_info"++integer_to_list(SubDBIndex)),
            update_information_sent(ProcRegName, Pid, erlang:external_size(Msg), none);
       true ->
            ok
    end.

trace_open(SubDBIndex, _Trace={trace_ts, Caller, open, Port, Driver, TS})->
    ProcRegName = list_to_atom("pdb_info"++integer_to_list(SubDBIndex)),
    update_information(ProcRegName, #information{
                          id = Port, entry = Driver, start = TS, parent = Caller}).

trace_closed(SubDBIndex,_Trace={trace_ts, Port, closed, _Reason, Ts})->
    ProcRegName = list_to_atom("pdb_info"++integer_to_list(SubDBIndex)),
    update_information(ProcRegName, #information{id = Port, stop = Ts}).

trace_call(SubDBIndex, _Trace={trace_ts, Pid, call, MFA,{cp, CP}, TS}) ->
    trace_call(SubDBIndex, Pid, MFA, TS, CP).

trace_return_to(SubDBIndex,_Trace={trace_ts, Pid, return_to, MFA, TS}) ->
    trace_return_to(SubDBIndex, Pid, MFA, TS).

mfarity({M, F, Args}) when is_list(Args) ->
    {M, F, length(Args)};
mfarity(MFA) ->
    MFA.

mfa2informative({erlang, apply, [M, F, Args]})  -> mfa2informative({M, F,Args});
mfa2informative({erlang, apply, [Fun, Args]}) ->
    FunInfo = erlang:fun_info(Fun), 
    M = case proplists:get_value(module, FunInfo, undefined) of
	    []        -> undefined_fun_module;
	    undefined -> undefined_fun_module;
	    Module    -> Module
	end,
    F = case proplists:get_value(name, FunInfo, undefined) of
	    []        -> 
                undefined_fun_function;
	    undefined -> 
                undefined_fun_function; 
	    Function  -> Function
	end,
    mfa2informative({M, F, Args});
mfa2informative(Mfa) -> Mfa.

%% consolidate_db() -> bool()
%% Purpose:
%%	Check start/stop time
%%	Activity consistency
consolidate_db(FileNameSubDBPairs) ->
    io:format("Consolidating...~n"),
    LastIndex = length(FileNameSubDBPairs),
    % Check start/stop timestamps
    case percept_db_select_query([], {system, start_ts}) of
	undefined ->
            Min=get_start_time_ts(),
            update_system_start_ts(1,Min);
        _ -> ok
    end,
    case percept_db_select_query([], {system, stop_ts}) of
	undefined ->
            Max = get_stop_time_ts(LastIndex),
            update_system_stop_ts(1,Max);
        _ -> ok
    end,
    io:format("consolidate runnability ...\n"),
    consolidate_runnability(LastIndex),
    %% consolidate_calltree(),
    %% gen_fun_info(),
    ok.

get_start_time_ts() ->
    AMin = case ets:first(pdb_activity1) of 
                      T when is_tuple(T)-> T;
                      _ ->undefined
                  end,
    SMin = case ets:first(pdb_scheduler1) of 
                       T1 when is_tuple(T1)-> T1;
                       _ -> undefined
                   end,
    case AMin==undefined andalso SMin==undefined of 
        true ->
            undefined;
        _ -> lists:min([AMin, SMin])
    end.


get_stop_time_ts(LastIndex) ->
    LastIndex1 = integer_to_list(LastIndex),
    LastActTab =list_to_atom("pdb_activity"++LastIndex1),
    LastSchedulerTab= list_to_atom("pdb_scheduler"++LastIndex1),
    AMax = case ets:last(LastActTab) of 
               T when is_tuple(T)-> T;
               _ ->undefined
           end,
    SMax = case ets:last(LastSchedulerTab) of 
               T1 when is_tuple(T1)-> T1;
               _ -> undefined
           end,
    case AMax==undefined andalso SMax==undefined of 
        true ->
            undefined;
        _ -> lists:max([AMax, SMax])
    end.
    
%% list_all_ts() ->  %% too expensive!
%%     ATs = [Act#activity.timestamp || Act <- select({activity, []})],
%%     STs = [Act#activity.timestamp || Act <- select({scheduler, []})],
%%     ITs = lists:flatten([
%%                          [I#information.start, 
%%                           I#information.stop] || 
%%                             I <- select({information, all})]),
%%     %% Filter out all undefined (non ts)
%%     [Elem || Elem = {_,_,_} <- ATs ++ STs ++ ITs].

%% get_runnable_count(Type, State) -> RunnableCount
%% In: 
%%	Type = procs | ports
%%	State = active | inactive
%% Out:
%%	RunnableCount = integer()
%% Purpose:
%%	Keep track of the number of runnable ports and processes
%%	during the profile duration.

get_runnable_count(Type, State) ->
    Id = Type,
    case {get({runnable, Id}), State} of 
    	{undefined, active} -> 
            put({runnable, Id}, 1),
	    1;
	{N, active} ->
	    put({runnable, Id}, N + 1),
	    N + 1;
	{N, inactive} ->
	    put({runnable, Id}, N - 1),
	    N - 1;
	Unhandled ->
	    io:format("get_runnable_count, unhandled ~p~n", [Unhandled]),
	    Unhandled
    end.
check_activity_consistency(Id, State) ->
    case get({previous_state, Id}) of
	State ->
      	    invalid_state;
	undefined when State == inactive -> 
	    invalid_state;
	_ ->
	    put({previous_state, Id}, State),
	    ok
    end.

%%%
%%% select_query
%%% In:
%%%	Query = {Table, Option}
%%%	Table = system | activity | scheduler | information
percept_db_select_query(FileNameSubDBPairs, Query) ->
    case Query of
	{system, _ } -> 
	    select_query_system(Query);
	{activity, _ } -> 
	    select_query_activity(FileNameSubDBPairs, Query);
    	{scheduler, _} ->
	    select_query_scheduler(FileNameSubDBPairs, Query);
	{information, _ } -> 
	    select_query_information(Query);
        {code, _} ->
            select_query_func(Query);
        {funs, _} ->
            select_query_func(Query);
        {calltime, _} ->
            select_query_func(Query);
        Unhandled ->
	    io:format("select_query, unhandled: ~p~n", [Unhandled]),
	    []
    end.

percept_sub_db_select_query(SubDBIndex, Query) ->
    io:format("Subdb query:\n~p\n", [{SubDBIndex, Query}]),
    case Query of 
        {activity, _ } -> 
	    select_query_activity_1(SubDBIndex, Query);
        {scheduler, _} ->
            select_query_scheduler_1(SubDBIndex, Query);
        Unhandled ->
	    io:format("percept_sub_db_select_query, unhandled: ~p~n", [Unhandled]),
	    []
    end.
% Options:
% {ts_min, timestamp()}
% {ts_max, timestamp()}
% {mfa, mfa()}
% {state, active | inactive}
% {id, all | procs | ports | pid() | port()}
%
% All options are regarded as AND expect id which are regarded as OR
% For example: [{ts_min, TS1}, {ts_max, TS2}, {id, PID1}, {id, PORT1}] would be
% ({ts_min, TS1} and {ts_max, TS2} and {id, PID1}) or
% ({ts_min, TS1} and {ts_max, TS2} and {id, PORT1}).

activity_ms(Opts) ->
    % {activity, Timestamp, State, Mfa}
    Head = #activity{
    	timestamp = '$1',
	id = '$2',
	state = '$3',
	where = '$4',
	_ = '_'},

    {Conditions, IDs} = activity_ms_and(Head, Opts, [], []),
    Body = ['$_'],
    
    lists:foldl(
    	fun (Option, MS) ->
	    case Option of
		{id, ports} ->
	    	    [{Head, [{is_port, Head#activity.id} | Conditions], Body} | MS];
		{id, procs} ->
	    	    [{Head,[{is_pid, Head#activity.id} | Conditions], Body} | MS];
		{id, ID} when is_pid(ID) ; is_port(ID) ->
	    	    [{Head,[{'==', Head#activity.id, ID} | Conditions], Body} | MS];
		{id, all} ->
	    	    [{Head, Conditions,Body} | MS];
		_ ->
	    	    io:format("activity_ms id dropped ~p~n", [Option]),
	    	    MS
	    end
	end, [], IDs).

activity_ms_and(_, [], Constraints, []) ->
    {Constraints, [{id, all}]};
activity_ms_and(_, [], Constraints, IDs) -> 
    {Constraints, IDs};
activity_ms_and(Head, [Opt|Opts], Constraints, IDs) ->
    case Opt of
	{ts_min, Min} ->
	    activity_ms_and(Head, Opts, 
		[{'>=', Head#activity.timestamp, {Min}} | Constraints], IDs);
	{ts_max, Max} ->
	    activity_ms_and(Head, Opts, 
		[{'=<', Head#activity.timestamp, {Max}} | Constraints], IDs);
	{id, ID} ->
	    activity_ms_and(Head, Opts, 
		Constraints, [{id, ID} | IDs]);
	{state, State} ->
	    activity_ms_and(Head, Opts, 
		[{'==', Head#activity.state, State} | Constraints], IDs);
	{mfa, Mfa} ->
	    activity_ms_and(Head, Opts, 
		[{'==', Head#activity.where, {Mfa}}| Constraints], IDs);
	_ -> 
	    io:format("activity_ms_and option dropped ~p~n", [Opt]),
	    activity_ms_and(Head, Opts, Constraints, IDs)
    end.

% Information = information()

%%%
%%% update_information
%%%
   
start_child_process(ProcRegName, Fun) ->
    Parent=self(),
    Pid=spawn_link(fun() -> Fun(ProcRegName, Parent) end),
    receive
        {ProcRegName, started} ->
            io:format("Process ~p started, Pid:~p\n", [ProcRegName, Pid]),
            ok;
        Msg ->
            io:format("Unexpected message:\n~p\n", [Msg])            
    end.      

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_warnings               %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_warnings(ProcRegName, Parent) ->
    register(ProcRegName, self()),
    Parent !{ProcRegName, started},
    pdb_warnings_loop().

pdb_warnings_loop()->
    receive
        {action, stop} ->
            ok 
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_activity               %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_activity(ProcRegName, Parent) ->
    register(ProcRegName, self()),
    ets:new(ProcRegName, [named_table, protected, {keypos, #activity.timestamp}, ordered_set]),
    Parent !{ProcRegName, started},
    pdb_activity_loop().

update_activity(ProcRegName, Activity) ->
   %% io:format("ProcRegName:~p\n", [{ProcRegName, whereis(ProcRegName)}])
    ProcRegName ! {update_activity, {ProcRegName, Activity}}.
    
consolidate_runnability(LastSubDBIndex) ->
    put({runnable, procs}, undefined),
    put({runnable, ports}, undefined),
    consolidate_runnability_1(1, LastSubDBIndex).

consolidate_runnability_1(CurSubDBIndex, LastSubDBIndex) 
  when CurSubDBIndex>LastSubDBIndex ->
    ok;
consolidate_runnability_1(CurSubDBIndex, LastSubDBIndex) ->
    ActivityProcRegName = list_to_atom("pdb_activity"++integer_to_list(CurSubDBIndex)),
    Pid = whereis(ActivityProcRegName),
    Pid ! {consolidate_runnability, {self(), CurSubDBIndex}},
    receive
        {Pid,done} ->
            consolidate_runnability_1(CurSubDBIndex+1, LastSubDBIndex)
    end.

select_query_activity(FileNameSubDBPairs, Query) ->
    io:format("select_query_activity:\n~p\n", [Query]),
    Res = percept2_utils:pmap(
            fun({_, SubDB}) ->
                    SubDB ! {select, self(), Query},
                    receive
                        {SubDB, Res} ->
                            io:format("received results from subdb:\n~p\n", [SubDB]),
                            Res
                    end
            end, FileNameSubDBPairs),
    lists:append(Res).                        

pdb_activity_loop()->
    receive 
        {update_activity, {SubDBIndex,Activity}} ->
            update_activity_1({SubDBIndex,Activity}),
            pdb_activity_loop();
        {consolidate_runnability, {From, SubDBIndex}} ->
            ok=do_consolidate_runnability(SubDBIndex), 
            From!{self(), done},
            pdb_activity_loop();
        {query_pdb_activity, From, {SubDBIndex, Query}} ->
            Res = select_query_activity_1(SubDBIndex, Query),
            From !{pdb_activity, Res},
            pdb_activity_loop();
        {action, stop} ->
            ok            
    end.

update_activity_1({SubActivityTab,Activity}) ->
    ets:insert(SubActivityTab, Activity).

do_consolidate_runnability(SubDBIndex) ->
    Tab=list_to_atom("pdb_activity"++integer_to_list(SubDBIndex)),
    consolidate_runnability_loop(Tab, ets:first(Tab)).

consolidate_runnability_loop(_Tab, '$end_of_table') -> ok;
consolidate_runnability_loop(Tab, Key) ->
    case ets:lookup(Tab, Key) of
	[#activity{id = Id, state = State }] when is_pid(Id) ->
	    Rc = get_runnable_count(procs, State),
            ets:update_element(Tab, Key, {#activity.runnable_count, Rc});
	[#activity{id = Id, state = State}] when is_port(Id) ->
	    Rc = get_runnable_count(ports, State),
	    ets:update_element(Tab, Key, {#activity.runnable_count, Rc});
	_ -> throw(consolidate)
    end,
    consolidate_runnability_loop(Tab, ets:next(Tab, Key)).

%%% select_query_activity
select_query_activity_1(SubDBIndex, Query) ->
    case Query of
    	{activity, Options} when is_list(Options) ->
	    case lists:member({ts_exact, true},Options) of
		true ->
		    case catch select_query_activity_exact_ts(SubDBIndex, Options) of
			{'EXIT', Reason} ->
	    		    io:format(" - select_query_activity [ catch! ]: ~p~n", [Reason]),
			    [];
		    	Match ->
			    Match
		    end;		    
		false ->
		    MS = activity_ms(Options),
                    Tab = list_to_atom("pdb_activity"++integer_to_list(SubDBIndex)),
                    io:format("Tab:\n~p\n", [Tab]),
		    case catch ets:select(Tab, MS) of
			{'EXIT', Reason} ->
	    		    io:format(" - select_query_activity [ catch! ]: ~p~n", [Reason]),
			    [];
		    	Match ->
                            io:format("~p items found in tab ~p\n", [length(Match), Tab]),
                            Match
		    end
	    end;
	Unhandled ->
	    io:format("select_query_activity, unhandled: ~p~n", [Unhandled]),
    	    []
    end.

select_query_activity_exact_ts(SubDBIndex, Options) ->
    case { proplists:get_value(ts_min, Options, undefined), 
           proplists:get_value(ts_max, Options, undefined) } of
	{undefined, undefined} -> [];
	{undefined, _        } -> [];
	{_        , undefined} -> [];
	{TsMin    , TsMax    } ->
            Tab = list_to_atom("pdb_activity"++integer_to_list(SubDBIndex)),
	    % Remove unwanted options
	    Opts = lists_filter([ts_exact], Options),
	    Ms = activity_ms(Opts),
	    case ets:select(Tab, Ms) of
		% no entries within interval
		[] -> 
		    Opts2 = lists_filter([ts_max, ts_min], Opts) ++ [{ts_min, TsMax}],
		    Ms2   = activity_ms(Opts2),
		    case ets:select(Tab, Ms2, 1) of
			'$end_of_table' -> [];
			{[E], _}  -> 
			    [PrevAct] = ets:lookup(Tab, ets:prev(Tab, E#activity.timestamp)),
			    [PrevAct#activity{ timestamp = TsMin} , E] 
		    end;
		Acts=[Head|_] ->
                    if
			Head#activity.timestamp == TsMin -> Acts;
			true ->
			    PrevTs = ets:prev(Tab, Head#activity.timestamp),
			    case ets:lookup(Tab, PrevTs) of
				[] -> Acts;
				[PrevAct] -> [PrevAct#activity{timestamp = TsMin}|Acts]
			    end
		    end
	    end
    end.

lists_filter([], Options) -> Options;
lists_filter([D|Ds], Options) ->
    lists_filter(Ds, lists:filter(
	fun ({Pred, _}) ->
	    if 
		Pred == D -> false;
		true      -> true
	    end
	end, Options)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_scheduler              %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_scheduler(ProcRegName, Parent) ->
    register(ProcRegName, self()),
    ets:new(ProcRegName, [named_table, protected, {keypos, #activity.timestamp}, ordered_set]),
    Parent ! {ProcRegName, started},    
    pdb_scheduler_loop().
    
update_scheduler(SchedulerProcRegName,Activity) ->
    SchedulerProcRegName ! {update_scheduler, {SchedulerProcRegName,Activity}}.

select_query_scheduler(FileNameSubDBPairs, Query) ->
    io:format("query scheduler:\n~p\n", [Query]),
    Res = percept2_utils:pmap(
            fun({_, SubDB}) ->
                    SubDB ! {select, self(), {SubDB, Query}},
                    receive
                        {SubDB, Res} ->
                            Res
                    end
            end, FileNameSubDBPairs),
    lists:append(Res).

pdb_scheduler_loop()->
    receive
        {update_scheduler, {SchedulerProcRegName,Activity}} ->
            update_scheduler_1({SchedulerProcRegName,Activity}),
            pdb_scheduler_loop();
        {'query_pdb_scheduler', From, {SubDBIndex, Query}} ->
            Res=select_query_scheduler_1(SubDBIndex, Query),
            From !{self(), Res},
            pdb_scheduler_loop();
        {action, stop} ->
            ok
    end.

update_scheduler_1({SchedulerProcRegName,Activity}) ->
    ets:insert(SchedulerProcRegName, Activity).

select_query_scheduler_1(SubDBIndex, Query) ->
    case Query of
	{scheduler, Options} when is_list(Options) ->
	    Head = #activity{
	    	timestamp = '$1',
		id = '$2',
		state = '$3',
		where = '$4',
		_ = '_'},
	    Body = ['$_'],
	    % We don't need id's
	    {Constraints, _ } = activity_ms_and(Head, Options, [], []),
            Tab = list_to_atom("pdb_scheduler"++integer_to_list(SubDBIndex)),
	    ets:select(Tab, [{Head, Constraints, Body}]);
	Unhandled ->
	    io:format("select_query_scheduler_1, unhandled: ~p~n", [Unhandled]),
	    []
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_info                   %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_info(ProcRegName, Parent) ->
    register(ProcRegName, self()),
    Parent ! {ProcRegName, started},
    pdb_info_loop().

update_information(ProcRegName, Info) ->
    ProcRegName!{update_information, Info}.

update_information_child(ProcRegName, Id, Child) ->
    ProcRegName!{update_information_child, {Id, Child}}.

update_information_rq(ProcRegName, Pid, {Ts,Rq}) ->
    ProcRegName!{update_information_rq, {Pid, {Ts, Rq}}}.

update_information_sent(ProcRegName, From, MsgSize, To) ->
    ProcRegName!{update_information_sent, {From, MsgSize, To}}.

update_information_received(ProcRegName, Pid, MsgSize)->
    ProcRegName!{update_information_received, {Pid, MsgSize}}.

update_information_element(ProcRegName, Key, {Pos, Value}) ->
    ProcRegName! {update_information_element, {Key, {Pos, Value}}}.


%%% select_query_information
select_query_information(Query) ->
    select_query_information(pdb_info1, Query).
select_query_information(InfoProcRegName, Query) ->
    %% io:format("Query info:\n~p\n", [Query]),
    %% io:format("InfoProcRegName:\n~p\n", [InfoProcRegName]),
    Pid = whereis(InfoProcRegName),
    Pid !{'query_pdb_info', self(), Query},
    receive 
        {Pid, Res} ->
           %% io:format("select_query_information receive result\n"),
            Res
    end.

pdb_info_loop()->
    receive
        {update_information, #information{id=_Id}=NewInfo} ->
            update_information_1(NewInfo),
            pdb_info_loop();
        {update_information_child, {Id, Child}} ->
            update_information_child_1(Id, Child),
            pdb_info_loop();
        {update_information_rq, {Pid, {TS,Rq}}} ->
            update_information_rq_1(Pid, {TS, Rq}),
            pdb_info_loop();
        {update_information_sent, {From, MsgSize, To}} ->
            update_information_sent_1(From, MsgSize, To),
            pdb_info_loop();
        {update_information_received, {Pid, MsgSize}} ->
            update_information_received_1(Pid, MsgSize),
            pdb_info_loop();       
        {update_information_element, {Key, {Pos, Value}}} ->
            ets:update_element(pdb_info, Key, {Pos, Value}),
            pdb_info_loop();
        {'query_pdb_info', From, Query} ->
            Res = select_query_information_1(Query),
            From!{self(), Res},
            pdb_info_loop();
        {action,stop} ->
            ok
    end.

update_information_1(#information{id = Id} = NewInfo) ->
    case ets:lookup(pdb_info, Id) of
    	[] ->
            ets:insert(pdb_info, NewInfo),
	    ok;
	[Info] ->
	    % Remake NewInfo and Info to lists then substitute
	    % old values for new values that are not undefined or empty lists.
	    {_, Result} = lists:foldl(
	    	fun (InfoElem, {[NewInfoElem | Tail], Out}) ->
		    case NewInfoElem of
		    	undefined ->
			    {Tail, [InfoElem | Out]};
		    	[] ->
			    {Tail, [InfoElem | Out]};
                        {0,0} ->
                            {Tail, [InfoElem | Out]};
                        0 ->
                            {Tail, [InfoElem|Out]};
                        _ ->
			    {Tail, [NewInfoElem | Out]}
		    end
		end, {tuple_to_list(NewInfo), []}, tuple_to_list(Info)),
                     ets:insert(pdb_info, list_to_tuple(lists:reverse(Result)))
    end.

update_information_child_1(Id, Child) -> 
    case ets:lookup(pdb_info, Id) of
    	[] ->
            ets:insert(pdb_info,#information{
                         id = Id,
                         children = [Child]});
        [I] ->
            ets:insert(pdb_info,
                       I#information{
                         children = [Child|I#information.children]})
    end.

update_information_rq_1(Pid, {TS,RQ}) ->
    case ets:lookup(pdb_info, Pid) of
        [] -> 
            ets:insert(pdb_info, #information{
                         id = Pid, 
                         rq_history=[{TS,RQ}]}),
            ok; %% this should not happen;
        [I] ->
            ets:update_element(
              pdb_info, Pid, {9, [{TS, RQ}|I#information.rq_history]})
    end.
%% with the parallel version, checking whether a message is 
%% send to the same run queue needs a different algorithm,
%% and this feature is removed for now.
update_information_sent_1(From, MsgSize, _To) ->
    case  ets:lookup(pdb_info, From) of
        [] -> 
            ets:insert(pdb_info, 
                       #information{id=From, 
                                    msgs_sent={1, MsgSize}
                                   });            
        [I] ->
            {No, Size} =  I#information.msgs_sent, 
            ets:update_element(pdb_info, From, {12, {No+1, Size+MsgSize}})
    end.
 
update_information_received_1(Pid, MsgSize) ->
    case  ets:lookup(pdb_info, Pid) of
        [] -> 
            ets:insert(pdb_info, #information{
                         id = Pid,
                         msgs_received ={1, MsgSize}
                        });
        [I] ->
            {No, Size} = I#information.msgs_received,
            ets:update_element(pdb_info, Pid,
                               {11, {No+1, Size+MsgSize}})
    end.

select_query_information_1(Query) ->
    case Query of
    	{information, all} -> 
	    ets:select(pdb_info, [{
		#information{ _ = '_'},
		[],
		['$_']
		}]);
	{information, procs} ->
	    ets:select(pdb_info, [{
		#information{id = '$1', _ = '_'},
		[{is_pid, '$1'}],
		['$_']
		}]);
	{information, ports} ->
	    ets:select(pdb_info, [{
		#information{ id = '$1', _ = '_'},
		[{is_port, '$1'}],
		['$_']
		}]);
	{information, Id} when is_port(Id) ; is_pid(Id) -> 
	    ets:select(pdb_info, [{
		#information{ id = Id, _ = '_'},
		[],
		['$_']
		}]);
	Unhandled ->
	    io:format("select_query_information, unhandled: ~p~n", [Unhandled]),
	    []
    end.

    


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_system                 %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
           
%% central pdb_system table shared by sub DBs.
init_pdb_system(ProcRegName, Parent)->  
    register(ProcRegName, self()),
    Parent ! {ProcRegName, started},
    pdb_system_loop().

update_system_start_ts(SystemProcRegName, TS) ->
    SystemProcRegName ! {'update_system_start_ts', TS}.

update_system_stop_ts(SystemProcRegName, TS) ->
    SystemProcRegName ! {'update_system_stop_ts', TS}.

select_query_system(Query) ->
    select_query_system(pdb_system1, Query).
select_query_system(SystemProcRegName,Query) ->
    Pid = whereis(SystemProcRegName),
    Pid ! {'query_system', self(), Query},
    receive
        {Pid, Res} ->
            Res
    end.
     
pdb_system_loop() ->
    receive
        {'update_system_start_ts', TS}->
            update_system_start_ts_1(TS),
            pdb_system_loop();
        {'update_system_stop_ts', TS} ->
            update_system_stop_ts_1(TS),
            pdb_system_loop();
        {'query_system', From, Query} ->
            Res=select_query_system_1(Query),
            From ! {self(), Res},
            pdb_system_loop();
        {action, stop} ->
            ok
    end.
    
update_system_start_ts_1(TS) ->
    case ets:lookup(pdb_system, {system, start_ts}) of
    	[] ->
	    ets:insert(pdb_system, {{system, start_ts}, TS});
	[{{system, start_ts}, StartTS}] ->
	    DT = ?seconds(StartTS, TS),
	    if 
		DT > 0.0 -> ets:insert(pdb_system, {{system, start_ts}, TS});
	    	true -> ok
	    end;
	Unhandled -> 
	    io:format("update_system_start_ts, unhandled ~p ~n", [Unhandled])
    end.
	
update_system_stop_ts_1(TS) ->
    case ets:lookup(pdb_system, {system, stop_ts}) of
    	[] ->
	    ets:insert(pdb_system, {{system, stop_ts}, TS});
	[{{system, stop_ts}, StopTS}] ->
	    DT = ?seconds(StopTS, TS),
	    if 
		DT < 0.0 -> ets:insert(pdb_system, {{system, stop_ts}, TS});
	  	true -> ok
	    end;
	Unhandled -> 
	    io:format("update_system_stop_ts, unhandled ~p ~n", [Unhandled])
    end.

%%% select_query_system
select_query_system_1(Query) ->
    case Query of
    	{system, start_ts} ->
    	    case ets:lookup(pdb_system, {system, start_ts}) of
	    	[] -> undefined;
		[{{system, start_ts}, StartTS}] -> StartTS
	    end;
    	{system, stop_ts} ->
    	    case ets:lookup(pdb_system, {system, stop_ts}) of
	    	[] -> undefined;
		[{{system, stop_ts}, StopTS}] -> StopTS
	    end;
	Unhandled ->
	    io:format("select_query_system, unhandled: ~p~n", [Unhandled]),
	    []
    end.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%   Gen process tree                               %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-type process_tree()::{#information{},[process_tree()]}.
gen_compressed_process_tree()->
    Trees = gen_process_tree(),
    compress_process_tree(Trees).
    

-spec gen_process_tree/0::()->[process_tree()].
gen_process_tree() ->
    Res = select({information,procs}),
    List = lists:keysort(2,Res),  
    gen_process_tree(List, []).

-spec gen_process_tree/2::([#information{}], [process_tree()]) 
                          -> [process_tree()].
gen_process_tree([], Out) ->
    add_ancestors(Out);
gen_process_tree([Elem|Tail], Out) ->
    Children = Elem#information.children,
    {ChildrenElems, Tail1} = lists:partition(
                               fun(E) -> 
                                       lists:member(E#information.id, Children)
                               end, Tail),
    {NewChildren, NewTail}=gen_process_tree_1(ChildrenElems, Tail1, []),
    gen_process_tree(NewTail, [{Elem, NewChildren}|Out]).

-spec gen_process_tree_1/3::([#information{}], [#information{}],[process_tree()]) 
                          -> {[process_tree()], [#information{}]}.
gen_process_tree_1([], Tail, NewChildren) ->
    {NewChildren, Tail};
gen_process_tree_1([C|Cs], Tail, Out) ->
    Children = C#information.children,
    {ChildrenElems, Tail1} = lists:partition(
                               fun(E) -> 
                                       lists:member(E#information.id, Children)
                               end, Tail),
    {NewChildren, NewTail}=gen_process_tree_1(ChildrenElems, Tail1, []),
    gen_process_tree_1(Cs, NewTail, [{C, NewChildren}|Out]).

-spec add_ancestors/1::(process_tree())->process_tree().
add_ancestors(ProcessTree) ->
    add_ancestors(ProcessTree, []).

add_ancestors(ProcessTree, As) ->
    [begin 
         update_information_element(pdb_info1, Parent#information.id, {8, As}),
         {Parent#information{ancestors=As},         
          add_ancestors(Children, [Parent#information.id|As])}
     end
     ||{Parent, Children} <- ProcessTree].
  
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_func                   %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_func(ProcRegName, Parent) ->
    register(ProcRegName, self()),
    Parent !{ProcRegName, started},
    pdb_fun_loop().

trace_call(_SubDBIndex, Pid, Func, TS, CP) ->
    pdb_func ! {trace_call, {Pid, Func, TS, CP}}.

trace_return_to(_SubDBIndex,Pid, MFA, TS) ->
    pdb_func !{trace_return_to, {Pid, MFA, TS}}.

consolidate_calltree()->    
    pdb_func!{consolidate_calltree, self()},
    receive
        {pdb_func, consolidate_calltree_done} ->
            ok
    end.

gen_fun_info()->
    pdb_func!{gen_fun_info, self()},
    receive
        {pdb_func, gen_fun_info_done} ->
            ok
    end.

select_query_func(Query) ->
    pdb_func !{query_pdb_func, self(), Query},
    receive
        {pdb_func, Res} ->
            Res
    end.

pdb_fun_loop()->
    receive
        {trace_call, {Pid, Func, TS, CP}} ->
            trace_call_1(Pid, Func, TS, CP),
            pdb_fun_loop();
        {trace_return_to, {Pid, Func, TS}} ->
            trace_return_to_1(Pid, Func, TS),
            pdb_fun_loop();
        {consolidate_calltree, From} ->
            ok=consolidate_calltree_1(),
            From!{pdb_func, consolidate_calltree_done},
            pdb_fun_loop();
        {gen_fun_info, From} ->
            ok = gen_fun_info_1(),
            From !{pdb_func, gen_fun_info_done},
            pdb_fun_loop();
        {query_pdb_func, From, Query} ->
            Res = select_query_fun_1(Query),
            From !{self(), Res},
            pdb_fun_loop();
        {action, stop} ->
            ok 
    end.


trace_call_1(Pid, MFA, TS, CP) -> 
    Func = mfarity(MFA),
    Stack = get_stack(Pid),
    ?dbg(0, "trace_call(~p, ~p, ~p, ~p)~n~p~n", 
	 [Pid, Func, TS, CP, Stack]),
    case Stack of 
        [[{Func1,TS1}, dummy]|Stack1] when Func1=/=CP ->
            {Caller1, Caller1StartTs}= case Stack1 of 
                                           [[{Func2, TS2}|_]|_]->
                                               {Func2, TS2};
                                           _ ->
                                               {Func1, TS1}
                                     end,
            update_calltree_info(Pid, {Func1, TS1, TS}, {Caller1, Caller1StartTs}),
            trace_call_1(Pid, Func, TS, CP, Stack1);
        _ ->
            trace_call_1(Pid, Func, TS, CP, Stack)
    end.
    
trace_call_1(Pid, Func, TS, CP, Stack) ->
    case Stack of
	[] ->
            ?dbg(0, "empty stack\n", []),
             OldStack = 
		if CP =:= undefined ->
			Stack;
		   true ->
			[[{CP, TS}]]
		end,
            put(Pid, trace_call_push(Func, TS, OldStack));
        [[{suspend, _} | _] | _] ->
      	    throw({inconsistent_trace_data, ?MODULE, ?LINE,
                   [Pid, Func, TS, CP, Stack]});
	[[{garbage_collect, _} | _] | _] ->
	    throw({inconsistent_trace_data, ?MODULE, ?LINE,
                   [Pid, Func, TS, CP, Stack]});
        [[{Func, _FirstInTS}]] ->
            put(Pid, Stack);
       	[[{CP, _} | _], [{CP, _} | _] | _] ->
            put(Pid, trace_call_shove(Pid,Func, TS, Stack));
        [[{CP, _} | _] | _] when Func==CP ->
            ?dbg(0, "Current function becomes new stack top.\n", []),
            put(Pid, Stack);
	[[{CP, _} | _] | _] ->
            ?dbg(0, "Current function becomes new stack top.\n", []),
            put(Pid, trace_call_push(Func, TS, Stack));
        [_, [{CP, _} | _] | _] ->
           ?dbg(0, "Stack top unchanged, no push.\n", []),
           put(Pid, trace_call_shove(Pid, Func, TS, Stack)); 
        [[{Func0, _} | _], [{Func0, _} | _], [{CP, _} | _] | _] ->
             put(Pid, 
                 trace_call_shove(Pid, Func, TS,
                                  trace_return_to_2(Pid, Func0, TS,
                                                    Stack)));
        [_|_] ->
            put(Pid, [[{Func, TS}], [{CP, TS}, dummy]|Stack])
    end.
   

%% Normal stack push
trace_call_push(Func, TS, Stack) ->
    [[{Func, TS}] | Stack].
 
%% Tail recursive stack push
trace_call_shove(_Pid, Func, TS, []) ->
    [[{Func, TS}]];
trace_call_shove(Pid, Func, TS,  [Level0|Stack1]) ->
    [[{Func1,TS1}| NewLevel0] | NewStack1] = 
        [trace_call_collapse([{Func, TS} | Level0]) | Stack1],
    case Level0 -- [{Func1,TS1}| NewLevel0] of 
        [] -> ok;
        Funs ->
            {Caller1, Caller1StartTs}= hd(NewLevel0),
            [update_calltree_info(Pid, {Func2, TS2, TS}, {Caller1, Caller1StartTs})||
                     {Func2, TS2} <- Funs]
    end,
    [[{Func, TS1} | NewLevel0] | NewStack1].
    
 
%% Collapse tail recursive call stack cycles to prevent them from
%% growing to infinite length.
trace_call_collapse([]) ->
    [];
trace_call_collapse([_] = Stack) ->
    Stack;
trace_call_collapse([_, _] = Stack) ->
     Stack;
trace_call_collapse([_ | Stack1] = Stack) ->
    ?dbg(0, "collapse_trace_state(~p)~n", [Stack]),
    trace_call_collapse_1(Stack, Stack1, 1).


%% Find some other instance of the current function in the call stack
%% and try if that instance may be used as stack top instead.
trace_call_collapse_1(Stack, [], _) ->
    Stack;
trace_call_collapse_1([{Func0, _} | _] = Stack, [{Func0, _} | S1] = S, N) ->
    case trace_call_collapse_2(Stack, S, N) of
	true ->
	    S;
	false ->
	    trace_call_collapse_1(Stack, S1, N+1)
    end;
trace_call_collapse_1(Stack, [_ | S1], N) ->
    trace_call_collapse_1(Stack, S1, N+1).

%% Check if all caller/called pairs in the perhaps to be collapsed
%% stack segment (at the front) are present in the rest of the stack, 
%% and also in the same order.
trace_call_collapse_2(_, _, 0) ->
    true;
trace_call_collapse_2([{Func1, _} | [{Func2, _} | _] = Stack2],
	   [{Func1, _} | [{Func2, _} | _] = S2],
	   N) ->
    trace_call_collapse_2(Stack2, S2, N-1);
trace_call_collapse_2([{Func1, _} | _], [{Func1, _} | _], _N) ->
    false;
trace_call_collapse_2(_Stack, [_], _N) ->
    false;
trace_call_collapse_2(Stack, [_ | S], N) ->
    trace_call_collapse_2(Stack, S, N);
trace_call_collapse_2(_Stack, [], _N) ->
    false.


trace_return_to_1(Pid, MFA, TS) ->
    Caller = mfarity(MFA),
    Stack = get_stack(Pid),
    ?dbg(0, "trace_return_to(~p, ~p, ~p)~n~p~n", 
	 [Pid, Caller, TS, Stack]),
    case Stack of
	[[{suspend, _} | _] | _] ->
	    throw({inconsistent_trace_data, ?MODULE, ?LINE,
		  [Pid, Caller, TS, Stack]});
	[[{garbage_collect, _} | _] | _] ->
	    throw({inconsistent_trace_data, ?MODULE, ?LINE,
		  [Pid, Caller, TS, Stack]});
        [_, [{Caller, _}|_]|_] ->
            NewStack=trace_return_to_2(Pid, Caller, TS, Stack),
            put(Pid, NewStack);
        [[{Func1, TS1}, dummy]|Stack1=[_, [{Caller, _}|_]]] when Caller=/=Func1->
            {Caller1, Caller1StartTs}= case Stack1 of 
                                           [[{Func2, TS2}|_]|_]->
                                               {Func2, TS2};
                                           _ ->
                                               {Func1, TS1}
                                       end,
            update_calltree_info(Pid, {Func1, TS1, TS}, {Caller1, Caller1StartTs}),
            NewStack=trace_return_to_2(Pid, Caller, TS, Stack),
            put(Pid, NewStack);
        _ when Caller == undefined ->
            NewStack=trace_return_to_2(Pid, Caller, TS, Stack),
            put(Pid, NewStack);            
        _ ->
            NewStack=trace_return_to_0(Pid, Caller, TS, Stack),
            put(Pid, NewStack)    
    end.

trace_return_to_0(Pid, Caller, TS, Stack)->
    {Callers,_} = lists:unzip([hd(S)||S<-Stack]),
    case lists:member(Caller, Callers) of
        true ->
            trace_return_to_2(Pid, Caller, TS, Stack);
        _ -> 
            [[{Caller, TS}, dummy]|Stack]
    end.

trace_return_to_2(_, undefined, _, []) ->
    [];
trace_return_to_2(_Pid, Func, TS, []) ->
    [[{Func, TS}]];
trace_return_to_2(Pid, Func, TS, [[] | Stack1]) ->
    trace_return_to_2(Pid, Func, TS, Stack1);
trace_return_to_2(_Pid, Func, _TS, [[{Func, _}|_Level0]|_Stack1] = Stack) ->
    Stack;
trace_return_to_2(Pid, Func, TS, [[{Func0, TS1} | Level1] | Stack1]) ->
    case Func0 of 
         {_, _, _} ->
            {Caller, CallerStartTs}= case Level1 of 
                                         [{Func1, TS2}|_] ->
                                             {Func1, TS2};
                                         _ -> case Stack1 of 
                                                  [[{Func1, TS2}, dummy]|_] ->
                                                      {Func1, TS2};
                                                  [[{Func1, TS2}|_]|_]->
                                                      {Func1, TS2};
                                                  [] ->
                                                      {Func, TS1}
                                              end
                                     end,
            ets:insert(funcall_info, #funcall_info{id={Pid, TS1}, func=Func0, end_ts=TS}),
            update_fun_call_count_time({Pid, Func0}, {TS1, TS}),
            update_calltree_info(Pid, {Func0, TS1, TS}, {Caller, CallerStartTs});
         _ -> ok  %% garbage collect or suspend.
    end,
    if Level1 ==[dummy] ->
            trace_return_to_2(Pid, Func, TS, Stack1);
       true ->
            trace_return_to_2(Pid, Func, TS, [Level1|Stack1])
    end.
   
        
update_calltree_info(Pid, {Callee, StartTS0, EndTS}, {Caller, CallerStartTS0}) ->
    CallerStartTS = case is_list_comp(Caller) of 
                       true -> undefined;
                       _ -> CallerStartTS0
                   end,
    StartTS = case is_list_comp(Callee) of 
                   true -> undefined;
                   _ -> StartTS0
               end,
   %% io:format("Caller,Callee StartTs:\n~p\n", [{CallerStartTS, StartTS}]),
    case ets:lookup(fun_calltree, {Pid, Callee, StartTS}) of
        [] ->
           %% io:format("Create new calleed\n"),
            add_new_callee_caller(Pid, {Callee, StartTS, EndTS},
                                  {Caller, CallerStartTS});
        [F] -> 
            %%io:format("add caller\n"),
            NewF =F#fun_calltree{id=setelement(3, F#fun_calltree.id, Caller),
                                 cnt=1,
                                 start_ts =StartTS,
                                 end_ts=EndTS},                  
            case ets:lookup(fun_calltree, {Pid, Caller, CallerStartTS}) of 
                [C] when Caller=/=Callee->
                   %% io:format("caller exist\n"),
                    ets:delete_object(fun_calltree, F),
                    NewC = C#fun_calltree{called=add_new_callee(NewF, C#fun_calltree.called)},
                   %% io:format("C:\n~p\n", [C]),
                   %% io:format("NewC:\n~p\n", [NewC]),
                    NewC1 = collapse_call_tree(NewC, Callee),
                    ets:insert(fun_calltree, NewC1);                  
                _ ->
                    %% io:format("Caller does not exist\n"),
                    CallerInfo = #fun_calltree{id = {Pid, Caller, CallerStartTS},
                                               cnt =1,
                                               start_ts=CallerStartTS,
                                               called = [NewF]}, 
                    ets:delete_object(fun_calltree, F),
                    NewCallerInfo = collapse_call_tree(CallerInfo, Callee),
                    ets:insert(fun_calltree, NewCallerInfo)
            end
    end.

add_new_callee_caller(Pid, {Callee, StartTS, EndTS},{Caller, CallerStartTS}) ->
    CalleeInfo = #fun_calltree{id={Pid, Callee, Caller},
                               cnt =1, 
                               called = [],
                               start_ts = StartTS,
                               end_ts = EndTS},
    case ets:lookup(fun_calltree, {Pid, Caller, CallerStartTS}) of
         [] ->
            CallerInfo = #fun_calltree{id = {Pid, Caller, CallerStartTS},
                                       cnt =1,
                                       called = [CalleeInfo],
                                       start_ts=CallerStartTS},
            ets:insert(fun_calltree, CallerInfo);
        [C] ->
            NewC = C#fun_calltree{called=add_new_callee(CalleeInfo, C#fun_calltree.called)},
            ets:insert(fun_calltree, NewC)
    end.


%% collapse recursive call chains to which Callee is an element of 
%% recursion.      
%% TOTest: is this accurate enough?
collapse_call_tree(CallTree, Callee) ->
    {_Pid, Caller,_TS} = CallTree#fun_calltree.id,
    Children=CallTree#fun_calltree.called,
    case collect_children_to_merge(Children, {Caller, Callee}) of 
        {_, []} ->
         %%   io:format("Nothing to merge\n"),
            CallTree;
        {ToRemain, ToMerge} ->
            NewCalled = lists:foldl(fun(C, Acc) ->
                                             add_new_callee(C, Acc)
                                    end, ToRemain, ToMerge),
            CallTree#fun_calltree{called=NewCalled}
            
    end.

collect_children_to_merge([], _) ->       
    {[], []};
collect_children_to_merge(CallTrees, {Caller, Callee}) ->
    {ToRemain, ToMerge}=lists:unzip(
                          [collect_children_to_merge_1(CallTree,{Caller,Callee})
                           ||CallTree <- CallTrees]),
    {ToRemain, lists:append(ToMerge)}.

collect_children_to_merge_1(CallTree, {Caller, Callee}) ->
    {_Pid, MFA, _TS}=CallTree#fun_calltree.id,
    case MFA of 
        Caller ->
            Called = CallTree#fun_calltree.called,
            {ToMerge, ToRemain}=lists:partition(
                                  fun(F)->
                                          element(2, F#fun_calltree.id)==Callee
                                  end, Called),
            {CallTree#fun_calltree{called=ToRemain}, ToMerge};
        _ ->
            {ToRemain, ToMerge}=collect_children_to_merge(
                                  CallTree#fun_calltree.called, {Caller, Callee}),
            {CallTree#fun_calltree{called=ToRemain}, ToMerge}
    end.

add_new_callee(CalleeInfo, CalleeList) ->
    Id = CalleeInfo#fun_calltree.id,
  %%  io:format("ID:\n~p\n", [Id]),
    case lists:keyfind(Id, 2, CalleeList) of
        false ->
          %%  io:format("not found\n"),
            [CalleeInfo|CalleeList];
        C ->
           %% io:format("found:~p\n", [C]),
            NewC=combine_fun_info(C, CalleeInfo),
            lists:keyreplace(Id, 2, CalleeList, NewC)
    end.

combine_fun_info(FunInfo1=#fun_calltree{id=Id, called=Callees1, 
                                        start_ts=StartTS1,end_ts= _EndTS1,
                                        cnt=CNT1}, 
                 _FunInfo2=#fun_calltree{id=Id, called=Callees2, 
                                         start_ts=_StartTS2, end_ts=EndTS2,
                                         cnt=CNT2}) ->
    NewCallees=lists:foldl(fun(C, Callees) ->
                                  add_new_callee(C, Callees)
                           end, Callees1, Callees2),
    FunInfo1#fun_calltree{id=Id, called=NewCallees, 
                      start_ts=StartTS1, end_ts=EndTS2,
                      cnt = CNT1 + CNT2}.
                      
get_stack(Id) ->
    case get(Id) of
	undefined ->
	    [];
	Stack ->
	    Stack
    end.

is_list_comp({_M, F, _A}) ->
    re:run(atom_to_list(F), ".*-lc.*", []) /=nomatch;
is_list_comp(_) ->
    false.
      
consolidate_calltree_1() ->
    Pids=ets:select(fun_calltree, [{#fun_calltree{id = {'$1', '_','_'}, _='_'},
                                    [],
                                    ['$1']
                                   }]),
    case Pids -- lists:usort(Pids) of 
        [] -> ok;  %%  each process only has one calltree, the ideal case.
        Pids1   %% abnormal case.
              ->
            consolidate_calltree_2(lists:usort(Pids1)),
            ok
    end.
             
consolidate_calltree_2(Pids) ->
    lists:foreach(fun(Pid) ->
                          consolidate_calltree_3(Pid)
                  end, Pids).
consolidate_calltree_3(Pid) ->
    [Tree|Others]=ets:select(fun_calltree, [{#fun_calltree{id = {'$1', '_','_'}, _='_'},
                                             [{'==', '$1', Pid}],
                                             ['$_']
                                            }]),
    Key = Tree#fun_calltree.id,
    ets:update_element(fun_calltree, Key, {4, Others++Tree#fun_calltree.called}),
    lists:foreach(fun(T)-> ets:delete_object(fun_calltree, T) end, Others).
                          
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                       %%
%%  Generate statistic information about each function.  %%
%%                                                       %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
gen_fun_info_1()->        
    Ids=ets:select(fun_calltree, 
                   [{#fun_calltree{id = '$1', _='_'},
                     [], ['$1']}]),
    percept2_utils:pforeach(fun(Id) -> process_a_call_tree(Id) end, Ids),
    ok.

process_a_call_tree(Id) ->
    [Tree]=ets:lookup(fun_calltree, Id),
    process_a_call_tree_1(Tree).    

process_a_call_tree_1(CallTree) ->
    {Pid, MFA, Caller}=CallTree#fun_calltree.id,
    case MFA of 
        undefined ->
            Children=CallTree#fun_calltree.called,
            [process_a_call_tree_1(C)||C <- Children];
        _ ->
            update_fun_info({Pid, MFA}, 
                             {Caller, CallTree#fun_calltree.cnt},
                             [{element(2, C#fun_calltree.id),
                               C#fun_calltree.cnt}
                              ||C <- CallTree#fun_calltree.called],
                             CallTree#fun_calltree.start_ts,
                             CallTree#fun_calltree.end_ts),                             
            Children=CallTree#fun_calltree.called,
            [process_a_call_tree_1(C)||C <- Children]
    end.

select_query_fun_1(Query) ->
    case Query of 
        {code, Options} when is_list(Options) ->
            Head = #funcall_info{
              id={'$1', '$2'}, 
              end_ts='$3',
              _='_'},
            Body =  ['$_'],
            MinTs = proplists:get_value(ts_min, Options, undefined),
            MaxTs = proplists:get_value(ts_max, Options, undefined),
            Constraints = [{'not', {'orelse', {'>=',{const, MinTs},'$3'},
                                    {'>=', '$2', {const,MaxTs}}}}],
            ets:select(funcall_info, [{Head, Constraints, Body}]);
        {funs, Options} when Options==[] ->
            Head = #fun_info{
              id={'$1', '$2'}, 
              _='_'},
            Body =  ['$_'],
            Constraints = [],
            ets:select(fun_info, [{Head, Constraints, Body}]);
        {funs, Id={_Pid, _MFA}} ->
            Head = #fun_info{
              id=Id, 
              _='_'},
            Body =  ['$_'],
            Constraints = [],
            ets:select(fun_info, [{Head, Constraints, Body}]);
        {calltime, Pid} ->
            Head = #fun_info{id={Pid,'$1'} ,
                             _='_', call_count='$2',
                             acc_time='$3'},
            Constraints = [],
            Body =[{{{{Pid,'$3'}}, '$1', '$2'}}],
            ets:select(fun_info, [{Head, Constraints, Body}]);
        Unhandled ->
	    io:format("select_query_func, unhandled: ~p~n", [Unhandled]),
	    []
    end.       
update_fun_call_count_time({Pid, Func}, {StartTs, EndTs}) ->
    Time = ?seconds(EndTs, StartTs),
    case ets:lookup(fun_info, {Pid, Func}) of 
        [] ->
            ets:insert(fun_info, #fun_info{id={Pid, Func}, 
                                           call_count=1, 
                                           acc_time=Time});
        [FunInfo] ->
            ets:update_element(fun_info, {Pid, Func}, 
                               [{7, FunInfo#fun_info.call_count+1},
                                {8, FunInfo#fun_info.acc_time+Time}])
    end.

update_fun_info({Pid, MFA}, Caller, Called, StartTs, EndTs) ->
    case ets:lookup(fun_info, {Pid, MFA}) of
        [] ->
            NewEntry=#fun_info{id={Pid, MFA},
                               callers = [Caller],
                               called = Called,
                               start_ts= StartTs, 
                               end_ts = EndTs},
            ets:insert(fun_info, NewEntry);
        [FunInfo] ->
            NewFunInfo=FunInfo#fun_info{
                         callers=add_to([Caller],
                                        FunInfo#fun_info.callers),
                         called = add_to(Called,FunInfo#fun_info.called),
                         start_ts = lists:min([FunInfo#fun_info.start_ts,StartTs]),
                         end_ts = lists:max([FunInfo#fun_info.end_ts,EndTs])},
            ets:insert(fun_info, NewFunInfo)
    end.

add_to(FunCNTPairs, Acc) ->
    lists:foldl(fun({Fun, CNT},Out) ->
                       add_to_1({Fun, CNT}, Out)
               end, Acc, FunCNTPairs).
add_to_1({Fun, CNT}, Acc) ->
    case lists:keyfind(Fun, 1, Acc) of 
        false ->
            [{Fun, CNT}|Acc];
        {Fun, CNT1} ->
            lists:keyreplace(Fun, 1, Acc, {Fun, CNT+CNT1})
    end.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                         

elapsed({Me1, S1, Mi1}, {Me2, S2, Mi2}) ->
    Me = (Me2 - Me1) * 1000000,
    S  = (S2 - S1 + Me) * 1000000,
    Mi2 - Mi1 + S.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                                      %% 
%%                Process Tree Graph Generlisation.                     %%
%%                                                                      %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%Todo: combine some nodes into one?
gen_process_tree_img() ->
    Pid=spawn_link(?MODULE, gen_process_tree_img_1, [self()]),
    receive
        {Pid, done, Result} ->
            Result
    end.

    
gen_process_tree_img_1(Parent)->
    Trees = gen_process_tree(),
    CompressedTrees = compress_process_tree(Trees),
    Res=gen_process_tree_img(CompressedTrees),
    Parent ! {self(), done, Res}.
    
compress_process_tree(Trees) ->
    compress_process_tree(Trees, []).

compress_process_tree([], Out)->
    lists:reverse(Out);
compress_process_tree([T|Ts], Out) ->
    T1=compress_process_tree_1(T),
    compress_process_tree(Ts, [T1|Out]).

compress_process_tree_1(Tree={_Parent, []}) ->
    Tree;
compress_process_tree_1(_Tree={Parent, Children}) ->
    CompressedChildren = compress_process_tree_2(Children),
    {Parent, CompressedChildren}.

compress_process_tree_2(Children) when length(Children)<3->
    compress_process_tree(Children);
compress_process_tree_2(Children) ->
    GroupByEntryFuns=group_by(1, 
                              [{clean_entry(C1#information.entry), {C1,  C2}}
                               ||{C1,C2}<-Children]),
    Res=[compress_process_tree_3(ChildrenGroup)||ChildrenGroup<-GroupByEntryFuns],
    lists:sort(fun({T1, _}, {T2, _}) -> 
                       T1#information.start > T2#information.start 
               end, lists:append(Res)).

compress_process_tree_3(ChildrenGroup) ->
    {[EntryFun|_], Children=[C={C0,_}|Cs]} =lists:unzip(ChildrenGroup),
    case length(Children) <3 of 
        true -> 
            compress_process_tree(Children);
        false ->
            UnNamedProcs=[C1#information.id||{C1,_}<-Children, 
                                             C1#information.name==undefined],
            case length(UnNamedProcs) == length(Children) of
                true ->
                    Num = length(Cs),
                    CompressedChildren=
                        #information{id=list_to_pid("<0.0.0>"),
                                     name=list_to_atom(integer_to_list(Num)++" procs omitted"),
                                     parent=C0#information.parent,
                                     entry = EntryFun,
                                     start =lists:min([C1#information.start||{C1,_}<-Cs]),
                                     stop = lists:max([C1#information.stop||{C1, _}<-Cs]),
                                     msgs_received=lists:foldl(fun({P,_}, {R1Acc, R2Acc}) ->
                                                                       {R1, R2}=P#information.msgs_received,
                                                                       {R1+R1Acc, R2+R2Acc}
                                                               end, {0,0}, Cs),
                                     msgs_sent = lists:foldl(fun({P, _}, {S1Acc, S2Acc}) ->
                                                                     {S1, S2} = P#information.msgs_sent,
                                                                     {S1+S1Acc, S2+S2Acc}
                                                             end, {0,0}, Cs)
                                    },
                    [compress_process_tree_1(C), {CompressedChildren,[]}];   
                false ->
                    compress_process_tree(Children)
            end
    end.

        

gen_process_tree_img([]) ->
    no_image;
gen_process_tree_img(ProcessTrees) ->
    BaseName = "processtree",
    DotFileName = BaseName++".dot",
    SvgFileName = filename:join(
                    [code:priv_dir(percept2), "server_root",
                     "images", BaseName++".svg"]),
    ok=process_tree_to_dot(ProcessTrees,DotFileName),
    os:cmd("dot -Tsvg " ++ DotFileName ++ " > " ++ SvgFileName),
    file:delete(DotFileName),
    ok.
            
process_tree_to_dot(ProcessTrees, DotFileName) ->
    {Nodes, Edges} = gen_process_tree_nodes_edges(ProcessTrees),
    MG = digraph:new(),
    digraph_add_edges_to_process_tree({Nodes, Edges}, MG),
    process_tree_to_dot_1(MG, DotFileName),
    digraph:delete(MG),
    ok.

gen_process_tree_nodes_edges(Trees) ->
    Res = percept2_utils:pmap(
            fun(Tree) ->
                    gen_process_tree_nodes_edges_1(Tree) 
            end,  Trees),
    {Nodes, Edges}=lists:unzip(Res),
    {lists:append(Nodes), lists:append(Edges)}.

gen_process_tree_nodes_edges_1({Parent, []}) ->
    Parent1={Parent#information.id, Parent#information.name,
              clean_entry(Parent#information.entry)},
    {[Parent1], []};
gen_process_tree_nodes_edges_1({Parent, Children}) -> 
    Parent1={Parent#information.id, Parent#information.name,
             clean_entry(Parent#information.entry)},
    %% Children1=[{C#information.id, C#information.name,
    %%             clean_entry(C#information.entry), process_tree_size(C1)}||C1={C, _}<-Children],
    %% {Nodes, Edges, IgnoredPids} = group_edges(Parent1, Children1),
    %% RemainedChildren=[Tree||Tree={P, _}<-Children, 
    %%                         not lists:member(P#information.id,
    %%                                          IgnoredPids)],
    Nodes = [{C#information.id, C#information.name,
              clean_entry(C#information.entry)}||{C, _}<-Children],
    Edges = [{Parent1, N, ""}||N<-Nodes],
    {Nodes1, Edges1}=gen_process_tree_nodes_edges(Children),
    {[Parent1|Nodes]++Nodes1, Edges++Edges1}.
             
process_tree_size(Tree) ->
    case Tree of
        {_, []} ->
            1;
        {_, Ts} ->
            1+length(Ts)+lists:sum([process_tree_size(T)||T<-Ts])
    end.
         

clean_entry({M, F, Args}) when is_list(Args) ->
    {M, F, length(Args)};
clean_entry(Entry) -> Entry.

group_edges(Parent, Children) ->
    ChildrenGroupedByName = group_by(2, Children),
    Res = [group_edges_1(Parent, ChildrenWithSameName)||
              ChildrenWithSameName<-ChildrenGroupedByName],
    {Nodes, Edges, Ignored}=lists:unzip3(lists:append(Res)),
    {lists:append(Nodes), lists:append(Edges), lists:append(Ignored)}.
  
    
group_edges_1(Parent, ChildrenWithSameName) ->
    ChildrenGroupedByEntry = group_by(3, ChildrenWithSameName),
    [group_edges_2(Parent, ChirdreWithSameNameAndEntry)||
                      ChirdreWithSameNameAndEntry<-ChildrenGroupedByEntry].
group_edges_2(Parent, ChildrenWithSameNameAndEntry) ->
    [{Pid, Name, Entry, _Size}|Sibs] = lists:reverse(
                                         lists:keysort(
                                           4, ChildrenWithSameNameAndEntry)),
    C = {Pid, Name, Entry},
    case Sibs of 
        [] ->
            Nodes = [Parent, C],
            Edges = [{Parent, C, ""}],
            Ignored = [],
            {Nodes, Edges, Ignored};        
        [Sib] ->
            Nodes = [Parent, C, Sib],
            Edges = [{Parent, C, ""}, {Parent, Sib, ""}],
            Ignored = [],
            {Nodes, Edges, Ignored};            
        _ ->
            %% Name must be 'undefined' here.
            Name1= list_to_atom(integer_to_list(length(Sibs)++" procs omitted")),
            DummyNode ={'...', Name1, Entry},
            Nodes = [Parent, C, DummyNode],
            Edges =[{Parent, C, ""}, 
                    {Parent, DummyNode, length(Sibs)}],
            Ignored = [Id||{Id, _, _, _}<-Sibs],
            {Nodes, Edges, Ignored}
    end.
         
digraph_add_edges_to_process_tree({Nodes, Edges}, MG) ->
    %% This cannot be parallelised because of side effects.
    [digraph:add_vertex(MG, Node)||Node<-Nodes],
    [digraph_add_edge_1(MG, From, To, Label)||{From, To, Label}<-Edges].

%% a function with side-effect.
digraph_add_edge_1(MG, From, To, Label) ->
    case digraph:vertex(MG, To) of 
        false ->
            digraph:add_vertex(MG, To);
        _ ->
            ok
    end,
    digraph:add_edge(MG, From, To, Label).

process_tree_to_dot_1(MG, OutFileName) ->
    Edges =[digraph:edge(MG, X) || X <- digraph:edges(MG)],
    Nodes = digraph:vertices(MG),
    GraphName="ProcessTree",
    Start = ["digraph ",GraphName ," {"],
    VertexList = [format_process_tree_node(N) ||N <- Nodes],
    End = ["graph [", GraphName, "=", GraphName, "]}"],
    EdgeList = [format_process_tree_edge(X, Y, Label) ||{_, X, Y, Label} <- Edges],
    String = [Start, VertexList, EdgeList, End],
    ok = file:write_file(OutFileName, list_to_binary(String)).

format_process_tree_node(V) ->
    String = format_process_tree_vertex(V),
    {Width, Heigth} = calc_dim(String),
    W = (Width div 7 + 1) * 0.55,
    H = Heigth * 0.4,
    SL = io_lib:format("~f", [W]),
    SH = io_lib:format("~f", [H]),
    ["\"", String, "\"", " [width=", SL, " heigth=", SH, " ", "", "];\n"].
            
format_process_tree_vertex({Pid, Name, Entry}) ->
    lists:flatten(io_lib:format("~p; ~p;\\n~p",
                                [Pid, Name, Entry]));
format_process_tree_vertex(Other)  ->
     io_lib:format("~p", [Other]).
    
format_process_tree_edge(V1, V2, Label) ->
    String = ["\"",format_process_tree_vertex(V1),"\"", " -> ",
	      "\"", format_process_tree_vertex(V2), "\""],
    [String, " [", "label=", "\"", format_label(Label),  
     "\"",  "fontsize=20 fontname=\"Verdana\"", "];\n"].
          
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                                      %% 
%%                Callgraph Generlisation.                              %%
%%                                                                      %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

gen_callgraph_img(Pid) ->
    Res=ets:select(fun_calltree, 
                      [{#fun_calltree{id = {'$1', '_','_'}, _='_'},
                        [{'==', '$1', Pid}],
                        ['$_']
                       }]),
    case Res of 
        [] -> no_image;
        [Tree] -> gen_callgraph_img_1(Pid, Tree)
    end.
   
gen_callgraph_img_1(Pid, CallTree) ->
    String = lists:flatten(io_lib:format("~p", [Pid])),
    PidStr=lists:sublist(String, 2, erlang:length(String)-2),
    BaseName = "callgraph"++PidStr,
    DotFileName = BaseName++".dot",
    SvgFileName = filename:join(
                    [code:priv_dir(percept2), "server_root",
                     "images", BaseName++".svg"]),
    fun_callgraph_to_dot(CallTree,DotFileName),
    os:cmd("dot -Tsvg " ++ DotFileName ++ " > " ++ SvgFileName),
    file:delete(DotFileName),
    ok.

fun_callgraph_to_dot(CallTree, DotFileName) ->
    Edges=gen_callgraph_edges(CallTree),
    MG = digraph:new(),
    digraph_add_edges(Edges, [], MG),
    to_dot(MG,DotFileName),
    digraph:delete(MG).

gen_callgraph_edges(CallTree) ->
    {_, CurFunc, _} = CallTree#fun_calltree.id,
    ChildrenCallTrees = CallTree#fun_calltree.called,
    lists:foldl(fun(Tree, Acc) ->
                        {_, ToFunc, _} = Tree#fun_calltree.id,
                        NewEdge = {CurFunc, ToFunc, Tree#fun_calltree.cnt},
                        [[NewEdge|gen_callgraph_edges(Tree)]|Acc]
                end, [], ChildrenCallTrees).

%%depth first traveral.
digraph_add_edges([], NodeIndex, _MG)-> 
    NodeIndex;
digraph_add_edges(Edge={_From, _To, _CNT}, NodeIndex, MG) ->
    digraph_add_edge(Edge, NodeIndex, MG);
digraph_add_edges([Edge={_From, _To, _CNT}|Children], NodeIndex, MG) ->
    NodeIndex1=digraph_add_edge(Edge, NodeIndex, MG),
    lists:foldl(fun(Tree, IndexAcc) ->
                        digraph_add_edges(Tree, IndexAcc, MG)
                end, NodeIndex1, Children);
digraph_add_edges(Trees=[Tree|_Ts], NodeIndex, MG) when is_list(Tree)->
    lists:foldl(fun(T, IndexAcc) ->
                        digraph_add_edges(T, IndexAcc, MG)
                end, NodeIndex, Trees).
        
   
digraph_add_edge({From, To,  CNT}, IndexTab, MG) ->
    {From1, IndexTab1}=
        case digraph:vertex(MG, {From,0}) of 
            false ->
                digraph:add_vertex(MG, {From,0}),
                {{From, 0}, [{From, 0}|IndexTab]};
            _ ->
                {From, Index}=lists:keyfind(From, 1, IndexTab),
                {{From, Index}, IndexTab}
        end,
     {To1, IndexTab2}= 
        case digraph:vertex(MG, {To,0}) of 
            false ->
                digraph:add_vertex(MG, {To,0}),
                {{To, 0}, [{To,0}|IndexTab1]};                          
            _ -> 
                {To, Index1} = lists:keyfind(To, 1,IndexTab1),
                case digraph:get_path(MG, {To, Index1}, From1) of 
                    false ->
                        digraph:add_vertex(MG, {To, Index1+1}),
                        {{To,Index1+1},lists:keyreplace(To,1, IndexTab1, {To, Index1+1})};
                    _ ->
                        {{To, Index1}, IndexTab1}
                end
        end,
    digraph:add_edge(MG, From1, To1, CNT),
    IndexTab2.
   

to_dot(MG, File) ->
    Edges = [digraph:edge(MG, X) || X <- digraph:edges(MG)],
    EdgeList=[{{X, Y}, Label} || {_, X, Y, Label} <- Edges],
    EdgeList1 = combine_edges(lists:keysort(1,EdgeList)),
    edge_list_to_dot(EdgeList1, File, "CallGraph").
    		
combine_edges(Edges) ->	
    combine_edges(Edges, []).
combine_edges([], Acc) ->		
    Acc;
combine_edges([{{X,Y}, Label}|Tl], [{X,Y, Label1}|Acc]) ->
    combine_edges(Tl, [{X, Y, Label+Label1}|Acc]);
combine_edges([{{X,Y}, Label}|Tl], Acc) ->
    combine_edges(Tl, [{X, Y, Label}|Acc]).
   
edge_list_to_dot(Edges, OutFileName, GraphName) ->
    {NodeList1, NodeList2, _} = lists:unzip3(Edges),
    NodeList = NodeList1 ++ NodeList2,
    NodeSet = ordsets:from_list(NodeList),
    Start = ["digraph ",GraphName ," {"],
    VertexList = [format_node(V) ||V <- NodeSet],
    End = ["graph [", GraphName, "=", GraphName, "]}"],
    EdgeList = [format_edge(X, Y, Label) || {X,Y,Label} <- Edges],
    String = [Start, VertexList, EdgeList, End],
    ok = file:write_file(OutFileName, list_to_binary(String)).

format_node(V) ->
    String = format_vertex(V),
    {Width, Heigth} = calc_dim(String),
    W = (Width div 7 + 1) * 0.55,
    H = Heigth * 0.4,
    SL = io_lib:format("~f", [W]),
    SH = io_lib:format("~f", [H]),
    ["\"", String, "\"", " [width=", SL, " heigth=", SH, " ", "", "];\n"].

format_vertex(undefined) ->
    "undefined";
format_vertex({M,F,A}) ->
    io_lib:format("~p:~p/~p", [M,F,A]);
format_vertex({undefined, _}) ->
    "undefined";
format_vertex({{M,F,A},C}) ->
    io_lib:format("~p:~p/~p(~p)", [M,F,A, C]).

calc_dim(String) ->
  calc_dim(String, 1, 0, 0).

calc_dim("\\n" ++ T, H, TmpW, MaxW) ->
    calc_dim(T, H + 1, 0, wrangler_misc:max(TmpW, MaxW));
calc_dim([_| T], H, TmpW, MaxW) ->
    calc_dim(T, H, TmpW+1, MaxW);
calc_dim([], H, TmpW, MaxW) ->
    {wrangler_misc:max(TmpW, MaxW), H}.

format_edge(V1, V2, Label) ->
    String = ["\"",format_vertex(V1),"\"", " -> ",
	      "\"", format_vertex(V2), "\""],
    [String, " [", "label=", "\"", format_label(Label),  "\"",  "fontsize=20 fontname=\"Verdana\"", "];\n"].


format_label(Label) when is_integer(Label) ->
    io_lib:format("~p", [Label]);
format_label(_Label) -> "".

    
group_by(N, TupleList) ->
    SortedTupleList = lists:keysort(N, lists:sort(TupleList)),
    group_by(N, SortedTupleList, []).

group_by(_N,[],Acc) -> Acc;
group_by(N,TupleList = [T| _Ts],Acc) ->
    E = element(N,T),
    {TupleList1,TupleList2} = 
	lists:partition(fun (T1) ->
				element(N,T1) == E
			end,
			TupleList),
    group_by(N,TupleList2,Acc ++ [TupleList1]).

%% fprof:apply(refac_sim_code_par_v0,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"], 8]). 

%% percept_profile:start({ip, 4711}, {refac_sim_code_par_v4,sim_code_detection, [["c:/cygwin/home/hl/percept/test"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/percept/test"], 8]}, [])  

%%percept_profile:start({file, "sim_code_v0.dat"}, {refac_sim_code_par_v0,sim_code_detection, [["c:/cygwin/home/hl/demo/c.erl"], 5, 40, 2, 4, 0.8, [], 8]}, [refac_sim_code_par_v0],[])
%% percept_profile:start({file, "foo3.dat"}, {foo,a1, [1]}, [foo], []).


%% percept2_db:gen_callgraph_img(list_to_pid("<0.1132.0>")).

%% percept2:profile({file, "mergesort.dat"}, {mergesort, msort_lte,[lists:reverse(lists:seq(1,2000))]}, [message, process_scheduling, concurrency,garbagage_collection,{function, [{mergesort, '_','_'}]}]).

%% percept2:analyze("mergesort.dat").

%% percept2:profile({file, "sim_code_v3.dat"}, {refac_sim_code_par_v3,sim_code_detection, [["c:/cygwin/home/hl/test"], 5, 40, 2, 4, 0.8, [], 8]},  [message, process_scheduling, concurrency,{function, [{refac_sim_code_par_v0, '_','_'}]}]).

%% To profile percept itself.
%% percept2:profile({file, "percept.dat"}, {percept2,analyze, ["sim_code_v2.dat"]},  [message, process_scheduling, concurrency,{function, [{percept2_db, '_','_'}, {percept2, '_','_'}]}]).
 %%percept2:analyze("percept.dat").


%%percept2:analyze("dialyzer.dat").
%% percept2:profile({file, "percept_process_img.dat"}, {percept2_db,gen_process_tree_img, []},  [message, process_scheduling, concurrency,{function, [{percept2_db, '_','_'}, {percept2, '_','_'}]}]).
%%percept2:analyze("percept_process_img.dat").


 %% percept2:analyze(["sim_code_v30.dat", "sim_code_v31.dat"]).
%%percept2_db:select({activity, []}).
