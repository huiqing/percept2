%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2007-2010. All Rights Reserved.
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
%% @doc Percept - Erlang Concurrency Profiling Tool
%%
%%	This module provides the user interface for the application.
%% 

-module(percept2).
-behaviour(application).
-export([
	profile/1, 
	profile/2, 
	profile/3,
        stop_profile/0, 

	start_webserver/0, 
	start_webserver/1, 
	stop_webserver/0, 
	stop_webserver/1, 

	analyze/1,
	% Application behaviour
	start/2, 
	stop/1]).

-include("../include/percept2.hrl").

%%========================================================================
%%
%% 		Application callback functions
%%
%%==========================================================================

%% @spec start(Type, Args) -> {started, Hostname, Port} | {error, Reason} 
%% @doc none
%% @hidden

start(_Type, _Args) ->
    %% start web browser service
    start_webserver(0).

%% @spec stop(State) -> ok 
%% @doc none
%% @hidden

stop(_State) ->
    %% stop web browser service
    stop_webserver(0).

%%==========================================================================
%%
%% 		Interface functions
%%
%%==========================================================================

%% @spec profile(Filename::string()) -> {ok, Port} | {already_started, Port}
%% @see percept_profile

%% profiling
-spec profile(Filename :: file:filename()) ->
	{'ok', port()} | {'already_started', port()}.

profile(Filename) ->
    percept2_profile:start(Filename, [concurrency]).

%% @spec profile(Filename::string(), [percept_option()]) -> 
%%       {ok, Port} | {already_started, Port}
%% @see percept_profile
-spec profile(Filename :: file:filename(),
	      Options :: [percept_option()]) ->
                     {'ok', port()} | {'already_started', port()}.
profile(Filename, Options) ->
    percept2_profile:start(Filename, Options). 

%% @spec profile(Filename::string(), MFA::mfa(), [percept_option()]) ->
%%     ok | {already_started, Port} | {error, not_started}
%% @see percept_profile
-spec profile(Type :: {file, file:filename()}|{ip,integer()},
	      Entry :: {atom(), atom(), list()},
	      Options :: [percept_option()]) ->
                     'ok' | {'already_started', port()} | {'error', 'not_started'}.
profile(Type, MFA, Options) ->
    percept2_profile:start(Type, MFA, Options).

-spec stop_profile() -> 'ok' | {'error', 'not_started'}.
%% @see percept_profile
stop_profile() ->
    percept2_profile:stop().

-spec analyze(FileNames :: [file:filename()]) ->
                     'ok' | {'error', any()}.
analyze(FileNames) ->
    case percept2_db:start(FileNames) of
	{started, FileNameSubDBPairs} ->
            analyze_par_1(FileNameSubDBPairs);
        {restarted, FileNameSubDBPairs} ->
            analyze_par_1(FileNameSubDBPairs)
    end.

analyze_par_1(FileNameSubDBPairs) ->
    _Res=percept2_utils:pmap(
           fun({FileName, SubDBPid}) ->
                   parse_and_insert(FileName, SubDBPid)
           end, FileNameSubDBPairs),
    percept2_db:consolidate_db(),
    io:format("    ~p created processes.~n",
              [percept2_db:select({information, procs_count})]),
    io:format("    ~p opened ports.~n", 
              [percept2_db:select({information, ports_count})]).
   

%% @spec start_webserver() -> {started, Hostname, Port} | {error, Reason}
%%	Hostname = string()
%%	Port = integer()
%%	Reason = term() 
%% @doc Starts webserver.
-spec start_webserver() ->{'started', string(), pos_integer()} | {'error', any()}.
start_webserver() ->
    start_webserver(0).

%% @spec start_webserver(integer()) -> {started, Hostname, AssignedPort} | {error, Reason}
%%	Hostname = string()
%%	AssignedPort = integer()
%%	Reason = term() 
%% @doc Starts webserver. If port number is 0, an available port number will 
%%	be assigned by inets.
-spec start_webserver(Port :: non_neg_integer()) ->
                             {'started', string(), pos_integer()} | {'error', any()}.
start_webserver(Port) when is_integer(Port) ->
    application:load(percept2),
    case whereis(percept_httpd) of
	undefined ->
	    {ok, Config} = get_webserver_config("percept", Port),
            inets:start(),
	    case inets:start(httpd, Config) of
		{ok, Pid} ->
		    AssignedPort = find_service_port_from_pid(inets:services_info(), Pid),
		    {ok, Host} = inet:gethostname(),
		    %% workaround until inets can get me a service from a name.
		    Mem = spawn(fun() -> service_memory({Pid,AssignedPort,Host}) end),
		    register(percept_httpd, Mem),
                    percept2_utils:rm_tmp_files(),
                    case ets:info(history_html) of 
                        undefined ->
                            ets:new(history_html, [named_table, public, {keypos, #history_html.id},
                                                   ordered_set]);
                        _ ->
                            ets:delete_all_objects(history_html)
                    end,
                    {started, Host, AssignedPort};
		{error, Reason} ->
		    {error, {inets, Reason}}
            end;
	_ ->
	    {error, already_started}
    end.

%% @spec stop_webserver() -> ok | {error, not_started}  
%% @doc Stops webserver.
stop_webserver() ->
    case whereis(percept_httpd) of
    	undefined -> 
	    {error, not_started};
	Pid ->
            do_stop([], Pid)
    end.

do_stop([], Pid)->
    Pid ! {self(), get_port},
    Port = receive P -> P end,
    do_stop(Port, Pid);
do_stop(Port, [])->
    case whereis(percept_httpd) of
        undefined ->
            {error, not_started};
        Pid ->
            do_stop(Port, Pid)
    end;
do_stop(Port, Pid)->
    case find_service_pid_from_port(inets:services_info(), Port) of
        undefined ->
            {error, not_started};
        Pid2 ->
            Pid ! quit,
            percept2_utils:rm_tmp_files(),
            inets:stop(httpd, Pid2)
    end.

%% @spec stop_webserver(integer()) -> ok | {error, not_started}
%% @doc Stops webserver of the given port.
%% @hidden

stop_webserver(Port) ->
    do_stop(Port,[]).
%%==========================================================================
%%
%% 		Auxiliary functions 
%%
%%==========================================================================

%% parse_and_insert

parse_and_insert(Filename,SubDB) ->
    io:format("Parsing: ~p ~n", [Filename]),
    T0 = erlang:now(),
    Parser = mk_trace_parser(self(), SubDB),
    Pid=dbg:trace_client(file, Filename, Parser), 
    Ref = erlang:monitor(process, Pid), 
    parse_and_insert_loop(Filename, Pid, Ref, SubDB,T0).
   
parse_and_insert_loop(Filename, Pid, Ref, SubDB,T0) ->
    receive
	{'DOWN',Ref,process, Pid, noproc} ->
	    io:format("Incorrect file or malformed trace file: ~p~n", [Filename]),
	    {error, file};
    	{parse_complete, {Pid, Count}} ->
            Pid ! {ack, self()},
            receive 
                {'DOWN', Ref, process, Pid, normal} -> 
                    ok 
            end,
            T1 = erlang:now(),
	    io:format("Parsed ~p entries from ~p in ~p s.~n", [Count, Filename, ?seconds(T1, T0)]),
            ok;
	{'DOWN',Ref, process, Pid, normal} -> parse_and_insert_loop(Filename, Pid, Ref, SubDB,T0);
	{'DOWN',Ref, process, Pid, Reason} -> {error, Reason};
        Msg -> io:format("parse and insert loop, unhandled message:~p\n", [Msg])
    end.

mk_trace_parser(Parent, SubDB) ->
    {fun trace_parser/2, {0, Parent, SubDB}}.

trace_parser(end_of_trace, {Count, Pid, SubDB}) -> 
    percept2_db:insert(SubDB, {trace_ts, self(), end_of_trace}),
    %% synchronisation is to make sure all traces have been 
    %% processed before consolidating the DB.
    receive 
        {SubDB, done} -> 
            Pid ! {parse_complete, {self(),Count}},
            receive
                {ack, Pid} ->
                    ok
            end
    end;
trace_parser(Trace, {Count, Pid, SubDB}) ->
    percept2_db:insert(SubDB, Trace),
    {Count + 1,  Pid, SubDB}.

find_service_pid_from_port([], _) ->
    undefined;
find_service_pid_from_port([{_, Pid, Options} | Services], Port) ->
    case lists:keyfind(port, 1, Options) of
	false ->
	    find_service_pid_from_port(Services, Port);
	{port, Port} ->
	    Pid
    end.

find_service_port_from_pid([], _) ->
    undefined;
find_service_port_from_pid([{_, Pid, Options} | _], Pid) ->
    case lists:keyfind(port, 1, Options) of
	false ->
	    undefined;
	{port, Port} ->
	   Port
    end;
find_service_port_from_pid([{_, _, _} | Services], Pid) ->
    find_service_port_from_pid(Services, Pid).
    
%% service memory
service_memory({Pid, Port, Host}) ->
    receive
	quit -> 
	    ok;
	{Reply, get_port} ->
	    Reply ! Port,
	    service_memory({Pid, Port, Host});
	{Reply, get_host} -> 
	    Reply ! Host,
	    service_memory({Pid, Port, Host});
	{Reply, get_pid} -> 
	    Reply ! Pid,
	    service_memory({Pid, Port, Host})
    end.

% Create config data for the webserver 
get_webserver_config(Servername, Port) when is_list(Servername), is_integer(Port) ->
    Path = code:priv_dir(percept2),
    Root = filename:join([Path, "server_root"]),
    MimeTypesFile = filename:join([Root,"conf","mime.types"]),
    {ok, MimeTypes} = httpd_conf:load_mime_types(MimeTypesFile),
    Config = [
	% Roots
	{server_root, Root},
	{document_root,filename:join([Root, "htdocs"])},
	
	% Aliases
	{eval_script_alias,{"/eval",[io]}},
        {erl_script_alias,{"/cgi-bin",[percept2_graph,percept2_html,io]}},
	{script_alias,{"/cgi-bin/", filename:join([Root, "cgi-bin"])}},
	{alias,{"/javascript/",filename:join([Root, "scripts"]) ++ "/"}},
	{alias,{"/images/", filename:join([Root, "images"]) ++ "/"}},
	{alias,{"/css/", filename:join([Root, "css"]) ++ "/"}},
	
	% Logs
	%{transfer_log, filename:join([Path, "logs", "transfer.log"])},
	%{error_log, filename:join([Path, "logs", "error.log"])},
	
	% Configs
	{default_type,"text/plain"},
	{directory_index,["index.html"]},
	{mime_types, MimeTypes},
	{modules,[mod_alias,
	          mod_esi,
	          mod_actions,
	          mod_cgi,
	          mod_include,
	          mod_dir,
	          mod_get,
	          mod_head
	%          mod_log,
	%          mod_disk_log
	]},
	{com_type,ip_comm},
	{server_name, Servername},
	{bind_address, any},
	{port, Port}],
    {ok, Config}.
