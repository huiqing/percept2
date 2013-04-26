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

%% @doc Utility functions to operate on percept data. These functions should
%%	be considered experimental. Behaviour may change in future releases.

-module(percept2_analyzer).
-export([	
	waiting_activities/1,
	activities2count/2,
	activities2count/3,
	activities2count2/2,
	analyze_activities/2,
	runnable_count/1,
	runnable_count/2, minmax_activities/2,
	mean/1
	]).

-compile(export_all).

-include("../include/percept2.hrl").

-define(ts(EndTs,StartTs), timer:now_diff(EndTs, StartTs)).

%%==========================================================================
%%
%% 		Interface functions
%%
%%==========================================================================
%% @spec mean([number()]) -> {Mean, StdDev, N}
%%	Mean = float()
%%	StdDev = float()
%%	N = integer()
%% @doc Calculates the mean and the standard deviation of a set of
%%	numbers.

%% mean([])      -> {0, 0, 0}; 
%% mean([Value]) -> {Value, 0, 1};
%% mean(List)    -> mean(List, {0, 0, 0}).

%% mean([], {Sum, SumSquare, N}) -> 
%%     Mean   = Sum / N,
%%     io:format("Mean:\n~p\n", [{Mean, SumSquare, (SumSquare - Sum*Sum/N)}]),
%%     StdDev = math:sqrt((SumSquare - Sum*Sum/N)/(N - 1)),
%%     {Mean, StdDev, N};
%% mean([Value | List], {Sum, SumSquare, N}) -> 
%%     mean(List, {Sum + Value, SumSquare + Value*Value, N + 1}).


mean([])      -> {0, 0, 0, 0}; 
mean([Value]) -> {Value, Value, 0, 1};
mean(List)    ->
    N = length(List),
    Total = lists:sum(List),
    Mean= Total/N,
    SumSquare=lists:sum([(V-Mean)*(V-Mean)||V<-List]),
    StdDev = math:sqrt(SumSquare/N),
    {Total, Mean, StdDev, N}.

%% mean([], {Sum, SumSquare, N}) -> 
%%     Mean   = Sum / N,
%%     io:format("Mean:\n~p\n", [{Mean, SumSquare, (SumSquare - Sum*Sum/N)}]),
%%     StdDev = math:sqrt((SumSquare - Sum*Sum/N)/(N - 1)),
%%     {Mean, StdDev, N};
%% mean([Value | List], {Sum, SumSquare, N}) -> 
%%     mean(List, {Sum + Value, SumSquare + Value*Value, N + 1}).


activities2count2(Acts, StartTs) -> 
    Start = inactive_start_states(Acts),
    activities2count2(Acts, StartTs, Start, dict:new(),[]).

activities2count2([], _, _, _, Out) -> lists:reverse(Out);
activities2count2([#activity{id = Id, timestamp = Ts, state = State} | Acts], StartTs, {Proc,Port}, StateDict, Out) ->
    case dict:find(Id, StateDict) of
        {ok, State} ->
            activities2count2(Acts, StartTs, {Proc, Port}, StateDict,
                              [{?seconds(Ts, StartTs), Proc, Port}|Out]);
        _ ->
            activities2count3([#activity{id = Id, timestamp = Ts, state = State} | Acts],
                              StartTs, {Proc, Port}, StateDict,Out)
                              %% [{?seconds(Ts, StartTs), Proc, Port}|Out])
    end.
                          
activities2count3([#activity{id = Id={pid, _}, timestamp = Ts, state = active} | Acts],
                  StartTs, {Proc,Port}, StateDict, Out) ->
    activities2count2(Acts, StartTs, {Proc + 1, Port}, dict:store(Id, active, StateDict),
                      [{?seconds(Ts, StartTs), Proc + 1, Port}|Out]);
activities2count3([#activity{ id =Id={pid, _}, timestamp = Ts, state = inactive} | Acts],
                  StartTs, {Proc,Port}, StateDict, Out) ->
    activities2count2(Acts, StartTs, {Proc - 1, Port}, dict:store(Id, inactive, StateDict),
                      [{?seconds(Ts, StartTs), Proc - 1, Port}|Out]);
activities2count3([#activity{ id = Id, timestamp = Ts, state = active} | Acts],
                  StartTs, {Proc,Port}, StateDict, Out) when is_port(Id) ->
    activities2count2(Acts, StartTs, {Proc, Port + 1}, dict:store(Id, active, StateDict),
                      [{?seconds(Ts, StartTs), Proc, Port + 1}|Out]);
activities2count3([#activity{ id = Id, timestamp = Ts, state = inactive} | Acts],
                  StartTs, {Proc,Port}, StateDict, Out) when is_port(Id) ->
    activities2count2(Acts, StartTs, {Proc, Port - 1}, dict:store(Id, inactive, StateDict),
                      [{?seconds(Ts, StartTs), Proc, Port - 1}|Out]).
inactive_start_states(Acts) ->
    D = activity_start_states(Acts, dict:new()),
    dict:fold(fun
        ({pid, _}, inactive, {Procs, Ports}) -> {Procs + 1, Ports};
        (K, inactive, {Procs, Ports}) when is_port(K) -> {Procs, Ports + 1};
        (_, _, {Procs, Ports}) -> {Procs, Ports}
    end, {0,0}, D).
activity_start_states([], D) -> D;
activity_start_states([#activity{id = Id, state = State}|Acts], D) ->
    case dict:is_key(Id, D) of
        true -> activity_start_states(Acts, D);
        false -> activity_start_states(Acts, dict:store(Id, State, D))
    end.


%% @spec activities2count(#activity{}, timestamp()) -> Result
%%	Result = [{Time, ProcessCount, PortCount}]
%%	Time = float()
%%	ProcessCount = integer()
%%	PortCount = integer()
%% @doc Calculate the resulting active processes and ports during
%%	the activity interval.
%%	Also checks active/inactive consistency.
%%	A task will always begin with an active state and end with an inactive state.

activities2count(Acts, StartTs) when is_list(Acts) -> activities2count(Acts, StartTs, separated).

activities2count(Acts, StartTs, Type) when is_list(Acts) -> 
    activities2count_loop(Acts, {StartTs, {0,0}}, Type, []).

activities2count_loop([], _, _, Out) -> lists:reverse(Out);
activities2count_loop(
	[#activity{timestamp = Ts, id = Id, runnable_procs=ProcsRc, runnable_ports=PortsRc} | Acts], 
	{StartTs, {Procs, Ports}}, separated, Out) ->
    
    Time = ?seconds(Ts, StartTs),
    case Id of 
	Id when is_port(Id) ->
	    Entry = {Time, Procs, PortsRc},
	    activities2count_loop(Acts, {StartTs, {Procs, PortsRc}}, separated, [Entry | Out]);
	{pid, _} ->
	    Entry = {Time, ProcsRc, Ports},
	    activities2count_loop(Acts, {StartTs, {ProcsRc, Ports}}, separated, [Entry | Out]);
	_ ->
   	    activities2count_loop(Acts, {StartTs,{Procs, Ports}}, separated, Out)
    end;
activities2count_loop(
	[#activity{ timestamp = Ts, id = Id, runnable_procs=ProcsRc,runnable_ports=PortsRc} | Acts], 
	{StartTs, {Procs, Ports}}, summated, Out) ->
	
    Time = ?seconds(Ts, StartTs), 
    case Id of 
	Id when is_port(Id) ->
	    Entry = {Time, Procs + PortsRc},
	    activities2count_loop(Acts, {StartTs, {Procs, PortsRc}}, summated, [Entry | Out]);
	{pid, _}  ->
	    Entry = {Time, ProcsRc + Ports},
	    activities2count_loop(Acts, {StartTs, {ProcsRc, Ports}}, summated, [Entry | Out])
    end.

%% @spec waiting_activities([#activity{}]) -> FunctionList
%%	FunctionList = [{Seconds, Mfa, {Mean, StdDev, N}}]
%%	Seconds = float()
%%	Mfa = mfa()
%%	Mean = float()
%%	StdDev = float()
%%	N = integer()
%% @doc Calculates the time, both average and total, that a process has spent
%%	in a receive state at specific function. However, if there are multiple receives
%%	in a function it cannot differentiate between them.

waiting_activities(Activities) ->
    ListedMfas = waiting_activities_mfa_list(Activities, []),
    Unsorted = lists:foldl(
    	fun (Mfa, MfaList) ->
                {_Total0, WaitingTimes} = get({waiting_mfa, Mfa}),
                % cleanup
                erlang:erase({waiting_mfa, Mfa}),
                % statistics of receive waiting places
                {Total, Mean, StdDev, N} = mean(WaitingTimes),
                [{Total, Mfa, {Mean, StdDev, N}} | MfaList]
	end, [], ListedMfas),
    lists:sort(fun ({A,_,_},{B,_,_}) ->
                       if 
                           A > B -> true;
                           true -> false 
                       end
               end, Unsorted).


%% Generate lists of receive waiting times per mfa
%% Out:
%%	ListedMfas = [mfa()]
%% Intrisnic:
%%	get({waiting, mfa()}) ->
%%	[{waiting, mfa()}, {Total, [WaitingTime]})
%%	WaitingTime = float()

waiting_activities_mfa_list([], ListedMfas) -> ListedMfas;
waiting_activities_mfa_list([Activity|Activities], ListedMfas) ->
    #activity{id = Pid, state = Act, timestamp = Time, where = MFA, in_out=_InOut} = Activity,
    if MFA == undefined ->
            waiting_activities_mfa_list(Activities, ListedMfas);
       true ->
            case Act of 
                active ->
                    waiting_activities_mfa_list(Activities, ListedMfas);
                inactive ->
                                                % Want to know how long the wait is in a receive,
                                                % it is given via the next activity
                    case Activities of
                        [] -> 
                            [Info] = percept2_db:select({information, Pid}),
                            case Info#information.stop of
                                undefined ->
                                                % get profile end time
                                    Waited = ?seconds((percept2_db:select({system,stop_ts})),Time);
                                Time2 ->
                                    Waited = ?seconds(Time2, Time)
                            end,
                            case get({waiting_mfa, MFA}) of
                                undefined ->
                                    put({waiting_mfa, MFA}, {Waited, [Waited]}),
                                    [MFA | ListedMfas];
                                {Total, TimedMfa} ->
                                    put({waiting_mfa, MFA}, {Total + Waited, [Waited | TimedMfa]}),
                                    ListedMfas
                            end;
                        [#activity{timestamp=Time2, id = Pid, state =active} | _ ] ->
                                                % Calculate waiting time
                            Waited = ?seconds(Time2, Time),
                                                % Get previous entry
                            case get({waiting_mfa, MFA}) of
                                undefined ->
                                                % add entry to list
                                    put({waiting_mfa, MFA}, {Waited, [Waited]}),
                                    waiting_activities_mfa_list(Activities, [MFA|ListedMfas]);
                                {Total, TimedMfa} ->
                                    put({waiting_mfa, MFA}, {Total + Waited, [Waited | TimedMfa]}),
                                    waiting_activities_mfa_list(Activities, ListedMfas)
                            end;
                        _ -> error
                    end
            end
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%	Analyze interval for concurrency
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @spec analyze_activities(integer(), [#activity{}]) -> [{integer(),#activity{}}]
%% @hidden

analyze_activities(Threshold, Activities) ->
    RunnableCount = runnable_count(Activities, 0),
    analyze_runnable_activities(Threshold, RunnableCount).


%% runnable_count(Activities, StartValue) -> RunnableCount
%% In:
%% 	Activities = [activity()]
%%	StartValue = integer()
%% Out:
%%	RunnableCount = [{integer(), activity()}]
%% Purpose:
%%	Calculate the runnable count of a given interval of generic
%% 	activities.

%% @spec runnable_count([#activity{}]) -> [{integer(),#activity{}}]
%% @hidden

runnable_count(Activities) ->
    Threshold = runnable_count_threshold(Activities),
    runnable_count(Activities, Threshold, []).

runnable_count_threshold(Activities) ->
    CountedActs = runnable_count(Activities, 0),
    Counts      = [C || {C, _} <- CountedActs],
    Min         = lists:min(Counts),
    0 - Min.
%% @spec runnable_count([#activity{}],integer()) -> [{integer(),#activity{}}]
%% @hidden

runnable_count(Activities, StartCount) when is_integer(StartCount) ->
    runnable_count(Activities, StartCount, []).
runnable_count([], _ , Out) ->
    lists:reverse(Out);
runnable_count([A | As], PrevCount, Out) ->
    case A#activity.state of 
	active ->
	    runnable_count(As, PrevCount + 1, [{PrevCount + 1, A} | Out]);
	inactive ->
	    runnable_count(As, PrevCount - 1, [{PrevCount - 1, A} | Out])
    end.

%% In:
%%	Threshold = integer(),
%%	RunnableActivities = [{Rc, activity()}]
%%	Rc = integer()

analyze_runnable_activities(Threshold, RunnableActivities) ->
    analyze_runnable_activities(Threshold, RunnableActivities, []).

analyze_runnable_activities( _z, [], Out) -> 
    lists:reverse(Out);
analyze_runnable_activities(Threshold, [{Rc, Act} | RunnableActs], Out) ->
    if 
	Rc =< Threshold ->
	    analyze_runnable_activities(Threshold, RunnableActs, [{Rc,Act} | Out]);
	true ->
	    analyze_runnable_activities(Threshold, RunnableActs, Out)
    end.

%% minmax_activity(Activities, Count) -> {Min, Max}
%% In:
%%	Activities = [activity()]
%%	InitialCount = non_neg_integer()
%% Out:
%%	{Min, Max}
%%	Min = non_neg_integer()
%%	Max = non_neg_integer()
%% Purpose:
%% 	Minimal and maximal activity during an activity interval.
%%	Initial activity count needs to be supplied.	 

%% @spec minmax_activities([#activity{}], integer()) -> {integer(), integer()}
%% @doc	Calculates the minimum and maximum of runnable activites (processes
%	and ports) during the interval of reffered by the activity list.

minmax_activities(Activities, Count) ->
    minmax_activities(Activities, Count, {Count, Count}).
minmax_activities([], _, Out) -> 
    Out;
minmax_activities([A|Acts], Count, {Min, Max}) ->
    case A#activity.state of
	active ->
	   minmax_activities(Acts, Count + 1, {Min, lists:max([Count + 1, Max])});
	inactive ->
	   minmax_activities(Acts, Count - 1, {lists:min([Count - 1, Min]), Max})
    end.
