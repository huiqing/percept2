-module(pp).

-compile(export_all).

parse_and_pretty_print(File) ->
    AST = parse_file(File),
    {ok, _}=percept2:profile({"pp", wrap, ".dat", 40000000}, 
                            [all, {callgraph, [wrangler_prettypr_v0]}]),
    _Str = print_ast(AST),
    percept2:stop_profile(),
    ok.

parse_file(File) ->
    {ok, {AST, _}}=wrangler_ast_server:parse_annotate_file(File, true),
    AST.

print_ast(AST) ->
    wrangler_prettypr_v0:print_ast('unix', AST).



%% _Res1=percept2:profile({"pp", wrap, ".dat", 40000000}, 
%%                      [all, {callgraph, [wrangler_prettypr_v0]}]),
%% percept2:stop_profile(),

%% pp:parse_and_pretty_print("test.erl").
%% percept2:analyze("pp", ".dat", 0, 13).
