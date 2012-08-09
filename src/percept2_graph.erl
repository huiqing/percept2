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
         activity/3, percentage/3, calltime_percentage/3]).

-export([query_fun_time/3, memory_graph/3]).

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
    mod_esi:deliver(SessionID, binary_to_list(activity_bar(Env, Input))).

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

memory_graph(SessionID, Env, Input) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, binary_to_list(memory_graph(Env, Input))).


graph(_Env, Input) ->
    Query    = httpd:parse_query(Input),
    RangeMin = percept2_html:get_option_value("range_min", Query),
    RangeMax = percept2_html:get_option_value("range_max", Query),
    Pids     = percept2_html:get_option_value("pids", Query),
    Width    = percept2_html:get_option_value("width", Query),
    Height   = percept2_html:get_option_value("height", Query),
    
    % Convert Pids to id option list
    IDs      = [ {id, ID} || ID <- Pids],

    % seconds2ts
    StartTs  = percept2_db:select({system, start_ts}),
    TsMin    = percept2_analyzer:seconds2ts(RangeMin, StartTs),
    TsMax    = percept2_analyzer:seconds2ts(RangeMax, StartTs),
    
    Options  = [{ts_min, TsMin},{ts_max, TsMax} | IDs],
    Acts     = percept2_db:select({activity, Options}),
    Counts   = case IDs of
                   [] -> percept2_analyzer:activities2count(Acts, StartTs);
                   _ -> percept2_analyzer:activities2count2(Acts, StartTs)
               end,
    percept2_image:graph(Width, Height, Counts).

scheduler_graph(_Env, Input) -> 
    Query    = httpd:parse_query(Input),
    RangeMin = percept2_html:get_option_value("range_min", Query),
    RangeMax = percept2_html:get_option_value("range_max", Query),
    Width    = percept2_html:get_option_value("width", Query),
    Height   = percept2_html:get_option_value("height", Query),
    
    StartTs  = percept2_db:select({system, start_ts}),
    TsMin    = percept2_analyzer:seconds2ts(RangeMin, StartTs),
    TsMax    = percept2_analyzer:seconds2ts(RangeMax, StartTs),
    

    Acts     = percept2_db:select({scheduler, [{ts_min, TsMin}, {ts_max,TsMax}]}),
    %% io:format("Acts:\n~p\n", [Acts]),
    Counts   = [{?seconds(Ts, StartTs), Scheds, 0} || #activity{where = Scheds, timestamp = Ts} <- Acts],
    percept2_image:graph(Width, Height, Counts).

memory_graph(_Env, Input) ->
    Query    = httpd:parse_query(Input),
    RangeMin = percept2_html:get_option_value("range_min", Query),
    RangeMax = percept2_html:get_option_value("range_max", Query),
    Width    = percept2_html:get_option_value("width", Query),
    Height   = percept2_html:get_option_value("height", Query),
    
    StartTs  = percept2_db:select({system, start_ts}),
    TsMin    = percept2_analyzer:seconds2ts(RangeMin, StartTs),
    TsMax    = percept2_analyzer:seconds2ts(RangeMax, StartTs),
    

    Acts     = percept2_db:select({scheduler, [{ts_min, TsMin}, {ts_max,TsMax}]}),
    %% io:format("Acts:\n~p\n", [Acts]),
    Counts   = [{?seconds(Ts, StartTs), Scheds, 0} || #activity{where = Scheds, timestamp = Ts} <- Acts],
    percept2_image:graph(Width, Height, Counts).

activity_bar(_Env, Input) ->
    Query  = httpd:parse_query(Input),
    Pid    = percept2_html:get_option_value("pid", Query),
    Min    = percept2_html:get_option_value("range_min", Query),
    Max    = percept2_html:get_option_value("range_max", Query),
    Width  = percept2_html:get_option_value("width", Query),
    Height = percept2_html:get_option_value("height", Query),
    
    Data    = percept2_db:select({activity, [{id, Pid}]}),
    StartTs = percept2_db:select({system, start_ts}),
    Activities = [{?seconds(Ts, StartTs), State} || #activity{timestamp = Ts, state = State} <- Data],
    percept2_image:activities(Width, Height, {Min,Max}, Activities).

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

header() ->
    "Content-Type: image/png\r\n\r\n".
