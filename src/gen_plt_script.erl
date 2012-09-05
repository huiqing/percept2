%#!/usr/bin/env escript
-module(gen_plt_script).

-export([gen_plt_script/6]).

gen_plt_script(Title, XLabel, YLabel, LineLabel, DataFile, OutFile)-> 
    {ok, FD}= file:open(DataFile, [read]),
    FirstLine=file:read_line(FD),
    case FirstLine of 
        {error, Reason} ->
            {error, Reason};
        eof ->
            {error, eof};
        {ok,Data} ->
            file:close(FD),
            gen_plt_sript_1(Title, XLabel, YLabel, LineLabel, Data,DataFile,OutFile)
    end.
    
gen_plt_sript_1(Title, XLabel, YLabel, LineLabel, DataStr, DataFile, OutFile) ->
    NoCols=length(string:tokens(DataStr, " \n")),
    OutStr1="set title \""++Title++"\"\n" ++
        "set autoscale \n" ++
        "set xtic auto \n" ++
        "set ytic auto \n" ++
        "set xlabel \""++XLabel++"\"\n"++
        "set ylabel \""++YLabel++"\"\n"++
        "set grid \n" ++
        "plot ",
    ColIndexs = lists:reverse(lists:seq(2, NoCols)),
    PlotStr= [begin
                  SubTitleStr = LineLabel++integer_to_list(Index-1),
                  Str="\""++DataFile++"\" using 1:"++ integer_to_list(NoCols-Index+2)++
                      " title \'"++SubTitleStr ++"\' with filledcurves x1 linestyle "++integer_to_list(Index-1), 
                  case Index of 
                      2 -> Str++"\n";
                      _ -> Str++", \\\n"
                  end 
              end|| Index<-ColIndexs],
    OutStr=OutStr1++lists:flatten(PlotStr),
    {ok,FD} = file:open(OutFile,[write]),
    file:write(FD, list_to_binary(OutStr)),
    file:close(FD).

    
%% gen_plt_script:gen_plt_script("Run Queue Length Graph", "Time(Seconds)","Run Queue Length", "Run Queue #", "sample_run_queues.dat", "sample_run_queues.plt").
    
    
    
 %% gen_plt_script:gen_plt_script("Scheduler Utilisation Graph", "Time(Seconds)","Scheduler Utilisation", "Scheduler #", "sample_scheduler_utilisation.dat", "sample_scheduler_utilisation.plt").
