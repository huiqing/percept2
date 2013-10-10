function Time(time) {
	this.time = time;
	queues = new Array();
	activities = new Array();
}
		
function Queue(id, order) {
	this.id = id;
	this.order = order;
	usage = 0;
	takenSpots = new Array();
	sharedNodes = new Array();
}

function Process(a,b,c) {
	this.a = a;
	this.b = b;
	this.c = c;
	queues = new Array();
	previousQueue = -1;
}

function Activity(process, queue){
	this.process = process;
	this.queue = queue;
	thisGap = 0;
}

var resolution = 1000; //the number of divisions of a second to make each iteration. e.g. 1000 = 1000th or 0.001s
var intervalTimer = 200; //number of milliseconds between each iteration on display

var testing = false;

//order of the queues on the screen

if (testing){
	//var order = [1,13,3,15,5,17,7,19,9,21,11,23,26,27,0,12,2,14,4,16,6,18,8,20,10,22,25,24];
	//var nodeGroupings = [[1,13],[3,15],[5,17],[7,19],[9,21],[11,23],[26,27],[0,12],[2,14],[4,16],[6,18],[8,20],[10,22],[24,25]];

	var order = [1,13,3,15,5,17,7,19,9,21,11,23,26,0,12,2,14,4,16,6,18,8,20,10,22,25,24]; //list of queueIDs.
	var nodeGroupings = [[1,13],[3,15],[5],[17,7],[19],[9,21],[11,23,26],[0,12],[2,14],[4,16],[6,18],[8,20],[10,22],[24,25]];
} else {
	var order = [1,13,3,15,5,17,7,19,9,21,11,23,0,12,2,14,4,16,6,18,8,20,10,22]; //list of queueIDs.
	var nodeGroupings = [[1,13],[3,15],[5,17],[7,19],[9,21],[11,23],[0,12],[2,14],[4,16],[6,18],[8,20],[10,22]];

}


var times = [];
var processes = [];
/*
*	Parse the queue lengths
*/
function parse(output){
	// create all the timing blocks
	var data = output[output.length-1].split("  ");
	iterations = Math.floor(parseFloat(data[0])*resolution);
	//console.log(output);
	//console.log(times);
	for(var i = 0; i <= iterations; i++){
		//console.log(i);
		times.push(new Time(i));
	}
	//console.log(times);
	for (var i = 0; i < output.length; i++){
		var data = output[i].split("  ");
		
		time = Math.floor(parseFloat(data[0])*resolution); //floor() is acceptable as time will always be positive
		//console.log(time);
		t = getTime(time);
		//t = new Time(time);
		//times.push(t);
		t.queues = new Array();
		for (var j = 1; j < data.length-1; j++){
			q = new Queue(j-1,findOrder(j-1));
			q.usage = data[j];
			q.takenSpots = new Array();
			t.queues.push(q);
		}
	}
}

/*
*	Finds a time object given a value for that time. Returns null if one not found
*/
function getTime(time){
	//console.log(time);
	for (var i = 0; i < times.length; i++){
		if (times[i].time == time){
			//console.log(times[i].time);
			return times[i];
		}
	}
	return null;
}

/*
* Finds a process object given the 3 process id values
*/
function findProcess(a,b,c) {
	for (var i = 0; i < processes.length; i++){
		if ((processes[i].a == a) && (processes[i].b == b) && (processes[i].c == c)){
			//console.log(processes[i].a, processes[i].b, processes[i].c);
			return processes[i];
		}
	}
	return null;

}

/*
*	Finds a queue with the id qId in the collection queues
*/
function getQueue(queues, qId){
	for (var i = 0; i < queues.length; i++){
		if (queues[i].id == qId){
			return queues[i];
		}
	}
	return null;
}

/*
*	Finds a queue order given a id number
*/
function findOrder(id){
	for (var i = 0; i < order.length; i++){
		if (order[i] == id){
			return i;
		}
	}
	return -1;
}

function getQueueFromOrder(orderID){
	return order[orderID];
}

/*
* Performs a logical exclsuive OR
*/
function XOR(a, b){
	return ( a || b ) && !( a && b );
}


/*
*	Parse the queue lengths
*/
function parseMigration(output){
	for (i = 0; i < output.length; i++){
	//i = 0;
		elements = output[i].split(",");
		//console.log(elements);
		var time = Math.floor(parseFloat(elements[0].substring(1,elements[0].length))*resolution);
		//console.log(time);
		var t = getTime(time);
		//console.log(t);
		if (t.activities == undefined){
			t.activities = new Array()
		}
		var a = parseInt(elements[2].substring(1,elements[2].length));
		var b = parseInt(elements[3]);
		var c = parseInt(elements[4]);
		
		var p = findProcess(a,b,c);
		if ((p == null) || (p == undefined)) {
			p = new Process(a,b,c);
			processes.push(p);
			p.queues = new Array();
		}
		var qId = parseInt(elements[5])-1;
		p.queues.push(qId);
		p.previousQueue = -1;
		//console.log(p);
		var a = new Activity(p,qId);
		a.thisGap = 0;
		t.activities.push(a);
		
	}
}

function buildSharedNodes(queues){
	for (i = 0; i < nodeGroupings.length; i++){
		var sharedNodes = nodeGroupings[i];
		for (j = 0; j < sharedNodes.length; j++){
			var q = getQueue(queues, sharedNodes[j]);
			//q.sharedNodes = removeFromArray(sharedNodes,sharedNodes[j]);
			q.sharedNodes = sharedNodes;
			//console.log(q);
		}
		//console.log(sharedNodes);
	}

}

/**
*	Removes the given value from the given array
*/
function removeFromArray(arr, value){
	console.log(arr, value);
	var index = arr.indexOf(value);
	if (index != undefined){
		arr.splice(index,1);
		return arr;
	}
	return arr;
}



var migrationRead = false;
var migrationOutput = [];
function readMigration(){
	readFile("migration");
}

var queueRead = false;
var queueOutput = [];
function readQueue(){
	readFile("queue");
}

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
		var output = read.result.split("\n");


		if(fileType == "migration"){
			migrationOutput = output;
			migrationRead = true;
			//console.log(output);
			//parseMigration(output);
		} else if(fileType == "queue"){
			queueOutput = output;
			queueRead = true;
			//console.log(output);
			//parse(output);
		}

		if (queueRead && migrationRead){
			console.log("q", queueOutput[0]);
			console.log("m", migrationOutput[0]);

			parse(queueOutput);
			parseMigration(migrationOutput);
			$("#instructions").hide();
			$("#main").show();

			start();

		}
		
	}
}


/*
* Read the files in and parse them
*/
var intervalObj;
var intervalCounter = 0;
var previousState;
function start() {
	
	//var txtFile = new XMLHttpRequest();
/*
	if (testing){
		txtFile.open("GET", "runQtest.txt", true);
	} else {
		txtFile.open("GET", "sample_run_queues.txt", true);
	}

	txtFile.onreadystatechange = function() {
		if (txtFile.readyState != 4) {
			window.status="Loading";
		} else {
			if (txtFile.status === 200) { 
				window.status="Loading";		
				var output = txtFile.responseText.split("\n"); 
				//console.log("anon function");
				parse(output);	
				
			}
		}
	};
	txtFile.send(null);
	var jsonFile = new XMLHttpRequest();
	jsonFile.open("GET", "rq_migration_by_time.txt", true);
	jsonFile.onreadystatechange = function() {
		if (jsonFile.readyState === 4) {  
			if (jsonFile.status === 200) {  
				var output = jsonFile.responseText.split("\n"); 
				parseMigration(output);
				
			}
		}
	};*/
	
	//console.log(times);
	prepareDrawing();
	animate(intervalCounter,intervalTimer);

	//jsonFile.send(null);
}

/*
* Stops the animation
*/
function stop() {
	clearInterval(intervalObj);
}

/*
* Continues the animation from where it was left off
*/
function continueAnimation() {
	animate(intervalCounter, intervalTimer);
}

/*
* Restarts the animation
*/
function restartAnimation() {
	animate(0, intervalTimer);
}

/*
* Handles the user clicking the pause button - changes label and task depending on state
*/
var paused = false;
function pauseAnimation() {
	var button = d3.select("#pause");
	if (paused){
		continueAnimation();
		paused = false;
		button.attr("value","Pause");
	} else {
		stop();
		paused = true;
		button.attr("value","Resume");
	}
	
}

/*
* Animate the display from a given start point
*/
function animate(intervalCount, timeGap){
	
	window.status="";
	intervalCounter = intervalCount;
	//console.log(times);
	intervalObj = window.setInterval(function() {	
			//console.log(times);				
			if (intervalCounter >= times.length){
				stop();
			} else {
				draw(intervalCounter); 
				intervalCounter++;
			}
		}, timeGap);
}

/*
* Returns the angle for a given queue - in radians
*/
function calculateAngle(itemNum, totalItems){
	return (itemNum * ((2 * Math.PI) / totalItems)) + (Math.PI / totalItems); //+0.13
}

/*
* Calculates the X cooridnate for a point on the circle 
*/
function calcXValue(cx, rx, ry, order, length, boxSize){
	//return cx + (rx * Math.cos(id * ((2 * Math.PI) / length))) ; //circle
	
	//d = id * ((2 * Math.PI) / length);
	d = calculateAngle(order, length);
	if ((d < (Math.PI / 2)) ||  (d > (3 *Math.PI / 2 ))){
		m = 1;
	} else {
		m = -1;
	}
	//console.log("calcX", order, d, ( m * rx * ry ), Math.sqrt( (rx * rx * Math.tan(d) *  Math.tan(d)) + (ry * ry) ), (( m * rx * ry ) / Math.sqrt( (rx * rx * Math.tan(d) *  Math.tan(d)) + (ry * ry) )) + cx - (boxSize/2));
	return (( m * rx * ry ) / Math.sqrt( (rx * rx * Math.tan(d) *  Math.tan(d)) + (ry * ry) )) + cx - (boxSize/2);
}
			
/*
* Calculates the Y cooridnate for a point on the circle 
*/			
function calcYValue(cy, rx, ry, order, length, boxSize){
	//return cy + (ry * Math.sin(id * ((2 * Math.PI) / length))) - (boxSize/2); //circle
	
	//d = id * ((2 * Math.PI) / length);
	d = calculateAngle(order, length);
	//console.log(id, d);
	if ((d > Math.PI/2) && (d <= (3*Math.PI)/2 ) ){
		m = 1;
	} else {
		m = -1;
	}
	return (( m * rx * ry * Math.tan(d) ) / Math.sqrt( (rx * rx * Math.tan(d) *  Math.tan(d)) + (ry * ry) )) + cy - (boxSize/2);
}

/*
* Calculates the height of a queue box
*/
function calcHeight(usage){
	usage = parseInt(usage);
	if (usage == 0) {
		return 0;
	} else if (usage > 100) {
		useage = 100
	}
	//return (10*Math.log(parseInt(usage)))+5;
	return usage*2;
}


/*
*	finds the first gap in an array of integers - this is to find the next spot for placing a spawning process
*/
function findFirstGap(takenSpots) {
	if (takenSpots.length == 0){
		return 0;
	}
	var lastValue = takenSpots[takenSpots.length-1];
	for (i = 0; i < lastValue; i++){
		//if this value isn't in the array
		if (takenSpots.indexOf(i) == -1){
			return i;
		}
	}
	return lastValue+1;

}

function prepareDrawing() {
	d3.select("#loading").remove();
	
	//console.log("preparing");
	//var svg = d3.select("#svgdiv")
	//var svg = d3.select("div")
	var svg = d3.select("#svgdiv")
		.append("svg")
		.attr("width", originalWidth)
		.attr("height", originalHeight)
		.attr("xmlns","http://www.w3.org/2000/svg")
		.attr("version","1.1")
		.attr("id","canvas");

	//console.log(svg);
	
	

		
	/*svg.append("ellipse")
		.attr("cx",cx)
		.attr("cy",cy)
		.attr("rx",rx)
		.attr("ry",ry)
		.attr("stroke","black")
		.attr("fill","none");*/

}

function draw(timeInstance) {

	intervalCounter = timeInstance;
	//if it hasn't loaded the svg elements yet, then prepare the drawing again
	if (d3.select("svg").empty()){
		//console.log("empty");
		prepareDrawing();
	}
	//console.log(Math.round(timeInstance*(1000/times.length)));
	$("#slider").slider("option","value",Math.round(timeInstance*(1000/times.length)));

	//console.log(previousState);
	var thisGap = 0;
	//console.log(timeInstance, times[timeInstance], times.length);
	var activities = times[timeInstance].activities;
	//console.log(timeInstance/resolution, activities);
	
	//If no previous state has been set, assume it's the starting configuration
	if (!previousState) {
		previousState = times[0].queues;
	}
	//if there's no queue data for this time frame, use the previous state. If there is, use that and set it as the previous state
	if (times[timeInstance].queues == undefined){
		dataset = previousState;
	} else {
		dataset = times[timeInstance].queues;
		previousState = dataset;
	}
	//console.log(dataset);
	//clears the svg before drawing the next batch
	//d3.select("svg").remove();

	buildSharedNodes(dataset);

	document.getElementsByTagName("html")[0].style.fontSize = (2500 / dataset.length) + "%";

	d3.selectAll("g").remove();
	d3.selectAll("ellipse").remove();
	d3.selectAll("#its").remove();
	d3.selectAll("#time").remove();
	d3.selectAll(".grouping").remove();
	d3.selectAll(".nodeArea").remove();
	//d3.selectAll("text").remove();
	var svg = d3.select("svg");

	/**
	svg.append("circle")
		.attr("cx",cx)
		.attr("cy",cy)
		.attr("r",ry);					
**/




	var gEnter = svg.selectAll("g")
		.data(dataset)
		.enter()
		.append("g");
	
	/* 
	*	process id labels
	*/
	gEnter.append("text")
		.text(function (d) {
			return d.id; // + " a:" + calculateAngle(d.order,dataset.length);
		})
		.attr("x", function(d) {
			console.log(boxSize);
			return parseInt(calcXValue(cx, rx+(boxSize/2), ry+(boxSize/2), d.order, dataset.length, 0));
		})
		.attr("y", function(d) {
			return parseInt(calcYValue(cy, rx+(boxSize/2), ry+(boxSize/2), d.order, dataset.length, 0));
		})
		.attr("width",40)
		.attr("height",40)
		.attr("text-anchor", "middle")
		.attr("class","queue")
		.attr("id",function(d){
			return "label"+d.id;
		})
		.append("svg:title")
		.text(function(d) {
			return "Queue: "+d.id+", Size:"+d.usage;
		});;
		
	/*
	*	Node grouping highlighting
	*/

	svg.selectAll("ellipse")
		.data(nodeGroupings)
		.enter()
		.append("ellipse")
		.attr("cx",function (d) {
			//console.log(d.length);
			var firstX = parseInt(d3.select("#label"+d[0]).attr("x"));
			var secondX = parseInt(d3.select("#label"+d[d.length-1]).attr("x"));
			//console.log("x", d[0],firstX,d[1],secondX,(firstX - secondX),((firstX - secondX)/2)+parseFloat(secondX));
		
			//var firstX =  calcXValue(cx, rx, ry, d[0], dataset.length, boxSize);
			//var secondX =  calcXValue(cx, rx, ry, d[1], dataset.length, boxSize);
			return parseInt(((firstX - secondX)/2)+parseFloat(secondX))+"";
		})
		.attr("cy",function (d) {
			var firstY = parseInt(d3.select("#label"+d[0]).attr("y"));
			var secondY = parseInt(d3.select("#label"+d[d.length-1]).attr("y"));
			//console.log("y",d[0],firstY,d[1],secondY,(firstY - secondY),((firstY - secondY)/2)+parseFloat(secondY));
			return parseInt(((firstY - secondY)/2)+parseFloat(secondY))+"";
			//return calcYValue(cy, rx, ry, d[0], dataset.length, boxSize);
		})
		.attr("rx",function (d) {
			return (960/dataset.length) * (d.length/2);
		})
		.attr("ry",480/dataset.length)
		.attr("class","grouping")
		.attr("id",function(d) {
			return d[0] + " " + d[1];
		})
		.attr("transform",function(d){
			//return "rotate(" + calculateAngle(d.order,dataset.length) +  ")";
			var firstAngle = parseInt(90 - ((180/Math.PI)*calculateAngle(findOrder(d[0]),dataset.length)) );
			var secondAngle = parseInt(90 - ((180/Math.PI)*calculateAngle(findOrder(d[d.length-1]),dataset.length)) );
			//console.log("id"+d[0], "order"+findOrder(d[0]), firstAngle, "id"+d[1], "order"+findOrder(d[1]), secondAngle, (firstAngle-secondAngle)/2, ((firstAngle - secondAngle)/2)+secondAngle);
			var angle = ((firstAngle - secondAngle)/2)+secondAngle;
			//var angle = secondAngle;
			
			var centreX = ((d3.select("#label"+d[0]).attr("x") - d3.select("#label"+d[d.length-1]).attr("x"))/2)+parseFloat(d3.select("#label"+d[d.length-1]).attr("x"));
			var centreY = ((d3.select("#label"+d[0]).attr("y") - d3.select("#label"+d[d.length-1]).attr("y"))/2)+parseFloat(d3.select("#label"+d[d.length-1]).attr("y"));

			//console.log(d[0], d[1], angle);

			return "rotate(" + angle + "," + parseInt(centreX) + "," + parseInt(centreY) + ")";
		});	
		
	var xAdjust = 25;
	var yAdjust = 20;
	//Highlighting Each individual node (semi-circles)
	svg.append("svg:path")
		.attr("d",function(d) {
			
			//var startValue = dataset.length/2;
			//console.log(nodes[0][0], nodes[0][1], nodes[1][0], nodes[1][1]);
			//console.log(getQueueFromOrder(0), parseInt((dataset.length/2)-1), getQueueFromOrder((dataset.length/2)-1), getQueueFromOrder((dataset.length/2)), getQueueFromOrder(dataset.length-1));
			//console.log(startValue-2, getQueueFromOrder(startValue-2),  order[startValue-2]);

			var startX = parseInt(d3.select("#label"+getQueueFromOrder(0)).attr("x"))+xAdjust; //12
			var startY = parseInt(d3.select("#label"+getQueueFromOrder(0)).attr("y"))+yAdjust;
			
			var endX = parseInt(d3.select("#label"+getQueueFromOrder(parseInt(dataset.length/2)-1)).attr("x"))-xAdjust; //10
			var endY = parseInt(d3.select("#label"+getQueueFromOrder(parseInt(dataset.length/2)-1)).attr("y"))+yAdjust;
			
			return "M" + startX + " " + startY + " A " + (rx) + "," + (ry) + " 0 1,0 " + endX + "," + endY + " z";
			
			
			//"M50 50 a 60,60 0 1,0 110,100 z"
		})
		.attr("class","nodeArea");
	svg.append("svg:path")
		.attr("d",function(d) {
			
			//var startValue = (dataset.length/2)+1;

			var startX = parseInt(d3.select("#label"+getQueueFromOrder(parseInt(dataset.length/2))).attr("x"))-xAdjust; //13
			var startY = parseInt(d3.select("#label"+getQueueFromOrder(parseInt(dataset.length/2))).attr("y"))-yAdjust;
			
			var endX = parseInt(d3.select("#label"+getQueueFromOrder(dataset.length-1)).attr("x"))+xAdjust; //11
			var endY = parseInt(d3.select("#label"+getQueueFromOrder(dataset.length-1)).attr("y"))-yAdjust;
			
			return "M" + startX + " " + startY + " A " + (rx) + "," + (ry) + " 0 1,0 " + endX + "," + endY + " z";
			
			
			//"M50 50 a 60,60 0 1,0 110,100 z"
		})
		.attr("class","nodeArea");

	
	/*
	*	Highlight Process Usage
	*/
	gEnter.append("rect")
		.attr("width",boxSize)
		.attr("height",function(d) {
			return calcHeight(d.usage);
		})
		.attr("x", function(d) {
			return parseInt(calcXValue(cx, rx+boxSize, ry+boxSize, d.order, dataset.length, boxSize));
			
		})
		.attr("y", function(d) {
		
			return parseInt(calcYValue(cy, rx+boxSize, ry+boxSize, d.order, dataset.length, boxSize) + boxSize); //- calcHeight(d.usage) 

		})
		.attr("id",function(d) {
			return "num"+d.id;
		})
		.attr("fill",function(d){
			var red = (d.usage * 2);
			if (red > 255) {
				red = 255;
			}
			var green = 255-(d.usage * 2);
			if (green < 0) {
				green = 0;
			}
			return d3.rgb(red,green,0);
			//return "#" + red.toString(16) + "" + green.toString(16) + "00";
		})
		.attr("transform",function(d){
			//return "rotate(" + calculateAngle(d.order,dataset.length) +  ")";
			
			return "rotate(" + (270 - ((180/Math.PI)*calculateAngle(d.order,dataset.length)) ) + "," + 
			parseInt(calcXValue(cx, rx+boxSize, ry+boxSize, d.order, dataset.length, boxSize)+(boxSize/2)) + "," + 
			parseInt(calcYValue(cy, rx+boxSize, ry+boxSize, d.order, dataset.length, boxSize)+(boxSize/2)) + ")";
		})
		.append("svg:title")
		.text(function(d) {
			return ""+parseInt(d.usage);
		});
		
	



	/*
	*	Size labels
	*/
	
	if (d3.select("#usage").property("checked")){
		//console.log("abc");
		
		gEnter.append("text")
		.text(function(d){
			return d.usage+" " + d.order;
		})
		.attr("width",boxSize)
		.attr("height",function(d) {
			return calcHeight(d.usage);
		})
		.attr("x", function(d) {
			return calcXValue(cx, rx+boxSize+10, ry+boxSize+10, d.order, dataset.length, boxSize)+(boxSize/2)-5;
		})
		.attr("y", function(d) {
			return calcYValue(cy, rx+boxSize+10, ry+boxSize+10, d.order, dataset.length, boxSize)+(boxSize/2); //-

		})
		.attr("class","usage");
		//return "abc";
			
	}
	
	//border rectangle
	gEnter.append("rect")
		.attr("width",boxSize)
		.attr("height",boxSize)
		.attr("x", function(d) {
			return parseInt(calcXValue(cx, rx, ry, d.order, dataset.length, boxSize));
			
		})
		.attr("y", function(d) {
			return parseInt(calcYValue(cy, rx, ry, d.order, dataset.length, boxSize)); //if circle

		})
		.attr("id",function(d) {
			return "border"+d.id;
		})
		.attr("class","border")					
		.attr("transform",function(d){
			//return "rotate(" + calculateAngle(d.order,dataset.length) +  ")";
			return "rotate(" + (90 - ((180/Math.PI)*calculateAngle(d.order,dataset.length)) ) + "," + parseInt(calcXValue(cx, rx, ry, d.order, dataset.length, boxSize)+(boxSize/2)) + "," + parseInt(calcYValue(cy, rx, ry, d.order, dataset.length, boxSize)+(boxSize/2)) + ")";
		});
		
		//#8888FF
		
			
		
	if (activities != undefined){
		//console.log(timeInstance/resolution, activities.length);
		//console.log(activities);
		activities.unshift(new Activity(new Process(-1,-1,-1),-1)); //D3's iterator won't read the first item, so insert this dummy value to counteract this.
		d3.select("svg")
			.selectAll("text")
			.data(activities, function (d, i) { 
				//console.log(i); 
				//return activities[i];
				return d;
			})
			.enter()
			.append("text")
			.text(function(d, i) {
				//console.log(d.process);
				//return "text";
				//if (i == 0) { return; }
				//console.log("act p" + d.process.a + " " + d.process.b + " " + d.process.c + " q" + d.queue + " pQ" + d.process.previousQueue, i);
				var previousQueueID = d.process.previousQueue;
				if ((previousQueueID >= 0) && (previousQueueID < d.process.queues.length))
				{
					var from = d.queue;
					var to = d.process.queues[previousQueueID];
					//console.log(previousQueueID, d.process.queues,from, to); //log
					var fromX = parseInt(svg.select("#border"+from).attr("x")) + (boxSize/2);
					var fromY = parseInt(svg.select("#border"+from).attr("y")) + (boxSize/2);
					var toX = parseInt(svg.select("#border"+to).attr("x")) + (boxSize/2);
					var toY = parseInt(svg.select("#border"+to).attr("y")) + (boxSize/2);

					var centrePoint = Math.abs(getQueue(dataset,from).order - getQueue(dataset,to).order);
					if (getQueue(dataset,from).order < getQueue(dataset,to).order){
						centrePoint = (centrePoint/2) + getQueue(dataset,from).order;
					} else {
						centrePoint = (centrePoint/2) + getQueue(dataset,to).order;
					}
					
					var centreOptions = [0.2,0.4,0.6,0.8];
					var centreValue = centreOptions[Math.floor(Math.random() * 4)];
					//console.log(centreValue);
					var centreX = calcXValue(cx, rx*centreValue, ry*centreValue, centrePoint, dataset.length, boxSize);
					var centreY = calcYValue(cy, rx*centreValue, ry*centreValue, centrePoint, dataset.length, boxSize);
					
					pathData = [{x:fromX, y:fromY},{x:centreX, y:centreY},{x:toX, y:toY}];
					
					//console.log(from-to);
					
					var line = d3.svg.line()
						.x(function (d) { return d.x;} )
						.y(function (d) { return d.y;} )
						.interpolate("cardinal")
						.tension(0.5);
					
					svg.append("svg:path")
						.attr("d", line(pathData))
						.attr("class",function (d) {
							fromCrossing = findOrder(from) >= (dataset.length /2);
							toCrossing = findOrder(to) >= (dataset.length /2);
							//console.log(findOrder(from), findOrder(to), fromCrossing, toCrossing );
							//console.log(from, to, getQueue(dataset, from).sharedNodes, getQueue(dataset, from).sharedNodes.indexOf(to));

							//if the process moves across the node
							if ( XOR(fromCrossing, toCrossing)){
								//console.log("nodeCrossing");
								return "nodeCrossing";
							//if the process moves to the same core
							} else if ( getQueue(dataset, from).sharedNodes.indexOf(to) != -1 )
							{
								return "sameCore";
							} else {
								return "coreCrossing";
							}
						})
						.style("opacity", 1)
						.transition()
						.duration(1500)
						.style("opacity", 0)
						.transition()
						.delay(1500)
						.each("start", function() {
							d3.select(this).remove(); 
							//line.remove();
						});
					/*
					svg.append("line")
						.attr("x1",function(d) {
							return ;
						//return 50;
						})
						.attr("y1",function(d) {
							return ;
						//return 50;
						})
						.attr("x2",function(d) {
							return ;
						//return 100;
						})
						.attr("y2",function(d) {
							return ;
						//return 100;
						})
						.style("opacity", 1)
						.transition()
						.duration(1500)
						.style("opacity", 0)
						.transition()
						.delay(1500)
						.each("start", function() {
							d3.select(this).remove(); 
						});
					*/	
					d.process.previousQueue++;
					return "";
				} else {
					//var thisGap = d.thisGap;
					if (d.queue != -1){ 
						var queue = getQueue(dataset,d.queue);
						//console.log(timeInstance, "dataset",d.queue, queue);
						//console.log(queue.takenSpots);
						takenSpots = queue.takenSpots;
						//console.log("inner before",d.thisGap);
						d.thisGap = findFirstGap(takenSpots);		
						//console.log("inner after",d.thisGap);
						takenSpots.push(d.thisGap);
						takenSpots.sort(function (a,b) { return (a-b); });	
						
						//console.log("add", d.queue, takenSpots, d.thisGap);
						
						var output = "p" + d.process.a + " " + d.process.b + " " + d.process.c; // + " q" + d.queue;
						d.process.previousQueue++;
						return output;
					}
				}
				
			})
			.attr("x",function(d) {
				//console.log("x", d.thisGap);
				var queue = getQueue(dataset,d.queue);
				var angle = calculateAngle(queue.order,dataset.length);
				
				var x = parseInt(svg.select("#num"+d.queue).attr("x")) + (20 *(d.thisGap+1) * Math.cos(angle));
				
				if ((angle > (3*Math.PI)/2) || (angle < Math.PI/2)) {
					x+= (boxSize/2);
				} else {
					x-= (boxSize/2);
				}
				//console.log(x);
				return x;
				//return d.thisGap * 10;
				//return svg.select("#num"+d.queue).attr("x") + 70;
			})
			.attr("y",function(d) {
				//console.log("y", d.thisGap);
				var queue = getQueue(dataset,d.queue);
				var angle = calculateAngle(queue.order,dataset.length);
				var y = parseInt(svg.select("#num"+d.queue).attr("y")) - (20 * (d.thisGap+1) * Math.sin(angle));
				if (angle < Math.PI) {
					y+= (boxSize/2);
				} else {
					y-= (boxSize/2);
				}
				//console.log(y);
				return y;
				//return svg.select("#num"+d.queue).attr("y");
			})
			.attr("class","process")
			.transition()
			.delay(2000)
			.each("start", function(d) {
				var queue = getQueue(dataset,d.queue);
				takenSpots = queue.takenSpots;
				
				var index = takenSpots.indexOf(d.thisGap);
				//console.log("remove", d.queue, takenSpots, d.thisGap, index);
				if (index == -1){
					//console.log("error");
					//console.log("remove", d.queue, takenSpots, d.thisGap, index);
				} else {
					takenSpots.splice(index,1);
				}
				//console.log("after remove", takenSpots);
				d3.select(this).remove();
				
			});
		//drop the dummy first item
		activities.splice(0,1);
	}	
		
	svg.append("text")
		.text(function() {
			return "i: " + timeInstance;
		})
		.attr("x", 20)
		.attr("y", 20)
		.attr("id", "its");
		
	svg.append("text")
		.text(function() {
			return "time: " + times[timeInstance].time/resolution + "s";
		})
		.attr("x", 20)
		.attr("y", 40)
		.attr("id", "time");
}