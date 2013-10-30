#!/usr/bin/perl -w

sub test {
  ($op,@test)=@_;

  if ($op eq 'dire') {
    $err = $::obj->dire(@test);
    return $err;

  } elsif ($op eq 'env') {
    $::obj->env(@test);
    return 0;

  } elsif ($op eq 'options') {
    $err = $::obj->options(@test);
    return $err;

  } elsif ($op eq 'cmd') {
    $::obj->cmd(@test);
    return 0;

  } elsif ($op eq 'flush') {
    $::obj->flush();
    return 0;

  } elsif ($op eq 'script') {
    $::obj->options('run' => 'script');
    @tmp = $::obj->run();
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

  } elsif ($op eq 'dry-run') {
    $::obj->options('run' => 'dry-run');
    ($script) = $::obj->run();
    @ret = split(/\n/,$script);
    return (@ret);

  }
}

1;
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
