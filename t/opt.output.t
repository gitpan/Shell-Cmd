#!/usr/bin/perl -w

use Test::Inter;
$t = new Test::Inter 'opt: output';
$testdir = '';
$testdir = $t->testdir();

use Shell::Cmd;
$::obj = undef;
$::obj = new Shell::Cmd;

require "$testdir/testfunc.pl";

$tests=qq(

##########################################
# Test output options

flush                            => 0

cmd  '$testdir/bin/succ'         => 0

cmd  '$testdir/bin/succ.2'       => 0

options echo echo                => 0

#############

options output both              => 0

script                           =>
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

#############

options output merged            => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   'It will give a warning'
   ===STDERR
   $testdir/bin/succ.2
   ===STDOUT
   'This will succeed too'
   'It will give a warning too'
   ===STDERR

#############

options output stdout            => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR
   $testdir/bin/succ.2
   ===STDOUT
   'This will succeed too'
   ===STDERR

#############

options output stderr            => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   ===STDERR
   'It will give a warning'
   $testdir/bin/succ.2
   ===STDOUT
   ===STDERR
   'It will give a warning too'

#############

options output quiet             => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   ===STDERR
   $testdir/bin/succ.2
   ===STDOUT
   ===STDERR

##########################################
# Test f-output options

flush                            => 0

cmd  '$testdir/bin/succ'         => 0

cmd  '$testdir/bin/fail'         => 0

cmd  '$testdir/bin/succ.2'       => 0

options echo echo                => 0

#############

options output both              => 0

options f-output f-both          => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR
   'It will give a warning'
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   '***FAILED'

#############

options output quiet             => 0

options f-output f-both          => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   ===STDERR
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   '***FAILED'

#############

options output stderr            => 0

options f-output f-both          => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   ===STDERR
   'It will give a warning'
   $testdir/bin/fail
   ===STDOUT
   'This will fail'
   ===STDERR
   'It will give an error'
   '***FAILED'

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
