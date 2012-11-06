%% Copyright (c) 2011, Huiqing Li, Simon Thompson
%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions are met:
%%     %% Redistributions of source code must retain the above copyright
%%       notice, this list of conditions and the following disclaimer.
%%     %% Redistributions in binary form must reproduce the above copyright
%%       notice, this list of conditions and the following disclaimer in the
%%       documentation and/or other materials provided with the distribution.
%%     %% Neither the name of the copyright holders nor the
%%       names of its contributors may be used to endorse or promote products
%%       derived from this software without specific prior written permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ''AS IS''
%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
%% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
%% BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
%% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
%% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
%% BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR 
%% OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF 
%% ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%% ===========================================================================================
%% Incremental similar code detection for Erlang programs.
%% 
%% Author contact: hl@kent.ac.uk, sjt@kent.ac.uk
%% 
%% @private
-module(sim_code_v5).

-export([sim_code_detection/8,sim_code_detection/4]). 

-export([ gen_initial_clone_candidates/3,
          generalise_and_hash_ast/5,
          check_clone_candidates/3]).


-export([init_hash_loop/0, init_clone_check/0, init_ast_loop/1]).

-include_lib("wrangler/include/wrangler_internal.hrl").

-compile(export_all).

-define(INC, false). %% incremental or not.

%% default threshold values.
-define(DefaultSimiScore, 0.8).
-define(DEFAULT_LEN, 5).
-define(DEFAULT_TOKS, 40).
-define(DEFAULT_FREQ, 2).
-define(DEFAULT_SIMI_SCORE, 0.8).
-define(DEFAULT_NEW_VARS, 4).
-define(MIN_TOKS, 10).

%% record for threshold values.
-record(threshold, 
	{min_len = ?DEFAULT_LEN,
	 min_freq= ?DEFAULT_FREQ,
	 min_toks= ?DEFAULT_TOKS,
	 max_new_vars =?DEFAULT_NEW_VARS,
	 simi_score=?DEFAULT_SIMI_SCORE}).

-spec(sim_code_detection/8::(DirFileList::[filename()|dir()], MinLen::integer(), MinToks::integer(),
			      MinFreq::integer(),  MaxVars::integer(),SimiScore::float(), 
                                 SearchPaths::[dir()], TabWidth::integer()) -> {ok, string()}).
sim_code_detection(DirFileList,MinLen1,MinToks1,MinFreq1,MaxVars1,SimiScore1,SearchPaths,TabWidth) ->
    {MinLen,MinToks,MinFreq,MaxVars,SimiScore} = check_parameters(MinLen1,MinToks1,MinFreq1,MaxVars1,SimiScore1),
    StartTime = now(),
    {Time1, Files} = timer:tc(wrangler_misc, expand_files, [DirFileList,".erl"]),
    case Files of
	[] ->
	    ?wrangler_io("Warning: No files found in the searchpaths specified.",[]);
	_ -> 
            Cs = sim_code_detection(Files, {MinLen, MinToks, MinFreq, MaxVars, SimiScore},
                                    SearchPaths, TabWidth),
            io:format("Clone detection finished with ~p clones found\n", [length(Cs)])
            %%display_clones_by_freq(lists:reverse(Cs), "Similar")
    end,
    {ok, "Similar code detection finished."}.


sim_code_detection(Files, {MinLen, MinToks, MinFreq, MaxVars, SimiScore},
		       SearchPaths, TabWidth) ->
    ets:new(var_tab, [named_table, public, {keypos, 1}, set,{read_concurrency, true}]),
    %% Threshold parameters.
    Threshold = #threshold{min_len = MinLen,
			   min_freq = MinFreq,
			   min_toks = MinToks,
			   max_new_vars = MaxVars,
			   simi_score = SimiScore},
    HashPid = start_hash_process(),
    ASTPid = start_ast_process(HashPid),
    
    Cs = sim_code_detection_1(Files, Threshold, HashPid, ASTPid, SearchPaths,TabWidth),
    
    stop_hash_process(HashPid),
    stop_ast_process(ASTPid),
    ets:delete(var_tab),
    Cs.

sim_code_detection_1(Files, Thresholds, HashPid, ASTPid, SearchPaths, TabWidth) ->
    ?wrangler_io("Generalise and hash ASTs ...\n", []),
    {Time2, _}=timer:tc(?MODULE, generalise_and_hash_ast, [Files, Thresholds, ASTPid, SearchPaths, TabWidth]),
    ?wrangler_io("\nCollecting initial clone candidates ...\n",[]),
    {Time3, Cs}= timer:tc(?MODULE, gen_initial_clone_candidates, [Files, Thresholds, HashPid]),
    ?wrangler_io("\nNumber of initial clone candidates: ~p\n", [length(Cs)]),
    
    ?wrangler_io("\nChecking clone candidates ... \n", []),
    {Time4, Res} =timer:tc(?MODULE, check_clone_candidates, [Thresholds, HashPid, Cs]),
    {Time2, Time3, Time4, Res}.
    
gen_initial_clone_candidates(Files, Thresholds, HashPid) ->
    %% Generate clone candidates using suffix tree based clone detection techniques.
    Dir = filename:dirname(hd(Files)),
    {ok, OutFileName} = get_clone_candidates(HashPid, Thresholds, Dir),
    {ok, Res} = file:consult(OutFileName),
    file:delete(OutFileName),
    Cs0 = case Res of
	      [] -> [];
	      [R] -> R
	  end,
    process_initial_clones(Cs0).
   
process_initial_clones(Cs) ->
    [begin
	 Rs1 =sets:to_list(sets:from_list(Rs)),
	 {Rs1, Len, length(Rs1)}
     end
     ||{Rs, Len, _Freq}<-sets:to_list(sets:from_list(Cs))].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                                                 %%
%%                       Generalise and hash ASTs                                  %%
%%                                                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 
   
%% Serialise, in breath-first order, generalise each expression in the AST and insert them into 
%% the AST table. Each object in the AST table has the following format:
%% {{FileName, FunName, Arity, Index}, ExprAST}, where Index is used to identify a specific 
%% expression in the function. 
generalise_and_hash_ast(Files, Threshold, ASTPid, SearchPaths, TabWidth) ->
    %% Refactoring1: lists comprehension parallel pmap. Since the value returned here is not actually 
    %% used, so pforeach should do as well.
    para_lib:pforeach(fun(File) ->
                              generalise_and_hash_file_ast_1(
                                File, Threshold, ASTPid, true, SearchPaths, TabWidth)
                      end, Files).

%% Generalise and hash the AST for an single Erlang file.
generalise_and_hash_file_ast_1(FName, Threshold, ASTPid, IsNewFile, SearchPaths, TabWidth) ->
    Forms = try quick_parse_annotate_file(FName, SearchPaths, TabWidth) of
		{ok, {AnnAST, _Info}} ->
		    wrangler_syntax:form_list_elements(AnnAST)
	    catch
		_E1:_E2 -> []
	    end,
    F = fun (Form) ->
		case wrangler_syntax:type(Form) of
		    function ->
                        generalise_and_hash_function_ast(Form, FName, IsNewFile, Threshold, ASTPid);
		    _ -> ok
		end
	end,
    %% Refactoring2: lists:foreach to para_lib:pforeach;
    %% to avoid very small processes, we allow each process to handle 10 Forms 
    %% at the most
    para_lib:pforeach(fun (Form) -> F(Form) end, Forms, 5).

%% generalise and hash the AST of a single function.
generalise_and_hash_function_ast(Form, FName, true, Threshold, ASTPid) ->
    FunName = wrangler_syntax:atom_value(wrangler_syntax:function_name(Form)),
    Arity = wrangler_syntax:function_arity(Form),
    HashVal = erlang:md5(format(Form)),
    generalise_and_hash_function_ast_1(FName, Form, FunName, Arity, HashVal, Threshold,ASTPid).

%% generalise and hash a function that is either new or has been changed since last run of clone detection.
generalise_and_hash_function_ast_1(File, Form, FunName, Arity, HashVal, Threshold, ASTPid) ->
    {StartLine, _} = wrangler_syntax:get_pos(Form),
    %% Turn absolute locations to relative locations, so 
    %% so that the result can be reused.
    NewForm = absolute_to_relative_loc(Form, StartLine),
    %% all locations are relative locations.
    %% variable binding information is needed by the anti-unification process.
    AllVars = wrangler_misc:collect_var_source_def_pos_info(NewForm),
    %% I also put the Hashvalue of a function in var_tab.
    ets:insert(var_tab, {{File, FunName, Arity}, HashVal, AllVars}),
    Fun = fun(Node, Index) ->
                  case wrangler_syntax:type(Node) of 
                      clause ->
                          Body = wrangler_syntax:clause_body(Node),
                          generalise_and_hash_body(ASTPid, Body, StartLine,
                                                   {File, FunName, Arity}, Threshold, Index);
                      block_expr ->
                          Body = wrangler_syntax:block_expr_body(Node),
                          generalise_and_hash_body(ASTPid, Body, StartLine,
                                                   {File, FunName, Arity}, Threshold, Index);
                      try_expr ->
                          Body = wrangler_syntax:try_expr_body(Node),
                          generalise_and_hash_body(ASTPid, Body, StartLine,
                                                   {File, FunName, Arity}, Threshold, Index);
                      _ -> Index
                  end
          end,
    api_ast_traverse:fold(Fun, 1, NewForm).


generalise_and_hash_body(ASTPid,Body, StartLine, FFA, Threshold, Index) ->
    Len = length(Body),
    case Len>= Threshold#threshold.min_len of
        true ->
            insert_to_ast_tab(ASTPid, {FFA, Body, Index, StartLine}),
            Index + Len;
        false ->
            Index
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                                    %%
%% Store the AST representation of expression statements in ETS table %%
%%                                                                    %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_ast_process(HashPid) ->
    %% Dummy entries are used to sparate entries from different functions.
    spawn_link(?MODULE, init_ast_loop, [HashPid]).

init_ast_loop(HashPid) ->
    ets:new(ast_tab, [named_table, protected, {keypos,1}, set,{read_concurrency, true}]),
    ast_loop(HashPid).
%% stop the ast process.
stop_ast_process(Pid)->
    Pid ! stop.

%% Insert a sequence of expressions into the AST table. 
%% The sequence of expressions to be inserted are from 
%% the same expression body (clause_expr, block_expr, try_expr).
insert_to_ast_tab(Pid, {{M, F, A}, ExprASTs, Index, StartLine}) ->
    Self=self(),
    Pid ! {add, {{M, F, A}, ExprASTs, Index,  StartLine}, Self},
    receive
        {Pid, Self, done} ->
            ok
    end.

ast_loop(HashPid) ->
    receive
        {add, {FFA, Body, Index, StartLine}, From} ->
            Len = length(Body),
            ExprASTsWithIndex = lists:zip(Body, lists:seq(0, Len - 1)),
            HashValExprPairs=[generalise_and_hash_expr(ast_tab, FFA, StartLine,
                                                       Index, {E, I})
                              ||{E, I}<-ExprASTsWithIndex],
            insert_hash(HashPid, {FFA, HashValExprPairs}),
            From ! {self(), From, done},
            ast_loop(HashPid);
 	stop ->
	    ets:delete(ast_tab);
	_Msg ->
	    ?wrangler_io("Unexpected message:\n~p\n", [_Msg]),
	  ok
    end.
       
generalise_and_hash_expr(ASTTab, {M, F, A}, StartLine,
			 StartIndex, {Expr, RelativeIndex}) ->
    %% Num of tokens is used to chech the size of a clone candidate.
    NoOfToks = no_of_tokens(Expr),
    %% insert the AST of an expression into the ast table.
    ets:insert(ASTTab, {{M, F, A, {StartIndex, RelativeIndex}}, Expr}),
    E1 = do_generalise(Expr),
    %% get the hash values of the generalised expression.
    HashVal = erlang:md5(format(E1)),
    %% the location here is relative location.
    StartEndLoc = wrangler_misc:start_end_loc(Expr),
    {HashVal, {{StartIndex, RelativeIndex},
	       NoOfToks, StartEndLoc, StartLine}}.

%% replace an AST node if the node can be generalised.
do_generalise(Node) ->
    F0 = fun (T, _Others) ->
		 case wrangler_code_search_utils:generalisable(T) of
		   true ->
		       {wrangler_syntax:variable('Var'), true};
		   false -> {T, false}
		 end
	 end,
    element(1, api_ast_traverse:stop_tdTP(F0, Node, [])).
    
 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                                    %%
%%  Hash the AST representation of generalised expressions using MD5, %%
%%  and map sequences of expressions into sequences of indexes.       %%
%%                                                                    %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
start_hash_process() ->
    spawn_link(?MODULE, init_hash_loop, []).

init_hash_loop() ->
    ets:new(expr_hash_tab, [named_table, protected, {keypos, 1}, set,{read_concurrency, true}]),
    ets:new(expr_seq_hash_tab, [named_table, protected, {keypos,1}, ordered_set,{read_concurrency, true}]),
    hash_loop(1).

%% Get initial clone candidates.    
get_clone_candidates(Pid, Thresholds, Dir) ->
    Pid ! {get_clone_candidates, self(), Thresholds, Dir},
    receive
	{Pid, {ok, OutFileName}}->
	    {ok, OutFileName}
    end.
get_clone_in_range(Pid, C) ->
    Pid! {get_clone_in_range, self(), C},
    receive
	{Pid, C1} ->
	    C1
    end.
stop_hash_process(Pid) ->
    Pid!stop.

insert_hash(Pid, {{M, F, A}, HashExprPairs}) ->
    Self=self(),
    Pid ! {add, {{M, F, A}, HashExprPairs}, Self},
    receive
        {Pid, Self, done} ->
            ok
    end.

get_index(Key) ->
    case ets:lookup(expr_hash_tab, Key) of 
	[{Key, I}]->
            I;
	[] ->
            NewIndex = ets:info(expr_hash_tab, size)+1,
	    ets:insert(expr_hash_tab, {Key, NewIndex}),
	    NewIndex
    end.

hash_loop(NextSeqNo) ->
    receive
	%% add a new entry.
        {add, {{M, F, A}, KeyExprPairs}, From} ->
            KeyExprPairs1 =
		[{{Index1, NumOfToks, StartEndLoc, StartLine, true}, HashIndex}
		 || {Key, {Index1, NumOfToks, StartEndLoc, StartLine}} <- KeyExprPairs,
		    HashIndex <- [get_index(Key)]],
            From ! {self(), From, done},
            ets:insert(expr_seq_hash_tab, {NextSeqNo, {M,F,A}, KeyExprPairs1}),
            hash_loop(NextSeqNo+1);
	{get_clone_candidates, From, Thresholds, Dir} ->
	    {ok, OutFileName} = search_for_clones(Dir, Thresholds),
            From ! {self(), {ok, OutFileName}},
            hash_loop(NextSeqNo);
	{get_clone_in_range, From, {Ranges, Len, Freq}} ->
	    F0 = fun ({ExprSeqId, ExprIndex}, L) ->
			 [{ExprSeqId, {M, F, A}, Exprs}] = ets:lookup(expr_seq_hash_tab, ExprSeqId),
			 Es = lists:sublist(Exprs, ExprIndex, L),
			 [{{M,F,A,Index}, Toks, {{StartLoc, EndLoc}, StartLine}, IsNew}
			  || {{Index, Toks, {StartLoc, EndLoc}, StartLine, IsNew}, _HashIndex} <- Es]
		 end,
	    C1 = {[F0(R, Len) || R <- Ranges], {Len, Freq}},
	    From ! {self(), C1},
	   %% hash_loop({NextSeqNo, NewData});
            hash_loop(NextSeqNo);
	stop ->
            ets:delete(expr_hash_tab),
            ets:delete(expr_seq_hash_tab),
            ok
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                                    %%
%%  Hash the AST representation of expressions using MD5, and map     %%
%%  sequence of expression into sequences of indexes.                 %%
%%                                                                    %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

check_clone_candidates(Thresholds, HashPid, Cs) ->
    CloneCheckerPid = start_clone_check_process(),
    %% examine each clone candiate and filter false positives.
    Cs2 = examine_clone_candidates(Cs, Thresholds, CloneCheckerPid, HashPid),
    Cs3 = combine_clones_by_au(Cs2),
    stop_clone_check_process(CloneCheckerPid),
    [{R, L, F, C}||{R, L, F, C}<-Cs3, length(R)>=2].
    

start_clone_check_process() ->
    spawn_link(?MODULE, init_clone_check, []).

init_clone_check() ->
    ets:new(clone_tab, [named_table, protected, {keypos, 1}, set,{read_concurrency, true}]),
    clone_check_loop([],[]).


stop_clone_check_process(Pid) ->
    Pid ! stop.

add_new_clones(Pid, Clones) ->
    Pid ! {add_clone, Clones}.

get_final_clone_classes(Pid, ASTTab) ->
    Pid ! {get_clones, self(), ASTTab},
    receive
        {Pid, Cs} ->
	  Cs
    end.

clone_check_loop(Cs, CandidateClassPairs) ->
    receive
	{add_clone,  {Candidate, Clones}} ->
            Clones1=[get_clone_class_in_absolute_locs(Clone) 
		     || Clone <- Clones],
            clone_check_loop(Clones1++Cs, [{hash_a_clone_candidate(Candidate), Clones}
                                           |CandidateClassPairs]);
	{get_clones, From, _ASTTab} ->
	    ?debug("TIME3:\n~p\n", [time()]),
	    Cs0=remove_sub_clones(Cs),
	    Cs1=[{AbsRanges, Len, Freq, AntiUnifier}||
		    {_, {Len, Freq}, AntiUnifier,AbsRanges}<-Cs0],
	    From ! {self(), Cs1},
	    clone_check_loop(Cs, CandidateClassPairs);       
	stop ->
            ets:delete(clone_tab),
            ok;            
	_Msg -> 
	    ?wrangler_io("Unexpected message:\n~p\n",[_Msg]),
	    clone_check_loop(Cs,  CandidateClassPairs)
    end.
 
%%=============================================================================
%% check each candidate clone, and drive real clone classes.
%% Refactoring3: refactored to remove the dependences between consecutive recursions.
%% Refactoring4: turn recursive function into lists:foreach.
%% Refactoring5: turn lists:foreach into para_lib:pforeach.
examine_clone_candidates(Cs, Thresholds, CloneCheckerPid, HashPid) ->
    NumberedCs = lists:zip(Cs, lists:seq(1, length(Cs))),
    para_lib:pforeach(fun({C, Nth}) ->
                              examine_a_clone_candidate({C,Nth},Thresholds, CloneCheckerPid, HashPid)
                     end,NumberedCs),
    get_final_clone_classes(CloneCheckerPid, ast_tab).
 
examine_a_clone_candidate({C,Nth},Thresholds,CloneCheckerPid,HashPid) ->
    output_progress_msg(Nth), 
    C1 = get_clone_in_range(HashPid,C),
    MinToks = Thresholds#threshold.min_toks, 
    MinFreq = Thresholds#threshold.min_freq, 
    case remove_short_clones(C1,MinToks,MinFreq) of
      [] ->
	  ok;
      [C2] ->
            case examine_a_clone_candidate(C2,Thresholds) of
                [] ->
                    ok;
                ClonesWithAU ->
                    add_new_clones(CloneCheckerPid,{C2, ClonesWithAU})
            end
    end.
 
output_progress_msg(Num) ->
    case Num rem 10 of
     	1 -> 
     	    ?wrangler_io("\nChecking clone candidate no. ~p ...", [Num]);
     	_-> ok
     end.
   
hash_a_clone_candidate(_C={Ranges, {_Len, _Freq}}) ->
    F = fun({MFAI, Toks, {Loc, _StartLine}, _IsNew}) ->
		{MFAI, Toks, Loc}
	end,
    erlang:md5(lists:usort(
		 [erlang:md5(lists:flatten(
			       io_lib:format(
				 "~p", [[F(E)||E<-R]])))
		  ||R<-Ranges])).
%% examine a  clone candidate.
examine_a_clone_candidate(_C={Ranges, {_Len, _Freq}}, Thresholds) ->
    ASTTab = ast_tab,
    RangesWithExprAST=[attach_expr_ast_to_ranges(R, ASTTab)|| R<-Ranges],
    Clones = examine_clone_class_members(RangesWithExprAST, Thresholds,[]),
    ClonesWithAU = [begin
			FromSameFile=from_same_file(Rs),
                        AU= get_anti_unifier(Info, FromSameFile),
                        {Rs1, AU1} = attach_fun_call_to_range(Rs, AU, FromSameFile),
                        {Rs1, {Len, length(Rs1)}, AU1}
		    end
		    || {Rs, {Len, _}, Info} <- Clones],
    [{Rs1, {Len, F}, AU1}||{Rs1, {Len, F}, AU1}<-ClonesWithAU,
                           F>=Thresholds#threshold.min_freq].
 

attach_expr_ast_to_ranges(Rs, ASTTab) ->
    [{R, ExpAST}||R={ExprKey, _Toks, _Loc, _IsNew}<-Rs, 
		  {_Key, ExpAST}<-ets:lookup(ASTTab, ExprKey)].


%% check the clone members of a clone candidate using 
%% anti-unification techniques.   
examine_clone_class_members(RangesWithExprAST, Thresholds, Acc) 
  when length(RangesWithExprAST)< Thresholds#threshold.min_freq ->
    %% The number of clone memebers left is less 
    %% than the min_freq threshold, so the examination
    %% finishes, and sub-clones are removed.
    remove_sub_clones(Acc);

examine_clone_class_members(RangesWithExprAST, Thresholds,Acc) ->
    %% Take the first clone member and  try to anti_unify other 
    %% clone members with this member. If there is a real clone 
    %% class found, then the anti-unifier of the class is derrived 
    %% by generalisation of the first clone member.

    [RangeWithExprAST1|Rs]=RangesWithExprAST,

    %% try to anti_unify each of the remaining candidate clone members 
    %% with the first candidate clone member.

    Res = [do_anti_unification(RangeWithExprAST1, RangeWithExprAST2)
	   || RangeWithExprAST2<-Rs],


    %% process the anti_unification result.
    Clones = process_au_result(Res, Thresholds),

    %% get the maximal length of the clone clone members returned.
    MaxCloneLength= case Clones ==[] of 
			true -> 
			    0;
			_-> 
			    %% make sure the clones returned are ordered!!!
			    element(1, element(2, hd(Clones)))
		    end,

    InitialLength = length(RangeWithExprAST1),

    case MaxCloneLength /= InitialLength of
	true ->
	    %% the original expression sequences have been chopped into shorter ones.
	    examine_clone_class_members(Rs, Thresholds, Clones ++ Acc);
	false ->
	    %% the original expression still a class member of the clones returned.
	    Rs1 = element(1, hd(Clones)),
	    RemainedRanges = RangesWithExprAST -- Rs1,
	    examine_clone_class_members(RemainedRanges, Thresholds, Clones ++ Acc)

    end.

%% try to anti-unify two expression sequences.
do_anti_unification(RangeWithExpr1, RangeWithExpr2) ->
    ZippedExprs=lists:zip(RangeWithExpr1, RangeWithExpr2),
    [begin
	 {{Index1,E1}, {Index2, E2},
	  do_anti_unification_1(E1,E2)}
     end|| {{Index1,E1}, {Index2, E2}}<-ZippedExprs].
    
%% try to anti_unift two expressions.
do_anti_unification_1(E1, E2) ->
    SubSt=wrangler_anti_unification:anti_unification(E1,E2),
    case SubSt of 
	none -> none;
	_ -> case subst_sanity_check(E1, SubSt) of
		 true ->
		     SubSt;
		 false ->
		     none
	     end
    end.

subst_sanity_check(Expr1, SubSt) ->
    BVs = api_refac:bound_vars(Expr1),
    F = fun ({E1, E2}) ->
		case wrangler_syntax:type(E1) of
		    variable ->
                        case is_macro_name(E1) of 
                            true -> 
                                false;
                            _ -> has_same_subst(E1, E2, SubSt)
			end;
		    _ ->
			%% the expression to be replaced should not contain local variables.
			BVs -- api_refac:free_vars(E1) == BVs
		end
	end,
    lists:all(F, SubSt).

has_same_subst(E1, E2, SubSt) ->
    E1Ann = wrangler_syntax:get_ann(E1),
    {value, {def, DefPos}} = lists:keysearch(def, 1, E1Ann),
    %% local vars should have the same substitute.
     not  lists:any(
	    fun ({E11, E21}) ->
		  wrangler_syntax:type(E11) == variable andalso
		    {value, {def, DefPos}} == lists:keysearch(
						def, 1, wrangler_syntax:get_ann(E11))
		      andalso
		  wrangler_prettypr:format(wrangler_misc:reset_ann_and_pos(E2))
	       =/= wrangler_prettypr:format(wrangler_misc:reset_ann_and_pos(E21))
	  end, SubSt).

%% process anti-unification result.
process_au_result(AURes, Thresholds) ->
    Res = [process_one_au_result(OneAURes, Thresholds)
	   || OneAURes <- AURes],
    ClonePairs = lists:append(Res),
    get_clone_classes(ClonePairs, Thresholds).

%% process one anti_unification pair. In case the whose 
%% pair of expression sequences do not anti-unify, get those 
%% pairs of sub sequences that do anti-unify.
process_one_au_result(OneAURes, Thresholds) ->
    SubAULists=group_au_result(OneAURes, Thresholds),
    ClonePairs =lists:append([get_clone_pairs(SubAUList, Thresholds)
			      ||SubAUList<-SubAULists]),
    ClonePairs1 =[lists:unzip3(CP)||CP<-ClonePairs],
    remove_sub_clone_pairs(ClonePairs1).

%% examine the result of anti-unifying a pair of expression sequences and 
%% get the sub expression sequences pairs that are anti-unifiable.
group_au_result([], _Thresholds)->
    [];
group_au_result(AURes, Thresholds) ->
    %% here 'none' means the two expressions E1 an E2 do not anti-unify.
    {AUResList1,AUResList2} =
	lists:splitwith(fun({_E1,_E2, S}) ->S/=none end, AURes),
    AUResList3 = case AUResList2 of
		     [] -> [];
		     [_|T] -> T
		 end,
    case clone_pair_above_min_size(AUResList1, Thresholds) of
	true ->
	    [AUResList1]++group_au_result(AUResList3, Thresholds);
	false ->
	    group_au_result(AUResList3, Thresholds)
    end.
  
get_clone_pairs(AURes, Thresholds) ->
    get_clone_pairs(AURes, Thresholds, {[],[]},[]).

get_clone_pairs([],Thresholds,{_VarSubAcc,ClonePairAcc},Acc) ->
    case clone_pair_above_min_size(ClonePairAcc,Thresholds) of
      true ->
	    ClonePairs = decompose_clone_pair(lists:reverse(ClonePairAcc),Thresholds), 
	    ClonePairs++Acc;
	false ->
	    Acc
    end;
get_clone_pairs([CurPair = {_E1,_E2,SubSt}| AURes],Thresholds,
		{VarSubAcc,ClonePairAcc},Acc) ->
    %% check the subsitution of variables. 
    %% variables with the same defining location should 
    %% has the same substitution.
    CurVarSubsts = get_var_subst(SubSt), 
    case var_sub_conflicts(CurVarSubsts,VarSubAcc) of
      true ->
	  %% conflicting variable substitution.
	  case clone_pair_above_min_size(ClonePairAcc,Thresholds) of
	    true ->
		NewClonePairs = decompose_clone_pair(lists:reverse(ClonePairAcc),Thresholds), 
		NewAcc = NewClonePairs++Acc, 
		get_clone_pairs(AURes,Thresholds,{[],[]},NewAcc);
	    false ->
		%% the clone pairs is too short.
		get_clone_pairs(AURes,Thresholds,{[],[]},Acc)
	  end;
      false ->
	  get_clone_pairs(AURes,Thresholds,
			  {CurVarSubsts++VarSubAcc,[CurPair]++ClonePairAcc},Acc)
    end.

get_var_subst(SubSt) ->
    F = fun ({E1, E2}) ->
		{value, {def, DefPos}} =
		    lists:keysearch(def, 1, wrangler_syntax:get_ann(E1)),
		{DefPos, wrangler_prettypr:format(wrangler_misc:reset_ann_and_pos(E2))}
	end,
    [F({E1,E2})
     || {E1,E2} <- SubSt,
	wrangler_syntax:type(E1) == variable,
	 not  is_macro_name(E1)].

is_macro_name(Exp) ->
    Ann = wrangler_syntax:get_ann(Exp),
    {value, {syntax_path, macro_name}} == 
        lists:keysearch(syntax_path, 1, Ann).


var_sub_conflicts(SubSts, ExistingVarSubsts) ->
    lists:any(fun ({DefPos, E}) ->
		      case lists:keysearch(DefPos, 1, ExistingVarSubsts) of
			{value, {DefPos, E1}} ->
			    E /= E1;
			false ->
			    false
		      end
	      end, SubSts).

%% decompose a clone pairs so that each new clone pairs' simi score 
%% is above the threshold specified.
decompose_clone_pair(ClonePair,Thresholds) ->
    ListOfClonePairs=decompose_clone_pair_by_new_vars(ClonePair, Thresholds),
    Res=[decompose_clone_pair_by_simi_score(CP, Thresholds)||CP<-ListOfClonePairs],
    lists:append(Res).

decompose_clone_pair_by_simi_score(ClonePair, Thresholds) ->
    case clone_pair_above_min_simi_score(ClonePair, Thresholds) of 
	true ->
	    [ClonePair];
	false->
	    decompose_clone_pair_by_simi_score_1(ClonePair, Thresholds)
    end.
    
decompose_clone_pair_by_simi_score_1(ClonePair,Thresholds) ->
    ClonePairWithSimiScore = 
	[{R1, R2, Subst, {simi_score([R1], SubEs1), simi_score([R2], SubEs2)}}
	  ||{R1, R2, Subst}<-ClonePair, {SubEs1, SubEs2}<-[lists:unzip(Subst)]],
	 decompose_clone_pair_by_simi_score_2(ClonePairWithSimiScore, Thresholds).

decompose_clone_pair_by_simi_score_2(ClonePairWithSimiScore, Thresholds) ->
    Scores = [(Score1+Score2)/2||Pair<-ClonePairWithSimiScore,
				 {Score1,Score2}<-[element(4, Pair)]],
    MinScore = lists:min(Scores),
    %%spliting the clone pairs at the pair of expressions with the lowest 
    %% similarity score.
    {ClonePair1, [_P|ClonePair2]} = lists:splitwith(
				      fun({_, _, _, {Score1, Score2}}) ->
					      (Score1+Score2)/2 /= MinScore
				      end, ClonePairWithSimiScore),
    decompose_clone_pair_by_simi_score_3(ClonePair1, Thresholds)
	++ decompose_clone_pair_by_simi_score_3(ClonePair2, Thresholds).


decompose_clone_pair_by_simi_score_3(ClonePair, Thresholds)->
    case not clone_pair_above_min_size(ClonePair, Thresholds) of 
	true ->
	    [];
	false ->
	    CP =[{R1, R2, Subst}||{R1,R2, Subst, _}<-ClonePair],
	    case clone_pair_above_min_simi_score(CP, Thresholds) of 
		true ->
		    [CP];
		false ->
		    decompose_clone_pair_by_simi_score_2(ClonePair, Thresholds)
	    end
    end.

decompose_clone_pair_by_new_vars(ClonePair, Thresholds)->
    MinLen = Thresholds#threshold.min_len,
    MaxNewVars = Thresholds#threshold.max_new_vars,
    {{CurLen, _}, CurClonePair, ClonePairs}=
	lists:foldl(fun({R1,R2, Subst}, {{Len, SubstAcc}, Acc1,  Acc2})->
			    case Subst of 
				[] ->
				    {{Len+1, SubstAcc}, [{R1,R2,Subst}|Acc1], Acc2};
				_ -> 
				    NewVars=num_of_new_vars(Subst++SubstAcc),
				    case NewVars> MaxNewVars of 
					true ->
					    {NewAcc1, NewSubst} = get_sub_clone_pair(lists:reverse([{R1,R2,Subst}|Acc1]), MaxNewVars),
					    NewLen = length(NewAcc1),
					    case Len>=MinLen of 
						true ->
						    {{NewLen, NewSubst}, lists:reverse(NewAcc1), [lists:reverse(Acc1)|Acc2]};
						false ->
						    {{NewLen, NewSubst}, lists:reverse(NewAcc1), Acc2}
					    end;
					false ->
					    {{Len+1, Subst++SubstAcc}, [{R1,R2,Subst}|Acc1], Acc2}
				    end
			    end
		    end, 
		    {{0, []}, [], []}, ClonePair),
    case CurLen>=MinLen of 
	true ->
	    lists:reverse([lists:reverse(CurClonePair)|ClonePairs]);
	false ->
	    lists:reverse(ClonePairs)
    end.
    

get_sub_clone_pair([{_R1,_R2, Subst}|CPs], NumOfNewVars) ->
    case Subst of
	[] ->
	    get_sub_clone_pair(CPs, NumOfNewVars);
	_ ->
	    {_,_, ListOfSubSt} = lists:unzip3(CPs),
	    NewSubst = lists:append(ListOfSubSt),
	    case num_of_new_vars(NewSubst) =< NumOfNewVars of
		true ->
		    {CPs, NewSubst};
		false ->
		    get_sub_clone_pair(CPs, NumOfNewVars)
	    end
    end.

clone_pair_above_min_simi_score(ClonePair, Thresholds)->
    SimiScoreThreshold = Thresholds#threshold.simi_score,
    {Range1, Range2, Subst} = lists:unzip3(ClonePair),
    {SubExprs1, SubExprs2} = lists:unzip(lists:append(Subst)),
    Score1 = simi_score(Range1, SubExprs1),
    Score2 = simi_score(Range2, SubExprs2),
    Score1 >= SimiScoreThreshold  andalso
	Score2>= SimiScoreThreshold.

clone_pair_above_min_size(CP, Thresholds) ->
    length(CP)>=Thresholds#threshold.min_len andalso
	lists:sum([element(2, E1)||{{E1,_}, _E2, _S}<-CP])
	>=Thresholds#threshold.min_toks.

simi_score(ExprRanges, SubExprs) ->
    ExprToks = lists:sum([element(2, (element(1,R)))||R<-ExprRanges]),
    case ExprToks of 
	0 ->
	    0;
	_ ->
	    1-((num_of_tokens(SubExprs)-length(SubExprs))/ExprToks)
    end.
    
num_of_tokens(Exprs) ->
   lists:sum([num_of_tokens_in_string(format(E))
	      ||E<-Exprs]).


num_of_tokens_in_string(Str) ->
    case wrangler_scan:string(Str, {1,1}, 8, 'unix') of
	{ok, Ts, _} -> 
            Ts1 = [T||T<-Ts],
	    length(Ts1);
	_ ->
	    0
    end.

remove_sub_clone_pairs([]) ->[];
remove_sub_clone_pairs(CPs) ->
    SortedCPs = lists:sort(fun({Rs1,_,_}, {Rs2, _, _}) ->
					  length(Rs1)>length(Rs2)
				  end, CPs),
    remove_sub_clone_pairs(SortedCPs, []).
remove_sub_clone_pairs([], Acc) ->
    lists:reverse(Acc);
remove_sub_clone_pairs([CP={Rs, _,_}|CPs], Acc) ->
    case lists:any(fun({Rs1, _,_}) ->
			   Rs--Rs1==[] 
		   end, Acc) of
	true ->
	    remove_sub_clone_pairs(CPs,Acc);
	_ -> remove_sub_clone_pairs(CPs, [CP|Acc])
    end.
	
%% derive clone classes from clone pairs.	
get_clone_classes(ClonePairs,Thresholds) ->
    RangeGroups = lists:usort([Rs1 || {Rs1, _Rs2, _Subst} <- ClonePairs]),
    CloneClasses = lists:append([get_one_clone_class(Range, ClonePairs, Thresholds) 
				 || Range <- RangeGroups]),
    lists:keysort(2, CloneClasses).
 
get_one_clone_class(RangeWithExprAST, ClonePairs, Thresholds) ->
    Res = lists:append([get_one_clone_class_1(RangeWithExprAST, ClonePair)
			|| ClonePair <- ClonePairs]),
    CloneClasses =group_clone_pairs(Res, Thresholds),
    [begin
	 {Range, Exprs} = lists:unzip(RangeWithExprAST),
	 [{{FName, FunName, Arity, _}, _, _,_}| _] = Range,
	 VarTab = var_tab,
	 VarsToExport = get_vars_to_export(Exprs, {FName, FunName, Arity}, VarTab),
	 {Ranges, ExportVars, SubSt} = lists:unzip3(C),
	 %% VarstoExport format : [{name, pos}].
	 ExportVars1 = {element(1, lists:unzip(VarsToExport)), 
			lists:usort(lists:append(ExportVars))},
	 {[RangeWithExprAST| Ranges], {length(Exprs), length(Ranges) + 1}, 
	  {Exprs, SubSt, ExportVars1}}
     end
     || C<-CloneClasses].

    
get_one_clone_class_1(RangeWithExprAST, _ClonePair = {Range1, Range2, Subst}) ->
    case RangeWithExprAST -- Range1 == [] of
      true ->
	    %% Range is a sub list of Range1.
	    Len = length(RangeWithExprAST),
	    R = hd(RangeWithExprAST),
	    StartIndex=length(lists:takewhile(fun (R0) -> R0 /= R end, Range1))+1,
	    SubRange2 = lists:sublist(Range2, StartIndex, Len),
	    SubSubst = lists:append(lists:sublist(Subst, StartIndex, Len)),
	    {_, Exprs2} = lists:unzip(SubRange2),
	    [{{{FName, FunName, Arity, _}, _, _, _},_}| _] = SubRange2,
	    VarTab = var_tab,
	    VarsToExport2 = get_vars_to_export(Exprs2, {FName, FunName, Arity}, VarTab),
	    %% Exprs from the first member of the clone pair which are going to 
            %% be replaced by new variables, and the new variables will be exported.
	    EVs = [E1 || {E1, E2} <- SubSubst, wrangler_syntax:type(E2) == variable,
			 lists:member({wrangler_syntax:variable_name(E2), get_var_define_pos(E2)},
				      VarsToExport2)],
	    %% EVs are variables from Exprs1 that need to be exported.
	    NumOfNewVars = num_of_new_vars(SubSubst),
	    [{{SubRange2, EVs, SubSubst},NumOfNewVars}];
      	false ->
	    []
    end.

group_clone_pairs(ClonePairs, Thresholds) ->
    ClonePairs1=lists:keysort(2,ClonePairs),
    group_clone_pairs(ClonePairs1, Thresholds, []).

group_clone_pairs([], _, Acc) ->
    lists:reverse(Acc);
group_clone_pairs(ClonePairs, Thresholds, Acc) ->
    MinFreq= Thresholds#threshold.min_freq -1,
    {NewCs, LeftPairs}=group_clone_pairs(ClonePairs,Thresholds, sets:new(),[],[]),
    NewAcc = case length(NewCs)>=MinFreq of
		 true->[NewCs|Acc];
		 false ->
		     Acc
	     end,
    case length(LeftPairs)<MinFreq of 
	true ->
	    NewAcc;
	false ->
	    group_clone_pairs(LeftPairs, Thresholds, NewAcc)
    end.

group_clone_pairs([], _, _, Acc, LeftPairs) ->
    {lists:reverse(Acc), lists:reverse(LeftPairs)};
group_clone_pairs([CP={C={_R, _EVs, Subst}, NumOfNewVars}|T], Thresholds, ExprsToBeGenAcc, Acc, LeftPairs) ->
    MaxNewVars = Thresholds#threshold.max_new_vars,
    ExprsToBeGen=exprs_to_be_generalised(Subst),
    NewExprsToBeGenAcc =sets:union(ExprsToBeGen, ExprsToBeGenAcc),
    case sets:size(NewExprsToBeGenAcc)=<MaxNewVars of
    	true ->
	    group_clone_pairs(T, Thresholds, NewExprsToBeGenAcc, [C|Acc], LeftPairs);
	false ->
	    case NumOfNewVars>MaxNewVars of 
		true ->
		    group_clone_pairs([], Thresholds, ExprsToBeGenAcc, Acc, LeftPairs);
		false ->
		    group_clone_pairs(T, Thresholds, ExprsToBeGenAcc, Acc, [CP|LeftPairs])
	    end
    end.

%% This is not accurate, and will be improved!
exprs_to_be_generalised(SubSt) ->
    sets:from_list([wrangler_prettypr:format(wrangler_misc:reset_ann_and_pos(E1))
		    || {E1,_E2} <- SubSt, wrangler_syntax:type(E1) /= variable]).

num_of_new_vars(SubSt) ->
    length(lists:usort([{wrangler_prettypr:format(wrangler_misc:reset_ann_and_pos(E1)), 
                         wrangler_prettypr:format(wrangler_misc:reset_ann_and_pos(E2))}
			|| {E1,E2} <- SubSt, wrangler_syntax:type(E1) /= variable])).


format(Node) ->
    wrangler_prettypr:format(wrangler_misc:reset_ann_and_pos(Node)).
    
    

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                                  %%
%%  Attach function call to each class member                       %%
%%                                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
attach_fun_call_to_range(RangesWithAST,{AU, Pars}, FromSameFile) ->
    RangesWithFunCalls=[generate_fun_call_1(RangeWithAST, AU, FromSameFile) 
			|| RangeWithAST <- RangesWithAST],
    {lists:append(RangesWithFunCalls),{simplify_anti_unifier(AU),Pars}}.

generate_fun_call_1(RangeWithAST, AUForm, FromSameFile) ->
    {Range, Exprs} = lists:unzip(RangeWithAST),
    AUFunClause=hd(wrangler_syntax:function_clauses(AUForm)),
    Pats = wrangler_syntax:clause_patterns(AUFunClause),
    AUBody = wrangler_syntax:clause_body(AUFunClause),
    try 
	%% it would be a bug if this does not match. 
	{true, Subst} = 
	    case length(AUBody) - length(Exprs) of 
		1 ->
		    SubAUBody = lists:reverse(tl(lists:reverse(AUBody))),
		    wrangler_unification:expr_unification_extended(SubAUBody, Exprs);
		0 ->
		    wrangler_unification:expr_unification_extended(AUBody, Exprs)
	    end,
	%% Need to check side-effect here. but it is a bit slow!!!
	FunCall=make_fun_call(new_fun, Pats, Subst, FromSameFile),
	[{Range, format(FunCall)}]
    catch 
	_E1:_E2 ->
	    [] %%"wrangler-failed-to-generate-the-function-application."
    end.

make_fun_call(FunName, Pats, Subst, FromSameFile) ->
    Fun = fun (P) ->
		  case wrangler_syntax:type(P) of
		      variable ->
			  PName = wrangler_syntax:variable_name(P),
			  case lists:keysearch(PName, 1, Subst) of
			      {value, {PName, Par}} ->
				  case wrangler_syntax:type(Par) of
				      atom ->
					  case FromSameFile of
					      true -> Par;
					      false ->
						  As = wrangler_syntax:get_ann(Par),
						  case lists:keysearch(fun_def, 1, As) of
						      {value, {fun_def, {M, _F, A, _, _}}} ->
							  case M== erlang orelse M=='_' of
							      true ->
								  Par;
							      false ->
								  Mod = wrangler_syntax:atom(M),
								  ModQualifier = wrangler_syntax:module_qualifier(Mod, Par),
								  wrangler_syntax:implicit_fun(ModQualifier, wrangler_syntax:integer(A))
							  end;
						      _ -> Par
						  end
					  end;
				      module_qualifier ->
					  As = wrangler_syntax:get_ann(Par),
					  case lists:keysearch(fun_def, 1, As) of
					      {value, {fun_def, {_M, _F, A, _, _}}} ->
						  wrangler_syntax:implicit_fun(Par, wrangler_syntax:integer(A));
					      _ -> Par   %% This should not happen!
					  end;
				      application ->
					  wrangler_syntax:fun_expr([wrangler_syntax:clause([], none, [Par])]);
				      _ -> Par
				  end;
			      _ ->
				  wrangler_syntax:atom(undefined)
			  end;
		      underscore ->
			  wrangler_syntax:atom(undefined);
		      _ -> P
		  end
	  end,
    Pars = lists:map(Fun, Pats),
    Op = wrangler_syntax:atom(FunName),
    wrangler_misc:reset_attrs(wrangler_syntax:application(Op, [P || P <- Pars])).

	 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                                  %%
%%  Remove sub-clones                                               %%
%%                                                                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
remove_sub_clones(Cs) ->
    remove_sub_clones(lists:reverse(lists:keysort(2,Cs)),[]).
remove_sub_clones([], Acc_Cs) ->
    lists:reverse(Acc_Cs);
remove_sub_clones([C|Cs], Acc_Cs) ->
    case is_sub_clone(C, Acc_Cs) of
	true -> 
	    remove_sub_clones(Cs, Acc_Cs);
	false ->remove_sub_clones(Cs, [C|Acc_Cs])
    end.

is_sub_clone({Ranges, {Len, Freq},Str,AbsRanges}, ExistingClones) ->
    case ExistingClones of 
	[] -> false;
	[{Ranges1, {_Len1, _Freq1}, _, _AbsRanges1}|T] ->
	    case is_sub_ranges(Ranges, Ranges1) of 
		true -> 
		    true;
		false -> is_sub_clone({Ranges, {Len, Freq},Str, AbsRanges}, T)
	    end
	end;

is_sub_clone({Ranges, {Len, Freq},Str}, ExistingClones) ->
    case ExistingClones of 
	[] -> false;
	[{Ranges1, {_Len1, _Freq1}, _}|T] ->
	    case is_sub_ranges(Ranges, Ranges1) of 
		true -> 
		    true;
		false -> is_sub_clone({Ranges, {Len, Freq},Str}, T)
	    end
    end;
is_sub_clone({Ranges, {Len, Freq}}, ExistingClones) ->
    case ExistingClones of 
	[] -> false;
	[{Ranges1, {_Len1, _Freq1}}|T] ->
	    case is_sub_ranges(Ranges, Ranges1) of 
		true -> 
		    true;
		false -> is_sub_clone({Ranges, {Len, Freq}}, T)
	    end
    end.

is_sub_ranges(Ranges1, Ranges2) ->
    lists:all(fun (R1)  -> 
		      lists:any(fun (R2) ->
					R1--R2==[]
				end, Ranges2) 
	      end, Ranges1).


get_var_define_pos(V) ->
    {value, {def, DefinePos}} = lists:keysearch(def, 1, wrangler_syntax:get_ann(V)),
    DefinePos.

get_anti_unifier({Exprs, SubSt, ExportVars}, FromSameFile) ->
    {AU, {NumOfPars, NumOfNewVars}} =wrangler_anti_unification:generate_anti_unifier_and_num_of_new_vars(
                                                Exprs, SubSt, ExportVars),
    case FromSameFile of
	true -> 
	    {AU,{NumOfPars, NumOfNewVars}};
	false ->
	    {post_process_anti_unifier(AU),{NumOfPars, NumOfNewVars}}
    end.
    
from_same_file(RangesWithAST) ->   
    Files = [element(1,element(1,(element(1,hd(Rs)))))||Rs<-RangesWithAST],
    length(lists:usort(Files)) ==1.

post_process_anti_unifier(FunAST) ->
    {FunAST1, _} = api_ast_traverse:stop_tdTP(fun do_post_process_anti_unifier/2, FunAST, none),
    FunAST1.

do_post_process_anti_unifier(Node, _Others) ->
    case wrangler_syntax:type(Node) of
	application ->
	    Operator = wrangler_syntax:application_operator(Node),
	    Arguments = wrangler_syntax:application_arguments(Node),
	    case wrangler_syntax:type(Operator) of
		atom ->
		    As = wrangler_syntax:get_ann(Operator),
		    {value, {fun_def, {M, _F, _A, _, _}}} = lists:keysearch(fun_def,1,As),
		    case M== erlang orelse M=='_' of
			true ->
			    {Node, false};
			false ->
			    Mod = wrangler_syntax:atom(M),
			    Operator1 = wrangler_misc:rewrite(Operator, wrangler_syntax:module_qualifier(Mod, Operator)),
			    Node1 = wrangler_misc:rewrite(Node, wrangler_syntax:application(Operator1, Arguments)),
			    {Node1, false}
		    end;
		_ ->
		    {Node, false}
	    end;
	_ -> {Node, false}
    end.


get_clone_member_start_end_loc(Range)->
    {{File, _, _, _}, _Toks, {{{Line1, Col1},_},StartLine},_} = hd(Range),
    {_ExprKey1, _Toks1,{{_, {Line2, Col2}}, StartLine},_}= lists:last(Range),
    {{File, Line1+StartLine-1, Col1}, {File, Line2+StartLine-1, Col2}}.
  
get_clone_class_in_absolute_locs({Ranges, {Len, Freq}, AntiUnifier}) ->
    StartEndLocsWithFunCall = [{get_clone_member_start_end_loc(R),FunCall}|| {R, FunCall} <- Ranges],
    RangesWithoutFunCalls=[R||{R,_}<-Ranges],
    {RangesWithoutFunCalls, {Len, Freq}, AntiUnifier,StartEndLocsWithFunCall}.

get_vars_to_export(Es, {FName, FunName, Arity}, VarTab) ->
    AllVars = ets:lookup(VarTab, {FName, FunName, Arity}),
    {_, EndLoc} = wrangler_misc:start_end_loc(lists:last(Es)),
    case AllVars of
	[] -> [];
	[{_, _, Vars}] ->
	    ExprBdVarsPos = [Pos || {_Var, Pos} <- api_refac:bound_vars(Es)],
	    [{V, DefPos} || {V, SourcePos, DefPos} <- Vars,
			    SourcePos > EndLoc,
			    lists:subtract(DefPos, ExprBdVarsPos) == []]
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%                                                            %%
%%        Search for cloned candidates                        %%
%%                                                            %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

integer_list_to_string(Is) ->
    integer_list_to_string(Is, "").
integer_list_to_string([], Acc) ->
    lists:reverse("\n\r$,"++Acc);
integer_list_to_string([I], Acc) ->
    S= case is_integer(I) of
	   true ->
	       integer_to_list(I);
	   false ->
	       atom_to_list(I)
       end,
    integer_list_to_string([], lists:reverse(S)++Acc);
integer_list_to_string([I|Is], Acc) ->
     S= case is_integer(I) of
	   true ->
		","++lists:reverse(integer_to_list(I));
	    false ->
		lists:reverse(atom_to_list(I))
	end,
    integer_list_to_string(Is, S++Acc).

    
search_for_clones(Dir, Thresholds) ->
    MinLen = Thresholds#threshold.min_len,
    MinFreq= Thresholds#threshold.min_freq,
    NumOfIndexStrs=integer_to_list(ets:info(expr_seq_hash_tab, size))++"\r\n",
    Data = ets:tab2list(expr_seq_hash_tab),
    case Data of 
        [] ->
            OutFileName = filename:join(Dir, "wrangler_suffix_tree"),
            write_file(OutFileName, []),
            {ok, OutFileName};
        _ ->
            IndexStr = NumOfIndexStrs++lists:append([integer_list_to_string(Is)
                                                     ||{_SeqNo, _FFA, ExpHashIndexPairs} <- Data,
                                                       {_, Is}<-[lists:unzip(ExpHashIndexPairs)]]),
            SuffixTreeExec = filename:join(code:priv_dir(wrangler), "gsuffixtree"),
            wrangler_suffix_tree:get_clones_by_suffix_tree_inc(Dir, IndexStr, MinLen,
                                                               MinFreq, 1, SuffixTreeExec)
    end.
   
remove_short_clones(_C={Rs, {Len, _Freq}}, MinToks, MinFreq) ->
    Rs1=[R||R<-Rs, NumToks<-[[element(2, Elem)||Elem<-R]],
	    lists:sum(NumToks)>=MinToks],
    Freq1 = length(Rs1),
    case Freq1>=MinFreq of
	true ->
	    [{Rs1, {Len, Freq1}}];
	false->
	    []
    end.

   
no_of_tokens(Node) when is_list(Node)->
    Str = format(wrangler_syntax:block_expr(Node)),
    {ok, Toks, _}=wrangler_scan:string(Str, {1,1}, 8, unix),
    length(Toks)-2;
no_of_tokens(Node) ->
    Str = format(Node),
    {ok, Toks, _} =wrangler_scan:string(Str, {1,1}, 8, unix),
    length(Toks).

combine_clones_by_au([]) -> [];
combine_clones_by_au(Cs = [{_Ranges, _Len, _F, _Code}| _T]) ->
    Cs1 = wrangler_misc:group_by(4, Cs),
    combine_clones_by_au_1(Cs1,[]).

combine_clones_by_au_1([], Acc) ->
    Acc;
combine_clones_by_au_1([Cs=[{_Ranges, Len, _Freq, Code}|_]|T], Acc) ->
    NewRanges=sets:to_list(sets:from_list(lists:append([Rs||{Rs, _, _, _}<-Cs]))),
    NewFreq = length(NewRanges),
    combine_clones_by_au_1(T, [{NewRanges, Len, NewFreq, Code}|Acc]).
    
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%     transform the absolute locations in an AST to          %%
%%     relative locations                                     %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
absolute_to_relative_loc(AST, OffLine) ->
    {AST1, _} = api_ast_traverse:full_tdTP(fun do_abs_to_relative_loc/2,
					   AST, OffLine),
    AST1.
do_abs_to_relative_loc(Node, OffLine) ->
    As = wrangler_syntax:get_ann(Node),
    As1 = [abs_to_relative_loc_in_ann(A, OffLine) || A <- As],
    {L, C} = wrangler_syntax:get_pos(Node),
    Node1 = wrangler_syntax:set_pos(Node, {to_relative(L, OffLine), C}),
    {wrangler_syntax:set_ann(Node1, As1), true}.

abs_to_relative_loc_in_ann(Ann, StartLine) ->
    case Ann of
	{range, {{L1, C1},{L2, C2}}} ->
	    {range, {{to_relative(L1,StartLine), C1}, 
		     {to_relative(L2,StartLine), C2}}};
	{bound, Vars} ->
	    {bound, [{V, {to_relative(L,StartLine),C}}||{V, {L,C}}<-Vars]};
	{free, Vars} ->
	    {free, [{V, {to_relative(L,StartLine),C}}||{V, {L,C}}<-Vars]};
	{def, Locs} ->
	    {def, [{to_relative(L,StartLine),C}||{L, C}<-Locs]};
	{fun_def, {M, F, A,{L1, C1},{L2, C2}}} ->
	    {fun_def, {M, F, A, {to_relative(L1,StartLine),C1}, 
		       {to_relative(L2,StartLine), C2}}};
	%% the following has nothing to do with locations,
	%% just remove some information not to be used from 
        %% from the AST.
	{toks, _} ->  
	    {toks, []};
	{env, _} ->
	    {env, []};
	_ -> Ann
    end.
to_relative(Line, StartLine) when Line>0->
    Line-StartLine+1;
to_relative(Line, _StartLine) -> 
    Line.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%       Simplify the anti unifier generated                  %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% simplify the anti unifier generated. 
%% currently, only check the last two expressions, and simplify:
%% Pats = Expr, Pats  to  Expr.
simplify_anti_unifier(AUForm) ->
    AUFunClause=hd(wrangler_syntax:function_clauses(AUForm)),
    FunName = wrangler_syntax:function_name(AUForm),
    Pats = wrangler_syntax:clause_patterns(AUFunClause),
    AUBody = wrangler_syntax:clause_body(AUFunClause),
    AUBody1 = simplify_anti_unifier_body(AUBody),
    C = wrangler_syntax:clause(Pats, none, AUBody1),
    NewAU=wrangler_syntax:function(FunName, [C]),
    format(NewAU).
    
simplify_anti_unifier_body(AUBody) when length(AUBody)<2 ->
    AUBody;
simplify_anti_unifier_body(AUBody) ->
    [E1,E2|Exprs] = lists:reverse(AUBody),
    case wrangler_syntax:type(E2) of
	match_expr ->
	    {E2Pat, E2Body} = {wrangler_syntax:match_expr_pattern(E2),
			       wrangler_syntax:match_expr_body(E2)},
	    case same_expr(E2Pat, E1) of
		true ->
		    lists:reverse([E2Body|Exprs]);
		false ->
		    AUBody
	    end;
	_ -> AUBody
    end.

same_expr(Expr1, Expr2) ->
    {ok, Ts1, _} = erl_scan:string(format(Expr1)),
    {ok, Ts2, _} = erl_scan:string(format(Expr2)),
    wrangler_misc:concat_toks(Ts1) == wrangler_misc:concat_toks(Ts2).


-spec(check_parameters/5::(MinLen :: integer(), MinToks :: integer(),
                           MinFreq :: integer(), MaxNewVars :: integer(),
                           SimiScore :: float()) -> 
                              {integer(), integer(), integer(), integer(),
                               float()}).
check_parameters(MinLen1,MinToks1,MinFreq1,MaxNewVars1,SimiScore1) ->
    MinLen = case MinLen1<1 of
	       true ->
		   ?DEFAULT_LEN;
	       _ -> MinLen1
	     end, 
    MinFreq = case MinFreq1<?DEFAULT_FREQ of
		true ->
		    ?DEFAULT_FREQ;
		_ -> MinFreq1
	      end, 
    MinToks = case MinToks1< ?MIN_TOKS of
		true -> ?MIN_TOKS;
		_ -> MinToks1
	      end, 
    MaxNewVars = case MaxNewVars1<0 of
		   true ->
		       ?DEFAULT_NEW_VARS;
		   _ -> MaxNewVars1
		 end, 
    SimiScore = case SimiScore1>=0.1 andalso SimiScore1=<1.0 of
		  true -> SimiScore1;
		  _ -> ?DefaultSimiScore
		end, 
    {MinLen,MinToks,MinFreq,MaxNewVars,SimiScore}.


write_file(File, Data) ->
    case File of 
	none ->
	    ok;
	_->
	    file:write_file(File, Data)
    end.


display_clones_by_freq(_Cs, _Str) ->
    ?wrangler_io("\n===================================================================\n",[]),
    ?wrangler_io(_Str ++ " Code Detection Results Sorted by the Number of Code Instances.\n",[]),
    ?wrangler_io("======================================================================\n",[]),		 
    _Cs1 = lists:reverse(lists:keysort(3, _Cs)),
    ?wrangler_io(display_clones(_Cs1, _Str),[]).


display_clones(Cs, _Str) ->
    Num = length(Cs),
    ?wrangler_io("\n" ++ _Str ++ " detection finished with *** ~p *** clone(s) found.\n", [Num]),
    case Num of 
	0 -> ok;
	_ -> display_clones_1(Cs,1)
    end.

display_clones_1([],_) ->
    ?wrangler_io("\n",[]),
    ok;
display_clones_1([C|Cs], Num) ->
    display_a_clone(C, Num),
    display_clones_1(Cs, Num+1).
  

display_a_clone(_C={Ranges, _Len, F,{Code, _}},Num) ->
    NewStr1 = make_clone_info_str(Ranges, F, Code, Num),
    ?wrangler_io("~s", [NewStr1]);
display_a_clone(_C={Ranges, _Len, F,Code},Num) ->
    NewStr1 = make_clone_info_str(Ranges, F, Code, Num),
    ?wrangler_io("~s", [NewStr1]);
display_a_clone(_C={Ranges, _Len, F,{Code, _}, ChangeStatus},Num) ->
    [R| _Rs] = lists:keysort(1, Ranges),
    NewStr = compose_clone_info(R, F, Ranges, "", Num, ChangeStatus),
    NewStr1 = NewStr ++ "The cloned expression/function after generalisation:\n\n" ++ Code,
    ?wrangler_io("~s", [lists:flatten(NewStr1)]).

make_clone_info_str(Ranges, F, Code, Num) ->
    [R | _Rs] = lists:keysort(1, Ranges),
    NewStr = compose_clone_info(R, F, Ranges, "", Num),
    NewStr ++"The cloned expression/function after generalisation:\n\n" ++Code.


compose_clone_info(_, F, Range, Str, Num) ->
    case F of
	2 -> 
            case Num of 
                0 ->
                    Str1 = "\n\nClone found. This code appears twice :\n",
                    display_clones_2(Range, Str1);
                _ ->
                    Str1 =Str ++ "\n\n" ++"Clone "++io_lib:format("~p. ", [Num])++ "This code appears twice:\n",
                    display_clones_2(Range, Str1)
            end;
	_ -> 
            case Num of
                0 ->
                    Str1 = "\n\nClone found. "++  io_lib:format("This code appears ~p times:\n",[F]),
                    display_clones_2(Range, Str1);
                _ ->                     
                    Str1 =Str ++ "\n\n" ++"Clone "++io_lib:format("~p. ", [Num])++ 
                        io_lib:format("This code appears ~p times:\n",[F]),
                    display_clones_2(Range, Str1)
             end
    end.
compose_clone_info(_, F, Range, Str, Num, ChangeStatus) ->
    case F of
	2 ->
            case Num of 
                0 ->
                    Str1 = "\n\nClone found. This code appears twice :\n",
                    display_clones_2(Range, Str1);
                _ ->
                    Str1 =Str ++ "\n\n" ++"Clone "++io_lib:format("~p. ", [Num])++ io_lib:format("~p:", [ChangeStatus])
                        ++ " This code appears twice:\n",
                    display_clones_2(Range, Str1)
            end;
	_ -> 
            case Num of 
                0 ->
                    Str1 = "\n\nClone found. "++  io_lib:format("This code appears ~p times:\n",[F]),
                    display_clones_2(Range, Str1);
                _ ->
                    Str1 =Str ++ "\n\n" ++"Clone "++io_lib:format("~p. ", [Num])++io_lib:format("~p:", [ChangeStatus])++ 
                        io_lib:format("This code appears ~p times:\n",[F]),
                    display_clones_2(Range, Str1)
            end
    end.


display_clones_2([], Str) -> Str ++ "\n";
display_clones_2([{{File, StartLine, StartCol}, {File, EndLine, EndCol}}|Rs], Str) ->
    Str1 =Str ++ File++io_lib:format(":~p.~p-~p.~p:\n", [StartLine, lists:max([1,StartCol-1]), EndLine, EndCol]),
    display_clones_2(Rs, Str1);
display_clones_2([{{{File, StartLine, StartCol}, {File, EndLine, EndCol}}, FunCall}|Rs], Str) ->
    Str1 = Str ++ File++io_lib:format(":~p.~p-~p.~p:", [StartLine,lists:max([1, StartCol-1]),EndLine, EndCol])++
	" \n   "++ FunCall ++ "\n",
    display_clones_2(Rs, Str1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

parse_files() ->
    quick_parse_annotate_file("./test/refac_api.erl", [], 8).
    
quick_parse_annotate_file(FName, SearchPaths, TabWidth) ->
    FileFormat = file_format(FName),
    case parse_a_file(FName, TabWidth, FileFormat) of
	{ok, Forms} ->
	    Dir = filename:dirname(FName),
	    DefaultIncl2 = [filename:join(Dir, X) || X <- wrangler_misc:default_incls()],
	    Includes = SearchPaths ++ DefaultIncl2,
	    Ms = get_macros(FName, TabWidth, FileFormat, Includes),
	    SyntaxTree = recomment_forms(Forms),
	    Info = analyze_forms(SyntaxTree),
	    AnnAST = annotate_bindings(FName, SyntaxTree, Info, Ms, TabWidth),
	    {ok, {AnnAST, Info}};
	{error, Reason} -> erlang:error(Reason)
    end.

annotate_bindings(FName, AST, Info, Ms, TabWidth) ->
    Toks = wrangler_misc:tokenize(FName, true, TabWidth),
    AnnAST0 = wrangler_syntax_lib:annotate_bindings(add_token_and_ranges(AST, Toks), ordsets:new(), Ms),
    Comments = wrangler_comment_scan:file(FName, TabWidth),
    AnnAST1= wrangler_recomment:recomment_forms(AnnAST0, Comments),
    AnnAST2 =update_toks(Toks,AnnAST1),
    wrangler_annotate_ast:add_fun_define_locations(AnnAST2, Info).

analyze_forms(SyntaxTree) ->
    wrangler_syntax_lib:analyze_forms(SyntaxTree).

recomment_forms(Forms) -> wrangler_recomment:recomment_forms(Forms, []).

get_macros(FName, TabWidth, FileFormat, Includes) ->
    case wrangler_epp:parse_file(FName, Includes, [], TabWidth, FileFormat) of
	{ok, _, {MDefs, MUses}} ->
	    {dict:from_list(MDefs), dict:from_list(MUses)};
	_ -> []
    end.

parse_a_file(FName, TabWidth, FileFormat) ->
    wrangler_epp_dodger:parse_file(FName, [{tab, TabWidth}, {format, FileFormat}]).


file_format(FName) ->
    wrangler_misc:file_format(FName).


add_token_and_ranges(SyntaxTree, Toks) ->
    Fs = wrangler_syntax:form_list_elements(SyntaxTree),
    NewFs = do_add_token_and_ranges(Toks, Fs),
    SyntaxTree1= rewrite(SyntaxTree, wrangler_syntax:form_list(NewFs)),
    add_range_to_body(SyntaxTree1, NewFs, "", "").

    
%% do it backwards starting from the last form. 
%% all the white spaces after a form belong to the next form if
%% there is one. 

update_toks(Toks, AnnAST) ->
    Fs = wrangler_syntax:form_list_elements(AnnAST),
    NewFs=do_update_toks(lists:reverse(Toks), lists:reverse(Fs), []),
    rewrite(AnnAST, wrangler_syntax:form_list(NewFs)).

do_update_toks(_, [], NewFs) ->
    NewFs;
do_update_toks(Toks, _Forms=[F|Fs], NewFs) ->
    {FormToks0, RemToks} = get_form_tokens(Toks, F, Fs), 
    FormToks = lists:reverse(FormToks0),
    F1 = update_ann(F, {toks, FormToks}),
    do_update_toks(RemToks, Fs, [F1| NewFs]).

do_add_token_and_ranges(Toks, Fs) ->
    do_add_token_and_ranges1(lists:reverse(Toks), lists:reverse(Fs)).

do_add_token_and_ranges1(Toks, Forms) ->
    FormTokenPairs = get_form_tokens1(Toks, Forms,[]),
    para_lib:pmap(fun({Form, FormToks}) ->
                          FormToks1 = lists:reverse(FormToks),
                          Form1 = update_ann(Form, {toks, FormToks1}),
                          add_category(add_range(Form1, FormToks1))
                  end, FormTokenPairs).
get_form_tokens1(_Toks, [], Acc) ->
    Acc;
get_form_tokens1(Toks, [F|Fs], Acc) ->
    {FormToks, RemToks} = get_form_tokens(Toks,F, Fs),
    get_form_tokens1(RemToks, Fs, [{F, FormToks}|Acc]).

                          
%% do_add_token_and_ranges(_, [], NewFs) ->
%%     NewFs;
%% do_add_token_and_ranges(Toks, _Forms=[F| Fs], NewFs) ->
%%     {FormToks0, RemToks} = get_form_tokens(Toks, F, Fs), 
%%     FormToks = lists:reverse(FormToks0),
%%     F1 = update_ann(F, {toks, FormToks}),
%%     F2 = add_category(add_range(F1, FormToks)),
%%     do_add_token_and_ranges(RemToks, Fs, [F2| NewFs]).

get_form_tokens(Toks, F, Fs) ->
    case wrangler_syntax:type(F) of
	comment ->
	    get_comment_form_toks(Toks, F, Fs);
	_ ->
	    get_non_comment_form_toks(Toks, F, Fs) 
    end.

%% stand-alone comments.
get_comment_form_toks(Toks, _F, Fs) when Fs==[] ->
    {Toks,[]};
get_comment_form_toks(Toks, F, _Fs) ->
    StartPos =start_pos(F),
    {Ts1,Ts2} = lists:splitwith(
		  fun(T) ->
			  token_loc(T)>=StartPos andalso 
			   is_whitespace_or_comment(T)
		  end, Toks),
    {Ts21, Ts22} = lists:splitwith(fun(T) ->
					   is_whitespace(T)
				   end, Ts2),
    {Ts1++Ts21, Ts22}.
 
get_non_comment_form_toks(Toks, _F, Fs) when Fs==[] ->
    {Toks, []};
get_non_comment_form_toks(Toks, F, _Fs) ->
    StartPos = start_pos(F),
    {Ts1, Ts2} = lists:splitwith(
		   fun(T) ->
			   token_loc(T)>=StartPos
		   end, Toks),
    {Ts21, Ts22} = lists:splitwith(
		     fun(T) ->
			     element(1, T) /=dot andalso
				 element(1,T)/=comment
		     end, Ts2),
    {Ts1++Ts21, Ts22}.

start_pos(F) ->
    case wrangler_syntax:type(F) of
	error_marker ->
	    case wrangler_syntax:revert(F) of
		{error, {_, {{Line, Col}, {_Line1, _Col1}}}} ->
		    {Line, Col};
		_ ->
		    wrangler_syntax:get_pos(F)
	    end;
	_ ->
	    case wrangler_syntax:get_precomments(F) of
		[] ->
		    wrangler_syntax:get_pos(F);
		[Com| _Tl] ->
		    wrangler_syntax:get_pos(Com)
	    end
    end.

%%-spec add_range(syntaxTree(), [token()]) -> syntaxTree(). 
add_range(AST, Toks) ->
    QAtomPs= [Pos||{qatom, Pos, _Atom}<-Toks],
    Toks1 =[Tok||Tok<-Toks, not (is_whitespace_or_comment(Tok))],
    api_ast_traverse:full_buTP(fun do_add_range/2, AST, {Toks1, QAtomPs}).

do_add_range(Node, {Toks, QAtomPs}) ->
    {L, C} = case wrangler_syntax:get_pos(Node) of
		 {Line, Col} -> {Line, Col};
		 Line -> {Line, 0}
	     end,
    case wrangler_syntax:type(Node) of
	variable ->
	    Len = length(wrangler_syntax:variable_literal(Node)),
	    update_ann(Node, {range, {{L, C}, {L, C + Len - 1}}});
	atom ->
            case lists:member({L,C}, QAtomPs) orelse 
                lists:member({L,C+1}, QAtomPs) of  
                true ->
                    Len = length(atom_to_list(wrangler_syntax:atom_value(Node))),
                    Node1 = update_ann(Node, {qatom, true}),
                    update_ann(Node1, {range, {{L, C}, {L, C + Len + 1}}});
                false ->
                    Len = length(atom_to_list(wrangler_syntax:atom_value(Node))),
                    update_ann(Node, {range, {{L, C}, {L, C + Len - 1}}})
	    end;
        operator ->
	    Len = length(atom_to_list(wrangler_syntax:atom_value(Node))),
	    update_ann(Node, {range, {{L, C}, {L, C + Len - 1}}});
	char -> update_ann(Node, {range, {{L, C}, {L, C}}});
	integer ->
            Len = length(wrangler_syntax:integer_literal(Node)),
	    update_ann(Node, {range, {{L, C}, {L, C + Len - 1}}});
	string ->
            Toks1 = lists:dropwhile(fun (T) -> 
                                            token_loc(T) < {L, C} 
                                    end, Toks),
            {Toks21, _Toks22} = lists:splitwith(fun (T) -> 
                                                       is_string(T) orelse 
                                                           is_whitespace_or_comment(T)
                                               end, Toks1),
	    Toks3 = lists:filter(fun (T) -> is_string(T) end, Toks21),
            Str = case Toks3 of 
                      [] -> wrangler_syntax:string_value(Node);
                      _ -> element(3, lists:last(Toks3))
                  end,
            Lines = wrangler_syntax_lib:split_lines(Str),
            {NumOfLines, LastLen}= 
                case Lines of 
                    [] -> 
                        {1, 0};
                    _ ->
                        {length(Lines),length(lists:last(Lines))}
                end,
            case Toks3 of 
                [] ->  %% this might happen with attributes when the loc info is not accurate.
                    Range = {{L, C}, {L+NumOfLines-1, C+LastLen+1}},
                    update_ann(Node, {range, Range});
                _ ->
                    {string, {L1, C1}, _} = lists:last(Toks3),
                    L2 = L1+NumOfLines-1,
                    C2 = case NumOfLines of
                             1 -> C1+LastLen+1;
                             _ -> LastLen+1
                         end,
                    Range ={token_loc(hd(Toks3)),{L2, C2}},
                    Node1 = update_ann(Node, {range, Range}),
                    update_ann(Node1, {toks, Toks3})
            end;
        float ->
	    update_ann(Node,
	               {range, {{L, C}, {L, C}}}); %% This is problematic.
	underscore -> update_ann(Node,
	                         {range, {{L, C}, {L, C}}});
        eof_marker -> update_ann(Node,
                                 {range, {{L, C}, {L, C}}});
        nil -> update_ann(Node, {range, {{L, C}, {L, C + 1}}});
	module_qualifier ->
            Arg = wrangler_syntax:module_qualifier_argument(Node),
            Field = wrangler_syntax:module_qualifier_body(Node),
            {S1,_E1} = get_range(Arg),
            {_S2,E2} = get_range(Field),
            Node1 = wrangler_syntax:set_pos(Node, S1),
            update_ann(Node1, {range, {S1, E2}});
	list ->  
            Es = list_elements(Node),
            case Es/=[] of
                true ->
                    Last = wrangler_misc:glast("refac_util:do_add_range,list", Es),
                    {_, E2} = get_range(Last),
                    E21 = extend_backwards(Toks, E2, ']'),
                    update_ann(Node, {range, {{L, C}, E21}});
                false ->
                    Node
            end;
        application ->
	    O = wrangler_syntax:application_operator(Node),
	    Args = wrangler_syntax:application_arguments(Node),
	    {S1, E1} = get_range(O),
	    {S3, E3} = case Args of
			   [] -> {S1, E1};
			   _ -> La = wrangler_misc:glast("refac_util:do_add_range, application", Args),
				{_S2, E2} = get_range(La),
				{S1, E2}
		       end,
	    E31 = extend_backwards(Toks, E3, ')'),
	    update_ann(Node, {range, {S3, E31}});
	case_expr ->
            A = wrangler_syntax:case_expr_argument(Node),
	    Lc = wrangler_misc:glast("refac_util:do_add_range,case_expr", wrangler_syntax:case_expr_clauses(Node)),
	    calc_and_add_range_to_node_1(Node, Toks, A, Lc, 'case', 'end');
	clause ->
            {S1,_} = case wrangler_syntax:clause_patterns(Node) of
                          [] -> case wrangler_syntax:clause_guard(Node) of
                                    none ->{{L,C}, {0,0}};
                                    _ -> get_range(wrangler_syntax:clause_guard(Node))
                                end;
                          Ps -> get_range(hd(Ps))
                      end,         
            Body = wrangler_misc:glast("refac_util:do_add_range, clause", wrangler_syntax:clause_body(Node)),
	    {_S2, E2} = get_range(Body),
	    update_ann(Node, {range, {lists:min([S1, {L, C}]), E2}});
	catch_expr ->
	    B = wrangler_syntax:catch_expr_body(Node),
	    {S, E} = get_range(B),
	    S1 = extend_forwards(Toks, S, 'catch'),
	    update_ann(Node, {range, {S1, E}});
	if_expr ->
	    Cs = wrangler_syntax:if_expr_clauses(Node),
	    add_range_to_list_node(Node, Toks, Cs, "refac_util:do_add_range, if_expr",
				   "refac_util:do_add_range, if_expr", 'if', 'end');
	cond_expr ->
	    Cs = wrangler_syntax:cond_expr_clauses(Node),
	    add_range_to_list_node(Node, Toks, Cs, "refac_util:do_add_range, cond_expr",
				   "refac_util:do_add_range, cond_expr", 'cond', 'end');
	infix_expr ->
	    calc_and_add_range_to_node(Node, infix_expr_left, infix_expr_right);
	prefix_expr ->
	    calc_and_add_range_to_node(Node, prefix_expr_operator, prefix_expr_argument);
	conjunction ->
	    B = wrangler_syntax:conjunction_body(Node),
	    add_range_to_body(Node, B, "refac_util:do_add_range,conjunction",
			      "refac_util:do_add_range,conjunction");
	disjunction ->
	    B = wrangler_syntax:disjunction_body(Node),
	    add_range_to_body(Node, B, "refac_util:do_add_range, disjunction",
			      "refac_util:do_add_range,disjunction");
	function ->
	    F = wrangler_syntax:function_name(Node),
	    Cs = wrangler_syntax:function_clauses(Node),
	    Lc = wrangler_misc:glast("refac_util:do_add_range,function", Cs),
	    {S1, _E1} = get_range(F),
	    {_S2, E2} = get_range(Lc),
	    update_ann(Node, {range, {S1, E2}});
	fun_expr ->
	    Cs = wrangler_syntax:fun_expr_clauses(Node),
	    S = wrangler_syntax:get_pos(Node),
	    Lc = wrangler_misc:glast("refac_util:do_add_range, fun_expr", Cs),
	    {_S1, E1} = get_range(Lc),
	    E11 = extend_backwards(Toks, E1,
				   'end'),   %% S starts from 'fun', so there is no need to extend forwards/
	    update_ann(Node, {range, {S, E11}});
	arity_qualifier ->
                calc_and_add_range_to_node(Node, arity_qualifier_body, arity_qualifier_argument);
	implicit_fun ->
                adjust_implicit_fun_loc(Node, Toks);
        attribute ->
	    Name = wrangler_syntax:attribute_name(Node),
	    Args = wrangler_syntax:attribute_arguments(Node),
	    case Args of
		none -> {S1, E1} = get_range(Name),
			S11 = extend_forwards(Toks, S1, '-'),
			update_ann(Node, {range, {S11, E1}});
		_ -> case length(Args) > 0 of
			 true -> 
                             Arg = wrangler_misc:glast("refac_util:do_add_range,attribute", Args),
                             {S1, _E1} = get_range(Name),
                             {_S2, E2} = get_range(Arg),
                             S11 = extend_forwards(Toks, S1, '-'),
                             update_ann(Node, {range, {S11, E2}});
			 _ -> {S1, E1} = get_range(Name),
			      S11 = extend_forwards(Toks, S1, '-'),
			      update_ann(Node, {range, {S11, E1}})
		     end
	    end;
	generator ->
	    calc_and_add_range_to_node(Node, generator_pattern, generator_body);
	binary_generator ->
	    calc_and_add_range_to_node(Node, binary_generator_pattern, binary_generator_body);
	tuple ->
	    Es = wrangler_syntax:tuple_elements(Node),
	    case length(Es) of
		0 -> update_ann(Node, {range, {{L, C}, {L, C + 1}}});
		_ ->
		    add_range_to_list_node(Node, Toks, Es, "refac_util:do_add_range, tuple",
					   "refac_util:do_add_range, tuple",
					   '{', '}')
	    end;
	list_comp ->
	    %%T = refac_syntax:list_comp_template(Node),
	    B = wrangler_misc:glast("refac_util:do_add_range,list_comp", wrangler_syntax:list_comp_body(Node)),
	    {_S2, E2} = get_range(B),
	    E21 = extend_backwards(Toks, E2, ']'),
	    update_ann(Node, {range, {{L, C}, E21}});
	binary_comp ->
	    %%T = refac_syntax:binary_comp_template(Node),
	    B = wrangler_misc:glast("refac_util:do_add_range,binary_comp",
				    wrangler_syntax:binary_comp_body(Node)),
	    {_S2, E2} = get_range(B),
	    E21 = extend_backwards(Toks, E2, '>>'),
	    update_ann(Node, {range, {{L, C}, E21}});
	block_expr ->
	    Es = wrangler_syntax:block_expr_body(Node),
	    add_range_to_list_node(Node, Toks, Es, "refac_util:do_add_range, block_expr",
				   "refac_util:do_add_range, block_expr", 'begin', 'end');
	receive_expr ->
	    case wrangler_syntax:receive_expr_timeout(Node) of
		none ->
                    %% Cs cannot be empty here.
		    Cs = wrangler_syntax:receive_expr_clauses(Node),
                    add_range_to_list_node(Node, Toks, Cs, "refac_util:do_add_range, receive_expr1",
                                           "refac_util:do_add_range, receive_expr1", 'receive', 'end');
                _E ->
                    A = wrangler_syntax:receive_expr_action(Node),
                    {_S2, E2} = get_range(wrangler_misc:glast("refac_util:do_add_range, receive_expr2", A)),
                    E21 = extend_backwards(Toks, E2, 'end'),
                    update_ann(Node, {range, {{L, C}, E21}})
            end;
	try_expr ->
	    B = wrangler_syntax:try_expr_body(Node),
	    After = wrangler_syntax:try_expr_after(Node),
	    {S1, _E1} = get_range(wrangler_misc:ghead("refac_util:do_add_range, try_expr", B)),
	    {_S2, E2} = case After of
			    [] ->
				Handlers = wrangler_syntax:try_expr_handlers(Node),
				get_range(wrangler_misc:glast("refac_util:do_add_range, try_expr", Handlers));
			    _ ->
				get_range(wrangler_misc:glast("refac_util:do_add_range, try_expr", After))
			end,
	    S11 = extend_forwards(Toks, S1, 'try'),
	    E21 = extend_backwards(Toks, E2, 'end'),
	    update_ann(Node, {range, {S11, E21}});
	binary ->
	    Fs = wrangler_syntax:binary_fields(Node),
	    case Fs == [] of
		true -> update_ann(Node, {range, {{L, C}, {L, C + 3}}});
		_ ->
		    Hd = wrangler_misc:ghead("do_add_range:binary", Fs),
		    Last = wrangler_misc:glast("do_add_range:binary", Fs),
		    calc_and_add_range_to_node_1(Node, Toks, Hd, Last, '<<', '>>')
	    end;
	binary_field ->
	    Body = wrangler_syntax:binary_field_body(Node),
	    Types = wrangler_syntax:binary_field_types(Node),
	    {S1, E1} = get_range(Body),
	    {_S2, E2} = if Types == [] -> {S1, E1};
			   true -> get_range(wrangler_misc:glast("refac_util:do_add_range,binary_field", Types))
			end,
	    case E2 > E1  %%Temporal fix; need to change refac_syntax to make the pos info correct.
		of
		true ->
		    update_ann(Node, {range, {S1, E2}});
		false ->
		    update_ann(Node, {range, {S1, E1}})
	    end;
	match_expr ->
	    calc_and_add_range_to_node(Node, match_expr_pattern, match_expr_body);
	form_list ->
	    Es = wrangler_syntax:form_list_elements(Node),
	    
	    add_range_to_body(Node, Es, "refac_util:do_add_range, form_list",
			      "refac_util:do_add_range, form_list");
	parentheses ->
	    B = wrangler_syntax:parentheses_body(Node),
	    {S, E} = get_range(B),
	    S1 = extend_forwards(Toks, S, '('),
	    E1 = extend_backwards(Toks, E, ')'),
	    update_ann(Node, {range, {S1, E1}});
	class_qualifier ->
	    calc_and_add_range_to_node(Node, class_qualifier_argument, class_qualifier_body);
	qualified_name ->
	    Es = wrangler_syntax:qualified_name_segments(Node),
	    
	    add_range_to_body(Node, Es, "refac_util:do_add_range, qualified_name",
			      "refac_util:do_add_range, qualified_name");
	query_expr ->
	    B = wrangler_syntax:query_expr_body(Node),
	    {S, E} = get_range(B),
	    update_ann(Node, {range, {S, E}});
	record_field ->
	    Name = wrangler_syntax:record_field_name(Node),
	    {S1, E1} = get_range(Name),
	    Value = wrangler_syntax:record_field_value(Node),
	    case Value of
		none -> update_ann(Node, {range, {S1, E1}});
		_ -> {_S2, E2} = get_range(Value), update_ann(Node,
                                                              {range, {S1, E2}})
	    end;
	typed_record_field   %% This is not correct; need to be fixed later!
                           ->
                Field = wrangler_syntax:typed_record_field(Node),
                {S1, _E1} = get_range(Field),
                Type = wrangler_syntax:typed_record_type(Node),
                {_S2, E2} = get_range(Type),
                update_ann(Node, {range, {S1, E2}});
	record_expr ->
                Arg = wrangler_syntax:record_expr_argument(Node),
                Type = wrangler_syntax:record_expr_type(Node),
                Toks2 = lists:dropwhile(fun(B)->
                                               element(2, B)/= {L,C}
                                       end, Toks),
                [{'#', _}, T|_] = Toks2,
                Pos1 = token_loc(T),
                Type1 = add_range(wrangler_syntax:set_pos(Type, Pos1), Toks),
                Fields = wrangler_syntax:record_expr_fields(Node),
                {S1, E1} = case Arg of
                               none -> get_range(Type);
                               _ -> get_range(Arg)
                           end,
                case Fields of
                    [] -> E11 = extend_backwards(Toks, E1, '}'),
                          Node1 =rewrite(Node, wrangler_syntax:record_expr(Arg, Type1, Fields)),
                          update_ann(Node1, {range, {S1, E11}});
                    _ ->
                        {_S2, E2} = get_range(wrangler_misc:glast("refac_util:do_add_range,record_expr", Fields)),
                        E21 = extend_backwards(Toks, E2, '}'),
                        Node1 =rewrite(Node, wrangler_syntax:record_expr(Arg, Type1, Fields)),
                        update_ann(Node1, {range, {S1, E21}})
                end;
	record_access ->
	    calc_and_add_range_to_node(Node, record_access_argument, record_access_field);
	record_index_expr ->
	    calc_and_add_range_to_node(Node, record_index_expr_type, record_index_expr_field);
	comment ->
	    T = wrangler_syntax:comment_text(Node),
	    Lines = length(T),
	    update_ann(Node,
		       {range,
			{{L, C},
                         {L + Lines - 1,
                          length(wrangler_misc:glast("refac_util:do_add_range,comment",
                                                     T))}}});
	macro ->
                Name = wrangler_syntax:macro_name(Node),
                Args = wrangler_syntax:macro_arguments(Node),
                {_S1, {L1, C1}} = get_range(Name),
                E1={L1, C1+1},
                M=case Args of
                      none -> update_ann(Node, {range, {{L, C}, E1}});
                      Ls ->
                          case Ls of
                              [] -> E21 = extend_backwards(Toks, E1, ')'),
                                    update_ann(Node, {range, {{L, C}, E21}});
                              _ ->
                                  La = wrangler_misc:glast("refac_util:do_add_range,macro", Ls),
                                  {_S2, E2} = get_range(La),
                                  E21 = extend_backwards(Toks, E2, ')'),
                                  update_ann(Node, {range, {{L, C}, E21}})
                          end
                  end,
                update_ann(M,{with_bracket,
                            wrangler_prettypr:has_parentheses(M, Toks)});
	size_qualifier ->
	    calc_and_add_range_to_node(Node, size_qualifier_body, size_qualifier_argument);
	error_marker ->
                case wrangler_syntax:revert(Node) of
                    {error, {_, {Start, End}}} ->
                        update_ann(Node, {range, {Start, End}});
                    _ ->
                        update_ann(Node, {range, {{L, C}, {L, C}}})
                end;
	type   %% This is not correct, and need to be fixed!!
	     ->
            update_ann(Node, {range, {{L, C}, {L, C}}});
	_ ->
	    %% refac_io:format("Node;\n~p\n",[Node]),
	    %% ?wrangler_io("Unhandled syntax category:\n~p\n", [refac_syntax:type(Node)]),
	    Node
    end.

calc_and_add_range_to_node(Node, Fun1, Fun2) ->
    Arg = wrangler_syntax:Fun1(Node),
    Field = wrangler_syntax:Fun2(Node),
    {S1,_E1} = get_range(Arg),
    {_S2,E2} = get_range(Field),
    update_ann(Node, {range, {S1, E2}}).

calc_and_add_range_to_node_1(Node, Toks, StartNode, EndNode, StartWord, EndWord) ->
    {S1,_E1} = get_range(StartNode),
    {_S2,E2} = get_range(EndNode),
    S11 = extend_forwards(Toks,S1,StartWord),
    E21 = extend_backwards(Toks,E2,EndWord),
    update_ann(Node, {range, {S11, E21}}).


get_range(Node) ->
     As = wrangler_syntax:get_ann(Node),
     case lists:keysearch(range, 1, As) of
       {value, {range, {S, E}}} -> {S, E};
       _ -> {?DEFAULT_LOC,
 	   ?DEFAULT_LOC} 
     end.

add_range_to_list_node(Node, Toks, Es, Str1, Str2, KeyWord1, KeyWord2) ->
    Hd = wrangler_misc:ghead(Str1, Es),
    La = wrangler_misc:glast(Str2, Es),
    calc_and_add_range_to_node_1(Node, Toks, Hd, La, KeyWord1, KeyWord2).

add_range_to_body(Node, [], _, _) -> Node; %% why this should happend?
add_range_to_body(Node, B, Str1, Str2) ->
    H = wrangler_misc:ghead(Str1, B),
    La = wrangler_misc:glast(Str2, B),
    {S1, _E1} = get_range(H),
    {_S2, E2} = get_range(La),
    update_ann(Node, {range, {S1, E2}}).
   
extend_forwards(Toks, StartLoc, Val) ->
    Toks1 = lists:takewhile(fun (T) -> token_loc(T) < StartLoc end, Toks),
    Toks2 = lists:dropwhile(fun (T) -> token_val(T) =/= Val end, lists:reverse(Toks1)),
    case Toks2 of
      [] -> StartLoc;
      _ -> token_loc(hd(Toks2))
    end.

extend_backwards(Toks, EndLoc, Val) ->
    Toks1 = lists:dropwhile(fun (T) -> token_loc(T) =< EndLoc end, Toks),
    Toks2 = lists:dropwhile(fun (T) -> token_val(T) =/= Val end, Toks1),
    case Toks2 of
      [] -> EndLoc;
      _ ->
	  {Ln, Col} = token_loc(hd(Toks2)),
	  {Ln, Col + length(atom_to_list(Val)) - 1}
    end.

token_loc(T) ->
    case T of
      {_, L, _V} -> L;
      {_, L1} -> L1
    end.

token_val(T) ->
    case T of
      {_, _, V} -> V;
      {V, _} -> V
    end.

	
is_whitespace({whitespace, _, _}) ->
    true;
is_whitespace(_) ->
    false.

is_whitespace_or_comment({whitespace, _, _}) ->
    true;
is_whitespace_or_comment({comment, _, _}) ->
    true;
is_whitespace_or_comment(_) -> false.
	
    
is_string({string, _, _}) ->
    true;
is_string(_) -> false.


%% =====================================================================
% @doc Attach syntax category information to AST nodes.
%% =====================================================================
%% -type (category():: pattern|expression|guard_expression|record_type|generator
%%                    record_field| {macro_name, none|int(), pattern|expression}
%%                    |operator
%%-spec(add_category(Node::syntaxTree()) -> syntaxTree()).
add_category(Node) ->
    add_category(Node, none).

add_category(Node, C) ->
    {Node1, _} =api_ast_traverse:stop_tdTP(fun do_add_category/2, Node, C),
    Node1.

do_add_category(Node, C) when is_list(Node) ->
    {[add_category(E, C)||E<-Node], true};
do_add_category(Node, C) ->
    case wrangler_syntax:type(Node) of
	clause ->
	    Body = wrangler_syntax:clause_body(Node),
	    Ps = wrangler_syntax:clause_patterns(Node),
	    G = wrangler_syntax:clause_guard(Node),
	    Body1 = [add_category(B, expression)||B<-Body],
	    Ps1 = [add_category(P, pattern)||P<-Ps]
,	    G1 = case G of
		     none -> none;
		     _ -> add_category(G, guard_expression)
		 end,
	    Node1 =rewrite(Node, wrangler_syntax:clause(Ps1, G1, Body1)),
	    {Node1, true};
	match_expr ->
	    P = wrangler_syntax:match_expr_pattern(Node),
	    B = wrangler_syntax:match_expr_body(Node),
	    P1 = add_category(P, pattern),
	    B1 = add_category(B, C),
	    Node1=rewrite(Node, wrangler_syntax:match_expr(P1, B1)),
            {update_ann(Node1, {category, C}), true};
        generator ->
	    P = wrangler_syntax:generator_pattern(Node),
	    B = wrangler_syntax:generator_body(Node),
	    P1 = add_category(P, pattern),
	    B1 = add_category(B, expression),
	    Node1=rewrite(Node, wrangler_syntax:generator(P1, B1)),
	    {update_ann(Node1, {category, generator}), true};
	binary_generator ->
	    P = wrangler_syntax:binary_generator_pattern(Node),
	    B = wrangler_syntax:binary_generator_body(Node),
	    P1 = add_category(P, pattern),
	    B1 = add_category(B, expression),
	    Node1=rewrite(Node, wrangler_syntax:binary_generator(P1, B1)),
	    {update_ann(Node1, {category, generator}), true};
	macro ->
	    Name = wrangler_syntax:macro_name(Node),
	    Args = wrangler_syntax:macro_arguments(Node),
            Name1 = case Args of 
                        none -> add_category(Name, C);  %% macro with no args are not annoated as macro_name.
                        _ ->add_category(Name, macro_name)
                    end,
	    Args1 = case Args of
			none -> none;
			_ -> add_category(Args, C) 
		    end,
	    Node1 = rewrite(Node, wrangler_syntax:macro(Name1, Args1)),
	    {update_ann(Node1, {category, C}), true};
	record_access ->
            Argument = wrangler_syntax:record_access_argument(Node),
            Type = wrangler_syntax:record_access_type(Node),
            Field = wrangler_syntax:record_access_field(Node),
            Argument1 = add_category(Argument, C),
            Type1 = case Type of
                        none -> none;
                        _ -> add_category(Type, record_type)
		   end,
            Field1 = add_category(Field, record_field),
            Node1 = rewrite(Node, wrangler_syntax:record_access(Argument1, Type1, Field1)),
            {update_ann(Node1, {category, C}), true};
	record_expr ->
	    Argument = wrangler_syntax:record_expr_argument(Node),
	    Type = wrangler_syntax:record_expr_type(Node),
	    Fields = wrangler_syntax:record_expr_fields(Node),
	    Argument1 = case Argument of
			    none -> none;
			    _ -> add_category(Argument, C)
			end,
	    Type1 = add_category(Type, record_type),
	    Fields1 =[wrangler_syntax:add_ann({category, record_field},
                                              rewrite(F, wrangler_syntax:record_field(
                                                              add_category(wrangler_syntax:record_field_name(F), record_field),
                                                              case wrangler_syntax:record_field_value(F) of
                                                                  none ->
                                                                      none;
                                                                  V ->
                                                                      add_category(V, C)
                                                              end))) || F <- Fields],
	    Node1 = rewrite(Node, wrangler_syntax:record_expr(Argument1, Type1, Fields1)),
	    {update_ann(Node1, {category, C}), true};
	record_index_expr ->
	    Type = wrangler_syntax:record_index_expr_type(Node),
	    Field = wrangler_syntax:record_index_expr_field(Node),
	    Type1 = add_category(Type, record_type),
	    Field1 = add_category(Field, record_field),
	    Node1 = rewrite(Node, wrangler_syntax:record_index_expr(Type1, Field1)),
	    {update_ann(Node1, {category, C}), true};
	operator ->
	    {update_ann(Node, {category, operator}), true};
	_ -> case C of
		 none ->
		     {Node, false};
		 _ -> 
		     {update_ann(Node, {category, C}),false}
	     end
    end.

rewrite(Tree, Tree1) ->
    wrangler_syntax:copy_attrs(Tree, Tree1).


list_elements(Node) ->
    lists:reverse(list_elements(Node, [])).

list_elements(Node, As) ->
    case wrangler_syntax:type(Node) of
      list ->
	    As1 = lists:reverse(wrangler_syntax:list_prefix(Node)) ++ As,
	    case wrangler_syntax:list_suffix(Node) of
                none -> As1;
                Tail ->
                    list_elements(Tail, As1)
            end;
        nil -> As;
        _ ->[Node|As]
    end.
           

adjust_implicit_fun_loc(T, Toks)->
    Pos = wrangler_syntax:get_pos(T),
    Name = wrangler_syntax:implicit_fun_name(T),
    Toks1 = lists:dropwhile(fun (B) -> element(2, B) =/= Pos end, Toks),
    Toks2 = [Tok||Tok<-Toks1,element(1, Tok)/='?' ],
    case wrangler_syntax:type(Name) of
        module_qualifier ->
            Arg = wrangler_syntax:module_qualifier_argument(Name),
            Body = wrangler_syntax:module_qualifier_body(Name),
            Fun = wrangler_syntax:arity_qualifier_body(Body),
            A = wrangler_syntax:arity_qualifier_argument(Body),
            [{'fun', Pos1},{_, Pos2, _ModName}, {':', _},
             {_, Pos4, _FunName}, {'/', _},
             {_, Pos5, _Arity}|_Ts] = Toks2,
            Arg1 =add_range(wrangler_syntax:set_pos(Arg, Pos2),Toks),
            Fun1= add_range(wrangler_syntax:set_pos(Fun, Pos4),Toks),
            A1 = add_range(wrangler_syntax:set_pos(A, Pos5),Toks),
            Body1 = add_range(
                      wrangler_syntax:set_pos(
                           rewrite(Body,wrangler_syntax:arity_qualifier(Fun1, A1)),
                           Pos4),Toks),
            Name1= add_range(wrangler_syntax:set_pos(
                                  wrangler_syntax:module_qualifier(
                                       Arg1, Body1), Pos2), Toks),
            {_S,E} = get_range(A1),
            T1=rewrite(T, wrangler_syntax:implicit_fun(Name1)),
            update_ann(T1, {range, {Pos1, E}});
        arity_qualifier->
            Fun = wrangler_syntax:arity_qualifier_body(Name),
            A = wrangler_syntax:arity_qualifier_argument(Name),
            [{'fun', Pos1}, {_, Pos4, _FunName}, {'/', _},
             {_, Pos5, _Arity}|_Ts] = Toks2,
            Fun1= add_range(wrangler_syntax:set_pos(Fun, Pos4),Toks),
            A1 = add_range(wrangler_syntax:set_pos(A, Pos5),Toks),
            Name1 = add_range(
                      wrangler_syntax:set_pos(
                           rewrite(Name,wrangler_syntax:arity_qualifier(Fun1, A1)),
                           Pos4),Toks),
            {_S,E} = get_range(A1),
            T1=rewrite(T, wrangler_syntax:implicit_fun(Name1)),
            update_ann(T1, {range, {Pos1, E}});
        _ -> T
    end.
  
   
update_ann(Node, Ann) ->
    wrangler_misc:update_ann(Node, Ann).

