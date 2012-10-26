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

-module(percept2_data_gen).

-compile(export_all).


-include("../include/percept2.hrl").

activity_data() ->
    StartTs = percept2_db:select({system, start_ts}),
    StopTs = percept2_db:select({system, stop_ts}),
    Options =  [{ts_min, StartTs},{ts_max, StopTs}],
    Counts1=[{?seconds(TS, StartTs), Procs, Ports}||
                {TS, {Procs, Ports}}
                    <-percept2_db:select(
                        {activity,{runnable_counts, Options}})],
    Str = lists:flatten([io_lib:format("{~f, {~p,~p}}.\n", [Sec, Procs, Counts])||{Sec, Procs,Counts}<-Counts1]),
    file:write_file("activity.txt", list_to_binary(Str)).
    

rq_migration_data() ->
    StartTs = percept2_db:select({system, start_ts}),
    Data = lists:sort(lists:append([[{?seconds(Ts, StartTs), E#information.id, Rq}
                                      ||{Ts, Rq}<-E#information.rq_history]
                                     ||E<-ets:tab2list(pdb_info)])),
    Str=lists:flatten([io_lib:format("~p.\n", [E])||E<-Data]),
    file:write_file("rq_migration.txt", list_to_binary(Str)).           
                                                                                                  
    
