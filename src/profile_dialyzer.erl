-module(profile_dialyzer).

-export([run_dialyzer/1, percept_profile/1, sample_profile/1]).

-include_lib("kernel/include/file.hrl").


percept_profile(Dir) ->
    percept2:profile("dialyzer.dat", {profile_dialyzer, run_dialyzer, [Dir]},
                     [message, process_scheduling, concurrency,{function, [{dialyzer_succ_typings, '_','_'}]}]).

%%sample:
%% profile:dialyzer:sample_profile(["/proj/wrangler"]).
%% profile:dialyzer:percept_profile(["/proj/wrangler"]).
sample_profile(Dir)->
    percept_sampling:sample(['run_queue','run_queues','scheduler_utilisation',
                             'process_count', 'schedulers_online','mem_info'],
                            {profile_dialyzer, run_dialyzer, [Dir]}).

run_dialyzer(Dir) ->
    {ok, Files} = list_dir(Dir, ".erl"),
    
    try dialyzer:run([{files, Files},{from, src_code},
                      {check_plt, false}])
    catch E1:{dialyzer_error,E2} -> 
            io:format("Error:\n~p\n", [{E1,{dialyzer_error, lists:flatten(E2)}}])
    end.


list_dir(Dir, Extension) ->
    case file:list_dir(Dir) of
	{error, _} = Error-> Error;
	{ok, Filenames} ->
	    FullFilenames = [filename:join(Dir, F) || F <-Filenames ],
	    Matches1 = [F || F <- FullFilenames,
                             file_type(F) =:= {ok, 'directory'}],			 
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
