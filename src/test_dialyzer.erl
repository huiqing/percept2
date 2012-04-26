-module(test_dialyzer).

-export([test/1, test/0]).

-include_lib("kernel/include/file.hrl").

test() ->
    percept_profile:start({file, "dialyzer.dat"}, {test_dialyzer, test, ["c:/cygwin/home/hl/git_repos/percept/test_dialyzer"]},
                          [dialyzer_succ_typings], []).

 %% dilyzer_callgraph,
 %%                           dialyzer_dataflow, dialyzer_typesig,
 %%                           dialyzer_analysis_callgraph],[]).

test(Dir) -> 
    {ok, Files} = list_dir(Dir, ".erl",false),
    try dialyzer:run([{files, Files},{from, src_code},
                      {check_plt, false}])
    catch E1:{dialyzer_error,E2} -> 
            io:format("Error:\n~p\n", [{E1,{dialyzer_error, lists:flatten(E2)}}])
    end.


list_dir(Dir, Extension, Dirs) ->
    case file:list_dir(Dir) of
	{error, _} = Error-> Error;
	{ok, Filenames} ->
	    FullFilenames = [filename:join(Dir, F) || F <-Filenames ],
	    Matches1 = case Dirs of
			   true ->
			       [F || F <- FullFilenames,
				     file_type(F) =:= {ok, 'directory'}];
			   false -> []
		       end,
	    Matches2 = [F || F <- FullFilenames,
			     file_type(F) =:= {ok, 'regular'},
			     filename:extension(F) =:= Extension],
	    {ok, lists:sort(Matches1 ++ Matches2)}
    end.

-spec file_type(file:filename()) ->
		       {ok, 'device' | 'directory' | 'regular' | 'other'} |
		       {error, any()}.

file_type(Filename) ->
    case file:read_file_info(Filename) of
	{ok, FI} -> {ok, FI#file_info.type};
	Error    -> Error
    end.
