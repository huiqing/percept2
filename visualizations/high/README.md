To run the offline high level visualization, there are several requirements:

All files need to be stored in a webserver, specifically one that can run PHP.
The webserver also needs Java 1.6 or greater.

Once these requirements are met, navigate to regions.html in your HTML5 compliant browser.

It requires three files in various formats, and these formats must be exact.

Example of sgroup format:
```
a b c ab bc ac abc
```

Example of node format:
```
node1 abc
node2 a
node3 ab
node4 ab
node5 b
node6 bc
```

Example of communication format:
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