set xlabel "Time (Seconds)"
set ylabel "Message Queue Length"
set title "Message Queue Length Graph"
plot filename using 1:2 title '#messages' with lines lw 3
