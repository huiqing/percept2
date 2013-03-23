set xlabel "Time (Seconds)"
set ylabel "Run Queue Count"
set title "Total Run-Queue Count Graph"
set terminal png truecolor
plot filename using 1:2 title '#Run-Queues' with lines lw 3
