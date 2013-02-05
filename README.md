percept2
========

Concurrent profiling tool for Erlang

Percept2 is an ehhanced version of the Percept profiling tool from the Erlang/OTP distriution. Percept2 extends 
Percept in two aspects: functionality and acalabity. Among the new functionalities added are:
 
 -- scheduler activity: the number of active schedulers at any time during the profiling;

 -- process migration information: the migration history of a process between run queues;

 -- statistics data about message passing between processes: the number of messages, 
    and the average message size, sent/received by a process;

 -- accumulated runtime per-process: the accumulated time when a process is in a running state;

 -- process tree: the hierarchy structure indicating the parent-child relationships between processes;

 -- dynamic calling-context-aware function call graph;
 
 -- active functions: the functions that are active during a specic time interval;

 -- inter-node message passing: the sending of messages from one node to another;

---- How to install ----











