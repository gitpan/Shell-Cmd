#!/usr/bin/perl

use Shell::Cmd;
$obj = new Shell::Cmd;
$obj->options("echo" => "echo");
$obj->options("mode" => "run");
$obj->cmd("if [ -d /tmp ]; then",  { "flow" => 1 },
          "   ls /tmp",
          "fi",                    { "flow" => 1 },
         );
($err) = $obj->run();

print "ERROR: $err\n";

