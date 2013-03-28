set xlabel "Time (Seconds)"
set ylabel "Process Count"
set title "Total Process Count Graph"
set terminal svg 
plot filename using 1:2 title '#processes' with lines lw 3
