Navigate to regions.html in your HTML5 compliant browser. You must be connected to the web.

Currently, you will need to run ws/bin/ws-server.php from the command line for the Euler diagram creation to be run. Soon, this will be stored externally so only a web connection will be required.

The visualization requires three files in various formats, and these formats must be exact.

Example of sgroup format (see sgroup.txt):
```
a b c ab bc ac abc
```

Example of node format (see nodes.txt):
```
node1 abc
node2 a
node3 ab
node4 ab
node5 b
node6 bc
```

Example of communication format (see inter_node_sum.txt):
```
{200,
 [{{node1,node11},1,240},
  {{node10,node10},3,152},
  {{node5,node5},3,150},
  {{node2,node2},22,46589}]}.
{400,
 [{{node1,node11},2,318},
  {{node1,node5},11,1091},
  {{node5,node5},19,46439}]}.
```