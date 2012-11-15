-module(test).  


init_group(S, G) ->
  S2 =
    case ?com_bug_013 of   % clear data when initializing a group
      true ->
        IfActive = fun(Tag, Id, X, Y) ->
               case G == com_cfg:ipdu_group(Tag, Id) of
                 true  -> Y;
                 false -> X
               end end,
        Clear = fun(Ipdu = #ipdu_data{kind = Dir, id = Id, pending_notification = Pending}) ->
                      (IfActive(Dir, Id, Ipdu, initial_ipdu_data(com_cfg:get(Dir, Id))))#ipdu_data{
                        pending_notification = Pending };
                   (Sig = #signal_data{kind = K, id = Id}) ->
                        if ?com_bug_030, (Id=='Com_IR26_SiGa' orelse Id=='Com_IR26_SiGb') ->
                                Sig;
                           true ->
                                IfActive(K, Id, Sig, initial_signal_data(com_cfg:get(K, Id)))
                        end
                 end,
        S3 = car_lib:safe_map(Clear, S),
        %% to reflect bug 030, we must copy signal values into the ipdu data
        %% (in the absence of bug 030, this is a no-op)
        lists:foldr(
          fun(#signal_data{kind=rx,id=Id},S0) -> copy_signal_to_ipdu({rx,Id},S0);
             (_,S0)                           -> S0
          end, 
          S3,
          S3#state.signals);
      false -> S
    end,
  reset_timers(clear_group_update_bits(S2, G), G).


bar()->
    id(true).

bar()->
    id(false).

d()->
    id(?com_bug_001).
f() ->
    [11]++[].

foo(Mode, X)->
    [a:self_callout(set_requested_reset, [none])
     , a:schedule(2,
                a:dsd_callout(respond,
                            [<<16#51, (dcm_spec:to_int("Dcm_ResetModeType", Mode))>>,
                             a:mk_callout('BswM_Dcm_RequestResetMode', ['DCM_RESET_EXECUTION'])]))].
