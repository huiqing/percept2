-module(percept2_dot).

-export([gen_callgraph_img/5,
         gen_process_tree_img/1,
         gen_process_comm_img/4,
         gen_callgraph_slice_img/4]).

-export([gen_process_tree_img_1/2]).

-compile(export_all).

-include("../include/percept2.hrl").
-include_lib("kernel/include/file.hrl").


%%% --------------------------------%%%
%%% 	Callgraph Image generation  %%%
%%% --------------------------------%%%
-spec(gen_callgraph_img(Pid::pid_value(), DestDir::file:filename(),
                        ImgFileBaseName::file:filename(),
                        MinCallCount::integer(), MinTimePercent::integer()) 
      -> ok|no_image|dot_not_found|{gen_svg_failed, Cmd::string()}).
gen_callgraph_img(Pid, DestDir, ImgFileBaseName, MinCallCount, MinTimePercent) ->
    Res=ets:select(fun_calltree, 
                   [{#fun_calltree{id = {Pid, '_','_'}, _='_'},
                     [],
                     ['$_']
                    }]),
    case Res of 
        [] -> no_image;
        [Tree] -> 
            gen_callgraph_img_1(Pid, Tree, DestDir, ImgFileBaseName, 
                                MinCallCount, MinTimePercent)
    end.
   
gen_callgraph_img_1(Pid, CallTree, DestDir, ImgFileBaseName, 
                    MinCallCount, MinTimePercent) ->
    DotFileName = ImgFileBaseName++".dot",
    SvgFileName =gen_svg_file_name(ImgFileBaseName, DestDir),
    fun_callgraph_to_dot(Pid, CallTree,DotFileName, MinCallCount, MinTimePercent),
    dot_to_svg(DotFileName, SvgFileName).

gen_svg_file_name(BaseName, DestDir) ->
    filename:join([DestDir, BaseName++".svg"]).
    
fun_callgraph_to_dot(Pid, CallTree, DotFileName, MinCallCount, MinTimePercent) ->
    Edges=gen_callgraph_edges(Pid, CallTree, MinCallCount, MinTimePercent),
    MG = digraph:new(),
    digraph_add_edges(Edges, [], MG),
    to_dot(MG,DotFileName, Pid),
    digraph:delete(MG).

get_proc_life_time(Pid)->
    SystemStartTS = percept2_db:select({system, start_ts}),
    SystemStopTS = percept2_db:select({system, stop_ts}),
    [PidInfo] = percept2_db:select({information, Pid}),
    ProcStartTs = case PidInfo#information.start of 
                      undefined -> SystemStartTS;
                      StartTs -> StartTs
                  end,
    ProcStopTs = case PidInfo#information.stop of 
                     undefined -> 
                         SystemStopTS;
                     StopTs -> StopTs
                 end,
    {ProcStartTs, ProcStopTs}.


gen_callgraph_edges(Pid, CallTree, MinCallCount, MinTimePercent) ->
    {ProcStartTs, ProcStopTs} = get_proc_life_time(Pid),
    if CallTree#fun_calltree.cnt==0 ->
            CallTree1=CallTree#fun_calltree{cnt=1, end_ts=ProcStopTs, 
                                            acc_time=timer:now_diff(
                                                       ProcStopTs, CallTree#fun_calltree.start_ts)},
            gen_callgraph_edges_1({ProcStartTs, ProcStopTs}, CallTree1, MinCallCount, MinTimePercent);
       true ->
             gen_callgraph_edges_1({ProcStartTs, ProcStopTs}, CallTree, MinCallCount, MinTimePercent)
    end.

gen_callgraph_edges_1({ProcStartTs, ProcStopTs},CallTree, MinCallCount, MinTimePercent) ->
    {_, CurFunc, _} = CallTree#fun_calltree.id,
    ProcTime = timer:now_diff(ProcStopTs, ProcStartTs),
    CurFuncTime = CallTree#fun_calltree.acc_time, 
    CurFuncEndTs = CallTree#fun_calltree.end_ts,
    ChildrenCallTrees = CallTree#fun_calltree.called,
    Edges = lists:foldl(
              fun(Tree, Acc) ->
                      {_, ToFunc, _} = Tree#fun_calltree.id,
                      ToFuncTime = Tree#fun_calltree.acc_time,
                      CallCount= Tree#fun_calltree.cnt,
                      ToFuncEndTs = Tree#fun_calltree.end_ts,
                      CurTimePercent = CurFuncTime/ProcTime,
                      ToTimePercent = ToFuncTime/ProcTime,
                      case CallCount >= MinCallCount andalso 
                           CurTimePercent >= MinTimePercent/100 andalso
                           ToTimePercent >= MinTimePercent/100 of 
                          true ->
                              NewEdge = {{CurFunc,CurTimePercent, CurFuncEndTs},
                                         {ToFunc,ToTimePercent, ToFuncEndTs}, 
                                         CallCount},
                              [[NewEdge|gen_callgraph_edges_1(
                                          {ProcStartTs, ProcStopTs}, 
                                          Tree, MinCallCount, MinTimePercent)]
                               |Acc];
                          false -> Acc
                      end
              end, [], ChildrenCallTrees),
    case CallTree#fun_calltree.rec_cnt of 
        0 ->Edges;
        N -> [{{CurFunc,CurFuncTime/ProcTime, CurFuncEndTs}, 
               {CurFunc,CurFuncTime/ProcTime, CurFuncEndTs}, N}|Edges]
    end.

%%depth first traveral.
digraph_add_edges([], NodeIndex, _MG)-> 
    NodeIndex;
digraph_add_edges(Edge={_From, _To, _CNT}, NodeIndex, MG) ->
    digraph_add_edge(Edge, NodeIndex, MG);
digraph_add_edges([Edge={_From, _To, _CNT}|Children], NodeIndex, MG) ->
    NodeIndex1=digraph_add_edge(Edge, NodeIndex, MG),
    lists:foldl(fun(Tree, IndexAcc) ->
                        digraph_add_edges(Tree, IndexAcc, MG)
                end, NodeIndex1, Children);
digraph_add_edges(Trees=[Tree|_Ts], NodeIndex, MG) when is_list(Tree)->
    lists:foldl(fun(T, IndexAcc) ->
                        digraph_add_edges(T, IndexAcc, MG)
                end, NodeIndex, Trees).
        

digraph_add_edge({{From, FromTime, FromEndTs}, {To, ToTime, ToEndTs}, CNT}, IndexTab, MG) ->
    {From1, IndexTab1}=
        case digraph:vertex(MG, {From,0}) of
            false ->
                digraph:add_vertex(MG, {From, 0},{label, FromTime}),
                {{From,0}, [{{From,FromEndTs},0}|IndexTab]};
            _ ->
                case lists:keyfind({From, FromEndTs},1, IndexTab) of 
                    {_, Index} ->
                        {{From, Index},IndexTab};
                    false ->
                        Es = length([true||{{From1, _}, _}<-IndexTab,From1==From]),
                        digraph:add_vertex(MG, {From, Es+1}, {label, FromTime}),
                        {{From, Es+1}, 
                         [{{From, FromEndTs}, Es+1}|IndexTab]}
                end
        end,
    {To1, IndexTab2}=
        if To==From ->
                {From1,IndexTab1};
           true ->
                case digraph:vertex(MG, {To,0}) of
                    false ->
                        digraph:add_vertex(MG, {To,0}, {label,ToTime}),
                        {{To,0}, [{{To, ToEndTs},0}|IndexTab1]};
                    _ ->  
                        case  lists:keyfind({To, ToEndTs}, 1,IndexTab1) of 
                            false ->
                                Elems = length([true||{{To1, _}, _}<-IndexTab1,To1==To]),
                                digraph:add_vertex(MG, {To, Elems+1}, {label, ToTime}),
                                {{To, Elems+1}, 
                                 [{{To, ToEndTs}, Elems+1}|IndexTab1]};
                            {_, Index1} ->
                                {{To, Index1}, IndexTab}
                        end
                end
        end,
    digraph:add_edge(MG, From1, To1, CNT),  
    IndexTab2.

to_dot(MG, File, Pid) ->
    Edges = [digraph:edge(MG, X) || X <- digraph:edges(MG)],
    EdgeList=[{digraph:vertex(MG,X), digraph:vertex(MG, Y), Label} 
              || {_, X, Y, Label} <- Edges],
    EdgeList1 = combine_edges(lists:keysort(1,EdgeList)),
    edge_list_to_dot(Pid, EdgeList1, File, "CallGraph").

combine_edges(Edges) ->	
    combine_edges(Edges, []).

combine_edges([], Acc) ->	
    Acc;
combine_edges([{X,Y,Label}], Acc) ->
    [{X, Y, Label}|Acc];
combine_edges(Ts=[{From, _To, _Label}|_], Acc) ->
    {Es1, Es2} = lists:partition(fun({F, _T, _L})-> F==From end, Ts),
    Es3=combine_edges_1(Es1),
    combine_edges(Es2, Es3++Acc).

combine_edges_1(Es) ->
   combine_edges_2(Es,[]).
   
combine_edges_2([], Acc) ->
    lists:reverse(Acc);
combine_edges_2([E],Acc) ->
    [E|Acc];
combine_edges_2(Ts=[{From, _To={{X, C}, _L1}, _L2}|_T], Acc) ->
    {T1, T2} = lists:partition(fun({_, {{X1, _}, _},_}) ->
                                   X==X1 end, Ts),
    NodeLabel=lists:sum([Label||{_, {_, {label, Label}},_}<-T1]),
    EdgeLabel=lists:sum([Label||{_, _, Label}<-T1]),
    combine_edges_2(T2, [{From, {{X, C}, {label, NodeLabel}}, EdgeLabel}|Acc]).


edge_list_to_dot(Pid, Edges, OutFileName, GraphName) ->
    {NodeList1, NodeList2, _} = lists:unzip3(Edges),
    NodeList = NodeList1 ++ NodeList2,
    NodeSet = ordsets:from_list(NodeList),
    Start = ["digraph ",GraphName ," {"],
    VertexList = [begin 
                      Label = format_vertex_label(V),
                      MFAValue= case V of  
                                    {{{M, F, A}, _}, _} ->
                                        lists:flatten(
                                          io_lib:format("{~p,~p,~p}", 
                                                        [M, F, A]));
                                    {{F, _}, _}  when is_atom(F) ->
                                        atom_to_list(F)
                                end,
                      
                      URL ="/cgi-bin/percept2_html/function_info_page_without_menu?pid="++pid2str(Pid)++
                          "&mfa=" ++ MFAValue,
                      format_node_with_label_and_url_1(
                        V, fun format_vertex/1,  Label, URL)
                  end   ||V <- NodeSet],
    End = ["graph [", GraphName, "=", GraphName, "]}"],
    EdgeList = [format_edge(X, Y, Cnt) || {X,Y,Cnt} <- Edges],
    String = [Start, VertexList, EdgeList, End],
    ok = file:write_file(OutFileName, list_to_binary(String)).


gen_callgraph_slice_img(Pid, Min, Max, DestDir) ->
    Res=ets:select(fun_calltree, 
                   [{#fun_calltree{id = {Pid, '_','_'}, _='_'},
                     [],
                     ['$_']
                    }]),
    case Res of 
        [] -> 
            no_image;
        [Tree] -> 
            gen_callgraph_slice_img_1(Pid, Tree, Min, Max, DestDir)
    end.

gen_callgraph_slice_img_1(Pid={pid, {P1, P2, P3}}, CallTree, Min, Max, DestDir) ->
    PidStr= integer_to_list(P1)++"." ++integer_to_list(P2)++
        "."++integer_to_list(P3),
    MinTsStr=lists:flatten(io_lib:format("~.4f", [Min])),
    MaxTsStr=lists:flatten(io_lib:format("~.4f", [Max])),
    BaseName = "callgraph"++PidStr++MinTsStr++"_"++MaxTsStr,
    DotFileName = BaseName++".dot",
    SvgFileName = gen_svg_file_name(BaseName, DestDir),
    fun_callgraph_slice_to_dot(Pid, CallTree, Min, Max, DotFileName),
    dot_to_svg(DotFileName, SvgFileName).

fun_callgraph_slice_to_dot(Pid, CallTree, Min, Max, DotFileName) ->
    StartTs = percept2_db:select({system, start_ts}),
    TsMin   = percept2_html:seconds2ts(Min, StartTs),
    TsMax   = percept2_html:seconds2ts(Max, StartTs),
    {ProcStartTs, ProcStopTs} = get_proc_life_time(Pid),
    ProcTime = timer:now_diff(ProcStopTs, ProcStartTs),
    Edges=gen_callgraph_slice_edges(CallTree,TsMin, TsMax, ProcTime),
    MG = digraph:new(),
    digraph_add_edges(Edges, [], MG),
    to_dot(MG,DotFileName, Pid),
    digraph:delete(MG).

gen_callgraph_slice_edges(CallTree, Min, Max,ProcTime) ->
    {_, CurFunc, _} = CallTree#fun_calltree.id,
    CurFuncTime = CallTree#fun_calltree.acc_time, 
    StartTs = CallTree#fun_calltree.start_ts,
    EndTs = CallTree#fun_calltree.end_ts,
    case StartTs < Max andalso (EndTs==undefined orelse EndTs>Min) of 
        true ->
            ChildrenCallTrees = CallTree#fun_calltree.called,
            lists:foldl(fun(Tree, Acc) ->
                                {_, ToFunc, _} = Tree#fun_calltree.id,
                                ToFuncTime = Tree#fun_calltree.acc_time,
                                StartTs1 = Tree#fun_calltree.start_ts,
                                EndTs1 = Tree#fun_calltree.end_ts,
                                case  StartTs1 < Max andalso (EndTs1==undefined orelse EndTs1>Min) of
                                    true ->
                                        NewEdge = {{CurFunc, CurFuncTime/ProcTime}, 
                                                   {ToFunc,ToFuncTime/ProcTime}, 
                                                   Tree#fun_calltree.cnt},
                                        [[NewEdge|gen_callgraph_slice_edges(Tree, Min, Max, ProcTime)]|Acc];
                                    false -> Acc
                                end
                        end, [], ChildrenCallTrees);
        false ->
            []
    end.
            

format_node_with_label_and_url(V, Fun, Label, URL) ->
    String = Fun(V),
    {Width, Heigth} = calc_dim(String),
    W = (Width div 7 + 1) * 0.55,
    H = Heigth * 0.4,
    SL = io_lib:format("~f", [W]),
    SH = io_lib:format("~f", [H]),
    [String, " [URL=\"", URL, "\""
     " label=\"", Label,"\"",
     " target=\"", "_graphviz","\"",
     " width=", SL, " heigth=", SH, " ", "", "];\n"].
 
format_node_with_label_and_url_1(V, Fun, Label, URL) ->
    String = Fun(V),
    {Width, Heigth} = calc_dim(String),
    W = (Width div 7 + 1) * 0.55,
    H = Heigth * 0.4,
    SL = io_lib:format("~f", [W]),
    SH = io_lib:format("~f", [H]),
    ["\"", String, "\"",  " [URL=\"", URL, "\""
     " label=\"", Label,"\"",
     " target=\"", "_graphviz","\"",
     " width=", SL, " heigth=", SH, " ", "", "];\n"].
            
format_node(V, Fun) ->
    String = Fun(V),
    {Width, Heigth} = calc_dim(String),
    W = (Width div 7 + 1) * 0.55,
    H = Heigth * 0.4,
    SL = io_lib:format("~f", [W]),
    SH = io_lib:format("~f", [H]),
    [String, " [width=", 
     SL, " heigth=", SH, " ", "", "];\n"].
       
       
format_vertex_label({V, {label, Label}}) when Label>=0->
    format_vertex_no_count(V) ++ 
        io_lib:format("(~.10B%)", [round(Label*100)]);
format_vertex_label({V, {label, _Label}}) ->
    format_vertex(V);
format_vertex_label(V) ->
    format_vertex(V).
 
format_vertex({V, {label, _Label}}) ->
    format_vertex(V);
format_vertex(V) when is_atom(V)->
    atom_to_list(V);
format_vertex({M,F,A})when is_atom(M) ->
    io_lib:format("~p:~p/~p", [M,F,A]);
format_vertex({V,0}) when is_atom(V) ->
    atom_to_list(V);
format_vertex({V,C}) when is_atom(V)->
    io_lib:format(atom_to_list(V)++"(~p)",[C]);
format_vertex({{M,F,A},0}) ->
    io_lib:format("~p:~p/~p", [M,F,A]);
format_vertex({{M,F,A},C}) ->
    io_lib:format("~p:~p/~p(~p)", [M,F,A, C]).


format_vertex_no_count({V,_C}) when is_atom(V)->
    atom_to_list(V);
format_vertex_no_count({{M,F,A},_C}) ->
    io_lib:format("~p:~p/~p", [M,F,A]).

format_edge(V1, V2, Label) ->
    String = ["\"",format_vertex(V1),"\"", " -> ",
	      "\"", format_vertex(V2), "\""],
    [String, " [", "label=", "\"", format_label(Label), "\"",
     " fontsize=14 fontname=\"Verdana\"", "];\n"].
                       

%%% ------------------------------------%%%
%%% 	Process tree image generation   %%%
%%% ------------------------------------%%%
gen_process_tree_img(DestDir) ->
    Pid=spawn_link(?MODULE, gen_process_tree_img_1, [self(), DestDir]),
    receive
        {Pid, done, Result} ->
            Result
    end.
    
gen_process_tree_img_1(Parent, DestDir)->
    CompressedTrees=percept2_db:gen_compressed_process_tree(),
    CleanPid =  percept2_db:select({system, nodes})==1,
    Res=gen_process_tree_img(CompressedTrees, CleanPid, DestDir),
    Parent ! {self(), done, Res}.

gen_process_tree_img([], _, _) ->
    no_image;
gen_process_tree_img(ProcessTrees, CleanPid, DestDir) ->
    BaseName = "processtree",
    DotFileName = BaseName++".dot",
    SvgFileName = gen_svg_file_name(BaseName, DestDir),
    ok=process_tree_to_dot(ProcessTrees,DotFileName, CleanPid),
    dot_to_svg(DotFileName, SvgFileName).

dot_to_svg(DotFileName, SvgFileName) ->
    case os:find_executable("dot") of
        false ->
            dot_not_found;
        _ ->
            Cmd ="dot -Tsvg " ++ filename:absname(DotFileName) ++ " > " ++ SvgFileName,
            _Res=os:cmd(Cmd),
             case filelib:is_regular(SvgFileName) of
                true ->
                     case file:read_file_info(SvgFileName) of 
                         {ok, FileInfo} ->
                             case FileInfo#file_info.size>0 of
                                 true -> 
                                     file:delete(DotFileName),
                                     ok;
                                 false ->
                                     file:delete(SvgFileName),
                                     {gen_svg_failed, Cmd}
                             end;
                         _ -> 
                             file:delete(SvgFileName),
                             {gen_svg_failed, Cmd}
                     end;
                 false ->
                     {gen_svg_failed, Cmd}
            end
    end.

            
process_tree_to_dot(ProcessTrees, DotFileName, CleanPid) ->
    {Nodes, Edges} = gen_process_tree_nodes_edges(ProcessTrees),
    MG = digraph:new(),
    digraph_add_edges_to_process_tree({Nodes, Edges}, MG),
    proc_to_dot(MG, DotFileName, "ProcessTree", CleanPid),
    digraph:delete(MG),
    ok.

gen_process_tree_nodes_edges(Trees) ->
    Res = percept2_utils:pmap(
            fun(Tree) ->
                    gen_process_tree_nodes_edges_1(Tree) 
            end,  Trees),
    {Nodes, Edges}=lists:unzip(Res),
    {sets:to_list(sets:from_list(lists:append(Nodes))), 
     lists:append(Edges)}.

gen_process_tree_nodes_edges_1({Parent, []}) ->
    Parent1={Parent#information.id, Parent#information.name,
             clean_entry(Parent#information.entry)},
    {[Parent1], []};
gen_process_tree_nodes_edges_1({Parent, Children}) -> 
    Parent1={Parent#information.id, Parent#information.name,
             clean_entry(Parent#information.entry)},
    Nodes = [{C#information.id, C#information.name,
              clean_entry(C#information.entry)}||{C, _} <- Children],
    Edges = [{Parent#information.id, element(1, N), ""}||N<-Nodes],
    {Nodes1, Edges1}=gen_process_tree_nodes_edges(Children),
    {[Parent1|Nodes]++Nodes1, Edges++Edges1}.

clean_entry({M, F, Args}) when is_list(Args) ->
    {M, F, length(Args)};
clean_entry(Entry) -> Entry.

digraph_add_edges_to_process_tree({Nodes, Edges}, MG) ->
    %% This cannot be parallelised because of side effects.
    [digraph:add_vertex(MG, Pid, {Pid, Name, Entry})||{Pid, Name, Entry}<-Nodes],
    [digraph_add_edge_1(MG, From, To, Label)||{From, To, Label}<-Edges].

%% a function with side-effect.
digraph_add_edge_1(MG, From, To, Label) ->
    digraph:add_edge(MG, From, To, Label).

format_process_node(RegName, _) when is_atom(RegName) ->
    format_node(RegName, fun atom_to_list/1);
format_process_node(Pid={pid, {_P1, _P2, _P3}}, CleanPid) ->
    case ets:lookup(pdb_info,Pid) of 
        [Info] ->
            Name =Info#information.name,
            Entry = Info#information.entry,
            format_process_node({Pid, Name, Entry}, CleanPid);
        [] ->
            format_process_node({Pid, undefined, undefined}, CleanPid)
    end;
format_process_node(_V={Pid={pid, {_P1, P2, P3}}, Name, Entry}, CleanPid) ->
    Pid1 = case CleanPid of 
               true -> {pid, {0, P2, P3}};
               _ -> Pid
           end,
    PidStr =  "<" ++ pid2str(Pid1) ++ ">",
    URL ="/cgi-bin/percept2_html/process_info_page_without_menu?pid="++pid2str(Pid),
    Label =  format_process_vertex({PidStr, Name, Entry}),
    format_node_with_label_and_url(PidStr, fun format_process_vertex/1, Label, URL).
           
format_process_vertex({PidStr, Name, Entry}) ->
    lists:flatten(io_lib:format("~s; ~p;\\n", [PidStr, Name])) ++
        format_entry(Entry);
format_process_vertex(Other)  ->
    io_lib:format("~p", [Other]).

format_process_tree_edge(Pid1, Pid2,Label, CleanPid) ->
    Pid1Str= format_proc_node(Pid1, CleanPid),
    Pid2Str=format_proc_node(Pid2, CleanPid),
    String = [format_process_vertex(Pid1Str), " -> ",
	      format_process_vertex(Pid2Str)],
    [String, " [", "label=", "\"", format_label(Label),
     "\"",  " fontsize=14 fontname=\"Verdana\"", "];\n"].

format_proc_node(Pid, _) when is_atom(Pid) ->
    atom_to_list(Pid);
format_proc_node(Pid, CleanPid) ->
    case CleanPid of
        true ->
            {pid, {_, P2, P3}}=Pid,
            "<" ++pid2str({pid, {0, P2, P3}})++">";
        _ -> 
            "<"++pid2str(Pid)++">"
    end.


format_entry(Entry) when is_atom(Entry)->
    atom_to_list(Entry);
format_entry({M, F, A}) ->
    MStr = atom_to_list(M),
    FStr = atom_to_list(F),
    case length(MStr)>25 orelse length(FStr)>25 of 
        true ->
            "{"++MStr++",\\n"++FStr++","
                ++integer_to_list(A)++"}";
        false ->
            "{"++MStr++","++FStr++","
                ++integer_to_list(A)++"}"
    end.

calc_dim(String) ->
  calc_dim(String, 1, 0, 0).

calc_dim("\\n" ++ T, H, TmpW, MaxW) ->
    calc_dim(T, H + 1, 0, lists:max([TmpW, MaxW]));
calc_dim([_| T], H, TmpW, MaxW) ->
    calc_dim(T, H, TmpW+1, MaxW);
calc_dim([], H, TmpW, MaxW) ->
    {lists:max([TmpW, MaxW]), H}.

format_label([]) -> "";
format_label(Label) ->
    io_lib:format("~p", [Label]).

-spec pid2str(Pid :: pid()|pid_value()) ->  string().
pid2str({pid, {P1,P2, P3}}) when is_atom(P2)->
     integer_to_list(P1)++"."++atom_to_list(P2)++"."++integer_to_list(P3);
pid2str({pid, {P1, P2, P3}}) ->
    integer_to_list(P1)++"."++integer_to_list(P2)++"."++integer_to_list(P3).


%%% --------------------------------------------%%%
%%% 	process communication image generation. %%%
%%% --------------------------------------------%%%

-spec(gen_process_comm_img(DestDir::file:filename(),
                          ImgFileBaseName::string(),
                          MinSends::non_neg_integer(),
                          MinSize::non_neg_integer()) 
      -> ok|no_image|dot_not_found|{gen_svg_failed, Cmd::string()}).
gen_process_comm_img(DestDir, ImgFileBaseName, MinSends,MinSize) ->
    case ets:info(inter_proc,size) of 
        0 -> 
            no_image;
        _ ->
            Tab=ets:new(tmp_inter_proc_tab, [named_table, protected, set]),
            ets:foldl(fun process_a_send/2, Tab, inter_proc),
            DotFileName = ImgFileBaseName++".dot",
            SvgFileName =gen_svg_file_name(ImgFileBaseName, DestDir),
            proc_comm_to_dot(Tab,DotFileName, MinSends, MinSize),
            ets:delete(Tab),
            dot_to_svg(DotFileName, SvgFileName)
    end.

process_a_send('$end_of_table', Tab) ->
    Tab;    
process_a_send(Send, Tab) ->
    From = element(3, Send#inter_proc.timed_from),
    To=element(2, Send#inter_proc.to),
    MsgSize = Send#inter_proc.msg_size,
    if is_atom(To) ->
            case ets:lookup(pdb_system, {regname, To}) of 
                [] ->
                    Tab;
                [{{regname, To}, Pid}] ->
                            process_a_send(From, Pid, MsgSize, Tab)
            end;
       true -> process_a_send(From, To, MsgSize, Tab)
    end.

process_a_send(FromPid, ToPid, MsgSize, Tab) ->
    case ets:lookup(Tab, {FromPid, ToPid}) of 
        [] ->
            ets:insert(Tab, {{FromPid, ToPid}, {1, MsgSize}});
        [I] ->
            {Key, {No,Size}} = I,
            ets:update_element(Tab,Key, {2, {No+1, Size+MsgSize}})
    end,
    Tab.

proc_comm_to_dot(Tab, DotFileName, MinSends, MinSize) ->
    Edges = gen_proc_comm_edges(Tab, MinSends, MinSize),
    MG = digraph:new(),
    proc_comm_add_edges(Edges, MG),
    proc_to_dot(MG,DotFileName,"proc_comm", true),
    digraph:delete(MG).

gen_proc_comm_edges(Tab, MinSends, MinSize) ->
    ets:foldl(fun(Elem, Acc) ->
                      case Elem of 
                          '$end_of_table' -> Acc;
                          {{From, To}, {Times, TotalSize}} ->
                              AvgSize = TotalSize div Times, 
                              case Times >= MinSends andalso AvgSize >= MinSize of 
                                  true ->
                                      NewEdge = {From,To,{Times, AvgSize}},
                                      [NewEdge|Acc];
                                  false ->
                                      Acc
                              end
                      end                                         
              end, [], Tab).

proc_comm_add_edges(Edges, MG)->
    [proc_comm_add_an_edge(MG, E)||E<-Edges].

proc_comm_add_an_edge(MG, _E={From, To, Label={_Times, _Size}}) ->
    case digraph:vertex(MG,From) of 
        false ->
            digraph:add_vertex(MG, From);
        _ -> ok
    end,
    case digraph:vertex(MG, To) of 
        false ->
            digraph:add_vertex(MG, To);
        _-> ok
    end,
    digraph:add_edge(MG, From, To, Label).

proc_to_dot(MG,OutFileName, GraphName,CleanPid) ->
    Edges =[digraph:edge(MG, X) || X <- digraph:edges(MG)],
    Nodes = digraph:vertices(MG),
    Start = ["digraph ",GraphName ," {"],
    VertexList = [format_process_node(N,CleanPid) ||N <- Nodes],
    End = ["graph [", GraphName, "=", GraphName, "]}"],
    EdgeList = [format_process_tree_edge(X, Y, Label, CleanPid) ||{_, X, Y, Label} <- Edges],
    String = [Start, VertexList, EdgeList, End],
    ok = file:write_file(OutFileName, list_to_binary(String)).
 
   
