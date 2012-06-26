set xlabel "Time (Seconds)"
set ylabel "Schdulers Count"
set title "Total Online Schedulers Count Graph"
plot "sample_schedulers_online.dat" using 1:2 title '#Schedulers' with lines lw 3
