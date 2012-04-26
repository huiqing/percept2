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

-module(percept_db).

-export([
	start/0,
	stop/0,
	insert/1,
	select/2,
	select/1,
	consolidate/0
	]).

-export([gen_process_tree/0]).
        
-compile(export_all).

-include("percept.hrl").

-define(STOP_TIMEOUT, 1000).

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
        stop_sync(PerceptDB),
        do_start().

%% @spec do_start() -> pid()
%% @private
%% @doc starts the percept database.

-spec do_start()-> pid().

do_start()->
    Pid = spawn( fun() -> init_percept_db() end),
    erlang:register(percept_db, Pid),
    Pid.

%% @spec stop() -> not_started | {stopped, Pid}
%%	Pid = pid()
%% @doc Stops the percept database.

-spec stop() -> 'not_started' | {'stopped', pid()}.

stop() ->
    case erlang:whereis(percept_db) of
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
    stop(),
    receive
        {'DOWN', MonitorRef, _Type, Pid, _Info}->
            true
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
    percept_db ! {action, consolidate},
    ok.

%%==========================================================================
 %%
%% 		Database loop 
%%
%%==========================================================================

init_percept_db() ->
    % Proc and Port information
    ets:new(pdb_info, [named_table, public, {keypos, #information.id}, set]),

    % Scheduler runnability
    ets:new(pdb_scheduler, [named_table, public, {keypos, #activity.timestamp}, ordered_set]),
    
    % Process and Port runnability
    ets:new(pdb_activity, [named_table, public, {keypos, #activity.timestamp}, ordered_set]),
    
    % System status
    ets:new(pdb_system, [named_table, private, {keypos, 1}, set]),
    
    % System warnings
    ets:new(pdb_warnings, [named_table, private, {keypos, 1}, ordered_set]),

    %functions
    ets:new(funcall_info, [named_table, public, {keypos, #funcall_info.id}, ordered_set]),

    ets:new(fun_info, [named_table, public, {keypos, #fun_info.id}, ordered_set]),
  
    put(debug, 0),
    loop_percept_db().

loop_percept_db() ->
    receive
        {insert, Trace} ->
            insert_trace(clean_trace(Trace)),
            loop_percept_db();
	{select, Pid, Query} ->
	    Pid ! {result, select_query(Query)},
	    loop_percept_db();
	{action, stop} -> 
	    stopped;
	{action, consolidate} ->
	    consolidate_db(),
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
		where = NoScheds}),
	    ok;

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
        {trace_ts, Pid, in, Rq,  _MFA, _Ts} when is_pid(Pid) ->
           update_information_rq(Pid, Rq);
        {trace_ts, Pid, out, _Rq,  _MFA, _Ts} when is_pid(Pid) ->
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
        {trace_ts, Pid, call, MFA,{cp, CP}, TS} ->
            %% io:format("Trace:\n~p\n", [Trace]),
            Func = mfarity(MFA),
            trace_call(Pid, Func, TS, CP);
        {trace_ts, Pid, return_to, undefined, TS}->
            %% io:format("Trace:\n~p\n", [Trace]),
            trace_return_to(Pid, undefined, TS);
        {trace_ts, Pid, return_to, MFA, TS} ->
           %% io:format("Trace:\n~p\n", [Trace]),
            Func = mfarity(MFA),
            trace_return_to(Pid, Func, TS);
        _Unhandled ->
           %% io:format("insert_trace, unhandled: ~p~n", [_Unhandled]),
          ok
    end.

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
	    Min = lists:min(list_all_ts()),
	    update_system_start_ts(Min);
	_ -> ok
    end,
    case select_query({system, stop_ts}) of
	undefined ->
	    Max = lists:max(list_all_ts()),
	    update_system_stop_ts(Max);
	_ -> ok
    end,
    consolidate_runnability(),
    ok.

consolidate_runnability() ->
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
          %%  io:format("check_activity_consistency, state flow invalid.~n"),
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
            select_query_code(Query);
        {funs, _} ->
            select_query_funs(Query);
        Unhandled ->
	    io:format("select_query, unhandled: ~p~n", [Unhandled]),
	    []
    end.

%%% select_query_information

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
		#information{ id = '$1', _ = '_'},
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

%%% select_query_scheduler

select_query_scheduler(Query) ->
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
	Unhandled ->
	    io:format("select_query_system, unhandled: ~p~n", [Unhandled]),
	    []
    end.

%%% select_query_activity

select_query_activity(Query) ->
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

select_query_code(Query) ->
    io:format("Query:\n~p\n", [Query]),
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
        Unhandled ->
	    io:format("select_query_code, unhandled: ~p~n", [Unhandled]),
	    []
    end.  
               
      
select_query_funs(Query) ->
    case Query of 
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
	    io:format("select_query_funs, unhandled: ~p~n", [Unhandled]),
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

update_information(#information{id = Id} = NewInfo) ->
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
                        _ ->
			    {Tail, [NewInfoElem | Out]}
		    end
		end, {tuple_to_list(NewInfo), []}, tuple_to_list(Info)),
            ets:insert(pdb_info, list_to_tuple(lists:reverse(Result))),
	    ok
    end.

update_information_child(Id, Child) -> 
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

update_information_rq(Pid, Rq) ->
    case  ets:lookup(pdb_info, Pid) of
        [] -> 
            ok; %% this should not happen;
        [I] ->
            case I#information.rq_history of 
                [Rq|_] ->
                    ok;
                _ ->
                 %%   io:format("Rq:\n~pn", [[Rq|I#information.rq_history]]),
                    ets:update_element(
                      pdb_info, Pid, {9, [Rq|I#information.rq_history]})
            end
    end.
                
update_information_sent(From, MsgSize, To) ->
    case  ets:lookup(pdb_info, From) of
        [] -> 
            ok; %% this should not happen;
        [I] ->
            {No, SameRq, OtherRq,  Size} = I#information.msgs_sent,
            NewSize = Size + MsgSize, 
            NewNo = No +1,
            if To==none ->
                    Data = {NewNo, SameRq,OtherRq + 1,  NewSize},
                    update_information_sent_1(From,Data);
               true ->
                    case ets:lookup(pdb_info, To) of 
                        [R] ->
                            case R#information.rq_history of 
                                [Rq|_] ->
                                    case I#information.rq_history of 
                                        [Rq|_] ->
                                            Data = {NewNo,SameRq + 1, OtherRq,  NewSize},
                                            update_information_sent_1(From,Data);
                                        _ ->
                                            Data = {NewNo, SameRq, OtherRq + 1,NewSize},
                                            update_information_sent_1(From,Data)
                                    end;
                                _ ->
                                    Data = {NewNo, SameRq + 1, OtherRq, NewSize},
                                    update_information_sent_1(From, Data)
                            end;
                        _ ->
                            Data = {NewNo, SameRq + 1, OtherRq, NewSize},
                            update_information_sent_1(From, Data)
                    end
            end
    end.

update_information_sent_1(From, Data) ->
    ets:update_element(pdb_info, From, {12, Data}).

                               

update_information_received(Pid, MsgSize) ->
    case  ets:lookup(pdb_info, Pid) of
        [] -> 
            ok; %% this should not happen;
        [I] ->
            {No, Size} = I#information.msgs_received,
            ets:update_element(pdb_info, Pid,
                               {11, {No+1, Size+MsgSize}})
    end.
    
            

%%%
%%% update_activity
%%%
update_scheduler(Activity) ->
    ets:insert(pdb_scheduler, Activity).

update_activity(Activity) ->
    ets:insert(pdb_activity, Activity). 

%%%
%%% update_system_ts
%%%

update_system_start_ts(TS) ->
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
	
update_system_stop_ts(TS) ->
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
	  
gen_process_tree() ->
    List = lists:keysort(2, ets:tab2list(pdb_info)),
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
         ets:update_element(pdb_info, Parent#information.id, {8, As}),
         {Parent#information{ancestors=As},         
          add_ancestors(Children, [Parent#information.id|As])}
     end
      ||{Parent, Children} <- ProcessTree].

   
mfarity({M, F, Args}) when is_list(Args) ->
    {M, F, length(Args)};
mfarity(MFA) ->
    MFA.


trace_call(Pid, Func, TS, CP) ->
    Stack = get_stack(Pid),
    ?dbg(0, "trace_call(~p, ~p, ~p, ~p)~n~p~n", 
	 [Pid, Func, TS, CP, Stack]),
    trace_call_1(Pid, Func, TS, CP, Stack).
    

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
        [[{Func0, FirstInTS}]] ->
            OldStack = [[{CP, FirstInTS}]],
            put(Pid, trace_call_push(Func, TS, OldStack));
	[[{CP, _} | _], [{CP, _} | _] | _] ->
            put(Pid, trace_call_shove(Func, TS, Stack));
	[[{CP, _} | _] | _] ->
            ?dbg(0, "Current function becomes new stack top.\n", []),
            put(Pid, trace_call_push(Func, TS, Stack));
      	[_, [{CP, _} | _] | _] ->
            ?dbg(0, "Stack top unchanged, no push.\n", []),
            put(Pid, trace_call_shove(Func, TS, Stack));
        [[{Func0, _} | _], [{Func0, _} | _], [{CP, _} | _] | _] ->
             put(Pid, 
                 trace_call_shove(Func, TS,
                                  trace_return_to_1(Pid, Func0, TS,
                                                    Stack)));
        [_ | _] ->
            put(Pid, [[{Func, TS}], [{CP, TS}, dummy]|Stack])
    end,
    ok.

%% Normal stack push
trace_call_push(Func, TS, Stack) ->
    [[{Func, TS}] | Stack].
 
%% Tail recursive stack push
trace_call_shove(Func, TS, Stack) ->
    [[_ | NewLevel0] | NewStack1] = 
	case Stack of
	    [] ->
		[[{Func, TS}]];
	    [Level0 | Stack1] ->
		[trace_call_collapse([{Func, TS} | Level0]) | Stack1]
	end,
    [[{Func, TS} | NewLevel0] | NewStack1].
 
%% Collapse tail recursive call stack cycles to prevent them from
%% growing to infinite length.
trace_call_collapse([]) ->
    [];
trace_call_collapse([_] = Stack) ->
    Stack;
trace_call_collapse([_, _] = Stack) ->
    Stack;
trace_call_collapse([_ | Stack1] = Stack) ->
    ?dbg(0, "collapse_tace_state(~p)~n", [Stack]),
    Res=trace_call_collapse_1(Stack, Stack1, 1),
    ?dbg(0, "collapse_tace_state_result:~p~n", [Res]),
    Res.
        

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


trace_return_to(Pid, Caller, TS) ->
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
	[_ | _] ->
            NewStack = trace_return_to_1(Pid, Caller, TS, Stack),
            put(Pid, NewStack);
	[] ->
	    NewStack = trace_return_to_1(Pid, Caller, TS, Stack),
            put(Pid, NewStack)
    end.
   
trace_return_to_1(_, undefined, _, []) ->
    [];
trace_return_to_1(Pid, Func, TS, []) ->
    [[{Func, TS}]];
trace_return_to_1(Pid, Func, TS, [[] | Stack1]) ->
    trace_return_to_1(Pid, Func, TS, Stack1);
trace_return_to_1(_Pid, Func, TS, [[{Func, _}|Level0]|Stack1] = Stack)->
    Stack;
trace_return_to_1(Pid, Func, TS, [[{Func0, TS1} | Level1] | Stack1]) ->
    case Func0 of 
         {_, _, _} ->
            ets:insert(funcall_info, #funcall_info{id={Pid, TS1}, func=Func0, end_ts=TS}),
            {Caller, CallerStartTs}= case Level1 of 
                                         [{Func1, TS2}|_] ->
                                             {Func1, TS2};
                                         _ -> case Stack1 of 
                                                  [[{Func1, TS2}, dummy]|_] ->
                                                      {Func1, TS2};
                                                  [[{Func1, TS2}|_]|_]->
                                                      {Func1, TS2};
                                                  [] ->
                                                      io:format("Info1:\n~p\n", [{Pid, Func, TS, [[{Func0, TS1} | Level1] | Stack1]}]),
                                                      {Func, TS1}
                                              end
                                     end,
            %% io:format("Callers:\n~p\n", [{Caller, CallerStartTs}]),
            %% io:format("Info1:\n~p\n", [{Pid, Func, TS, [[{Func0, TS1} | Level1] | Stack1]}]),
            update_fun_info(Pid, {Func0, TS1, TS}, {Caller, CallerStartTs});
        _ -> ok  %% garbage collect or suspend.
    end,
    if Level1 ==[dummy] ->
            trace_return_to_1(Pid, Func, TS, Stack1);
       true ->
             trace_return_to_1(Pid, Func, TS, [Level1|Stack1])
    end.

update_fun_info(Pid, {Callee,StartTS, EndTs}, {Caller, CallerStartTs}) ->
    case ets:lookup(fun_info, {Pid, Callee}) of
        [] ->
            ets:insert(fun_info,
                       #fun_info{id={Pid, Callee},
                                 callers=[{Caller, 1}],
                                 start_ts = StartTS,
                                 end_ts = EndTs});
        [F=#fun_info{callers=Callers}] ->
            ets:insert(fun_info,
                       F#fun_info{callers=update_counter(Callers,Caller),
                                  end_ts = EndTs})
    end,
    case ets:lookup(fun_info, {Pid, Caller}) of
        [] ->
            ets:insert(fun_info,
                       #fun_info{id={Pid, Caller},
                                 called=[{Callee, 1}],
                                 start_ts=CallerStartTs});
        [F1=#fun_info{called=Called, start_ts=undefined}] ->
            ets:insert(fun_info,
                       F1#fun_info{called=update_counter(Called,Callee),
                                   start_ts=CallerStartTs});
        [F1=#fun_info{called=Called}] ->
            ets:insert(fun_info,
                       F1#fun_info{called=update_counter(Called,Callee)})
    end.

update_counter(FunCounterList, Func) ->
    case lists:keyfind(Func, 1, FunCounterList) of
        {Func, Count} ->
            lists:keyreplace(Func, 1, FunCounterList, {Func, Count+1});
        _ ->
            FunCounterList++[{Func, 1}]
    end.

get_stack(Id) ->
    case get(Id) of
	undefined ->
	    [];
	Stack ->
	    Stack
    end.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                            %%
%%  Generate function call tree from the trace.               %%
%%                                                            %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

gen_call_tree() ->
    List = ets:tab2list(fun_info),
    gen_call_tree_1(List).

gen_call_tree_1([]) ->
    [];
gen_call_tree_1([F|Tail]) ->
    {Pid,_} = F#fun_info.id,
    {Fs, NewTail} = lists:splitwith(fun(E)->
                                            element(1,E#fun_info.id)==Pid
                                    end, Tail),
    CallTree=[case Entry#fun_info.id of 
                  {_, undefined} ->
                      case Children of 
                          [_] -> hd(Children);
                          _ -> T
                      end;
                  _ ->T
              end||T={Entry, Children}<-gen_call_tree_2([F|Fs])]
        ++gen_call_tree_1(NewTail),    
    lists:sort(fun({T1,_}, {T2, _}) ->
                       T1#fun_info.start_ts=< T2#fun_info.start_ts
               end, CallTree).

gen_call_tree_2(Fs) ->
    case  [F||F<-Fs,F#fun_info.callers==[]] of 
        [Entry] ->
            gen_call_tree_3([Entry], Fs--[Entry], []);
        Others ->
            []
    end.

gen_call_tree_3([], _, Out)->
    lists:reverse(Out);
gen_call_tree_3([CurFun|Fs], Others, Out)->
    {Callees,_} = lists:unzip(CurFun#fun_info.called),
    {CalleeFuns,Funs1} = lists:partition(
                           fun(E)->
                                   FunName=element(2, E#fun_info.id),
                                   lists:member(FunName, Callees)
                           end, Others),
    NewCallees=gen_call_tree_3(CalleeFuns, Funs1, []),
    gen_call_tree_3(Fs, Others, [{CurFun, NewCallees}|Out]).
 



%% fprof:apply(refac_sim_code_par_v0,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"], 8]). 
%% percept_profile:start({ip, 4711}, {refac_sim_code_par_v4,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"], 8]}, [])

%% percept_profile:start({file, "sim_code_v0.dat"}, {refac_sim_code_par_v0,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"], 8]}, [])

%% percept_profile:start({file, "sim_code_v1.dat"}, {refac_sim_code_par_v1,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"], 8]}, []).


%% percept_profile:start({file, "sim_code_v2.dat"}, {refac_sim_code_par_v2,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"], 8]}, []).


%% percept_profile:start({file, "sim_code_v3.dat"}, {refac_sim_code_par_v3,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"], 8]}, []).


%% percept_profile:start({file, "sim_code_v4.dat"}, {refac_sim_code_par_v4,sim_code_detection, [["c:/cygwin/home/hl/demo"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/demo"], 8]}, [])


%% percept_profile:start({ip, 4711}, {refac_sim_code_par_v4,sim_code_detection, [["c:/cygwin/home/hl/percept/test"], 5, 40, 2, 4, 0.8, ["c:/cygwin/home/hl/percept/test"], 8]}, [])  

%%percept_profile:start({file, "sim_code_v0.dat"}, {refac_sim_code_par_v0,sim_code_detection, [["c:/cygwin/home/hl/demo/c.erl"], 5, 40, 2, 4, 0.8, [], 8]}, [refac_sim_code_par_v0],[])


%% percept_profile:start({file, "foo3.dat"}, {foo,a1, [1]}, [foo], []).
