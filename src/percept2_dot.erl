-module(percept2_dot).

-export([gen_callgraph_img/1,
         gen_process_tree_img/0]).

-export([gen_process_tree_img_1/1]).

-include("../include/percept2.hrl").
          
%%% --------------------------------%%%
%%% 	Callgraph Image generation  %%%
%%% --------------------------------%%%
-spec(gen_callgraph_img(Pid::pid_value()) -> ok|no_image).
gen_callgraph_img(Pid) ->
    Res=ets:select(fun_calltree, 
                      [{#fun_calltree{id = {Pid, '_','_'}, _='_'},
                        [],
                        ['$_']
                       }]),
    case Res of 
        [] -> no_image;
        [Tree] -> 
            gen_callgraph_img_1(Pid, Tree)
    end.
   
gen_callgraph_img_1({pid, {P1, P2, P3}}, CallTree) ->
    PidStr= integer_to_list(P1)++"." ++integer_to_list(P2)++
                        "."++integer_to_list(P3),
    BaseName = "callgraph"++PidStr,
    DotFileName = BaseName++".dot",
    SvgFileName = filename:join(
                    [code:priv_dir(percept2), "server_root",
                     "images", BaseName++".svg"]),
    fun_callgraph_to_dot(CallTree,DotFileName),
    os:cmd("dot -Tsvg " ++ DotFileName ++ " > " ++ SvgFileName),
    file:delete(DotFileName),
    ok.

fun_callgraph_to_dot(CallTree, DotFileName) ->
    Edges=gen_callgraph_edges(CallTree),
    MG = digraph:new(),
    digraph_add_edges(Edges, [], MG),
    to_dot(MG,DotFileName),
    digraph:delete(MG).

gen_callgraph_edges(CallTree) ->
    {_, CurFunc, _} = CallTree#fun_calltree.id,
    ChildrenCallTrees = CallTree#fun_calltree.called,
    lists:foldl(fun(Tree, Acc) ->
                        {_, ToFunc, _} = Tree#fun_calltree.id,
                        NewEdge = {CurFunc, ToFunc, Tree#fun_calltree.cnt},
                        [[NewEdge|gen_callgraph_edges(Tree)]|Acc]
                end, [], ChildrenCallTrees).

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
        
   
digraph_add_edge({From, To,  CNT}, IndexTab, MG) ->
    {From1, IndexTab1}=
        case digraph:vertex(MG, {From,0}) of 
            false ->
                digraph:add_vertex(MG, {From,0}),
                {{From, 0}, [{From, 0}|IndexTab]};
            _ ->
                {From, Index}=lists:keyfind(From, 1, IndexTab),
                {{From, Index}, IndexTab}
        end,
     {To1, IndexTab2}= 
        case digraph:vertex(MG, {To,0}) of 
            false ->
                digraph:add_vertex(MG, {To,0}),
                {{To, 0}, [{To,0}|IndexTab1]};                          
            _ -> 
                {To, Index1} = lists:keyfind(To, 1,IndexTab1),
                case digraph:get_path(MG, {To, Index1}, From1) of 
                    false ->
                        digraph:add_vertex(MG, {To, Index1+1}),
                        {{To,Index1+1},lists:keyreplace(To,1, IndexTab1, {To, Index1+1})};
                    _ ->
                        {{To, Index1}, IndexTab1}
                end
        end,
    digraph:add_edge(MG, From1, To1, CNT),
    IndexTab2.
   
to_dot(MG, File) ->
    Edges = [digraph:edge(MG, X) || X <- digraph:edges(MG)],
    EdgeList=[{{X, Y}, Label} || {_, X, Y, Label} <- Edges],
    EdgeList1 = combine_edges(lists:keysort(1,EdgeList)),
    edge_list_to_dot(EdgeList1, File, "CallGraph").
    		
combine_edges(Edges) ->	
    combine_edges(Edges, []).
combine_edges([], Acc) ->		
    Acc;
combine_edges([{{X,Y}, Label}|Tl], [{X,Y, Label1}|Acc]) ->
    combine_edges(Tl, [{X, Y, Label+Label1}|Acc]);
combine_edges([{{X,Y}, Label}|Tl], Acc) ->
    combine_edges(Tl, [{X, Y, Label}|Acc]).
   
edge_list_to_dot(Edges, OutFileName, GraphName) ->
    {NodeList1, NodeList2, _} = lists:unzip3(Edges),
    NodeList = NodeList1 ++ NodeList2,
    NodeSet = ordsets:from_list(NodeList),
    Start = ["digraph ",GraphName ," {"],
    VertexList = [format_node(V) ||V <- NodeSet],
    End = ["graph [", GraphName, "=", GraphName, "]}"],
    EdgeList = [format_edge(X, Y, Label) || {X,Y,Label} <- Edges],
    String = [Start, VertexList, EdgeList, End],
    ok = file:write_file(OutFileName, list_to_binary(String)).

format_node(V) ->
    format_node(V, fun format_vertex/1).

format_node(V, Fun) ->
    String = Fun(V),
    {Width, Heigth} = calc_dim(String),
    W = (Width div 7 + 1) * 0.55,
    H = Heigth * 0.4,
    SL = io_lib:format("~f", [W]),
    SH = io_lib:format("~f", [H]),
    ["\"", String, "\"", " [width=", SL, " heigth=", SH, " ", "", "];\n"].

format_vertex(undefined) ->
    "undefined";
format_vertex({M,F,A}) ->
    io_lib:format("~p:~p/~p", [M,F,A]);
format_vertex({undefined, _}) ->
    "undefined";
format_vertex({{M,F,A},C}) ->
    io_lib:format("~p:~p/~p(~p)", [M,F,A, C]).

format_edge(V1, V2, Label) ->
    String = ["\"",format_vertex(V1),"\"", " -> ",
	      "\"", format_vertex(V2), "\""],
    [String, " [", "label=", "\"", format_label(Label), "\"",
     "fontsize=20 fontname=\"Verdana\"", "];\n"].
                       

%%% ------------------------------------%%%
%%% 	Process tree image generation   %%%
%%% ------------------------------------%%%
gen_process_tree_img() ->
    Pid=spawn_link(?MODULE, gen_process_tree_img_1, [self()]),
    receive
        {Pid, done, Result} ->
            Result
    end.
    
gen_process_tree_img_1(Parent)->
    CompressedTrees=percept2_db:gen_compressed_process_tree(),
    CleanPid =  percept2_db:select({system, nodes})==1,
    Res=gen_process_tree_img(CompressedTrees, CleanPid),
    Parent ! {self(), done, Res}.

gen_process_tree_img([], _) ->
    no_image;
gen_process_tree_img(ProcessTrees, CleanPid) ->
    BaseName = "processtree",
    DotFileName = BaseName++".dot",
    SvgFileName = filename:join(
                    [code:priv_dir(percept2), "server_root",
                     "images", BaseName++".svg"]),
    ok=process_tree_to_dot(ProcessTrees,DotFileName, CleanPid),
    os:cmd("dot -Tsvg " ++ DotFileName ++ " > " ++ SvgFileName),
    file:delete(DotFileName),
    ok.
            
process_tree_to_dot(ProcessTrees, DotFileName, CleanPid) ->
    {Nodes, Edges} = gen_process_tree_nodes_edges(ProcessTrees),
    MG = digraph:new(),
    digraph_add_edges_to_process_tree({Nodes, Edges}, MG),
    process_tree_to_dot_1(MG, DotFileName, CleanPid),
    digraph:delete(MG),
    ok.

gen_process_tree_nodes_edges(Trees) ->
    Res = percept2_utils:pmap(
            fun(Tree) ->
                    gen_process_tree_nodes_edges_1(Tree) 
            end,  Trees),
    {Nodes, Edges}=lists:unzip(Res),
    {lists:append(Nodes), lists:append(Edges)}.

gen_process_tree_nodes_edges_1({Parent, []}) ->
    Parent1={Parent#information.id, Parent#information.name,
             clean_entry(Parent#information.entry)},
    {[Parent1], []};
gen_process_tree_nodes_edges_1({Parent, Children}) -> 
    Parent1={Parent#information.id, Parent#information.name,
             clean_entry(Parent#information.entry)},
    Nodes = [{C#information.id, C#information.name,
              clean_entry(C#information.entry)}||{C, _} <- Children],
    Edges = [{Parent1, N, ""}||N<-Nodes],
    {Nodes1, Edges1}=gen_process_tree_nodes_edges(Children),
    {[Parent1|Nodes]++Nodes1, Edges++Edges1}.

clean_entry({M, F, Args}) when is_list(Args) ->
    {M, F, length(Args)};
clean_entry(Entry) -> Entry.

digraph_add_edges_to_process_tree({Nodes, Edges}, MG) ->
    %% This cannot be parallelised because of side effects.
    [digraph:add_vertex(MG, Node)||Node<-Nodes],
    [digraph_add_edge_1(MG, From, To, Label)||{From, To, Label}<-Edges].

%% a function with side-effect.
digraph_add_edge_1(MG, From, To, Label) ->
    case digraph:vertex(MG, To) of 
        false ->
            digraph:add_vertex(MG, To);
        _ ->
            ok
    end,
    digraph:add_edge(MG, From, To, Label).

process_tree_to_dot_1(MG, OutFileName,CleanPid) ->
    Edges =[digraph:edge(MG, X) || X <- digraph:edges(MG)],
    Nodes = digraph:vertices(MG),
    GraphName="ProcessTree",
    Start = ["digraph ",GraphName ," {"],
    VertexList = [format_process_tree_node(N,CleanPid) ||N <- Nodes],
    End = ["graph [", GraphName, "=", GraphName, "]}"],
    EdgeList = [format_process_tree_edge(X, Y, Label, CleanPid) ||{_, X, Y, Label} <- Edges],
    String = [Start, VertexList, EdgeList, End],
    ok = file:write_file(OutFileName, list_to_binary(String)).

format_process_tree_node(V, CleanPid) ->
    format_node({V, CleanPid}, fun format_process_tree_vertex/1).
            
format_process_tree_vertex({{Pid={pid, {_P1, P2, P3}}, Name, Entry}, CleanPid}) ->
    Pid1 = case CleanPid of 
               true -> {pid, {0, P2, P3}};
               _ -> Pid
           end,
    PidStr =  "<" ++ pid2str(Pid1) ++ ">",
    lists:flatten(io_lib:format("~s; ~p;\\n", [PidStr, Name])) ++
        format_entry(Entry);

format_process_tree_vertex(Other)  ->
    io_lib:format("~p", [Other]).
    
format_process_tree_edge(V1, V2, Label, CleanPid) ->
    String = ["\"",format_process_tree_vertex({V1, CleanPid}),"\"", " -> ",
	      "\"", format_process_tree_vertex({V2, CleanPid}), "\""],
    [String, " [", "label=", "\"", format_label(Label),
     "\"",  "fontsize=20 fontname=\"Verdana\"", "];\n"].


format_entry(undefined) ->
    "undefined";
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
    calc_dim(T, H + 1, 0, wrangler_misc:max(TmpW, MaxW));
calc_dim([_| T], H, TmpW, MaxW) ->
    calc_dim(T, H, TmpW+1, MaxW);
calc_dim([], H, TmpW, MaxW) ->
    {wrangler_misc:max(TmpW, MaxW), H}.

format_label(Label) when is_integer(Label) ->
    io_lib:format("~p", [Label]);
format_label(_Label) -> "".


-spec pid2str(Pid :: pid()|pid_value()) ->  string().
pid2str({pid, {P1,P2, P3}}) when is_atom(P2)->
     integer_to_list(P1)++"."++atom_to_list(P2)++"."++integer_to_list(P3);
pid2str({pid, {P1, P2, P3}}) ->
    integer_to_list(P1)++"."++integer_to_list(P2)++"."++integer_to_list(P3).
