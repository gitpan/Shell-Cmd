#!/usr/bin/perl -w

use Test::Inter;
$t = new Test::Inter 'dry-run';
$testdir = '';
$testdir = $t->testdir();

use Shell::Cmd;
$::obj = undef;
$::obj = new Shell::Cmd;

require "$testdir/testfunc.pl";

$::obj->options("echo" => "echo");
$::obj->cmd("if [ -d /tmp/1 ]; then",   { "flow" => '+' },
            "echo 'case 1'",
            "elif [ -d /tmp/2 ]; then", { "flow" => '=' },
            "echo 'case 2'",
            "if [ -d /tmp/2/a ]; then", { "flow" => '+' },
            "echo 'case 2a'",
            "fi",                       { "flow" => '-' },
            "fi",                       { "flow" => '-' },
           );

$tests=q(

##########################################
# Dry-run

dry-run  =>
   "SC_FAILED=0;"
   "SC_DIRE=`pwd`;"
   "SC_ALT_FAILED=0;"
   "if [ -d /tmp/1 ]; then"
   ""
   "   if [ $SC_FAILED -eq 0 ]; then"
   "      SC_ALT_FAILED=0;"
   "      #"
   "      # Command 3"
   "      #"
   "      SC_ALT_PASSED=0;"
   "      echo 'case 1' ;"
   "      if [ $? -eq 0 ]; then"
   "         SC_ALT_PASSED=1;"
   "      fi"
   ""
   "      if [ $SC_ALT_PASSED -eq 0 ]; then"
   "         SC_ALT_FAILED=1;"
   "      fi"
   "      if [ $SC_ALT_FAILED -ne 0 ]; then"
   "         SC_FAILED=3;"
   "      fi"
   "   fi"
   "   SC_ALT_FAILED=0;"
   "elif [ -d /tmp/2 ]; then"
   ""
   "   if [ $SC_FAILED -eq 0 ]; then"
   "      SC_ALT_FAILED=0;"
   "      #"
   "      # Command 5"
   "      #"
   "      SC_ALT_PASSED=0;"
   "      echo 'case 2' ;"
   "      if [ $? -eq 0 ]; then"
   "         SC_ALT_PASSED=1;"
   "      fi"
   ""
   "      if [ $SC_ALT_PASSED -eq 0 ]; then"
   "         SC_ALT_FAILED=1;"
   "      fi"
   "      if [ $SC_ALT_FAILED -ne 0 ]; then"
   "         SC_FAILED=5;"
   "      fi"
   "   fi"
   "   SC_ALT_FAILED=0;"
   "   if [ -d /tmp/2/a ]; then"
   ""
   "      if [ $SC_FAILED -eq 0 ]; then"
   "         SC_ALT_FAILED=0;"
   "         #"
   "         # Command 7"
   "         #"
   "         SC_ALT_PASSED=0;"
   "         echo 'case 2a' ;"
   "         if [ $? -eq 0 ]; then"
   "            SC_ALT_PASSED=1;"
   "         fi"
   ""
   "         if [ $SC_ALT_PASSED -eq 0 ]; then"
   "            SC_ALT_FAILED=1;"
   "         fi"
   "         if [ $SC_ALT_FAILED -ne 0 ]; then"
   "            SC_FAILED=7;"
   "         fi"
   "      fi"
   "      SC_ALT_FAILED=0;"
   "   fi"
   ""
   "   SC_ALT_FAILED=0;"
   "fi"
   ""
   "exit $SC_FAILED;"

);

$t->tests(func  => \&test,
          tests => $tests);
$t->done_testing();

#Local Variables:
#mode: cperl
#indent-tabs-mode: nil
#cperl-indent-level: 3
#cperl-continued-statement-offset: 2
#cperl-continued-brace-offset: 0
#cperl-brace-offset: 0
#cperl-brace-imaginary-offset: 0
#cperl-label-offset: 0
#End:
