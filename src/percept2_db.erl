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

-export([start/1,
         stop/0,
         stop/1,
         insert/2,
         select/1,
         consolidate_db/0,
         gen_process_tree/0,
         gen_compressed_process_tree/0
        ]).
 
-export([is_dummy_pid/1, pid2value/1,
         pid2name/1,
        is_database_loaded/0, stop_sync/1]).

%% internal export
-export([trace_spawn/2, trace_exit/2, trace_register/2,
         trace_unregister/2, trace_getting_unlinked/2,
         trace_getting_linked/2, trace_link/2,
         trace_unlink/2, trace_in/2, trace_out/2,
         trace_out_exited/2, trace_out_exiting/2,
         trace_in_exiting/2, trace_receive/2, trace_send/2,
         trace_send_to_non_existing_process/2, 
         trace_open/2, trace_closed/2, trace_call/2,
         trace_return_to/2, trace_end_of_trace/2]).

-include("../include/percept2.hrl").

-define(STOP_TIMEOUT, 1000).

-compile(export_all).

%%% ------------------------%%%
%%% 	Type definitions    %%%
%%% ------------------------%%%

-type activity_option() ::
	{ts_min, timestamp()} | 
	{ts_max, timestamp()} | 
	{ts_exact, boolean()} |  
	{mfa, {atom(), atom(), byte()}} | 
	{state, active | inactive} | 
	{id, all | procs | ports | pid() | port()}.

-type scheduler_option() ::
	{ts_min, timestamp()} | 
	{ts_max, timestamp()} |
	{ts_exact, boolean()} |
	{id, scheduler_id()}.

-type system_option() :: start_ts | stop_ts.

-type information_option() ::
	all | procs | ports | pid() | port() | procs_count| ports_count.

-type inter_proc_option() ::
        all |{message_acts, {node(), node(), float(), float()}}.

-type inter_sched_option() ::
        all |{message_acts, {node(), node(), float(), float()}}.

-type filename()::file:filename().
%%% ------------------------%%%
%%% 	Interface functions %%%
%%% ------------------------%%%

%% @doc starts the percept database
-spec start([file:filename()]) ->{started, [{file:filename(), pid()}]} | 
                                 {restarted, [{file:filename(), pid()}]}.
start(TraceFileNames) ->
    case erlang:whereis(percept2_db) of
    	undefined ->
	    {started, do_start(TraceFileNames)};
	PerceptDB ->
	    {restarted, restart(TraceFileNames,PerceptDB)}
    end.

%% @private
%% @doc restarts the percept database.
-spec restart([file:filename()],pid())-> [{filename(), pid()}].
restart(TraceFileNames, PerceptDB)->
    stop(PerceptDB),
    do_start(TraceFileNames).

%% @private
%% @doc starts the percept database.
-spec do_start([filename()])->[{filename(), pid()}].
do_start(TraceFileNames)->
    Parent = self(),
    _Pid =spawn_link(fun() -> 
                             init_percept_db(Parent, TraceFileNames)
                     end),
    receive
        {percept2_db, started, FileNameSubDBPairs} ->
            FileNameSubDBPairs
    end.
    
%% @doc stops the percept2_db database.
-spec stop()->'not_started' | {pid(),'stopped'}.
stop()->
    stop(percept2_db).

%% @doc Stops a percept database.
-spec stop(pid()|atom()) -> 'not_started' | {pid(), 'stopped'}.
stop(Pid) when is_pid(Pid) ->
    Pid! {action, stop, self()},
    receive
        {Pid, stopped} ->
            {Pid, stopped}
    end;
stop(ProcRegName) ->
    case erlang:whereis(ProcRegName) of
        undefined -> 
            not_started;
        Pid -> 
            Pid ! {action, stop, self()},
            receive
                {Pid, stopped} ->
                    {Pid, stopped}
            end
    end.
-type regname()::atom().
-spec stop_sync(pid()|regname())-> true.
stop_sync(RegName) when is_atom(RegName) ->
    case whereis(RegName) of
        undefined -> 
            true;
        Pid ->
            stop_sync(Pid)
    end;
stop_sync(Pid)->
    MonitorRef = erlang:monitor(process, Pid),
    case stop(Pid) of 
        not_started -> true;
        {Pid, stopped} ->
            receive
                {'DOWN', MonitorRef, _Type, _Pid1, _Info}->
                    true;
                {'EXIT', _Pid1, _Info} ->
                    true
            after ?STOP_TIMEOUT->
                    erlang:demonitor(MonitorRef, [flush]),
                    exit(Pid, kill)
            end
    end.

-spec stop_percept_db([{filename(), pid()}]) -> stopped.
stop_percept_db(FileNameSubDBPairs) ->
    ok = stop_percept_sub_dbs(FileNameSubDBPairs),
    ets:delete(pdb_warnings),
    ets:delete(pdb_info),
    ets:delete(pdb_system),
    ets:delete(funcall_info),
    ets:delete(fun_calltree),
    ets:delete(fun_info),
    ets:delete(inter_proc),
    ets:delete(inter_sched),
    ets:delete(s_group),
    %% ets:delete(msg_queue_len),
    case ets:info(history_html) of
        undefined -> 
            stopped;
        _ ->
            ets:delete_all_objects(history_html),
            stopped
    end.

stop_percept_sub_dbs(FileNameSubDBPairs) ->
    percept2_utils:pforeach(
      fun({_FileName, SubDB}) ->
              true=stop_sync(SubDB)
      end, FileNameSubDBPairs).
    
is_database_loaded() ->
    whereis(percept2_db)/=undefined.

%% @doc Inserts a trace or profile message to the database.  
-spec insert(pid()|atom(), tuple()) -> ok.
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
-spec select({system, system_option()} | 
             {information, information_option()}| 
             {scheduler, scheduler_option()}|
             {activity, activity_option()} |
             {inter_node,inter_proc_option()}|
             {inter_proc,inter_proc_option()}|
             {inter_sched, inter_sched_option()}|
             {calltime, pid_value()}|
             {code, term()} |
             {funs, term()}) ->
                    term().
                 
select(Query) ->
    percept2_db ! {select, self(), Query},
    receive {result, Match} ->
            Match 
    end.
-spec consolidate_db() -> ok.
consolidate_db() ->
    percept2_db ! {action, self(), consolidate_db},
    receive
        {percept2_db, consolidate_done} ->
            ok
    end.

%%% ------------------------%%%
%%% 	Database loop       %%%
%%% ------------------------%%%

-spec init_percept_db(pid(), [filename()]) -> any().
init_percept_db(Parent, TraceFileNames) ->
    process_flag(trap_exit, true),
    register(percept2_db, self()),
    ets:new(pdb_warnings, [named_table, public, {keypos, 1}, ordered_set]),
    ets:new(pdb_info, [named_table, public, {keypos, #information.id}, set, 
                       {read_concurrency,true}, {write_concurrency,true}]),
    ets:new(pdb_system, [named_table, public, {keypos, 1}, set]),
    ets:new(funcall_info, [named_table, public, {keypos, #funcall_info.id}, 
                           ordered_set]),
    ets:new(fun_calltree, [named_table, public, {keypos, #fun_calltree.id}, 
                           set,{read_concurrency,true}, {write_concurrency, true}]),
    ets:new(fun_info, [named_table, public, {keypos, #fun_info.id}, 
                       set,{read_concurrency, true},{write_concurrency,true}]),
    ets:new(inter_proc, [named_table, public, 
                         {keypos,#inter_proc.timed_from}, ordered_set]),
    ets:new(inter_sched, [named_table, public, 
                          {keypos, #inter_sched.from_sched_with_ts}, ordered_set]),
    ets:new(s_group, [named_table, public, {keypos,#s_group_info.timed_node}, 
                      ordered_set, {read_concurrency, true},
                      {write_concurrency, true}]),                      
    FileNameSubDBPairs=start_percept_sub_dbs(TraceFileNames),
    Parent!{percept2_db, started, FileNameSubDBPairs},
    loop_percept_db(FileNameSubDBPairs).

loop_percept_db(FileNameSubDBPairs) ->
    receive
     	{select, Pid, Query} ->
            Res = percept_db_select_query(FileNameSubDBPairs, Query),
            Pid ! {result, Res},
	    loop_percept_db(FileNameSubDBPairs);
	{action, stop, From} ->
            stop_percept_db(FileNameSubDBPairs),
            From ! {self(), stopped};
	{action, From, consolidate_db} ->
            ok=consolidate_db(FileNameSubDBPairs),
            From ! {percept2_db, consolidate_done},
	    loop_percept_db(FileNameSubDBPairs);
        {operate, Pid, {Table, {Fun, Start}}} ->
	    Result = ets:foldl(Fun, Start, Table),
	    Pid ! {result, Result},
	    loop_percept_db(FileNameSubDBPairs);
        {'EXIT', _, normal} ->
            loop_percept_db(FileNameSubDBPairs);
	_Unhandled -> 
	    ?dbg(0, "loop_percept_db, unhandled query: ~p~n", [_Unhandled]),
	    loop_percept_db(FileNameSubDBPairs)
    end.

loop_percept_sub_db(SubDBIndex) ->
    receive
        {insert, Trace} ->
            insert_trace(SubDBIndex,Trace),
            loop_percept_sub_db(SubDBIndex);
        {select, Pid, Query} ->
            Pid ! {self(), percept_sub_db_select_query(SubDBIndex, Query)},
            loop_percept_sub_db(SubDBIndex);
        {action, stop, From} ->
            stop_a_percept_sub_db(SubDBIndex),
            From ! {self(), stopped};
        {'EXIT', _, normal} ->
            loop_percept_sub_db(SubDBIndex);
        Unhandled ->
            io:format("loop_percept_sub_db, unhandled:~p~n", [Unhandled]),
            loop_percept_sub_db(SubDBIndex)
    end.

start_percept_sub_dbs(TraceFileNames) ->
    Self = self(),
    IndexList = lists:seq(1, length(TraceFileNames)),
    IndexedTraceFileNames = lists:zip(IndexList, TraceFileNames),
    lists:map(fun({Index, FileName})->
                      SubDBPid = spawn_link(fun()->
                                                    start_a_percept_sub_db(Self, {Index, FileName})
                                            end),
                      receive
                          {percept_sub_db_started, {FileName, SubDBPid}} ->
                              {FileName, SubDBPid}
                      end                      
              end, IndexedTraceFileNames).

start_a_percept_sub_db(Parent, {Index, TraceFileName}) ->
    process_flag(trap_exit, true),
    Scheduler = mk_proc_reg_name("pdb_scheduler", Index),
    Activity = mk_proc_reg_name("pdb_activity", Index),
    ProcessInfo = mk_proc_reg_name("pdb_info", Index),
    System = mk_proc_reg_name("pdb_system", Index),
    FuncInfo = mk_proc_reg_name("pdb_func", Index),
    Warnings = mk_proc_reg_name("pdb_warnings", Index),
    ?dbg(0,"starting a percept_sub_db...\n", []),
    start_child_process(Scheduler, fun init_pdb_scheduler/2),
    start_child_process(Activity, fun init_pdb_activity/2),
    start_child_process(ProcessInfo, fun init_pdb_info/2),
    start_child_process(System, fun init_pdb_system/2),
    start_child_process(FuncInfo, fun init_pdb_func/2),
    start_child_process(Warnings, fun init_pdb_warnings/2),
    put({runnable, procs}, 0),
    put({runnable, ports}, 0),
    put(runnable_states, []),
    Parent ! {percept_sub_db_started, {TraceFileName, self()}},
    loop_percept_sub_db(Index).

start_child_process(ProcRegName, Fun) ->
    Parent=self(),
    _Pid=spawn_link(fun() -> Fun(ProcRegName, Parent) end),
    receive
        {ProcRegName, started} ->
            ?dbg(0, "Process ~p started, Pid:~p\n", [ProcRegName, _Pid]),
            ok;
        Unhandled ->
            io:format("start_child_process, unhandled:~p~n", [Unhandled])
    end.

-spec stop_a_percept_sub_db(integer()) -> true.
stop_a_percept_sub_db(SubDBIndex) ->
    Scheduler = mk_proc_reg_name("pdb_scheduler", SubDBIndex),
    Activity = mk_proc_reg_name("pdb_activity", SubDBIndex),
    ProcessInfo = mk_proc_reg_name("pdb_info", SubDBIndex),
    System = mk_proc_reg_name("pdb_system", SubDBIndex),
    FuncInfo = mk_proc_reg_name("pdb_func", SubDBIndex),
    Warnings = mk_proc_reg_name("pdb_warnings", SubDBIndex),
    true = stop_sync(Scheduler),
    true = stop_sync(Activity),
    true = stop_sync(ProcessInfo),
    true = stop_sync(System),
    true = stop_sync(FuncInfo),
    true = stop_sync(Warnings).      


%%% -----------------------------%%%
%%%        query database        %%%
%%% -----------------------------%%%
%%% select_query
%%% In:
%%%	Query = {InfoType, Option}
%%%	InfoType = system | activity | scheduler |
%%                 information |code | funs      |
%%                 calltime
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
        {inter_node, _} ->
            select_query_message(Query);
        {inter_proc, _} ->
            select_query_message(Query);
        {inter_sched, _} ->
            select_query_inter_sched(Query);
        Unhandled ->
	    io:format("percept_db_select_query, unhandled: ~p~n", [Unhandled]),
	    []
    end.

percept_sub_db_select_query(SubDBIndex, Query) ->
    ?dbg(0, "Subdb query:\n~p\n", [{SubDBIndex, Query}]),
    case Query of 
        {activity, _ } -> 
	    select_query_activity_1(SubDBIndex, Query);
        {scheduler, _} ->
            select_query_scheduler_1(SubDBIndex, Query);
        Unhandled ->
	    io:format("percept_sub_db_select_query, unhandled: ~p~n", [Unhandled]),
	    []
    end.

select_query_inter_sched(Query) ->
    case Query of
        {inter_sched, all} ->
            Head = #inter_sched{from_sched_with_ts={'$0', '$1'},
                                dest_sched = '$2',
                               _='_'},
            Constraints = [],
            Body =  [['$1', '$2']],
            Nodes=ets:select(inter_sched, [{Head, Constraints, Body}]),
            sets:to_list(sets:from_list(lists:append(Nodes)));
        Unhandled ->
	    io:format("select_query_inter_sched, unhandled: ~p~n", 
                      [Unhandled]),
	    []
    end.
select_query_message(Query) ->
    case Query of
        {inter_node, all} ->
            Head = #information{node='$0',
                                _='_'},
            Constraints = [{'/=', '$0','nonode'}],
            Body =  ['$0'],
            Res=ets:select(pdb_info, [{Head, Constraints, Body}]),
            lists:usort(Res);
        {inter_node, {message_acts, {FromNode1, ToNode1, MinTs, MaxTs}}} ->
            FromNode = list_to_atom(FromNode1),
            ToNode = list_to_atom(ToNode1),
            Head = #inter_proc{timed_from={'$0', FromNode, '_'},
                               to = {ToNode, '_'},
                               msg_size = '$2',
                               _='_'},
            Constraints = [{'>=', '$0', {MinTs}}, {'=<', '$0', {MaxTs}}],
            Body =  [{{'$0', '$2'}}],
            ets:select(inter_proc, [{Head, Constraints, Body}]);
        Unhandled ->
	    io:format("select_query_inter_node, unhandled: ~p~n", 
                      [Unhandled]),
	    []
    end.

select_query_func(Query) ->
    case Query of 
        {code, Options} when is_list(Options) ->
                      Head = #funcall_info{
                        id={'$1', '$2', '$3'}, 
                        _='_'},
            Body =  ['$_'],
            MinTs = proplists:get_value(ts_min, Options, undefined),
            MaxTs = proplists:get_value(ts_max, Options, undefined),
            Pids =  proplists:get_value(pids, Options, undefined),
            Constraints = [{'not', {'orelse', {'>=',{const, MinTs},'$3'},
                                    {'>=', '$2', {const,MaxTs}}}}],
            case Pids of 
                [] ->
                    Head = #funcall_info{
                      id={'$1', '$2', '$3'}, 
                      _='_'},
                    ets:select(funcall_info, [{Head, Constraints, Body}]);
                _ ->
                    MS = [{#funcall_info{id={Pid, '$2', '$3'}, _='_'},
                           Constraints,
                           Body} || Pid<- Pids],
                    ets:select(funcall_info, MS)
            end;
        {funs, Options} when Options==[] ->
            Head = #fun_info{
              id={'$1','$2'}, 
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
        {calltime, Pid={pid,{P1,P2,P3}}}->
            Head = #fun_info{id={Pid,'$1'} ,
                             _='_', call_count='$2',
                             acc_time='$3'},
            Constraints = [],
            Body =[{{{{{{pid, {{P1,P2, P3}}}},'$3'}}, '$1', '$2'}}],
            ets:select(fun_info, [{Head, Constraints, Body}]);
        Unhandled ->
            io:format("select_query_func, unhandled: ~p~n", 
                      [Unhandled]),
	    []
    end.

%%%========================================%%%
%%%                                        %%%
%%% 	process trace events               %%%
%%%                                        %%%
%%%========================================%%%
-type dest()::pid()|port()|atom()|{atom, node()}.
-spec same_node_pids(dest(), dest()) -> boolean().

same_node_pids(Pid1, Pid2) 
  when is_pid(Pid1) andalso is_pid(Pid2)->
    Pid1Str = pid_to_list(Pid1),
    [P1,_,_] = string:tokens(Pid1Str,"."),
    Pid2Str = pid_to_list(Pid2),
    [P2,_,_] = string:tokens(Pid2Str, "."),
    P1 == P2;
same_node_pids(Pid1, Pid2) 
  when is_atom(Pid1);is_atom(Pid2) ->
    true;
same_node_pids({RegName, Node}, Pid2) 
  when is_pid(Pid2) ->
    same_node_pids(Pid2, {RegName, Node});
same_node_pids(Pid1, {_RegName, Node})
  when is_pid(Pid1)->
    case node(Pid1) of 
        nonode@nohost ->
            true;
        Node1 ->
            Node1 ==Node
    end;    
same_node_pids({_, Node1}, {_, Node2})->
    Node1 == Node2;
same_node_pids(_, _) -> true.

-spec get_node_name(port()|pid()|reference()|{atom(),node()})
                   -> node().
get_node_name({_RegName, Node}) ->    
    Node;
get_node_name(Arg) -> 
    try node(Arg) 
    catch _E1:_E2 ->
            nonode
    end.

insert_trace(SubDBIndex,Trace) ->
    case element(1, Trace) of
        trace_ts -> 
            Type=element(3, Trace),
            FunName = list_to_atom("trace_"++atom_to_list(Type)),
            ?MODULE:FunName(SubDBIndex, Trace);
        _ ->
            insert_profile_trace(SubDBIndex,Trace)
    end.                  

insert_profile_trace(SubDBIndex,Trace) ->
    case Trace of
        {profile_start, Ts} ->
            SystemProcRegName =mk_proc_reg_name("pdb_system", SubDBIndex),
            update_system_start_ts(SystemProcRegName,Ts);
        {profile_opts, Opts} ->
            SystemProcRegName =mk_proc_reg_name("pdb_system", SubDBIndex),
            update_system_profile_opts(SystemProcRegName, Opts);
        {profile_stop, Ts} ->
            SystemProcRegName =mk_proc_reg_name("pdb_system", SubDBIndex),
            update_system_stop_ts(SystemProcRegName,Ts);
        %% sometimes Mfa is 0. 
        {profile, Id, State, Mfa, TS} when is_pid(Id)  ->
            insert_profile_trace_1(SubDBIndex, Id, State,Mfa,TS,procs);
        {profile, Id, State, Mfa, TS} when is_port(Id) ->
            insert_profile_trace_1(SubDBIndex, Id, State, Mfa, TS, ports);
        {profile, scheduler, Id, State, NoScheds, Ts} ->
            Act= #scheduler{
              timestamp = Ts,
              id =  Id,
              state = State,
              active_scheds = NoScheds},
                                                % insert scheduler activity
            SchedulerProcRegName = mk_proc_reg_name("pdb_scheduler",
                                                    SubDBIndex),
            update_scheduler(SchedulerProcRegName, Act);
        _Unhandled ->
            ?dbg(0, "unhandled trace: ~p~n", [_Unhandled]),
            io:format("unhandled trace: ~p~n", [_Unhandled]),
            ok
    end.

insert_profile_trace_1(SubDBIndex, Id,State,Mfa,TS, procs) ->
    ActProcRegName = mk_proc_reg_name("pdb_activity", SubDBIndex),
    case check_activity_consistency(SubDBIndex, Id, State) of 
        invalid_state ->
            ok;
        valid_state ->
            InternalPid =pid2value(Id),
            case State of 
                active->
                    erlang:put({active, Id}, {TS, []});
                inactive ->  %% process changes to be inactive.
                    case erlang:get({active, Id}) of 
                        undefined ->
                            erlang:erase({in, Id}),
                            erlang:erase({active, Id});
                        {TS1, InOuts} ->
                            {TS1, InOuts}=erlang:get({active, Id}),
                            AccRunTime = calc_acc_runtime(TS1, lists:reverse(InOuts), TS),
                            InfoProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
                            update_information_acc_time(InfoProcRegName, {InternalPid,AccRunTime}),
                            update_activity(ActProcRegName, {update_inouts, InternalPid, TS1, InOuts}),
                            erlang:erase({in, Id}),
                            erlang:erase({active, Id})
                    end
            end,
            ProcRC = get_runnable_count(procs, State),
            PortRC = get({runnable, ports}),
            update_activity(ActProcRegName,
                            #activity{id =InternalPid,
                                      state = State,
                                      timestamp = TS,
                                      runnable_procs=ProcRC,
                                      runnable_ports=PortRC,
                                      where = Mfa})
    end;
insert_profile_trace_1(SubDBIndex, Id,State,Mfa,TS, ports) ->
    ProcRegName = mk_proc_reg_name("pdb_activity", SubDBIndex),
    case check_activity_consistency(SubDBIndex, Id, State) of 
        invalid_state ->
            ok;
        valid_state ->
            ProcRC = get({runnable, procs}),
            PortRC = get_runnable_count(ports, State),
            update_activity(ProcRegName,
                            #activity{id =Id,
                                      state = State,
                                      timestamp = TS,
                                      runnable_procs=ProcRC,
                                      runnable_ports=PortRC,
                                      where = Mfa})
    end.

calc_acc_runtime(ActiveST, [], InActiveST) -> elapsed(ActiveST, InActiveST);
calc_acc_runtime(ActiveST, [{out, TS}|InOuts], InActiveST) -> 
    calc_acc_runtime_1([{in, ActiveST},{out,TS}|InOuts], InActiveST,0);
calc_acc_runtime(_ActiveST, InOuts, InActiveST) ->
    calc_acc_runtime_1(InOuts, InActiveST,0).

calc_acc_runtime_1([],_InActiveST, Acc) -> Acc;
calc_acc_runtime_1([{in, TS1}, {out, TS2}|InOuts],InActiveST, Acc) ->
    calc_acc_runtime_1(InOuts, InActiveST, Acc+elapsed(TS1, TS2));
calc_acc_runtime_1([{in, TS1}], InActiveST, Acc) ->
    elapsed(TS1, InActiveST)+Acc.

check_activity_consistency(SubDBIndex, Id, State) ->
    RunnableStates = erlang:get(runnable_states),
    case lists:keyfind(Id,1,RunnableStates) of 
        {Id, State} ->  %% same state. 
            invalid_state;
        false when State == inactive andalso SubDBIndex==1 ->
             invalid_state;
        false ->
            NewState =[{Id, State}|RunnableStates],
            put(runnable_states, NewState),
            valid_state;
        _ ->
            NewState=lists:keyreplace(Id, 1, RunnableStates, {Id, State}),
            put(runnable_states, NewState),
            valid_state
    end.

trace_spawn(SubDBIndex, _Trace={trace_ts, Parent, spawn, Pid, Mfa, TS}) when is_pid(Pid) ->
    ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
    InformativeMfa = mfarity(mfa2informative(Mfa)),
    update_information(ProcRegName,
                       #information{id = pid2value(Pid), node=node(Pid),start = TS,
                                    parent = pid2value(Parent), entry = InformativeMfa}),
    update_information_child(ProcRegName, pid2value(Parent), Pid).

trace_exit(SubDBIndex,_Trace= {trace_ts, Pid, exit, _Reason, TS}) when is_pid(Pid)->
    FuncProcRegName = mk_proc_reg_name("pdb_func", SubDBIndex),
    FuncProcRegName ! {trace_exit, {Pid, TS}},
    ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
    insert_profile_trace_1(SubDBIndex, Pid, inactive, undefined, TS, procs), 
    update_information(ProcRegName, #information{id = pid2value(Pid), node=node(Pid), stop = TS}).

trace_register(SubDBIndex,_Trace={trace_ts, Pid, register, Name, _Ts}) when is_pid(Pid)->
    ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
    ets:insert(pdb_system, {{regname, Name}, pid2value(Pid)}),
    update_information(ProcRegName, #information{id = pid2value(Pid), node=node(Pid),
                                                 name = Name}).
 
trace_unregister(_SubDBIndex, _Trace)->
    ok.  

trace_getting_unlinked(_SubDBIndex, _Trace) ->
    ok.

trace_getting_linked(_SubDBIndex, _Trace) ->
    ok.
trace_link(_SubDBIndex,_Trace) ->
    ok.

trace_unlink(_SubDBIndex, _Trace) ->
    ok.

trace_in(SubDBIndex, _Trace={trace_ts, Pid, in, Rq, MFA, TS}) when is_pid(Pid)->
    ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
    case erlang:get({run_queue, Pid}) of 
        Rq ->
            ok;
        _ ->
            erlang:put({run_queue, Pid}, Rq),
            update_information_rq(ProcRegName, pid2value(Pid), {TS, Rq})
    end,
    process_trace_in(SubDBIndex, Pid, MFA, TS);
trace_in(SubDBIndex, _Trace={trace_ts, Pid, in, MFA, TS}) when is_pid(Pid)->
    process_trace_in(SubDBIndex, Pid, MFA, TS);
trace_in(_SubDBIndex, _Trace) ->
    ok.

process_trace_in(SubDBIndex, Pid, MFA, TS) ->
    FuncProcRegName = mk_proc_reg_name("pdb_func", SubDBIndex),
    FuncProcRegName ! {trace_in, {Pid, MFA, TS}},
    erlang:put({in, Pid}, TS),
    case erlang:get({active, Pid}) of 
        undefined ->
            %% process scheduling data is not recorded somehow.
            %% add activity data.
            erlang:put({active, Pid}, {TS,[]}),
            RunnableStates =erlang:get(runnable_states),
            NewState =[{Pid, active}|RunnableStates],
            put(runnable_states, NewState),
            ActProcRegName = mk_proc_reg_name("pdb_activity", SubDBIndex),
            RC = if SubDBIndex == 1 ->
                         get_runnable_count(procs, active);
                    true ->
                         get({runnable, procs})
                 end,
            update_activity(ActProcRegName,
                            #activity{id = pid2value(Pid),
                                      state = active,
                                      timestamp = TS,
                                      where = MFA,
                                      runnable_procs=RC, 
                                      runnable_ports=get({runnable, ports})});                                  
        {TS1, InOuts} ->
            erlang:put({active, Pid}, {TS1, [{in, TS}|InOuts]})
    end.
 
trace_out(SubDBIndex, _Trace={trace_ts, Pid, out, _Rq,  MFA, TS}) when is_pid(Pid) ->  
    process_trace_out(SubDBIndex, Pid, MFA, TS);
trace_out(SubDBIndex, _Trace={trace_ts, Pid, out, MFA, TS}) when is_pid(Pid) ->  
    process_trace_out(SubDBIndex,Pid, MFA, TS);
     
trace_out(_SubDBIndex, _Trace)->
    ok.

process_trace_out(SubDBIndex, Pid, MFA, TS) ->
    FuncProcRegName = mk_proc_reg_name("pdb_func", SubDBIndex),
    FuncProcRegName ! {trace_out, {Pid, MFA, TS}},
    InTime = case erlang:get({in, Pid}) of  
                 undefined -> %% sometime there is no 'in' trace.
                     case erlang:get({active, Pid}) of 
                         {Ts, _InOuts} -> Ts;
                         undefined -> undefined
                     end;
                 Ts -> Ts
             end,
    erlang:erase({in,Pid}),
    if InTime == undefined -> ok; %% this should not happen.
       true ->
            case erlang:get({active, Pid}) of
                undefined ->
                    ok;
                {TS1, InOuts} ->
                    erlang:put({active, Pid}, {TS1, [{out, TS}|InOuts]})
            end
    end.

elapsed({Me1, S1, Mi1}, {Me2, S2, Mi2}) ->
    Me = (Me2 - Me1) * 1000000,  
    S  = (S2 - S1 + Me) * 1000000,
    Mi2 - Mi1 + S.

%%{trace_ts, _Pid, out_exited, _, _, _Ts}
trace_out_exited(_SubDBIndex, _Trace)-> 
    ok.

%%{trace_ts, _Pid, out_exiting, _, _, _Ts}
trace_out_exiting(_SubDBIndex, _Trace) ->
    ok.
%%{trace_ts, _Pid, in_exiting, _, _, _Ts})
trace_in_exiting(_SubDBIndex, _Trace) ->
    ok.

%% trace_receive(SubDBIndex, _Trace={trace_ts, Pid, 'receive', Msg, MsgQueueLen, Ts}) ->
%%     if is_pid(Pid) ->
%%             ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
%%             ets:insert(msg_queue_len, #msg_queue_len{pid=Pid, 
%%                                                      timestamp=Ts,
%%                                                      len=MsgQueueLen}),
%%             update_information_received(ProcRegName, Pid, byte_size(term_to_binary(Msg)));
%%        true ->
%%             ok
%%     end;
trace_receive(SubDBIndex, _Trace={trace_ts, Pid, 'receive', Msg, _Ts}) ->
    if is_pid(Pid) ->
            ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
            update_information_received(ProcRegName, Pid, byte_size(term_to_binary(Msg)));
       true ->
            ok
    end.

trace_send(SubDBIndex,_Trace= {trace_ts, Pid, send, Msg, To, Ts}) ->
    if is_pid(Pid) ->
            ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
            MsgSize = byte_size(term_to_binary(Msg)),
            update_information_sent(ProcRegName, Pid, MsgSize, To, Ts);
           %% the following was for generating data about inter-scheduler 
           %% message passing data.
            %% if is_pid(To) ->
            %%         case erlang:get({run_queue, Pid}) of 
            %%             undefined -> ok;
            %%             FromRQ -> 
            %%                 case erlang:get({run_queue, To}) of 
            %%                     undefined -> 
            %%                         ok;
            %%                     ToRQ -> 
            %%                         update_inter_sched_msg_tab(FromRQ, ToRQ, MsgSize, Ts)
            %%                 end                        
            %%         end;
            %%    true -> ok
            %% end;       
       true ->
            ok
    end.

trace_send_to_non_existing_process(SubDBIndex,
                                   _Trace={trace_ts, Pid, send_to_non_existing_process, 
                                           Msg, _To, Ts})->
    if is_pid(Pid) ->
            ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
            update_information_sent(ProcRegName,Pid, byte_size(term_to_binary(Msg)), none, Ts);
       true ->
            ok
    end.

trace_open(SubDBIndex, _Trace={trace_ts, Caller, open, Port, Driver, TS})->
    ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
    update_information(ProcRegName, #information{
                         id = Port, entry = Driver, start = TS,
                         parent =  pid2value(Caller)}).

trace_closed(SubDBIndex,_Trace={trace_ts, Port, closed, _Reason, Ts})->
    ProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
    update_information(ProcRegName, #information{id = Port, stop = Ts}).

%% Dialyzer reports an error here, but I think Dialyzer thought the atom 
%% s_group used in the pattern is a record tag.
trace_call(_SubDBIndex, _Trace={trace_ts, Pid, call, {s_group, new_s_group, Args}, _, TS}) ->
    ets:insert(s_group, #s_group_info{timed_node={TS, get_node_name(Pid)}, 
                                 op={new_s_group, Args}});
trace_call(_SubDBIndex, _Trace={trace_ts, Pid, call, {s_group, delete_s_group, Args}, _, TS}) ->
    ets:insert(s_group, #s_group_info{timed_node={TS, get_node_name(Pid)}, 
                                 op={delete_s_group, Args}});
trace_call(_SubDBIndex, _Trace={trace_ts, Pid, call, {s_group, add_nodes, Args}, _, TS}) ->
    ets:insert(s_group, #s_group_info{timed_node={TS, get_node_name(Pid)}, 
                                 op={add_nodes, Args}});
trace_call(_SubDBIndex, _Trace={trace_ts, Pid, call, {s_group, remove_nodes, Args}, _, TS}) ->
    ets:insert(s_group, #s_group_info{timed_node={TS, get_node_name(Pid)}, 
                                 op={remove_nodes, Args}});
trace_call(SubDBIndex, _Trace={trace_ts, Pid, call, MFA, {cp, CP}, TS}) ->
    trace_call(SubDBIndex, Pid, MFA, TS, CP).

trace_return_to(SubDBIndex,_Trace={trace_ts, Pid, return_to, MFA, TS}) ->
    trace_return_to(SubDBIndex, Pid, MFA, TS).

trace_gc_start(SubDBIndex, {trace_ts, Pid, gc_start, _Info, TS}) ->
    FuncProcRegName = mk_proc_reg_name("pdb_func", SubDBIndex),
    erlang:put({gc_start, Pid}, TS),
    FuncProcRegName ! {trace_gc_start, {Pid, TS}},
    ok.

trace_gc_end(SubDBIndex, {trace_ts, Pid, gc_end, _Info, TS}) ->
    FuncProcRegName = mk_proc_reg_name("pdb_func", SubDBIndex),
    FuncProcRegName ! {trace_gc_end, {Pid, TS}},
    case erlang:get({gc_start, Pid}) of 
        undefined -> ok;
        TS1 -> 
            Time = now_diff(TS, TS1),
            InfoProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
            update_information_gc_time(InfoProcRegName, {pid2value(Pid), Time}),
            erlang:erase({gc_start, Pid}),
            ok
    end.
                

trace_end_of_trace(SubDBIndex, {trace_ts, Parent, end_of_trace}) ->
    ProcRegName =mk_proc_reg_name("pdb_func", SubDBIndex),
    ProcRegName ! {self(), end_of_trace_file},
    ActRegName=mk_proc_reg_name("pdb_activity", SubDBIndex),
    Data = erase(),
    [begin
         InfoProcRegName = mk_proc_reg_name("pdb_info", SubDBIndex),
         AccRunTime = calc_acc_runtime(TS, lists:reverse(InOuts), element(2, hd(InOuts))),
         update_information_acc_time(InfoProcRegName, {pid2value(Pid),AccRunTime}),
         update_activity(ActRegName, {update_inouts, pid2value(Pid), TS, InOuts})
     end
     ||{{active, Pid}, {TS,InOuts}}<-Data, InOuts/=[]],
    receive 
        {SubDBIndex, done} ->
            ?dbg(0, "Trace end of trace received done\n", []),
            Parent ! {self(), done}
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
        {action, stop, From} ->
            From ! {self(), stopped}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_activity               %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_activity(ProcRegName, Parent) ->
    register(ProcRegName, self()),
    ets:new(ProcRegName, [named_table, protected, 
                          {keypos, #activity.timestamp},
                          ordered_set]),
    Parent !{ProcRegName, started},
    pdb_activity_loop(ProcRegName).

update_activity(ProcRegName, Activity) ->
    ProcRegName ! {update_activity, {ProcRegName, Activity}}.
    

select_query_activity(FileNameSubDBPairs, Query) ->
    ?dbg(0, "select_query_activity:\n~p\n", [Query]),
    Res = percept2_utils:pmap(
            fun({_, SubDB}) ->
                    SubDB ! {select, self(), Query},
                    receive
                        {SubDB, Res} ->
                            Res
                    end
            end, FileNameSubDBPairs),
    case Query of 
        {activity,{min_max_ts, _}} ->
            {Mins,Maxs}=lists:unzip(lists:append(Res)),
            {case Mins of [] -> undefined; _ -> lists:min(Mins) end,
             case Maxs of [] -> undefined; _ -> lists:max(Maxs) end};
        _ ->
            lists:append(Res)
    end.

pdb_activity_loop(ProcRegName)->
    receive 
        {update_activity, {SubTab, {update_inouts, _Pid, TS, InOuts}}} ->
            ets:update_element(SubTab, TS, {#activity.in_out, InOuts}),
            pdb_activity_loop(ProcRegName);
        {update_activity, {SubTab,Activity}} ->
            ets:insert(SubTab, Activity),
            pdb_activity_loop(ProcRegName);
        {consolidate_runnability, {From, SubDBIndex, PreviourRC}} ->
            Tab=mk_proc_reg_name("pdb_activity", SubDBIndex),
            {ok, NewRC}=do_consolidate_runnability(Tab, PreviourRC), 
            From!{self(), done, NewRC},
            pdb_activity_loop(ProcRegName);
        {action, stop, From} ->
            case ets:info(ProcRegName) of 
                undefined -> ok;
                _ -> ets:delete(ProcRegName)
            end,            
            From ! {self(), stopped}
    end.


%% get_runnable_count(Type, Id, State) -> RunnableCount
%% In: 
%%	Type = procs | ports
%%	State = active | inactive
%% Out:
%%	RunnableCount = integer()
%% Purpose:
%%	Keep track of the number of runnable ports and processes
%%	during the profile duration.
get_runnable_count(Type, State) ->
    case {get({runnable, Type}), State} of 
        {N, active} ->
            put({runnable, Type}, N + 1),
            N + 1;
        {N, inactive} ->
            put({runnable, Type}, N - 1),
            N - 1;
        Unhandled ->
	    ?dbg(0, "get_runnable_count, unhandled ~p~n", [Unhandled]),
            Unhandled
    end.

%%% select_query_activity
select_query_activity_1(SubDBIndex, Query) ->
    case Query of
        {activity, {runnable, Pid}} ->
            get_runnable(SubDBIndex, Pid);
        {activity, {runnable_counts, Options}} ->
            get_runnable_counts(SubDBIndex, Options);
        {activity, {min_max_ts, Pids}} ->
            MS= [{#activity{timestamp ='$1', id=Pid, _='_'}, [], ['$1']}
                 ||Pid<-Pids],
            Tab = mk_proc_reg_name("pdb_activity", SubDBIndex),
            case ets:select(Tab, MS, 1) of 
                '$end_of_table'->[];
                {First, _Cont}->
                    {Last, _Cont1} = ets:select_reverse(Tab, MS, 1),
                    case First of 
                        [] -> [];
                        [F] ->
                            [Last1] = ets:lookup(Tab, hd(Last)),
                            LastTS = case Last1#activity.in_out of 
                                         [] -> hd(Last);
                                         _ ->element(2, hd(Last1#activity.in_out))
                                     end,
                            [{F, LastTS}]
                    end
            end;
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
                    Tab = mk_proc_reg_name("pdb_activity", SubDBIndex),
                    case catch ets:select(Tab, MS) of
                        {'EXIT', Reason} ->
	                    io:format(" - select_query_activity [ catch! ]: ~p~n", [Reason]),
			    [];
		    	Match ->
                            ?dbg(0, "~p items found in tab ~p~n", [length(Match), Tab]),
                            Match
		    end
	    end;
	Unhandled ->
	    io:format("select_query_activity, unhandled: ~p~n", [Unhandled]),
    	    []
    end.

get_runnable(SubDBIndex, _Pid={pid, {P1, P2, P3}}) ->
    MS = [{#activity{timestamp = '$1',id = '$2',state = '$3',in_out = '$4', _='_'},
           [{'==',  '$2',{{pid, {{P1, P2, P3}}}}}],
           [{{'$1', '$3', '$4'}}]}],
    Tab = mk_proc_reg_name("pdb_activity", SubDBIndex),
    case catch ets:select(Tab, MS) of
        {'EXIT', Reason} ->
            io:format(" - select_query_activity [ catch! ]: ~p~n", [Reason]),
            [];
        Match ->
            Match
    end.
       
    
%% This only works when all the procs/ports are selected.
get_runnable_counts(SubDBIndex, Options) ->
    MS = activity_count_ms(Options),
    Tab = mk_proc_reg_name("pdb_activity", SubDBIndex),
    case catch ets:select(Tab, MS) of
        {'EXIT', Reason} ->
            io:format(" - select_query_activity [ catch! ]: ~p~n", [Reason]),
            [];
        Match ->
            Match
    end.
         

select_query_activity_exact_ts(SubDBIndex, Options) ->
    case { proplists:get_value(ts_min, Options, undefined), 
           proplists:get_value(ts_max, Options, undefined) } of
	{undefined, undefined} -> [];
	{undefined, _        } -> [];
	{_        , undefined} -> [];
	{TsMin    , TsMax    } ->
            Tab = mk_proc_reg_name("pdb_activity", SubDBIndex),
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
    Head=#activity{timestamp = '$1',
                   id = '$2',
                   state = '$3',
                   where= '$4', 
                   runnable_procs='$5', 
                   runnable_ports='$6',
                   _='_'},
    Body = [{{activity, '$1', '$2', '$3', '$4', '$5', '$6',[]}}],
    {Conditions, IDs} = activity_ms_and(Head, Opts, [], []),
    Cond =  lists:foldl(
              fun (Option, Conds) ->
                      case Option of
                          {id, ports} ->
                              [{is_port, Head#activity.id}|Conds];
                          {id, procs} ->
                              [{'==', pid, {element, 1, Head#activity.id}} | Conds];
                          {id, ID} when is_port(ID) ->
                              [{'==', Head#activity.id, ID} | Conds];
                          {id, {pid, {P1, P2, P3}}}->
                              [{'==', Head#activity.id, {{pid, {{P1, P2, P3}}}}}| Conds];
                          {id, all} ->
                              Conds;
                          {pids, Pids}->
                              case length(Pids)/ets:info(pdb_info, size) <0.6 of 
                                  true ->
                                      [mk_pids_cond(Pids)|Conds];
                                  false ->
                                      AllPids = ets:select(
                                                  pdb_info,[{#information{id='$1', _='_'}, 
                                                             [{'not', {is_port, '$1'}}], ['$1']}]),
                                      OtherPids = AllPids -- Pids,
                                      case OtherPids of 
                                          [] -> 
                                              [{'==', pid, {element, 1, Head#activity.id}} | Conds];
                                          _ ->
                                              [{'==', pid, {element, 1, Head#activity.id}}, 
                                               {'not', mk_pids_cond(OtherPids)}|Conds]
                                      end
                              end;
                          _ ->
                              io:format("activity_ms id dropped ~p~n", [Option]),
                              Conds
                      end
              end, lists:reverse(Conditions), IDs),
    [{Head, lists:reverse(Cond), Body}].

mk_pids_cond(Pids) ->
    lists:foldl(fun({pid, {P1, P2, P3}},C) ->
                        if C == [] ->
                                {'==', '$2', {{pid, {{P1, P2, P3}}}}};
                           true -> {'orelse', {'==', '$2', {{pid, {{P1, P2, P3}}}}}, C}
                        end
                end, [], Pids).

activity_count_ms(Opts) ->
    Head = #activity{
      timestamp = '$1',
      id = '$2',
      runnable_procs='$3',
      runnable_ports ='$4',
      _ = '_'
     },
    {Conditions, IDs} = activity_ms_and(Head, Opts, [], []),
    Body = [{{'$1',{{'$3','$4'}}}}],
    lists:foldl(
      fun (Option, MS) ->
              case Option of
                  {id, ports} ->
                      [{Head, [{is_port, Head#activity.id}| Conditions], Body} | MS];
                  {id, procs} ->
                      [{Head,[{'==', pid, {element, 1, '$2'}}| Conditions], Body} | MS];
                  {id, all} ->
                      [{Head, Conditions,Body} | MS];
                  _ ->
                      io:format("activity_ms id dropped ~p~n", [Option]),
                      MS
              end
      end, [], IDs).

%% activity_ms_and(_, [], Constraints, []) ->
%%     {Constraints, [{id, all}]};
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
        {pids, Pids} ->
	    activity_ms_and(Head, Opts, 
		Constraints, [{pids, Pids} | IDs]);
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_scheduler              %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_scheduler(ProcRegName, Parent) ->
    register(ProcRegName, self()),
    ets:new(ProcRegName, [named_table, protected, 
                          {keypos, #scheduler.timestamp},
                          ordered_set]),
    Parent ! {ProcRegName, started},    
    pdb_scheduler_loop(ProcRegName).
    
update_scheduler(SchedulerProcRegName,Activity) ->
    SchedulerProcRegName ! {update_scheduler, 
                            {SchedulerProcRegName,Activity}}.

select_query_scheduler(FileNameSubDBPairs, Query) ->
    Res = percept2_utils:pmap(
            fun({_, SubDB}) ->
                    SubDB ! {select, self(), Query},
                    receive
                        {SubDB, Res} ->
                            Res
                    end
            end, FileNameSubDBPairs),
    lists:append(Res).

pdb_scheduler_loop(ProcRegName)->
    receive
        {update_scheduler, {SchedulerProcRegName,Activity}} ->
            ets:insert(SchedulerProcRegName, Activity),
            pdb_scheduler_loop(ProcRegName);
        {action, stop, From} ->
            case ets:info(ProcRegName) of 
                undefined -> 
                    ok;
                _ ->                     
                    ets:delete(ProcRegName)
            end,
            From ! {self(), stopped}
    end.

select_query_scheduler_1(SubDBIndex, Query) ->
    case Query of
	{scheduler, Options} when is_list(Options) ->
            Head = #scheduler{
	    	timestamp = '$1',
		id = '$2',
		state = '$3',
		active_scheds = '$4'
             },
	    Body = ['$_'],
	    % We don't need id's
            Constraints = scheduler_ms_and(Head, Options, []),
            Tab = mk_proc_reg_name("pdb_scheduler", SubDBIndex),
            ets:select(Tab, [{Head, Constraints, Body}]);
	Unhandled ->
	    io:format("select_query_scheduler_1, unhandled: ~p~n", [Unhandled]),
	    []
    end.

scheduler_ms_and(_, [], Constraints) -> 
    Constraints;
scheduler_ms_and(Head, [Opt|Opts], Constraints) ->
    case Opt of
	{ts_min, Min} ->
	    scheduler_ms_and(Head, Opts, 
                             [{'>=', Head#scheduler.timestamp, {Min}} | Constraints]);
        {ts_max, Max} ->
	    scheduler_ms_and(Head, Opts, 
                             [{'=<', Head#scheduler.timestamp, {Max}} | Constraints]);
	_ -> 
	    io:format("scheduler_ms_and option dropped ~p~n", [Opt]),
	    scheduler_ms_and(Head, Opts, Constraints)
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

update_information_sent(ProcRegName, From, MsgSize, To, Ts) ->
    ProcRegName!{update_information_sent, {From, MsgSize, To, Ts}}.

update_information_received(ProcRegName, Pid, MsgSize)->
    ProcRegName!{update_information_received, {Pid, MsgSize}}.

update_information_element(ProcRegName, Key, {Pos, Value}) ->
    ProcRegName! {update_information_element, {Key, {Pos, Value}}}.

update_information_acc_time(ProcRegName, {Key, Elapsed}) ->
    ProcRegName ! {update_information_acc_time, {Key, Elapsed}}.

update_information_gc_time(ProcRegName, {Pid, Time})->
    ProcRegName ! {update_information_gc_time, {Pid, Time}}.


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
        {update_information_sent, {From, MsgSize, To, Ts}} ->
            update_information_sent_1(From, MsgSize, To, Ts),
            pdb_info_loop();
        {update_information_received, {Pid, MsgSize}} ->
            update_information_received_1(Pid, MsgSize),
            pdb_info_loop();       
        {update_information_element, {Key, {Pos, Value}}} ->
            ets:update_element(pdb_info, Key, {Pos, Value}),
            pdb_info_loop();
        {update_information_acc_time, {Key, Value}} ->
            update_information_acc_time_1(Key, Value),
            pdb_info_loop();
        {update_information_gc_time, {Pid, Time}} ->
            update_information_gc_time_1(Pid, Time),
            pdb_info_loop();
        {action,stop, From} ->
            From ! {self(), stopped},
            ok
    end.

update_information_acc_time_1(Key, Value) ->
    case ets:lookup(pdb_info, Key) of 
        [] ->
            ets:insert(pdb_info, #information{id=Key, accu_runtime=Value});
        [_Info] ->
            ets:update_counter(pdb_info, Key, {#information.accu_runtime, Value})
    end.

update_information_gc_time_1(Pid, Time) ->
    case ets:lookup(pdb_info, Pid) of 
        [] ->
            ets:insert(pdb_info, #information{id=Pid, gc_time=Time});
        [_Info] ->
            ets:update_counter(pdb_info, Pid, {#information.gc_time, Time})
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

update_information_child_1(Id, ChildPid) ->
    InternalPid = pid2value(ChildPid),
    case ets:lookup(pdb_info, Id) of
    	[] ->
            ets:insert(pdb_info,#information{
                         id = Id,
                         children = [InternalPid]});
        [I] ->
            ets:insert(pdb_info,
                       I#information{
                         children = [InternalPid|I#information.children]})
    end.

update_information_rq_1(Pid, {TS,RQ}) ->
    case ets:lookup(pdb_info, Pid) of
        [] -> 
            ets:insert(pdb_info, #information{
                         id = pid2value(Pid),
                         rq_history=[{TS,RQ}]}),
            ok; %% this should not happen;
        [I] ->
            ets:update_element(
              pdb_info, Pid, {#information.rq_history, [{TS, RQ}|I#information.rq_history]})
    end.

%% with the parallel version, checking whether a message is 
%% send to the same run queue needs a different algorithm,
%% and this feature is removed for now.
update_information_sent_1(From, MsgSize, To, Ts) ->
    InternalFrom =pid2value(From),
    update_inter_proc_msg_tab(From, MsgSize, To, Ts),
    case ets:lookup(pdb_info, InternalFrom) of
        [] -> 
            ets:insert(pdb_info, 
                       #information{id=InternalFrom,
                                    node=node(From),
                                    msgs_sent={1, MsgSize}
                                   });            
        [I] ->
            {No, Size} =  I#information.msgs_sent,
            ets:update_element(pdb_info, InternalFrom, 
                               {#information.msgs_sent, {No+1, Size+MsgSize}})
    end.


update_inter_proc_msg_tab(_From, _MsgSize, To, _Ts) when is_port(To) ->
    ok;
update_inter_proc_msg_tab(From, MsgSize, To, Ts) ->
    InternalFrom=pid2value(From),
    InternalTo = if is_pid(To) ->
                         pid2value(To);
                    true ->To
                 end,
    ets:insert(inter_proc, 
               #inter_proc{
                 timed_from = {Ts, get_node_name(From), InternalFrom},
                 to={get_node_name(To), InternalTo},
                 msg_size = MsgSize}).

  
update_information_received_1(Pid, MsgSize) ->
    Pid1=pid2value(Pid),
    case  ets:lookup(pdb_info, Pid1) of
        [] -> 
            ets:insert(pdb_info, #information{
                         id =Pid1,
                         node = node(Pid),
                         msgs_received ={1, MsgSize}
                        });
        [I] ->
            {No, Size} = I#information.msgs_received,
            ets:update_element(pdb_info, Pid1,
                               {#information.msgs_received, {No+1, Size+MsgSize}})
    end.

select_query_information(Query) ->
    case Query of
    	{information, all} -> 
	    ets:select(pdb_info, [{
		#information{ _ = '_'},
		[],
		['$_']
		}]);
	{information, procs} ->
	    ets:select(pdb_info, [{
		#information{id = {pid,'$1'}, _ = '_'},
                [],
		['$_']
		}]);
        {information, procs_count} ->
             ets:select_count(pdb_info, [{
		#information{id = {pid, '$1'}, _ = '_'},
		[],
		[true]
		}]);
	{information, ports} ->
	    ets:select(pdb_info, [{
		#information{ id = '$1', _ = '_'},
		[{is_port, '$1'}],
		['$_']
		}]);
        {information, ports_count} ->
	    ets:select_count(pdb_info, [{
		#information{ id = '$1', _ = '_'},
		[{is_port, '$1'}],
		[true]
		}]);
        {information, {range_min_max, Ids}} ->
            StartStopTS=[ets:select(pdb_info, 
                                    [{#information{id = Id, start='$2', stop='$3', _ = '_'},
                                      [],
                                      [{{'$2', '$3'}}]
                                     }])||Id<-Ids],
            {Starts, Stops} = lists:unzip(lists:append(StartStopTS)),
            {lists:min(Starts), lists:max(Stops)};
        {information, Id} when is_port(Id) -> 
	    ets:select(pdb_info, [{
		#information{ id = Id, _ = '_'},
		[],
		['$_']
		}]);
        {information, Id={pid, _}} -> 
	    ets:select(pdb_info, [{
		#information{ id = Id, _ = '_'},
		[],
		['$_']
		}]);
        {information, dummy_pids} -> 
	    ets:select(pdb_info, [{
		#information{ id = {pid, '$1'}, _ = '_'},
		[{is_atom, {element, 2, '$1'}}],
		['$_']
		}]);
        {information, num_of_nodes} ->
            NodeIds=ets:select(pdb_info, 
                               [{#information{id={pid, {'$1', '_','_'}}, _='_'},
                                 [], ['$1']}]),
            length(sets:to_list(sets:from_list(NodeIds)));
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

update_system_profile_opts(SystemProcRegName, Opts)->
    SystemProcRegName ! {'update_system_profile_opts', Opts}.

update_system_stop_ts(SystemProcRegName, TS) ->
    SystemProcRegName ! {'update_system_stop_ts', TS}.

update_system_nodes_num(SystemProcRegName, Num) ->
    SystemProcRegName ! {'update_system_nodes_num', Num}.

pdb_system_loop() ->
    receive
        {'update_system_start_ts', TS}->
            update_system_start_ts_1(TS),
            pdb_system_loop();
        {'update_system_profile_opts', Opts}->
            ets:insert(pdb_system, {{system, profile_opts}, Opts}),
            pdb_system_loop();
        {'update_system_stop_ts', TS} ->
            update_system_stop_ts_1(TS),
            pdb_system_loop();
        {'update_system_nodes_num', Num} ->
            ets:insert(pdb_system, {{system, nodes}, Num});
        {action, stop, From} ->
            From ! {self(), stopped},
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
select_query_system(Query) ->
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
        {system, nodes} ->
            case ets:lookup(pdb_system, {system, nodes}) of
	    	[] -> 1;
		[{{system, nodes}, Num}] -> Num
	    end;
        {system, profile_opts} ->
            case ets:lookup(pdb_system, {system, profile_opts}) of 
                [] -> [];
                [{{system, profile_opts}, Opts}] -> Opts
            end;
	Unhandled ->
	    io:format("select_query_system, unhandled: ~p~n", [Unhandled]),
	    []
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_func                   %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_func(ProcRegName, Parent) ->
    register(ProcRegName, self()),
    Parent !{ProcRegName, started},
    "pdb_func" ++ Index = atom_to_list(ProcRegName),
    pdb_func_loop({Parent, list_to_integer(Index), [], [], false}).

trace_call(SubDBIndex, Pid, Func, TS, CP) ->
    ProcRegName =mk_proc_reg_name("pdb_func", SubDBIndex),
    ProcRegName ! {trace_call, {Pid, Func, TS, CP}}.

trace_return_to(SubDBIndex,Pid, MFA, TS) ->
    ProcRegName =mk_proc_reg_name("pdb_func", SubDBIndex),
    ProcRegName !{trace_return_to, {Pid, MFA, TS}}.

%% one pdb_func_loop for each trace file.
pdb_func_loop({SubDB, SubDBIndex, ChildrenProcs, PrevStacks, Done}) ->
    receive
        Trace={trace_call, _} ->
            NewChildrenProcs=pdb_func_loop_process_trace(
                               SubDBIndex, ChildrenProcs, PrevStacks, Trace),
            pdb_func_loop({SubDB, SubDBIndex, NewChildrenProcs, PrevStacks, Done});
        Trace={trace_return_to, _} ->
            NewChildrenProcs=pdb_func_loop_process_trace(
                               SubDBIndex, ChildrenProcs, PrevStacks, Trace),
            pdb_func_loop({SubDB, SubDBIndex, NewChildrenProcs, PrevStacks, Done});
        Trace={trace_out, _} ->
            pdb_func_loop_process_trace_1(ChildrenProcs,Trace),
            pdb_func_loop({SubDB, SubDBIndex, ChildrenProcs, PrevStacks, Done});
        Trace={trace_in, _} ->
            pdb_func_loop_process_trace_1(ChildrenProcs,Trace),
            pdb_func_loop({SubDB, SubDBIndex, ChildrenProcs, PrevStacks, Done});
        Trace={trace_exit, {Pid, _TS}} ->
            case lists:keyfind(Pid, 1, ChildrenProcs) of
                {Pid, Proc} ->
                    Proc ! {self(),Trace};
                false ->
                    ok
            end,
            pdb_func_loop({SubDB, SubDBIndex, ChildrenProcs, PrevStacks, Done});
        Trace={trace_gc_start, _Info} ->
            pdb_func_loop_process_trace_1(ChildrenProcs,Trace),
            pdb_func_loop({SubDB, SubDBIndex, ChildrenProcs, PrevStacks, Done});
        Trace={trace_gc_end, _Info} ->
            pdb_func_loop_process_trace_1(ChildrenProcs,Trace),
            pdb_func_loop({SubDB, SubDBIndex, ChildrenProcs, PrevStacks, Done});
        %% the current trace file gets to the end.
        {_Parent, end_of_trace_file} ->
            Self = self(),
            NextFuncRegName = mk_proc_reg_name("pdb_func", SubDBIndex+1),
            case whereis(NextFuncRegName) of 
                undefined -> ok;
                NextPid ->
                    [NextPid ! {end_of_trace_file, {SubDBIndex, Pid, Stack}}
                     ||{Pid, Stack}<-PrevStacks]
            end,
            case ChildrenProcs  of 
                [] -> 
                    SubDB ! {SubDBIndex,done};
                _ ->
                    [Proc!{Self, end_of_trace_file}
                     ||{_, Proc}<-ChildrenProcs]
            end,
            pdb_func_loop({SubDB, SubDBIndex,ChildrenProcs,[], true});
        {Pid, done} ->
            case lists:keydelete(Pid,1,ChildrenProcs) of
                [] ->
                    ?dbg(0, "All procs are done. SubdbIndex:~p\n", [{SubDB, SubDBIndex}]),
                    SubDB ! {SubDBIndex,done},
                    pdb_func_loop({SubDB, SubDBIndex,[], [], Done});
                NewChildrenProcs ->
                    pdb_func_loop({SubDB, SubDBIndex, lists:keydelete(Pid, 1, NewChildrenProcs),
                                   lists:keydelete(Pid, 1, PrevStacks), Done})
            end;
        %% a process parsing the previous log file gets to the end
        {end_of_trace_file, {PrevSubDBIndex,Pid, Stack}} ->
            case lists:keyfind(Pid, 1, ChildrenProcs) of 
                {Pid, Proc} ->
                    Proc ! {end_of_trace_file, {PrevSubDBIndex, Pid, Stack}},
                    pdb_func_loop({SubDB, SubDBIndex,ChildrenProcs,PrevStacks, Done});
                false when Done->
                    NextFuncRegName = mk_proc_reg_name("pdb_func", SubDBIndex+1),
                    case whereis(NextFuncRegName) of 
                        undefined -> ok;
                        NextPid ->
                            NextPid ! {end_of_trace_file, {SubDBIndex, Pid, Stack}}
                    end,
                    pdb_func_loop({SubDB, SubDBIndex, ChildrenProcs, PrevStacks, Done});
                false ->
                    %% This could be that the process has not run yet, or the process 
                    %% has finished.
                    pdb_func_loop({SubDB, SubDBIndex, ChildrenProcs, [{Pid, Stack}|PrevStacks], Done})
            end;
        {action, stop, From} ->
            From ! {self(), stopped};
        Unhandled ->
            io:format("function pdb_func_loop, unhandled:~p~n", [Unhandled]),
            pdb_func_loop({SubDB,SubDBIndex,ChildrenProcs, PrevStacks, Done})                
    end.

pdb_func_loop_process_trace(SubDBIndex, ChildrenProcs, PrevStacks, Trace) ->
    {_TraceTag, TraceData} = Trace,
    Pid = element(1, TraceData),
    case lists:keyfind(Pid, 1, ChildrenProcs) of
        {Pid, Proc} ->
            Proc ! Trace,
            ChildrenProcs;
        false ->
            PrevStack = case lists:keyfind(Pid,1,PrevStacks) of
                            false -> false;
                            {Pid, Stack} -> Stack
                        end,
            Proc = spawn_link(
                     fun() ->
                             pdb_sub_func_loop({SubDBIndex, Pid, [], PrevStack})
                     end),
            Proc ! Trace,
            [{Pid, Proc}|ChildrenProcs]
    end.

pdb_func_loop_process_trace_1(ChildrenProcs, Trace) ->
    {_TraceTag, TraceData} = Trace,
    Pid = element(1, TraceData),
    case lists:keyfind(Pid, 1, ChildrenProcs) of
        {Pid, Proc} ->
            Proc ! Trace;
        false ->
            ok
    end.

pdb_sub_func_loop({SubDBIndex,Pid, Stack, PrevStack}) ->
    receive
        {trace_call, {Pid, Func, TS, CP}} ->
            {NewStack, NewPrevStack}=trace_call_1(SubDBIndex, Pid, Func, TS, CP, Stack, PrevStack),
            pdb_sub_func_loop({SubDBIndex, Pid, NewStack, NewPrevStack});
        {trace_return_to, {Pid, Func, TS}} ->
            {NewStack, NewPrevStack}=trace_return_to_1(SubDBIndex, Pid, Func, TS, Stack,PrevStack),
            pdb_sub_func_loop({SubDBIndex, Pid, NewStack, NewPrevStack});
        {trace_in, {Pid, Func, TS}} ->
            {NewStack, NewPrevStack} = trace_in_1(SubDBIndex, Pid, Func, TS, Stack, PrevStack),
            pdb_sub_func_loop({SubDBIndex, Pid, NewStack, NewPrevStack});
        {trace_out, {Pid, Func, TS}} ->
            Stack1 = case Stack of 
                         [] -> case Func of undefined -> [];
                                   _ -> [[{Func, TS}]]
                               end;
                         _ -> Stack
                     end,
            NewStack = [[{suspend, TS}] | Stack1],
            pdb_sub_func_loop({SubDBIndex, Pid, NewStack, PrevStack});
        {Parent, {trace_exit, {Pid,TS}}} ->
            case lists:reverse(lists:flatten(Stack)) of 
                [] -> 
                    Parent ! {Pid, done};
                [{Func0, _}|_] -> 
                    {Stack1, NewPrevStack}=trace_return_to_2(SubDBIndex, Pid, Func0, TS, Stack, PrevStack),
                    trace_return_to_2(SubDBIndex, Pid, undefined, TS, Stack1, NewPrevStack),
                    Parent ! {Pid, done}
            end;
        {trace_gc_start, {Pid,TS}} ->
            NewStack = [[{garbage_collect, TS}]|Stack],
            pdb_sub_func_loop({SubDBIndex, Pid, NewStack, PrevStack});
        {trace_gc_end, {Pid,TS}} ->
            {NewStack, NewPrevStack}=trace_gc_end_1(SubDBIndex, Pid, TS, Stack, PrevStack),
            pdb_sub_func_loop({SubDBIndex, Pid, NewStack, NewPrevStack});
        {Parent, end_of_trace_file} ->
            NextFuncRegName = mk_proc_reg_name("pdb_func",SubDBIndex+1),
            case whereis(NextFuncRegName) of 
                undefined ->
                    Parent ! {Pid, done};
                NextPid ->
                    NextPid ! {end_of_trace_file, {SubDBIndex, Pid, Stack}},
                    Parent ! {Pid, done}
            end
    end.

trace_in_1(SubDBIndex, Pid, Func, TS, Stack, PrevStack) ->
    ?dbg(-1, "trace_in(~p, ~p, ~p)~n~p~n", [Pid, Func, TS, Stack]),
    case Stack of 
        [] ->
            {[[{Func,TS}]], PrevStack}; 
        [[{suspend, _}]] ->
            trace_return_to_2(SubDBIndex, Pid, undefined, TS, Stack, PrevStack);
        [[{suspend,_}] | [[{suspend,_}] | _]=NewStack] ->
	    %% No stats update for a suspend on suspend
            {NewStack, PrevStack};
        [[{suspend, TS0}] | [[{Func1, TS1} | _] | _]] ->
            update_fun_related_info(Pid, suspend, TS0, TS, Func1, TS1,[]),
            trace_return_to_2(SubDBIndex, Pid, Func1, TS, Stack, PrevStack);
        _ ->
            %%inconsistent trace data
            {Stack, PrevStack}   
    end.

trace_gc_end_1(SubDBIndex, Pid, TS, Stack, PrevStack) ->
    ?dbg(0, "trace_gc_end(~p, ~p)~n~p~n", [Pid, TS, Stack]),
    case Stack of
	[] ->
	    {[], PrevStack};
        [[{garbage_collect, _}]] ->
            trace_return_to_2(SubDBIndex, Pid, undefined, TS, Stack, PrevStack);
	[[{garbage_collect, TS0}], [{Func1, TS1} | _] | _] ->
            update_fun_related_info(Pid, garbage_collect, TS0, TS, Func1, TS1, []),
            trace_return_to_2(SubDBIndex, Pid, Func1, TS, Stack, PrevStack);
	_ ->
            %%inconsistent trace data
            {Stack, PrevStack} 
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             trace function call                  %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
trace_call_1(SubDBIndex, Pid, MFA, TS, CP, Stack, PrevStack) ->
    Func = mfarity(MFA),
    ?dbg(-1, "trace_call(~p, ~p, ~p, ~p, ~p)~n", 
	 [Pid, Stack, Func, TS, CP]),
    case Stack of 
        [[{Func1,TS1}, dummy]|Stack1] when Func1=/=CP ->
            {Caller1, Caller1StartTs}= case Stack1 of 
                                           [[{Func2, TS2}|_]|_]->
                                               {Func2, TS2};
                                           _ ->
                                               {Func1, TS1}
                                       end,
            update_calltree_info(Pid, {Func1, TS1, TS}, {Caller1, Caller1StartTs}),
            trace_call_2(SubDBIndex, Pid, Func, TS, CP, Stack1, PrevStack);
        _ ->
            trace_call_2(SubDBIndex, Pid, Func, TS, CP, Stack, PrevStack)
    end.

trace_call_2(SubDBIndex, Pid, Func, TS, CP, Stack, PrevStack) ->
    case Stack of
	[] when CP =:= undefined ->
            ?dbg(-1, "empty stack\n", []),
            {[[{Func, TS}] | []], PrevStack};
        [] ->
            ?dbg(-1, "empty stack\n", []),
            case wait_for_prev_stack(SubDBIndex, Pid, Func, TS) of 
                [] ->
                    {[[{Func, TS}] | [[{CP, TS}]]], PrevStack};
                NewPrevStack ->
                    trace_call_2(SubDBIndex, Pid, Func, TS, CP, 
                                 NewPrevStack, NewPrevStack)
            end;
        [[{suspend, _} | _] |Stack1] ->
            %% inconsistent trace data!
            trace_call_2(SubDBIndex, Pid, Func, TS, CP, Stack1, PrevStack); 
       	[[{garbage_collect, _} | _] |Stack1] ->
            %% inconsistent trace data!
            trace_call_2(SubDBIndex, Pid, Func, TS, CP, Stack1, PrevStack);
        [[{Func, _FirstInTS}]] ->
            {Stack, PrevStack};
        [[{CP, _} | _], [{CP, _} | _] | _] ->
            {trace_call_shove(Pid,Func, TS, Stack), PrevStack};
        [[{CP, TS1} | _] | _] when Func==CP ->
            ?dbg(-1, "Current function becomes new stack top.\n", []),
            update_calltree_info(Pid, {Func, TS, undefined}, {Func, TS1}),
            {Stack, PrevStack};
	[[{CP, _} | _] | _] ->
            ?dbg(-1, "Current function becomes new stack top.\n", []),
            {[[{Func, TS}] | Stack], PrevStack};
                [[{Func, TS1} | _], [{CP, _TS1} | _] | _] ->
            update_calltree_info(Pid, {Func, TS, undefined}, {Func, TS1}),
            {Stack, PrevStack};
        [_, [{CP, _} | _] | _] ->
            ?dbg(-1, "Stack top unchanged, no push.\n", []),
            {trace_call_shove(Pid, Func, TS, Stack), PrevStack}; 
        [[{Func0, _} | _], [{Func0, _} | _], [{CP, _} | _] | _] ->
            {NewStack, NewPrevStack} = trace_return_to_2(SubDBIndex,Pid, Func0, TS,
                                                         Stack, PrevStack),
            NewStack1=trace_call_shove(Pid, Func, TS, NewStack),
            {NewStack1, NewPrevStack};
        [_|_] ->
            {[[{Func, TS}], [{CP, TS}, dummy]|Stack], PrevStack}
    end.
    
%% Tail recursive stack push
trace_call_shove(_Pid, Func, TS, []) ->
    [[{Func, TS}]];
trace_call_shove(Pid, Func, TS,  [Level0|Stack1]) ->
    ?dbg(-1, "Before collapse:\n~p\n", [[[{Func, TS} | Level0]| Stack1]]),
    Level01 = [{Func, TS} | Level0],
    [NewLevel0| NewStack1] = 
        [trace_call_collapse(Level01) | Stack1],
    ?dbg(-1, "After collapse:\n~p\n", [[NewLevel0| NewStack1]]),
    case Level01 -- NewLevel0 of 
        [] -> ok;
        Funs ->
            Funs1= lists:sublist(NewLevel0, length(Funs)+1),
            trace_call_shove_update_call_info(Pid,Funs1)
    end,
    [NewLevel0| NewStack1].
    
trace_call_shove_update_call_info(_, []) ->
    ok;
trace_call_shove_update_call_info(_, [_]) ->
    ok;
trace_call_shove_update_call_info(Pid, [{Func1, TS1}, {Func2, Ts2}|Tail])->
    update_calltree_info(Pid, {Func1, TS1, undefined}, {Func2, Ts2}),
    trace_call_shove_update_call_info(Pid, [{Func2, Ts2}|Tail]).
    

%% Collapse tail recursive call stack cycles to prevent them from
%% growing to infinite length.
trace_call_collapse([_] = Stack) ->
    Stack;
trace_call_collapse([_, _] = Stack) ->
    Stack;
trace_call_collapse([_ | Stack1] = Stack) ->
    ?dbg(-1, "collapse_trace_state(~p)~n", [Stack]),
    trace_call_collapse_1(Stack, Stack1, 1).
    
%% Find some other instance of the current function in the call stack
%% and try if that instance may be used as stack top instead.
trace_call_collapse_1(Stack, [], _) ->
    Stack;
trace_call_collapse_1([{Func0, _} |_] = Stack, [{Func0, _TS} | S1] = S, N) ->
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


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             trace function return                %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

wait_for_prev_stack(SubDBIndex, Pid, Func, TS)->
    case SubDBIndex of
        1 ->
            [[{Func, TS}]];
        _ ->
            PrevSubIndex = SubDBIndex-1,
            receive
                {end_of_trace_file, {PrevSubIndex, Pid, PrevStack}} ->
                    PrevStack
                    %% after 1000  %% what is the proper timeout value here?
                    %%           ->
                    %%         [[{Func, TS}]].
            end
    end.
           
trace_return_to_1(SubDBIndex, Pid, Func, TS, Stack, PrevStack) ->
    Caller = if is_tuple(Func) -> mfarity(Func);
                true -> Func
             end,
    ?dbg(-1, "trace_return_to(~p, ~p, ~p)~n~p~n",
	 [Pid, Caller, TS, Stack]),
    case Stack of
	[[{suspend, _} | _] | Stack1] ->
            %% inconsistent trace data!
            trace_return_to_1(SubDBIndex, Pid, Func, TS, Stack1, PrevStack);           
	[[{garbage_collect, _} | _] | Stack1] ->
            %% inconsistent trace data!
            trace_return_to_1(SubDBIndex, Pid, Func, TS, Stack1, PrevStack);
        [_, [{Caller, _}|_]|_] ->
            trace_return_to_2(SubDBIndex, Pid, Caller, TS, Stack, PrevStack);
        [[{Func1, TS1}, dummy]|Stack1=[_, [{Caller, _}|_]|_]] when Caller=/=Func1->
            {Caller1, Caller1StartTs}= 
                case Stack1 of 
                    [[{Func2, TS2}|_]|_]->
                        {Func2, TS2};
                    _ ->
                        {Func1, TS1}
                end,
            update_fun_related_info(Pid, Func1, TS1, TS, Caller1, Caller1StartTs, Stack1),
            trace_return_to_2(SubDBIndex, Pid, Caller, TS, Stack1, PrevStack);
        _ when Caller == undefined ->
            trace_return_to_2(SubDBIndex, Pid, Caller, TS, Stack, PrevStack);
        [] ->
            case SubDBIndex of 
                1 ->  {[[{Func, TS}]], PrevStack};
                _ ->
                    case PrevStack of 
                        false ->
                            NewPrevStack=wait_for_prev_stack(SubDBIndex, Pid, Func, TS),
                            trace_return_to_1(SubDBIndex, Pid, Func, TS, NewPrevStack, NewPrevStack);
                        _ ->
                            {[[{Func, TS}]], PrevStack}
                    end
            end;
        _ ->
            {Callers,_} = lists:unzip([hd(S)||S<-Stack]),
            case lists:member(Caller, Callers) of
                true ->
                    trace_return_to_2(SubDBIndex, Pid, Caller, TS, Stack, PrevStack);
                _ -> 
                    {[[{Caller, TS}, dummy]|Stack], PrevStack}
            end
    end.

trace_return_to_2(_, _, undefined, _, [], PrevStack) ->
    {[], PrevStack};
trace_return_to_2(SubDBIndex, Pid, Func, TS, [], PrevStack) ->
    case SubDBIndex of 
        1 ->  {[[{Func, TS}]], PrevStack};
        _ ->
            case PrevStack of 
                false ->
                    NewPrevStack=wait_for_prev_stack(SubDBIndex, Pid, Func, TS), 
                    trace_return_to_2(SubDBIndex, Pid, Func, TS, NewPrevStack, NewPrevStack);
                _ ->
                    {[[{Func, TS}]], PrevStack}
            end
    end;
trace_return_to_2(SubDBIndex, Pid, Func, TS, [[] | Stack1], PrevStack) ->
    trace_return_to_2(SubDBIndex, Pid, Func, TS, Stack1, PrevStack);
trace_return_to_2(_, _Pid, Func, _TS, [[{Func, _}|_Level0]|[[{Func1,_}|_]|_Stack1]] = Stack, 
                  PrevStack) when
      Func/=Func1 -> {Stack, PrevStack};    
trace_return_to_2(_, _Pid, Func, _TS, [[{Func, _}|_Level0]] = Stack, PrevStack) ->
    {Stack, PrevStack};    
trace_return_to_2(SubDBIndex, Pid, Func, TS, [[{Func0, Func0StartTS} | Level1] | Stack1], PrevStack) ->
    case Func0 of
         {_, _, _} ->
            case Level1 of
                [{Func1, TS2}|_] ->
                    {Caller, CallerStartTs}={Func1, TS2},
                    update_fun_related_info(Pid, Func0, Func0StartTS, TS, 
                                            Caller, CallerStartTs, [Level1|Stack1]);
                _ ->
                    {Caller, CallerStartTs}=case Stack1 of
                                                [[{Func1, TS2}, dummy]|_] ->
                                                    {Func1, TS2};
                                                [[{Func1, TS2}|_]|_]->
                                                    {Func1, TS2};
                                                [] ->
                                                    {Func, Func0StartTS}
                                            end,
                    update_fun_related_info(Pid, Func0, Func0StartTS, TS, Caller, CallerStartTs,Stack1)
            end;
        _ ->
            ok
    end,
    if Level1 ==[dummy] ->
            trace_return_to_2(SubDBIndex, Pid, Func, TS, Stack1, PrevStack);
       true ->
            trace_return_to_2(SubDBIndex, Pid, Func, TS, [Level1|Stack1], SubDBIndex)
    end.

update_fun_related_info(Pid, Func, StartTS, EndTS, Caller, CallerStartTs, Stack) ->
    case lists:any(fun({Func1, _}) -> Func ==Func1;
                     (_) -> false
                   end, lists:append(Stack)) of 
        true ->
            ok;
        false ->
            ets:insert(funcall_info, #funcall_info{id={pid2value(Pid), StartTS, EndTS}, func=Func}),
            update_fun_call_time({Pid, Func}, {StartTS, EndTS})
    end,
    update_calltree_info(Pid, {Func, StartTS, EndTS}, {Caller, CallerStartTs}).
            
-spec(update_calltree_info(pid(), {true_mfa()|suspend|garbage_collect, timestamp(), timestamp()|undefined}, 
                           {true_mfa(), timestamp()}) ->true).       
update_calltree_info(Pid, {Callee, _StartTS0, _}, {Caller,  CallerStartTS0}) when Caller==Callee ->
    CallerStartTS = case is_list_comp(Caller) of 
                        true -> undefined;
                       _ -> CallerStartTS0
                   end,
    Pid1 = pid2value(Pid),
    CallerId = {Pid1, Caller, CallerStartTS},
    case ets:lookup(fun_calltree, CallerId) of 
        [C]->
            ets:update_element(fun_calltree,CallerId, 
                               {#fun_calltree.rec_cnt, C#fun_calltree.rec_cnt+1});                     
        [] ->
            CallerInfo = #fun_calltree{id = CallerId,
                                       rec_cnt=1,
                                       start_ts=CallerStartTS0,
                                       called = []}, 
            ets:insert(fun_calltree, CallerInfo) 
    end;
  
update_calltree_info(Pid, {Callee, StartTS0, EndTS}, {Caller, CallerStartTS0}) ->
    CallerStartTS = case is_list_comp(Caller) of 
                        true -> undefined;
                       _ -> CallerStartTS0
                    end,
    StartTS = case is_list_comp(Callee) of 
                  true -> undefined;
                  _ -> StartTS0
              end,
    Pid1 = pid2value(Pid),
    case ets:lookup(fun_calltree, {Pid1, Callee, StartTS}) of
        [] ->
            add_new_callee_caller(Pid1, {Callee, StartTS, EndTS}, 
                                  now_diff(EndTS,StartTS0),
                                  {Caller, CallerStartTS});
        [F] -> 
            NewF =F#fun_calltree{id=setelement(3, F#fun_calltree.id, Caller),
                                 cnt=1,
                                 acc_time = now_diff(EndTS,StartTS0),
                                 start_ts =StartTS0,
                                 end_ts=EndTS},   
            CallerId = {Pid1, Caller, CallerStartTS},
            case ets:lookup(fun_calltree, CallerId) of 
                [C] when Caller=/=Callee->
                    ets:delete_object(fun_calltree, F),
                    NewC = C#fun_calltree{called=add_new_callee(NewF, C#fun_calltree.called)},
                    NewC1 = collapse_call_tree(NewC, Callee),
                    ets:insert(fun_calltree, NewC1);    
                _ ->
                    CallerInfo = create_caller_info(CallerId, EndTS, StartTS0, NewF),
                    ets:delete_object(fun_calltree, F),
                    NewCallerInfo = collapse_call_tree(CallerInfo, Callee),
                    case ets:lookup(fun_calltree, CallerId) of
                        [] ->
                            ets:insert(fun_calltree, NewCallerInfo);
                        [C1] ->
                            NewC = combine_fun_info(C1, NewCallerInfo),
                            ets:insert(fun_calltree, NewC)
                    end                            
            end
    end.

add_new_callee_caller(Pid, {Callee, StartTS, EndTS},CalleeTime, 
                      {Caller, CallerStartTS}) ->
    CalleeInfo = #fun_calltree{id={Pid, Callee, Caller},
                               cnt =1, 
                               called = [],
                               acc_time = CalleeTime,
                               start_ts = StartTS,
                               end_ts = EndTS},
    CallerId = {Pid, Caller, CallerStartTS},
    case ets:lookup(fun_calltree, {Pid, Caller, CallerStartTS}) of
        [] ->
            CallerInfo = create_caller_info(CallerId, EndTS, CallerStartTS,CalleeInfo),
            ets:insert(fun_calltree, CallerInfo);
        [C] ->
            NewC = C#fun_calltree{
                     called=add_new_callee(CalleeInfo, 
                                           C#fun_calltree.called)},
            ets:insert(fun_calltree, NewC)
    end.

create_caller_info(CallerId = {Pid, Caller, CallerStartTS}, 
                   EndTS, CallerStartTS0, CalleeInfo) ->
    if Caller == undefined orelse Caller == {percept2_profile, start, 3} ->
            update_fun_call_time({Pid, Caller}, {CallerStartTS0, EndTS}),
            #fun_calltree{id = CallerId,
                          cnt =0,
                          start_ts=CallerStartTS,
                          end_ts = EndTS,
                          acc_time =  now_diff(EndTS,CallerStartTS0),
                          called = [CalleeInfo]};
       true ->
            #fun_calltree{id = CallerId,
                          cnt =0,
                          start_ts=CallerStartTS,
                          called = [CalleeInfo]}
    end.


%% collapse recursive call chains to which Callee is an element of 
%% recursion.      
%% TOTest: is this accurate enough?
collapse_call_tree(CallTree, Callee) ->
    {_Pid, Caller,_TS} = CallTree#fun_calltree.id,
    Children=CallTree#fun_calltree.called,
    case collect_children_to_merge(Children, {Caller, Callee}) of 
        {_, []} ->
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
    case lists:keyfind(Id, 2, CalleeList) of
        false ->
            [CalleeInfo|CalleeList];
        C ->
            NewC=combine_fun_info(C, CalleeInfo),
            lists:keyreplace(Id, 2, CalleeList, NewC)
    end.

combine_fun_info(FunInfo1=#fun_calltree{id=Id, called=Callees1, 
                                        start_ts=StartTS1,end_ts= EndTS1,
                                        acc_time = AccTime1,
                                        cnt=CNT1,
                                        rec_cnt = RecCnt1}, 
                 _FunInfo2=#fun_calltree{id=Id, called=Callees2, 
                                         start_ts=StartTS2, end_ts=EndTS2,
                                         acc_time = AccTime2,
                                         cnt=CNT2,
                                         rec_cnt = RecCnt2}) ->
    NewAccTime = case StartTS1=<StartTS2 andalso EndTS1>=EndTS2 of 
                     true ->
                         AccTime1;
                     false ->
                         case StartTS1>=StartTS2 andalso EndTS1=<EndTS2 of 
                             true ->
                                 AccTime2;
                             false ->
                                 AccTime1+AccTime2
                         end
                 end,
    NewCallees=lists:foldl(fun(C, Callees) ->
                                   add_new_callee(C, Callees)
                           end, Callees1, Callees2),
    FunInfo1#fun_calltree{id=Id, called=NewCallees, 
                          start_ts=lists:min([StartTS1,StartTS2]),
                          end_ts=lists:max([EndTS1, EndTS2]),
                          acc_time = NewAccTime, 
                          cnt = CNT1 + CNT2, 
                          rec_cnt = RecCnt1+RecCnt2}.


is_list_comp({_M, F, _A}) ->
    re:run(atom_to_list(F), ".*-lc.*", []) /=nomatch;
is_list_comp(_) ->
    false.
      

%%%---------------------------%%%
%%%                           %%%
%%%     consolidate db        %%%
%%%                           %%%
%%%---------------------------%%%
%% consolidate_db() -> bool()
%% Purpose:
%%	Check start/stop time
%%	Activity consistency
%%      function call tree, and
%%      generate function inforation.

-spec consolidate_db([{filename(), pid()}]) ->ok.
consolidate_db(FileNameSubDBPairs) ->
    io:format("Consolidating...~n"),
    LastIndex = length(FileNameSubDBPairs),
    SystemProc = mk_proc_reg_name("pdb_system", 1),
    % Check start/stop timestamps
    case percept_db_select_query([], {system, start_ts}) of
	undefined ->
            Min=get_start_time_ts(),
            update_system_start_ts(SystemProc,Min);
        _ -> ok
    end,
    case percept_db_select_query([], {system, stop_ts}) of
	undefined ->
            Max = get_stop_time_ts(LastIndex),
            update_system_stop_ts(SystemProc,Max);
        _ -> ok
    end,
    %% check no of nodes (temporary solution).
    NumOfNodes=percept_db_select_query(
                 [],{information, num_of_nodes}),
    update_system_nodes_num(SystemProc, NumOfNodes),

    ?dbg(0, "consolidate runnability ...\n",[]),
    consolidate_runnability(LastIndex),
    ?dbg(0, "consolidate function callgraph ...\n",[]),
    consolidate_calltree(),
    ?dbg(0,"generate function information ...\n",[]),
    process_func_info(),
    ok.

get_start_time_ts() ->
    AMin = case ets:first(pdb_activity1) of 
               '$end_of_table' -> undefined;
               T when is_tuple(T)-> T
           end,
    SMin =case ets:first(pdb_scheduler1) of 
              '$end_of_table' -> undefined;
              T1 when is_tuple(T1)-> T1
          end,
    IMin =case ets:first(inter_proc) of 
              '$end_of_table' -> undefined;
              {T2, _, _} when is_tuple(T2)-> T2
          end,
    Ts = [T||T<-[AMin, SMin, IMin], T/=undefined],
    case Ts of
        [] -> undefined;
        _ -> lists:min(Ts)
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
    IMax =case ets:last(inter_proc) of 
              {T2, _,_} when is_tuple(T2)-> T2;
              _ -> undefined
          end,
    Ts = [T||T<-[AMax, SMax, IMax], T/=undefined],
    case Ts of
        [] -> undefined;
        _ -> lists:max(Ts)
    end.

%%%------------------------------------------------------%%%
%%%                                                      %%%
%%%  consolidate runnability                             %%%
%%%                                                      %%%
%%%------------------------------------------------------%%%
consolidate_runnability(1) -> ok;
consolidate_runnability(LastSubDBIndex) ->
    Tab = mk_proc_reg_name("pdb_activity", 1),
    LastKey = ets:last(Tab),
    case LastKey of 
        '$end_of_table' -> 
            consolidate_runnability_1(2, {0, 0},LastSubDBIndex);
        _ ->
            [#activity{runnable_procs=RunnableProcs,
                       runnable_ports=RunnablePorts}]=
                ets:lookup(Tab, LastKey),
            consolidate_runnability_1(2, {RunnableProcs, RunnablePorts}, LastSubDBIndex)
    end.

consolidate_runnability_1(CurSubDBIndex, _, LastSubDBIndex) 
  when CurSubDBIndex>LastSubDBIndex ->
    ok;
consolidate_runnability_1(CurSubDBIndex, PreviousRC, LastSubDBIndex) ->
    ActivityProcRegName = mk_proc_reg_name("pdb_activity", CurSubDBIndex),
    Pid = whereis(ActivityProcRegName),
    Pid ! {consolidate_runnability, {self(), CurSubDBIndex, PreviousRC}},
    receive
        {Pid,done, NewRC} ->
            consolidate_runnability_1(CurSubDBIndex+1, NewRC, LastSubDBIndex)
    end.

do_consolidate_runnability(Tab, PrevRC) ->
    case  ets:first(Tab) of
        '$end_of_table' ->
            {ok, PrevRC};
        Key ->
            do_consolidate_runnability(Tab, Key, PrevRC)
    end.
do_consolidate_runnability(Tab, '$end_of_table', _PrevRC) ->
    LastKey = ets:last(Tab),
    [#activity{runnable_procs=RunnableProcs,
               runnable_ports=RunnablePorts}]=
        ets:lookup(Tab, LastKey),
    {ok, {RunnableProcs, RunnablePorts}};
do_consolidate_runnability(Tab, Key, {PrevRunnableProcs, PrevRunnablePorts}) ->
    ets:update_counter(Tab, Key, [{#activity.runnable_procs, PrevRunnableProcs},
                                  {#activity.runnable_ports, PrevRunnablePorts}]),
    do_consolidate_runnability(Tab, ets:next(Tab,Key),{PrevRunnableProcs, PrevRunnablePorts}).


%%%------------------------------------------------------%%%
%%%                                                      %%%
%%%  consolidate calltree to make sure each process only %%%
%%   has one calltree.                                   %%%
%%%                                                      %%% 
%%%------------------------------------------------------%%%
consolidate_calltree() ->
    Pids=ets:select(fun_calltree, 
                    [{#fun_calltree{id = {'$1', '_','_'}, _='_'},
                      [],
                      ['$1']
                     }]),
    case Pids -- lists:usort(Pids) of 
        [] ->  %%  each process only has one calltree, the ideal case.
            ok; 
        Pids1->
            consolidate_calltree_1(lists:usort(Pids1))
    end.
             
consolidate_calltree_1(Pids) ->
    lists:foreach(fun(Pid) ->
                          consolidate_calltree_2(Pid)
                  end, Pids).
consolidate_calltree_2(Pid) ->
    Trees=ets:select(fun_calltree, 
                             [{#fun_calltree{id = {Pid, '_','_'}, _='_'},
                               [],
                               ['$_']
                              }]),
    [_Tree|Others] = lists:sort(fun(T1, T2) ->
                                       erlang:external_size(T1)>= erlang:external_size(T2)
                               end, Trees),
    lists:foreach(fun(T)-> 
                          ets:delete_object(fun_calltree, T) 
                  end, Others),
    ok.

    
%%%------------------------------------------------------%%%
%%%                                                      %%%
%%%  Generate statistic information about each function. %%%
%%%                                                      %%%
%%%------------------------------------------------------%%%
process_func_info() ->
    Ids=ets:select(fun_calltree, 
                   [{#fun_calltree{id = '$1', _='_'},
                     [], ['$1']}]),
    percept2_utils:pforeach(
      fun(Id) -> 
              process_a_call_tree(Id) 
      end, Ids),
    ok.
process_a_call_tree(Id) ->
    [Tree]=ets:lookup(fun_calltree, Id),
    process_a_call_tree_1(Tree).    

process_a_call_tree_1(CallTree) ->
    {Pid, MFA, Caller}=CallTree#fun_calltree.id,
    RecCnt = CallTree#fun_calltree.rec_cnt,
    if RecCnt /=0 ->
            update_fun_info({Pid, MFA}, 
                            {MFA, CallTree#fun_calltree.rec_cnt},
                            [],
                            CallTree#fun_calltree.start_ts,
                            CallTree#fun_calltree.end_ts);
       true -> ok
    end,
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

      
update_fun_call_time({Pid, Func}, {StartTs, EndTs}) ->
    Time =now_diff(EndTs, StartTs),
    PidValue = pid2value(Pid),
    case ets:lookup(fun_info, {PidValue, Func}) of 
        [] ->
            ets:insert(fun_info, #fun_info{id={PidValue, Func},
                                           start_ts=StartTs,
                                           end_ts = EndTs,
                                           acc_time=Time});
        [FunInfo] ->  %% This is not quite right whit recursive calls because 
                       %% of the overlapping.
            ets:update_element(fun_info, {PidValue, Func},
                               [{#fun_info.acc_time, FunInfo#fun_info.acc_time+Time}])
    end.

%% -spec(update_fun_info({pid(), true_mfa()}, {true_mfa()|undefined, non_neg_integer()},
%%                       [{true_mfa(), non_neg_integer()}], timestamp(), timestamp()) ->true).
update_fun_info({Pid, MFA}, Caller={_Func, Cnt}, Called, StartTs, EndTs) ->
    case ets:lookup(fun_info, {Pid, MFA}) of
        [] ->
            NewEntry=#fun_info{id={pid2value(Pid), MFA},
                               callers = [Caller],
                               called = Called,
                               start_ts= StartTs,
                               end_ts = EndTs,
                               call_count = Cnt},
            ets:insert(fun_info, NewEntry);
        [FunInfo] ->
            NewFunInfo=
                FunInfo#fun_info{
                  callers=add_to([Caller],
                                 FunInfo#fun_info.callers),
                  called = add_to(Called,FunInfo#fun_info.called),
                  start_ts = lists:min([FunInfo#fun_info.start_ts,StartTs]),
                  end_ts = lists:max([FunInfo#fun_info.end_ts,EndTs]),
                  call_count =FunInfo#fun_info.call_count+Cnt},
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
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%   Generate process tree                          %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% process_tree_size(Trees) ->
%%     lists:sum([process_tree_size_1(Tree)||Tree<-Trees]).

%% process_tree_size_1({_Parent, Children}) ->
%%     1 + process_tree_size(Children).

  
-type process_tree()::{#information{},[process_tree()]}.

-spec gen_compressed_process_tree/0::()->[process_tree()].
gen_compressed_process_tree()->
    Trees = gen_process_tree(),
    put(last_index, 0),
    NewTrees=compress_process_tree(Trees),
    erase(last_index),
    NewTrees.
    

-spec gen_process_tree/0::()->[process_tree()].
gen_process_tree() ->
    Res =ets:select(pdb_info, [{#information{id = {pid,'$1'},  
                                             start='$2', children='$3', _='_'},
                                [],[{{{{pid, '$1'}}, '$2','$3'}}]}]),
    List = lists:keysort(2,Res),
    gen_process_tree(List, []).

-spec gen_process_tree/2::([{pid_value(),any(), any()}],[process_tree()]) 
                          -> [process_tree()].
gen_process_tree([], Out) ->
    add_ancestors(Out);
gen_process_tree([_Item={Pid, _Start, Children}|Tail], Out) ->
    {ChildrenElems, Tail1} = lists:partition(
                               fun({Pid1, _, _}) -> 
                                       lists:member(Pid1, Children) 
                               end, Tail),
    {NewChildren, NewTail}=gen_process_tree_1(ChildrenElems, Tail1, []),
    [Parent] = ets:lookup(pdb_info, Pid),
     gen_process_tree(NewTail, [{Parent, NewChildren}|Out]).

-spec gen_process_tree_1/3::([{pid_value(),any(), any()}],
                             [{pid_value(),any(), any()}],
                             [process_tree()])
                            -> {[process_tree()],[{pid_value(),any(), any()}]}.
gen_process_tree_1([], Tail, NewChildren) ->
    {NewChildren, Tail};
gen_process_tree_1([_C={Pid, _Start, Children}|Cs], Tail, Out) ->
    {ChildrenElems, Tail1} = lists:partition(
                               fun({Pid1, _, _}) -> 
                                       lists:member(Pid1, Children) 
                               end, Tail),
    [Parent] = ets:lookup(pdb_info, Pid),
    {NewChildren, NewTail}=gen_process_tree_1(ChildrenElems, Tail1, []),
    gen_process_tree_1(Cs, NewTail, [{Parent, NewChildren}|Out]).



-spec add_ancestors/1::([process_tree()])->[process_tree()].
add_ancestors(ProcessTree) ->
    add_ancestors(ProcessTree, []).

add_ancestors(ProcessTree, As) ->
    [begin 
         update_information_element(pdb_info1, Parent#information.id, 
                                    {#information.ancestors, As}),
         {Parent#information{ancestors=As},         
          add_ancestors(Children, [Parent#information.id|As])}
     end
     ||{Parent, Children} <- ProcessTree].

%%% -------------------	---%%%
%%% compress process tree  %%%
%%% -----------------------%%%

compress_process_tree(Trees) ->
    compress_process_tree(Trees, []).
  

compress_process_tree([], Out)->
    lists:reverse(Out);
compress_process_tree([T={P, _}|Ts], Out) ->
    case is_dummy_pid(P#information.id) of
        true ->
            compress_process_tree(Ts, Out);
        false ->
            T1=compress_process_tree_1(T),
            compress_process_tree(Ts, [T1|Out])
    end.

compress_process_tree_1(Tree={_Parent, []}) ->
    Tree;
compress_process_tree_1(_Tree={Parent, Children}) ->
    CompressedChildren = compress_process_tree_2(Children),
    {Parent, CompressedChildren}.

compress_process_tree_2(Children) when length(Children)<3->
    compress_process_tree(Children);
compress_process_tree_2(Children) ->
    GroupByEntryFuns=group_by(
                       1, 
                       [{mfarity(C1#information.entry), {C1,  C2}}
                        ||{C1,C2}<-Children]),
    TreeLists=[compress_process_tree_3(ChildrenGroup)||
                  ChildrenGroup<-GroupByEntryFuns],
    lists:append(lists:sort(
                   fun([{T1, _}|_], [{T2, _}|_]) -> 
                           T1#information.id> T2#information.id 
                   end, TreeLists)).

compress_process_tree_3(ChildrenGroup) ->
    {[EntryFun|_], Children=[C={C0,_}|Cs]} =
        lists:unzip(ChildrenGroup),
    case length(Children) <3 of 
        true -> 
            compress_process_tree(Children);
        false ->
            UnNamedProcs=[C1#information.id||
                             {C1, _}<-Children, C1#information.name==undefined],
            case length(UnNamedProcs) == length(Children) of
                true ->
                    ChildWithMostRunTime = {Proc, _}=get_proc_with_callgraph_and_most_runtime(Children),
                    Num = length(Cs),
                    LastIndex = get(last_index),
                    put(last_index, LastIndex+1),
                    {pid, {NodeIndex, _, _}} =hd(UnNamedProcs),
                    HiddenTrees = lists:reverse(Children-- [ChildWithMostRunTime]),
                    CompressedChildren=
                        Info=#information{id={pid, {NodeIndex,list_to_atom("*"++integer_to_list(LastIndex)++"*"),0}},
                                          name=list_to_atom(integer_to_list(Num)++" siblings omitted"),
                                          parent=C0#information.parent,
                                          entry = EntryFun,
                                          start =lists:min([C1#information.start||{C1,_}<-Cs]),
                                          stop = lists:max([C1#information.stop||{C1, _}<-Cs]),
                                          %% Total;
                                          msgs_received=lists:foldl(fun({P,_}, {R1Acc, R2Acc}) ->
                                                                            {R1, R2}=P#information.msgs_received,
                                                                            {R1+R1Acc, R2+R2Acc}
                                                                    end, {0,0}, Cs),
                                          %% Total;
                                          msgs_sent = lists:foldl(fun({P, _}, {S1Acc, S2Acc}) ->
                                                                          {S1, S2} = P#information.msgs_sent,
                                                                          {S1+S1Acc, S2+S2Acc}
                                                                  end, {0,0}, Cs),
                                          %%Total;
                                          rq_history =lists:append([C1#information.rq_history||{C1,_}<-Cs]),
                                          hidden_proc_trees=HiddenTrees,
                                          hidden_pids =hidden_pids(HiddenTrees)
                                         },
                    update_information_1(Info),
                    [compress_process_tree_1(ChildWithMostRunTime), {CompressedChildren,[]}];   
                false ->
                    compress_process_tree(Children)
            end
    end.

hidden_pids(ProcTrees) ->
    Pids=lists:append([hidden_pids_1(Tree)||Tree<-ProcTrees]),
    lists:sort(Pids).

hidden_pids_1({Parent, Children}) ->
    [Parent#information.id|hidden_pids(Children)].

get_proc_with_callgraph_and_most_runtime(Procs) ->
    Procs1=[Proc||Proc={P,_}<-Procs, has_callgraph(P#information.id)],
    case Procs1 of 
        [] -> get_proc_with_most_runtime(Procs);
        _ ->
            get_proc_with_most_runtime(Procs1)
    end.
get_proc_with_most_runtime([Proc|Procs]) ->
    get_proc_with_most_runtime(Procs, Proc).
get_proc_with_most_runtime([], Proc) ->
    Proc;
get_proc_with_most_runtime([CurP={Proc, _}|Procs], P={Proc1,_}) ->
    Time = Proc#information.accu_runtime,
    case Proc1#information.accu_runtime < Time of 
        true ->
            get_proc_with_most_runtime(Procs,CurP);
        false ->
            get_proc_with_most_runtime(Procs,P)
    end.
    
is_dummy_pid({pid, {_, P2, _}}) ->
    is_atom(P2);
is_dummy_pid(_) -> false.

has_callgraph(Pid) ->
    CallTree=ets:select(fun_calltree, 
                        [{#fun_calltree{id = {Pid, '_','_'}, _='_'},
                          [],
                          ['$_']
                         }]), 
    CallTree/=[].

%%% -------------------	%%%
%%% Utility functionss	%%%
%%% -------------------	%%%
        
-spec(mfarity({atom(), atom(), list()}) ->true_mfa()).             
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

-spec pid2value(Pid :: pid()|pid_value()) -> pid_value().
pid2value(Pid={pid, {_, _, _}}) -> Pid;
pid2value(Pid) when is_pid(Pid) ->
    String = lists:flatten(io_lib:format("~p", [Pid])),
    PidStr=lists:sublist(String, 2, erlang:length(String)-2),
    [P1,P2,P3] = string:tokens(PidStr,"."),
    {pid, {list_to_integer(P1), 
           list_to_integer(P2),
           list_to_integer(P3)}}.


now_diff(EndTS,StartTS) ->
    try timer:now_diff(EndTS, StartTS)
    catch _E1:_E2 -> 0
    end.
   

mk_proc_reg_name(RegNamePrefix,Index) ->
    list_to_atom(RegNamePrefix ++ integer_to_list(Index)).


pid2name(Pid) ->
    case ets:lookup(pdb_info, Pid) of 
        [] -> 'undefined';
        [Info] ->
            Info#information.name
    end.
 
