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
%% @doc Percept2 - An Enhanced version of the Erlang Concurrency Profiling Tool Percept.
%%
%%Percept2 extends Percept in two aspects: functionality and scalability. Among the new functionalities added to Percept are: 
%% <ul>
%% <li> Scheduler activity: the number of active schedulers at any time. </li>
%% <li> Process migration information: the migration history of a process between run queues. </li>
%% <li> Statistics data about message passing between processes: the number of messages, and the average message size, sent/received by a process.</li>
%% <li> Accumulated runtime per-process: the accumulated time when a process is in a running state.</li>
%% <li> Process tree: the hierarchy structure indicating the parent-child relationships between processes.</li> 
%% <li> Dynamic function call graph/count/time: the hierarchy structure showing the calling 
%% relationships between functions during the program run, and the amount of time spent on a function.</li>
%% <li> Active functions: the functions that are active during a specific time interval.</li>
%% <li> Inter-node message passing: the sending of messages from one node to another.
%% </li>
%% </ul> 
%% The following techniques have been used to improved the scalability of Percept. 
%% <ul>
%% <li> Compressed process tree/function call graph representation: an approach to reducing the number of processes/function call paths presented without losing important information.</li>
%% <li> Parallelisation of Percept: the processing of profile data has been parallelised so that multiple data files can be processed at the same time </li>
%% </ul>
%%
%% This module provides the user interface for the application.
%% 
-module(percept2).

-behaviour(application).

-export([
         profile/2, 
         profile/3,
         stop_profile/0, 
         
         start_webserver/0, 
         start_webserver/1, 
         stop_webserver/0, 
         stop_webserver/1, 
         
         analyze/1,
         analyze/4,
         stop_db/0]).

%% Application callback functions.
-export([start/2, stop/1, parse_and_insert/3]).

-include("../include/percept2.hrl").

-type module_name()::atom().
 
-type filespec()::file:filename()|
                  {file:filename(), wrap, Suffix::string(),
                   WrapSize::pos_integer(), WrapCnt::pos_integer()}.

-type trace_profile_option()::'procs' |                %% profile process concurrency.
                              'ports' |                %% profile port concurreny.
                              'schedulers'|            %% profile scheduler concurrency.
                              'running'|               %% distinguish process running state from runnable state.
                              'message'|               %% profile message passing.
                              'migration'|             %% profile process migration.
                              {'callgraph', [module_name()]}.  %%trace the call/return of functins defined the modules specified.

%%---------------------------------------------------------%%
%%                                                         %%
%% 		Application callback functions             %%
%%                                                         %%
%%---------------------------------------------------------%%
%% @spec start(Type, Args) -> {started, Hostname, Port} | {error, Reason} 
%% @doc none
%% @hidden
start(_Type, _Args) ->
    %% start web browser service
    start_webserver(0).

%% @spec stop(State) -> ok 
%% @doc none
%% @hidden
-spec stop(any()) -> ok.
stop(_State) ->
    %% stop web browser service
    stop_webserver(0).

%% @doc Stops the percept2 database.
-spec stop_db() -> ok.
stop_db() ->
    percept2_db:stop(),
    ok.

%%---------------------------------------------------------%%
%%                                                         %%
%% 		Interface functions                        %%
%%                                                         %%
%%---------------------------------------------------------%%
-spec profile(FileSpec::filespec(), 
              TraceProfileOptions::[trace_profile_option()])-> 
                     {ok, integer()} | {already_started, port()}.
profile(FileSpec, TraceProfileOptions) ->
    case process_trace_profile_opts(TraceProfileOptions,[]) of
        {error, Reason} ->
            {error, Reason};
        Opts ->
            percept2_profile:start(FileSpec, Opts)
    end.
 
-spec profile(FileSpec :: filespec(),
	      Entry :: {atom(), atom(), list()},
              TraceProfileOptions::[trace_profile_option()]) ->
                     'ok' | {'already_started', port()}.

profile(FileSpec,Entry, TraceProfileOptions) ->
    case process_trace_profile_opts(TraceProfileOptions,[]) of
        {error, Reason} ->
            {error, Reason};
        Opts ->
            percept2_profile:start(FileSpec, Entry, Opts)
    end.

process_trace_profile_opts([], Res) ->
    lists:usort(Res);
process_trace_profile_opts([Opt|Opts], Acc) ->
    case Opt of 
        port ->
            process_trace_profile_opts(
              Opts,[runnable_ports, ports|Acc]);
        procs ->
            process_trace_profile_opts(
              Opts,[runnable_procs, procs, exclusive|Acc]);
        schedulers ->
            process_trace_profile_opts(
              Opts,[scheduler|Acc]);
        running ->
            process_trace_profile_opts(
              Opts,[runnable_procs,procs,exclusive, 
                    running,exiting|Acc]);
        message ->
            process_trace_profile_opts(
              Opts,[runnable_procs,exclusive,
                    procs, 'send','receive'|Acc]);
        migration ->
            process_trace_profile_opts(
              Opts,[runnable_procs, procs, exclusive,
                    running, scheduler_id|Acc]);
        {callgraph, Mods} when is_list(Mods) ->
            process_trace_profile_opts(
              Opts,[runnable_procs, procs,exclusive, call, 
                    return_to, arity, {callgraph, Mods}|Acc]);
        Other ->
            Msg = lists:flatten(
                    io_lib:format(
                      "Invalid profile option:~p.", 
                      [Other])),
            {error, Msg}
    end.


%%@doc Stops the profiling.
%%@see profile/1
%%@see profile/2.
-spec stop_profile() -> 'ok' | {'error', 'not_started'}.
stop_profile() ->
    percept2_profile:stop().

%%@doc Parallel analysis of trace files. See the <a href="overview-summary.html">Overview</a> page for examples.
-spec analyze(FileNames :: [file:filename()]) ->
                     'ok' | {'error', any()}.
analyze(FileNames) ->
    case percept2_db:start(FileNames) of
	{started, FileNameSubDBPairs} ->
            analyze_par_1(FileNameSubDBPairs);
        {restarted, FileNameSubDBPairs} ->
            analyze_par_1(FileNameSubDBPairs)
    end.

%%@doc Parallel analysis of trace files. See the <a href="overview-summary.html">Overview</a> page for examples.
-spec analyze(Filename::file:filename(), Suffix::string(), 
              StartIndex::pos_integer(), EndIndex::pos_integer()) ->
                     'ok' | {'error', any()}.
analyze(FileName, Suffix, StartIndex, EndIndex) 
  when is_integer(StartIndex) andalso is_integer(EndIndex) ->
    Index=lists:seq(StartIndex, EndIndex),
    FileNames=[FileName++integer_to_list(I)++Suffix||I<-Index],
    analyze(FileNames);
analyze(_FileName, _Suffux, _, _) ->
    {error, "Start/end indexes must be integers."}.
    
analyze_par_1(FileNameSubDBPairs) ->
    Self = self(),
    process_flag(trap_exit, true),
    Pids = lists:foldl(fun({File, SubDBPid}, Acc) ->
                               Pid=spawn_link(?MODULE, parse_and_insert, [File, SubDBPid, Self]),
                               receive 
                                   {started, {File, SubDBPid}} ->
                                       [Pid|Acc]
                               end
                       end, [], FileNameSubDBPairs),
    loop_analyzer_par(Pids).
    
loop_analyzer_par(Pids) ->
    receive 
        {Pid, done} ->
            case Pids -- [Pid] of 
                [] ->
                    ok=percept2_db:consolidate_db(),
                    io:format("    ~p created processes.~n",
                              [percept2_db:select({information, procs_count})]),
                    io:format("    ~p opened ports.~n", 
                              [percept2_db:select({information, ports_count})]);
                PidsLeft ->
                    loop_analyzer_par(PidsLeft)
            end;
        {error, Reason} ->
            percept2_db:stop(percept2_db),
            flush(),
            {error, Reason};
        _Other ->
            loop_analyzer_par(Pids)            
    end.
            
flush() ->
    receive
        _ -> flush()
    after 0 ->
            ok
    end.
%% @spec start_webserver() -> {started, Hostname, Port} | {error, Reason}
%%	Hostname = string()
%%	Port = integer()
%%	Reason = term() 
%% @doc Starts webserver. An available port number will be assigned by inets.
-spec start_webserver() ->{'started', string(), pos_integer()} | {'error', any()}.
start_webserver() ->
    start_webserver(0).

%% @spec start_webserver(integer()) -> {started, Hostname, AssignedPort} | {error, Reason}
%%	Hostname = string()
%%	AssignedPort = integer()
%%	Reason = term() 
%% @doc Starts webserver with a given port number. If port number is 0, an available port number will 
%%	be assigned by inets.
-spec start_webserver(Port :: non_neg_integer()) ->
                             {'started', string(), pos_integer()} | {'error', any()}.
start_webserver(Port) when is_integer(Port) ->
    application:load(percept2),
    case whereis(percept_httpd) of
	undefined ->
	    {ok, Config} = get_webserver_config("percept2", Port),
            inets:start(),
	    case inets:start(httpd, Config) of
		{ok, Pid} ->
		    AssignedPort = find_service_port_from_pid(inets:services_info(), Pid),
		    {ok, Host} = inet:gethostname(),
		    %% workaround until inets can get me a service from a name.
		    Mem = spawn(fun() -> service_memory({Pid,AssignedPort,Host}) end),
		    register(percept_httpd, Mem),
                    rm_tmp_files(),
                    case ets:info(history_html) of 
                        undefined ->
                            ets:new(history_html, [named_table, public, {keypos, #history_html.id},
                                                   ordered_set]);
                        _ ->
                            ets:delete_all_objects(history_html)
                    end,
                    Filename = filename:join([code:priv_dir(percept2),"fonts", "6x11_latin1.wingsfont"]),
                    egd_font:load(Filename),
                    {started, Host, AssignedPort};
		{error, Reason} ->
		    {error, {inets, Reason}}
            end;
	_ ->
	    {error, already_started}
    end.


%% @doc Stops webserver.
-spec stop_webserver() -> ok | {error, not_started}.
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
            rm_tmp_files(),
            case ets:info(egd_font_table) of 
                undefined -> ok;
                _  ->ets:delete(egd_font_table)
            end,
            inets:stop(httpd, Pid2)
    end.

%% @doc Stops webserver of the given port.
-spec stop_webserver(integer()) -> ok | {error, not_started}.
stop_webserver(Port) ->
    do_stop(Port,[]).
%%==========================================================================
%%
%% 		Auxiliary functions 
%%
%%==========================================================================

%% parse_and_insert
%%@hidden
parse_and_insert(Filename,SubDB, Parent) ->
    io:format("Parsing: ~p ~n", [Filename]),
    T0 = erlang:now(),
    Parser = mk_trace_parser(self(), SubDB),
    ?dbg(0,"Parser Pid:\n~p\n", [Parser]),
    Pid=dbg:trace_client(file, Filename, Parser),
    ?dbg(0,"Trace client Pid:\n~p\n", [Pid]),
    Ref = erlang:monitor(process, Pid),
    ?dbg(0, "Trace client Ref:\n~p\n",[{Pid, Ref}]),
    Parent!{started, {Filename, SubDB}},
    parse_and_insert_loop(Filename, Pid, Ref, SubDB,T0, Parent).
   
parse_and_insert_loop(Filename, Pid, Ref, SubDB,T0, Parent) ->
    receive
	{'DOWN',Ref,process, Pid, noproc} ->
	    Msg=lists:flatten(io_lib:format(
                                "Incorrect file or malformed trace file: ~s~n", [Filename])),
            Parent ! {error, Msg};
    	{parse_complete, {Pid, Count}} ->
            Pid ! {ack, self()},
            T1 = erlang:now(),
	    io:format("Parsed ~p entries from ~p in ~p s.~n", [Count, Filename, ?seconds(T1, T0)]),
            Parent ! {self(), done};
	{'DOWN',Ref, process, Pid, normal} -> 
            parse_and_insert_loop(Filename, Pid, Ref, SubDB,T0,Parent);
	{'DOWN',Ref, process, Pid, Reason} -> 
            Parent ! {error, Reason};
        Msg -> 
            io:format("parse_and_insert_loop, unhandled: ~p\n", [Msg]), 
            parse_and_insert_loop(Filename, Pid, Ref, SubDB,T0,Parent)
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
        {port, Port} ->
	    Pid;
	false ->
	    find_service_pid_from_port(Services, Port)
    end.

find_service_port_from_pid([], _) ->
    undefined;
find_service_port_from_pid([{_, Pid, Options} | _], Pid) ->
    case lists:keyfind(port, 1, Options) of
        {port, Port} ->
            Port;
        false ->
	    undefined
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
-spec get_webserver_config(list(), pos_integer()) -> {ok, list()}.
get_webserver_config(Servername, Port) 
  when is_list(Servername), is_integer(Port) ->
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
        {alias,{"/svgs/", percept2_utils:svg_file_dir()}},
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


rm_tmp_files() ->
    Dir =percept2_utils:svg_file_dir(),
    case file:list_dir(Dir) of 
        {error, Error} ->
            {error, Error};
        {ok, FileNames} ->
            [file:delete(filename:join(Dir, F))
             ||F<-FileNames,
               lists:prefix("callgraph", F) orelse
                   lists:prefix("processtree", F)]
    end.
