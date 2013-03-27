/*******************************************************************
--------------------------------------------------------------------
* PARSER.JS
* Erlang -> JSON parsing module
* Authors:        Joe Flood
* Key Functions:  There are some key functions and code blocks to
*                 focus on for core functionality (use ctrl+f to
*                 find):
*
*               parseText()         Take a (sub-)callgraph and return 
*                                   the JSON equivalent
*               eatCallInfoTuple()  Read the call info from a string
*               eatChild()          Read the children from a string
--------------------------------------------------------------------
*******************************************************************/

/**
   * Parses a (sub-)callgraph and returns the JSON version
   * @param  {[string]} text  [The callgraph in string form from Erlang]
   * @return The Object version of the callgraph
   */
function parseText(text) {
  //eat header (call info)
  var callInfo = eatCallInfoTuple(text);
  var i = callInfo.stopIndex;
  var root = callInfo.callgraph;

  if (root === null) return null;

  //eat children
  while (i < text.length)
  {
    var childInfo = eatChild(text, i); //eat one child, and get it's text/end position
    i = childInfo.stopIndex; //fast forward to the end of this child

    if (childInfo.text !== null) //if there was a child and we were at the end...
    {
      var toPush = parseText(childInfo.text);
      if (toPush !== null) root.children.push(toPush); //parse the text of this child into a header + subgraph (recursion!)
    }
  }

  //return this node!
  return root;
}

/**
   * Parses the call info of this (sub-)callgraph 
   * @param  {[string]} text  [The callgraph in string form from Erlang]
   * @return The JSON version of the call info, and where the call info ends in the string
   */
function eatCallInfoTuple(text) {
  var i = 0, level = 0, group = 0;
  var buffer = [], currentGroup = [], groups = [];

  //horrible parse loop :)
  while (i < text.length) {
    var thisChar = text.charAt(i);

    if (thisChar == '{')  //got a {, increase bracket level
      level++;
    else if (thisChar == '}') { //got a }, decrease bracket level and increase group/tuple number
      level--;

      if (buffer.length > 0) {
        currentGroup.push(buffer.join('')); //add this entry (string) to the current group
        groups.push(currentGroup); //add the group to the groups

        currentGroup = []; //start a new group
        buffer = []; //start a new entry
        group++;
      }

      if (level == 0) break; //we are done :D
    }
    else if (thisChar == ',') { //got a ,, next string please
      if (buffer.length > 0) {
        currentGroup.push(buffer.join('')); //add this entry (string) to the current group
        buffer = []; //start a new entry
      }
    }
    else buffer.push(thisChar); //got anything else - append string :)

    i++; //next char :)
  }

  //hacky hacky - now we normalise it so it has two {0, 0}'s if we see just one :)
  var normalisedGroups = [];
  groups.forEach(function(group) {
    normalisedGroups.push(group);

    if (group.length == 2 && group[0] == 0 && group[1] == 0)  //push twice, its {0, 0} :O!
      normalisedGroups.push(group)
  });

  if (normalisedGroups.length == 0)
    return { stopIndex: i, callgraph: null };


  //all done - retrieve data from groups and make sensible!
  

  var noFile = normalisedGroups[1][1] == "0" && normalisedGroups[1][2] == "0";

  var callInfo = {
    module:     normalisedGroups[0][0],
    function:   normalisedGroups[0][1],
    arity:      parseInt(normalisedGroups[0][2]),
    start:      noFile ? { row: 0, column: 0} : { row: parseInt(normalisedGroups[1][1]), column: parseInt(normalisedGroups[1][2]) },
    end:        noFile ? { row: 0, column: 0} : { row: parseInt(normalisedGroups[2][0]), column: parseInt(normalisedGroups[2][1]) },
    callCount:  parseInt(normalisedGroups[noFile ? 6 : 7][0]),
    children:   []
  };


  //return the callgraph and the end index of this header
  return { stopIndex: i, callgraph: callInfo }
}


/**
   * Parses one child of this (sub-)callgraph 
   * @param  {[string]} text  [The callgraph in string form from Erlang]
   * @param  {[int]}    i     [Where to start in the string]
   * @return The plain string of the child, and where it ends in the original string
   */
function eatChild(text, i) {
  var level = 0, start = 0, found = 0;

  if (text.length == 2) return { stopIndex: text.length, text: null };            //we found a "[]" and thus no children - return null to say we've reached the end

  while (i < text.length) {
    var thisChar = text.charAt(i);

    if (thisChar == '[')  { //got a {, increase bracket level
      if (start == 0) start = i;

      found++; //we found at least one child here :)
      level++;
    }
    else if (thisChar == ']') { //got a }, decrease level and increase group
      level--;

      if (level == 0) break; //we are done :D
    }

    i++; //next char
  }

  if (found == 0) return { stopIndex: text.length, text: null };            //we found no brackets and thus no children - return null to say we've reached the end
  else      return { stopIndex: i + 1, text: text.substring(start + 1, i) };  //otherwise - return the end index and the textual representation of the child (for parsing)
};
