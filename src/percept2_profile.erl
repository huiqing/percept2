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

-module(percept2_profile).

-export([
         start/2, 
         start/3,
         stop/0
      	]).

-compile(export_all).

-include("../include/percept2.hrl").

%%==========================================================================
%%
%% 		Type definitions 
%%
%%==========================================================================
%%-type port_number() :: integer().

-type trace_flags() :: 
        'all' | 'send' |'receive' |'procs'|'call'|'silent'|
        'return_to' |'running'|'exiting'|'garbage_collection'|
        'timestamp'|'cpu_timestamp'|'arity'|'set_on_spawn'|
        'set_on_first_spawn'|'set_on_link'|'set_on_first_link'|'ports'.

-type profile_flags():: 
        'runnable_procs'|'runnable_ports'|'scheduler'|'exclusive'.

-type module_name()::atom().
-type percept_option() ::
      'concurreny' | 'message'| 'process_scheduling'
      |{'mods', [module_name()|mfa()]}.


%%==========================================================================
%%
%% 		Interface functions
%%
%%==========================================================================

-spec start(FileSpec::file:filename()|
                      {file:filename(), wrap, Suffix::string(),
                       WrapSize::pos_integer()}, 
            Options::[trace_flags()|profile_flags()]) ->
                   {'ok', port()} | {'already_started', port()}.
start(FileSpec, Options) ->
    profile_to_file(FileSpec,Options). 

%%@doc Starts profiling at the entrypoint specified by the MFA. All events are collected, 
%%	this means that processes outside the scope of the entry-point are also profiled. 
%%	No explicit call to stop/0 is needed, the profiling stops when
%%	the entry function returns.
-spec start(FileSpec::file:filename()|
                      {file:filename(), wrap, Suffix::string(),
                       WrapSize::pos_integer()},
            Entry :: {atom(), atom(), list()},
            Options :: [trace_flags()|profile_flags()|{callgraph, [module_name()]}]) ->
                   'ok' | {'already_started', port()} |
                   {'error', 'not_started'}.
start(FileSpec, _Entry={Mod, Fun, Args}, Options) ->
    case whereis(percept2_port) of
	undefined ->
	    profile_to_file(FileSpec,Options),
            _Res=erlang:apply(Mod, Fun, Args),
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
    erlang:trace(Tracee, true, [procs, {tracer, Tracer}]),
    Tracer ! {Tracee, start},
    receive {Tracer, ok} -> ok end,
    erlang:trace(Tracee, false, [procs]),
    ok.

%% @doc Stops profiling.
-spec stop() -> 'ok' | {'error', 'not_started'}.
stop() ->
    erlang:system_profile(undefined, [runnable_ports, runnable_procs, 
                                      scheduler, exclusive]),
    erlang:trace(all, false, [all]),
    erlang:trace_pattern({'_', '_', '_'}, false, [local]),
    case ets:info(percept2_spawn) of 
        undefined -> ok;
        _ -> ets:delete(percept2_spawn)
    end,
    deliver_all_trace(), 
    case whereis(percept2_port) of
    	undefined -> 
	    {error, not_started};
	Port ->
	    erlang:port_command(Port, 
                                erlang:term_to_binary({profile_stop, erlang:now()})),
            erlang:port_close(Port),
       	    ok
    end. 

%%==========================================================================
%%
%% 		Auxiliary functions 
%%
%%==========================================================================
-spec profile_to_file(FileSpec::file:filename()|
                                {file:filename(), wrap, Suffix::string(),
                                 WrapSize::pos_integer()},
                      Opts::[percept_option()])->
                             {'ok', port()} | {'already_started', port()}.
profile_to_file(FileSpec, Opts) ->
    case whereis(percept2_port) of 
	undefined ->
	    io:format("Starting profiling.~n", []),
            
	    erlang:system_flag(multi_scheduling, block),
            FileSpec1 = case FileSpec of 
                            {FileName, wrap, Suffix, Size} ->
                                {FileName, wrap, Suffix, Size, 49};
                            {FileName, wrap, Suffix, Size, MaxFileCnt} ->
                                {FileName, wrap, Suffix, Size, MaxFileCnt-1};
                            _ -> FileSpec
                        end,
	    Port =  (dbg:trace_port(file, FileSpec1))(),
                                                % Send start time
	    erlang:port_command(Port, erlang:term_to_binary({profile_start, erlang:now()})),
            erlang:port_command(Port, erlang:term_to_binary({profile_opts, Opts})),
	    erlang:system_flag(multi_scheduling, unblock),
		
	    %% Register Port
    	    erlang:register(percept2_port, Port),
	    set_tracer(Port, Opts), 
	    {ok, Port};
	Port ->
	    io:format("Profiling already started at port ~p.~n", [Port]),
	    {already_started, Port}
    end.
-spec(set_tracer(pid()|port(), [percept_option()]) -> ok).
set_tracer(Port, Opts) ->
    {TraceOpts, ProfileOpts, ModOrMFAs} = parse_profile_options(Opts),
    MatchSpec = [{'_', [], [{message, {{cp, {caller}}}}]}],
    Mods = [M||M<-ModOrMFAs,is_atom(M)],
    MFAs = [MFA||MFA={_M, _F, _A}<-ModOrMFAs],
    load_modules(Mods),
    case Mods of 
        [] -> ok;
        _ ->
            ets:new(?percept2_spawn_tab, [named_table, public, {keypos,1}, set]),
            ets:insert(?percept2_spawn_tab, {mods, Mods})
    end,
    [erlang:trace_pattern(MFA, MatchSpec, [local])
     ||Mod <- Mods, MFA<-module_funs(Mod)],
    [erlang:trace_pattern(MFA, MatchSpec, [local])||MFA<-MFAs],
    erlang:trace(all, true, [{tracer, Port}, timestamp,set_on_spawn| TraceOpts]),
    erlang:system_profile(Port, ProfileOpts),
    ok.
    

module_funs(s_group) ->
    [{s_group, new_s_group, 2}, {s_group, delete_s_group, 1},
     {s_group, add_nodes, 2},  {s_group, remove_nodes, 2}];
module_funs(Mod) ->
    [{Mod, F, A}||{F, A}<-Mod:module_info(functions),hd(atom_to_list(F))/=$-].
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
load_modules([]) ->
    ok;
load_modules([Mod|Mods]) ->
    case code:ensure_loaded(Mod) of 
        {module, _} -> load_modules(Mods);
        {error, _} ->
            Str = io_lib:format("Percept2 failed to load module ~p, "
                                "and functions defined in this module are not traced.", [Mod]),
            io:format(lists:flatten(Str)),
            load_modules(Mods)
    end.
           
-spec(parse_profile_options([percept_option()]) -> 
             {[trace_flags()], [profile_flags()], [module_name()|mfa()]}).
parse_profile_options(Opts) ->
    parse_profile_options(Opts, {[],[],[]}).

parse_profile_options([], Out={TraceOpts, ProfileOpts, ModOpts}) ->
    case lists:member(s_group, ModOpts) of 
        true ->
            {TraceOpts--[arity], ProfileOpts, ModOpts};
        false ->
            Out
    end;
parse_profile_options([Opt|Opts],{TraceOpts, ProfileOpts, ModOpts}) ->
    case Opt of
        {callgraph, Mods} ->
            parse_profile_options(
              Opts, {TraceOpts, ProfileOpts, Mods ++ ModOpts});
        s_group ->
            parse_profile_options(
               Opts, {TraceOpts, ProfileOpts, [s_group|ModOpts]});
	_ -> 
            case lists:member(Opt, trace_flags()) of 
                true ->
                    parse_profile_options(
                      Opts, {[Opt|TraceOpts], ProfileOpts, ModOpts});
                false -> case lists:member(Opt,profile_flags()) of 
                             true ->
                                 parse_profile_options(
                                   Opts, {TraceOpts, [Opt|ProfileOpts], ModOpts});
                             false ->
                                 parse_profile_options(
                                   Opts, {TraceOpts, ProfileOpts, ModOpts})
                         end
            end
    end.

trace_flags()->
    ['all','send','receive','procs','call','silent',
     'return_to','running','exiting','garbage_collection',
     'timestamp','cpu_timestamp','arity','set_on_spawn',
     'set_on_first_spawn','set_on_link','set_on_first_link',
     'scheduler_id', 'ports'].
               
profile_flags()->        
    ['runnable_procs','runnable_ports','scheduler','exclusive'].

