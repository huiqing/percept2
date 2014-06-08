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

-module(percept2_code_server).

-compile(export_all).

-spec(stop()->ok).
stop() ->    
    percept2_code_server!stop,
    ok.

-spec(start()->true).
start() ->
    case whereis(percept2_code_server) of
        undefined -> ok;
        _ -> percept2_code_server!stop
    end,
    register(percept2_code_server, 
             spawn_link(fun()-> 
                                code_server_loop([]) 
                        end)).

-spec(load(DirsOrFiles::[filelib:dirname()|file:filename()]) -> ok).
load(DirOrFiles) ->
    Files = expand_files(DirOrFiles, ".erl"),
    io:format("Files:~p\n", [Files]),
    add_files(Files),
    ok.

get_func_code(MFA) ->
    MFA1 = normalise_fun_name(MFA),
    Pid = whereis(percept2_code_server),
    Pid ! {get_func_code, MFA1, self()}, 
    receive {Pid, Res} ->
            Res
    end.

get_file(Mod) ->
    Pid = whereis(percept2_code_server),
    Pid ! {get_file, Mod, self()}, 
    receive {Pid, Res} ->
            Res
    end.

add_files(Files) ->
    percept2_code_server!{add_files, Files}.

code_server_loop(State) ->
    receive
        {get_func_code, {M, F, A}, From} ->
            case lists:keyfind(M, 1, State) of 
                {M, {File, none}} ->
                    {ok, AST} =wrangler_ast_gen:parse_file(File),
                    Code = get_func_code(File, AST, {M,F, A}),
                    From !{self(), Code},
                    code_server_loop(State);
                {M, {File, AST}} ->
                    Code = get_func_code(File, AST, {M,F, A}),
                    From !{self(), Code},
                    code_server_loop([{File, AST}|State]);
                _ ->
                    From !{self(), ""},
                    code_server_loop(State)
            end;
        {add_files, Files} ->
            Data=[begin
                      ModName = list_to_atom(filename:basename(F, ".erl")),
                      {ModName, {F, none}}
                  end
                  ||F<-Files],
            code_server_loop(Data++State);
        stop -> stop
    end.

get_func_code(File, AST, {_M, F, A}) ->
    Forms = wrangler_syntax:form_list_elements(AST),
    Res=[Form||                                
            Form<-Forms, 
            wrangler_syntax:type(Form)==function,
            {wrangler_syntax:atom_value(wrangler_syntax:function_name(Form)), 
             wrangler_syntax:function_arity(Form)}=={F, A}],
    case Res of 
        [] -> "";
        [Form1] ->
            {{StartLine, _}, {EndLine,_}} = get_start_end_loc_with_comment(Form1),
            {ok, IoDevice} = file:open(File, [read]),
            [file:read_line(IoDevice)||_I<-lists:seq(1, StartLine-1)],
            Lines =[file:read_line(IoDevice)||_I<-lists:seq(StartLine, EndLine)],
            element(2, lists:unzip(Lines))
    end.
       

get_start_end_loc_with_comment(Node) when Node==[] ->
    {{0,0},{0,0}};
get_start_end_loc_with_comment(Node) when is_list(Node) ->
    {Start, _} = get_start_end_loc_with_comment(hd(Node)),
    {_, End} = get_start_end_loc_with_comment(lists:last(Node)),
    {Start, End};
get_start_end_loc_with_comment(Node) ->
    {Start={_StartLn, StartCol}, End} = get_range(Node),
    PreCs = wrangler_syntax:get_precomments(Node),
    PostCs = wrangler_syntax:get_postcomments(Node),
    Start1 = case PreCs of
                 [] -> 
                     Start;
                 _ ->
                     {StartLn1, StartCol1}=wrangler_syntax:get_pos(hd(PreCs)),
                     {StartLn1, lists:max([StartCol, StartCol1])}
             end,
    End1 = case PostCs of
               [] ->
                   End;
               _ ->
                   LastC = lists:last(PostCs),
                   LastCText = wrangler_syntax:comment_text(LastC),
                   {L, C}=wrangler_syntax:get_pos(LastC),
                   {L+length(LastCText)-1, C+length(lists:last(LastCText))-1}
           end,
    {Start1, End1}.

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


expand_files(FileDirs, Ext) ->
    expand_files(FileDirs, Ext, []).

expand_files([FileOrDir | Left], Ext, Acc) ->
    case filelib:is_dir(FileOrDir) of
        true ->
	    case file:list_dir(FileOrDir) of 
		{ok, List} ->
		    NewFiles = [filename:join(FileOrDir, X)
				|| X <- List, filelib:is_file(filename:join(FileOrDir, X)),
                                   filename:extension(X) == Ext],
		    NewDirs = [filename:join(FileOrDir, X) || 
                                  X <- List, 
                                  filelib:is_dir(filename:join(FileOrDir, X))],
		    expand_files(NewDirs ++ Left, Ext, NewFiles ++ Acc);
		{error, Reason} ->
                    Msg = io_lib:format("Percept2 could not read directory ~s: ~w \n", 
                                        [filename:dirname(FileOrDir), Reason]),
		    throw({error, lists:flatten(Msg)})
	    end;
	false ->
	    case filelib:is_regular(FileOrDir) of
		true ->
		    case filename:extension(FileOrDir) == Ext of
			true ->
                            expand_files(Left, Ext, [FileOrDir | Acc]);
			false -> 
                            expand_files(Left, Ext, Acc)
		    end;
		_ -> expand_files(Left, Ext, Acc)
	    end
    end;
expand_files([], _Ext, Acc) -> ordsets:from_list(Acc).

get_range(Node) ->
     As = wrangler_syntax:get_ann(Node),
     case lists:keysearch(range, 1, As) of
       {value, {range, {S, E}}} -> {S, E};
       _ -> {{0,0},{0,0}} 
     end.

