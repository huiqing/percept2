-module(pingpong).

loop_a() ->
    receive
	stop -> ok;
	{msg,_Msg,0} -> loop_a();
	{msg,Msg,N} ->
            io:format("ping!~n"),
            timer:sleep(500),
            b!{msg,Msg,N+1},
            loop_a()
    end.

loop_b() ->
    receive
	stop -> ok;
	{msg,_Msg,0} -> loop_b();
	{msg,Msg,N} ->
	    io:format("pong!~n"),
	    timer:sleep(500),
	    a!{msg,Msg,N+1},
	    loop_b()
    end.

