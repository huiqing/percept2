%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2008-2010. All Rights Reserved.
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

%% 
%% @doc Percept Collector 
%%
%%	This module provides the user interface for the percept data
%	collection (profiling).
%% 

-module(percept_profile).
-export([
         start/2, 
         start/4,
         stop/0
	]).

-include("percept.hrl").

-compile(export_all).

%%==========================================================================
%%
%% 		Type definitions 
%%
%%==========================================================================

%% @type percept_option() = procs | ports | exclusive

-type percept_option() :: 'procs' | 'ports' | 'exclusive' | 'scheduler'.

-type port_number() :: integer().
%%==========================================================================
%%
%% 		Interface functions
%%
%%==========================================================================

-spec start(Type :: {file, file:filename()}|{ip, node(),port_number()}, Options::[percept_option()]) ->
            {'ok', port()} | {'already_started', port()}.
start(Type, Options) ->
    start_profile(Type,Options). 

%% @spec start(string(), MFA::mfa(), [percept_option()]) -> ok | {already_started, Port} | {error, not_started}
%%	Port = port()
%% @doc Starts profiling at the entrypoint specified by the MFA. All events are collected, 
%%	this means that processes outside the scope of the entry-point are also profiled. 
%%	No explicit call to stop/0 is needed, the profiling stops when
%%	the entry function returns.

-spec start(Type :: {file, file:filename()}|{ip, port_number()},
	    Entry :: {atom(), atom(), list()},
            Mods ::[atom()],
            Options :: [percept_option()]) ->
	'ok' | {'already_started', port()} | {'error', 'not_started'}.

start(Type, {Module, Function, Args}, Mods, Options) ->
    case whereis(percept_port) of
	undefined ->
	    start_profile(Type,Options),
            MatchSpec = [{'_', [], [{message, {{cp, {caller}}}}]}],
            [erlang:trace_pattern({M, '_', '_'}, MatchSpec, [local])||M<-Mods],
            erlang:trace_pattern({lists, foreach, 2}, MatchSpec),
            erlang:trace_pattern({timer, tc, 3}, MatchSpec),
            Res=erlang:apply(Module, Function, Args),
            io:format("Res:\n~p\n", [Res]),
            stop();
	Port ->
	    {already_started, Port}
    end.


deliver_all_trace() -> 
    Tracee = self(),
    Tracer = spawn(fun() -> 
	receive {Tracee, start} -> ok end,
    	Ref = erlang:trace_delivered(Tracee),
	receive {trace_delivered, Tracee, Ref} -> Tracee ! {self(), ok} end
    end),
    %%erlang:trace(Tracee, true, [procs, {tracer, Tracer}]),
    Tracer ! {Tracee, start},
    receive {Tracer, ok} -> ok end,
    erlang:trace(Tracee, false, [procs]),
    ok.

%% @spec stop() -> ok | {'error', 'not_started'}
%% @doc Stops profiling.
    
-spec stop() -> 'ok' | {'error', 'not_started'}.

stop() ->
    erlang:system_profile(undefined, [runnable_ports, runnable_procs]),
    erlang:trace(all, false, [procs, ports, timestamp]),
    erlang:trace_pattern({'_', '_', '_'}, false, [local]),
    deliver_all_trace(),  %%Need to put this back!
    case whereis(percept_port) of
    	undefined -> 
	    {error, not_started};
	Port ->
	    erlang:port_command(Port, erlang:term_to_binary({profile_stop, erlang:now()})),
	    %% trace delivered?
	    erlang:port_close(Port),
            stop_trace_client(),
	    ok
    end. 

%%==========================================================================
%%
%% 		Auxiliary functions 
%%
%%==========================================================================

start_profile(Opts) ->
    start_profile({ip, 'hl2@hl-lt', 4711}, Opts).

start_profile(Type,Opts) ->
    case whereis(percept_port) of 
	undefined ->
	    io:format("Starting profiling.~n", []),
	    erlang:system_flag(multi_scheduling, block),
            Port = case Type of 
                       {file, FileName} -> 
                           P=(dbg:trace_port(file, FileName))(),
                           P;
                       {ip, Node, Number}->
                           P=(dbg:trace_port(ip, {Number, 50000}))(),
                           {trace_client, Node} ! {self(), {start_profile, Number}},
                           receive 
                               {trace_client, started} -> 
                                   ok
                           end,
                           P
                   end,
            % Send start time
	    erlang:port_command(Port, erlang:term_to_binary({profile_start, erlang:now()})),
	    erlang:system_flag(multi_scheduling, unblock),
		
	    %% Register Port
    	    erlang:register(percept_port, Port),
	    set_tracer(Port, Opts), 
	    {ok, Port};
	Port ->
	    io:format("Profiling already started at port ~p.~n", [Port]),
	    {already_started, Port}
    end.


set_tracer(Port, Opts) ->
    {TOpts, POpts} = parse_profile_options(Opts),
    %% DO not change 'all' to 'new' here!!!
    erlang:trace(all, true, [procs, {tracer, Port}, call, return_to, arity, 
                             garbage_collection,set_on_spawn, %% send, 'receive'
                              timestamp,running, scheduler_id| TOpts]),
    erlang:system_profile(Port, [runnable_ports, runnable_procs,scheduler|POpts]).

%% parse_profile_options

parse_profile_options(Opts) ->
    parse_profile_options(Opts, {[],[]}).

parse_profile_options([], Out) ->
    Out;
parse_profile_options([Opt|Opts], {TOpts, POpts}) ->
    case Opt of
	procs ->
	    parse_profile_options(Opts, {
		[procs | TOpts], 
		[runnable_procs | POpts]
	    });
	ports ->
	    parse_profile_options(Opts, {
		[ports | TOpts],  
		[runnable_ports | POpts]
	    });
	scheduler ->
	    parse_profile_options(Opts, {
		TOpts, 
		[scheduler | POpts]
	    });
	exclusive ->
	    parse_profile_options(Opts, {
		TOpts, 
		[exclusive | POpts]
	    });
	_ -> 
	    parse_profile_options(Opts, {TOpts, POpts})
    end.


start_trace_client() ->
    register(trace_client, spawn_link(fun trace_client_loop/0)).

stop_trace_client() ->
    {trace_client, 'hl2@hl-lt'} ! stop_profile.
              
trace_client_loop() ->
    receive 
        {From, {start_profile, Ip}} ->
            {_, DB} =percept_db:start(), 
            T0 = erlang:now(),
            Pid=dbg:trace_client(ip, Ip, percept:mk_trace_parser(self())),
            Ref = erlang:monitor(process, Pid), 
            From ! {trace_client, started},
            parse_and_insert_loop(Pid, Ref, DB, T0),
            trace_client_loop();
        stop_profile ->
            dbg:stop_clear(),
            trace_client_loop();
        stop ->
            dbg:stop_clear()
    end.


parse_and_insert_loop(Pid, Ref, DB, T0) ->
    receive
    	{parse_complete, {Pid, Count}} ->
	   %% receive {'DOWN', Ref, process, Pid, normal} -> ok after 0 -> ok end,
            Pid ! {ack, self()},
	    DB ! {action, consolidate},
	    T1 = erlang:now(),
	    io:format("Parsed ~p entries in ~p s.~n", [Count, ?seconds(T1, T0)]),
    	    io:format("    ~p created processes.~n", [length(percept_db:select({information, procs}))]),
     	    io:format("    ~p opened ports.~n", [length(percept_db:select({information, ports}))]),
	    ok;
	{'DOWN',Ref, process, Pid, normal} -> parse_and_insert_loop(Pid, Ref, DB, T0);
	{'DOWN',Ref, process, Pid, Reason} -> {error, Reason}
    end.
