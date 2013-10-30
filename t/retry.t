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
# Test retry option

flush                            => 0

options echo echo                => 0

cmd  '$testdir/bin/fail_twice'   { retry 5 }      => 0

cmd  '$testdir/bin/succ'                          => 0

script                           =>
   $testdir/bin/fail_twice
   ===STDOUT
   'Running first time'
   ===STDERR
   'Failing first time'
   $testdir/bin/fail_twice
   ===STDOUT
   'Running second time'
   ===STDERR
   'Failing second time'
   $testdir/bin/fail_twice
   ===STDOUT
   'Running third time'
   ===STDERR
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR
   'It will give a warning'

#############

flush                            => 0

options echo echo                => 0

cmd  '$testdir/bin/fail'   { retry 3 }      => 0

cmd  '$testdir/bin/succ'                    => 0

script                           =>
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   ***FAILED

#############

flush                            => 0

options echo echo                => 0

cmd  [ $testdir/bin/fail $testdir/bin/fail_twice ]  { retry 5 }      => 0

cmd  '$testdir/bin/succ'                          => 0

script                           =>
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail_twice
   ===STDOUT
   'Running first time'
   ===STDERR
   'Failing first time'
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail_twice
   ===STDOUT
   'Running second time'
   ===STDERR
   'Failing second time'
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail_twice
   ===STDOUT
   'Running third time'
   ===STDERR
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR
   'It will give a warning'

#############

flush                            => 0

options failure display          => 0

options echo echo                => 0

cmd  '$testdir/bin/fail'                       => 0

cmd  '$testdir/bin/fail_twice'   { retry 3 }   => 0

cmd  '$testdir/bin/succ'                       => 0

script                           =>
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail_twice
   ===STDOUT
   '# COMMAND NOT RUN: $testdir/bin/fail_twice'
   ===STDERR
   $testdir/bin/succ
   ===STDOUT
   '# COMMAND NOT RUN: $testdir/bin/succ'
   ===STDERR
   ***FAILED

#############

flush                            => 0

options failure continue         => 0

options echo echo                => 0

cmd  '$testdir/bin/fail'                       => 0

cmd  '$testdir/bin/fail_twice'   { retry 3 }   => 0

cmd  '$testdir/bin/succ'                       => 0

script                           =>
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   $testdir/bin/fail_twice
   ===STDOUT
   'Running first time'
   ===STDERR
   'Failing first time'
   $testdir/bin/fail_twice
   ===STDOUT
   'Running second time'
   ===STDERR
   'Failing second time'
   $testdir/bin/fail_twice
   ===STDOUT
   'Running third time'
   ===STDERR
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
