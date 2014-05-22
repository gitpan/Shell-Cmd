package Shell::Cmd;
# Copyright (c) 2013-2014 Sullivan Beck. All rights reserved.
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
$VERSION = "2.02";

$| = 1;

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
      $$self{'mode'}      = 'run';
      $$self{'output'}    = 'both';
      $$self{'f-output'}  = 'both';
      $$self{'script'}    = '';
      $$self{'echo'}      = 'noecho';
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
   return $$self{'dire'}  if (! defined($dire));

   return $self->options("dire",$dire);
}

sub mode {
   my($self,$mode) = @_;
   return $$self{'mode'}  if (! defined($mode));

   return $self->options("mode",$mode);
}

sub env {
   my($self,@tmp) = @_;
   return @{ $$self{'env'} }  if (! @tmp);

   while (@tmp) {
      my $var = shift(@tmp);
      my $val = shift(@tmp);
      push @{ $$self{'env'} },[$var,$val];
   }
}

sub options {
   my($self,%opts) = @_;

   OPT:
   foreach my $opt (keys %opts) {

      my $val = $opts{$opt};
      $opt    = lc($opt);

      if ($opt eq 'mode') {

         if (lc($val) =~ /^(run|dry-run|script)$/) {
            $$self{$opt} = lc($val);
            next OPT;
         }

      } elsif ($opt eq 'dire') {
         $$self{$opt} = $val;
         next OPT;

      } elsif ($opt eq 'output'  ||  $opt eq 'f-output') {

         if (lc($val) =~ /^(both|merged|stdout|stderr|quiet)$/) {
            $$self{$opt} = lc($val);
            next OPT;
         }

      } elsif ($opt eq 'script') {

         if (lc($val) =~ /^(run|script|simple)$/) {
            $$self{$opt} = lc($val);
            next OPT;
         }

      } elsif ($opt eq 'echo') {

         if (lc($val) =~ /^(echo|noecho|failed)$/) {
            $$self{$opt} = lc($val);
            next OPT;
         }

      } elsif ($opt eq 'failure') {

         if (lc($val) =~ /^(exit|display|continue)$/) {
            $$self{$opt} = lc($val);
            next OPT;
         }

      } elsif ($opt =~ s/^ssh://) {
         $$self{'ssh_opts'}{$opt} = $val;
         next OPT;

      } elsif ($opt eq 'ssh_num' ||
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

   if ($$self{'mode'} eq 'dry-run') {
      $script .= "\n";
      if (wantarray) {
         return ($script);
      }
      return $script;
   }

   #
   # If it's running in real-time, do so.
   #

   if ($$self{'mode'} eq 'run') {
      system("$script");
      my $err = $?;
      if (wantarray) {
         return ($err);
      }
      return $err;
   }

   #
   # If it's running in 'script' mode, capture the output so that
   # we can parse it.
   #

   my($capt_out,$capt_err,$capt_exit);

   if      ($stdout  &&  $stderr) {
      ($capt_out,$capt_err,$capt_exit) = capture        { system( "$script" ) };
   } elsif ($stdout) {
      ($capt_out,$capt_exit)           = capture_stdout { system( "$script" ) };
   } elsif ($stderr) {
      ($capt_err,$capt_exit)           = capture_stderr { system( "$script" ) };
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

   if ($$self{'mode'} eq 'dry-run') {
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

   if ($$self{'mode'} eq 'run') {
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
   $capt_exit = $capt_exit >> 8;

   #
   # Parse the output and return it.
   #

   return $self->_script_output($capt_out,$capt_err,$capt_exit);
}

###############################################################################
###############################################################################

BEGIN {
   # Error trapping variables:
   my $sc_flow_lev = 0;   # Number of levels of flow
   my $sc_flow_err = 0;   # An error in flow was seen

   # Global options
   my $sc_run;       # How the script is run:         dry-run, run, script
   my $sc_type;      # The type of script to create:  run, script, simple
   my $sc_echo;      # If we want to echo commands:   0/1
   my $sc_fail;      # How to handle failure:         exit, display, continue
   my $sc_redir;     # String to redirect output
   my $sc_out;       # Capture STDOUT
   my $sc_err;       # Capture STDERR
   my $sc_output;    # The output option
   my $sc_foutput;   # The f-output option

   # Command options
   my $cmd_dire;     # A directory where this command runs
   my $cmd_flow;     # 1 if it is a flow command
   my $cmd_retries;  # The number of retries
   my $cmd_sleep;    # How long to sleep between retries
   my $cmd_noredir;  # 1 if this command should not be redirected
   my $cmd_check;    # The command to check success

   # Command options
   my $retries = 0;  # N if we want to retry this command N times
   my $try;          # M if this is the Mth try (1..N)

   # Variables used in scripts
   #   SC_FAILED = N    : the command which failed (0 = none, 1 = script
   #                      initialization, 2+ = command N)
   #                      Unused in simple scripts
   #   SC_DIRE          : the working directory of the script
   #   SC_RETRIES = N   : this command will run up to N times
   #   SC_TRY = N       : we're currently on the Nth try
   #   SC_CMD_PASSED    : 1 if one of the alternatives to this command ran
   #   SC_EXIT          : the current exit code
   #   SC_PREV_EXIT     : used to store the old exit code during command
   #                      retries so if a later retry succeeds, it can
   #                      roll back the exit code to whatever it was before

   # Script indentation
   my $ind_per_lev = "   ";
   my $ind_cur_lev = 0;

   my $curr_ind    = "";
   my $next_ind    = $ind_per_lev;
   my $prev_ind    = "";

   # Some hashes to make some operations cleaner
   my %keep_stdout = map { $_,1 } qw(both merged stdout);
   my %keep_stderr = map { $_,1 } qw(both stderr);
   my %succ_status = map { $_,1 } qw(succ retried);
   $succ_status{''} = 1;
   my %fail_status = map { $_,1 } qw(exit fail);

   #####################
   # This creates the script and it is ready to be printed or evaluated
   # in double quotes.
   #
   sub _script {
      my($self)  = @_;

      my @script;
      $self->_script_options();

      #
      # Handle env, dire, and output options
      #

      push @script, $self->_script_init();

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

         my @cmd         = (ref($cmd) ? @$cmd : ($cmd));
         my $alt_num     = 0;
         while (@cmd) {
            $alt_num++;
            my $first    = ($alt_num==1 ? 1 : 0);  # 1 if this is the first or only
                                                   # alternate
            my $c        = shift(@cmd);
            my $last     = (! @cmd ? 1 : 0);       # 1 if this is the last alternate

            #
            # Add the command to the script (with error handling)
            #

            push @script, $self->_alt_init($c,$cmd_num,$alt_num);
            push @script, $self->_alt_cmd($c,$cmd_num,$alt_num,$first,$last);
            push @script, $self->_alt_term();
         }

         push @script, $self->_cmd_term($cmd_num);
      }

      #
      # Form the script.
      #

      push @script, $self->_script_term();
      my $script = join("\n",@script);

      return ($script,$sc_out,$sc_err);
   }

   #####################
   # Set up the script.

   sub _script_init {
      my($self) = @_;
      my @script;

      #
      # Initialize the variable which tracks which command failed.
      #

      if ($sc_type ne 'simple') {
         push @script, qq(${curr_ind}SC_FAILED=0;),
                       qq(${curr_ind}SC_EXIT=0;);
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
            push @script, qq(${curr_ind}$var="$val";);
            push(@var,$var);
         }
         my $vars = join(' ',@var);
         push @script, qq(${curr_ind}export $vars;);
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
         if ($sc_type eq 'simple') {
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
      my @script;

      #
      # Handle the exit code.
      #

      if ($sc_type ne 'simple') {
         push @script, qq(${curr_ind}exit \$SC_EXIT;);
      }

      return @script;
   }

   #####################
   # Set up the command (which might include any number of
   # alternates).

   sub _cmd_init {
      my($self,$cmd_num,%options) = @_;
      my @script;
      $self->_cmd_options(%options);

      #
      # Check to make sure that flow is valid
      #

      if ($cmd_flow) {
         if ($cmd_flow eq '+') {
            $sc_flow_lev++;
         } elsif ($cmd_flow eq '-') {
            if ($sc_flow_lev) {
               $sc_flow_lev--;
            } else {
               $sc_flow_err = 1;
            }
         } elsif ($cmd_flow eq '=') {
            $sc_flow_err = 1  if (! $sc_flow_lev);
         }
      }

      #
      # Print out a header to clarify the start of the command.
      #

      if ($sc_type ne 'simple'  &&  ! $cmd_flow) {
         push @script,
           qq(${curr_ind}#),
           qq(${curr_ind}# Command $cmd_num),
           qq(${curr_ind}#);
      }

      #
      # If 'failure' is an exit, then we need to wrap non-flow commands
      # as:
      #
      #    if [ $SC_FAILED -eq 0 ]; then
      #       ...
      #    fi
      #
      # but flow commands are wrapped as entire blocks:
      #
      #    if [ $SC_FAILED -eq 0 ]; then
      #       flow (open)
      #          ...
      #       flow (close)
      #    fi
      #

      if ($sc_fail eq 'fail'  &&  (! $cmd_flow  ||  $cmd_flow eq '+')) {
         push @script, qq(${curr_ind}if [ \$SC_FAILED -eq 0 ]; then);
         _ind_plus();
      }

      #
      # Handle the per-command 'dire' option.
      #

      if ($cmd_dire) {
         push @script, qq(${curr_ind}cd "$cmd_dire";);
         push @script,
           qq(${curr_ind}if [ \$? -ne 0 ] && [ \$SC_FAILED -eq 0 ]; then),
           qq(${next_ind}SC_FAILED=$cmd_num;),
           qq(${curr_ind}fi)
             if ($sc_type ne 'simple');

      }

      #
      # Handle command retries.  If a command is set to do retries,
      # we'll always do them, but if a command has failed with 'display'
      # mode, then we'll only do 1 iteration.
      #

      if ($cmd_retries > 1) {
         # If a command has failed (possibly in the initialization of
         # the current command), then we want to go through the retries:
         #    0 time : if we're exiting on failure
         #    1 time : if we're displaying commands beyond a failure
         #    N time : if we're continuing
         # If the command has not failed, then we'll go through it:
         #    N time
         my $fail_n;
         if      ($sc_fail eq 'display') {
            $fail_n = 1;
         } elsif ($sc_fail eq 'exit') {
            $fail_n = 0;
         } else {  # 'continue'
            $fail_n = $cmd_retries;
         }

         push @script, qq(${curr_ind}if [ \$SC_FAILED -eq 0 ]; then),
                       qq(${next_ind}SC_RETRIES=$cmd_retries;),
                       qq(${curr_ind}else),
                       qq(${next_ind}SC_RETRIES=$fail_n;),
                       qq(${curr_ind}fi),

                       qq(${curr_ind}SC_PREV_EXIT=\$SC_EXIT;),
                       qq(${curr_ind}SC_TRY=0;),
                       qq(${curr_ind}while [ \$SC_TRY -lt \$SC_RETRIES ]; do);
         _ind_plus();
      }

      #
      # The variable which will let us know that all alternates failed.
      #

      push @script, qq(${curr_ind}SC_CMD_PASSED=0;)
        if ($sc_type ne 'simple'  &&  ! $cmd_flow);
      return @script;
   }

   sub _cmd_term {
      my($self,$cmd_num) = @_;
      my @script;

      #
      # Handle command retries.
      #

      if ($cmd_retries > 1) {
         push @script, qq(${curr_ind}if [ \$SC_CMD_PASSED -eq 1 ]; then),
                       qq(${next_ind}SC_RETRIES=0;),
                       qq(${next_ind}SC_EXIT=\$SC_PREV_EXIT;),
                       qq(${curr_ind}fi),
                       qq(${curr_ind}SC_TRY=`expr \$SC_TRY + 1`;);

         if ($cmd_sleep) {
            push @script, qq(${curr_ind}if [ \$SC_TRY -lt \$SC_RETRIES ]; then),
                          qq(${next_ind}sleep $cmd_sleep;),
                          qq(${curr_ind}fi);
         }

         _ind_minus();
         push @script, qq(${curr_ind}done);
      }

      #
      # Go back to the correct directory if we were doing a per-command
      # directory.
      #

      if ($cmd_dire) {
         push @script, qq(${curr_ind}cd "\$SC_DIRE";);
      }

      #
      # Set the failure code if the command failed.
      #

      if (! $cmd_flow  &&  $sc_type ne 'simple') {
         push @script, qq(${curr_ind}if [ \$SC_FAILED -eq 0 ] && ) .
                         qq([ \$SC_CMD_PASSED -eq 0 ]; then),
                       qq(${next_ind}SC_FAILED=$cmd_num;),
                       qq(${curr_ind}fi);
      }

      #
      # If 'failure' is an exit, then we wrapped this command in an if-fi block,
      # and we need to finish that block now.
      #

      if ($sc_fail eq 'fail'  &&  (! $cmd_flow  ||  $cmd_flow eq '-')) {
         _ind_minus();
         push(@script, qq(${curr_ind}fi));
      }

      return @script;
   }

   #####################
   # Set up a single command (i.e. alternate).

   sub _alt_init {
      my($self,$cmd,$cmd_num,$alt_num) = @_;
      my @script;

      #
      # Add some stuff to clarify the start of the command.
      #
      # If we're running it in 'script' mode, then we need to specify the
      # start of the output for this command.
      #
      # If we're just creating a script, we'll just add some comments.
      #

      if      ($sc_type eq 'script'  &&  ! $cmd_flow) {
         push @script, qq(${curr_ind}echo "#SC CMD $cmd_num.$alt_num";)
           if ($sc_out);
         push @script, qq(${curr_ind}echo "#SC CMD $cmd_num.$alt_num" >&2;)
           if ($sc_err);

         if ($cmd_retries > 1) {
            push @script, qq(${curr_ind}echo "#SC TRY \$SC_TRY";)
              if ($sc_out);
            push @script, qq(${curr_ind}echo "#SC TRY \$SC_TRY" >&2;)
              if ($sc_err);
         }

      } elsif ($sc_type eq 'run'  &&  ! $cmd_flow) {
         #
         # Command number comment (not for non-flow lines)
         #

         if ($cmd_retries > 1) {
            push @script,
              qq(${curr_ind}#),
              qq(${curr_ind}# Command $cmd_num.$alt_num  [Retry: \$SC_TRY]),
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
      #   o  After a failure with 'failure' set to 'display'
      #   o  Running in 'run' mode with 'echo' selected
      #
      # Don't do these if it's a simple script.
      #

      if ($sc_type ne 'simple') {
         $cmd = $self->_quote($cmd);
         if      ($sc_fail eq 'display') {
            push @script,
              qq(${curr_ind}if [ \$SC_FAILED -gt 0 ] && ) .
                 qq([ \$SC_FAILED -lt $cmd_num ]; then),
              qq(${next_ind}echo "# COMMAND NOT RUN:";),
              qq(${next_ind}echo "$cmd";),
              qq(${curr_ind}else);
            _ind_plus();

         } elsif ($sc_type eq 'run'  &&  $sc_echo eq 'echo') {
            push @script, qq(${curr_ind}echo "# $cmd";);
         }
      }

      return @script;
   }

   # This will finish up a command
   #
   sub _alt_term {
      my($self) = @_;
      my @script;

      #
      # Make sure that the last command has included a newline when
      # running in script mode (for both STDOUT and STDERR).
      #

      if ($sc_type eq 'script'  &&  ! $cmd_flow) {
         push @script, qq(${curr_ind}echo "";)      if ($sc_out);
         push @script, qq(${curr_ind}echo "" >&2;)  if ($sc_err);
      }

      #
      # Running in 'run' or 'script' mode after a failure (and not in
      # a simple script):
      #

      if ($sc_type ne 'simple'  &&  $sc_fail eq 'display') {
         _ind_minus();
         push @script,qq(${curr_ind}fi);
      }

      push @script, "";

      return @script;
   }

   sub _alt_cmd {
      my($self,$cmd,$cmd_num,$alt_num,$first,$last) = @_;
      my(@script);

      my $redir             = ($cmd_noredir ? '' : $sc_redir);

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

      if ($cmd_flow) {
         if      ($cmd_flow eq '+') {
            push @script, qq(${curr_ind}$cmd);
            _ind_plus();

         } elsif ($cmd_flow eq '-') {
            push @script, qq(${prev_ind}$cmd);
            _ind_minus();

         } else {
            push @script, qq(${prev_ind}$cmd);
         }

      } else {

         if ($sc_type eq 'simple') {
            # With a simple script, we want to see which commands have
            # alternates, so we'll add a begin/end to them (and only them).
            if ($first  &&  ! $last) {
               push @script, qq(${curr_ind}# COMMAND ALTERNATES);
            }
            push @script, qq(${curr_ind}$cmd;);
            if (! $first  &&  $last) {
               push @script, qq(${curr_ind}# END ALTERNATES);
            }

            # We'll also add the check, but we'll only show it once since
            # this is a simple script.
            if ($last  &&  $cmd_check) {
               push @script, qq(${curr_ind}# CHECK WITH),
                             qq(${curr_ind}$cmd_check);
            }

         } else {
            if ($sc_fail eq 'exit') {
               push @script,
                 qq(${curr_ind}if [ \$SC_CMD_PASSED -eq 0 ] && ) .
                 qq([ \$SC_FAILED -eq 0 ]; then);
            } else {
               # $sc_fail = continue
               push @script,
                 qq(${curr_ind}if [ \$SC_CMD_PASSED -eq 0 ]; then);
            }
            _ind_plus();

            push @script,
              qq(${curr_ind}$cmd $redir;);
            push @script,
              qq(${curr_ind}# CHECK WITH),
              qq(${curr_ind}$cmd_check $redir;)  if ($cmd_check);

            if      ($sc_type eq 'script') {
               push @script, qq(${curr_ind}CMD_EXIT=\$?;),
                             qq(${curr_ind}if [ \$CMD_EXIT -eq 0 ]; then),
                             qq(${next_ind}SC_CMD_PASSED=1;),
                             qq(${curr_ind}else);
               my $c = qq(echo "#SC EXIT $cmd_num.$alt_num \$CMD_EXIT");
               push @script, qq(${next_ind}${c};)      if ($sc_out);
               push @script, qq(${next_ind}${c} >&2;)  if ($sc_err);
               push @script, qq(${curr_ind}fi);

            } elsif ($sc_type eq 'run') {
               push @script, qq(${curr_ind}CMD_EXIT=\$?;),
                             qq(${curr_ind}if [ \$CMD_EXIT -eq 0 ]; then),
                             qq(${next_ind}SC_CMD_PASSED=1;),
                             qq(${curr_ind}elif [ \$SC_EXIT -eq 0 ]; then),
                             qq(${next_ind}SC_EXIT=\$CMD_EXIT;),
                             qq(${curr_ind}fi);
            }

            _ind_minus();
            push @script,
              qq(${curr_ind}fi);
         }
      }

      return @script;
   }

   #####################
   # This analyzes the options and sets some variables to determine
   # how the script behaves.
   #
   # If we're creating a simple script, ignore retries.
   #
   sub _cmd_options {
      my($self,%options) = @_;

      $cmd_dire    = ($options{'dire'}    ? $options{'dire'}    : '');
      $cmd_dire    = $self->_quote($cmd_dire);
      $cmd_flow    = ($options{'flow'}    ? $options{'flow'}    : 0);
      $cmd_retries = ($options{'retry'}   ? $options{'retry'}   : 0) + 0;
      $cmd_retries = 0  if ($sc_type eq 'simple');
      $cmd_sleep   = ($options{'sleep'}   ? $options{'sleep'}   : 0) + 0;
      $cmd_noredir = ($options{'noredir'} ? $options{'noredir'} : 0);
      $cmd_check   = ($options{'check'}   ? $options{'check'}   : '');
   }

   #####################
   # This analyzes the options and sets some variables to determine
   # how the script behaves.
   #
   sub _script_options {
      my($self) = @_;

      #
      # What type of script, and whether it runs or not.
      #

      $sc_run  = $$self{'mode'};

      if ($sc_run eq 'dry-run') {
         $sc_type = $$self{'script'};
      } else {
         $sc_type = $sc_run;
      }

      if ($sc_run eq 'run') {
         $sc_echo = $$self{'echo'};
      } else {
         $sc_echo = 0;
      }

      $sc_fail = $$self{'failure'};
      $sc_fail = 'continue'  if ($sc_type eq 'simple');

      #
      # Analyze the 'output' and 'f-output' options.
      #
      #
      # If we ever want:
      #    STDOUT -> /dev/null,  STDERR -> STDOUT:
      # use:
      #    $sc_redir = '2>&1 >/dev/null';

      $sc_output  = $$self{'output'};
      $sc_foutput = $$self{'f-output'};

      if ($sc_type eq 'run') {

         if ($sc_output eq 'both') {
            # Capturing both so no redirection
            $sc_redir = '';
            $sc_out   = 1;
            $sc_err   = 1;

         } elsif ($sc_output eq 'merged') {
            # Merged output
            $sc_redir = '2>&1';
            $sc_out   = 1;
            $sc_err   = 0;

         } elsif ($sc_output eq 'stdout') {
            # Keep STDOUT, discard STDERR
            $sc_redir = '2>/dev/null';
            $sc_out   = 1;
            $sc_err   = 0;

         } elsif ($sc_output eq 'stderr') {
            # Discard STDOUT, keep STDERR
            $sc_redir = '>/dev/null';
            $sc_out   = 0;
            $sc_err   = 1;

         } elsif ($sc_output eq 'quiet') {
            # Discard everthing
            $sc_redir = '>/dev/null 2>&1';
            $sc_out   = 0;
            $sc_err   = 0;
         }

      } elsif ($sc_type eq 'script') {

         if ($sc_output eq 'merged'  ||
             ($sc_output eq 'quiet'  &&  $sc_foutput eq 'merged')) {
            # Merged output
            $sc_redir = '2>&1';
            $sc_out   = 1;
            $sc_err   = 0;

            if ($sc_foutput eq 'both'    ||
                $sc_foutput eq 'stdout'  ||
                $sc_foutput eq 'stderr') {
               # If regular output is merged, then it cannot be
               # separate for a failed command.
               $$self{'f-output'} = 'merged';
            }

         } elsif ($sc_output eq 'quiet'  &&  $sc_foutput eq 'quiet') {
            # Discard everthing
            $sc_redir = '>/dev/null 2>&1';
            $sc_out   = 0;
            $sc_err   = 0;

         } elsif (($sc_output eq 'stdout'   ||  $sc_output eq 'quiet')  &&
                  ($sc_foutput eq 'stdout'  ||  $sc_foutput eq 'quiet')) {
            # We only need STDOUT
            $sc_redir = '2>/dev/null';
            $sc_out   = 1;
            $sc_err   = 0;

         } elsif (($sc_output eq 'stderr'   ||  $sc_output eq 'quiet')  &&
                  ($sc_foutput eq 'stderr'  ||  $sc_foutput eq 'quiet')) {
            # We only need STDERR
            $sc_redir = '>/dev/null';
            $sc_out   = 0;
            $sc_err   = 1;

         } else {
            # Keep both.
            $sc_redir = '';
            $sc_out   = 1;
            $sc_err   = 1;

            if ($sc_foutput eq 'merged') {
               # We can't support merged output on a failed
               # command since it hasn't been merged, so we'll
               # just do the next best thing.
               $$self{'f-output'} = 'both';
            }
         }

      } else {   # $sc_type eq 'simple'

         $sc_redir = '';
         $sc_out   = 1;
         $sc_err   = 1;

      }
   }

   #####################
   # The stdout/stderr from a script-mode run are each of the form:
   #     #SC CMD N1.A1
   #     ...
   #     #SC CMD N2.A2
   #     ...
   # where N* are the command number and A* are the alternate number.
   #
   # Both may have:
   #     #SC EXIT N1.A1 EXIT_VALUE
   #
   sub _script_output {
      my($self,$out,$err,$exit) = @_;
      $out    = ''  if (! defined $out);
      $err    = ''  if (! defined $err);
      my @out = split(/\n/,$out);
      my @err = split(/\n/,$err);

      #
      # Parse stdout and stderr and turn it into:
      #
      #   ( [ CMD_NUM_1, ALT_NUM_1, TRY_1, EXIT_1, STDOUT_1, STDERR_1 ],
      #     [ CMD_NUM_2, ALT_NUM_2, TRY_2, EXIT_2, STDOUT_2, STDERR_2 ], ... )
      #

      my @cmd;

      PARSE_LOOP:
      while (@out  ||  @err) {

         #
         # Get STDOUT/STDERR for the one command.
         #

         my($cmd_num,$alt_num,$cmd_exit,$cmd_try,$tmp);
         my($out_hdr,@stdout);
         my($err_hdr,@stderr);
         $cmd_exit = 0;
         $cmd_try  = 0;

         # STDOUT

         if (@out) {
            $out_hdr = shift(@out);

            # If there is any STDOUT, it MUST start with a header:
            #    #SC CMD X.Y
            #
            if ($out_hdr !~ /^\#SC CMD (\d+)\.(\d+)$/) {
               # Invalid output... should never happen
               $self->_print(1,"Missing command header in STDOUT: $out_hdr");
               return ();
            }

            ($cmd_num,$alt_num) = ($1,$2);

            while (@out  &&  $out[0] !~ /^\#SC CMD (\d+)\.(\d+)$/) {
               if      ($out[0] =~ /^\#SC_TRY (\d+)$/) {
                  $cmd_try = $1;
                  shift(@out);

               } elsif ($out[0] =~ /^\#SC EXIT $cmd_num\.$alt_num (\d+)$/) {
                  $cmd_exit = $1;
                  shift(@out);

               } else {
                  push(@stdout,shift(@out));
               }
            }
         }

         # STDERR

         if (@err) {
            $err_hdr = shift(@err);

            # If there is any STDERR, it MUST start with a header:
            #    #SC CMD X.Y
            #
            if ($err_hdr !~ /^\#SC CMD (\d+)\.(\d+)$/) {
               # Invalid output... should never happen
               $self->_print(1,"Missing command header in STDERR: $err_hdr");
               return ();
            }

            ($cmd_num,$alt_num) = ($1,$2);

            # If there was any STDOUT, then the command headers must be
            # identical.
            #
            if ($out_hdr  &&  $err_hdr ne $out_hdr) {
               # Mismatched headers... should never happen
               $self->_print(1,"Mismatched header in STDERR: $err_hdr");
               return ();
            }

            while (@err  &&  $err[0] !~ /^\#SC CMD (\d+)\.(\d+)$/) {
               if      ($err[0] =~ /^\#SC_TRY (\d+)$/) {
                  $tmp = $1;
                  shift(@err);
                  if ($out_hdr  &&  $tmp != $cmd_try) {
                     # Mismatched try number... should never happen
                     $self->_print(1,"Mismatched try number in STDERR: $err_hdr");
                     return ();
                  }
                  $cmd_try = $tmp;

               } elsif ($err[0] =~ /^\#SC EXIT $cmd_num\.$alt_num (\d+)$/) {
                  $tmp = $1;
                  shift(@err);
                  if ($out_hdr  &&  $tmp != $cmd_exit) {
                     # Mismatched exit codes... should never happen
                     $self->_print(1,"Mismatched exit codes in STDERR: $err_hdr");
                     return ();
                  }
                  $cmd_exit = $tmp;

               } else {
                  push(@stderr,shift(@err));
               }
            }
         }

         push (@cmd, [ $cmd_num,$alt_num,$cmd_try,$cmd_exit, \@stdout, \@stderr]);
      }

      #
      # Now go through this list and group all alternates together and determine
      # the status for each command.
      #
      # When looking at the I'th status list, we also have to take into account
      # the J'th (J=I+1) list:
      #
      #   I            J
      #   CMD ALT TRY  CMD ALT TRY
      #
      #   *   *   *    *   1   0/1     The current command determines status.
      #                                It will be '', succ, exit, fail, or disp.
      #
      #   C   A   T    C   A+1 T       The next command is another alternate.
      #                                Check it for status.
      #
      #   C   A   T    C   1   T+1     This command failed, but we will retry.
      #                                Status = 'retried'.
      #
      #   Everthing else is an error
      #

      my $failed = ($exit == 1 ? -1 : 0);
      my @ret    = ($failed);
      my @curr   = (0,undef);

      STATUS_LOOP:
      foreach (my $i = 0; $i < @cmd; $i++) {

         #
         # Get the values of current and next command, alt, and try
         # numbers.
         #

         my($curr_cmd_num,$curr_alt_num,$curr_try_num,
            $curr_exit,$curr_out,$curr_err) = @{ $cmd[$i] };

         my $next_cmd     = (defined $cmd[$i+1] ? 1 : 0);

         my($next_cmd_num,$next_alt_num,$next_try_num) =
           ($next_cmd ? @{ $cmd[$i+1] } : (0,1,0));

         #
         # Get the command that was actually run.
         #

         my $tmp  = $$self{'cmd'}[$curr_cmd_num-2][0];
         my @cmd  = (ref($tmp) ? @$tmp : ($tmp));
         my $c    = $cmd[$curr_alt_num-1];

         #
         # If this is the last alternate in a command that is not
         # being retried, we'll use this to determined the status.
         #
         # Status will be '', succ, or disp if it succeeds, or exit or
         # fail if it does not succeed.
         #

         if ($next_alt_num == 1  &&
             $next_try_num <= 1) {

            $curr[0] = $curr_cmd_num;
            push(@curr,[$c,$curr_exit,$curr_out,$curr_err]);

            if ($curr_exit) {
               if ($failed) {
                  $curr[1] = 'fail';
               } else {
                  $curr[1] = 'exit';
                  $curr[0] = $i+1;
               }

            } else {
               if (! $failed) {
                  $curr[1] = '';
               } elsif ($sc_fail eq 'display') {
                  $curr[1] = 'disp';
               } else {
                  $curr[1] = 'succ';
               }
            }

            push(@ret,[@curr]);
            @curr = (0,undef);

            next STATUS_LOOP;
         }

         #
         # If the next command is another alternate, we'll need to check
         # it for the status.
         #

         if ($next_cmd_num == $curr_cmd_num  &&
             $next_alt_num == ($curr_alt_num + 1)  &&
             $next_try_num == $curr_try_num) {

            push(@curr,[$c,$curr_exit,$curr_out,$curr_err]);
            next STATUS_LOOP;
         }

         #
         # If this command failed, but we will retry it, the status will
         # be 'retried'.
         #

         if ($next_cmd_num == $curr_cmd_num  &&
             $next_alt_num == 1  &&
             $next_try_num == ($curr_try_num+1)) {

            push(@curr,[$c,$curr_exit,$curr_out,$curr_err]);
            $curr[1] = 'retried';

            push(@ret,[@curr]);
            @curr = (0,undef);

            next STATUS_LOOP;
         }

         #
         # Everything else is an error in the output.
         #

         $self->_print(1,"Unexpected error in output: $i " .
                         "[$curr_cmd_num,$curr_alt_num,$curr_try_num] " .
                         "[$next_cmd_num,$next_alt_num,$next_try_num]");
         return ();
      }

      #
      # Do some final cleanup of the output including:
      #    discard STDOUT/STDERR based on output/f-output
      #    strip leading/trailing blank lines from STDOUT/STDERR if being kept
      #

      for (my $c = 1; $c <= $#ret; $c++) {
         my $status = $ret[$c][1];
         for (my $a = 2; $a <= $#{ $ret[$c] }; $a++) {
            my $out = $ret[$c][$a][2];
            my $err = $ret[$c][$a][3];

            # Keep STDOUT if:
            #    command succeded and output = both/merged/stdout
            #    command failed and f-output = both/merged/stdout
            #
            # Similar for STDERR.

            if ( (exists $succ_status{$status}  &&
                  exists $keep_stdout{$sc_output})  ||
                 (exists $fail_status{$status}  &&
                  exists $keep_stdout{$sc_foutput}) ) {

               my @tmp = @$out;
               while (@tmp  &&  $tmp[0] eq '') {
                  shift(@tmp);
               }
               while (@tmp  &&  $tmp[$#tmp] eq '') {
                  pop(@tmp);
               }
               $out = [@tmp];

            } else {
               $out = [];
            }

            if ( (exists $succ_status{$status}  &&
                  exists $keep_stderr{$sc_output})  ||
                 (exists $fail_status{$status}  &&
                  exists $keep_stderr{$sc_foutput}) ) {

               my @tmp = @$err;
               while (@tmp  &&  $tmp[0] eq '') {
                  shift(@tmp);
               }
               while (@tmp  &&  $tmp[$#tmp] eq '') {
                  pop(@tmp);
               }
               $err = [@tmp];

            } else {
               $err = [];
            }

            $ret[$c][$a][2] = $out;
            $ret[$c][$a][3] = $err;
         }
      }

      return @ret;
   }

   #####################
   # Script indentation

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
