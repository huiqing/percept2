
-module(sorter_sel).
-export([go/3,loop/0,main/4]).


%% This example starts a tree of processes that does 
%% sorting of random numbers. A controller process 
%% is used to distributes work to different client
%% processes.
%%
%% I: number of times to generate sort work.
%% N: to control the range of random integer generation.
%% M: number of client processes.

go(I,N,M) ->
    spawn(?MODULE, main, [I,N,M,self()]),
    receive done -> ok end.

main(I,N,M,Parent) ->
    Pids = lists:foldl(
             fun(_,Ps) ->
                     [percept2_utils:spawn(?MODULE,loop, []) | Ps]
             end, [], lists:seq(1,M)),
    lists:foreach(
      fun(_) ->
              send_work(N,Pids),
              gather(Pids)
      end, lists:seq(1,I)),
    lists:foreach(
      fun(Pid) ->
              Pid ! {self(), quit}
      end, Pids),
    gather(Pids), Parent ! done.

send_work(_,[]) -> ok;
send_work(N,[Pid|Pids]) ->
    Pid ! {self(),sort,N},
    send_work(round(N*1.2),Pids).

loop() ->
    receive
        {Pid, sort, N} -> 
            dummy_sort(N),Pid ! {self(), done},loop();
        {Pid, quit} -> 
            Pid ! {self(), done}
    end.

dummy_sort(N) -> 
    lists:sort([ random:uniform(N) 
                 || _ <- lists:seq(1,N)]).

gather([]) -> ok;
gather([Pid|Pids]) -> 
    receive 
        {Pid, done}-> gather(Pids)
    end.


%% Percept commands.

%% percept:profile("test.dat", {sorter, go, [5, 2000, 15]}, [procs]). 

%% percept:analyze("test.dat").

%% percept:start_webserver().


%% Percept2 commands:

%% percept2:profile("sorter.dat", {sorter, go, [5, 2000,15]}, [all, {callgraph, [sorter]}]).

%% percept2:analyze(["sorter.dat"]).

%% percept2:start_webserver().



%% Percept2 commands:

%% percept2:profile("sorter_sel.dat", {sorter_sel, go, [5, 2000,15]}, [all, {callgraph, [sorter_sel]}]).

%% percept2:analyze(["sorter_sel.dat"]).

%% percept2:start_webserver().
