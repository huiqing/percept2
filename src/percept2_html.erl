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

-module(percept2_html).
-export([
         overview_page/3,
         concurrency_page/3,
         codelocation_page/3, 
         active_funcs_page/3,
         databases_page/3, 
         load_database_page/3, 
         process_tree_page/3,
         sub_process_tree_page/3,
         ports_page/3,
         process_info_page/3,
         function_info_page/3,
         inter_node_message_page/3,
         inter_node_message_graph_page/3,
         inter_node_comm_graph_page/3,
         summary_report_page/3,
         process_tree_visualisation_page/3,
         process_comm_graph_page/3,
         callgraph_visualisation_page/3,
         callgraph_slice_visualisation_page/3,
         func_callgraph_content/3,
         visualise_sampling_data_page/3,
         process_info_page_without_menu/3
        ]).

-export([get_option_value/2,
         seconds2ts/2]).

%% experimental.
-compile(export_all).

-include("../include/percept2.hrl").
-include_lib("kernel/include/file.hrl").

%%% --------------------------- %%%
%%% 	API functions     	%%%
%%% --------------------------- %%%

-spec(overview_page(pid(), list(), string()) -> ok | {error, term()}).

-define(Million, 1000000).

overview_page(SessionID, Env, Input) ->
    ?dbg(0, "overview_content input:~p~n", [Input]),
    try
        case percept2_db:is_database_loaded() of 
           false ->
                deliver_page(SessionID, menu_1(0, 0), 
                             blink_msg("No data has been analyzed!"));
            _ ->
                Menu = menu(Input),
                OverviewContent = overview_content(Env, Input),
                deliver_page(SessionID, Menu, OverviewContent)
        end
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(concurrency_page(pid(), list(), string()) -> ok | {error, term()}).
concurrency_page(SessionID, Env, Input) ->
    try
        mod_esi:deliver(SessionID, concurrency_header()),
        mod_esi:deliver(SessionID, menu(Input)),
        mod_esi:deliver(SessionID, concurrency_content(Env, Input)),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(codelocation_page(pid(), list(), string()) -> ok | {error, term()}).
codelocation_page(SessionID, Env, Input) ->
    try
        Menu = menu(Input),
        Content = codelocation_content(Env, Input),
        deliver_page(SessionID, Menu, Content)
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(active_funcs_page(pid(), list(), string()) -> ok | {error, term()}).
active_funcs_page(SessionID, Env, Input) ->
    try
        case percept2_db:is_database_loaded() of 
            false ->
                deliver_page(SessionID, menu_1(0, 0), 
                             blink_msg("No data has been analyzed!"));
            _ ->
                Menu = menu(Input),
                Content = active_funcs_content(Env, Input),
                deliver_page(SessionID, Menu, Content)
        end
    catch
        _E1:_E2->
            error_page(SessionID, Env, Input)
    end.

-spec(summary_report_page(pid(), list(), string()) -> ok | {error, term()}).
summary_report_page(SessionID, Env, Input) ->
    try
        case percept2_db:is_database_loaded() of 
            false ->
                deliver_page(SessionID, menu_1(0, 0), 
                             blink_msg("No data has been analyzed!"));
            _ ->
                Menu = menu(Input),
                deliver_page(SessionID, Menu, summary_report_content())
        end
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.
    
-spec(databases_page(pid(), list(), string()) -> ok | {error, term()}).
databases_page(SessionID, Env, Input) ->
    try 
        Menu = menu_1(0,0),
        deliver_page(SessionID, Menu, databases_content())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(load_database_page(pid(), list(), string()) -> ok | {error, term()}).
load_database_page(SessionID, Env, Input) ->
    try
        mod_esi:deliver(SessionID, header()),
        % Very dynamic page, handled differently
        load_database_content(SessionID, Env, Input),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(process_tree_page(pid(), list(), string()) -> ok | {error, term()}).
process_tree_page(SessionID, Env, Input) ->
    try
        case percept2_db:is_database_loaded() of 
            false ->
                deliver_page(SessionID, menu_1(0, 0), 
                             blink_msg("No data has been analyzed!"));
            _ ->
                Menu = menu(Input),
                {Header, Content} = process_page_header_content(Env, Input),
                mod_esi:deliver(SessionID, header(Header)),
                mod_esi:deliver(SessionID, Menu),
                mod_esi:deliver(SessionID, Content),
                mod_esi:deliver(SessionID, footer())
        end
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.


-spec(sub_process_tree_page(pid(), list(), string()) -> ok | {error, term()}).
sub_process_tree_page(SessionID, Env, Input) ->
    try
        case percept2_db:is_database_loaded() of 
            false ->
                deliver_page(SessionID, menu_1(0, 0), 
                             blink_msg("No data has been analyzed!"));
            _ ->
                Menu = menu(Input),
                {Header, Content} = sub_process_page_header_content(Env, Input),
                mod_esi:deliver(SessionID, header(Header)),
                mod_esi:deliver(SessionID, Menu),
                mod_esi:deliver(SessionID, Content),
                mod_esi:deliver(SessionID, footer())
        end
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.


-spec(ports_page(pid(), list(), string()) -> ok | {error, term()}).
ports_page(SessionID, Env, Input) ->
    try
        case percept2_db:is_database_loaded() of 
            false ->
                deliver_page(SessionID, menu_1(0, 0), 
                             blink_msg("No data has been analyzed!"));
            _ ->
                Menu = menu(Input),
                Content = ports_page_content(Env, Input),
                mod_esi:deliver(SessionID, header()),
                mod_esi:deliver(SessionID, Menu),
                mod_esi:deliver(SessionID, Content),
                mod_esi:deliver(SessionID, footer())
        end
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.
-spec(process_tree_visualisation_page(pid(), list(), string()) -> 
             ok | {error, term()}).
process_tree_visualisation_page(SessionID, Env, Input) ->
    try
        mod_esi:deliver(SessionID, header()),
        mod_esi:deliver(SessionID, menu(Input)), 
        mod_esi:deliver(SessionID, process_tree_content(Env, Input)),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.


-spec(process_comm_graph_page(pid(), list(), string()) -> 
             ok | {error, term()}).
process_comm_graph_page(SessionID, Env, Input) ->
    try
        mod_esi:deliver(SessionID, header()),
        mod_esi:deliver(SessionID, menu(Input)), 
        
        mod_esi:deliver(SessionID, process_comm_graph_content(Env, Input)),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(inter_node_comm_graph_page(pid(), list(), string()) -> 
             ok | {error, term()}).
inter_node_comm_graph_page(SessionID, Env, Input) ->
    try
        mod_esi:deliver(SessionID, header()),
        mod_esi:deliver(SessionID, menu(Input)), 
        
        mod_esi:deliver(SessionID, inter_node_comm_graph_content(Env, Input)),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(process_info_page(pid(), list(), string()) -> ok | {error, term()}).
process_info_page(SessionID, Env, Input) ->
    try
        Menu = menu(Input),
        Content = process_info_content(Env, Input),
        deliver_page(SessionID, Menu, Content)
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(process_info_page_without_menu(
        pid(), list(), string()) -> ok | {error, term()}).
process_info_page_without_menu(SessionID, Env, Input) ->
    try
        Content = process_info_content(Env, Input),
        mod_esi:deliver(SessionID,  common_header([])),
        mod_esi:deliver(SessionID, Content),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(function_info_page(pid(), list(), string()) -> ok | {error, term()}).
function_info_page(SessionID, Env, Input) ->
    try
        Menu = menu(Input),
        Content = function_info_content(Env, Input),
        deliver_page(SessionID, Menu, Content)
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(function_info_page_without_menu(
        pid(), list(), string()) -> ok | {error, term()}).
function_info_page_without_menu(SessionID, Env, Input) ->
    try
        Content = function_info_content(Env, Input),
        mod_esi:deliver(SessionID,  common_header([])),
        mod_esi:deliver(SessionID, Content),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(callgraph_visualisation_page(pid(), list(), string()) -> 
             ok | {error, term()}).
callgraph_visualisation_page(SessionID, Env, Input) ->
    try
        mod_esi:deliver(SessionID, header()),
        mod_esi:deliver(SessionID, menu(Input)), 
        mod_esi:deliver(SessionID, callgraph_time_content(Env, Input)),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.


-spec(callgraph_slice_visualisation_page(pid(), list(), string()) -> 
             ok | {error, term()}).
callgraph_slice_visualisation_page(SessionID, Env, Input) ->
    try
        mod_esi:deliver(SessionID, header()),
        mod_esi:deliver(SessionID, menu(Input)), 
        mod_esi:deliver(SessionID, callgraph_slice_content(Env, Input)),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

inter_node_message_page(SessionID, Env, Input) ->
    try
        case percept2_db:is_database_loaded() of 
            false ->
                deliver_page(SessionID, menu_1(0, 0), 
                             blink_msg("No data has been analyzed!"));
            _ ->
                mod_esi:deliver(SessionID, inter_node_message_header()),
                mod_esi:deliver(SessionID, menu(Input)), 
                mod_esi:deliver(SessionID, inter_node_message_content(Env, Input)),
                mod_esi:deliver(SessionID, footer())
        end
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

inter_node_message_graph_page(SessionID, Env, Input) ->
    try
        mod_esi:deliver(SessionID, inter_node_message_header()),
        mod_esi:deliver(SessionID, menu(Input)), 
        mod_esi:deliver(SessionID, inter_node_msg_graph_content(Env, Input)),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

-spec(deliver_page(pid(), list(), string()) -> 
             ok | {error, term()}).
deliver_page(SessionID, Menu, Content) ->
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, Menu),
    mod_esi:deliver(SessionID, Content),
    mod_esi:deliver(SessionID, footer()).
   
%%% --------------------------- %%%
%%% 	loal functions   	%%%
%%% --------------------------- %%%
error_page(SessionID, _Env, _Input) ->
    StackTrace = lists:flatten(
                   io_lib:format("~p\n",
                          [erlang:get_stacktrace()])),
    Str="<div>" ++
        "<h3 style=\"text-align:center;\"> Percept Internal Error </h3>" ++
        "<center><h3><p>" ++ StackTrace ++ "</p></h3></center>" ++
        "</div>",
    mod_esi:deliver(SessionID, header()),
    mod_esi:deliver(SessionID, Str),
    mod_esi:deliver(SessionID, footer()).


%%% --------------------------- %%%
%%% 	Content pages     	%%%
%%% --------------------------- %%%

%%% overview content page.
-spec(overview_content(list(), string()) -> string()).
overview_content(Env, Input) ->
    CacheKey = "overview"++integer_to_list(erlang:crc32(Input)),
    gen_content(Env,Input,CacheKey,fun overview_content_1/2).

-spec(overview_content_1(list(), string()) -> string()).
overview_content_1(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Min = get_option_value("range_min", Query),
    Max = get_option_value("range_max", Query),
    TotalProfileTime = ?seconds((percept2_db:select({system, stop_ts})),
                                (percept2_db:select({system, start_ts}))),
    Procs = percept2_db:select({information, procs_count}),
    Ports = percept2_db:select({information, ports_count}),
    InformationTable = 
	"<table>" ++
	table_line(["Profile time:", TotalProfileTime]) ++
        %% This needs to be fixed. What about if profiling was done
        %% on another machine with different number of cores?
        table_line(["Schedulers:", erlang:system_info(schedulers)]) ++  

	table_line(["Processes:", Procs]) ++
        table_line(["Ports:", Ports]) ++
    	table_line(["Min. range:", Min]) ++
    	table_line(["Max. range:", Max]) ++
    	"</table>",
    Header = "
    <div id=\"content\">
    <div>" ++ InformationTable ++ "</div>\n
    <form name=form_area method=POST action=/cgi-bin/percept2_html/overview_page>
    <input name=data_min type=hidden value=" ++ term2html(float(Min)) ++ ">
    <input name=data_max type=hidden value=" ++ term2html(float(Max)) ++ ">\n",
    RangeTable = 
	"<table>"++
	table_line([
	    "Min:", 
	    "<input name=range_min value=" ++ term2html(float(Min)) ++">",
	    "<select name=\"graph_select\" onChange=\"select_image()\">
                <option value=\"" ++ url_procs_graph(Min, Max, []) ++ "\">Processes </option>
                <option value=\"" ++ url_sched_graph(Min, Max, []) ++ "\">Schedulers </option>
                <option value=\"" ++ url_ports_graph(Min, Max, []) ++ "\">Ports </option>
	      	<option value=\"" ++ url_graph(Min,Max,[]) ++ "\">Ports & Processes </option>
            </select>",
	    "<input type=submit value=Update>"
	    ]) ++
	table_line([
	    "Max:", 
	    "<input name=range_max value=" ++ term2html(float(Max)) ++">",
            "",
	    "<a href=\"/cgi-bin/percept2_html/codelocation_page?range_min=" ++
	    term2html(Min) ++ "&range_max=" ++ term2html(Max) ++"\">Code location</a>"
            ]) ++
    	"</table>",
    MainTable = 
	"<table>" ++
	table_line([div_tag_graph("percept_graph", 20)]) ++
	table_line([RangeTable]) ++
	"</table>",
    Footer = "</div></form>",
    Header ++ MainTable ++ Footer.
    
-spec(div_tag_graph(string(), integer()) -> string()).
div_tag_graph(Name, Margin) ->
    MarginStr=integer_to_list(Margin),
   %background:url('/images/loader.gif') no-repeat center;
    "<div id=\""++Name++"\" 
	onMouseDown=\"select_down(event,"++MarginStr++")\" 
	onMouseMove=\"select_move(event,"++MarginStr++")\" 
	onMouseUp=\"select_up(event,"++MarginStr++")\"

	style=\"
	background-size: 100%;
	background-origin: content;
	width: 100%;
	position:relative; 
	\">     
	
	<div id=\"percept_areaselect\"
	style=\"background-color:#ef0909;
	position:relative;
	visibility:hidden;
        border-left: 1px solid #101010;
	border-right: 1px solid #101010;
	z-index:2;
	width:40px;
	height:40px;\"></div></div>".

url_graph(Min,Max,Pids) ->
    graph("/cgi-bin/percept2_graph/graph",Min,Max,Pids).

url_sched_graph(Min, Max, Pids) ->
    graph("/cgi-bin/percept2_graph/scheduler_graph", Min, Max, Pids).

url_ports_graph(Min, Max, Pids) ->
    graph("/cgi-bin/percept2_graph/ports_graph",Min, Max, Pids).

url_procs_graph(Min, Max, Pids) ->
    graph("/cgi-bin/percept2_graph/procs_graph",Min, Max, Pids).

-spec graph(Func :: string(), Min :: float(), Max :: float(),
            Pids :: [pid()]) -> string().
graph(Func,Min,Max,Pids) ->
    Func ++ "?range_min=" ++ term2html(float(Min))
    	++ "&range_max=" ++ term2html(float(Max))
        ++ "&pids=" ++ pids2request(Pids).

-spec(pids2request([pid_value()]) ->  string()).
pids2request([]) ->
    "";
pids2request(Pids) ->
    PidValues = [pid2str(Pid) || Pid <- Pids],
    join_strings_with(PidValues, ":").
                                   
%%% code location content page.
-spec(codelocation_content(list(), string()) -> string()).
codelocation_content(Env, Input) ->
    CacheKey = "codelocation_content"++integer_to_list(erlang:crc32(Input)),
    gen_content(Env, Input, CacheKey, fun codelocation_content_1/2).
codelocation_content_1(_Env, Input) ->
    Query   = httpd:parse_query(Input),
    Min     = get_option_value("range_min", Query),
    Max     = get_option_value("range_max", Query),
    StartTs = percept2_db:select({system, start_ts}),
    TsMin   = seconds2ts(Min, StartTs),
    TsMax   = seconds2ts(Max, StartTs),
    Acts    = percept2_db:select({activity, [{ts_min, TsMin}, {ts_max, TsMax}]}),
    Secs  = [timer:now_diff(A#activity.timestamp,StartTs)/1000 || A <- Acts],
    Delta = cl_deltas(Secs),
    Zip   = lists:zip(Acts, Delta),
    CleanPid = percept2_db:select({system, nodes})==1,
    TableContent = [[{td, term2html(D)},
                     {td, term2html(timer:now_diff(A#activity.timestamp,StartTs) / 1000)},
                     {td, pid2html(A#activity.id, CleanPid)},
                     {td, term2html(A#activity.state)},
                     {td, mfa2html(A#activity.where)},
                     {td, term2html({A#activity.runnable_procs, A#activity.runnable_ports})}] || {A, D} <- Zip],
    Table = html_table([
                        [{th, "delta [ms]"},
                         {th, "time [ms]"},
                         {th, " pid "},
                         {th, "activity"},
                         {th, "module:function/arity"},
                         {th, "#runnables"}]] ++ TableContent),
    "<div id=\"content\">" ++
        Table ++  "</div>".

cl_deltas([])   -> [];
cl_deltas(List) -> cl_deltas(List, [0.0]).
cl_deltas([_], Out)       -> lists:reverse(Out);
cl_deltas([A,B|Ls], Out) -> cl_deltas([B|Ls], [B - A | Out]).

%%% concurrency page content.
-spec(concurrency_content(list(), string()) -> string()).
concurrency_content(Env, Input) ->
    CacheKey = "concurrency_content"++
        integer_to_list(erlang:crc32(Input)),
    Query = httpd:parse_query(Input),
    Pids = ticked_pids(Query),
    case Pids of 
        [] ->
            error_msg("No processes selected!");
        _ ->
            gen_content(Env, Input, CacheKey, 
                        fun concurrency_content_1/2)
    end.
-spec(concurrency_content_1(list(), string()) -> string()).
concurrency_content_1(_Env, Input) ->
    IDs = get_pids_to_compare(Input),
    StartTs = percept2_db:select({system, start_ts}),
    StopTs = percept2_db:select({system, stop_ts}),
    {MinTs, MaxTs} = percept2_db:select({activity, {min_max_ts, IDs}}),
    case {MinTs, MaxTs} of 
        {undefined, undefined} ->
            error_msg("No activities have been recorded "
                      "for the processess selected!");
        _ ->
            %% concurrency_content_2(IDs, StartTs, MinTs, MaxTs)
            concurrency_content_2(IDs, StartTs, StartTs, StopTs)
    end.

concurrency_content_2(IDs, StartTs, MinTs, MaxTs) ->
    {T0, T1} = {?seconds(MinTs, StartTs), ?seconds(MaxTs, StartTs)},
    CleanPid = percept2_db:select({system, nodes})==1,
    ActivityBarTable =
        lists:append(lists:map(
                       fun(Pid) ->
                               ValueString = pid2str(Pid),
                               ActivityBar = image_string_head(
                                               "activity", 
                                               [{"pid", ValueString},
                                                {range_min, T0},
                                                {range_max, T1},
                                                {height, 10}], []),
                               %% RegName = percept2_db:pid2name(Pid),
                               %% PidOrName = case RegName of 
                               %%                 undefined -> pid2html(Pid, CleanPid);
                               %%                 _ -> term2html(RegName)
                               %%             end,
                               "<tr><td><input type=checkbox name="++pid2str(Pid)++"></td>"++
                                 case has_callgraph(Pid) of 
                                     true ->
                                         "<td width=100; bgcolor=#E0FFFF>"++
                                             pid2html(Pid, CleanPid)++"</td>";
                                     false ->
                                         "<td width=100>"++pid2html(Pid, CleanPid)++"</td>"
                                 end ++
                                   "<td>" ++ "<img onload=\"size_image(this, '" ++
                                   ActivityBar ++
                                   "')\" src=/images/white.png border=0 />" ++ "</td>\n"
                       end, IDs)),
    PidsRequest = pids2request(IDs),
    Header = "
     <div id=\"content\">
     <form name=form_area method=POST action=/cgi-bin/percept2_html/active_funcs_page>
     <input name=data_min type=hidden value=" ++ term2html(T0) ++ ">
     <input name=data_max type=hidden value=" ++ term2html(T1) ++ ">
     <input name=height   type=hidden value=" ++ term2html(400) ++ ">
     <input name=pids     type=hidden value=" ++ term2html(PidsRequest) ++ ">
     \n",  
    Header1 = 
        "<div id=\"content\">
         <form name=form_area1 method=POST action=/cgi-bin/percept2_html/concurrency_page>\n",  
    FuncActs = "<table>"++table_line(
                            [
                             "Min:",
                             "<input name=range_min value=" ++ term2html(float(T0)) ++">",
                             "",
                             "Max:", 
                             "<input name=range_max value=" ++ term2html(float(T1)) ++">",
                             "",
                             "<input type=submit value=\"Active Functions\">"
                            ])
        ++"</table>",
    MainTable = 
         "<table cellspacing=0 cellpadding=0 border=0>" ++ 
         table_line([div_tag_graph("percept_graph", 120)])
         ++
         table_line([FuncActs]) ++ "</table>\n",
    MainTable1 =
        "<table cellspacing=0 cellpadding=0 border=0>" ++ 
        table_line(["<input type=submit value=\"Compare Selected Processes\">"])++ "</table>\n"++
        "<table  cellspacing=0 cellpadding=0 border=0>" ++
        [ActivityBarTable]++"</table>",
    Footer = "</div></form>",
    Header++ MainTable++ Footer ++ Header1 ++ MainTable1++Footer.

-spec(get_pids_to_compare(string()) ->[pid()]).
get_pids_to_compare(Input) ->
    Query = httpd:parse_query(Input),
    Pids = ticked_pids(Query),
    ResPids=case lists:member({"include_children_procs", "on"}, Query) of 
                true -> 
                    case lists:member({"include_unshown_procs","on"}, Query) of 
                        true ->
                            lists:append([case is_dummy_pid(Pid) of 
                                              true -> expand_a_pid(Pid);
                                              false ->process_tree_pids(Pid)
                                          end||Pid<-Pids]);
                        false ->
                            AllPids=lists:append([process_tree_pids(Pid)                                                  
                                                  ||Pid<-Pids,not is_dummy_pid(Pid)]),
                            TickedRealPids = [Pid||Pid<-Pids, not is_dummy_pid(Pid)],
                            (lists:usort(AllPids) --hidden_pids())++TickedRealPids                  
                    end;
                false ->
                    case lists:member({"include_unshown_procs","on"}, Query) of
                        true ->
                            lists:append([expand_a_pid(Pid)|| Pid <- Pids]);
                        false ->
                            [Pid||Pid<-Pids,not is_dummy_pid(Pid)]
                    end
            end,
    lists:usort(ResPids).

ticked_pids(Query) ->
    Options= ["select_all",
              "include_unshown_procs", 
              "include_children_procs"],
    [str_to_internal_pid(PidValue)
     || {PidValue, Case} <- Query,
        Case == "on", not lists:member(PidValue, Options)].
    
  
hidden_pids() ->
    DummyEntries=percept2_db:select({information, dummy_pids}),
    {_, HiddenPidLists}=
        lists:unzip([{Entry#information.id, Entry#information.hidden_pids}
                     ||Entry<-DummyEntries]),
    lists:append(HiddenPidLists).   

    
expand_a_pid(Pid) ->
    case is_dummy_pid(Pid) of
        true ->
            [Info] = percept2_db:select({information, Pid}),            
            PidLists=[[percept2_db:pid2value(Pid2)||Pid2<-process_tree_pids(Pid1)]
                      ||Pid1 <- Info#information.hidden_pids],
            lists:append(PidLists);
        false ->
            [Pid]
    end.

process_tree_pids(Pid) ->
    [Info] = percept2_db:select({information, Pid}),
    case Info#information.children of 
        [] -> [Pid];
        ChildrenPids ->
            [Pid|lists:append([process_tree_pids(ChildPid)
                               ||ChildPid<-ChildrenPids])]
    end.              
             
%%% active functions content page.
-spec(active_funcs_content(list(), string()) -> string()).
active_funcs_content(Env, Input) ->
    CacheKey = "active_funcs_content"++
        integer_to_list(erlang:crc32(Input)),
    gen_content(Env, Input, CacheKey, fun active_funcs_content_1/2).
active_funcs_content_1(_Env, Input) ->
    Query   = httpd:parse_query(Input),
    Min     = get_option_value("range_min", Query),
    Max     = get_option_value("range_max", Query),
    StartTs = percept2_db:select({system, start_ts}),
    TsMin   = seconds2ts(Min, StartTs),
    TsMax   = seconds2ts(Max, StartTs),
    Pids = get_option_value("pids", Query),
    ActiveFuns  = percept2_db:select({code,[{ts_min, TsMin}, {ts_max, TsMax}, {pids, Pids}]}),
    ActiveFuns1 = [{Pid, Start, Func, End}||
                      {funcall_info,{Pid, Start, End}, Func}<-ActiveFuns],
    GroupedActiveFuns = [[group_active_funcs(ActiveFuncsByFunc)
                          ||ActiveFuncsByFunc<-group_by(3,ActiveFuncsByPid)]
                         ||ActiveFuncsByPid <- group_by(1, ActiveFuns1)],
    GroupedActiveFuns1 = lists:sort(fun({Pid1,_, {StartTs1,_}, _},
                                        {Pid2, _,{StartTs2,_},_})->
                                            {Pid1, StartTs1} =< {Pid2, StartTs2}
                                    end, lists:append(GroupedActiveFuns)),
    active_funcs_content_2(Min, Max, StartTs, GroupedActiveFuns1, Pids).
  
group_active_funcs([{Pid, StartTs, Func, EndTs}]) ->
    SystemStartTS = percept2_db:select({system, start_ts}),
    FunStart = ?seconds(StartTs, SystemStartTS),
    FunEnd = ?seconds(EndTs, SystemStartTS),
    {Pid, Func, {FunStart, FunEnd}, 1};
group_active_funcs(Data=[{Pid, StartTs, Func, _EndTs}|_ActiveFuncs]) ->
    SystemStartTS = percept2_db:select({system, start_ts}),
    FunStart = ?seconds(StartTs, SystemStartTS),
    StartEndTs = [{Start, End}||{_Pid, Start, _Func, End}<-Data],
    FunEnd = lists:sum([timer:now_diff(End, Start)|| 
                           {Start, End} <- StartEndTs]) / ?Million
       + FunStart,
    {Pid, Func,{FunStart, FunEnd}, length(Data)}.
   
active_funcs_content_2(_Min, _Max, _StartTs, [], _) ->
    blink_msg("No function activities recorded for the time interval selected.");
active_funcs_content_2(Min, Max, _StartTs, ActiveFuns, Pids) ->
    CleanPid = percept2_db:select({system, nodes})==1,
    TableContent = [[{td, pid2html(Pid, CleanPid)},
                     {td, mfa2html_with_link({Pid, Func})},
                     {td, make_image_string({FunStart, FunEnd}, {Min, Max})},
                     {td, term2html(Count)}]
                    ||{Pid, Func, {FunStart, FunEnd}, Count}<- ActiveFuns],
    InfoTable = "<table>" ++ 
        table_line(["Min. range:", Min])++
        table_line(["Max. range:", Max])++
        "</table>",
    PidsWithCallgraph = [Pid||Pid<-Pids, has_callgraph(Pid)],
    Table = html_table(
              [[{th, " pid "},
                {th, "module:function/arity"},
                {th, "active period"}, 
                {th, "call count"}]
              ] ++TableContent, " class=\"sortable\""),
    case PidsWithCallgraph of 
        [] ->
            "<div id=\"content\">" ++ InfoTable++"<br></br>"++ Table ++ "</div>";
        _  ->
            PidList = lists:foldl(
                        fun(Pid, Out) ->
                                Out ++ "<option value=\""++
                                    pid2str(Pid)++"\">"++
                                    term2html(Pid)++"</option>"
                        end, "", PidsWithCallgraph),
            Header =
                "<div id=\"content\">
        	<form name=callgraph_slice method=POST action=/cgi-bin/percept2_html/callgraph_slice_visualisation_page>
                 <input name=range_min type=hidden value=" ++ term2html(Min) ++ ">
                 <input name=range_max type=hidden value=" ++ term2html(Max) ++ ">
                \n",
            Header ++
                InfoTable ++
                "<br></br>" ++
                "<table>
	           <tr><td><select name=\"pid\">"++PidList ++
                "</select></td>
                 <td width=200><input type=submit value=\"Call Graph Slice\" /></td></tr>
        	</table>" 
                ++"<br></br>"
                ++ Table ++
                "</div></form>"
    end.

            
make_image_string({FunStart, FunEnd}, {QueryStart, QueryEnd})->
    image_string(query_fun_time,
                 [{query_start, QueryStart},
                  {fun_start, FunStart},
                  {query_end, QueryEnd},
                  {fun_end, FunEnd},
                  {width, 100},
                  {height, 10}]).


%%% inter-node message passing content.
-spec(inter_node_msg_graph_content(list(), string()) -> string()).
inter_node_msg_graph_content(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Node1 = get_option_value("node1", Query),
    Node2 = get_option_value("node2", Query),
    Min = get_option_value("range_min", Query),
    Max = get_option_value("range_max", Query),
    inter_node_msg_graph_content_1(Node1, Node2, Min, Max).

inter_node_msg_graph_content_1(Node, Node, _, _) ->
    error_msg("The two nodes selected are the same!\n");
inter_node_msg_graph_content_1(Node1, Node2, Min, Max) ->
    Header = "
    <div id=\"content\">
    <form name=form_area method=POST action=/cgi-bin/percept2_html/inter_node_message_graph_page>
    <input name=data_min type=hidden value=" ++ term2html(float(Min)) ++ ">
    <input name=data_max type=hidden value=" ++ term2html(float(Max)) ++ ">
    <input name=node1 type=hidden value=" ++ term2html(Node1) ++ ">
    <input name=node2 type=hidden value=" ++ term2html(Node2) ++ ">
    \n",
    RangeTable = 
	"<table>"++
	table_line([
                    "Min:", 
                    "<input name=range_min value=" ++ term2html(float(Min)) ++">",
                    "Max:", 
                    "<input name=range_max value=" ++ term2html(float(Max)) ++">"
                    "<input type=submit value=Update>"
                   ]) ++
        "</table>",
    
    MainTable = 
	"<table>" ++
	table_line([div_tag_graph("percept_graph", 120)]) ++
     	table_line([RangeTable]) ++
	"</table>",
    Footer = "</div></form>",
    Header ++ MainTable ++ Footer.
    
-spec(summary_report_content() -> string()).
summary_report_content() ->
    blink_msg("Sorry, this functionality is not supported yet.").

%%% databases content page.
databases_content() ->
    "<div id=\"content\">
	<form name=load_percept_file method=post action=/cgi-bin/percept2_html/load_database_page>
	<center>
	<table>
	    <tr><td>Enter file to analyse:</td><td><input type=hidden name=path /></td></tr>
	    <tr><td><input type=file name=file size=40 /></td><td><input type=submit value=Load onClick=\"path.value = file.value;\" /></td></tr>
	</table>
	</center>
	</form>
	</div>". 

%%% databases content page.
load_database_content(SessionId, _Env, Input) ->
    Query = httpd:parse_query(Input),
    {_,{_,Path}} = lists:keysearch("file", 1, Query),
    {_,{_,File}} = lists:keysearch("path", 1, Query),
    Filename = filename:join(Path, File),
    % Check path/file/filename
    
    mod_esi:deliver(SessionId, "<div id=\"content\">"), 
    case file:read_file_info(Filename) of
	{ok, _} ->
    	    Content = "<center>
    	    Parsing: " ++ Filename ++ "<br>
    	    </center>",
	    mod_esi:deliver(SessionId, Content),
	        case percept2:analyze([Filename]) of
		    {error, Reason} ->
                        mod_esi:deliver(SessionId, error_msg("Analyze" ++ term2html(Reason)));
		    _ ->
		        Complete = "<center><a href=\"/cgi-bin/percept2_html/overview_page\">View</a></center>",
	                mod_esi:deliver(SessionId, Complete)
	        end;
	{error, Reason} ->
	    mod_esi:deliver(SessionId, error_msg("File" ++ term2html(Reason)))
    end,
    mod_esi:deliver(SessionId, "</div>"). 

%%% process tree  page content.
process_page_header_content(Env, Input) ->
    CacheKey = "process_tree_page"++integer_to_list(erlang:crc32(Input)),
    gen_content(Env, Input, CacheKey, fun process_page_header_content_1/2).
 

sub_process_page_header_content(Env, Input) ->
    CacheKey = "sub_process_tree_page"++integer_to_list(erlang:crc32(Input)),
    gen_content(Env, Input, CacheKey, fun sub_process_page_header_content_1/2).
 

sub_process_page_header_content_1(_Env, Input) ->
    Query   = httpd:parse_query(Input),
    Pid     = get_option_value("pid", Query),
    %% StartTs = percept2_db:select({system, start_ts}),
    [I] = percept2_db:select({information, Pid}),
    ChildrenTrees = I#information.hidden_proc_trees,
    ProcessTreeHeader = mk_display_style(ChildrenTrees),
    %% TsMin and TsMax are not used yet.
    Content = processes_content(ChildrenTrees, {0, 0}),  
    {ProcessTreeHeader, Content}.


process_page_header_content_1(_Env, Input) ->
    Query   = httpd:parse_query(Input),
    Min     = get_option_value("range_min", Query),
    Max     = get_option_value("range_max", Query),
    StartTs = percept2_db:select({system, start_ts}),
    TsMin   = seconds2ts(Min, StartTs),
    TsMax   = seconds2ts(Max, StartTs),
    ProcessTree = percept2_db:gen_compressed_process_tree(),
    ProcessTreeHeader = mk_display_style(ProcessTree),
    Content = processes_content(ProcessTree, {TsMin, TsMax}),
    {ProcessTreeHeader, Content}.

processes_content(ProcessTree, {_TsMin, _TsMax}) ->
    SystemStartTS = percept2_db:select({system, start_ts}),
    SystemStopTS = percept2_db:select({system, stop_ts}),
    ProfileTime = ?seconds(SystemStopTS, SystemStartTS),
    ProcsHtml = mk_procs_html(ProcessTree, ProfileTime, []), 
    Selector = "<table cellspacing=10>" ++
        "<tr> <td>" ++ "<input onClick='selectall()' type=checkbox name=select_all>Select all" ++ "</td>"
        ++"<td><input type=checkbox name=include_children_procs>Include children procs"++"</td>" 
        ++"<td><input type=checkbox name=include_unshown_procs>Include omitted procs"++"</td></tr>" ++
        "<tr> <td> <input type=submit value=Compare> </td>" ++
        "<td align=right width=200> <a href=\"/cgi-bin/percept2_html/process_tree_visualisation_page\">"++
        "<b>Process Tree Graph</b>"++"</a></td>" ++  
        "<td align=right width=200> <a href=\"/cgi-bin/percept2_html/process_comm_graph_page\">"++
        "<b align=middle> Process Communication</b>"++"</a></td>" ++  
        "</tr>",
    Right = "<div>"
        ++ Selector ++ 
        "</div>\n",
    Middle = "<div id=\"content\">
    <table>" ++
        ProcsHtml ++
        "</table>" ++
        Right ++ 
        "</div>\n",
    "<form name=process_select method=POST action=/cgi-bin/percept2_html/concurrency_page>" ++
        Middle ++ 
        "</form>".
      
mk_procs_html(ProcessTree, ProfileTime, ActiveProcsInfo) ->
    CleanPid = percept2_db:select({system, nodes})==1,
    ProfileOpts = percept2_db:select({system, profile_opts}),
    MsgSendProfiled = ProfileOpts==[] orelse 
        lists:member('send', ProfileOpts),
    MsgRecvProfiled = ProfileOpts==[] orelse 
        lists:member('receive', ProfileOpts),
    RqProfiled = ProfileOpts==[] orelse 
        lists:member('scheduler_id', ProfileOpts),
    ProcsHtml=lists:foldl(
              fun ({I, Children},Out) ->
                      Id=I#information.id,
                      StartTime = procstarttime(I#information.start),
                      EndTime   = procstoptime(I#information.stop),
                      Prepare =
                          table_line([
                                      "<input type=checkbox name=" ++ pid2str(I#information.id) ++ ">",
                                      expand_or_collapse(Children, Id),
                                      pid2html(Id, CleanPid),
                                      image_string(proc_lifetime, [
                                                           {profiletime, ProfileTime},
                                                           {start, StartTime},
                                                           {"end", term2html(float(EndTime))},
                                                           {width, 100},
                                                                   {height, 10}]),
                                      proc_name_to_html(Id, I#information.name),
                                      pid2html(I#information.parent, CleanPid),
                                      info_to_html(max(0,length(I#information.rq_history)-1), RqProfiled),
                                      info_to_html(num_msgs_recv(I), MsgRecvProfiled),
                                      info_to_html(avg_msg_size_recv(I), MsgRecvProfiled), 
                                      info_to_html(num_msgs_sent(I), MsgSendProfiled),
                                      info_to_html(avg_msg_size_sent(I),MsgSendProfiled),
                                      mfa2html(I#information.entry),
                                      visual_link({I#information.id, undefined, undefined}, 
                                                  I#information.children)]),
                      SubTable = sub_table(Id, Children, ProfileTime, ActiveProcsInfo),
                      [Prepare, SubTable|Out]
              end, [], ProcessTree),
    if 
	length(ProcsHtml) > 0 ->
            " <tr><td>
 	   <table class=sortable align=center width=1100 cellspacing=10 border=0>"
                ++
                "<tr>
		<td width=40><b>Select</b></td>
                <td width=40> <b>[+/-]</b></td>
		<td width=80><b>Pid</b></td>
               	<td width=80><b>Lifetime</b></td>
	        <td width=80><b>Name</b></td>
		<td width=80><b>Parent</b></td>
                <td width=80><b>#RQ_chgs</b></td>
                <td width=100><b>#msgs<br />_recv</b></td>
                <td width=100><b>avg_size<br />msg_recv</b></td>
                <td width=100><b>#msgs <br /> _sent</b></td>
                <td width=100><b>avg_size<br />msg_sent  </b></td>
                <td width=120><b>Entrypoint</b></td>
                <td width=120><b> Callgraph </b></td>    
		</tr>" ++
		lists:flatten(ProcsHtml) ++ 
	    "</table>
	    </td></tr>";
	true ->
            ""
    end.

%%% process tree  page content.
ports_page_content(Env, Input) ->
    CacheKey = "ports_page"++integer_to_list(erlang:crc32(Input)),
    gen_content(Env, Input, CacheKey, fun ports_page_content_1/2).

ports_page_content_1(_Env, _Input) ->
    Ports = percept2_db:select({information, ports}),
    SystemStartTS = percept2_db:select({system, start_ts}),
    SystemStopTS = percept2_db:select({system, stop_ts}),
    ProfileTime = ?seconds(SystemStopTS, SystemStartTS),
    Ports = percept2_db:select({information, ports}),
    PortsHtml = mk_ports_html(lists:reverse(lists:keysort(2, Ports)), ProfileTime),
    "<div id=\"content\"> <table>" ++
        PortsHtml ++ 
        "</table>" ++
        "</div>\n".
   
mk_ports_html(Ports, ProfileTime) ->
    CleanPid = percept2_db:select({system, nodes})==1,
    PortsHtml=lists:foldl(
                fun (I, Out) ->
                        StartTime = procstarttime(I#information.start),
                        EndTime   = procstoptime(I#information.stop),
                        Prepare =
                            table_line([
                                        pid2html(I#information.id),
                                        image_string(proc_lifetime, [
                                                                     {profiletime, ProfileTime},
                                                                     {start, StartTime},
                                                                     {"end", term2html(float(EndTime))},
                                                                     {width, 100},
                                                                     {height, 10}]),
                                        mfa2html(I#information.entry),
                                        term2html(I#information.name),
                                        pid2html(I#information.parent, CleanPid)
                                       ]),
                        [Prepare|Out]
                end, [], Ports),        
    if length(PortsHtml) > 0 ->
    	   " <tr><td><b>Ports</b></td></tr>
            <table width=900  border=1 cellspacing=10 cellpadding=2>
		<tr>
	        <td align=middle width=80><b>Port Id</b></td>
		<td align=middle width=80><b>Lifetime</b></td>
                <td align=middle width=80><b>Entry</b></td>
	        <td align=middle width=80><b>Name</b></td>
		<td align=middle width=80><b>Parent</b></td>
               	</tr>" ++
	      lists:flatten(PortsHtml) ++
		"</table>
	    </td></tr>";
	true ->
          ""
    end.
 
num_msgs_recv(I) ->
    element(1,I#information.msgs_received).
 
avg_msg_size_recv(I) ->
    {No, Size} = I#information.msgs_received,
    case No of 
        0 -> 0;
        _ -> Size div No
    end.
 
info_msg_recv(I)->
    {num_msgs_recv(I), avg_msg_size_recv(I)}.

num_msgs_sent(I) ->
    element(1,I#information.msgs_sent).

avg_msg_size_sent(I) ->
    {No, Size} = I#information.msgs_sent,
    case No of 
        0 -> 0;
        _ -> Size div No
    end.

info_msg_sent(I) ->
    {num_msgs_sent(I), avg_msg_size_sent(I)}.

info_to_html(_, false) ->
    "--";
info_to_html(Info, _) ->
    term2html(Info).

expand_or_collapse(Children, Id) ->
    case Children of 
        [] ->
            "<input type=\"button\", value=\"-\">";
        _ ->
            "<input type=\"button\" id=\"lnk" ++ pid2str(Id) ++
                  "\" onclick = \"return toggle('lnk" ++ pid2str(Id) ++ "', '"
                  ++ mk_table_id(Id) ++ "')\", value=\"+\">"
    end.

mk_table_id(Pid) ->
    "t" ++ [C||C <- pid2str(Pid), not lists:member(C, [46, 60, 62])].

sub_table(_Id, [], _ProfileTime, _) ->
    "";
sub_table(Id, Children, ProfileTime, ActivePids) ->
    SubHtml=mk_procs_html(Children, ProfileTime, ActivePids),
    "<tr><td colspan=\"10\"> <table width=1000 cellspacing=10  cellpadding=2 border=1 "
        "id=\""++mk_table_id(Id)++"\", style=\"margin-left:60px;\">" ++
        SubHtml ++ "</table></td></tr>".

mk_display_style(ProcessTrees) ->
    Str = parent_pids(ProcessTrees),
    "\n<style type=\"text/css\">\n" ++
      Str ++ " {display:none;}\n" ++
     "</style>\n".


parent_pids(ProcessTrees) ->
    parent_pids(ProcessTrees, []).
parent_pids([], Out) -> Out;
parent_pids([T|Ts], Out) ->
    case T of 
        {_I,[]} ->
            parent_pids(Ts, Out);
        {I, Children} ->
            if Out==[] ->
                    parent_pids(Children++Ts, Out++"#"
                                ++mk_table_id(I#information.id));
               true ->
                    parent_pids(Children++Ts, Out++",#"
                                ++mk_table_id(I#information.id))
            end
    end.

procstarttime(TS) ->
    case TS of
    	undefined -> 0.0;
	    TS -> ?seconds(TS,(percept2_db:select({system, start_ts})))
    end.

procstoptime(TS) ->
    case TS of
            undefined -> ?seconds((percept2_db:select({system, stop_ts})),
                              (percept2_db:select({system, start_ts})));
	    TS -> ?seconds(TS, (percept2_db:select({system, start_ts})))
    end.


%%% process_info_content
process_info_content(Env, Input) ->
    CacheKey = "process_info"++integer_to_list(erlang:crc32(Input)),
    gen_content(Env, Input, CacheKey, fun process_info_content_1/2).

process_info_content_1(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Pid = get_option_value("pid", Query),
    [I] = percept2_db:select({information, Pid}),
    ProfileOpts = percept2_db:select({system, profile_opts}),
    MsgSendProfiled = ProfileOpts==[] orelse 
        lists:member('send', ProfileOpts),
    MsgRecvProfiled = ProfileOpts==[] orelse 
        lists:member('receive', ProfileOpts),
    RqProfiled = ProfileOpts==[] orelse 
        lists:member('scheduler_id', ProfileOpts),
    GCProfiled =ProfileOpts==[] orelse 
        lists:member('garbage_collection', ProfileOpts),
    ArgumentString = case I#information.entry of
                         {_, _, Arguments} when is_list(Arguments)-> 
                             lists:flatten(io_lib:write(Arguments, 10));
                         _                 ->
                             ""
                     end,
    TimeTable = html_table([
	[{th, ""}, 
	 {th, "Timestamp"}, 
	 {th, "Profile Time"}],
	[{td, "Start"},
	 term2html(I#information.start),
	 term2html(procstarttime(I#information.start))],
	[{td, "Stop"},
	 term2html(I#information.stop),
	 term2html(procstoptime(I#information.stop))]
	]),   
    CleanPid = percept2_db:select({system, nodes})==1,
    InfoTable = html_table
                  ([
                    [{th, "Pid"},        pid2html(I#information.id, CleanPid)],
                    [{th, "Node"},       term2html(I#information.node)],
                    [{th, "Name"}, term2html(case is_dummy_pid(Pid) of
                                                 true -> dummy_process;
                                                 _ -> I#information.name
                                             end)],
                    [{th, "Entrypoint"}, mfa2html(I#information.entry)],
                    [{th, "Arguments"},  ArgumentString],
                    [{th, "Timetable"},  TimeTable],
                    [{th, "Parent"},     pid2html(I#information.parent, CleanPid)],
                    [{th, "Children"},   lists:flatten(lists:map(fun(Child) -> 
                                                                         pid2html(Child, CleanPid) ++ " " end,
                                                                 I#information.children))]]
                   ++ case is_dummy_pid(Pid) of 
                          true ->
                              [];
                          false ->
                              [[{th, "RQ_history"}, info_to_html(
                                                      element(2,lists:unzip(
                                                                  lists:keysort(1, I#information.rq_history))),
                                                      RqProfiled)]]
                      end
                   ++
                    [[{th, "{#msg_received, <br>avg_msg_size}"},
                     info_to_html(info_msg_recv(I), MsgRecvProfiled)],
                    [{th, "{#msg_sent,<br>avg_msg_size}"}, 
                     info_to_html(info_msg_sent(I), MsgSendProfiled)]]
                   ++
                       case is_dummy_pid(Pid) of 
                           true ->
                               [];
                           false ->
                               [[{th, "garbage collection time (in secs) <br>"},
                                info_to_html(I#information.gc_time/?Million, GCProfiled)]]
                       end
                   ++
                       case is_dummy_pid(Pid) of 
                           true -> [];
                           false->
                             [[{th, "accumulated runtime (in secs) <br>"},
                              term2html(I#information.accu_runtime/?Million)]]
                      end
                 ++
                   [[{th, "Callgraph/time"}, visual_link({Pid, I#information.entry, undefined}, [])]]
                 ++ case is_dummy_pid(Pid) of
                        true ->
                            [[{th, "Compressed Processes"}, lists:flatten(
                                                              lists:map(fun(Id) -> pid2html(Id, CleanPid) ++ " " end,
                                                                        I#information.hidden_pids))]];
                        false -> []
                    end),
    PidActivities = percept2_db:select({activity, [{id, Pid}]}),
    WaitingMfas   = percept2_analyzer:waiting_activities(PidActivities),
    TotalWaitTime = lists:sum( [T || {T, _, _} <- WaitingMfas] ),
    MfaTable = html_table([
        [{th, "percentage of <br>total waiting time"},
         {th, "total"},         
         {th, "mean"},
         {th, "stddev"},
         {th, "#recv"},
         {th, "module:function/arity"}]] 
                          ++ [[{td, image_string(percentage, [{width, 100}, {height, 10}, 
                                                              {percentage, Time / TotalWaitTime}])},
                               {td, term2html(Time)},
                               {td, term2html(Mean)},
                               {td, term2html(StdDev)},
                               {td, term2html(N)},
                               {td, mfa2html(MFA)}] || 
                                 {Time, MFA, {Mean, StdDev, N}} <- WaitingMfas]),
    
    "<div id=\"content\" scrolling=\"no\">" ++
        InfoTable ++ "<br>" ++
        MfaTable ++
        "</div>".


%%% process tree content.
process_tree_content(_Env, _Input) ->
    SvgDir = percept2:get_svg_alias_dir(),
    ImgFileName="processtree"++".svg",
    ImgFullFilePath = filename:join([SvgDir, ImgFileName]),
    Content = "<div style=\"text-align:center; align:center\">" ++
        "<h3 style=\"text-align:center;\">Process Tree</h3>"++ 
        "<object data=\"/svgs/"++ImgFileName++"\" type=\"image/svg+xml\"" ++
        " overflow=\"visible\"  scrolling=\"yes\" "++
        "></object>"++
        "</div>",
    case filelib:is_regular(ImgFullFilePath) of 
        true -> 
            %% file already generated, so reuse.
            Content;  
        false -> 
            GenImgRes=percept2_dot:gen_process_tree_img(SvgDir),
            process_gen_graph_img_result(Content, GenImgRes)
    end.
 

process_comm_graph_content(_Env, Input) ->
    Query = httpd:parse_query(Input),
    MinSends = get_option_value("sends_min", Query),
    MinSize = get_option_value("size_min", Query),
    SvgDir = percept2:get_svg_alias_dir(),
    ImgFileBaseName="proc_comm_graph"++"_"++integer_to_list(MinSends)
        ++"_"++integer_to_list(MinSize),
    ImgFileName = ImgFileBaseName++".svg",
    ImgFullFilePath = filename:join([SvgDir, ImgFileName]),
    Content = "<div style=\"text-align:center; align:center\">" ++
        "<h3 style=\"text-align:center;\">Process Communication Graph</h3>"++ 
        "<form name=filter_proc_comm_graph method=post 
           action=/cgi-bin/percept2_html/process_comm_graph_page>
	<center>
        <br></br>
        <table>
           <tr><td align=left>Minimum number of sends:</td>
               <td><input type=text name=sends_min  value=" 
                 ++ term2html(MinSends) ++ "> </tr>
           <tr><td align=left>Minimum avg. message size:</td> 
               <td align=left><input type=text name=size_min  value=" 
                 ++ term2html(MinSize) ++"> </td></tr>
           <tr><td><input type=submit value=\"Update\" /> </td></tr>
        </table>
  	</center>
	</form>" ++
        "<object data=\"/svgs/"++ImgFileName++"\" type=\"image/svg+xml\"" ++
        " overflow=\"visible\"  scrolling=\"yes\" "++
        "></object>"++
        "</div>",
    case filelib:is_regular(ImgFullFilePath) of 
        true -> 
            %% file already generated, so reuse.
            Content;  
        false -> 
           %%TODO: Add a timeout here in case it takes 'dot' too long 
           %%      generate the svg file.
            GenImgRes=percept2_dot:gen_process_comm_img( 
                        SvgDir, ImgFileBaseName, MinSends, MinSize),
            process_gen_graph_img_result(Content, GenImgRes)
    end.



inter_node_comm_graph_content(_Env, _Input) ->
    SvgDir = percept2:get_svg_alias_dir(),
    ImgFileBaseName="inter_node_comm_graph",
    ImgFileName = ImgFileBaseName++".svg",
    ImgFullFilePath = filename:join([SvgDir, ImgFileName]),
    Content = "<div style=\"text-align:center; align:center\">" ++
        "<h3 style=\"text-align:center;\">Inter-node Communication Graph</h3>"++ 
        "<object data=\"/svgs/"++ImgFileName++"\" type=\"image/svg+xml\"" ++
        " overflow=\"visible\"  scrolling=\"yes\" "++
        "></object>"++
        "</div>",
    case filelib:is_regular(ImgFullFilePath) of 
        true -> 
            %% file already generated, so reuse.
            Content;  
        false -> 
           %%TODO: Add a timeout here in case it takes 'dot' too long 
           %%      generate the svg file.
            GenImgRes=percept2_dot:gen_node_comm_img( 
                        SvgDir, ImgFileBaseName),
            process_gen_graph_img_result(Content, GenImgRes)
    end.

%%% function callgraph content
func_callgraph_content(_SessionID, Env, Input) ->
    CacheKey = "func_callpath"++integer_to_list(erlang:crc32(Input)),
    case ets:info(hisotry_html) of
        undefined ->
            apply(fun func_callgraph_content_1/2, [Env, Input]);
        _ ->
            case ets:lookup(history_html, CacheKey) of 
                [{history_html, CacheKey, HeaderStyleAndContent}] ->
                    HeaderStyleAndContent;
                [] ->
                    HeaderStyleAndContent= apply(fun func_callgraph_content_1/2, [Env, Input]),
                    ets:insert(history_html, 
                               #history_html{id=CacheKey,
                                         content=HeaderStyleAndContent}),
                    HeaderStyleAndContent
            end
    end.

func_callgraph_content_1(_Env, _Input) ->
    %% should Input be used?
    CallTree = ets:tab2list(fun_calltree),
    HeaderStyle = mk_fun_display_style(CallTree),
    Content = functions_content(CallTree),
    {HeaderStyle,Content}. 

functions_content(FunCallTree) ->
    FunsHtml=mk_funs_html(FunCallTree, false),
    Table=if length(FunsHtml) >0 ->
                  "<table border=1 cellspacing=10 cellpadding=2 bgcolor=\"#FFFFFF\">
                  <tr>
	          <td align=left width=80><b> Pid </b></td>
                  <td align=left width=80><b> [+/-] </b></td>
		  <td align=right width=160><b> module:function/arity </b></td>
	          <td align=right width=80><b> call count </b></td>   
                  <td align=right width=120><b> graph visualisation </b></td>    
	          </tr>" ++
                      lists:flatten(FunsHtml) ++ 
                      "</table>" ;
             true ->
                  ""
          end,
    "<div id=\"content\">" ++ 
        Table ++ 
        "</div>".

mk_funs_html(FunCallTree, IsChildren) ->
    lists:foldl(
      fun(F, Out) ->
              Id={Pid, _MFA, _Caller} = F#fun_calltree.id,
              FChildren = lists:reverse(F#fun_calltree.called),
              CNT = F#fun_calltree.cnt,
              Prepare = 
                  if IsChildren ->
                          table_line([pid2str(Pid),
                                      fun_expand_or_collapse(FChildren, Id),
                                      mfa2html_with_link(Id),
                                      term2html(CNT)]);
                     true ->
                          table_line([pid2str(Pid),
                                      fun_expand_or_collapse(FChildren, Id),
                                      mfa2html_with_link(Id),
                                      term2html(CNT),
                                      visual_link(Id, [])])
                  end,
              SubTable = fun_sub_table(Id, FChildren, true),
              [Prepare, SubTable|Out]
      end, [], lists:reverse(FunCallTree)).

fun_sub_table(_Id, [], _IsChildren) ->
    "";
fun_sub_table(Id={_Pid, _Fun, _Caller},Children, IsChildren) ->
    SubHtml = mk_funs_html(Children, IsChildren),
    "<tr><td colspan=\"10\"> <table cellspacing=10  cellpadding=2 border=1 "
        "id=\""++mk_fun_table_id(Id)++"\" style=\"margin-left:60px;\">" ++
        SubHtml ++ "</table></td></tr>".
     %% "<tr><td colspan=\"10\"> <table width=450 cellspacing=10 "
     
fun_expand_or_collapse(Children, Id) ->
    case Children of 
        [] ->
            "<input type=\"button\", value=\"-\">";
        _ ->
            "<input type=\"button\" id=\"lnk"++id_to_list(Id)++
                "\" onclick = \"return toggle('lnk"++id_to_list(Id)++"', '"
                ++mk_fun_table_id(Id)++"')\", value=\"+\">"
    end.


mk_fun_display_style(FunCallTree) ->
    Str = parent_funs(FunCallTree),
    "\n<style type=\"text/css\">\n" ++
        Str ++ " {display:none;}\n" ++
        "</style>\n".

parent_funs(FunCallTree) ->
    parent_funs(FunCallTree, []).
parent_funs([], Out) ->
    Out;
parent_funs([F|Fs], Out) ->
    Id=F#fun_calltree.id,
    case F#fun_calltree.called of 
        [] -> parent_funs(Fs, Out);
        Children ->
            if Out==[] ->
                    parent_funs(Children++Fs, Out++"#"++mk_fun_table_id(Id));
               true ->
                    parent_funs(Children++Fs, Out++",#"++mk_fun_table_id(Id))
            end
    end.

mk_fun_table_id(Id) ->
    "t"++[C||C<-id_to_list(Id), 
             not lists:member(C,[14,36, 45, 46,47, 60, 62,94])].

id_to_list({Pid, Func, Caller}) -> pid2str(Pid) ++ mfa_to_list(Func) ++ mfa_to_list(Caller).

mfa_to_list({M, F, A}) when is_atom(M) andalso is_atom(F)->
    atom_to_list(M)++atom_to_list(F)++integer_to_list(A);
mfa_to_list(V) when is_atom(V)-> atom_to_list(V).

    
%%%function information
function_info_content(Env, Input) ->
    CacheKey = "function_info"++integer_to_list(erlang:crc32(Input)),
    gen_content(Env, Input, CacheKey, fun function_info_content_1/2).
function_info_content_1(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Pid = get_option_value("pid", Query),
    MFA = get_option_value("mfa", Query),
    [I] = percept2_db:select({information, Pid}),
    [F] = percept2_db:select({funs, {Pid, MFA}}),
    CleanPid = percept2_db:select({system, nodes})==1,
    CallersTable = html_table([[{th, " module:function/arity "}, {th, " call count "}]]++
                                  [[{td, mfa2html_with_link({Pid,C})}, {td, term2html(Count)}]||
                                      {C, Count}<-F#fun_info.callers, Count/=0]), 
    CalledTable= html_table([[{th, " module:function/arity "}, {th, " call count "}]]++
                                [[{td, mfa2html_with_link({Pid,C})}, {td, term2html(Count)}]||
                                    {C, Count}<-F#fun_info.called]),
    InfoTable = html_table([
                            [{th, "Pid"},         pid2html(Pid, CleanPid)],
                            [{th, "Entrypoint"},  mfa2html(I#information.entry)],
                            [{th, "M:F/A"},       mfa2html_with_link({Pid, MFA})],
                            [{th, "Call count"}, term2html(F#fun_info.call_count)],
                            [{th, "Accumulated time <br>(in secs)"}, term2html((F#fun_info.acc_time/?Million))],
                            [{th, "Callers"},     CallersTable], 
                            [{th, "Called"},      CalledTable]
                           ]),
    "<div id=\"content\">" ++
     InfoTable ++ "<br>" ++
         "</div>".


callgraph_time_content(Env, Input) ->
    CleanPid = percept2_db:select({system, nodes})==1,
    Query = httpd:parse_query(Input),
    Pid = get_option_value("pid", Query),
    MinTimePercent = get_option_value("time_percent_min", Query),
    ImgFileBaseName="callgraph" ++ pid2str(Pid)++"_"++integer_to_list(MinTimePercent),
    ImgFileName=ImgFileBaseName++".svg",
    SvgDir = percept2:get_svg_alias_dir(),
    ImgFullFilePath = filename:join([SvgDir, ImgFileName]),
    Table = calltime_content(Env,Pid),
    Content = "<div style=\"text-align:center; align:center\">" ++
        "<h3 style=\"text-align:center;\">" ++ pid2html(Pid,CleanPid)++"</h3>"++ 
        "<form name=filter_callgraph method=post 
           action=/cgi-bin/percept2_html/callgraph_visualisation_page>
        <input name=pid type=hidden value=" ++ pid2str(Pid) ++ ">
	<center>
        <table> <tr><td align=left>Minimum time percentage:</td> 
               <td align=left><input type=text name=time_percent_min  value=" 
                 ++ term2html(MinTimePercent) ++"> </td></tr>
           <tr><td><input type=submit value=\"Update\" /> </td></tr>
        </table>
  	</center>
	</form>" ++
        "<object data=\"/svgs/"++ImgFileName++"\" type=\"image/svg+xml\"" ++
        " overflow=\"visible\"  scrolling=\"yes\" "++
        "></object>"++
        "<h3 style=\"text-align:center;\">" ++ "Accumulated Calltime"++"</h3>"++
        Table++
        "<br></br><br></br>"++
        "</div>",
    case filelib:is_regular(ImgFullFilePath) of 
        true -> Content;  %% file already generated.
        false -> 
            GenImgRes=percept2_dot:gen_callgraph_img(
                        Pid, SvgDir, ImgFileBaseName, MinTimePercent),
            process_gen_graph_img_result(Content, GenImgRes)
    end.


callgraph_slice_content(_Env, Input) ->
    Query = httpd:parse_query(Input),
    Pid = get_option_value("pid", Query),
    Min = get_option_value("range_min", Query),
    Max = get_option_value("range_max", Query),
    ImgFileName="callgraph" ++ pid2str(Pid) ++
        term2html(Min)++"_"++term2html(Max)++ ".svg",
    SvgDir = percept2:get_svg_alias_dir(),
    ImgFullFilePath = filename:join([SvgDir, ImgFileName]),
    Content = "<div style=\"text-align:center; align:center\"; width=1000>" ++
        "<object data=\"/svgs/"++ImgFileName++"\" "++ "type=\"image/svg+xml\"" ++
        " overflow=\"visible\"  scrolling=\"yes\" "++
        "></object>"++
        "</div>",
    case filelib:is_regular(ImgFullFilePath) of 
        true -> Content;  
        false -> 
            GenImgRes=percept2_dot:gen_callgraph_slice_img(Pid,Min,Max,SvgDir),
            process_gen_graph_img_result(Content, GenImgRes)
    end.


process_gen_graph_img_result(Content, GenImgRes) ->
    case GenImgRes of
        ok ->
            Content;
        no_image ->
            Msg = "No data generated",
            graph_img_error_page(Msg);
        dot_not_found ->
            Msg = "Percept2 cound not find the 'dot' executable from Graphviz; please make sure Graphviz is installed.",
            graph_img_error_page(Msg);
        {gen_svg_failed, Cmd} ->
            Msg = "Percept2 failed to use the 'dot' command (from Graphviz) to generate a .svg file. <br> The command "
                "Percept2 tried to run was: <br>" ++ Cmd,
            graph_img_error_page(Msg);
        {gnuplot_failed, Cmd} ->
            Msg = "Percept2 failed to use the 'gnuplot' command to generate a .svg file. <br> The command "
                "Percept2 tried to run was: <br>" ++ Cmd,
            graph_img_error_page(Msg)
    end.

graph_img_error_page(Msg) ->
    "<div style=\"text-align:center;\">" ++
        "<center><h3><p>" ++ Msg ++ "</p></h3></center>" ++
    "</div>".

        
calltime_content(Env, Pid)->
    CacheKey = "calltime" ++ integer_to_list(erlang:crc32(pid2str(Pid))),
    gen_content(Env, Pid, CacheKey, fun calltime_content_1/2).

calltime_content_1(_Env, Pid) ->
    Elems0 = percept2_db:select({calltime, Pid}),
    Elems = lists:reverse(lists:keysort(1, Elems0)),
    SystemStartTS = percept2_db:select({system, start_ts}),
    SystemStopTS = percept2_db:select({system, stop_ts}),
    [PidInfo] = percept2_db:select({information, Pid}),
    ProcStartTs = case PidInfo#information.start of 
                    undefined -> SystemStartTS;
                    StartTs -> StartTs
                end,
    ProcStopTs = case PidInfo#information.stop of 
                  undefined -> SystemStopTS;
                  StopTs -> StopTs
              end,
    ProcLifeTime = timer:now_diff(ProcStopTs, ProcStartTs),
    Props = " align=center",
    html_table(
      [[{th, "module:function/arity"},
        {th, "callcount"},
        {th, "accumulated time"}]|
       [[{td, mfa2html_with_link({Pid,Func})},
         {td, term2html(CallCount)},
         {td, image_string(calltime_percentage, 
                           [{width,200}, {height, 10}, 
                            {calltime, CallTime / ?Million},
                            {percentage, CallTime/ProcLifeTime}])}]
        ||{{_Pid, CallTime}, Func, CallCount}<-Elems]], Props).
   

inter_node_message_content(Env, _Input) ->
    Nodes =percept2_db:select({inter_node, all}),
    case length(Nodes) < 2 of 
        true -> blink_msg("No inter-node message passing has been recorded.");
        _ ->
            inter_node_message_content_1(Env, Nodes)
    end.

inter_node_message_content_1(_Env, Nodes) -> 
    NodeList = lists:foldl(
                 fun(Node, Out) ->
                         Out ++ "<option value=\""++atom_to_list(Node)++"\">"++atom_to_list(Node)++"</option>"
                 end, "", Nodes),    
    "<div id=\"content\">
	<form name=inter_node_message method=POST action=/cgi-bin/percept2_html/inter_node_message_graph_page>
	<center>
         <table>
	    <tr>
                 <td width=200>Sender node:</td>
                <td width=200>Receiver node:</td></tr>
	    <tr><td><select name=\"node1\">"++NodeList ++
            "</select></td>
            <td><select name=\"node2\">"++NodeList++
        "</select></td>
         <td width=200><input type=submit value=\"Generate Node-to-Node \n Message sends Graph\" /></td>"++
        "<td align=right width=400> <a href=\"/cgi-bin/percept2_html/inter_node_comm_graph_page\">"++
        "<b>Overall Inter-node Communication Graph</b>"++"</a></td></tr>" ++
	"</table>
	</center>
	</form>
	</div>". 

    
%%% --------------------------- %%%
%%% 	Utility functions	%%%
%%% --------------------------- %%%

%% Should be in string stdlib?

join_strings(Strings) ->
    lists:flatten(Strings).

-spec join_strings_with(Strings :: [string()], Separator :: string()) -> string().

join_strings_with([S1, S2 | R], S) ->
    join_strings_with([join_strings_with(S1,S2,S) | R], S);
join_strings_with([S], _) ->
    S.
join_strings_with(S1, S2, S) ->
    join_strings([S1,S,S2]).

%%% Generic erlang2html

-spec html_table(Rows :: [[string() | {'td' | 'th', string()}]]) -> string().
html_table(Rows) ->
    html_table(Rows, "").

html_table(Rows, Props) -> "<table" ++ Props++">" ++ html_table_row(Rows) ++ "</table>".

html_table_row(Rows) -> html_table_row(Rows, odd).
html_table_row([], _) -> "";
html_table_row([Row|Rows], odd ) -> "<tr class=\"odd\">" ++ html_table_data(Row) ++ "</tr>" ++ html_table_row(Rows, even);
html_table_row([Row|Rows], even) -> "<tr class=\"even\">" ++ html_table_data(Row) ++ "</tr>" ++ html_table_row(Rows, odd ).

html_table_data([]) -> "";
html_table_data([{td, Data}|Row]) -> "<td>" ++ Data ++ "</td>" ++ html_table_data(Row);
html_table_data([{th, Data}|Row]) -> "<th>" ++ Data ++ "</th>" ++ html_table_data(Row);
html_table_data([Data|Row])       -> "<td>" ++ Data ++ "</td>" ++ html_table_data(Row).

-spec table_line(Table :: [any()]) -> string().

table_line(List) -> table_line(List, ["<tr>"]).
table_line([], Out) -> lists:flatten(lists:reverse(["</tr>\n"|Out]));
table_line([Element | Elements], Out) when is_list(Element) ->
    table_line(Elements, ["<td align=left>" ++ Element ++ "</td>" |Out]);
table_line([Element | Elements], Out) ->
    table_line(Elements, ["<td align=left>" ++ term2html(Element) ++ "</td>"|Out]).

-spec term2html(any()) -> string().

term2html(Term) when is_float(Term) -> lists:flatten(io_lib:format("~.4f", [Term]));
term2html(Pid={pid, _}) -> "<" ++ pid2str(Pid) ++ ">";
term2html(Term) -> lists:flatten(io_lib:format("~p", [Term])).

-spec mfa2html(MFA :: {atom(), atom(), list() | integer()}) -> string().

mfa2html({Module, Function, Arguments}) when is_list(Arguments) ->
    lists:flatten(io_lib:format("~p:~p/~p", [Module, Function, length(Arguments)]));
mfa2html({Module, Function, Arity}) when is_atom(Module), is_integer(Arity) ->
    lists:flatten(io_lib:format("~p:~p/~p", [Module, Function, Arity]));
mfa2html(V) when is_atom(V)->
    atom_to_list(V);
mfa2html(_V) -> "undefined".

    

%% -spec mfa2html_with_link({Pid::pid(),MFA :: {atom(), atom(), list() | integer()}}) -> string().

mfa2html_with_link({Pid, MFA, _Caller}) ->
    mfa2html_with_link({Pid, MFA});
mfa2html_with_link({Pid, {Module, Function, Arguments}}) when is_list(Arguments) ->
    MFAString=lists:flatten(io_lib:format("~p:~p/~p", 
                                          [Module, Function, length(Arguments)])),
    MFAValue=lists:flatten(io_lib:format("{~p,~p,~p}", 
                                         [Module, Function, length(Arguments)])),
    "<a href=\"/cgi-bin/percept2_html/function_info_page?pid=" ++ pid2str(Pid) ++
        "&mfa=" ++ MFAValue ++ "\">" ++ MFAString ++ "</a>";
mfa2html_with_link({Pid, {Module, Function, Arity}}) when is_atom(Module), is_integer(Arity) ->
    MFAString=lists:flatten(io_lib:format("~p:~p/~p", [Module, Function, Arity])),
    MFAValue=lists:flatten(io_lib:format("{~p,~p,~p}", [Module, Function, Arity])),
    "<a href=\"/cgi-bin/percept2_html/function_info_page?pid=" ++ pid2str(Pid) ++
        "&mfa=" ++ MFAValue ++ "\">" ++ MFAString ++ "</a>";
mfa2html_with_link({_Pid, V}) when is_atom(V) ->
    atom_to_list(V).



visual_link({Pid,_, _}, ChildrenPids)->
    case has_callgraph(Pid) of 
        true ->
            "<a href=\"/cgi-bin/percept2_html/callgraph_visualisation_page?pid=" ++ 
                pid2str(Pid) ++ "\">" ++ "show call graph/time" ++ "</a>";
        false ->
            case has_children_with_callgraph(ChildrenPids) of 
                true ->
                    "childern w/t call graph/time";
                false ->
                    "no callgraph/time"
            end
    end.

has_children_with_callgraph(Pids) ->
    lists:any(fun(Pid) ->
                      has_children_with_callgraph_1(Pid)
              end, Pids).

has_children_with_callgraph_1(Pid) ->
    case has_callgraph(Pid) of 
        true ->
            true;
        false ->
            [Info] = percept2_db:select({information, Pid}),
            has_children_with_callgraph(Info#information.children)
    end.

has_callgraph(Pid) ->
    CallTree=ets:select(fun_calltree, 
                        [{#fun_calltree{id = {Pid, '_','_'}, _='_'},
                          [],
                          ['$_']
                         }]), 
    CallTree/=[].

%%% --------------------------- %%%
%%% 	to html          	%%%
%%% --------------------------- %%%
pid2html(Pid={pid, {_P1, P2, P3}}, true) ->
    PidValue = pid2str(Pid),
    PidString= "<"++pid2str({pid, {0, P2, P3}})++">",
    pid2html_1(Pid, PidString, PidValue);
pid2html(Other, _) ->
    pid2html(Other).

-spec pid2html(Pid :: pid()|pid_value()| port()) -> string().
pid2html(Pid) 
  when is_pid(Pid); is_tuple(Pid) andalso element(1, Pid)==pid ->
    PidString = term2html(Pid),
    PidValue = pid2str(Pid),
    pid2html_1(Pid, PidString, PidValue);
pid2html(Pid) when is_port(Pid) ->
    term2html(Pid);
pid2html(_) ->
    "undefined".

pid2html_1(Pid, PidString, PidValue) ->
    case is_dummy_pid(Pid) of
        true ->
            "<a href=\"/cgi-bin/percept2_html/process_info_page?pid="++PidValue++"\">"
                ++"<font color=\"#FF0000\">"++PidString++"</font></a>";
        _ ->
            "<a href=\"/cgi-bin/percept2_html/process_info_page?pid="++
                PidValue++"\">"++PidString++"</a>"
    end.

proc_name_to_html(Pid, Name) ->
    case is_dummy_pid(Pid) of 
        true ->
            "<a href=\"/cgi-bin/percept2_html/sub_process_tree_page?pid="++pid2str(Pid)++"\">"
                ++"<font color=\"#FF0000\">"++term2html(Name)++"</font></a>";
        _ -> term2html(Name)
    end.

msg2html(Msg) ->
    AvgMsgSize = lists:last(tuple_to_list(Msg)),
    %% TODO: generalise this function!
    case AvgMsgSize < 1000000 of   
        true ->
            term2html(Msg);
        false ->
            " <font color=\"#FF0000\">"++term2html(Msg)++"</font></a>"
    end.

%%% --------------------------- %%%
%%% 	percept conversions    	%%%
%%% --------------------------- %%%
-spec image_string(Request :: string()) -> string().
image_string(Request) ->
    "<img border=0 src=\"/cgi-bin/percept2_graph/" ++
    Request ++ 
    " \">".
-spec image_string(atom() | string(), list()) -> string().
image_string(Request, Options) when is_atom(Request), is_list(Options) ->
     image_string(image_string_head(erlang:atom_to_list(Request), Options, []));
image_string(Request, Options) when is_list(Options) ->
     image_string(image_string_head(Request, Options, [])).

image_string_head(Request, [{Type, Value} | Opts], Out) when is_atom(Type), is_number(Value) ->
    Opt = join_strings(["?",term2html(Type),"=",term2html(Value)]),
    image_string_tail(Request, Opts, [Opt|Out]);
image_string_head(Request, [{Type, Value} | Opts], Out) ->
    Opt = join_strings(["?",Type,"=",Value]),
    image_string_tail(Request, Opts, [Opt|Out]).

image_string_tail(Request, [], Out) ->
    join_strings([Request | lists:reverse(Out)]);
image_string_tail(Request, [{Type, Value} | Opts], Out) when is_atom(Type), is_number(Value) ->
    Opt = join_strings(["&",term2html(Type),"=",term2html(Value)]),
    image_string_tail(Request, Opts, [Opt|Out]);
image_string_tail(Request, [{Type, Value} | Opts], Out) ->
    Opt = join_strings(["&",Type,"=",Value]),
    image_string_tail(Request, Opts, [Opt|Out]).
        
%%% --------------------------- %%%
%%% 	percept conversions    	%%%
%%% --------------------------- %%%
-spec pid2str(Pid :: pid()|pid_value()) ->  string().
pid2str(Pid) when is_pid(Pid) ->
    String = lists:flatten(io_lib:format("~p", [Pid])),
    lists:sublist(String, 2, erlang:length(String)-2);
pid2str({pid, {P1,P2, P3}}) when is_atom(P2)->
     integer_to_list(P1)++"."++atom_to_list(P2)++"."++integer_to_list(P3);
pid2str({pid, {P1, P2, P3}}) ->
    integer_to_list(P1)++"."++integer_to_list(P2)++"."++integer_to_list(P3).

    
-spec str_to_internal_pid(Str :: string()) ->  pid_value().
str_to_internal_pid(PidStr) ->
    [P1,P2,P3] = string:tokens(PidStr,"."),
    {pid, {list_to_integer(P1), 
           case hd(P2)==$* of
               true->list_to_atom(P2);
               _ -> list_to_integer(P2)
           end,
           list_to_integer(P3)}}.

string2mfa(String) ->
    
    Str=lists:sublist(String, 2, erlang:length(String)-2),
    case string:tokens(Str, ",") of 
        [M, F, A] ->
            F1=case hd(F) of 
                   39 ->lists:sublist(F,2,erlang:length(F)-2);
                   _ -> F
               end,
            {list_to_atom(M), list_to_atom(F1), list_to_integer(A)};
        [_F] ->
            list_to_atom(String)
    end.

%%% --------------------------- %%%
%%% 	get value       	%%%
%%% --------------------------- %%%
-spec get_option_value(Option :: string(), Options :: [{string(),any()}]) ->
                              {'error', any()} | boolean() | pid_value() | [pid_value()] | number().
get_option_value(Option, Options) ->
    case lists:keysearch(Option, 1, Options) of
        false -> get_default_option_value(Option);
        {value, {Option, _Value}} when Option == "fillcolor" -> true;
        {value, {Option, Value}} when Option == "pid" ->
            str_to_internal_pid(Value);
        {value, {Option, Value}} when Option == "pids" -> 
             [str_to_internal_pid(PidValue)|| PidValue <- string:tokens(Value,":")];
        {value, {Option, Value}} when Option =="mfa" ->
            string2mfa(Value);
        {value, {Option, Value}} when Option =="node1" -> 
            Value;
        {value, {Option, Value}} when Option =="node2" -> 
            Value;
        {value, {Option, Value}} when Option =="mod" ->
            Value;
        {value, {Option, Value}} -> get_number_value(Value);
        _ -> {error, undefined}
    end.

get_default_option_value(Option) ->
    case Option of 
    	"fillcolor" -> false;
	"range_min" -> float(0.0);
	"pids" -> [];
	"range_max" ->
            ?seconds((percept2_db:select({system, stop_ts})),
                     (percept2_db:select({system, start_ts})));
        "width" -> 800;
        "height" -> 400;
        "sends_min" -> 1;
        "size_min" -> 100;
        "callcounts_min" -> 1;
        "time_percent_min" -> 0;
        _ -> {error, {undefined_default_option, Option}}
    end.
-spec get_number_value(string()) -> number() | {'error', 'illegal_number'}.
get_number_value(Value) ->
    % Try float
    case string:to_float(Value) of
    	{error, no_float} ->
	    % Try integer
	    case string:to_integer(Value) of
		{error, _} -> {error, illegal_number};
		{Integer, _} -> Integer
	    end;
	{error, _} -> {error, illegal_number};
	{Float, _} -> Float
    end.

%%% --------------------------- %%%
%%% 	html prime functions	%%%
%%% --------------------------- %%%
-spec header()->string().
header() -> header([]).

-spec header(HeaderData::string()) -> string().
header(HeaderData) ->
    common_header(HeaderData)++ 
   "<body onLoad=\"load_image()\">
   <div id=\"header\"><a href=/index.html>percept2</a></div>\n".

%%TODO: refactor this out.
-spec inter_node_message_header() -> string().
inter_node_message_header() ->
    common_header([])++ 
   "<body onLoad=\"load_message_image()\">
   <div id=\"header\"><a href=/index.html>percept2</a></div>\n".

-spec concurrency_header() -> string().
concurrency_header() ->
    common_header([])++ 
   "<body onLoad=\"load_concurrency_image()\">
   <div id=\"header\"><a href=/index.html>percept2</a></div>\n".


common_header(HeaderData)->
    "Content-Type: text/html\r\n\r\n" ++
    "<html>
    <head>
    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=iso-8859-1\">
    <title>percept2</title>
    <link href=\"/css/percept2.css\" rel=\"stylesheet\" type=\"text/css\">
    <script type=\"text/javascript\" src=\"/javascript/percept_error_handler.js\"></script>
    <script type=\"text/javascript\" src=\"/javascript/percept_select_all.js\"></script>
    <script type=\"text/javascript\" src=\"/javascript/percept_area_select.js\"></script>
    <script type=\"text/javascript\" src=\"/javascript/sorttable.js\"></script>
    <script type=\"text/javascript\">
           function toggle(lnkid, tbid)
           {
           if(document.all)
		     {document.getElementById(tbid).style.display = document.getElementById(tbid).style.display == \"block\" ? \"none\" : \"block\";}
           else
		    {document.getElementById(tbid).style.display = document.getElementById(tbid).style.display == \"table\" ? \"none\" : \"table\";}
           document.getElementById(lnkid).value = document.getElementById(lnkid).value == \"[-]\" ? \"[+]\" : \"[-]\";
          }
     </script>
    " ++ HeaderData ++"
    </head>".
 
-spec footer() -> string().
footer() ->
    "</body>
     </html>\n". 

-spec menu(Input::string()) -> string().
menu(Input) ->
    Query = httpd:parse_query(Input),
    Min = get_option_value("range_min", Query),
    Max = get_option_value("range_max", Query),
    menu_1(Min, Max).

menu_1(Min, Max) ->
    "<div id=\"menu\" class=\"menu_tabs\">
	<ul>
     	<li><a href=/cgi-bin/percept2_html/databases_page>databases</a></li>
        <li><a href=/cgi-bin/percept2_html/visualise_sampling_data_page>visualise sampling data</a></li>
        <li><a href=/cgi-bin/percept2_html/inter_node_message_page?range_min=" ++
        term2html(Min) ++ "&range_max=" ++ term2html(Max) ++ ">inter-node messaging</a></li>
        <li><a href=/cgi-bin/percept2_html/active_funcs_page?range_min=" ++
        term2html(Min) ++ "&range_max=" ++ term2html(Max) ++ ">function activities</a></li>
        <li><a href=/cgi-bin/percept2_html/ports_page?range_min=" ++
        term2html(Min) ++ "&range_max=" ++ term2html(Max) ++ ">ports</a></li>
        <li><a href=/cgi-bin/percept2_html/process_tree_page?range_min=" ++
        term2html(Min) ++ "&range_max=" ++ term2html(Max) ++ ">processes</a></li>
      	<li><a href=/cgi-bin/percept2_html/overview_page>overview</a></li>
     </ul></div>\n".
   

%%% -------------------------------------%%%
%%%  check cached istory htmls; reuse or %%%
%%%  regenerate.                         %%%
%%%         	                         %%%
%%% ------------------------------------ %%%
-spec gen_content(list(), term(), string(), 
                  fun((_,_) -> nonempty_string())) ->
                         string()|{string(), string()}.
gen_content(Env,Input,CacheKey,Fun) ->
    case ets:info(history_html) of
        undefined -> 
            apply(Fun, [Env, Input]);
        _ -> 
            case ets:lookup(history_html, CacheKey) of 
                [{history_html, CacheKey, Content}] ->
                    Content;
                [] ->
                    Content= apply(Fun, [Env, Input]),
                    ets:insert(history_html, 
                               #history_html{id=CacheKey,
                                             content=Content}),
                    Content
            end
    end.
%%% --------------------------- %%%
%%% 	Errror messages     	%%%
%%% --------------------------- %%%
-spec error_msg(Error::string()) -> string().
error_msg(Error) ->
    "<table width=400>
	<tr height=5><td></td> <td></td></tr>
	<tr><td width=150 align=left><b>Error: </b></td> <td align=left>"++ Error ++ "</td></tr>
	<tr height=5><td></td> <td></td></tr>
     </table>\n".

blink_msg(Message) ->
    "<div style=\"text-align:center;\"><blink><center><h3><p>"
        ++ Message ++"</p></h3></center><blink></div>".

%% seconds2ts(Seconds, StartTs) -> TS
%% In:
%%	Seconds = float()
%%	StartTs = timestamp()
%% Out:
%%	TS = timestamp()
%% @spec seconds2ts(float(), StartTs::{integer(),integer(),integer()}) -> timestamp()
%% @doc Calculates a timestamp given a duration in seconds and a starting timestamp. 
seconds2ts(Seconds, {Ms, S, Us}) ->
    % Calculate mega seconds integer
    MsInteger = trunc(Seconds) div ?Million,

    % Calculate the reminder for seconds
    SInteger  = trunc(Seconds),

    % Calculate the reminder for micro seconds
    UsInteger = trunc((Seconds - SInteger) * ?Million),

    % Wrap overflows

    UsOut =  (UsInteger + Us) rem ?Million,

    SOut  =   ((SInteger + S) + (UsInteger + Us) div ?Million) rem ?Million,
    MsOut =  (MsInteger + Ms) + ((SInteger + S) + (UsInteger + Us) div ?Million) div ?Million,

    {MsOut, SOut, UsOut}.

group_by(N, TupleList) ->
    SortedTupleList = lists:keysort(N, lists:sort(TupleList)),
    group_by(N, SortedTupleList, []).

group_by(_N,[],Acc) -> Acc;
group_by(N,TupleList = [T| _Ts],Acc) ->
    E = element(N,T),
    {TupleList1,TupleList2} = 
	lists:partition(fun (T1) ->
				element(N,T1) == E
			end,
			TupleList),
    group_by(N,TupleList2,Acc ++ [TupleList1]).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                            %%
%%       For callgraph visualisaton.          %%
%%                                            %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec(procs_ports_count(pid(), list(), string()) -> 
             ok | {error, term()}).
procs_ports_count(SessionID, _Env, Input) ->
    Query    = httpd:parse_query(Input),
    RangeMin = percept2_html:get_option_value("range_min", Query),
    RangeMax = percept2_html:get_option_value("range_max", Query),
    Pids     = percept2_html:get_option_value("pids", Query),
    %% Width    = percept2_html:get_option_value("width", Query),
    %% Height   = percept2_html:get_option_value("height", Query),
    
     % seconds2ts
    StartTs  = percept2_db:select({system, start_ts}),
    TsMin    = percept2_html:seconds2ts(RangeMin, StartTs),
    TsMax    = percept2_html:seconds2ts(RangeMax, StartTs),
    
    % Convert Pids to id option list
    IDs      = [{id, ID} || ID <- Pids],
    TypeOpt = [{id, all}],
    Counts=case IDs/=[] of 
               true -> 
                   Options  = TypeOpt++[{ts_min, TsMin},{ts_max, TsMax} | IDs],
                   Acts     = percept2_db:select({activity, Options}),
                   percept2_analyzer:activities2count2(Acts, StartTs);
               false ->                
                   Options  = TypeOpt++ [{ts_min, TsMin},{ts_max, TsMax}],
                   [{?seconds(TS, StartTs), Procs, Ports}||
                       {TS, {Procs, Ports}}
                           <-percept2_db:select(
                               {activity,{runnable_counts, Options}})]
               
           end,
    Str= io_lib:format("~p", [Counts]),
    mod_esi:deliver(SessionID, Str).
   
-spec(callgraph(pid(), list(), string()) -> 
             ok | {error, term()}).
callgraph(SessionID, _Env, Input) ->
    Query = httpd:parse_query(Input),
    Pid = get_option_value("pid", Query),
    Str=percept2_callgraph:gen_callgraph_txt_data(Pid),
    mod_esi:deliver(SessionID, Str).
   
-spec(module_content(pid(), list(), string()) -> 
             ok | {error, term()}).
module_content(SessionID, _Env, Input) ->
    Query = httpd:parse_query(Input),
    ModName = get_option_value("mod", Query),
    Str =case percept2_callgraph:get_file(list_to_atom(ModName)) of 
             file_non_existing -> 
                 "";
             FileName ->
                 case file:read_file(FileName) of 
                     {ok, Binary} -> binary_to_list(Binary);
                     _ -> ""
                 end
         end,
    mod_esi:deliver(SessionID, Str).


   
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                       %%
%% For sample based profiling.                           %%
%%                                                       %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec(visualise_sampling_data_page(pid(), list(), string()) -> 
             ok | {error, term()}).
visualise_sampling_data_page(SessionID, Env, Input) ->
    try 
        Menu = menu_1(0,0),
        deliver_page(SessionID, Menu, sample_page_content())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

sample_page_content() ->
    "<div id=\"content\">
	<form name=load_sample_data_file method=post action=/cgi-bin/percept2_html/load_sample_data_page>
	<center>
        <br></br>
	<table>
           <tr> <td  align=left> Select sampling data type:</td> 
                <td  align=left> <select name=\"type\">
                     <option value=\"mem_info\">Memory Usage</option>
                     <option value=\"message_queue_len\">Message Queue Length</option>
                     <option value=\"run_queues\">Run-queue Lengths</option>
                      <option value=\"run_queue\">Sum Run-queue Length</option>
                     <option value=\"process_count\">Process Count</option>
                     <option value=\"scheduler_utilisation\">Scheduler Utilisation</option>
                     <option value=\"schedulers_online\">Schedulers Online</option>
                     </select></td> 
               </tr>
        </table>
        <br></br>
        <table>
           <tr><td align=left>Enter file to analyse:</td>
               <td><input type=file name=file size=60 /> </tr>
           <tr><td align=left>Copy and paste path to file here:</td> 
               <td align=left><input type=text name=path size=75/> </td></tr>
           <tr><td><input type=submit value=\"Generate Graph\" /> </td></tr>
        </table>
  	</center>
	</form>
	</div>". 

-spec(load_sample_data_page(pid(), list(), string()) -> ok | {error, term()}).
load_sample_data_page(SessionID, Env, Input) ->
    try
        mod_esi:deliver(SessionID, header()),
        mod_esi:deliver(SessionID, sample_page_content(SessionID, Env, Input)),
        mod_esi:deliver(SessionID, footer())
    catch
        _E1:_E2 ->
            error_page(SessionID, Env, Input)
    end.

sample_page_content(_SessionId, _Env, Input) ->
    Query = httpd:parse_query(Input),
    {_,{_,Type}} = lists:keysearch("type", 1, Query),
    {_,{_,Path}} = lists:keysearch("path", 1, Query),
    {_,{_,File}} = lists:keysearch("file", 1, Query),
    Filename = filename:join(Path, File),
    case file:read_file_info(Filename) of
	{ok, _} ->
            case check_file_content(Filename, Type) of 
                {ok, Cols} -> 
                    analyze_sample_data(Filename, Type, Cols);
                {error, Error} ->
                    error_msg(Error)
            end;
        {error, Reason} ->
	    error_msg("Data file error:" ++ term2html(Reason))
    end.


check_file_content(Filename, Type) ->
    case  file:open(Filename, [raw, read]) of 
        {error, _} ->
            {error, "Percept2 failed to open the data file."};
        {ok, FileDev} ->
            case file:read_line(FileDev) of 
                {ok, Line} ->
                    case lists:prefix("#"++Type, Line)  of 
                        true ->
                            case file:read_line(FileDev) of 
                                {ok, Line1} ->
                                    Cols=string:tokens(Line1, "\ "),
                                    {ok, length(Cols)-1};
                                {error, _} ->
                                    {error, "Percept2 failed to read from data file."}
                            end;
                        false ->
                          {error, "The type of data selected, "++ Type ++ 
                               ",does not match the data file content."}
                    end;
                {error, _} ->
                    {error, "Percept2 failed to read from data file."}
            end
    end.

analyze_sample_data(DataFileName, Type, Cols) ->
    SvgDir = percept2:get_svg_alias_dir(),
    ImgFileName=Type++".svg",
    ImgFullFilePath = filename:join([SvgDir, ImgFileName]),
    ScriptFileName=filename:join(
                     [code:lib_dir(percept2), "gplt", 
                      Type++".plt"]),
    Content = "<div style=\"text-align:center; align:center; width=1000; bgcolor=#FFFFFF\">" ++
        "<object data=\"/svgs/"++ImgFileName++"\" "++ "type=\"image/svg+xml\"" ++
        " overflow=\"visible\"  scrolling=\"yes\" "++
        "></object>"++
        "</div>",
    GenImgRes=gnuplot_gen_graph(DataFileName, ScriptFileName, 
                                Type, Cols,ImgFullFilePath),
    process_gen_graph_img_result(Content, GenImgRes).
   

gnuplot_gen_graph(DataFileName, ScriptFileName, Type, Cols, OutputFileName) ->
    case os:find_executable("gnuplot") of
        false ->
            gnuplot_not_found;
        _ ->
            Cmd = compose_gnuplot_cmd(DataFileName, Type, Cols, 
                                      ScriptFileName,OutputFileName),
            _Res=os:cmd(Cmd),
            case filelib:is_regular(OutputFileName) of
                true ->
                    case file:read_file_info(OutputFileName) of
                        {ok, FileInfo} ->
                            case FileInfo#file_info.size > 0 of
                                true ->
                                    ok;
                                false ->
                                    {gnuplot_failed, Cmd}
                            end;
                        _ ->
                            {gnuplot_failed, Cmd}
                    end;
               false ->
                   {gnuplot_failed, Cmd}
            end
    end.

compose_gnuplot_cmd(DataFile, "run_queues", Cols, ScriptFile, OutputFile) ->
    compose_gnuplot_cmd_1(DataFile, Cols, ScriptFile, OutputFile);
compose_gnuplot_cmd(DataFile, "scheduler_utilisation", Cols, ScriptFile, OutputFile) ->
    compose_gnuplot_cmd_1(DataFile, Cols, ScriptFile, OutputFile);
compose_gnuplot_cmd(DataFile, _Type, _Cols, ScriptFile, OutputFile) ->
    "gnuplot -e \"filename='"++DataFile++"'\" " ++ 
        ScriptFile ++ " > " ++ OutputFile.

compose_gnuplot_cmd_1(DataFile, Cols, ScriptFile, OutputFile) ->
    "gnuplot -e \"n=" ++ integer_to_list(Cols) ++ "; " ++
          "filename='" ++ DataFile ++ "'\" " ++
              ScriptFile ++ " > " ++ OutputFile.

is_dummy_pid({pid, {_, P2, _}}) ->
    is_atom(P2);
is_dummy_pid(_) -> false.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%5
%% only for experiments.

get_live_data(SessionID, _Env, _Input) ->
    live_data_proc ! {get_next, self()},
    receive
        {live_data_proc, Data} ->
            mod_esi:deliver(SessionID, Data)
    end.

get_live_data()->
    live_data_proc ! {get_next, self()},
    receive
        {live_data_proc, Data} ->
            Data
    end.
start_live_data_proc(File) ->
    spawn(?MODULE, init_live_data_proc, [File]).

init_live_data_proc(File) ->
    register(live_data_proc, self()),
    {ok, FD} =file:open(File, [read]),
    live_data_loop(FD).

stop_live_data_proc() ->
    live_data_proc!stop.

live_data_loop(FD)->
    receive
        {get_next, Pid} ->
            {ok, Data} = file:read_line(FD),
            Pid!{live_data_proc, Data},
            live_data_loop(FD);
        stop ->
            ok
    end.

%%percept2:start_webserver(8888).
%%percept2_html:start_live_data_proc("rq_migration.txt").
%% http://localhost:8888/cgi-bin/percept2_html/get_live_data
%%  {{pid,{0,1578,0}},[{1.129399,13},{1.130775,12}]}. 
%% http://localhost:8888/cgi-bin/percept2_html/get_live_data
%%  {{pid,{0,2743,0}},[{13.596175,1}]}. 
%%  ....
%%  ....
%%percept2_html:stop_live_data_proc().
%%percept2:stop_webserver().
