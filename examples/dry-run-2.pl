#!/usr/bin/perl

use Shell::Cmd;
$obj = new Shell::Cmd;
$obj->options("echo" => "echo");
$obj->options("run"  => "dry-run");
$obj->cmd("if [ -d /tmp/1 ]; then",   { "flow" => '+' },
          "echo 'case 1'",
          "elif [ -d /tmp/2 ]; then", { "flow" => '=' },
          "echo 'case 2'",
          "if [ -d /tmp/2/a ]; then", { "flow" => '+' },
          "echo 'case 2a'", 
          "fi",                       { "flow" => '-' },
          "fi",                       { "flow" => '-' },
         );
($script) = $obj->run();

print $script;

