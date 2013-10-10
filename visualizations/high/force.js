
function circleForceHorizontal(node){
	//console.log(node);
	var force = 0;
	var k = 1000; //multiplier

	//this node's co-ordinates
	var px = node.x;
	var py = node.y;

	for(i = 0; i < circles.length; i++){
		var circle = circles[i];
		var cx = circle.x;
		var cy = circle.y;
		var r = circle.r;

		var v = Math.sqrt(  Math.pow((px - cx),2) +  Math.pow((py - cy),2) );

		var inside = v < (r * multiplier);


		//var distance = inside ? px - (cx + r) : px + (cx - r);



		var distance = Math.abs(px - (px / (v * r) ));

		//console.log(circle,distance,circle.label,node.label);
		var localForce = k / distance;
		force += localForce;
		//console.log("node"+node.label,circle.label,distance, localForce, inside, "v", v, "r", r);
		//console.log(circle,"force",force,"cx",cx,"cy",cy,"r",r,"px",px,"py",py,"v",v,"d",distance);

	}
	//console.log(force);
	return force;

}

function getAngle(n1, n2){
	//console.log(n1,n2);
	var x = n1.x - n2.x;
	var y = n1.y - n1.y;
	var angle;
	//to avoid the ambiguities with the arctan at 0 & 180 deg and the undefined result at 90 & 270
	if ((x == 0) && (y != 0)) {
		if (n1.y > n2.y){
			angle = Math.PI / 2; //90deg
		} else {
			angle = ((-1) * Math.PI) / 2; //-90deg
		}
	} else if((x != 0) && (y == 0)){
		if (n1.x > n2.x){
			angle = Math.PI; //180deg
		} else {
			angle = 0; //0deg
		}
	} else {
		angle = Math.atan(y/x);
	}
	return angle;
}

function cool(t){
	return t/2;
}

function forceAttract(x, k){
	return (x * x)/k;
}

function forceRepel(x, k){
	//console.log(x, k);
	return (k * k)/x;
}

function nodesConnect(n1,n2) {
	for (var i = 0; i < edges.length; i++){
		e = edges[i];
		
		if(n1 == e.source && n2 == e.target) {
			return true;
		}
		if(n1 == e.target && n2 == e.source) {
			return true;
		}
	}
	return false;
}

function nodesInRegion(region){
	var result = [];
	for (var i = 0; i < nodes.length; i++){
		if (nodes[i].region == region){
			result.push(nodes[i]);
		}
	}
	return result;
}

/*
	Returns an array of circles this node is outside of that it shouldn't be
 */
function insideCircles(node){
	var strCircles = node.region.label;
	var result = [];
	//console.log(circles);

	for (var i = 0; i < circles.length; i++){
		var circle = circles[i];
		var distance = Math.sqrt( Math.pow(node.x - circle.x, 2) + Math.pow(node.y - circle.y, 2) );
		//does this node's region contain this circle

		//console.log(circle.label, strCircles, node.x, circle.x);
		if (strCircles.indexOf(circle.label) != -1) {
			//check node is inside
			
			//console.log(strCircles, label, circle, node, distance);
			if (distance >= circle.r){
				result.push(circle);
			}
		} else {
			//check if node is outside
			if (distance <= circle.r){
				result.push(circle);
			}

		}
	}
	return result;
}

function iterateGraph(nodes, edges){

	var K = 0.01; // attractive force multiplier
	var R = 500.0; // repulsive force mutiplier
	var C = 500.0; // circle force multiplier
	var F = 1.0; // final movement multiplier
	var maxForce = 10 // force limit in horizontal or vertical

	for(var i = 0; i < nodes.length; i++){
		var n1 = nodes[i];
	
		var xAttractive = 0;
		var yAttractive = 0;
		var xRepulsive = 0;
		var yRepulsive = 0;
		var xCircleForce = 0;
		var yCircleForce = 0;

		for(var j = 0; j < nodes.length; j++){
			if(i != j) {
				var n2 = nodes[j];

				var distance = Math.sqrt( Math.pow(n1.x - n2.x, 2) + Math.pow(n1.y - n2.y, 2) );
				var xDistance = n1.x - n2.x;
				var yDistance = n1.y - n2.y;
				
				var absDistance = distance;
				var absXDistance = xDistance;
				if(absXDistance < 0) {
					absXDistance = -xDistance;
				}
				var absYDistance = yDistance;
				if(absYDistance < 0) {
					absYDistance = -yDistance;
				}

				var xForceShare = absXDistance/(absXDistance+absYDistance);
				var yForceShare = absYDistance/(absXDistance+absYDistance);

				// attractive force
				if (nodesConnect(n1,n2)) {

					if(xDistance > 0) {
						xAttractive -= K*xForceShare*absDistance;
					} else {
						xAttractive += K*xForceShare*absDistance;
					}

					if(yDistance > 0) {
						yAttractive -= K*yForceShare*absDistance;
					} else {
						yAttractive += K*yForceShare*absDistance;
					}
				}


				// repulsive force
				var repulsiveForce = R / (distance * distance);

				if(xDistance > 0) {
					xRepulsive += repulsiveForce*xForceShare;
				} else {
					xRepulsive -= repulsiveForce*xForceShare;
				}

				if(yDistance > 0) {
					yRepulsive += repulsiveForce*yForceShare;
				} else {
					yRepulsive -= repulsiveForce*yForceShare;
				}
			}
			
			// circle - node force
			for (var k = 0; k < circles.length; k++){
//var k = 0;
				var circle = circles[k];
				var distanceToCentre = Math.sqrt( Math.pow(n1.x - circle.x, 2) + Math.pow(n1.y - circle.y, 2) );
				
				var xDistance = n1.x - circle.x;
				var yDistance = n1.y - circle.y;
				
				var absXDistance = xDistance;
				if(absXDistance < 0) {
					absXDistance = -xDistance;
				}
				var absYDistance = yDistance;
				if(absYDistance < 0) {
					absYDistance = -yDistance;
				}
				
				var distanceToCircleBorder = distanceToCentre;
				if(distanceToCircleBorder < circle.r) {
					distanceToCircleBorder = circle.r - distanceToCircleBorder;
				} else {
					distanceToCircleBorder = distanceToCircleBorder - circle.r;
				}



				var xForceShare = absXDistance/(absXDistance+absYDistance);
				var yForceShare = absYDistance/(absXDistance+absYDistance);


				var circleForce = C / (distanceToCircleBorder * distanceToCircleBorder);

				var	thisAbsXCircleForce = circleForce*xForceShare;
				if(thisAbsXCircleForce < 0) {
					thisAbsXCircleForce = -thisAbsXCircleForce;
				}
				
				var	thisAbsYCircleForce = circleForce*yForceShare;
				if(thisAbsYCircleForce < 0) {
					thisAbsYCircleForce = -thisAbsYCircleForce;
				}
				
				// sort out movement direction
				var inside = true;
				if(distanceToCentre > circle.r) {
					inside = false;
				}
				var above = true;
				if(n1.y > circle.y) {
					above = false;
				}
				var left = true;
				if(n1.x > circle.x) {
					left = false;
				}
				
		
				var thisXCircleForce = 0;
				var thisYCircleForce = 0;
				
				// assume inside in these tests
				if(left) {
					thisXCircleForce = thisAbsXCircleForce
				} else {
					thisXCircleForce = -thisAbsXCircleForce
				}
				if(above) {
					thisYCircleForce = thisAbsYCircleForce
				} else {
					thisYCircleForce = -thisAbsYCircleForce
				}
				// reverse the direction if outside
				if(!inside) {
					thisXCircleForce = -thisXCircleForce;
					thisYCircleForce = -thisYCircleForce;
				}							
				
				xCircleForce += thisXCircleForce;
				yCircleForce += thisYCircleForce;

			}
		}
		
		var totalXForce = F*(xRepulsive + xAttractive + xCircleForce);
		var totalYForce = F*(yRepulsive + yAttractive + yCircleForce);

		// chop the force if it is too large
		if(totalXForce > 0) {
			if(totalXForce > maxForce) {
				totalXForce = maxForce;
			}
		} else {
			if(-totalXForce > maxForce) {
				totalXForce = -maxForce;
			}
		}
		if(totalYForce > 0) {
			if(totalYForce > maxForce) {
				totalYForce = maxForce;
			}
		} else {
			if(-totalYForce > maxForce) {
				totalYForce = -maxForce;
			}
		}

		n1.horizontal = totalXForce;
		n1.vertical = totalYForce;
		
	}

					//move nodes around
	for (var i = 0; i < nodes.length; i++){
		var n = nodes[i];

		//console.log(n.label, n.x, n.horizontal, n.y, n.vertical, t);
		var ox, oy;

		d3.select("#"+n.label)
			.attr("cx", function(){
				
				//if node has moved to a different circle
				//console.log(insideCircles(n));
				if (insideCircles(n).length == 0){
					n.x = n.x + n.horizontal;
				}

				ox = parseInt(n.x);
			
				return ox;
			})
			.attr("cy", function(){

				//if node has moved to a different circle
				if (insideCircles(n).length == 0){
					n.y = n.y + n.vertical;
				}							
				
				oy = parseInt(n.y);
				
				return oy;
			})

	}

	
	//move edges around
	for (var i = 0; i < edges.length; i++){
		e = edges[i];
		d3.select("#edge"+e.source.label+e.target.label)
			.attr("x1", function(){
				return d3.select("#"+e.source.label).attr("cx");
			})
			.attr("y1", function(){
				return d3.select("#"+e.source.label).attr("cy");
			})
			.attr("x2", function(){
				return d3.select("#"+e.target.label).attr("cx");
			})
			.attr("y2", function(){
				return d3.select("#"+e.target.label).attr("cy");
			});
	}

}