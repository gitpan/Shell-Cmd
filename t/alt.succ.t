#!/usr/bin/perl -w

use Test::Inter;
$t = new Test::Inter 'alternates: success';
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

cmd  [ $testdir/bin/fail $testdir/bin/succ ]  => 0

cmd  '$testdir/bin/succ.2'       => 0

script                           =>
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR
   'It will give a warning'
   $testdir/bin/succ.2
   ===STDOUT
   'This will succeed too'
   ===STDERR
   'It will give a warning too'

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
