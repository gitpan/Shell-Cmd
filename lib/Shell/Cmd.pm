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
$VERSION = "1.12";

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
      $$self{'run'}       = 'run';
      $$self{'output'}    = 'both';
      $$self{'f-output'}  = 'f-both';
      $$self{'echo'}      = 'noecho';
      $$self{'simple'}    = 0;
      $$self{'failure'}   = 'exit';

      $$self{'ssh_opts'}  = {};
      $$self{'ssh_num'}   = 1;
      $$self{'ssh_sleep'} = 0;
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
            $$self{$opt} = $val;
            next OPT;
         }

      } elsif ($opt eq 'output') {

         if ($val =~ /^(both|merged|stdout|stderr|quiet)$/) {
            $$self{$opt} = $val;
            next OPT;
         }

      } elsif ($opt eq 'f-output') {

         if ($val =~ /^(f-both|f-stdout|f-stderr|f-quiet)$/) {
            $$self{$opt} = $val;
            next OPT;
         }

      } elsif ($opt eq 'echo') {

         if ($val =~ /^(echo|noecho|failed)$/) {
            $$self{$opt} = $val;
            next OPT;
         }

      } elsif ($opt eq 'failure') {

         if ($val =~ /^(exit|display|continue)$/) {
            $$self{$opt} = $val;
            next OPT;
         }

      } elsif ($opt =~ s/^ssh://) {
         $$self{'ssh_opts'}{$opt} = $val;
         next OPT;

      } elsif ($opt eq 'simple'  ||
               $opt eq 'ssh_num' ||
               $opt eq 'ssh_sleep'
              ) {
         $$self{$opt} = $val;
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
         if ($opt !~ /^(dire|flow|noredir|retry|sleep|check)$/) {
            $self->_print(1,"Invalid cmd option: $opt");
            return 1;
         }
      }

      if ($options{'flow'}) {
         if ($options{'dire'}) {
            $self->_print(1,"Flow option should not be used with dire");
            return 1;
         }
         if ($options{'retry'}  &&  $options{'retry'} > 1) {
            $self->_print(1,"Flow option should not be used with retry");
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
   my($self)   = @_;
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
   # If we're sleeping, do so.
   #

   if ($$self{'ssh_sleep'}) {
      sleep(int(rand($$self{'ssh_sleep'})));
   }

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

# Environment variables used in scripts:
#   SC_FAILED = N    : the command which failed (0 = none, 1 = script
#                      initialization)
#   SC_DIRE          : the working directory of the script
#   SC_RETRIES = N   : this command will run up to N times
#   SC_TRY = N       : we're currently on the Nth try
#   SC_ALT_FAILED    : 1 if all alternatives to this command failed
#   SC_ALT_PASSED    : one of the alternatives succeeded, so we
#                      don't need to run any more

# This creates the script and it is ready to be printed or evaluated
# in double quotes.
#
sub _script {
   my($self)  = @_;

   my @script;

   #
   # Handle env, dire, and output options
   #

   push @script, $self->_script_init();
   my ($output,$stdout,$stderr) = $self->_script_redirect();

   #
   # Handle each command.  They will be numbered starting at 2.
   # This allows 1 to refer to an exit in the script initialization.
   #
   # Each command can have any number of alternates, only one of
   # which needs to succeed for the command to be treated as a
   # success.
   #

   my $cmd_num = 1;
   foreach my $ele (@{ $$self{'cmd'} }) {
      my($cmd,%options) = @$ele;
      $cmd_num++;

      push @script, $self->_cmd_init($cmd_num,%options);

      #
      # Handle each alternate of the command.  They will be numbered
      # starting at 1.
      #

      my @cmd           = (ref($cmd) ? @$cmd : ($cmd));
      my $alt_num       = 0;
      my $only          = (@cmd==1     ? 1 : 0);  # 1 if there are no alternates
      while (@cmd) {
         $alt_num++;
         my $first      = ($alt_num==1 ? 1 : 0);  # 1 if this is the first or only
                                                  # alternate
         my $last       = (@cmd==1     ? 1 : 0);  # 1 if this is the last or only
                                                  # alternate
         my $c          = shift(@cmd);

         #
         # Add the command to the script (with error handling)
         #

         push @script, $self->_alt_init($c,$cmd_num,$alt_num,$only,$stdout,
                                        $stderr,%options);
         push @script, $self->_alt_cmd($c,$output,$first,%options);
         push @script, $self->_alt_term(%options);
      }

      push @script, $self->_cmd_term($cmd_num,%options);
   }

   #
   # Form the script.
   #

   push @script, $self->_script_term();
   my $script = join("\n",@script);

   return ($script,$stdout,$stderr);
}

# The stdout/stderr from a script-mode run is:
#     #SC CMD N1.A1
#     ...
#     #SC CMD N2.A2
#     ...
# where N* are the command number and A* are the alternate number.
#
# The output may repeat (if there are retries).
#
# The output from this script is:
#   ( EXIT, CMD_OUT, CMD_OUT, ... )
# where
#   EXIT is the exit code of the script
#   CMD_OUT is the description of the output from one command and
#      is: CMD_OUT = [ CMD, OUT, ERR ]
# where
#   CMD is the command that was run (if we're echoing)
#   OUT is STDOUT from the command
#   ERR is STDERR from the command
#
sub _script_output {
   my($self,$stdout,$stderr,$exit) = @_;
   my @ret = ($exit ? (1) : (0));
   my @out = split(/\n/,$stdout);
   my @err = split(/\n/,$stderr);

   LOOP:
   while (@out  ||  @err) {

      #
      # Get STDOUT/STDERR for the one command.
      #

      my($out_hdr,$c,@stdout,$cmd_num,$alt_num);

      if (@out) {
         $out_hdr = shift(@out);

         # If there is any STDOUT, it MUST start with a header:
         #    #SC CMD X.Y
         #
         if ($out_hdr !~ /^\#SC CMD (\d+)\.(\d+)$/) {
            # Invalid output... should never happen
            $self->_print(1,"Missing command header in STDOUT: $out_hdr");
            last LOOP;
         }

         ($cmd_num,$alt_num) = ($1,$2);

         while (@out  &&  $out[0] !~ /^\#SC CMD (\d+)\.(\d+)$/) {
            push(@stdout,shift(@out));
         }
      }

      my($err_hdr,@stderr);

      if (@err) {
         $err_hdr = shift(@err);

         # If there is any STDERR, it MUST start with a header:
         #    #SC CMD X.Y
         #
         if ($err_hdr !~ /^\#SC CMD (\d+)\.(\d+)$/) {
            # Invalid output... should never happen
            $self->_print(1,"Missing command header in STDERR: $err_hdr");
            last LOOP;
         }

         ($cmd_num,$alt_num) = ($1,$2);

         # If there was any STDOUT, then the command headers must be
         # identical.
         #
         if ($out_hdr  &&  $err_hdr ne $out_hdr) {
            # Mismatched headers... should never happen
            $self->_print(1,"Mismatched header in STDERR: $err_hdr");
            last LOOP;
         }

         while (@err  &&  $err[0] !~ /^\#SC CMD (\d+)\.(\d+)$/) {
            push(@stderr,shift(@err));
         }
      }

      #
      # Get the command that was actually run.
      #

      my $tmp  = $$self{'cmd'}[$cmd_num-2][0];
      my @cmd  = (ref($tmp) ? @$tmp : ($tmp));
      if ($$self{'echo'} eq 'echo'  ||
          ($$self{'echo'} eq 'failed'  &&  $exit == $cmd_num)) {
         $c = $cmd[$alt_num-1];
      } else {
         $c = '';
      }

      #
      # Strip leading/trailing blank lines from STDOUT/STDERR.
      #
      # Figure out which we need to keep based on output and f-output
      # options.
      #

      my($out,$err,$txt);
      while (@stdout  &&  $stdout[0] eq '') {
         shift(@stdout);
      }
      while (@stdout  &&  $stdout[$#stdout] eq '') {
         pop(@stdout);
      }
      $txt = join("\n",@stdout);

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

      while (@stderr  &&  $stderr[0] eq '') {
         shift(@stderr);
      }
      while (@stderr  &&  $stderr[$#stderr] eq '') {
         pop(@stderr);
      }
      $txt = join("\n",@stderr);

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

      push(@ret,[$c,$out,$err]);
   }

   return @ret;
}

{
   my $ind_per_lev = "   ";
   my $ind_cur_lev = 0;

   my $curr_ind    = "";
   my $next_ind    = $ind_per_lev;
   my $prev_ind    = "";

   sub _ind_plus {
      $ind_cur_lev++;
      $curr_ind    = $ind_per_lev x $ind_cur_lev;
      $next_ind    = $ind_per_lev x ($ind_cur_lev + 1);
      $prev_ind    = ($ind_cur_lev == 0 ? '' :
                      $ind_per_lev x ($ind_cur_lev - 1));
   }
   sub _ind_minus {
      $ind_cur_lev--;
      $ind_cur_lev = 0  if ($ind_cur_lev < 0);
      $curr_ind    = $ind_per_lev x $ind_cur_lev;
      $next_ind    = $ind_per_lev x ($ind_cur_lev + 1);
      $prev_ind    = ($ind_cur_lev == 0 ? '' :
                      $ind_per_lev x ($ind_cur_lev - 1));
   }

   #####################
   # Set up the script.

   sub _script_init {
      my($self) = @_;
      my $simple_script = ($$self{'run'} eq 'dry-run'  &&  $$self{'simple'}
                           ? 1 : 0);
      my @script;

      #
      # Initialize the variable which tracks which command failed.
      #
      #   SC_FAILED = N
      #      N = 0  : no failure
      #      N = 1  : failed in script initialization
      #      N = 2+ : failed in command N (numbered 2...)
      #
      # We do this in all cases except simple scripts.
      #

      if (! $simple_script) {
         push @script, qq(${curr_ind}SC_FAILED=0;);
      }

      #
      # Handle environment variables.
      #
      #   ENV_VAR=VAL
      #   export ENV_VAR
      #

      my @env = @{ $$self{'env'} };
      my @var;
      if (@env) {
         foreach my $env (@env) {
            my($var,$val) = @$env;
            $val          = $self->_quote($val);
            push @script, qq(${curr_ind}$var="$val");
            push(@var,$var);
         }
         my $vars = join(' ',@var);
         push @script, qq(${curr_ind}export $vars);
         push(@script,'');
      }

      #
      # To handle the working directory, we'll check for the existance of the
      # directory, and store the directory in a variable.
      #
      # We'll set an exit value of 1 if this fails, and it's not a simple
      # script.
      #

      if ($$self{'dire'}  &&  $$self{'dire'} ne '.') {
         my $dire = $self->_quote($$self{'dire'});
         if ($simple_script) {
            push @script,
              qq(${curr_ind}SC_DIRE="$dire";),
              qq(${curr_ind}cd "\$SC_DIRE";);
         } else {
            push @script,
              qq(${curr_ind}SC_DIRE="$dire";),
              qq(${curr_ind}if [ -d "\$SC_DIRE" ]; then),
              qq(${next_ind}cd "\$SC_DIRE";),
              qq(${curr_ind}else),
              qq(${next_ind}echo "Directory does not exist: \$SC_DIRE" >&2;),
              qq(${next_ind}SC_FAILED=1;),
              qq(${curr_ind}fi;);
         }
      } else {
         push @script, qq(${curr_ind}SC_DIRE=`pwd`;);
      }

      return @script;
   }

   sub _script_term {
      my($self) = @_;
      my $simple_script = ($$self{'run'} eq 'dry-run'  &&  $$self{'simple'}
                           ? 1 : 0);
      my @script;

      #
      # Handle the exit code.
      #

      if (! $simple_script) {
         push @script, qq(${curr_ind}exit \$SC_FAILED;);
      }

      return @script;
   }

   #####################
   # Set up the command (which might include any number of
   # alternates).

   sub _cmd_init {
      my($self,$cmd_num,%options) = @_;
      my @script;

      my $dire          = ($options{'dire'}  ? $options{'dire'} : '');
      my $flow          = ($options{'flow'}  ? $options{'flow'} : 0);
      my $retry         = ($options{'retry'} ? $options{'retry'} : 0) + 0;
      my $failure       = $$self{'failure'};
      my $simple_script = ($$self{'run'} eq 'dry-run'  &&  $$self{'simple'}
                           ? 1 : 0);
      $retry            = 0  if ($retry < 2  ||  $simple_script);
      my $exit_on_fail  = ($failure eq 'exit'  &&  ! $simple_script  &&  ! $flow
                           ? 1 : 0);

      #
      # If 'failure' is an exit, and we've already failed, then we'll
      # completely skip this command.  If we're doing a simple script,
      # we don't need to add this since we don't do error checking.
      #
      # Don't do this for flow commands.
      #

      if ($exit_on_fail) {
         push @script, qq(${curr_ind}if [ \$SC_FAILED -eq 0 ]; then);
         _ind_plus();
      }

      #
      # Handle the per-command 'dire' option.
      #

      if ($dire) {
         $dire = $self->_quote($dire);
         push @script, qq(${curr_ind}cd "$dire";);
         push @script,
           qq(${curr_ind}if [ \$? -ne 0 ] && [ \$SC_FAILED -eq 0 ]; then),
           qq(${next_ind}SC_FAILED=$cmd_num;),
           qq(${curr_ind}fi)
             if (! $simple_script);

      }

      #
      # Handle command retries.  If a command is set to do retries,
      # we'll always them, but if a command has failed with 'display'
      # mode, then we'll only do 1 iteration.
      #

      if ($retry) {
         # If a command has failed (possibly in the initialization of
         # the current command), then we want to go through the retries:
         #    0 time : if we're exiting on failure
         #    1 time : if we're displaying unrun commands
         #    N time : if we're continuing
         # If the command has not failed, then we'll go through it:
         #    N time
         my $fail_n;
         if ($failure eq 'display') {
            $fail_n = 1;
         } elsif ($exit_on_fail) {
            $fail_n = 0;
         } else {
            $fail_n = $retry;
         }

         push @script, qq(${curr_ind}if [ \$SC_FAILED -eq 0 ]; then),
                       qq(${next_ind}SC_RETRIES=$retry;),
                       qq(${curr_ind}else),
                       qq(${next_ind}SC_RETRIES=$fail_n;),
                       qq(${curr_ind}fi);

         push @script, qq(${curr_ind}SC_TRY=0;),
                       qq(${curr_ind}while [ \$SC_TRY -lt \$SC_RETRIES ]; do);
         _ind_plus();
      }

      #
      # The variable which will let us know that all alternates failed.
      #

      push @script, qq(${curr_ind}SC_ALT_FAILED=0;)
        if (! $simple_script);
      return @script;
   }

   sub _cmd_term {
      my($self,$cmd_num,%options) = @_;
      my @script;

      my $dire          = ($options{'dire'}  ? $options{'dire'} : '');
      my $flow          = ($options{'flow'}  ? $options{'flow'} : 0);
      my $retry         = ($options{'retry'} ? $options{'retry'} : 0) + 0;
      my $sleep         = ($options{'sleep'} ? $options{'sleep'} : 0) + 0;
      my $failure       = $$self{'failure'};
      my $simple_script = ($$self{'run'} eq 'dry-run'  &&  $$self{'simple'}
                           ? 1 : 0);
      $retry            = 0  if ($retry < 2  ||  $simple_script);
      my $exit_on_fail  = ($failure eq 'exit'  &&  ! $simple_script  &&  ! $flow
                           ? 1 : 0);

      #
      # Check to make sure that the command succeeded (don't check flow commands):
      #

      if (! $flow  &&  ! $simple_script) {
         push @script, qq(${curr_ind}if [ \$SC_ALT_PASSED -eq 0 ]; then),
                       qq(${next_ind}SC_ALT_FAILED=1;),
                       qq(${curr_ind}fi);
      }

      #
      # Handle command retries.
      #

      if ($retry) {
         push @script, qq(${curr_ind}if [ \$SC_ALT_FAILED -eq 0 ]; then),
                       qq(${next_ind}SC_RETRIES=0;),
                       qq(${curr_ind}fi),
                       qq(${curr_ind}SC_TRY=`expr \$SC_TRY + 1`;);

         if ($sleep) {
            push @script, qq(${curr_ind}if [ \$SC_TRY -lt \$SC_RETRIES ]; then),
                          qq(${next_ind}sleep $sleep;),
                          qq(${curr_ind}fi);
         }

         _ind_minus();
         push @script, qq(${curr_ind}done);
      }

      #
      # Go back to the correct directory if we were doing a per-command
      # directory.
      #

      if ($dire) {
         push @script, qq(${curr_ind}cd "\$SC_DIRE";);
      }

      #
      # Set the failure code if all alternates failed.
      #

      if (! $flow  &&  ! $simple_script) {
         push @script, qq(${curr_ind}if [ \$SC_ALT_FAILED -ne 0 ]; then),
                       qq(${next_ind}SC_FAILED=$cmd_num;),
                       qq(${curr_ind}fi);
      }

      #
      # If 'failure' is an exit, we wrapped this command in an if-fi block,
      # and we need to finish that block now.
      #

      if ($exit_on_fail) {
         _ind_minus();
         push(@script, qq(${curr_ind}fi));
      }

      return @script;
   }

   #####################
   # Set up a single command (i.e. alternate).

   sub _alt_init {
      my($self,$cmd,$cmd_num,$alt_num,$only,$stdout,$stderr,%options) = @_;
      my @script;

      my $simple = $$self{'simple'};
      my $flow   = ($options{'flow'}  ? $options{'flow'} : 0);

      #
      # Add some stuff to clarify the start of the command.
      #
      # If we're running it in 'script' mode, then we need to specify the
      # start of the output for this command.
      #
      # If we're just creating a script, we'll just add some comments.
      #

      if ($$self{'run'} eq 'script'  &&  ! $flow) {
         push @script, qq(${curr_ind}echo "#SC CMD $cmd_num.$alt_num";)
           if ($stdout);
         push @script, qq(${curr_ind}echo "#SC CMD $cmd_num.$alt_num" >&2;)
           if ($stderr);

      } elsif ($$self{'run'} eq 'dry-run'  &&  ! $flow  &&  ! $simple) {
         #
         # Command number comment (not for non-flow lines)
         #

         if ($only) {
            push @script,
              qq(${curr_ind}#),
              qq(${curr_ind}# Command $cmd_num),
              qq(${curr_ind}#);
         } else {
            push @script,
              qq(${curr_ind}#),
              qq(${curr_ind}# Command $cmd_num.$alt_num),
              qq(${curr_ind}#);
         }
      }

      #
      # Display the command if:
      #
      #   o  Running in 'run' or 'script' mode, after a failure
      #      with 'failure' set to 'display'
      #   o  Running in 'run' mode with 'echo' selected
      #

      $cmd = $self->_quote($cmd);
      if      ($$self{'run'}     ne 'dry-run'  &&
               $$self{'failure'} eq 'display') {
         push @script,
           qq(${curr_ind}if [ \$SC_FAILED -gt 0 ] && ) .
             qq([ "\$SC_FAILED" -lt $cmd_num ]; then),
           qq(${next_ind}echo "# COMMAND NOT RUN: $cmd";),
           qq(${curr_ind}else);
         _ind_plus();

      } elsif ($$self{'run'}  eq 'run'  &&
               $$self{'echo'} eq 'echo') {
         push @script, qq(${curr_ind}echo "# $cmd";);
      }

      return @script;
   }

   # This will finish up a command
   #
   sub _alt_term {
      my($self,%options) = @_;
      my @script;

      my $flow   = ($options{'flow'}  ? $options{'flow'} : 0);

      #
      # Make sure that the last command has included a newline when
      # running in script mode (for both STDOUT and STDERR).
      #

      if ($$self{'run'} eq 'script'  &&  ! $flow) {
         push @script, qq(${curr_ind}echo "";),
                       qq(${curr_ind}echo "" >&2;);
      }

      #
      # Running in 'run' or 'script' mode after a failure.
      #

      if      ($$self{'run'}     ne 'dry-run'  &&
               $$self{'failure'} eq 'display') {
         _ind_minus();
         push @script,qq(${curr_ind}fi);
      }

      push @script, "";

      return @script;
   }

   sub _alt_cmd {
      my($self,$cmd,$output,$first,%options) = @_;
      my(@script);

      my $check         = ($options{'check'} ? $options{'check'} : '');
      my $noredir       = ($options{'noredir'} ? 1 : 0);
      my $flow          = ($options{'flow'}  ? $options{'flow'} : 0);
      $flow             = '='  if ($flow  &&  $flow !~ /^[=+-]$/);
      my $simple_script = ($$self{'run'} eq 'dry-run'  &&  $$self{'simple'}
                           ? 1 : 0);
      $output           = ''   if ($noredir);

      # We want to generate essentially the following script:
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
      #    fi
      #
      # where CMDn is the last alternate and X is the command number.
      #
      # If we have a 'check' option, we'll need to run that
      # command immediately after every CMDi.

      if ($flow) {
         if      ($flow eq '+') {
            push @script, qq(${curr_ind}$cmd);
            _ind_plus();

         } elsif ($flow eq '-') {
            push @script, qq(${prev_ind}$cmd);
            _ind_minus();

         } else {
            push @script, qq(${prev_ind}$cmd);
         }

      } else {

         if ($first  ||  $simple_script) {
            push @script, qq(${curr_ind}SC_ALT_PASSED=0;)  if (! $simple_script);
            push @script, qq(${curr_ind}$cmd $output;);
            if ($check) {
               push @script, qq(${curr_ind}$check $output;);
            }
         } else {
            push @script,
              qq(${curr_ind}if [ \$SC_ALT_PASSED -eq 0 ]; then),
              qq(${next_ind}$cmd $output;);
            push @script,
              qq(${next_ind}$check $output;)  if ($check);
            push @script,
              qq(${curr_ind}fi);
         }

         if (! $simple_script) {
            push @script, qq(${curr_ind}if [ \$? -eq 0 ]; then),
                          qq(${next_ind}SC_ALT_PASSED=1;),
                          qq(${curr_ind}fi);
         }
      }

      return @script;
   }
}

# This analyzes the 'output' and 'f-output' options and verifies
# that they are consistent.
#
# It returns a string that will be appended to commands to send
# the output to the appropriate location.
#
sub _script_redirect {
   my($self) = @_;
   my $simple_script = ($$self{'run'} eq 'dry-run'  &&  $$self{'simple'}
                        ? 1 : 0);

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

      if ($$self{'output'} eq 'both'  ||  $simple_script) {
         # We won't add any output redirection
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
