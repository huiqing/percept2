
set xlabel "Time (Seconds)"
set ylabel "Memory Usage (Mega bytes)"
set title "Memory Usage Graph"
set terminal svg 
plot filename using 1:2 title 'Total' with lines lw 3, \
     filename using 1:3 title 'Process' with lines lw 3, \
     filename using 1:4 title 'ETS'  with lines lw 3,\
     filename using 1:5 title 'Atom'  with lines lw 3,\
     filename using 1:6 title 'Code'  with lines lw 3,\
     filename using 1:7 title 'Binary' with lines lw 3
