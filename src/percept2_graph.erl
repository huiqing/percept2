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

%% @doc Interface for CGI request on graphs used by percept. The module exports two functions that 
%%are implementations for ESI callbacks used by the httpd server. 
%%See http://www.erlang.org//doc/apps/inets/index.html.

-module(percept2_graph).
-export([proc_lifetime/3, graph/3, scheduler_graph/3, 
         ports_graph/3, procs_graph/3,
         activity/3, percentage/3, calltime_percentage/3]).

-export([query_fun_time/3,
         memory_graph/3,
         inter_node_message_graph/3]).

-compile(export_all).

-include("../include/percept2.hrl").
-include_lib("kernel/include/file.hrl").

%% API

%% graph
%% @spec graph(SessionID, Env, Input) -> term()
%% @doc An ESI callback implementation used by the httpd server. 
%% 

graph(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(graph(Env, Input))).
  
%% activity
%% @spec activity(SessionID, Env, Input) -> term() 
%% @doc An ESI callback implementation used by the httpd server.

activity(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    StartTs = percept2_db:select({system, start_ts}),
    mod_esi:deliver(SessionID, binary_to_list(activity_bar(Env, Input, StartTs))).

proc_lifetime(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(proc_lifetime(Env, Input))).

query_fun_time(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(query_fun_time(Env, Input))).
   
percentage(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(percentage(Env,Input))).

calltime_percentage(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(calltime_percentage(Env,Input))).

scheduler_graph(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(scheduler_graph(Env, Input))).

ports_graph(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(ports_graph(Env, Input))).

procs_graph(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(procs_graph(Env, Input))).

memory_graph(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(memory_graph(Env, Input))).

inter_node_message_graph(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(inter_node_message_graph(Env, Input))).

graph(_Env, Input) ->
    graph_1(_Env, Input, procs_ports).

procs_graph(_Env, Input) ->
    graph_1(_Env, Input, procs).

ports_graph(_Env, Input) ->
    graph_1(_Env, Input, ports).

scheduler_graph(_Env, Input) ->
    graph_1(_Env, Input, schedulers).

graph_1(Env, Input, Type) -> 
    CacheKey = atom_to_list(Type)++integer_to_list(erlang:crc32(Input)),
    case ets:info(history_html) of 
        undefined ->
            graph_2(Env, Input, Type);
        _ ->
            case ets:lookup(history_html, CacheKey) of 
                [{history_html, CacheKey, Content}] ->
                    Content;
                [] ->
                    Content= graph_2(Env, Input, Type),
                    ets:insert(history_html, 
                               #history_html{id=CacheKey,
                                             content=Content}),
                    Content
            end
    end.                

graph_2(_Env, Input, Type) ->
    Query    = httpd:parse_query(Input),
    RangeMin = percept2_html:get_option_value("range_min", Query),
    RangeMax = percept2_html:get_option_value("range_max", Query),
    Pids     = percept2_html:get_option_value("pids", Query),
    Width    = percept2_html:get_option_value("width", Query),
    Height   = percept2_html:get_option_value("height", Query),
    
    StartTs  = percept2_db:select({system, start_ts}),
    TsMin    = percept2_html:seconds2ts(lists:max([RangeMin-0.1,0]), StartTs),
    TsMax    = percept2_html:seconds2ts(RangeMax+0.1, StartTs),
    
    %% Convert Pids to id option list
    IDs = [{pids, Pids}],
    TypeOpt  = case Type of 
                   procs_ports -> [{id, all}];
                   procs -> [{id, procs}];
                   ports -> [{id, ports}];
                   _ ->[]
               end,
    case Pids/=[] of 
        true -> 
            Options  = [{ts_min, TsMin},{ts_max, TsMax} | IDs],
            Acts     = percept2_db:select({activity, Options}),
            Counts=percept2_analyzer:activities2count2(Acts, StartTs),
            percept2_image:graph(Width, Height,{RangeMin, 0, RangeMax, 0},Counts,120);
        false ->                
            Options  = TypeOpt++ [{ts_min, TsMin},{ts_max, TsMax}],
            Counts = case Type of 
                         procs_ports ->
                             [{?seconds(TS, StartTs), Procs, Ports}||
                                 {TS, {Procs, Ports}}
                                     <-percept2_db:select(
                                         {activity,{runnable_counts, Options}})];
                         procs ->
                             [{?seconds(TS, StartTs), Procs, 0}||
                                 {TS, {Procs, _Ports}}
                                     <-percept2_db:select(
                                         {activity,{runnable_counts, Options}})];
                         ports ->
                             [{?seconds(TS, StartTs), 0, Ports}||
                                 {TS, {_Procs, Ports}}
                                     <-percept2_db:select(
                                         {activity,{runnable_counts, Options}})];
                         schedulers ->
                             Acts = percept2_db:select({scheduler, Options}),
                             Schedulers = erlang:system_info(schedulers), %% not needed if the trace info is correct!
                             [{?seconds(Ts, StartTs), lists:min([Scheds,Schedulers]), 0} ||
                                 #scheduler{timestamp = Ts, 
                                            active_scheds=Scheds} <- Acts]
                     end,
            case Counts of 
                [] -> 
                    percept2_image:error_graph(Width,Height, "No trace data recorded.");
                _ ->
                    percept2_image:graph(Width, Height, {RangeMin, 0, RangeMax, 0}, Counts,20)
            end
    end.

memory_graph(Env, Input) ->
    scheduler_graph(Env, Input). %% change this!
 
activity_bar(_Env, Input, StartTs) ->
    Query  = httpd:parse_query(Input),
    Pid    = percept2_html:get_option_value("pid", Query),
    Min    = percept2_html:get_option_value("range_min", Query),
    Max    = percept2_html:get_option_value("range_max", Query),
    Width  = percept2_html:get_option_value("width", Query),
    Height = percept2_html:get_option_value("height", Query),
    
    Data    = percept2_db:select({activity, {runnable, Pid}}),
    Activities = [{?seconds(Ts, StartTs), State, [{InOut, ?seconds(InOutTs, StartTs)}
                                                  ||{InOut, InOutTs}<-lists:reverse(InOuts)]} 
                  || {Ts, State,InOuts} <- Data],
    percept2_image:activities(Width-50, Height, {Min,Max}, Activities).

proc_lifetime(_Env, Input) ->
    Query = httpd:parse_query(Input),
    ProfileTime = percept2_html:get_option_value("profiletime", Query),
    Start = percept2_html:get_option_value("start", Query),
    End = percept2_html:get_option_value("end", Query),
    Width = percept2_html:get_option_value("width", Query),
    Height = percept2_html:get_option_value("height", Query),
    percept2_image:proc_lifetime(round(Width), round(Height), float(Start), float(End), float(ProfileTime)).


query_fun_time(_Env, Input) ->
    Query = httpd:parse_query(Input),
    QueryStart = percept2_html:get_option_value("query_start", Query),
    FunStart = percept2_html:get_option_value("fun_start", Query),
    QueryEnd = percept2_html:get_option_value("query_end", Query),
    FunEnd = percept2_html:get_option_value("fun_end", Query),
    Width = percept2_html:get_option_value("width", Query),
    Height = percept2_html:get_option_value("height", Query),
    percept2_image:query_fun_time(
        round(Width), round(Height), {float(QueryStart),float(FunStart)},
        {float(QueryEnd), float(FunEnd)}).
    

percentage(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Width = percept2_html:get_option_value("width", Query),
    Height = percept2_html:get_option_value("height", Query),
    Percentage = percept2_html:get_option_value("percentage", Query),
    percept2_image:percentage(round(Width), round(Height), float(Percentage)).


calltime_percentage(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Width = percept2_html:get_option_value("width", Query),
    Height = percept2_html:get_option_value("height", Query),
    CallTime = percept2_html:get_option_value("calltime", Query),
    Percentage = percept2_html:get_option_value("percentage", Query),
    percept2_image:calltime_percentage(round(Width), round(Height), float(CallTime), float(Percentage)).


inter_node_message_graph(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Width = percept2_html:get_option_value("width", Query),
    Height = percept2_html:get_option_value("height", Query),
    RangeMin = percept2_html:get_option_value("range_min", Query),
    RangeMax = percept2_html:get_option_value("range_max", Query),
    Node1 = percept2_html:get_option_value("node1", Query),
    Node2 = percept2_html:get_option_value("node2", Query),
    StartTs = percept2_db:select({system, start_ts}),
    MinTs    = percept2_html:seconds2ts(RangeMin, StartTs),
    MaxTs    = percept2_html:seconds2ts(RangeMax, StartTs),
    FromData = percept2_db:select({inter_node, {message_acts, {Node1, Node2, MinTs, MaxTs}}}),
    %% ToData = percept2_db:select({inter_node, {message_acts, {Node2, Node1, MinTs, MaxTs}}}),
    FromData1=[{?seconds(TS, StartTs), Size, 0}||{TS, Size}<-FromData],
    %% ToData1 =[{?seconds(TS, StartTs), Size, 0}||{TS, Size}<-ToData],
    percept2_image:inter_node_message_image(Width, Height, RangeMin, RangeMax, FromData1).
    
header() ->
    "Content-Type: image/png\r\n\r\n".

