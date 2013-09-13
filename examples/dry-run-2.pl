#!/usr/bin/perl

use Shell::Cmd;
$obj = new Shell::Cmd;
$obj->options("echo" => "echo");
$obj->options("run"  => "dry-run");
$obj->cmd("if [ -d /tmp ]; then",  { "flow" => 1 },
          "   ls /tmp",
          "fi",                    { "flow" => 1 },
         );
($script) = $obj->run();

print $script;

