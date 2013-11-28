/** Find the circle with the given label */
function circleWithLabel(label, circles) {
	for (var i = 0; i <  circles.length; i++) {
		if(circles[i].label==label) {
			return circles[i];
		}
	}
	return null;
}


/**
  Adapted from http://jsfromhell.com/math/dot-line-length.
  x y is the point
  x0 yo x1 y2 is the line segment
  if o is true, just consider the line segment, if it is false consider an infinite line.
*/		
function pointLineLength(x, y, x0, y0, x1, y1, o){
	if(o && !(o = function(x, y, x0, y0, x1, y1){
		if(!(x1 - x0)) return {x: x0, y: y};
		else if(!(y1 - y0)) return {x: x, y: y0};
		var left, tg = -1 / ((y1 - y0) / (x1 - x0));
		return {x: left = (x1 * (x * tg - y + y0) + x0 * (x * - tg + y - y1)) / (tg * (x1 - x0) + y0 - y1), y: tg * left - tg * x + y};
	}(x, y, x0, y0, x1, y1), o.x >= Math.min(x0, x1) && o.x <= Math.max(x0, x1) && o.y >= Math.min(y0, y1) && o.y <= Math.max(y0, y1))){
		var l1 = distance(x, y, x0, y0), l2 = distance(x, y, x1, y1);
		return l1 > l2 ? l2 : l1;
	}
	else {
		var a = y0 - y1, b = x1 - x0, c = x0 * y1 - y0 * x1;
		return Math.abs(a * x + b * y + c) / Math.sqrt(a * a + b * b);
	}
};


/** Finds a rectangle that covers the given circle */
function circlesLimit(circles) {
	var minX = 0;
	var minY = 0;
	var maxX = 0;
	var maxX = 0;
	for (var i = 0; i < circles.length; i++) {
		if (circles[i] == undefined){
			continue;
		}
		if(i == 0) {
			minX = circles[i].x - circles[i].r;
			minY = circles[i].y - circles[i].r;
			maxX = circles[i].x + circles[i].r;
			maxY = circles[i].y + circles[i].r;
		} else {
			if(minX > circles[i].x - circles[i].r) {
				minX = circles[i].x - circles[i].r;
			}
			if(minY > circles[i].y - circles[i].r) {
				minY = circles[i].y - circles[i].r;
			}
			if(maxX < circles[i].x + circles[i].r) {
				maxX = circles[i].x + circles[i].r;
			}
			if(maxY < circles[i].y + circles[i].r) {
				maxY = circles[i].y + circles[i].r;
			}
		}
	}
	var rectangle = new Rectangle(minX,minY,maxX-minX,maxY-minY);
	return rectangle;
}



/** Tests to see if the point is in the circle */
function inCircle(circle,x,y) {
	if(distance(circle.x,circle.y,x,y) < circle.r) {
		return true;
	}
	return false;
}


/** Distance between two points - pythagoras */
function distance(x1,y1,x2,y2) {
	return Math.sqrt((x1-x2) * (x1-x2) + (y1-y2) * (y1-y2));
}


/**
  Find out if the point is in the zone. The zone is specified
  by the circles it is in and the circles it is out of. All
  the circles should be in one of the two sets.
*/
function inZone(inCircles,outCircles,x,y) {
	for (var i = 0; i < inCircles.length; i++) {
		if(!inCircle(inCircles[i],x,y)) {
			return false;
		}
	}
	for (var i = 0; i < outCircles.length; i++) {
		if(inCircle(outCircles[i],x,y)) {
			return false;
		}
	}
	return true;

}


/**
  Find out if the rectangle is completely in the zone. The zone is specified
  by the circles it is in and the circles it is out of. All
  the circles should be in one of the two sets. This tests the oorner
  points, so some oddly shaped zones may return an incorrect true.
*/
function rectangleInZone(circlesInZone,circlesOutZone, minX,maxX,minY,maxY) {

	// first test the corners
	if(!inZone(circlesInZone,circlesOutZone, minX,minY)) {
		return false;
	}
	if(!inZone(circlesInZone,circlesOutZone, minX,maxY)) {
		return false;
	}
	if(!inZone(circlesInZone,circlesOutZone, maxX,minY)) {
		return false;
	}
	if(!inZone(circlesInZone,circlesOutZone, maxX,maxY)) {
		return false;
	}
	
	// all the corners are in the zone. Do any of the rectangle
	// edges leave the zone? To test this, check each circle
	// that the rectangle is not supposed to be in for shortest
	// centre edge distance and compare this distance to the radius.
	var distanceToCentre;
	for (var i = 0; i < circlesOutZone.length; i++) {
		var circle = circlesOutZone[i];
		distanceToCentre = pointLineLength(circle.x, circle.y, minX, minY, maxX, minY, true)
		if(distanceToCentre < circle.r) {
			return false;
		}
		distanceToCentre = pointLineLength(circle.x, circle.y, minX, minY, minX, maxY, true)
		if(distanceToCentre < circle.r) {
			return false;
		}
		distanceToCentre = pointLineLength(circle.x, circle.y, maxX, maxY, maxX, minY, true)
		if(distanceToCentre < circle.r) {
			return false;
		}
		distanceToCentre = pointLineLength(circle.x, circle.y, maxX, maxY, minX, maxY, true)
		if(distanceToCentre < circle.r) {
			return false;
		}

	}
	
	return true;
}


/**
  Given that the zone in in the inZone circles, this finds
  the circles that do not contain the zone.
*/
function getOutZones(circles,inZone) {
	var outZone = [];
	for (var i = 0; i < circles.length; i++) {
		var circleInZone = false;
		for (var j = 0; j < inZone.length; j++) {
			if(circles[i] == inZone[j]) {
				circleInZone = true;
				outCircle = circles[i];
			}
		}
		if(!circleInZone) {
			outZone.push(circles[i]);
		}
	}
	return outZone;
}


/**
	Find the points in the given zone in a grid based on the parameters.
*/
function findPointsInZone(displayLimit,xStep,yStep,circlesInZone,circlesOutZone) {

	var points = [];
	for(var x = displayLimit.x+xStep/2; x <= displayLimit.x + displayLimit.width; x = x + xStep) {
		for(var y = displayLimit.y+yStep/2; y <= displayLimit.y + displayLimit.height; y = y + yStep) {
			var pointInZone = inZone(circlesInZone, circlesOutZone,x,y);
			if(pointInZone) {
				points.push(new Point(x,y));
			}
		}
	}
	return points;
}


/** Finds a minimum number of points in a zone, or return empty list*/
function findSufficientPointsInZone(circlesInZone,circlesOutZone) {
	var displayLimit = circlesLimit(circlesInZone);
	var gridSide = 3;
	var xStep = displayLimit.width/gridSide;
	var yStep = displayLimit.height/gridSide;
	
	var zonePointsX = [];
	var zonePointsY = [];
	
	var pointsInZone = [];
	while(pointsInZone.length < 10) {
		if(xStep < 1 && yStep < 1) {
			console.log("zone not found");
				return [];
			}
		pointsInZone = findPointsInZone(displayLimit,xStep,yStep,circlesInZone,circlesOutZone)
		xStep = xStep/2;
		yStep = yStep/2;
	}
	return pointsInZone;
}



/** For each zone, finds circles that the zones are in. Returns a list of lists */
function zoneFinder(zoneStrings,circles) {
	//console.log(zoneStrings);
	var ret = [];
	for (var i = 0; i <  zoneStrings.length; i++) {
		var zoneString = zoneStrings[i].trim();

		//console.log(zoneString, zoneString.length);

		var nextZone = [];
		for (var j = 0; j < zoneString.length; j++) {
			var circleLabel = zoneString[j];
			//console.log(circleLabel);
			if (circleLabel == "" || circleLabel == " "){
				continue;
			}
			var circle = circleWithLabel(circleLabel,circles);

			//console.log(circle);
			if (circle != null) {
				nextZone.push(circle);
			}
		}
		//console.log(nextZone);
		ret.push(nextZone);
	}
	return ret;
}


/**
  Expand a rectangle until it fills the zone as much as possible
*/
function findRectangle(point,circlesInZone,circlesOutZone) {


	var minX = point.x;
	var maxX = point.x+1;
	var minY = point.y;
	var maxY = point.y+1;
	var moveDistance = circlesInZone[0].r/4;

	while (moveDistance > 0.5) {

		var noMove = true;
		
		if(rectangleInZone(circlesInZone,circlesOutZone, minX-moveDistance,maxX,minY,maxY)) {
			noMove = false;
			minX = minX-moveDistance
		}
		if(rectangleInZone(circlesInZone,circlesOutZone, minX,maxX+moveDistance,minY,maxY)) {
			noMove = false;
			maxX = maxX+moveDistance
		}
		if(rectangleInZone(circlesInZone,circlesOutZone, minX,maxX,minY-moveDistance,maxY)) {
			noMove = false;
			minY = minY-moveDistance
		}
		if(rectangleInZone(circlesInZone,circlesOutZone, minX,maxX,minY,maxY+moveDistance)) {
			noMove = false;
			maxY = maxY+moveDistance
		}
		
		if(noMove) {
			moveDistance = moveDistance/2
		}
	}

	var ret = new Rectangle(minX, minY, maxX-minX, maxY-minY);
	return ret;
}



/**
  This finds a biggest contained rectangle for a zone, specified by
  the circles containing the zone and the circles that are outside the
  zone.
*/
function findZoneRectangle(circlesInZone,circlesOutZone) {

	var pointsInZone = findSufficientPointsInZone(circlesInZone,circlesOutZone);
	
	if(pointsInZone.length == 0) {
		return new Rectangle(0,0,0,0);
	}
	var biggestRectangle;
	var biggestArea = 0;
	for (var i = 0; i < pointsInZone.length; i++) {

		//console.log(pointsInZone[i],circlesInZone,circlesOutZone);

		var rectangle = findRectangle(pointsInZone[i],circlesInZone,circlesOutZone);
		if(rectangle.width*rectangle.height > biggestArea) {
			biggestRectangle = rectangle;
			biggestArea = rectangle.width*rectangle.height;
		}
	}
	return biggestRectangle;
}


/**
  This finds a biggest contained rectangle for each zone. The rectangles
  are returned in array, in the same order as the zones. The zones are
  specified by an array of strings. The circles should be an array
  of all the circles in the diagram
*/
function findZoneRectangles(zoneStrings, circles) {

	var zones = zoneFinder(zoneStrings,circles);

	var rectangles = [];
	
	// iterate through the zones, finding the best rectangle for each zone
	for (var i = 0; i <  zones.length; i++) {
		var circlesInZone = zones[i];
		
		var circlesOutZone = getOutZones(circles, circlesInZone);

		//console.log(circlesInZone, circlesOutZone, rectangles, zones, zoneStrings, circles);

		var rectangle = findZoneRectangle(circlesInZone,circlesOutZone);

		for (var j = 0; j < circlesInZone.length; j++){
			rectangle.label = rectangle.label + "" + circlesInZone[j].label;
		}

		//console.log(circlesInZone, circlesOutZone, rectangle);
		rectangles.push(rectangle);
	}
	return rectangles;
}