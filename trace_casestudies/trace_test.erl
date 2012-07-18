-module(trace_test).

-export([foo/0]).
-compile(export_all).

r() ->
    P1 = spawn(?MODULE,p,[]),
    %%P1 = (dbg:trace_port(file, "c:/cygwin/home/hl/percept/trace_casestudies/trace.dat"))(),
    P2 = spawn(?MODULE,p,[]),
    wrangler_io:format("P1,P2:~p\n", [{P1, P2}]),
    Q1 = spawn(?MODULE,q,[]),
    Q2 = spawn(?MODULE,q,[]),
    wrangler_io:format("Q1,Q2:~p\n", [{Q1, Q2}]),
    wait(),
    erlang:trace(Q1,true,[{tracer,P1},call, 'receive' , send, timestamp]),
    Res= erlang:trace_pattern({trace_test, '_', '_'},
                               [{'_',[],[{return_trace}]}],[local]),
    io:format("Res:\n~p\n", [Res]),
    wait(),
    Q1 ! foo,
    wait(),
    Q1 ! foo,
    wait(),
    erlang:trace(Q2,true,[{tracer,P2},'receive', send]),
    wait(),
    Q1 ! foo,
    wait(),
    Q2 ! foo,
    wait(),
    wait(),
    foo(),
    Q1 ! foo,
    wait(),
    Q2 ! foofooo,
    wait(),
    P1! stop,
 %%   erlang:port_close(P1),
    P2 ! stop,
    Q1 ! stop,
    Q2 ! stop.
   
wait() ->
    receive
	after 1000 ->
		ok
    end.

foo() ->
    R =1 +1,
    R.

p() ->
    receive
	stop ->
	    ok;
	Msg ->
	    io:format("~p  ~p\n",[self(),Msg]),
	    p()
    end.

q() ->
    receive
	stop ->
	    ok;
	_ ->
            foo(),
	    q()
    end.
