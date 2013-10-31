var circles = [];
var nodes = [];
var edges = [];
var zones = [];
var multiplier = 3;
var c = 20;
var t = 200;
var k;
var rectangles;
var currentTime = 0;

var svg;
var times = [];

var conn = new WebSocket('ws://localhost:8081');
//var conn = new WebSocket('ws://cs.kent.ac.uk/~rb440/:8081');
conn.onopen = function(e) {
    console.log("Connection established!");
};

conn.onmessage = function(e) {
    parseCircles(e.data);
};

/** A labelled circle */
function Circle(label,r,x,y) {
	this.label = label;
	this.r = r;
	this.x = x;
	this.y = y;
}


function Rectangle(x,y,width,height) {
	this.x = x;
	this.y = y;
	this.width = width;
	this.height = height;
	this.label = "";
}

function Point(x,y) {
	this.x = x;
	this.y = y;
}


function Node(label,region){
	this.label = label;
	x = 0.0;
	y = 0.0;
	this.region = region;
	horizontal = 0;
	vertical = 0;
}

function Edge(source, target, size){
	this.source = source;
	this.target = target;
	this.size = size;
}


function Time(time){
	this.time = time;
	this.interactions = [];
}

function Interaction(start, end, size){
	this.start = start;
	this.end = end;
	this.size = size;
}


/*
Finds a circle given a label
 */
function findCircle(label){
	for (var i = 0; i < circles.length; i++){
		if (label == circles[i].label){
			return circles[i];
		}
	}
}

/*
Finds a rectangel given a label
*/
function findRectangleFromLabel(label, rectangles){

	for (var i = 0; i < rectangles.length; i++){
		if (label.trim() == rectangles[i].label.trim()){
			return rectangles[i];
		}
	}
}

/*
Finds a node given a label
*/
function findNode(label, nodes){
	for (var i = 0; i < nodes.length; i++){
		//console.log(nodes[i].label,label, nodes[i].label == label);
		if (nodes[i].label == label) {
			return nodes[i];
		}
	} 
}

function stringCompare(s1, s2){
	console.log(s1.length,s2.length, s1.charAt(1));
	if (s1.length != s2.length){
		return false;
	}
	for (var i = 0; i < s1.length; i++){
		//console.log(s1.charAt(i),s2.charAt(i));
		if (s1.charAt(i) != s2.charAt(i)){
			return false;
		}
	}
	return true;

}


var sGroupsRead = false;
function readSGroup(){
	//console.log("reading s group");
	readFile("sGroup");
}

var nodesRead = false;
function readNodes(){
	//console.log("reading s group");
	readFile("nodes");
}

var commsRead = false;
var commsData;
function readComms() {
	readFile("comms");
}


/**
*	Reads a file from the user and interacts with is as appropriate
*/
function readFile(fileType){
	var uploadName = "#"+fileType+"Upload";
	var feedbackName = "#"+fileType+"Feedback";

	var file = $(uploadName)[0].files[0];
	//var output;

	var read=new FileReader();
	read.readAsText(file);

	read.onerror=function(){
		$(feedbackName).html("An error has occurred");
	}

	read.onprogress=function(evt){
		//console.log(evt.loaded, evt.total);
		var percent = parseInt((evt.loaded / evt.total)*100);

		$(feedbackName).html("Loading: "+percent+"% complete");
	}

	read.onloadend=function(){

		$(feedbackName).html("Upload Complete");
		//console.log(output);
		var output = read.result;
		//console.log(output);

		if (fileType == "sGroup"){
			sGroupsRead = true;

			//parseCircles(output);
			conn.send(output);

			$(sGroupUpload).hide();
			$(nodesBox).show();

/*
			if (nodesRead){
				parseNodes(output);
			}

			if (nodesRead && sGroupsRead && commsRead){
				parseComms(commsData);
				buildGraph();
			}*/
		} else if (fileType == "nodes"){
			nodesRead = true;

			parseNodes(output);

			$(nodesUpload).hide();
			$(commsBox).show();
/*
			if (sGroupsRead){
				
			}
			
			if (nodesRead && sGroupsRead && commsRead){
				parseComms(commsData);
				buildGraph();
			}
*/
		} else if (fileType == "comms"){
			commsRead = true;
			commsData = output;
			

			//if (nodesRead && sGroupsRead && commsRead){
				parseComms(output);

				$(instructions).hide();
				$(main).show();

				drawGraph(nodes, times[0].interactions, rectangles, circles);
			//}
		}
		
	}
}

function parseNodes(nodesFile) {

	var nodesArr = nodesFile.split("\n");

	for (var i = 0; i < nodesArr.length; i++){
		var thisLine = nodesArr[i].split(" ");
		if (zones.indexOf(thisLine[1]) == -1){
			zones.push(thisLine[1]);
		}
		var zone = zones[zones.indexOf(thisLine[1])].trim();
	}

//	console.log(zones, circles);

	rectangles = findZoneRectangles(zones, circles);
	for(var i =0; i<rectangles.length; i++){
		rectangles[i].label.trim();
	}

	//console.log(rectangles);

	for (var i = 0; i < nodesArr.length; i++){
		var thisLine = nodesArr[i].split(" ");
		var nodeLabel = thisLine[0];

		//console.log();
		//add region of node to be rectangle

		var node = new Node(nodeLabel, findRectangleFromLabel(thisLine[1], rectangles));
		nodes.push(node);
	}
	console.log(circles, nodes, rectangles);
}

function parseCircles(input){

	console.log(input);

	//var url = "http://www.cs.kent.ac.uk/people/rpg/rb440/Release/runJava.php?input="+input;
	//var url = "runJava.php?input="+input;

	circleFile = input.split("\n")
	//use 1 as first row of input are labels
	for (var i = 1; i < circleFile.length-1; i++){
		var result = circleFile[i].split(",");
		//console.log(result);
		var c = new Circle(result[0].trim(), parseInt(result[3]), parseInt(result[1]), parseInt(result[2]));
		circles.push(c);	
	}

	
}

function parseComms(commsFile){
	var input = commsFile.split(".");
					
	//console.log(input[0], times);	
	for (var i = 0; i < input.length; i++){
	//for (var i = 0; i < 2; i++){
		var timeInstance = input[i];

		var interactions = timeInstance.split(",\n");
		
		var timeInt = "";
		if (i == 0) {
			timeInt = parseInt(interactions[0].substring(1));
		} else {
			timeInt = parseInt(interactions[0].substring(2));
		}

		var time = new Time(timeInt);
		times.push(time);

		for (var j = 1; j < interactions.length; j++){
			var interactionDetails = interactions[j].split(",");

			var start = parseInt(interactionDetails[0].substring(8));
			var finish = parseInt(interactionDetails[1].substring(4));
			var count = parseInt(interactionDetails[2]);

			//console.log(time);

			var startNode = findNode("node"+start, nodes);
			var finishNode = findNode("node"+finish, nodes);
			//console.log(startNode, start, nodes);
			var edge = new Edge(startNode, finishNode, count);

			time.interactions.push( edge );

			//console.log(start, finish, count);
		}

	}

	console.log(times);

}

function next(){
	iterateGraph(nodes, times[currentTime].interactions);
}


function animate(){
	var m = 0;
	var changeValue = 100;
	$("#time").html(times[currentTime].time+" ms");
	var interval = setInterval(
		function() {
			m++;
			//console.log("m", m, "currentTime", currentTime);
			if (m % changeValue == changeValue-1) {
				currentTime++;
				$("#time").html(times[currentTime].time+" ms");
				if (currentTime == times.length){
					window.clearInterval(interval);
					console.log("done");
					return;
				}
				drawEdges(times[currentTime].interactions);
			}
			next();
		}
	,10);
}