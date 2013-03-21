set title "Scheduler Utilisation Graph"
set autoscale 
set xtic auto 
set ytic auto 
set xlabel "Time(Seconds)"
set ylabel "Scheduler Utilisation"
set grid
title(n) = sprintf("Scheduler %d", n)
plot for [i=1:n] filename using 1:(i+1) with filledcurves x1 linestyle (n-i) title title(i)
