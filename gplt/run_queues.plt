reset
set title "Run Queue Length Graph"
set autoscale 
set xtic auto 
set ytic auto 
set terminal png truecolor
set grid
set xlabel "Time(Seconds)"
set ylabel "Run ueue Length"
title(n) = sprintf("Run Queue %d", n)
plot for [i=1:n] filename using 1:(i+1) with filledcurves x1 linestyle (n-i) title title(i)

