#!/usr/bin/perl

if (! @ARGV) {
   die "usage: ssh-parallel-run.pl HOST HOST ...\n";
}

use Shell::Cmd;
$obj = new Shell::Cmd;
$obj->options("echo" => "echo");
$obj->options("run"  => "script");
$obj->options("ssh_num" => 5);
$obj->cmd(q(echo "Dollar \$ Backtick \` Backslash \\\\ Quote \\""));
$obj->cmd("hostname");
@out = $obj->ssh(@ARGV);

foreach my $host (@ARGV) {
   print "#############################\n";
   print "# $host\n";
   print "#############################\n";
   $tmp = shift(@out);
   @tmp = @$tmp;
   shift(@tmp);

   while (@tmp) {
      my ($cmd,$out,$err) = @{ shift(@tmp) };
      print "# $cmd\n";
      print "# STDOUT\n";
      print "$out\n";
      print "# STDERR\n";
      print "$err\n";
      print "\n";
   }
}
