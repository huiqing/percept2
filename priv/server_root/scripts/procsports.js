var plot, data, graph, options;
var backtrace = [];

var grabSeries = function(rawText) {
    var lines = rawText.split('\n');
    var portsArr = [], processesArr = [];

    for (var i = 0; i < lines.length; i += 10) //every 10 lines
    {
        var line = lines[i].substring(2, lines[i].length - 2);
        var data = line.split(',');

        var time = parseFloat(data[0]).toFixed(6);
        var processes = parseInt(data[1]);
        var ports = parseInt(data[2]);

        portsArr.push([time, ports]);
        processesArr.push([time, processes]);
    }

    return { ports: portsArr, processes: processesArr };
};

$(function () {
    $.get('/cgi-bin/percept2_html/procs_ports_count', function(result) {
        $("#spinner").fadeOut();

        var rawData = grabSeries(result);

        graph = $("#procsportsgraph");

        data = [ { data:  rawData.ports, label: "Active Ports"}, { data: rawData.processes, label: "Active Processes" } ];
        options = {
            series: { lines: { show: true, steps: true }/*, points: {show: true} */},
            crosshair: { mode: "xy" },
            selection: { mode: "xy" },
            grid: { hoverable: true, autoHighlight: false },
            legend: { backgroundColor: null, backgroundOpacity: 0 }
        };

        plot = $.plot(graph, data, options);

        graph.bind("plotselected", function (event, ranges) {
            var axes = plot.getAxes();
            backtrace.push({    xaxis: { from: axes.xaxis.min, to: axes.xaxis.max }, 
                                yaxis: { from: axes.yaxis.min, to: axes.yaxis.max } });
            
            plot = $.plot(graph, data,
                $.extend(true, {}, options, {
                    xaxis: { min: ranges.xaxis.from, max: ranges.xaxis.to },
                    yaxis: { min: ranges.yaxis.from, max: ranges.yaxis.to }
                }));
        });

        graph.dblclick(function (event) {
            var bt = backtrace.pop();

            if (bt === undefined) plot = $.plot(graph, data, options);
            else plot = $.plot(graph, data, $.extend(true, {}, options, {
                    xaxis: { min: bt.xaxis.from, max: bt.xaxis.to },
                    yaxis: { min: bt.yaxis.from, max: bt.yaxis.to }
                }));
            
            event.preventDefault();
        });
    });

    $("#zoomOut").click(function (event) {
        var bt = backtrace.pop();

        if (bt === undefined) plot = $.plot(graph, data, options);
        else plot = $.plot(graph, data, $.extend(true, {}, options, {
                xaxis: { min: bt.xaxis.from, max: bt.xaxis.to },
                yaxis: { min: bt.yaxis.from, max: bt.yaxis.to }
            }));

        event.preventDefault();
    });
});