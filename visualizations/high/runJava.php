<?php

function exec_enabled() {
  $disabled = explode(', ', ini_get('disable_functions'));
  return !in_array('exec', $disabled);
}

//echo "output";
exec_enabled();

$input = $_GET["input"];

//$output = array();
exec("java -jar iCircles.jar \"" . $input . "\"", $output);

//exec("ls", $output);
//var_dump($output);
foreach ($output as $result){
	echo $result."\n";
}

?>
