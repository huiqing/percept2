var svg;

function drawGraph(nodes, edges, rectangles, circles){
	console.log(nodes, edges, rectangles, circles);

	svg = d3.select("#svg").append("svg")
	    .attr("width", 800)
	    .attr("height", 600)
	    .attr("version", 1.1)
	    .attr("xmlns", "http://www.w3.org/2000/svg");



	svg.append("g");
	for (var i = 0; i < circles.length; i++) {
		circle = circles[i];


		svg.select("g")
			.append("circle")
			.attr("r", function(){
				circle.r = circle.r * multiplier;
				return circle.r
			})
			.attr("cx",function(){
				circle.x = circle.x * multiplier;
				return circle.x
			})
			.attr("cy",function(){
				circle.y = circle.y * multiplier;
				return circle.y
			})
			.attr("class","euler")
			.attr("style","fill: none; stroke:blue;");



		svg.select("g")
			.append("text")
			.text(function(){
				return circle.label;
			})
			.attr("x", function(){
				return circle.x;
			})
			.attr("y", function(){
				return (circle.y - circle.r)+25 ;
			})
			.attr("width", 20)
			.attr("height", 20)
			.attr("style", "font-weight:bold; font-size:1.5em; font-family:sans-serif;");

	}

	for (var i = 0; i < rectangles.length; i++) {
		//context.fillRect(rectangles[i].x * multiplier, rectangles[i].y * multiplier, rectangles[i].width * multiplier, rectangles[i].height * multiplier);

		svg.select("g")
			.append("rect")
			.attr("x", rectangles[i].x * multiplier)
		    .attr("y", rectangles[i].y * multiplier)
		    .attr("width", rectangles[i].width * multiplier)
		    .attr("height", rectangles[i].height * multiplier)
		    .attr("class","startingRect")
		    .attr("style", "fill: rgba(0, 255, 0, 0.5)");
	}

	k = c * Math.sqrt(800 / nodes.length);
	//console.log(k,c, nodes.length);

	

	svg.selectAll("circle")
		.data(nodes, function(d){
			return d;
		})
		.enter()
		.append("circle")
		.attr("r",5)
		.attr("cx",function (d,i){
			
			var cols = Math.round(Math.sqrt(nodesInRegion(d.region).length));

			//console.log(cols, d.label);
			//console.log((i % cols)+1, i, cols, nodes.length, d.region.width, (d.region.width / (cols + 1)));
			var cx = ( ((i % cols)+1) * (d.region.width / (cols + 1)) ) + d.region.x;
			 //var cx = (Math.random() * d.region.width) + d.region.x;
			d.x = cx* multiplier;
			//console.log("x", d);
			return parseInt(d.x) ;

			//return d.region.width * multiplier;
			//return 10;
		})
		.attr("cy",function (d){
			//console.log("y", d.region.y * multiplier);
			//d.y = d.region.y;

			var cols = Math.round(Math.sqrt(nodesInRegion(d.region).length));

			//var cy = d.region.y + ((Math.floor(i / cols)+1) * (d.region.height / (cols + 1)));
			//console.log(cy, d.region.height, d.region.y, Math.floor(i / cols)+1 , (d.region.height / (cols + 1)));

			var i = nodesInRegion(d.region).indexOf(d);

			/*
			console.log(
				d.region.y,
				"i", i,
				"cols", cols,
				i % cols,
				(Math.floor(i / cols)+1),
				(d.region.height / (cols + 1)),
				((Math.floor(i % cols)+1) * (d.region.height / (cols + 1)))
			);
*/
			var cy = ((Math.floor(i / cols)+1) * (d.region.height / (cols + 1))) + d.region.y

			//var cy = (Math.random() * d.region.height) + d.region.y;
			//var cy = d.region.y + 50;
			d.y = cy* multiplier;
			return parseInt(d.y);
			//return 10;
		})
		.attr("id", function(d){
			return d.label;
		})
		.attr("class","node")
		.style("fill", "blue");

		drawEdges(edges);

	
}

function drawEdges(edges){
	svg.selectAll("line").remove();

	svg.selectAll("line")
		.data(edges)
		.enter()
		.append("line")
		.attr("x1", function(d){
			//console.log(d);
			return d3.select("#"+d.source.label).attr("cx");
		})
		.attr("y1", function(d){
			return d3.select("#"+d.source.label).attr("cy");
		})
		.attr("x2", function(d){
			return d3.select("#"+d.target.label).attr("cx");
		})
		.attr("y2", function(d){
			return d3.select("#"+d.target.label).attr("cy");
		})
		.style("stroke", function (d){
			//console.log(d.size);
			var size = Math.max(200-(d.size * 10),0);
			return "rgb(" + size + "," + size + "," + size + ")";
		})
		.style("stroke-width", 2)
		.attr("id", function(d){
			return "edge" + d.source.label + d.target.label;
		});
}