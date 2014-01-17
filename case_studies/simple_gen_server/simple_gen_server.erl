-module(simple_gen_server).
-behaviour(gen_server).

-export([start/2]).

-export([init/1, terminate/2, code_change/3, start_link/0,
         handle_info/2, handle_call/3, handle_cast/2]).

%% genserver: a gen_server processing a synchronous call
%%   and asked to process asynchronous casts.

start(Pause, Casts) ->
    {ok, Server} = ?MODULE:start_link(),
    register(server, Server),
    [gen_server:call(Server, {synchronous_call, Pause, "Hi!"++integer_to_list(N)}, infinity)
     ||N<-lists:seq(1, Casts)],
    [gen_server:cast(Server, {asynchronous_cast, N})
     || N <- lists:seq(1, Casts)],
    gen_server:call(Server, terminate).


%% Internals

handle_call({synchronous_call, Pause, Msg}, _From, State) ->
    io:format("Synchronous call: ~p.~n", [Msg]),
    timer:sleep(1000 * Pause),
    io:format("Synchronous call response: ~p.~n", ["Hello Joe"]),
    {reply, i_slept_well, State};
handle_call(terminate, _From, State) ->
    {stop, normal, ok, State}.



%% handle_call({synchronous_call, Pause, Msg}, _From, State) ->
%%     timer:sleep(Pause),
%%     {reply, i_slept_well, State};
%% handle_call(terminate, _From, State) ->
%%     {stop, normal, ok, State}.


handle_cast({asynchronous_cast, N}, State) ->
    io:format("Asynchronous cast n*~p done.~n", [N]),
    {noreply, State};
handle_cast(terminate, State) ->
    {stop, ok, State}.

%% handle_cast({asynchronous_cast, N}, State) ->
%%     {noreply, State};
%% handle_cast(terminate, State) ->
%%     {stop, ok, State}.



%% gen_server Internals
start_link() -> gen_server:start_link(?MODULE, [], []).

init([]) -> {ok, []}.

handle_info(Msg, State) ->
    io:format("Unexpected message '~p'~n", [Msg]),
    {noreply, State}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.
terminate(Reason, State) ->
    io:format("~nTerminating with ~p.~n", [[{reason, Reason},
                                            {state, State}]]).


%% percept2:profile("simple_gen_server1.dat", {simple_gen_server, start, [1000, 1000]}, [all, {callgraph, [simple_gen_server]}]).
 

 %% rpc:call('percept2@127.0.0.1', percept2, profile, ["simple_gen_server1.dat", {simple_gen_server, start, [1000, 1000]},[all, {callgraph, [simple_gen_server]}]]).

