-module(test2).  

-export([old_api_module_name/0]).

old_api_module_name() ->
    dd.


foo(New) ->
    [self_callout() %%dddd  
       || not false].

self_callout() ->
    dd.
