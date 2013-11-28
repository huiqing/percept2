'use scrict';

//https://github.com/yonran/detect-zoom

window.onresize = function onresize() {
	var r = DetectZoom.ratios();
	var width = d3.select("#canvas").attr("width");
	d3.select("#canvas").attr("width",parseInt(originalWidth*(1/r.zoom)));
	
	//var height = d3.select("#canvas").attr("height");
	d3.select("#canvas").attr("height",parseInt(originalHeight*(1/r.zoom)));
	
	cx = parseInt(originalcx*(1/r.zoom));
	cy = parseInt(originalcy*(1/r.zoom));
	
	
	d3.select("#slider").style("width",parseInt(originalWidth*(1/r.zoom)));
}
onresize();

if ('ontouchstart' in window) {
	window.onscroll = onresize;
}
