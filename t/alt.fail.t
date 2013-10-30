#!/usr/bin/perl -w

use Test::Inter;
$t = new Test::Inter 'alternates: all fail';
$testdir = '';
$testdir = $t->testdir();

use Shell::Cmd;
$::obj = undef;
$::obj = new Shell::Cmd;

require "$testdir/testfunc.pl";

$tests=qq(

##########################################
# Test env option

flush                            => 0

options echo echo                => 0

cmd  [ $testdir/bin/fail $testdir/bin/fail.2 ]  => 0

cmd  '$testdir/bin/succ'         => 0

script                           =>
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail.2
   ===STDOUT
   'This will fail too'
   ===STDERR
   'It will give an error too'
   ***FAILED

#############

options failure display          => 0

script                           =>
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail.2
   ===STDOUT
   'This will fail too'
   ===STDERR
   'It will give an error too'
   $testdir/bin/succ
   ===STDOUT
   '# COMMAND NOT RUN: $testdir/bin/succ'
   ===STDERR
   ***FAILED

#############

options failure continue         => 0

script                           =>
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail.2
   ===STDOUT
   'This will fail too'
   ===STDERR
   'It will give an error too'
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR
   'It will give a warning'
   ***FAILED

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
