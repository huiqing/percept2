<?php
namespace HighVis;
use Ratchet\MessageComponentInterface;
use Ratchet\ConnectionInterface;

class HVWebSocket implements MessageComponentInterface {
    protected $clients;

    public function exec_enabled() {
      $disabled = explode(', ', ini_get('disable_functions'));
      return !in_array('exec', $disabled);
    }

    public function __construct() {
        $this->clients = new \SplObjectStorage;
    }

    public function onOpen(ConnectionInterface $conn) {
        // Store the new connection to send messages to later
        $this->clients->attach($conn);

        echo "New connection! ({$conn->resourceId})\n";
    }

    public function onMessage(ConnectionInterface $from, $msg) {

      //  exec_enabled();

        //$input = $_GET["input"];

        //$output = array();
        exec("java -jar ..\iCircles.jar \"" . $msg . "\"", $output);

        $resultText = "";
        foreach ($output as $result){
            $resultText = $resultText.$result."\n";
        }

        $from->send($resultText);
        /*$numRecv = count($this->clients) - 1;
        echo sprintf('Connection %d sending message "%s" to %d other connection%s' . "\n"
            , $from->resourceId, $msg, $numRecv, $numRecv == 1 ? '' : 's');

        foreach ($this->clients as $client) {
            if ($from !== $client) {
                // The sender is not the receiver, send to each client connected
                $client->send($msg);
            }
        }*/
    }

    public function onClose(ConnectionInterface $conn) {
        // The connection is closed, remove it, as we can no longer send it messages
        $this->clients->detach($conn);

        echo "Connection {$conn->resourceId} has disconnected\n";
    }

    public function onError(ConnectionInterface $conn, \Exception $e) {
        echo "An error has occurred: {$e->getMessage()}\n";

        $conn->close();
    }
}