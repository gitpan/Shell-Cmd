#!/usr/bin/perl -w

use Test::Inter;
$t = new Test::Inter 'opt: misc';
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

env DIR '$testdir/dir 1'         => 0

cmd  'cd "\$DIR"; ls -1'       => 0

script                           =>
   'cd "\$DIR"; ls -1'
   ===STDOUT
   a1
   b1
   ===STDERR

##########################################
# Test dire option

flush                            => 0

options echo echo                => 0

dire '$testdir/dir 1'            => 0

cmd  'ls -1'                     => 0

script                           =>
   'ls -1'
   ===STDOUT
   a1
   b1
   ===STDERR

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
