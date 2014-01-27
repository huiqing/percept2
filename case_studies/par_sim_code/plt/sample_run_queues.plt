reset
set title "Run Queue Length Graph"
set autoscale 
set xtic auto 
set ytic auto 
set grid
set xlabel "Time(Seconds)"
set ylabel "Run ueue Length"
set terminal png truecolor
ti(n) = sprintf("Run Queue %d", n)
plot for [i=1:4] 'sample_run_queues.dat' using 1:(i+1) with title ti(i) filledcurves x1 linestyle (4-i+1)