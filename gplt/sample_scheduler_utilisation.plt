set title "Scheduler Utilisation Graph"
set autoscale 
set xtic auto 
set ytic auto 
set xlabel "Time(Seconds)"
set ylabel "Scheduler Utilisation"
set grid 
plot "sample_scheduler_utilisation.dat" using 1:2 title 'Scheduler #4' with filledcurves x1 linestyle 4, \
"sample_scheduler_utilisation.dat" using 1:3 title 'Scheduler #3' with filledcurves x1 linestyle 3, \
"sample_scheduler_utilisation.dat" using 1:4 title 'Scheduler #2' with filledcurves x1 linestyle 2, \
"sample_scheduler_utilisation.dat" using 1:5 title 'Scheduler #1' with filledcurves x1 linestyle 1
