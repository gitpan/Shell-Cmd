#!/usr/bin/perl -w

use Test::Inter;
$t = new Test::Inter 'special characters';
$testdir = '';
$testdir = $t->testdir();

use Shell::Cmd;
$::obj = undef;
$::obj = new Shell::Cmd;

require "$testdir/testfunc.pl";

$::obj->cmd(q(echo "Dollar \$ Backtick \` Backslash \\ Quote \""));

$tests=q(

##########################################
# Test special characters

options echo echo                => 0

script                           =>
   'echo "Dollar \$ Backtick \` Backslash \\ Quote \""'
   ===STDOUT
   'Dollar $ Backtick ` Backslash \ Quote "'
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
