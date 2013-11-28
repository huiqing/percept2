$(function() {
	var slider = $( "#slider" );

	slider.slider({
		range: "min",
		value: 0,
		min: 0,
		max: 1000,
		
		
		slide: function(event, ui){
			var button = d3.select("#pause");
			paused = true;
			button.attr("value","Resume");
			var i = Math.round(slider.slider("value")*((times.length-1)/1000));
			//console.log(i, times.length);
			stop();
			draw(i);
		}
	});
});