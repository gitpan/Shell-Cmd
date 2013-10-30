#!/usr/bin/perl -w

use Test::Inter;
$t = new Test::Inter 'opt: flow';
$testdir = '';
$testdir = $t->testdir();

use Shell::Cmd;
$::obj = undef;
$::obj = new Shell::Cmd;

require "$testdir/testfunc.pl";

$tests=qq(

##########################################
# Test flow option

flush                            => 0

options echo echo                => 0

cmd  'if [ -d "$testdir/dir 2" ]; then'    { flow + }   => 0

cmd  'cd "$testdir/dir 2"'                              => 0

cmd  'ls -1'                                              => 0

cmd  'elif [ -d "$testdir/dir 1" ]; then'  { flow = }   => 0

cmd  'cd "$testdir/dir 1"'                              => 0

cmd  'ls -1'                                              => 0

cmd  'else'                                  { flow = }   => 0

cmd  'echo "No directory found"'                        => 0

cmd  'fi'                                    { flow - }   => 0

script                           =>
   'cd "$testdir/dir 1"'
   ===STDOUT
   ===STDERR
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
