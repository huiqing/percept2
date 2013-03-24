-module(percept2_callgraph).

-compile(export_all).

-include("../include/percept2.hrl").
-include_lib("kernel/include/file.hrl").


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Used for generating data only; not part of percept2 yet,%% 
%% but don't remove.                                       %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec gen_callgraph_txt_data(Pid::pid_value()) -> string().
gen_callgraph_txt_data(Pid) ->
    [Tree]=ets:select(fun_calltree, 
                      [{#fun_calltree{id = {Pid, '_','_'}, _='_'},
                        [],
                        ['$_']
                       }]),
    {ProcStartTs, ProcStopTs} = get_proc_life_time(Pid),
    ProcTime =timer:now_diff(ProcStopTs, ProcStartTs),
    Edges=gen_callgraph_edges(Tree,  ProcTime),
    lists:flatten(io_lib:format("~p", [Edges])).

gen_callgraph_edges(CallTree, ProcTime) ->
    {_Pid, FromFunc, _} = CallTree#fun_calltree.id,
    ChildrenCallTrees = CallTree#fun_calltree.called,
    CurFuncTime = CallTree#fun_calltree.acc_time, 
    FromFunc1=normalise_fun_name(FromFunc),
    FromFunLoc=get_func_location(FromFunc1),
    Edges=lists:foldl(
      fun(Tree, Acc) ->
              {_, ToFunc, _} = Tree#fun_calltree.id,
              ToFunc1 = normalise_fun_name(ToFunc),
              ToFuncLoc =get_func_location(ToFunc1),
              ToFuncTime = Tree#fun_calltree.acc_time,
              NewEdge = {{FromFunc, FromFunLoc, CurFuncTime / ProcTime},
                         {ToFunc,ToFuncLoc, ToFuncTime/ProcTime}, 
                         Tree#fun_calltree.cnt},
              [{NewEdge,gen_callgraph_edges(Tree,ProcTime)}|Acc]
      end, [], ChildrenCallTrees),
    %% case CallTree#fun_calltree.rec_cnt of 
    %%     0 ->
    %%         Edges;
    %%     N ->
    %%         [{{FromFunc,FromFunLoc, CurFuncTime/ProcTime}, 
    %%           {FromFunc,FromFunLoc, CurFuncTime/ProcTime}, N}|Edges]
    %% end.
    Edges.
  
normalise_fun_name({M,F,A}) ->
    case atom_to_list(F) of 
        "-"++F1 ->
            {F2, [_|F3]} = lists:splitwith(fun(C)->C/=$/ end, F1),
            {A1, _} = lists:splitwith(fun(C)->C/=$- end, F3),
            {M, list_to_atom(F2),list_to_integer(A1)};
        _ -> {M, F, A}
    end;
normalise_fun_name(Other) ->
     Other.




start_percept2_file_server() ->
    register(percept2_file_server, spawn_link(fun()-> file_server_loop([]) end)).

get_func_location(MFA) ->
    Pid = whereis(percept2_file_server),
    Pid ! {get_func_location, MFA, self()}, 
    receive {Pid, Res} ->
            Res
    end.

get_file(Mod) ->
    Pid = whereis(percept2_file_server),
    Pid ! {get_file, Mod, self()}, 
    receive {Pid, Res} ->
            Res
    end.

add_file(File) ->
    percept2_file_server!{add_file, File}.

file_server_loop(State) ->
    receive
        {get_func_location, {M, F, A}, From} ->
            case lists:keyfind(M, 1, State) of 
                {M, File, FunLocs} ->
                    case lists:keyfind({F,A}, 1, FunLocs) of 
                        {{F, A}, Loc} -> 
                            From ! {self(), {File, Loc}},
                            file_server_loop(State);
                        false ->
                            From ! {self(), {File, {0,0}}},
                            file_server_loop(State)
                    end;
                false ->
                    case code:where_is_file(atom_to_list(M)++".erl") of 
                        non_existing ->
                            From ! {self(), {file_non_existing, {0,0}}},
                            file_server_loop(State);                            
                        File ->
                            FunLocs=get_fun_locations(File),
                            case lists:keyfind({F,A}, 1, FunLocs) of 
                                {{F, A}, Loc} ->
                                    From ! {self(),{File, Loc}};
                                false ->
                                    From ! {self(),{File, {0,0}}}
                            end,
                            file_server_loop([{M, File, FunLocs}|State])
                    end
            end;
        {get_func_location, _, From} ->
            From ! {self(),{file_non_existing, {0,0}}},
            file_server_loop(State);
        {add_file, File} ->
            ModName = list_to_atom(filename:basename(File, ".erl")),
            FunLocs=get_fun_locations(File),
            file_server_loop([{ModName, filename:absname(File), FunLocs}|State]);
        {get_file, ModName, From} ->
            case lists:keyfind(ModName, 1, State) of 
                {ModName, FileName, _} -> 
                    From ! {self(), FileName};
                false -> From ! {self(), file_non_existing}
            end,
            file_server_loop(State);
        stop -> stop
    end.

get_fun_locations(FName) ->
    {ok, AST} =  percept2_ast_server:parse_file(FName),
    Forms = percept2_syntax:form_list_elements(AST),
    [{{percept2_syntax:atom_value(percept2_syntax:function_name(Form)), 
       percept2_syntax:function_arity(Form)},
      percept2_ast_server:get_range(Form)}
      ||Form<-Forms, 
       erl_syntax:type(Form)==function].

get_proc_life_time(Pid)->
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
    {ProcStartTs, ProcStopTs}.


init() ->
    start_percept2_file_server(),
    add_file("sim_code.erl").
    
