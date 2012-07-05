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
        start/0,
        stop/1,
        insert/1,
	select/2,
	select/1,
	consolidate/0
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

%%==========================================================================
%%
%% 		Interface functions
%%
%%==========================================================================

%% @spec start() -> ok | {started, Pid} | {restarted, Pid}
%%	Pid = pid()
%% @doc Starts or restarts the percept database.

-spec start() -> {'started', pid()} | {'restarted', pid()}.

start() ->
    case erlang:whereis(percept_db) of
    	undefined ->
	    {started, do_start()};
	PerceptDB ->
	    {restarted, restart(PerceptDB)}
    end.

%% @spec restart(pid()) -> pid()
%% @private
%% @doc restarts the percept database.

-spec restart(pid())-> pid().

restart(PerceptDB)->
    io:format("restart percept_db\n"),
    stop_sync(PerceptDB),
    do_start().

%% @spec do_start() -> pid()
%% @private
%% @doc starts the percept database.

-spec do_start()-> pid().

do_start()->
    Parent = self(),
    Pid =spawn_link(fun() -> init_percept_db(Parent) end),
  %%  io:format("percept_db:\n~p\n", [Pid]),
    receive
        {percept_db, started} ->
            Pid
    end.
    

%% @spec stop() -> not_started | {stopped, Pid}
%%	Pid = pid()|regname()
%% @doc Stops the percept database.

-spec stop(pid()|atom()) -> 'not_started' | {'stopped', pid()}.

stop(Pid) when is_pid(Pid) ->
    Pid! {action, stop},
    {stopped, Pid};
stop(RegName) ->
    case erlang:whereis(RegName) of
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
    stop(Pid),
   %% io:format("Pid:\n~p\n", [Pid]),
    receive
        {'DOWN', MonitorRef, _Type, Pid, _Info}->
            true;
        {'EXIT', Pid, _Info} ->
            true
        %% Others ->
        %%     io:format("pid stoped normal:~p\n", [Others]),
        %%     true  
                
    after ?STOP_TIMEOUT->
            erlang:demonitor(MonitorRef, [flush]),
            exit(Pid, kill)
    end.

%% @spec insert(tuple()) -> ok
%% @doc Inserts a trace or profile message to the database.  

insert(Trace) -> 
    percept_db ! {insert, Trace},
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

select(Query) -> 
    %% io:format("Query:\n~p\n", [Query]),
    %% io:format("whereis percept_db:\n~p\n", [whereis(percept_db)]),
    percept_db ! {select, self(), Query},
    receive {result, Match} -> Match end.

%% @spec select(atom(), list()) -> Result
%% @equiv select({Table,Options}) 

select(Table, Options) -> 
    percept_db ! {select, self(), {Table, Options}},
    receive {result, Match} -> Match end.

%% @spec consolidate() -> Result
%% @doc Checks timestamp and state-flow inconsistencies in the
%%	the database.

consolidate() ->
    %% io:format("consolidate start\n"),
    %% io:format("consolidate start\n"),
    percept_db ! {action, self(), consolidate},
    receive
        {percept_db, consolidate_done} -> ok;
         Others -> io:format("Consoliate receive:~p\n", [Others])                  
    end.
    

%%==========================================================================
 %%
%% 		Database loop 
%%
%%==========================================================================

init_percept_db(Parent) ->
    process_flag(trap_exit, true),
    register(percept_db, self()),
    start_child_process(pdb_info, fun init_pdb_info/1),
    start_child_process(pdb_system, fun init_pdb_system/1),
    start_child_process(pdb_scheduler, fun init_pdb_scheduler/1),
    start_child_process(pdb_activity, fun init_pdb_activity/1),
    start_child_process(pdb_func, fun init_pdb_func/1),
    start_child_process(pdb_warnings, fun init_pdb_warnings/1),
    put(debug, 0),
    Parent!{percept_db, started},
    loop_percept_db().

loop_percept_db() ->
    receive
        {insert, Trace} ->
            insert_trace(clean_trace(Trace)),
            loop_percept_db();
	{select, Pid, Query} ->
            %% io:format("recevied query:\n~p\n", [Query]),
	    Pid ! {result, select_query(Query)},
	    loop_percept_db();
	{action, stop} -> 
            true=stop_sync(whereis(pdb_system)),
            true=stop_sync(whereis(pdb_info)),
            true=stop_sync(whereis(pdb_scheduler)),
            true=stop_sync(whereis(pdb_activity)),
            true=stop_sync(whereis(pdb_func)),
            true=stop_sync(whereis(pdb_warnings)),
	    stopped;
	{action, From, consolidate} ->
            consolidate_db(),
            From ! {percept_db, consolidate_done},
	    loop_percept_db();
        {operate, Pid, {Table, {Fun, Start}}} ->
	    Result = ets:foldl(Fun, Start, Table),
	    Pid ! {result, Result},
	    loop_percept_db();
	Unhandled -> 
	    io:format("loop_percept_db, unhandled query: ~p~n", [Unhandled]),
	    loop_percept_db()
    end.

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

insert_trace_1(Trace)->
    case element(1, Trace) of
        trace_ts -> 
            Type=element(3, Trace),
            FunName = list_to_atom("trace_"++atom_to_list(Type)),
            try FunName(Trace) 
            catch
                _E1:_E2 ->
                     io:format("insert_trace, unhandled: ~p~n", [Trace]),
                    ok
            end
    end.
                    

insert_trace(Trace) ->
    case Trace of
	{profile_start, Ts} ->
             update_system_start_ts(Ts),
	    ok;
        {profile_stop, Ts} ->
	    update_system_stop_ts(Ts),
	    ok; 
        %%% erlang:system_profile, option: runnable_procs
    	%%% ---------------------------------------------
    	{profile, Id, State, Mfa, TS} when is_pid(Id) ->
	    % Update runnable count in activity and db
	    case check_activity_consistency(Id, State) of
		invalid_state -> 
		    ignored;
		ok ->
		    Rc = get_runnable_count(procs, State),
		    % Update registered procs
		    % insert proc activity
		    update_activity(#activity{
		    	id = Id, 
			state = State, 
			timestamp = TS, 
			runnable_count = Rc,
			where = Mfa}),
		    ok
            end;
	%%% erlang:system_profile, option: runnable_ports
    	%%% ---------------------------------------------
	{profile, Id, State, Mfa, TS} when is_port(Id) ->
	    case check_activity_consistency(Id, State) of
		invalid_state -> 
		    ignored;
		ok ->
		    % Update runnable count in activity and db
		    Rc = get_runnable_count(ports, State),
	    
		    % Update registered ports
		    % insert port activity
		    update_activity(#activity{
		    	id = Id, 
			state = State, 
			timestamp = TS, 
			runnable_count = Rc,
			where = Mfa}),

		    ok
	    end;
	%%% erlang:system_profile, option: scheduler
	{profile, scheduler, Id, State, NoScheds, Ts} ->
            % insert scheduler activity
            update_scheduler(#activity{
	    	id = {scheduler, Id}, 
		state = State, 
		timestamp = Ts, 
		where = NoScheds});
         %%% erlang:trace, option: procs
         %%% ---------------------------
        {trace_ts, Parent, spawn, Pid, Mfa, TS} ->
            InformativeMfa = mfa2informative(Mfa),
            update_information(
              #information{id = Pid, start = TS, 
                           parent = Parent, entry = InformativeMfa}),
            update_information_child(Parent, Pid),
	    ok;
	{trace_ts, Pid, exit, _Reason, TS} ->
            update_information(#information{id = Pid, stop = TS}),
            ok;
	{trace_ts, Pid, register, Name, _Ts} when is_pid(Pid) ->
	    % Update id_information
	    update_information(#information{id = Pid, name = Name}),
	    ok;
	{trace_ts, _Pid, unregister, _Name, _Ts} -> 
	    % Not implemented
	    ok;
	{trace_ts, Pid, getting_unlinked, _Id, _Ts} when is_pid(Pid) ->
	    % Update id_information
	    ok;
	{trace_ts, Pid, getting_linked, _Id, _Ts} when is_pid(Pid)->
	    % Update id_information
	    ok;
	{trace_ts, Pid, link, _Id, _Ts} when is_pid(Pid)->
	    % Update id_information
	    ok;
	{trace_ts, Pid, unlink, _Id, _Ts} when is_pid(Pid) ->
	    % Update id_information
	    ok;
        {trace_ts, Pid, in, Rq,  _MFA, Ts} when is_pid(Pid) ->
            %% erlang:put(Pid, Ts),
             update_information_rq(Pid, Rq);
        {trace_ts, Pid, out, _Rq,  _MFA, Ts} when is_pid(Pid) ->
            %% case erlang:get(Pid) of 
            %%     undefined -> io:format("No In time\n");
            %%     InTime ->
            %%         Elapsed = elapsed(InTime, Ts),
            %%         erlang:erase(Pid),
            %%         ets:update_counter(pdb_info, Pid, {13, Elapsed})
            %% end;
            ok;
        {trace_ts, Pid, 'receive', MsgSize, _Ts} when is_pid(Pid)->
            update_information_received(Pid, erlang:external_size(MsgSize));
        {trace_ts, Pid, send, MsgSize, To, _Ts} when is_pid(Pid) ->
            update_information_sent(Pid, erlang:external_size(MsgSize), To);
        {trace_ts, Pid, send_to_non_existing_process, Msg, _To, _Ts} when is_pid(Pid) ->
            update_information_sent(Pid, erlang:external_size(Msg), none);
      	%%erlang:trace, option: ports
	%%% ----------------------------
	{trace_ts, Caller, open, Port, Driver, TS} ->
	    % Update id_information
	    update_information(#information{
	    	id = Port, entry = Driver, start = TS, parent = Caller}),
	    ok;
	{trace_ts, Port, closed, _Reason, Ts} ->
	    % Update id_information
	    update_information(#information{id = Port, stop = Ts}),
	    ok;

         %%function call/returns.
         %%% ----------------------------
        {trace_ts, Pid, call, MFA,{cp, CP}, TS} ->
            Func = mfarity(MFA),
            trace_call(Pid, Func, TS, CP);
        {trace_ts, Pid, return_to, MFA, TS} ->
            Func = mfarity(MFA),
            trace_return_to(Pid, Func, TS);
        _Unhandled ->
            %% io:format("insert_trace, unhandled: ~p~n", [_Unhandled]),
            ok
    end.



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
consolidate_db() ->
    io:format("Consolidating...~n"),
    % Check start/stop timestamps
    case select_query({system, start_ts}) of
	undefined ->
            case list_all_ts() of 
                [] -> ok;
                TSs ->
                    Min = lists:min(TSs),
                    update_system_start_ts(Min)
            end;
        _ -> ok
    end,
    case select_query({system, stop_ts}) of
	undefined ->
            case list_all_ts() of
                [] -> [];
                TSs1 ->
                    Max = lists:max(TSs1),
                    update_system_stop_ts(Max)
            end;
        _ -> ok
    end,
    consolidate_runnability(),
    consolidate_calltree(),
    gen_fun_info(),
    ok.

list_all_ts() ->
    ATs = [Act#activity.timestamp || Act <- select_query({activity, []})],
    STs = [Act#activity.timestamp || Act <- select_query({scheduler, []})],
    ITs = lists:flatten([
	[I#information.start, 
	 I#information.stop] || 
	 I <- select_query({information, all})]),
    %% Filter out all undefined (non ts)
    [Elem || Elem = {_,_,_} <- ATs ++ STs ++ ITs].

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
    case {get({runnable, Type}), State} of 
    	{undefined, active} -> 
	    put({runnable, Type}, 1),
	    1;
	{N, active} ->
	    put({runnable, Type}, N + 1),
	    N + 1;
	{N, inactive} ->
	    put({runnable, Type}, N - 1),
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
select_query(Query) ->
  %%  io:format("Query1:\n~p\n", [Query]),
    case Query of
	{system, _ } -> 
	    select_query_system(Query);
	{activity, _ } -> 
	    select_query_activity(Query);
    	{scheduler, _} ->
	    select_query_scheduler(Query);
	{information, _ } -> 
	    select_query_information(Query);
        {code, _} ->
            select_query_func(Query);
        {funs, _} ->
            select_query_func(Query);
        Unhandled ->
	    io:format("select_query, unhandled: ~p~n", [Unhandled]),
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
   
start_child_process(Name, Fun) ->
    Parent=self(),
    spawn_link(fun()-> Fun(Parent) end),
    receive
        {Name, started} ->
            ok
    end.      

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_warnings               %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_warnings(Parent) ->
    register(pdb_warnings, self()),
    ets:new(pdb_warnings, [named_table, private, {keypos, 1}, ordered_set]),
    Parent !{pdb_warnings, started},
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
init_pdb_activity(Parent) ->
    register(pdb_activity, self()),
    ets:new(pdb_activity, [named_table, private, {keypos, #activity.timestamp}, ordered_set]),
    Parent !{pdb_activity, started},
    pdb_activity_loop().

update_activity(Activity) ->
    pdb_activity ! {update_activity, Activity}.
    
consolidate_runnability() ->
    pdb_activity ! {consolidate_runnability, self()},
    receive
        {pdb_activity, done} ->
            ok
    end.

select_query_activity(Query) ->
    pdb_activity ! {query_pdb_activity, self(), Query},
    receive
        {pdb_activity, Res} ->
            Res
    end.

pdb_activity_loop()->
    receive 
        {update_activity, Activity} ->
            update_activity_1(Activity),
            pdb_activity_loop();
        {consolidate_runnability, From} ->
            ok=consolidate_runnability_1(), 
            From!{pdb_activity, done},
            pdb_activity_loop();
        {query_pdb_activity, From, Query} ->
            Res = select_query_activity_1(Query),
            From !{pdb_activity, Res},
            pdb_activity_loop();
        {action, stop} ->
            ok            
    end.

update_activity_1(Activity) ->
    ets:insert(pdb_activity, Activity).

consolidate_runnability_1() ->
    put({runnable, procs}, undefined),
    put({runnable, ports}, undefined),
    consolidate_runnability_loop(ets:first(pdb_activity)).

consolidate_runnability_loop('$end_of_table') -> ok;
consolidate_runnability_loop(Key) ->
    case ets:lookup(pdb_activity, Key) of
	[#activity{id = Id, state = State } = A] when is_pid(Id) ->
	    Rc = get_runnable_count(procs, State),
	    ets:insert(pdb_activity, A#activity{ runnable_count = Rc});
	[#activity{id = Id, state = State } = A] when is_port(Id) ->
	    Rc = get_runnable_count(ports, State),
	    ets:insert(pdb_activity, A#activity{ runnable_count = Rc});
	_ -> throw(consolidate)
    end,
    consolidate_runnability_loop(ets:next(pdb_activity, Key)).

%%% select_query_activity
select_query_activity_1(Query) ->
    case Query of
    	{activity, Options} when is_list(Options) ->
	    case lists:member({ts_exact, true},Options) of
		true ->
		    case catch select_query_activity_exact_ts(Options) of
			{'EXIT', Reason} ->
	    		    io:format(" - select_query_activity [ catch! ]: ~p~n", [Reason]),
			    [];
		    	Match ->
			    Match
		    end;		    
		false ->
		    MS = activity_ms(Options),
		    case catch ets:select(pdb_activity, MS) of
			{'EXIT', Reason} ->
	    		    io:format(" - select_query_activity [ catch! ]: ~p~n", [Reason]),
			    [];
		    	Match ->
			    Match
		    end
	    end;
	Unhandled ->
	    io:format("select_query_activity, unhandled: ~p~n", [Unhandled]),
    	    []
    end.

select_query_activity_exact_ts(Options) ->
    case { proplists:get_value(ts_min, Options, undefined), proplists:get_value(ts_max, Options, undefined) } of
	{undefined, undefined} -> [];
	{undefined, _        } -> [];
	{_        , undefined} -> [];
	{TsMin    , TsMax    } ->
	    % Remove unwanted options
	    Opts = lists_filter([ts_exact], Options),
	    Ms = activity_ms(Opts),
	    case ets:select(pdb_activity, Ms) of
		% no entries within interval
		[] -> 
		    Opts2 = lists_filter([ts_max, ts_min], Opts) ++ [{ts_min, TsMax}],
		    Ms2   = activity_ms(Opts2),
		    case ets:select(pdb_activity, Ms2, 1) of
			'$end_of_table' -> [];
			{[E], _}  -> 
			    [PrevAct] = ets:lookup(pdb_activity, ets:prev(pdb_activity, E#activity.timestamp)),
			    [PrevAct#activity{ timestamp = TsMin} , E] 
		    end;
		Acts ->
		    [Head| _] = Acts,
		    if
			Head#activity.timestamp == TsMin -> Acts;
			true ->
			    PrevTs = ets:prev(pdb_activity, Head#activity.timestamp),
			    case ets:lookup(pdb_activity, PrevTs) of
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
init_pdb_scheduler(Parent) ->
    register(pdb_scheduler, self()),
    ets:new(pdb_scheduler, [named_table, private, {keypos, #activity.timestamp}, ordered_set]),
    Parent !{pdb_scheduler, started},
    pdb_scheduler_loop().
    
update_scheduler(Activity) ->
    pdb_scheduler ! {update_scheduler, Activity}.

select_query_scheduler(Query) ->
    pdb_scheduler ! {'query_pdb_scheduler', Query},
    receive
        {pdb_scheduler, Res} ->
            Res
    end.
    

pdb_scheduler_loop()->
    receive
        {update_scheduler, Activity} ->
            update_scheduler_1(Activity),
            pdb_scheduler_loop();
        {select_query_scheduler, From, Query} ->
            Res=select_query_scheduler_1(Query),
            From !{pdb_scheduler, Res},
            pdb_scheduler_loop();
        {action, stop} ->
            ok
    end.

update_scheduler_1(Activity) ->
    ets:insert(pdb_scheduler, Activity).

select_query_scheduler_1(Query) ->
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
	    ets:select(pdb_scheduler, [{Head, Constraints, Body}]);
	Unhandled ->
	    io:format("select_query_scheduler, unhandled: ~p~n", [Unhandled]),
	    []
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_info                   %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_info(Parent)->  
    register(pdb_info, self()),
    ets:new(pdb_info, [named_table, private, {keypos, #information.id}, set]),
    Parent ! {pdb_info, started},
    pdb_info_loop().

update_information(Info) ->
    pdb_info!{update_information, Info}.

update_information_child(Id, Child) ->
    pdb_info!{update_information_child, {Id, Child}}.

update_information_rq(Pid, Rq) ->
    pdb_info!{update_information_rq, {Pid, Rq}}.

update_information_sent(From, MsgSize, To) ->
    pdb_info!{update_information_sent, {From, MsgSize, To}}.

update_information_received(Pid, MsgSize)->
    pdb_info!{update_information_received, {Pid, MsgSize}}.

update_information_element(Key, {Pos, Value}) ->
    pdb_info ! {update_information_element, {Key, {Pos, Value}}}.

%%% select_query_information
select_query_information(Query) ->
   %% io:format("Query info:\n~p\n", [Query]),
    pdb_info !{'query_pdb_info', self(), Query},
    receive 
        {pdb_info, Res} ->
            Res
    end.

pdb_info_loop()->
    receive
        {update_information, #information{id=Id}=NewInfo} ->
            update_information_1(NewInfo),
            pdb_info_loop();
        {update_information_child, {Id, Child}} ->
            update_information_child_1(Id, Child),
            pdb_info_loop();
        {update_information_rq, {Pid, Rq}} ->
            update_information_rq_1(Pid, Rq),
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
            From!{pdb_info, Res},
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
			{0,0,0,0} ->
                             {Tail, [InfoElem | Out]};
                        {0,0} ->
                            {Tail, [InfoElem | Out]};
                        0 ->
                            {Tail, [InfoElem|Out]};
                        _ ->
			    {Tail, [NewInfoElem | Out]}
		    end
		end, {tuple_to_list(NewInfo), []}, tuple_to_list(Info)),
            ets:insert(pdb_info, list_to_tuple(lists:reverse(Result))),
	    ok
    end.

update_information_child_1(Id, Child) -> 
    case ets:lookup(pdb_info, Id) of
    	[] ->
	    ets:insert(pdb_info,#information{
	    	id = Id,
		children = [Child]}),
	    ok;
	[I] ->
	    ets:insert(pdb_info,I#information{children = [Child | I#information.children]}),
	    ok
    end.

update_information_rq_1(Pid, Rq) ->
    case  ets:lookup(pdb_info, Pid) of
        [] -> 
            ok; %% this should not happen;
        [I] ->
            case I#information.rq_history of 
                [Rq|_] ->
                    ok;
                _ ->
                    ets:update_element(
                      pdb_info, Pid, {9, [Rq|I#information.rq_history]})
            end
    end.
                
update_information_sent_1(From, MsgSize, To) ->
    case  ets:lookup(pdb_info, From) of
        [] -> 
            ok; %% this should not happen;
        [I] ->
            {No, SameRq, OtherRq,  Size} = I#information.msgs_sent,
            NewSize = Size + MsgSize, 
            NewNo = No +1,
            if To==none ->
                    Data = {NewNo, SameRq,OtherRq + 1,  NewSize},
                    ets:update_element(pdb_info, From, {12, Data});
               true ->
                    case ets:lookup(pdb_info, To) of 
                        [R] ->
                            case R#information.rq_history of 
                                [Rq|_] ->
                                    case I#information.rq_history of 
                                        [Rq|_] ->
                                            Data = {NewNo,SameRq + 1, OtherRq,  NewSize},
                                            ets:update_element(pdb_info, From,
                                                               {12, Data});
                                        _ ->
                                            Data = {NewNo, SameRq, OtherRq + 1,NewSize},
                                            ets:update_element(pdb_info, From,
                                                               {12, Data})
                                    end;
                                _ ->
                                    Data = {NewNo, SameRq + 1, OtherRq, NewSize},
                                    ets:update_element(pdb_info, From,
                                                       {12, Data})
                            end;
                        _ ->
                            Data = {NewNo, SameRq + 1, OtherRq, NewSize},
                            ets:update_element(pdb_info, From, {12, Data})
                    end
            end
    end.


update_information_received_1(Pid, MsgSize) ->
    case  ets:lookup(pdb_info, Pid) of
        [] -> 
            ok; %% this should not happen;
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
           
init_pdb_system(Parent)->  
    register(pdb_system, self()),
    ets:new(pdb_system, [named_table, private, {keypos, 1}, set]),
    Parent ! {pdb_system, started},
    pdb_system_loop().

update_system_start_ts(TS) ->
    pdb_system ! {'update_system_start_ts', TS}.

update_system_stop_ts(TS) ->
    pdb_system ! {'update_system_stop_ts', TS}.

select_query_system(Query) ->
    %% io:format("whereis pdb_system:~p\n", [whereis(pdb_system)]),
    pdb_system ! {'query_system', self(), Query},
    receive
        {pdb_system, Res} ->
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
            From ! {pdb_system, Res},
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
	  
gen_process_tree() ->
    io:format("Gen process tree\n"),
    List = lists:keysort(2,select_query({information, procs})),
    gen_process_tree(List, []).

gen_process_tree([], Out) ->
    add_ancestors(Out);
gen_process_tree([Elem|Tail], Out) ->
    Children = Elem#information.children,
    {ChildrenElems, Tail1} = lists:partition(fun(E) -> 
                                                     lists:member(E#information.id, Children)
                                         end, Tail),
    {NewChildren, NewTail}=gen_process_tree_1(ChildrenElems, Tail1, []),
    gen_process_tree(NewTail, [{Elem, NewChildren}|Out]).


gen_process_tree_1([], Tail, NewChildren) ->
    {NewChildren, Tail};
gen_process_tree_1([C|Cs], Tail, Out) ->
    Children = C#information.children,
    {ChildrenElems, Tail1} = lists:partition(fun(E) -> 
                                                     lists:member(E#information.id, Children)
                                             end, Tail),
    {NewChildren, NewTail}=gen_process_tree_1(ChildrenElems, Tail1, []),
    gen_process_tree_1(Cs, NewTail, [{C, NewChildren}|Out]).
      
add_ancestors(ProcessTree) ->
    add_ancestors(ProcessTree, []).

add_ancestors(ProcessTree, As) ->
    [begin 
         update_information_element(Parent#information.id, {8, As}),
         {Parent#information{ancestors=As},         
          add_ancestors(Children, [Parent#information.id|As])}
     end
     ||{Parent, Children} <- ProcessTree].
  
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                  %%
%%             access to pdb_func                   %%
%%                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
init_pdb_func(Parent) ->
    register(pdb_func, self()),
    ets:new(funcall_info, [named_table, private, {keypos, #funcall_info.id}, ordered_set]),
    ets:new(fun_calltree, [named_table, private, {keypos, #fun_calltree.id}, ordered_set]),
    ets:new(fun_info, [named_table, private, {keypos, #fun_info.id}, ordered_set]),
    Parent !{pdb_func, started},
    pdb_func_loop().

trace_call(Pid, Func, TS, CP) ->
    pdb_func ! {trace_call, {Pid, Func, TS, CP}}.

trace_return_to(Pid, Caller, TS) ->
    pdb_func !{trace_return_to, {Pid, Caller, TS}}.

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

pdb_func_loop()->
    receive
        {trace_call, {Pid, Func, TS, CP}} ->
            trace_call_1(Pid, Func, TS, CP),
            pdb_func_loop();
        {trace_return_to, {Pid, Func, TS}} ->
            trace_return_to_1(Pid, Func, TS),
            pdb_func_loop();
        {consolidate_calltree, From} ->
            ok=consolidate_calltree_1(),
            From!{pdb_func, consolidate_calltree_done},
            pdb_func_loop();
        {gen_fun_info, From} ->
            ok = gen_fun_info_1(),
            From !{pdb_func, gen_fun_info_done},
            pdb_func_loop();
        {query_pdb_func, From, Query} ->
            Res = select_query_func_1(Query),
            From !{pdb_func, Res},
            pdb_func_loop();
        {action, stop} ->
            ok 
    end.


select_query_func_1(Query) ->
    io:format("Querycode::\n~p\n", [Query]),
    case Query of 
        {code, Options} when is_list(Options) ->
            Head = #funcall_info{
              id={'$1', '$2'}, 
              end_ts='$3',
              _='_'},
            Body =  ['$_'],
            MinTs = proplists:get_value(ts_min, Options, undefined),
            MaxTs = proplists:get_value(ts_max, Options, undefined),
            Constraints = [{'not', {'orelse', {'>=',{const, MinTs},'$3'},{'>=', '$2', {const,MaxTs}}}}],
            %% Constraints = [{'>=', {const, MinTs}, '$2'}, {'>=', '$3', {const, MaxTs}}],
            io:format("Info:\n~p\n", [{Head, Constraints, Body}]),
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
        Unhandled ->
	    io:format("select_query_func, unhandled: ~p~n", [Unhandled]),
	    []
    end.        

trace_call_1(Pid, Func, TS, CP) -> 
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
            update_fun_calltree_info(Pid, {Func1, TS1, TS}, {Caller1, Caller1StartTs}),
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
            [update_fun_calltree_info(Pid, {Func2, TS2, TS}, {Caller1, Caller1StartTs})||
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


trace_return_to_1(Pid, Caller, TS) ->
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
            update_fun_calltree_info(Pid, {Func1, TS1, TS}, {Caller1, Caller1StartTs}),
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
            update_fun_info({Pid, Func0}, {TS1, TS}),
            update_fun_calltree_info(Pid, {Func0, TS1, TS}, {Caller, CallerStartTs});
         _ -> ok  %% garbage collect or suspend.
    end,
    if Level1 ==[dummy] ->
            trace_return_to_2(Pid, Func, TS, Stack1);
       true ->
            trace_return_to_2(Pid, Func, TS, [Level1|Stack1])
    end.
   
update_fun_info({Pid, Func}, {StartTs, EndTs}) ->
    Time = ?seconds(EndTs, StartTs),
    case ets:lookup(fun_info, {Pid, Func}) of 
        [] ->
            ets:insert(fun_info, #fun_info{id={Pid, Func}, call_count=1, acc_time=Time});
        [FunInfo] ->
            ets:update_element(fun_info, {Pid, Func}, [{7, FunInfo#fun_info.call_count+1},
                                                       {8, FunInfo#fun_info.acc_time+Time}])
    end.
         
update_fun_calltree_info(Pid, {Callee, StartTS0, EndTS}, {Caller, CallerStartTS0}) ->
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
   %% io:format("Collapse recursive calls\n"),
    {_Pid, Caller,_TS} = CallTree#fun_calltree.id,
    Children=CallTree#fun_calltree.called,
    case collect_children_to_merge(Children, {Caller, Callee}) of 
        {_, []} ->
         %%   io:format("Nothing to merge\n"),
            CallTree;
        {ToRemain, ToMerge} ->
           %% io:format("Something to merge\n"),
            NewCalled = lists:foldl(fun(C, Acc) ->
                                             add_new_callee(C, Acc)
                                    end, ToRemain, ToMerge),
          %%  io:format("OldCalled:\n~p\n", [Children]),
         %%   io:format("NewChilren:\n~p\n", [NewCalled]),
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
                          


%% Statistic information per function.
gen_fun_info_1()->         
    CallTrees=ets:tab2list(fun_calltree),
    [process_a_call_tree(CallTree)||CallTree<-CallTrees],
    ok.

process_a_call_tree(CallTree)->
    {Pid, MFA, Caller}=CallTree#fun_calltree.id,
    case MFA of 
        undefined ->
            Children=CallTree#fun_calltree.called,
            [process_a_call_tree(C)||C<-Children];
        _ ->
            case ets:lookup(fun_info, {Pid, MFA}) of 
                [] ->
                    NewEntry=#fun_info{id={Pid, MFA},
                                       callers = [{Caller, CallTree#fun_calltree.cnt}],
                                       called = [{element(2, C#fun_calltree.id), 
                                                  C#fun_calltree.cnt}
                                                 ||C<-CallTree#fun_calltree.called],
                                       start_ts= CallTree#fun_calltree.start_ts,
                                       end_ts = CallTree#fun_calltree.end_ts},
                    ets:insert(fun_info, NewEntry);
                [FunInfo] ->
                    NewFunInfo=FunInfo#fun_info{
                                 callers=add_to([{Caller, CallTree#fun_calltree.cnt}],
                                                FunInfo#fun_info.callers),
                                 called = add_to([{element(2, C#fun_calltree.id), 
                                                   C#fun_calltree.cnt}
                                                  ||C<-CallTree#fun_calltree.called],
                                                 FunInfo#fun_info.called),
                                 start_ts = lists:min([FunInfo#fun_info.start_ts,
                                                       CallTree#fun_calltree.start_ts]),
                                 end_ts = lists:max([FunInfo#fun_info.end_ts,
                                                     CallTree#fun_calltree.end_ts])},
                    ets:insert(fun_info, NewFunInfo)
            end,
            Children=CallTree#fun_calltree.called,
            [process_a_call_tree(C)||C<-Children]
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
                         

elapsed({Me1, S1, Mi1}, {Me2, S2, Mi2}) ->
    Me = (Me2 - Me1) * 1000000,
    S  = (S2 - S1 + Me) * 1000000,
    Mi2 - Mi1 + S.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                                      %% 
%%                Callgraph Generlisation.                              %%
%%                                                                      %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

gen_callgraph_img(Pid) ->
    [Tree]=ets:select(fun_calltree, 
                      [{#fun_calltree{id = {'$1', '_','_'}, _='_'},
                        [{'==', '$1', Pid}],
                        ['$_']
                       }]),
    gen_callgraph_img_1(Pid, Tree).
   
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
    file:delete(DotFileName).



   

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
digraph_add_edges([], NodeIndex, MG)-> 
    NodeIndex;
digraph_add_edges(Edge={_From, _To, _CNT}, NodeIndex, MG) ->
    digraph_add_edge(Edge, NodeIndex, MG);
digraph_add_edges([Edge={_From, _To, _CNT}|Children], NodeIndex, MG) ->
    NodeIndex1=digraph_add_edge(Edge, NodeIndex, MG),
    lists:foldl(fun(Tree, IndexAcc) ->
                        digraph_add_edges(Tree, IndexAcc, MG)
                end, NodeIndex1, Children);
digraph_add_edges(Trees=[Tree|_Ts], NodeIndex, MG) when is_list(Tree)->
    lists:foldl(fun(Tree, IndexAcc) ->
                        digraph_add_edges(Tree, IndexAcc, MG)
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

    
%% fprof:apply(refac_sim_code_par_v0,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"], 8]). 

%% percept_profile:start({ip, 4711}, {refac_sim_code_par_v4,sim_code_detection, [["c:/cygwin/home/hl/percept/test"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/percept/test"], 8]}, [])  

%%percept_profile:start({file, "sim_code_v0.dat"}, {refac_sim_code_par_v0,sim_code_detection, [["c:/cygwin/home/hl/demo/c.erl"], 5, 40, 2, 4, 0.8, [], 8]}, [refac_sim_code_par_v0],[])
%% percept_profile:start({file, "foo3.dat"}, {foo,a1, [1]}, [foo], []).


%% percept2_db:gen_callgraph_img(list_to_pid("<0.1132.0>")).

%% percept2:profile({file, "mergesort.dat"}, {mergesort, msort_lte,[lists:reverse(lists:seq(1,2000))]}, [message, process_scheduling, concurreny,garbagage_collection,{function, [{mergesort, '_','_'}]}]).

%% percept2:analyze("mergesort.dat").

%% percept2:profile({file, "sim_code_v3.dat"}, {refac_sim_code_par_v3,sim_code_detection, [["c:/cygwin/home/hl/test"], 5, 40, 2, 4, 0.8, [], 8]},  [message, process_scheduling, concurreny,{function, [{refac_sim_code_par_v0, '_','_'}]}]).

%% To profile percept itself.
%% percept2:profile({file, "percept.dat"}, {percept2,analyze, ["sim_code_v2.dat"]},  [message, process_scheduling, concurreny,{function, [{percept2_db, '_','_'}, {percept2, '_','_'}]}]).
 %%percept2:analyze("percept.dat").
