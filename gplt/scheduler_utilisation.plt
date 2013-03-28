reset
set title "Scheduler Utilisation Graph"
set autoscale 
set xtic auto 
set ytic auto 
set xlabel "Time(Seconds)"
set ylabel "Scheduler Utilisation"
set grid
set terminal svg
title(n) = sprintf("Scheduler %d", n)
plot for [i=2:n] filename using 1:i with filledcurves x1 linestyle i t title(i-1)
