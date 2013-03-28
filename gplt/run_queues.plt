reset
set title "Run Queue Length Graph"
set autoscale 
set xtic auto 
set ytic auto 
set terminal svg 
set grid
set xlabel "Time(Seconds)"
set ylabel "Run ueue Length"
title1(n) = sprintf("Run Queue %d", n)
plot for [i=2:n] filename using 1:i with filledcurves x1 linestyle i t title1(i-1)