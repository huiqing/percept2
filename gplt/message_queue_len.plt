reset
set xlabel "Time (Seconds)"
set ylabel "Message Queue Length"
set title "Message Queue Length Graph"
set terminal svg 
plot 'sample_message_queue_len.dat' using 1:2 title '#messages' with lines lw 3
