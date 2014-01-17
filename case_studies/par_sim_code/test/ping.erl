-module(ping).  

-export([start/0, stop/1, send/1, loop/0]).

start() ->
     spawn_link(ping, loop, []).

stop(Pid) ->
    Pid ! stop.

send(Pid) ->
    Pid ! {self(), ping},
    receive 
        pong ->pong 
    end.


loop()->
    receive
        {Pid, ping} ->
            spawn(crash, do_not_exist, []),
            Pid !pong,
            loop();
        stop ->
            ok
    end.
