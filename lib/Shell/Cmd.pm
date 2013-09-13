package Shell::Cmd;
# Copyright (c) 2013-2013 Sullivan Beck. All rights reserved.
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.

###############################################################################

require 5.008;
use warnings 'all';
use strict;
use Capture::Tiny qw(capture capture_stdout capture_stderr);
use Net::OpenSSH;
use Parallel::ForkManager 0.7.6;

our($VERSION);
$VERSION = "1.00";

###############################################################################
# METHODS
###############################################################################

sub version {
  my($self) = @_;
  return $VERSION;
}

sub new {
   my($class,%options) = @_;

   my $self = {};

   bless $self,$class;
   $self->flush();

   return $self;
}

sub flush {
   my($self, @opts)   = @_;
   my $all            = 1  if (! @opts);
   my %opts           = map { $_,1 } @opts;

   $$self{'dire'}     = '.'       if ($all  ||  $opts{'dire'});

   # [ [VAR, VAL], [VAR, VAL], ... ]
   $$self{'env'}      = []        if ($all  ||  $opts{'env'});

   if ($all  ||  $opts{'opts'}) {
      $$self{'run'}      = 'run';
      $$self{'output'}   = 'both';
      $$self{'f-output'} = 'f-both';
      $$self{'echo'}     = 'noecho';

      $$self{'ssh_opts'} = {};
      $$self{'ssh_num'}  = 1;
   }

   # [ [CMD, %OPTS], [CMD, %OPTS], ... ]
   $$self{'cmd'}      = []        if ($all  ||  $opts{'commands'});
}

###############################################################################

sub dire {
   my($self,$dire) = @_;

   if (! -d $dire) {
      $self->_print(1,"Directory does not exist: $dire");
      return 1;
   }
   $$self{'dire'} = $dire;
   return 0;
}

sub env {
   my($self,$var,$val) = @_;

   push @{ $$self{'env'} },[$var,$val];
}

sub options {
   my($self,%opts) = @_;

   OPT:
   foreach my $opt (keys %opts) {

      my $val = $opts{$opt};
      $opt    = lc($opt);
      $val    = lc($val);

      if ($opt eq 'run') {

         if ($val =~ /^(run|dry-run|script)$/) {
            $$self{'run'} = $val;
            next OPT;
         }

      } elsif ($opt eq 'output') {

         if ($val =~ /^(both|merged|stdout|stderr|quiet)$/) {
            $$self{'output'} = $val;
            next OPT;
         }

      } elsif ($opt eq 'f-output') {

         if ($val =~ /^(f-both|f-stdout|f-stderr|f-quiet)$/) {
            $$self{'f-output'} = $val;
            next OPT;
         }

      } elsif ($opt eq 'echo') {

         if ($val =~ /^(echo|noecho|failed)$/) {
            $$self{'echo'} = $val;
            next OPT;
         }

      } elsif ($opt =~ s/^ssh://) {
         $$self{'ssh_opts'}{$opt} = $val;
         next OPT;

      } elsif ($opt eq 'ssh_num') {
         $$self{'ssh_num'} = $val;
         next OPT;

      } else {
         $self->_print(1,"Invalid option: $opt");
         return 1;
      }

      $self->_print(1,"Invalid value: $opt [ $val ]");
      return 1;
   }

   return 0;
}

###############################################################################

sub cmd {
   my($self,@args) = @_;

   while (@args) {
      my $cmd  = shift(@args);
      if (ref($cmd) ne ''  &&
          ref($cmd) ne 'ARRAY') {
         $self->_print(1,"cmd must be a string or listref");
         return 1;
      }

      my %options;
      if (@args  &&  ref($args[0]) eq 'HASH') {
         %options = %{ shift(@args) };
      }

      foreach my $opt (keys %options) {
         if ($opt !~ /^(dire|flow)$/) {
            $self->_print(1,"Invalid cmd option: $opt");
            return 1;
         }
      }

      if ($options{'flow'}) {
         if ($options{'dire'}) {
            $self->_print(1,"Flow option should not be used with dire");
            return 1;
         }
         if (ref($cmd)) {
            $self->_print(1,
                          "Flow option should not be used with command alternates");
            return 1;
         }
      }

      push @{ $$self{'cmd'} },[$cmd,%options];
   }
   return 0;
}

###############################################################################

# Construct and run or print the script.
#
sub run {
   my($self) = @_;
   my ($script,$stdout,$stderr) = $self->_script();

   #
   # Print out the script if this is a dry run.
   #

   if ($$self{'run'} eq 'dry-run') {
      $script .= "\n";
      return ($script);
   }

   #
   # If it's running in real-time, do so.
   #

   if ($$self{'run'} eq 'run') {
      system("$script");
      return ($?);
   }

   #
   # If it's running in 'script' mode, capture the output so that
   # we can parse it.
   #

   my($capt_out,$capt_err,$capt_exit);

   if      ($stdout  &&  $stderr) {
      ($capt_out,$capt_err,$capt_exit) = capture        {
         $capt_exit = system( "$script" ) };
   } elsif ($stdout) {
      ($capt_out,$capt_exit)           = capture_stdout {
         $capt_exit = system( "$script" ) };
   } elsif ($stderr) {
      ($capt_err,$capt_exit)           = capture_stderr {
         $capt_exit = system( "$script" ) };
   } else {
      system("$script");
      $capt_exit = $?;
   }
   $capt_exit = $capt_exit >> 8;

   #
   # Parse the output and return it.
   #

   return $self->_script_output($capt_out,$capt_err,$capt_exit);
}

###############################################################################

sub ssh {
   my($self,@hosts) = @_;

   if (! @hosts) {
      $self->_print(1,"A host or hosts must be supplied with the ssh method");
      return 1;
   }

   my ($script,$stdout,$stderr) = $self->_script();

   #
   # Print out the script if this is a dry run.
   #

   if ($$self{'run'} eq 'dry-run') {
      $script .= "\n";
      $script  = $self->_quote($script);

      my @ret;
      foreach my $host (@hosts) {
         push @ret, "##########################\n" .
                    "ssh $host \"$script\"\n\n";
      }
      return @ret;
   }

   #
   # Run the script on each host.
   #

   if ($$self{'ssh_num'} == 1) {
      return $self->_ssh_serial($script,$stdout,$stderr,@hosts);
   } else {
      return $self->_ssh_parallel($script,$stdout,$stderr,@hosts);
   }
}

sub _ssh_serial {
   my($self,$script,$stdout,$stderr,@hosts) = @_;
   my @ret;

   foreach my $host (@hosts) {
      push @ret, $self->_ssh($script,$stdout,$stderr,$host);
   }

   return @ret;
}

sub _ssh_parallel {
   my($self,$script,$stdout,$stderr,@hosts) = @_;
   my @ret;

   my $max_proc = ($$self{'ssh_num'} ? $$self{'ssh_num'} : @hosts);
   my $manager = Parallel::ForkManager->new($max_proc);

   $manager->run_on_finish(
                           sub {
                              my($pid,$exit_code,$id,$signal,$core_dump,$data) = @_;
                              my $n    = shift(@$data);
                              $ret[$n] = $data;
                           }
                          );

   for (my $i=0; $i<@hosts; $i++) {
      my $host = $hosts[$i];

      $manager->start and next;

      my @r = ($i);
      push @r, $self->_ssh($script,$stdout,$stderr,$host);

      $manager->finish(0,\@r);
   }

   $manager->wait_all_children();
   return @ret;
}

sub _ssh {
   my($self,$script,$stdout,$stderr,$host) = @_;

   my $ssh = Net::OpenSSH->new($host, %{ $$self{'ssh_opts'} });

   #
   # If it's running in real-time, do so.
   #

   if ($$self{'run'} eq 'run') {
      $ssh->system({},$script);
      return ($?);
   }

   #
   # If it's running in 'script' mode, capture the output so that
   # we can parse it.
   #

   my($capt_out,$capt_err,$capt_exit);

   if      ($stderr) {
      ($capt_out,$capt_err) = $ssh->capture2({},$script);
      $capt_exit            = $?;
   } elsif ($stdout) {
      $capt_out             = $ssh->capture({},$script);
      $capt_exit            = $?;
   } else {
      $ssh->system({},$script);
      $capt_exit            = $?;
   }

   #
   # Parse the output and return it.
   #

   return $self->_script_output($capt_out,$capt_err,$capt_exit);
}

###############################################################################
###############################################################################

# To handle environment variables, just add them to the start
# of the script:
#    ENV_VAR=VAL
#    export ENV_VAR
#
sub _cmd_env {
   my($self) = @_;
   my @script;

   my @env = @{ $$self{'env'} };
   my @var;
   if (@env) {
      push @script,
        q(#),
        q(# Set up environment variables),
        q(#);
      foreach my $env (@env) {
         my($var,$val) = @$env;
         $val          = $self->_quote($val);
         push @script, qq($var="$val");
         push(@var,$var);
      }
      my $vars = join(' ',@var);
      push @script, qq(export $vars);
      push(@script,'');
   }

   return @script;
}

# To handle the working directory, we'll check for the existance of the
# directory, and store the directory in a variable.
#
sub _cmd_dire {
   my($self) = @_;
   my(@script);

   push @script,
     q(#),
     q(# Handle working directory),
     q(#);
   if ($$self{'dire'}  &&  $$self{'dire'} ne '.') {
      my $dire = $self->_quote($$self{'dire'});
      push @script,
        qq(SC_DIRE="$dire";),
         q(if [ -d "$SC_DIRE" ]; then),
         q(   cd "$SC_DIRE";),
         q(else),
         q(   echo "Directory does not exist: $SC_DIRE" >&2;),
         q(   exit 1;),
         q(fi;),
   } else {
      push @script, q(SC_DIRE=`pwd`;);
   }
   push(@script,'');

   return @script;
}

# This analyzes the 'output' and 'f-output' options and verifies
# that they are consistent.
#
# It returns a string that will be appended to commands to send
# the output to the appropriate location.
#
sub _cmd_output {
   my($self) = @_;

   # $output  is a string to append to the command to handle
   #          STDOUT/STDERR redirection
   # $stdout  1 if we're keeping STDOUT
   # $stderr  1 if we're keeping STDERR

   # If we ever want:
   #    STDOUT -> /dev/null,  STDERR -> STDOUT:
   # use:
   #    $output = '2>&1 >/dev/null';

   my $output = '';
   my $stdout = 1;
   my $stderr = 1;

   if ($$self{'run'} eq 'run'  ||
       $$self{'run'} eq 'dry-run') {

      if ($$self{'output'} eq 'both') {
         # This is okay
      } elsif ($$self{'output'} eq 'merged') {
         $output = '2>&1';
         $stderr = 0;
      } elsif ($$self{'output'} eq 'stdout') {
         $output = '2>/dev/null';
         $stderr = 0;
      } elsif ($$self{'output'} eq 'stderr') {
         $output = '>/dev/null';
         $stdout = 0;
      } elsif ($$self{'output'} eq 'quiet') {
         $output = '>/dev/null 2>&1';
         $stdout = 0;
         $stderr = 0;
      }

   } elsif ($$self{'run'} eq 'script') {

      if ($$self{'output'} eq 'merged') {
         $output = '2>&1';

         if ($$self{'f-output'} eq 'f-both'    ||
             $$self{'f-output'} eq 'f-stdout'  ||
             $$self{'f-output'} eq 'f-stderr') {
            # If regular output is merged, then it cannot be
            # separate for a failed command.
            $$self{'f-output'} = 'f-merged';

         } elsif ($$self{'f-output'} eq 'f-merged') {
            # This is okay.

         } elsif ($$self{'f-output'} eq 'f-quiet') {
            # This is okay too.

         }

      } elsif ($$self{'output'} eq 'both'    ||
               $$self{'output'} eq 'stdout'  ||
               $$self{'output'} eq 'stderr') {

         if ($$self{'f-output'} eq 'f-both'    ||
             $$self{'f-output'} eq 'f-stdout'  ||
             $$self{'f-output'} eq 'f-stderr') {
            # These are okay.  Discard any output we don't use.
            if ($$self{'output'} eq 'stderr'  &&
                $$self{'f-output'} eq 'f-stderr') {
               $output = '>/dev/null';
               $stdout = 0;
            } elsif ($$self{'output'} eq 'stdout'  &&
                     $$self{'f-output'} eq 'f-stdout') {
               $output = '2>/dev/null';
               $stderr = 0;
            }

         } elsif ($$self{'f-output'} eq 'f-merged') {
            # We can't support merged output on a failed
            # command since it hasn't been merged, so we'll
            # just do the next best thing.
            $$self{'f-output'} = 'f-both';

         } elsif ($$self{'f-output'} eq 'f-quiet') {
            # This is okay.  We can discard output here too.
            if ($$self{'output'} eq 'stderr') {
               $output = '>/dev/null';
               $stdout = 0;
            } elsif ($$self{'output'} eq 'stdout') {
               $output = '2>/dev/null';
               $stderr = 0;
            }

         }

      } elsif ($$self{'output'} eq 'quiet') {

         if ($$self{'f-output'} eq 'f-both'    ||
             $$self{'f-output'} eq 'f-stdout'  ||
             $$self{'f-output'} eq 'f-stderr') {
            # This is okay.  We can discard output here.
            if ($$self{'f-output'} eq 'f-stderr') {
               $output = '>/dev/null';
               $stdout = 0;
            } elsif ($$self{'f-output'} eq 'f-stdout') {
               $output = '2>/dev/null';
               $stderr = 0;
            }

         } elsif ($$self{'f-output'} eq 'f-merged') {
            # This is okay, but we want to merge the output.
            $output = '2>&1';
            $stderr = 0;
         } elsif ($$self{'f-output'} eq 'f-quiet') {
            # This is okay, and we can discard all output.
            $output = '>/dev/null 2>&1';
            $stdout = 0;
            $stderr = 0;
         }

      }
   }

   return ($output,$stdout,$stderr);
}

# This will set up a command (echoing, etc.)
#
sub _cmd_init {
   my($self,$cmd,$cmd_num,$alt_num,$only,$stdout,$stderr,$dire) = @_;
   my @script;

   #
   # Add some stuff to clarify the start of the command.
   #
   # If we're running it in 'script' mode, then we need to specify the
   # start of the output for this command.
   #
   # If we're just creating a script, we'll just add some comments.
   #

   if ($$self{'run'} eq 'script') {
      if ($stdout) {
         push @script, qq(echo "#SC CMD $cmd_num.$alt_num";);
      }
      if ($stderr) {
         push @script, qq(echo "#SC CMD $cmd_num.$alt_num" >&2;);
      }

   } elsif ($$self{'run'} eq 'dry-run') {
      #
      # Command number comment
      #

      if ($only) {
         push @script,
           qq(#),
           qq(# Command $cmd_num),
           qq(#);
      } else {
         push @script,
           qq(#),
           qq(# Command $cmd_num.$alt_num),
           qq(#);
      }
   }

   #
   # Handle the per-command 'dire' option.
   #

   if ($dire) {
      $dire = $self->_quote($dire);
      push @script,
        qq(cd "$dire;"),
         q(if [ "$?" != 0 ]; then),
        qq(   exit $cmd_num;),
         q(fi);
   }

   #
   # Echo the command (if desired) when running real-time.  When
   # running it as a script, we don't need to echo it during the
   # execution.  It can be done added when we parse the output.
   #

   if ($$self{'run'} eq 'run'  &&
       $$self{'echo'} eq 'echo') {
      $cmd = $self->_quote($cmd);
      push @script, qq(echo "# $cmd";);
   }

   return @script;
}

# This will finish up a command
#
sub _cmd_term {
   my($self,$dire) = @_;
   my @script;

   #
   # Handle the per-command 'dire' option.
   #

   if ($dire) {
      push @script, q(cd "$SC_DIRE";);
   }

   #
   # Make sure that the last command has included a newline when
   # running in script mode.
   #

   push @script, q(echo "";)  if ($$self{'run'} eq 'script');
   return @script;
}

sub _cmd {
   my($self,$cmd,$cmd_num,$output,$first,$last,$only,$flow) = @_;
   my(@script);

   # We want to generate the following script:
   #
   #    CMD1
   #    if [ "$?" != 0 ]; then
   #       CMD2
   #    fi
   #    ...
   #    if [ "$?" != 0 ]; then
   #       CMDn
   #    fi
   #    if [ "$?" != 0 ]; then
   #       exit X
   #
   # where CMDn is the last alternate and X is the command number.

   my $semicolon = ($flow ? '' : ';');

   if ($first) {
      push @script, qq($cmd $output$semicolon);

   } else {
      push @script,
         q(if [ "$?" != 0 ]; then),
        qq(   $cmd $output$semicolon),
         q(fi);
   }

   if ($last  &&  ! $flow) {
      push @script,
         q(if [ "$?" != 0 ]; then),
        qq(   exit $cmd_num;),
         q(fi);
   }
   push @script, "";

   return @script;
}

# This creates the script and it is ready to be printed or evaluated
# in double quotes.
#
sub _script {
   my($self) = @_;

   my @script;

   #
   # Handle env, dire, and output options
   #

   push @script, $self->_cmd_env();
   push @script, $self->_cmd_dire();
   my ($output,$stdout,$stderr) = $self->_cmd_output();

   #
   # Handle each command.  They will be numbered (starting at 1).
   #
   # Each command can have any number of alternates, only one of
   # which needs to succeed for the command to be treated as a
   # success.
   #

   my $cmd_num = 0;
   foreach my $ele (@{ $$self{'cmd'} }) {
      my($cmd,%options) = @$ele;
      my $dire          = ($options{'dire'} ? $options{'dire'} : '');
      my $flow          = ($options{'flow'} ? 1 : 0);
      $cmd_num++;

      my @cmd           = (ref($cmd) ? @$cmd : ($cmd));

      my $alt_num       = 0;
      my $only          = (@cmd==1     ? 1 : 0);  # 1 if there are no alternates
      while (@cmd) {
         my $first      = ($alt_num==0 ? 1 : 0);  # 1 if this is the first or only
                                                  # alternate
         my $last       = (@cmd==1     ? 1 : 0);  # 1 if this is the last or only
                                                  # alternate
         my $c          = shift(@cmd);

         #
         # Add the command to the script (with error handling)
         #

         push @script,
           $self->_cmd_init($c,$cmd_num,$alt_num,$only,$stdout,$stderr,$dire);
         push @script, $self->_cmd($c,$cmd_num,$output,$first,$last,$only,$flow);
         push @script, $self->_cmd_term($dire);

         $alt_num++;
      }
   }

   #
   # Form the script.
   #

   my $script = join("\n",@script);

   return ($script,$stdout,$stderr);
}

sub _script_output {
   my($self,$stdout,$stderr,$exit) = @_;
   my @ret = ($exit ? (1) : (0));
   my @out = split(/\n/,$stdout);
   my @err = split(/\n/,$stderr);

   my $cmd_num = 0;

   CMD:
   foreach my $ele (@{ $$self{'cmd'} }) {
      my($cmd,%options) = @$ele;
      $cmd_num++;
      my @cmd           = (ref($cmd) ? @$cmd : ($cmd));

      ALT:
      for (my $alt_num=0; $alt_num<@cmd; $alt_num++) {
         # If a command failed, subsequent ones were not run.
         last ALT  if (! @out  &&  ! @err);

         my $c;
         if ($$self{'echo'} eq 'echo'  ||
             ($$self{'echo'} eq 'failed'  &&  $exit == $cmd_num)) {
            $c = $cmd[$alt_num];
         } else {
            $c = '';
         }

         my $out;
         if ($out[0] eq "#SC CMD $cmd_num.$alt_num") {
            shift(@out);
            my @tmp;
            while (@out  &&  $out[0] !~ /^#SC CMD/) {
               push(@tmp,shift(@out));
            }
            my $txt = join("\n",@tmp);

            if ($exit == $cmd_num) {
               # Handle the failed command
               if ($$self{'f-output'} eq 'f-both'    ||
                   $$self{'f-output'} eq 'f-merged'  ||
                   $$self{'f-output'} eq 'f-stdout') {
                  $out = $txt;
               } else {
                  $out = '';
               }

            } else {
               # Handle a successful command
               if ($$self{'output'} eq 'both'    ||
                   $$self{'output'} eq 'merged'  ||
                   $$self{'output'} eq 'stdout') {
                  $out = $txt;
               } else {
                  $out = '';
               }
            }
         } else {
            # Invalid output... should never happen
            $self->_print(1,
                          "Missing command header in stdout for command: $cmd_num");
         }

         my $err;
         if ($err[0] eq "#SC CMD $cmd_num.$alt_num") {
            shift(@err);
            my @tmp;
            while (@err  &&  $err[0] !~ /^#SC CMD/) {
               push(@tmp,shift(@err));
            }
            my $txt = join("\n",@tmp);

            if ($exit == $cmd_num) {
               # Handle the failed command
               if ($$self{'f-output'} eq 'f-both'    ||
                   $$self{'f-output'} eq 'f-stderr') {
                  $err = $txt;
               } else {
                  $err = '';
               }

            } else {
               # Handle a successful command
               if ($$self{'output'} eq 'both'    ||
                   $$self{'output'} eq 'stderr') {
                  $err = $txt;
               } else {
                  $err = '';
               }
            }
         } else {
            # Invalid stderr... should never happen
            $self->_print(1,
                          "Missing command header in stderr for command: $cmd_num");
         }

         push(@ret,[$c,$out,$err]);
      }

      last CMD  if ($exit == $cmd_num);
   }

   return @ret;
}

###############################################################################

sub _print {
   my($self,$err,$text) = @_;

   my $c = ($err ? "# ERROR: " : "# INFO: ");

   print {$err ? *STDERR : *STDOUT} "${c}${text}\n";
}

# This prepares a string to be enclosed in double quotes.
#
# Escape:  \ $ ` "
#
sub _quote {
   my($self,$string) = @_;

   $string =~ s/([\\\$`"])/\\$1/g;
   return $string;
}


1;
# Local Variables:
# mode: cperl
# indent-tabs-mode: nil
# cperl-indent-level: 3
# cperl-continued-statement-offset: 2
# cperl-continued-brace-offset: 0
# cperl-brace-offset: 0
# cperl-brace-imaginary-offset: 0
# cperl-label-offset: 0
# End:
