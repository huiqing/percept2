<?php
use Ratchet\Server\IoServer;
use Ratchet\Http\HttpServer;
use Ratchet\WebSocket\WsServer;
use HighVis\HVWebSocket;

    //require '/../autoload.php';
    require dirname(__DIR__) . '/vendor/autoload.php'; 

    //require '/vendor/autoload.php';
/*
    $server = IoServer::factory(
            new WsServer(
                new HVWebSocket()
            )
        , 8081
    );
/*/
$server = IoServer::factory(
        new HttpServer(
            new WsServer(
                new HVWebSocket()
            )
        ),
        8081
    );

    $server->run();