-module(test3).  

foo(New) ->
    [self_callout() %%dddd  
       || not false].

self_callout() ->
    dd.
