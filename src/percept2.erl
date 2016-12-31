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
%% <li> Compressed process tree/function call graph representation: an approach to reducing the
%%      number of processes/function call paths presented without losing important information.</li>
%% <li> Parallelisation of Percept: the processing of profile data has been parallelised so that multiple
%%      data files can be processed at the same time </li>
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

-compile(export_all).

-include("../include/percept2.hrl").
-include_lib("kernel/include/file.hrl").

-type module_name()::atom().

-type function_name()::atom().
 
-type filespec()::file:filename()|
                  {file:filename(), wrap, Suffix::string(),
                   WrapSize::pos_integer()} |
                  {file:filename(), wrap, Suffix::string(),
                   WrapSize::pos_integer(), MaxFileCnt::pos_integer()}.

-type trace_profile_option()::'procs_basic'|           %% profile basic process activities including
                                                       %% spawn, exit and register.
                              'ports_basic'|           %% profile basic port activities: open, close.
                              'procs' |                %% profile basic process activities and process runnability.
                              'ports' |                %% profile basic port activities and port runnability.
                              'schedulers'|            %% profile scheduler concurrency.
                              'running'|               %% enable 'procs_basic' and 'running', but also 
                                                       %% distinguish process running state from runnable state.
                              'message'|               %% enable 'procs_basic', but also profile message send and receive.
                              'migration'|             %% enable 'running' and 'scheduler_id'.
                              'garbage_collection'|    %% enable 'procs_basic' and 'garbage_collection'.
                              's_group'|               %% profile s_group activities.
                              'all'      |             %% profile all the activities above.
                              {'callgraph', [module_name()]}. %% enable 'procs_basic', but also trace the call/return of 
                                                              %% functions defined the modules specified. This feature
                                                              %% should not be used when 's_group' is enabled.


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

%%@doc Starts the profiling while an application of interest 
%%     is already running. 
%%     The profiling can be stopped by `percept2:stop_profile/0'.
%%     The valid `TraceProfileOptions' values are: `procs', `ports',
%%     `schedulers', `running', `message', `migration' and `all'. See 
%%     <a href="percept2.html#profile-3">profile/3</a> for the 
%%     descriptions of the options.
%%@see stop_profile/0.
-spec profile(FileSpec::filespec(), 
              TraceProfileOptions::[trace_profile_option()])-> 
                     {ok, integer()} | {already_started, port()}.
profile(FileSpec, TraceProfileOptions) ->
    case process_trace_profile_opts(TraceProfileOptions) of
        {error, Reason} ->
            {error, Reason};
        Opts ->
            percept2_profile:start(FileSpec, Opts)
    end.
 
%%@doc The profiling starts with executing the entry function given, and goes on for 
%%     the whole duration until the entry function returns and the profiling 
%%     has concluded. The events to be traced/profiled depends on the options 
%%     specified by `TraceProfileOptions'. The following options are available:
%%
%%    -- `procs_basic'       : only profile basic process activities including
%%                             spawn, exit, register. Other activiites including 
%%                             unregister, link, unlink, getting_linked, and 
%%                             getting_unlinked, are traced but not profiled.
%%
%%    -- `procs'             : enable `'procs_baisc', but also profile the 
%%                             runnablity of processes. 
%%
%%    -- `ports_basic'       : only profile basic port activities: open and close.
%%
%%    -- `ports'             : enable `ports_basic', but also profile the 
%%                             runnablity of ports.
%%
%%    -- `schedulers'        : enable the profiling of scheduler concurrency.
%%
%%    -- `running'           : enable the feature to distinguish running from 
%%                             runnable process states. If the `procs' option is 
%%                             not given, this option enables the process concurrency
%%                             automatically.
%%
%%    -- `message'           : enable the profiling of message passing between 
%%                             processes; This option enables `procs_basic' automically.
%%         
%%    -- `migration'         : enable the profiling of process migration between 
%%                             schedulers; this option enables `procs' automatically.
%%
%%    -- `garbage_collection': enable the profiling of garbage collection. This 
%%
%%    -- `s_group'           : enable the profiling of s_group-related activities, including
%%                             the creation/deletion of s_groups as well adding/removing nodes
%%                             to/from a s_group. 
%%
%%    -- `all'               : enable all the previous options apart from `s_group'.
%%
%%    -- `{callgraph, Mods}' : enable the profiling of function activities 
%%                              (`call' and `return_to') of functions defined in `Mods'.
%%                              This option enables `procs_basic' automatically. Given the huge 
%%                              amount of data that could possibly be produced when this 
%%                              feature is on, we do not recommend profiling many modules 
%%                              in one go at this stage. We are in the process of improving 
%%                              the performance of this feature. This feature should not be 
%%                              used when `s_group' is enabled, since the latter needs to 
%%                              record the actual arguments of function calls.
%%
%% See the <a href="overview-summary.html">Overview</a> page for examples.
-spec profile(FileSpec :: filespec(),
	      Entry :: {module_name(), function_name(), [term()]},
              TraceProfileOptions::[trace_profile_option()]) ->
                     'ok' | {'already_started', port()}.

profile(FileSpec,Entry, TraceProfileOptions) ->
    case process_trace_profile_opts(TraceProfileOptions) of
        {error, Reason} ->
            {error, Reason};
        Opts ->
            percept2_profile:start(FileSpec, Entry, Opts)
    end.

process_trace_profile_opts([]) ->
    process_trace_profile_opts([procs]);
process_trace_profile_opts(Opts) ->
    process_trace_profile_opts(Opts, []).

process_trace_profile_opts([], Res) ->
    lists:usort(Res);
process_trace_profile_opts([Opt|Opts], Acc) ->
    case Opt of 
        ports_basic ->
            process_trace_profile_opts(
              Opts,[ports|Acc]);
        ports ->
            process_trace_profile_opts(
              Opts,[runnable_ports, ports|Acc]);
        procs_basic ->
            process_trace_profile_opts(
              Opts,[procs|Acc]);
        procs ->
            process_trace_profile_opts(
              Opts,[runnable_procs, procs, exclusive|Acc]);
        schedulers ->
            process_trace_profile_opts(
              Opts,[procs, scheduler|Acc]);
        running ->
            process_trace_profile_opts(
              Opts,[runnable_procs,procs,exclusive, 
                    running,exiting|Acc]);
        message ->
            process_trace_profile_opts(
              Opts,[procs, 'send','receive'|Acc]);
        migration ->
            process_trace_profile_opts(
              Opts,[runnable_procs, procs, exclusive,
                    running, exiting, scheduler_id|Acc]);
        garbage_collection ->
            process_trace_profile_opts(
              Opts,[procs,garbage_collection|Acc]);
        s_group ->
            process_trace_profile_opts(
              Opts, [call,return_to, s_group|Acc]);
        all ->
            process_trace_profile_opts(
              Opts, [runnable_ports, ports,
                     runnable_procs, procs, exclusive,
                     scheduler,running,exiting,
                     garbage_collection,
                     'send','receive',scheduler_id|Acc]);
        {callgraph, Mods} when is_list(Mods) ->
            process_trace_profile_opts(
              Opts,[procs,call,return_to,arity,{callgraph, Mods}|Acc]);
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
-spec analyze(FileNames :: file:filename() | [file:filename()]) ->
                     'ok' | {'error', any()}.
analyze([H | _] = Filename) when not is_list(H) ->
    analyze([Filename]);
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
    case whereis(percept2_httpd) of 
        undefined ->
            ok;
        _ ->
            TmpDir=get_svg_alias_dir(), 
            rm_tmp_files(TmpDir)
    end,
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
                    try percept2_db:consolidate_db()
                    catch _E1:_E2 -> ok  %%sometimes it is not possible.
                    end,
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
    case whereis(percept2_httpd) of
	undefined ->
	    {ok, Config} = get_webserver_config("percept2", Port),
            inets:start(),
	    case inets:start(httpd, Config) of
		{ok, Pid} ->
		    AssignedPort = find_service_port_from_pid(inets:services_info(), Pid),
		    {ok, Host} = inet:gethostname(),
                    TmpDir= get_svg_alias_dir(Config),
		    %% workaround until inets can get me a service from a name.
		    Mem = spawn(fun() -> service_memory({Pid,AssignedPort,Host, TmpDir}) end),
		    register(percept2_httpd, Mem),
                    rm_tmp_files(TmpDir),
                    case ets:info(history_html) of 
                        undefined ->
                            ets:new(history_html, [named_table, public, {keypos, #history_html.id},
                                                   ordered_set]);
                        _ ->
                            ets:delete_all_objects(history_html)
                    end,
                    Filename = filename:join([code:priv_dir(percept2),"fonts", "6x11_latin1.wingsfont"]),
                    egd_font:load(Filename),
                    true=percept2_code_server:start(),
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
    case whereis(percept2_httpd) of
    	undefined -> 
	    {error, not_started};
	Pid ->
            try do_stop([], Pid)
            catch _E1:_E2 ->
                    stop_webserver()
            end
    end.

do_stop([], Pid)->
    Pid ! {self(), get_port},
    Port = receive P -> P end,
    do_stop(Port, Pid);
do_stop(Port, [])->
    case whereis(percept2_httpd) of
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
            TmpDir = get_svg_alias_dir(),
            rm_tmp_files(TmpDir),
            Pid ! quit,
            case ets:info(egd_font_table) of 
                undefined -> ok;
                _  ->ets:delete(egd_font_table)
            end,
            inets:stop(httpd, Pid2),
            percept2_code_server:stop()
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
    T0 = erlang:timestamp(),
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
                                "Incorrect file or malformed trace file: ~p~n", [Filename])),
            Parent ! {error, Msg};
    	{parse_complete, {Pid, Count}} ->
            Pid ! {ack, self()},
            T1 = erlang:timestamp(),
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
service_memory({Pid, Port, Host, TmpDir}) ->
    receive
	quit -> 
	    ok;
	{Reply, get_port} ->
	    Reply ! Port,
	    service_memory({Pid, Port, Host, TmpDir});
	{Reply, get_host} -> 
	    Reply ! Host,
	    service_memory({Pid, Port, Host, TmpDir});
	{Reply, get_pid} -> 
	    Reply ! Pid,
	    service_memory({Pid, Port, Host, TmpDir});
        {Reply, get_dir} ->
            Reply ! {dir,TmpDir},
            service_memory({Pid, Port, Host, TmpDir})
    end.

% Create config data for the webserver 
-spec get_webserver_config(list(), pos_integer()) -> {ok, list()}.
get_webserver_config(Servername, Port) 
  when is_list(Servername), is_integer(Port) ->
    Path = code:priv_dir(percept2),
    Root = filename:join([Path, "server_root"]),
    MimeTypesFile = filename:join([Root,"conf","mime.types"]),
    {ok, MimeTypes} = httpd_conf:load_mime_types(MimeTypesFile),
    TmpDir = get_tmp_dir(),
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
        {alias,{"/svgs/", TmpDir}},
	{alias,{"/css/", filename:join([Root, "css"]) ++ "/"}},
	{alias,{"/tree/", filename:join([Root, "tree"]) ++ "/"}},
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
        {accept_timeout, 50000},
	{port, Port}],
    {ok, Config}.


rm_tmp_files(Dir) ->
    case file:list_dir(Dir) of 
        {error, Error} ->
            {error, Error};
        {ok, FileNames} ->
            [file:delete(filename:join(Dir, F))
             ||F<-FileNames]
    end.

get_svg_alias_dir() ->
    percept2_httpd!{self(), get_dir},
    receive 
        {dir, Dir} ->
            Dir
    end.
get_svg_alias_dir(Config) ->
    [Dir]=[Dir||{alias,{"/svgs/", Dir}}<-Config],
    Dir.

get_tmp_dir()->
    ServerRoot = filename:join([code:priv_dir(percept2), "server_root"]),
    case writeable(ServerRoot) of 
         true ->
            SvgDir=filename:join([ServerRoot, "svgs"]) ++"/",
            case filelib:ensure_dir(SvgDir) of 
                ok -> SvgDir;
                {error, _} ->
                    get_tmp_dir_1()
            end;
        false ->
            get_tmp_dir_1()
    end.
get_tmp_dir_1()->
    Dir="/tmp/percept2/",
    case filelib:ensure_dir(Dir) of
        ok -> Dir;
        {error, _Reason} ->
            get_user_input_dir()
    end.

get_user_input_dir() ->
    Msg ="I could not find a directory with write permission to store "
        "temporary files, please specify a directory.\n",
    get_user_input_dir(Msg).
get_user_input_dir(Msg) ->
    io:format("~s\n", [Msg]),
    Input=io:get_line("Dir: "),
    [$\n|Str] = lists:reverse(Input),
    Str1 = filename:join(lists:reverse(Str), "."),
    [_|Str2] = lists:reverse(Str1),
    Dir = lists:reverse(Str2),             
    case filelib:is_dir(Dir) of 
        true ->
            case writeable(Dir) of 
                true ->
                    Dir;
                false ->
                    Msg1="I don't have write permission to the directory given, "
                        "please specify another directory.\n", 
                    get_user_input_dir(Msg1)
            end;
        false ->
            case filelib:ensure_dir(Dir) of 
                ok ->
                    Dir;
                {error,_Reason} ->
                    Msg2="The directory given does not exist, or could not be created, "
                        "please specify another directory.\n",
                    get_user_input_dir(Msg2)
            end
    end.
writeable(F) ->
    case file:read_file_info(F) of
        {ok, FileInfo} ->
            case FileInfo#file_info.access of 
                read_write -> true;
                write -> true;
                _ -> false
            end;
        _ -> false
    end.

