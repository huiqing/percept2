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
%% =====================================================================
%% The refactoring command level API that can be run in an Erlang shell.
%%
%% Author contact: H.Li@kent.ac.uk, Simon.J.Thompson@kent.ac.uk
%%
%% =====================================================================

-module(wrangler_dsl).

-export([rename_mod/3, rename_fun/5, move_fun/5, similar_code/7]).

-include("../include/wrangler_internal.hrl").


%%Generalized refactoring command interface.

rename_fun(ModuleFilter, OldFunNameFiler, ArityFilter, NewFunNameGenerator, SeatchPaths) ->
    ModName="aa",
    FunName="bb",
    Arity=1,
    NewFunName = NewFunNameGenerator({ModName, FunName, Arity}),
    try_apply(refac_rename_fun, rename_fun_command, 
              [ModOrFileName, FunName, Arity, NewFunName, SearchPaths]).


rename_var(ModuleFilter, FunNameFilter, ArityFilter, OldVarNameFilter, NewVarNameGenerator, SearchPaths) ->
    ModName="aa",
    FunName ="bb",
    Arity = 1,
    VarName = "AA",
    case MouleFilter(ModName) of 
        true ->
            case FunNameFilter(FunName) of 
                true ->
                    case ArityFilter(Arity) of 
                        true ->
                            case OldVarNameFilter(OldVarName) of 
                                true ->
                                    NewVarName = NewvarNameGenerator({ModName, FunName, Arity, OldVarName}),
                                    try_apply(refac_rename_var, rename_var, [ModName, FunName, Arity, VarName, NewVar]);
                                false ->
                                    false;
                                end;
                        false ->
                            ok
                    end;
                false ->
                    ok
            end;
        false ->
            ok
    end.
                    
%% case ?Match(?T("f@(Args@@, Line1, Col1, Args@@)")) of 
%%     true ->
%%         {M,F,A} =refac_api:fun_define_info(f@),
%%         refac_tuple_args(M,F,A, length(Args@@)+1, length(Args@++2));
%%     false ->
%%         ok.

remove_clone(ModName, FunName, Arity) ->
    [rename_fun(ModName, FunName, Arity, {user_input, "new function name"}, SearchPaths),
     {repeat,{maybe rename_var(ModName, NewNmae, Arity, fun(X) ->
                                                                re:match(X, "NewVar*")
                                                        end, ?{user_input, "New variable name?", NewName}, SearchPaths)}}
     {repeat, {maybe refac_swap_args(ModName, NewName, Arity, StartIndex, EndIndex, SearchPaths)}}
     fold_expr_against_function(fun(X)->
                                        true 
                                end, NewFunName, Arity, SearchPaths)].


-spec(is_atomic::()-> boolean()).
is_atomic() ->
    true.

signle_refactoring: 
   rename_fun|rename_var|remove_mod|function_extraction|...
composite_refactoring:
   single_refactoring,
   {maybe single_refactoring},
   {repeat composite_refactoring}
   composite_refactoring, composite_refactoring

-spec rename_fun(ModOrFile::{filter, file, FileFilter}|{filter, module, ModFilter}|atom()|filename(), 
                 OldFunName::{filter, FunNameFilter}|atom(), 
                 Arity::{filter, ArityFilter}|integer(),
                 NewFunName::{generator, NewNameGenerator}|{user_input, Prompt}|atom(),
                 SearchPaths::[filename()|dir()]) ->
                        {ok, FilesChanged::[filename()]}|{error,Reason}.

rename_fun(ModorFile, OldFunName, Arity, NewFunName, SearchPaths)->
    Files= get_files(MorOrFile, SearchPaths),
    CmdLists=[rename_fun_1(File, OldFunName, Arity, NewFunName, SearchPaths)
              ||File<-Files],
    lists:append(CmdLists).
    
      
get_files(ModOrFile, SearchPaths) ->
    Files = refac_mic:expand_files(SearchPaths, ".erl"),
    case ModorFile of 
        {filter, file, FileFilter} ->
            [F||F<-Files, FileFilter(F)];
        {filter, module, ModFilter} ->
            Files = refac_misc:expand_files(SearchPaths, ".erl"),
            [F||F<-Files, ModFilter(filename:basename(F, ".erl"))];
        _ when is_atom(ModorFile) ->
            [F||F<-Files, filename:basename(F,".erl")==ModOrFile];
        _ when is_regular(ModorFile)->
            [ModOrFile];
        _ ->
            throw({error, "Invalid argument"})
    end.

rename_fun_1(File, OldFunName, Arity, NewFunName, SearcPaths) ->
    FAs= get_old_fa(File, OldFunName, Arity),
    [{wrangler_api, rename_fun, [File, F, A, NewFunName, SearchPaths]}||{F, A}<-FAs].

get_old_fa(File, OldFunName, Arity) ->
    {ok, ModuleInfo} = refac_api:get_module_info(File),
    case lists:keyfind(functions, 1, ModuleInfo) of
        {functions, Funs} ->
            case OldFunName of
                {filter, OldFunNameFilter} ->
                    FAs=[{F,A}||{F,A}<-Funs, OldFunNameFilter(F)],
                    filter_with_arity(FAs, Arity);
                _ when is_atom(OldFunName) ->
                    FAs=[{OldFunName,A}||{OldFunName,A}<-Funs],
                    filter_with_arity(FAs, Arity);
                _ -> 
                    throw({error, "Invalid function name."})
            end;
        false ->
            []
    end.

filter_with_arity(FAs, Arity) ->
    case Arity of 
        {filter, ArityFilter} ->
            [{F,A}||{F,A}<-FAs,
                    ArityFilter(A)];
        _ when is_integer(Arity) ->
            [{F,Arity}||{F,Arity}<-FAs];
        _ ->
            throw({error, "Invalid arity."})
    end.
