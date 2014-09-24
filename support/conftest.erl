-module(conftest).

-export([start/0]).

start() ->
    EIDirS = code:lib_dir("erl_interface") ++ "\n",
    EILibS =  libpath("erl_interface") ++ "\n",
    RootDirS = code:root_dir() ++ "\n",
    file:write_file("conftest.out", list_to_binary(EIDirS ++ EILibS ++ RootDirS)),
    halt().

%% return physical architecture based on OS/Processor
archname() ->
    ArchStr = erlang:system_info(system_architecture),
    case os:type() of
        {win32, _} -> "windows";
        {unix,UnixName} ->
            Specs = string:tokens(ArchStr,"-"),
            Cpu = case lists:nth(2,Specs) of
                "pc" -> "x86";
                _ -> hd(Specs)
            end,
            atom_to_list(UnixName) ++ "-" ++ Cpu;
        _ -> "generic"
    end.

%% Return arch-based library path or a default value if this directory
%% does not exist
libpath(App) ->
    PrivDir    = code:priv_dir(App),
    ArchDir    = archname(),
    LibArchDir = filename:join([[PrivDir,"lib",ArchDir]]),
    case file:list_dir(LibArchDir) of
        %% Arch lib dir exists: We use it
        {ok, _List}  -> LibArchDir;
        %% Arch lib dir does not exist: Return the default value
        %% ({error, enoent}):
        _Error -> code:lib_dir("erl_interface") ++ "/lib"
    end.

