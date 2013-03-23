%% Copyright (c) 2010, Huiqing Li, Simon Thompson
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

%% @hidden
%% @private
-module(percept2_ast_server).

-compile(export_all).

%% API
%%-export([parse_file/1]).
         
parse_file(FName) ->
    case percept2_epp_dodger:parse_file(FName,[]) of 
        {ok, Forms} ->
            SyntaxTree = erl_recomment:recomment_forms(Forms, []),
            AnnAST = annotate_bindings(FName, SyntaxTree),
	    {ok, AnnAST};
	{error, Reason} -> erlang:error(Reason)
    end.


annotate_bindings(FName, AST) ->
    {ok, Toks} = tokenize(FName),
    add_token_and_ranges(AST, Toks).


tokenize(File) ->
    case file:read_file(File) of
	{ok, Bin} ->
	    S = erlang:binary_to_list(Bin),
	    {ok, Ts, _}= percept2_scan:string(S),
            {ok, Ts};
	{error, Reason} ->
            {error, Reason}
    end.
  
%% Attach tokens to each form in the AST, and also add 
%% range information to each node in the AST.
%%-spec add_tokens(syntaxTree(), [token()]) -> syntaxTree(). 		 
add_token_and_ranges(SyntaxTree, Toks) ->
    Fs = percept2_syntax:form_list_elements(SyntaxTree),
    NewFs = do_add_token_and_ranges(Toks, Fs),
    rewrite(SyntaxTree, percept2_syntax:form_list(NewFs)).
 
do_add_token_and_ranges(Toks, Fs) ->
    do_add_token_and_ranges(lists:reverse(Toks), lists:reverse(Fs), []).

do_add_token_and_ranges(_, [], NewFs) ->
    NewFs;
do_add_token_and_ranges(Toks, _Forms=[F| Fs], NewFs) ->
    {FormToks0, RemToks} = get_form_tokens(Toks, F, Fs), 
    FormToks = lists:reverse(FormToks0),
    F1 = update_ann(F, {toks, FormToks}),
    F2 = add_range(F1, FormToks),
    do_add_token_and_ranges(RemToks, Fs, [F2| NewFs]).

get_form_tokens(Toks, F, Fs) ->
    case percept2_syntax:type(F) of
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
    case percept2_syntax:type(F) of
	error_marker ->
	    case percept2_syntax:revert(F) of
		{error, {_, {{Line, Col}, {_Line1, _Col1}}}} ->
		    {Line, Col};
		_ ->
		    percept2_syntax:get_pos(F)
	    end;
	_ ->
	    case percept2_syntax:get_precomments(F) of
		[] ->
		    percept2_syntax:get_pos(F);
		[Com| _Tl] ->
		    percept2_syntax:get_pos(Com)
	    end
    end.

%%-spec add_range(syntaxTree(), [token()]) -> syntaxTree(). 
add_range(AST, Toks) ->
    QAtomPs= [Pos||{qatom, Pos, _Atom}<-Toks],
    Toks1 =[Tok||Tok<-Toks, not (is_whitespace_or_comment(Tok))],
    full_buTP(fun do_add_range/2, AST, {Toks1, QAtomPs}).

do_add_range(Node, {Toks, QAtomPs}) ->
    {L, C} = case percept2_syntax:get_pos(Node) of
		 {Line, Col} -> {Line, Col};
		 Line -> {Line, 0}
	     end,
    case percept2_syntax:type(Node) of
	variable ->
	    Len = length(percept2_syntax:variable_literal(Node)),
	    update_ann(Node, {range, {{L, C}, {L, C + Len - 1}}});
	atom ->
            case lists:member({L,C}, QAtomPs) orelse 
                lists:member({L,C+1}, QAtomPs) of  
                true ->
                    Len = length(atom_to_list(percept2_syntax:atom_value(Node))),
                    Node1 = update_ann(Node, {qatom, true}),
                    update_ann(Node1, {range, {{L, C}, {L, C + Len + 1}}});
                false ->
                    Len = length(atom_to_list(percept2_syntax:atom_value(Node))),
                    update_ann(Node, {range, {{L, C}, {L, C + Len - 1}}})
	    end;
        operator ->
	    Len = length(atom_to_list(percept2_syntax:atom_value(Node))),
	    update_ann(Node, {range, {{L, C}, {L, C + Len - 1}}});
	char -> update_ann(Node, {range, {{L, C}, {L, C}}});
	integer ->
            Len = length(percept2_syntax:integer_literal(Node)),
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
                      [] -> percept2_syntax:string_value(Node);
                      _ -> element(3, lists:last(Toks3))
                  end,
            Lines =split_lines(Str),
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
            Arg = percept2_syntax:module_qualifier_argument(Node),
            Field = percept2_syntax:module_qualifier_body(Node),
            {S1,_E1} = get_range(Arg),
            {_S2,E2} = get_range(Field),
            Node1 = percept2_syntax:set_pos(Node, S1),
            update_ann(Node1, {range, {S1, E2}});
	list ->  
            Es = list_elements(Node),
            case Es/=[] of
                true ->
                    Last = glast("do_add_range,list", Es),
                    {_, E2} = get_range(Last),
                    E21 = extend_backwards(Toks, E2, ']'),
                    update_ann(Node, {range, {{L, C}, E21}});
                false ->
                    Node
            end;
        application ->
	    O = percept2_syntax:application_operator(Node),
	    Args = percept2_syntax:application_arguments(Node),
	    {S1, E1} = get_range(O),
	    {S3, E3} = case Args of
			   [] -> {S1, E1};
			   _ -> La = glast("do_add_range, application", Args),
				{_S2, E2} = get_range(La),
				{S1, E2}
		       end,
	    E31 = extend_backwards(Toks, E3, ')'),
	    update_ann(Node, {range, {S3, E31}});
	case_expr ->
            A = percept2_syntax:case_expr_argument(Node),
	    Lc = glast("do_add_range,case_expr", percept2_syntax:case_expr_clauses(Node)),
	    calc_and_add_range_to_node_1(Node, Toks, A, Lc, 'case', 'end');
	clause ->
            {S1,_} = case percept2_syntax:clause_patterns(Node) of
                          [] -> case percept2_syntax:clause_guard(Node) of
                                    none ->{{L,C}, {0,0}};
                                    _ -> get_range(percept2_syntax:clause_guard(Node))
                                end;
                          Ps -> get_range(hd(Ps))
                      end,         
            Body = glast("do_add_range, clause", percept2_syntax:clause_body(Node)),
	    {_S2, E2} = get_range(Body),
	    update_ann(Node, {range, {lists:min([S1, {L, C}]), E2}});
	catch_expr ->
	    B = percept2_syntax:catch_expr_body(Node),
	    {S, E} = get_range(B),
	    S1 = extend_forwards(Toks, S, 'catch'),
	    update_ann(Node, {range, {S1, E}});
	if_expr ->
	    Cs = percept2_syntax:if_expr_clauses(Node),
	    add_range_to_list_node(Node, Toks, Cs, "refac_util:do_add_range, if_expr",
				   "refac_util:do_add_range, if_expr", 'if', 'end');
	cond_expr ->
	    Cs = percept2_syntax:cond_expr_clauses(Node),
	    add_range_to_list_node(Node, Toks, Cs, "refac_util:do_add_range, cond_expr",
				   "refac_util:do_add_range, cond_expr", 'cond', 'end');
	infix_expr ->
	    calc_and_add_range_to_node(Node, infix_expr_left, infix_expr_right);
	prefix_expr ->
	    calc_and_add_range_to_node(Node, prefix_expr_operator, prefix_expr_argument);
	conjunction ->
	    B = percept2_syntax:conjunction_body(Node),
	    add_range_to_body(Node, B, "refac_util:do_add_range,conjunction",
			      "refac_util:do_add_range,conjunction");
	disjunction ->
	    B = percept2_syntax:disjunction_body(Node),
	    add_range_to_body(Node, B, "refac_util:do_add_range, disjunction",
			      "refac_util:do_add_range,disjunction");
	function ->
	    F = percept2_syntax:function_name(Node),
	    Cs = percept2_syntax:function_clauses(Node),
	    Lc = glast("do_add_range,function", Cs),
	    {S1, _E1} = get_range(F),
	    {_S2, E2} = get_range(Lc),
	    update_ann(Node, {range, {S1, E2}});
	fun_expr ->
	    Cs = percept2_syntax:fun_expr_clauses(Node),
	    S = percept2_syntax:get_pos(Node),
	    Lc = glast("do_add_range, fun_expr", Cs),
	    {_S1, E1} = get_range(Lc),
	    E11 = extend_backwards(Toks, E1,
				   'end'),   %% S starts from 'fun', so there is no need to extend forwards/
	    update_ann(Node, {range, {S, E11}});
	arity_qualifier ->
                calc_and_add_range_to_node(Node, arity_qualifier_body, arity_qualifier_argument);
        attribute ->
	    Name = percept2_syntax:attribute_name(Node),
	    Args = percept2_syntax:attribute_arguments(Node),
	    case Args of
		none -> {S1, E1} = get_range(Name),
			S11 = extend_forwards(Toks, S1, '-'),
			update_ann(Node, {range, {S11, E1}});
		_ -> case length(Args) > 0 of
			 true -> 
                             Arg = glast("do_add_range,attribute", Args),
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
	    Es = percept2_syntax:tuple_elements(Node),
	    case length(Es) of
		0 -> update_ann(Node, {range, {{L, C}, {L, C + 1}}});
		_ ->
		    add_range_to_list_node(Node, Toks, Es, "refac_util:do_add_range, tuple",
					   "refac_util:do_add_range, tuple",
					   '{', '}')
	    end;
	list_comp ->
	    %%T = refac_syntax:list_comp_template(Node),
	    B = glast("do_add_range,list_comp", percept2_syntax:list_comp_body(Node)),
	    {_S2, E2} = get_range(B),
	    E21 = extend_backwards(Toks, E2, ']'),
	    update_ann(Node, {range, {{L, C}, E21}});
	binary_comp ->
	    %%T = refac_syntax:binary_comp_template(Node),
	    B = glast("do_add_range,binary_comp",
				    percept2_syntax:binary_comp_body(Node)),
	    {_S2, E2} = get_range(B),
	    E21 = extend_backwards(Toks, E2, '>>'),
	    update_ann(Node, {range, {{L, C}, E21}});
	block_expr ->
	    Es = percept2_syntax:block_expr_body(Node),
	    add_range_to_list_node(Node, Toks, Es, "refac_util:do_add_range, block_expr",
				   "refac_util:do_add_range, block_expr", 'begin', 'end');
	receive_expr ->
	    case percept2_syntax:receive_expr_timeout(Node) of
		none ->
                    %% Cs cannot be empty here.
		    Cs = percept2_syntax:receive_expr_clauses(Node),
                    add_range_to_list_node(Node, Toks, Cs, "refac_util:do_add_range, receive_expr1",
                                           "refac_util:do_add_range, receive_expr1", 'receive', 'end');
                _E ->
                    A = percept2_syntax:receive_expr_action(Node),
                    {_S2, E2} = get_range(glast("do_add_range, receive_expr2", A)),
                    E21 = extend_backwards(Toks, E2, 'end'),
                    update_ann(Node, {range, {{L, C}, E21}})
            end;
	try_expr ->
	    B = percept2_syntax:try_expr_body(Node),
	    After = percept2_syntax:try_expr_after(Node),
	    {S1, _E1} = get_range(ghead("do_add_range, try_expr", B)),
	    {_S2, E2} = case After of
			    [] ->
				Handlers = percept2_syntax:try_expr_handlers(Node),
				get_range(glast("do_add_range, try_expr", Handlers));
			    _ ->
				get_range(glast("do_add_range, try_expr", After))
			end,
	    S11 = extend_forwards(Toks, S1, 'try'),
	    E21 = extend_backwards(Toks, E2, 'end'),
	    update_ann(Node, {range, {S11, E21}});
	binary ->
	    Fs = percept2_syntax:binary_fields(Node),
	    case Fs == [] of
		true -> update_ann(Node, {range, {{L, C}, {L, C + 3}}});
		_ ->
		    Hd = ghead("do_add_range:binary", Fs),
		    Last = glast("binary", Fs),
		    calc_and_add_range_to_node_1(Node, Toks, Hd, Last, '<<', '>>')
	    end;
	binary_field ->
	    Body = percept2_syntax:binary_field_body(Node),
	    Types = percept2_syntax:binary_field_types(Node),
	    {S1, E1} = get_range(Body),
	    {_S2, E2} = if Types == [] -> {S1, E1};
			   true -> get_range(glast("do_add_range,binary_field", Types))
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
	    Es = percept2_syntax:form_list_elements(Node),
	    
	    add_range_to_body(Node, Es, "refac_util:do_add_range, form_list",
			      "refac_util:do_add_range, form_list");
	parentheses ->
	    B = percept2_syntax:parentheses_body(Node),
	    {S, E} = get_range(B),
	    S1 = extend_forwards(Toks, S, '('),
	    E1 = extend_backwards(Toks, E, ')'),
	    update_ann(Node, {range, {S1, E1}});
	class_qualifier ->
	    calc_and_add_range_to_node(Node, class_qualifier_argument, class_qualifier_body);
	qualified_name ->
	    Es = percept2_syntax:qualified_name_segments(Node),
	    
	    add_range_to_body(Node, Es, "refac_util:do_add_range, qualified_name",
			      "refac_util:do_add_range, qualified_name");
	query_expr ->
	    B = percept2_syntax:query_expr_body(Node),
	    {S, E} = get_range(B),
	    update_ann(Node, {range, {S, E}});
	record_field ->
	    Name = percept2_syntax:record_field_name(Node),
	    {S1, E1} = get_range(Name),
	    Value = percept2_syntax:record_field_value(Node),
	    case Value of
		none -> update_ann(Node, {range, {S1, E1}});
		_ -> {_S2, E2} = get_range(Value), update_ann(Node,
                                                              {range, {S1, E2}})
	    end;
	typed_record_field   %% This is not correct; need to be fixed later!
                           ->
                Field = percept2_syntax:typed_record_field(Node),
                {S1, _E1} = get_range(Field),
                Type = percept2_syntax:typed_record_type(Node),
                {_S2, E2} = get_range(Type),
                update_ann(Node, {range, {S1, E2}});
	record_expr ->
                Arg = percept2_syntax:record_expr_argument(Node),
                Type = percept2_syntax:record_expr_type(Node),
                Toks2 = lists:dropwhile(fun(B)->
                                               element(2, B)/= {L,C}
                                       end, Toks),
                [{'#', _}, T|_] = Toks2,
                Pos1 = token_loc(T),
                Type1 = add_range(percept2_syntax:set_pos(Type, Pos1), Toks),
                Fields = percept2_syntax:record_expr_fields(Node),
                {S1, E1} = case Arg of
                               none -> get_range(Type);
                               _ -> get_range(Arg)
                           end,
                case Fields of
                    [] -> E11 = extend_backwards(Toks, E1, '}'),
                          Node1 =rewrite(Node, percept2_syntax:record_expr(Arg, Type1, Fields)),
                          update_ann(Node1, {range, {S1, E11}});
                    _ ->
                        {_S2, E2} = get_range(glast("do_add_range,record_expr", Fields)),
                        E21 = extend_backwards(Toks, E2, '}'),
                        Node1 =rewrite(Node, percept2_syntax:record_expr(Arg, Type1, Fields)),
                        update_ann(Node1, {range, {S1, E21}})
                end;
	record_access ->
	    calc_and_add_range_to_node(Node, record_access_argument, record_access_field);
	record_index_expr ->
	    calc_and_add_range_to_node(Node, record_index_expr_type, record_index_expr_field);
	comment ->
	    T = percept2_syntax:comment_text(Node),
	    Lines = length(T),
	    update_ann(Node,
		       {range,
			{{L, C},
                         {L + Lines - 1,
                          length(glast("do_add_range,comment",
                                                     T))}}});
	macro ->
                Name = percept2_syntax:macro_name(Node),
                Args = percept2_syntax:macro_arguments(Node),
                {_S1, {L1, C1}} = get_range(Name),
                E1={L1, C1+1},
                case Args of
                    none -> update_ann(Node, {range, {{L, C}, E1}});
                    Ls ->
                        case Ls of
                              [] -> E21 = extend_backwards(Toks, E1, ')'),
                                    update_ann(Node, {range, {{L, C}, E21}});
                            _ ->
                                La = glast("do_add_range,macro", Ls),
                                {_S2, E2} = get_range(La),
                                E21 = extend_backwards(Toks, E2, ')'),
                                  update_ann(Node, {range, {{L, C}, E21}})
                        end
                  end;
             size_qualifier ->
	    calc_and_add_range_to_node(Node, size_qualifier_body, size_qualifier_argument);
	error_marker ->
                case percept2_syntax:revert(Node) of
                    {error, {_, {Start, End}}} ->
                        update_ann(Node, {range, {Start, End}});
                    _ ->
                        update_ann(Node, {range, {{L, C}, {L, C}}})
                end;
	type   %% This is not correct, and need to be fixed!!
	     ->
            update_ann(Node, {range, {{L, C}, {L, C}}});
	_ ->
           Node
    end.

calc_and_add_range_to_node(Node, Fun1, Fun2) ->
    Arg = percept2_syntax:Fun1(Node),
    Field = percept2_syntax:Fun2(Node),
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
     As = percept2_syntax:get_ann(Node),
     case lists:keysearch(range, 1, As) of
       {value, {range, {S, E}}} -> {S, E};
       _ -> {{0,0},{0,0}} 
     end.

add_range_to_list_node(Node, Toks, Es, Str1, Str2, KeyWord1, KeyWord2) ->
    Hd = ghead(Str1, Es),
    La = glast(Str2, Es),
    calc_and_add_range_to_node_1(Node, Toks, Hd, La, KeyWord1, KeyWord2).

add_range_to_body(Node, [], _, _) -> Node; %% why this should happend?
add_range_to_body(Node, B, Str1, Str2) ->
    H = ghead(Str1, B),
    La = glast(Str2, B),
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



rewrite(Tree, Tree1) ->
    percept2_syntax:copy_attrs(Tree, Tree1).


list_elements(Node) ->
    lists:reverse(list_elements(Node, [])).

list_elements(Node, As) ->
    case percept2_syntax:type(Node) of
      list ->
	    As1 = lists:reverse(percept2_syntax:list_prefix(Node)) ++ As,
	    case percept2_syntax:list_suffix(Node) of
                none -> As1;
                Tail ->
                    list_elements(Tail, As1)
            end;
        nil -> As;
        _ ->[Node|As]
    end.
           

update_ann(Tree, {Key, Val}) ->
    As0 = percept2_syntax:get_ann(Tree),
    As1 = case lists:keysearch(Key, 1, As0) of
	    {value, _} -> lists:keyreplace(Key, 1, As0, {Key, Val});
	    _ -> As0 ++ [{Key, Val}]
	  end,
    percept2_syntax:set_ann(Tree, As1).

glast(Info, []) -> erlang:error(Info);
glast(_Info, List) -> lists:last(List).

ghead(Info, []) -> erlang:error(Info);
ghead(_Info, List) -> hd(List).

     
split_lines(Cs) ->
    split_lines(Cs, "").

split_lines(Cs, Prefix) -> split_lines(Cs, Prefix, 0).

split_lines(Cs, Prefix, N) ->
    lists:reverse(split_lines(Cs, N, [], [], Prefix)).

split_lines([$\r, $\n | Cs], _N, Cs1, Ls, Prefix) ->
    split_lines_1(Cs, Cs1, Ls, Prefix);
split_lines([$\r | Cs], _N, Cs1, Ls, Prefix) ->
    split_lines_1(Cs, Cs1, Ls, Prefix);
split_lines([$\n | Cs], _N, Cs1, Ls, Prefix) ->
    split_lines_1(Cs, Cs1, Ls, Prefix);
split_lines([$\t | Cs], N, Cs1, Ls, Prefix) ->
    split_lines(Cs, 0, push(8 - N rem 8, $\s, Cs1), Ls,
		Prefix);
split_lines([C | Cs], N, Cs1, Ls, Prefix) ->
    split_lines(Cs, N + 1, [C | Cs1], Ls, Prefix);
split_lines([], _, [], Ls, _) -> Ls;
split_lines([], _N, Cs, Ls, Prefix) ->
    [Prefix ++ lists:reverse(Cs) | Ls].

split_lines_1(Cs, Cs1, Ls, Prefix) ->
    split_lines(Cs, 0, [],
		[Prefix ++ lists:reverse(Cs1) | Ls], Prefix).

push(N, C, Cs) when N > 0 -> push(N - 1, C, [C | Cs]);
push(0, _, Cs) -> Cs.


full_tdTP(Function, Node, Others) ->
    case Function(Node, Others) of
      {Node1, Changed} ->
	  case percept2_syntax:subtrees(Node1) of
	    [] -> {Node1, Changed};
	    Gs ->
		Gs1 = [[full_tdTP(Function, T, Others) || T <- G] || G <- Gs],
		Gs2 = [[N || {N, _B} <- G] || G <- Gs1],
		G = [[B || {_N, B} <- G] || G <- Gs1],
		Node2 = percept2_syntax:make_tree(percept2_syntax:type(Node1), Gs2),
		{rewrite(Node1, Node2), Changed or lists:member(true, lists:flatten(G))}
	  end
    end.

stop_tdTP(Function, Node, Others) ->
     case Function(Node, Others) of
       {Node1, true} -> {Node1, true};
       {Node1, false} ->
           case percept2_syntax:subtrees(Node1) of
             [] -> {Node1, false};
             Gs ->
                 Gs1 = [[stop_tdTP(Function, T, Others) || T <- G] || G <- Gs],
                 Gs2 = [[N || {N, _B} <- G] || G <- Gs1],
                 G = [[B || {_N, B} <- G] || G <- Gs1],
                 Node2 = percept2_syntax:make_tree(percept2_syntax:type(Node1), Gs2),
                 {rewrite(Node1, Node2), lists:member(true, lists:flatten(G))}
           end
     end.


full_buTP(Fun, Tree, Others) ->
    case percept2_syntax:subtrees(Tree) of
      [] -> Fun(Tree, Others); 
      Gs ->
	  Gs1 = [[full_buTP(Fun, T, Others) || T <- G] || G <- Gs],
	  Tree1 = percept2_syntax:make_tree(percept2_syntax:type(Tree), Gs1),
	  Fun(rewrite(Tree, Tree1), Others)
    end.
