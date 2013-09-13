#!/usr/bin/perl -w

use Test::Inter;
$t = new Test::Inter 'run simple';
$testdir = '';
$testdir = $t->testdir();

use Shell::Cmd;
$obj = new Shell::Cmd;

sub test {
  ($op,@test)=@_;

  if ($op eq 'dire') {
    $err = $obj->dire(@test);
    return $err;

  } elsif ($op eq 'env') {
    $obj->env(@test);
    return 0;

  } elsif ($op eq 'options') {
    $err = $obj->options(@test);
    return $err;

  } elsif ($op eq 'cmd') {
    $obj->cmd(@test);
    return 0;

  } elsif ($op eq 'flush') {
    $obj->flush();
    return 0;

  } elsif ($op eq 'script') {
    $obj->options('run' => 'script');
    @tmp = $obj->run();
    $ret = shift(@tmp);
    @ret = ();
    while (@tmp) {
       ($cmd,$out,$err) = @{ shift(@tmp) };
       $cmd = ""  if (! defined $cmd);
       $out = ""  if (! defined $out);
       $err = ""  if (! defined $err);
       push(@ret,$cmd);
       push(@ret,"===STDOUT");
       push(@ret,split(/\n/,$out));
       push(@ret,"===STDERR");
       push(@ret,split(/\n/,$err));
    }
    push(@ret,"***FAILED")  if ($ret);
    return @ret;
  }
}

$tests="

##########################################

flush                            => 0

options echo echo                => 0

env DIR $testdir/dir_1           => 0

cmd  'cd \$DIR; ls -1'           => 0

script                           =>
   'cd \$DIR; ls -1'
   ===STDOUT
   a1
   b1
   ===STDERR

#############

flush                            => 0

options echo echo                => 0

env DIR $testdir/dir_2           => 0

cmd  'cd \$DIR; ls -1'           => 0

script                           =>
   'cd \$DIR; ls -1'
   ===STDOUT
   a2
   ===STDERR

#############
flush                            => 0

options echo echo                => 0

dire $testdir/dir_1              => 0

cmd  'ls -1'                     => 0

script                           =>
   'ls -1'
   ===STDOUT
   a1
   b1
   ===STDERR

#############

flush                            => 0

options echo echo                => 0

dire $testdir/dir_2              => 0

cmd  'ls -1'                     => 0

script                           =>
   'ls -1'
   ===STDOUT
   a2
   ===STDERR

##########################################

flush                            => 0

cmd  'cd $testdir/dir_1'         => 0

cmd  'ls -1'                     => 0

#############

options echo echo                => 0

script                           =>
   'cd $testdir/dir_1'
   ===STDOUT
   ===STDERR
   'ls -1'
   ===STDOUT
   a1
   b1
   ===STDERR

#############

options echo noecho              => 0

script                           =>
   ''
   ===STDOUT
   ===STDERR
   ''
   ===STDOUT
   a1
   b1
   ===STDERR

##########################################

flush                            => 0

cmd  '$testdir/bin/succ'         => 0

cmd  '$testdir/bin/succ'         => 0

options echo echo                => 0

#############

options output both              => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR
   'It will give a warning'
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR
   'It will give a warning'

#############

options output merged            => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   'It will give a warning'
   ===STDERR
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   'It will give a warning'
   ===STDERR

#############

options output stdout            => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR
   $testdir/bin/succ
   ===STDOUT
   'This will succeed'
   ===STDERR

#############

options output stderr            => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   ===STDERR
   'It will give a warning'
   $testdir/bin/succ
   ===STDOUT
   ===STDERR
   'It will give a warning'

#############

options output quiet             => 0

script                           =>
   $testdir/bin/succ
   ===STDOUT
   ===STDERR
   $testdir/bin/succ
   ===STDOUT
   ===STDERR

##########################################

flush                            => 0

cmd  '$testdir/bin/succ'         => 0

cmd  '$testdir/bin/fail'         => 0

cmd  '$testdir/bin/succ'         => 0

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

";

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
