set title "Run Queue Length Graph"
set autoscale 
set xtic auto 
set ytic auto 
set xlabel "Time(Seconds)"
set ylabel "Run Queue Length"
set grid 
plot "sample_run_queues.dat" using 1:2 title 'Run Queue #4' with filledcurves x1 linestyle 4, \
"sample_run_queues.dat" using 1:3 title 'Run Queue #3' with filledcurves x1 linestyle 3, \
"sample_run_queues.dat" using 1:4 title 'Run Queue #2' with filledcurves x1 linestyle 2, \
"sample_run_queues.dat" using 1:5 title 'Run Queue #1' with filledcurves x1 linestyle 1
