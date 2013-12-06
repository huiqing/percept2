-module(percept2_dist). 

-compile(export_all).

-include("../include/percept2.hrl").

-type nodes()::atom() | [atom()] | all | existing | new.
-type procs()::all | existing | new.

%% should be able to accept more flags.
-type flag()::send|'receive'|s_group.

%%@see ttb for possible values for Opts.
-spec(start(Nodes::nodes(), Procs::procs(), Flags::[flag()], Opts::[term()])-> ok).
start(Nodes, Procs, Flags, Opts) ->
    {TraceOpts, ModOrMFAs} = parse_profile_options(Flags),
    MFAs = [MFA||MFA={_M, _F, _A}<-ModOrMFAs],
    _Ref1=ttb:start_trace(Nodes, MFAs, {Procs, TraceOpts}, Opts),    
    ok.

start(Nodes, {M, F, Args}, Procs, Flags, Opts) ->
    {TraceOpts, ModOrMFAs} = parse_profile_options(Flags),
    MFAs = [MFA||MFA={_M, _F, _A}<-ModOrMFAs],
    _Ref1=ttb:start_trace(Nodes, MFAs, {Procs, TraceOpts}, Opts),
    Self=self(),
    Pid=spawn(fun()->
                      Res=erlang:apply(M, F, Args),
                      Self!{self(),Res}
              end),
    receive
        {Pid, _Val}->
            ttb:stop()
    end.

stop()->
    ttb:stop().

 
parse_profile_options(Opts) ->
    parse_profile_options(Opts, {[],[]}).

parse_profile_options([], {TraceOpts, Patterns}) ->
    {TraceOpts, lists:append(Patterns)};
parse_profile_options([Opt|Opts],{TraceOpts, ModOpts}) ->
    case Opt of
        s_group ->
            parse_profile_options(
              Opts, {TraceOpts, [module_funs(s_group)|ModOpts]});
	_ -> 
            case lists:member(Opt, trace_flags()) of 
                true ->
                    parse_profile_options(
                      Opts, {[Opt|TraceOpts], ModOpts});
                false -> 
                    parse_profile_options(Opts, {TraceOpts, ModOpts})
            end
    end.

trace_flags()->
    ['all','send','receive','procs','call','silent',
     'return_to','running','exiting','garbage_collection',
     'timestamp','cpu_timestamp','arity','set_on_spawn',
     'set_on_first_spawn','set_on_link','set_on_first_link',
     'scheduler_id', 'ports'].

module_funs(s_group) ->
    [{s_group, new_s_group, 2}, 
     {s_group, delete_s_group, 1},
     {s_group, add_nodes, 2},
     {s_group, remove_nodes, 2}].


     
