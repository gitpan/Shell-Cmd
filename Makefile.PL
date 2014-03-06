######################################################################
# Makefile.PL for Shell::Cmd
######################################################################

use strict;
use warnings;
use 5.008;
use ExtUtils::MakeMaker 6.30;

my %module_prereq = (
   'Capture::Tiny'            => '0',
   'Net::OpenSSH'             => '0',
   'Parallel::ForkManager'    => '0',
);

my %script_prereq = (
);

my %test_prereq = (
   'IO::File'                 => '0',
   'Test::Inter'              => '0',
   'Test::More'               => '0',
);

my %config_prereq = (
   'ExtUtils::MakeMaker'      => '6.30',
);

%module_prereq = (%module_prereq,%script_prereq);
if ($ExtUtils::MakeMaker::VERSION < 6.64) {
   %config_prereq = (%config_prereq,%test_prereq);
}

WriteMakefile(
   NAME             => "Shell::Cmd",
   VERSION          => "2.00",
   ABSTRACT         => "run shell commands with enhanced support",
   LICENSE          => "perl",
   ($ExtUtils::MakeMaker::VERSION >= 6.48
    ? (MIN_PERL_VERSION => "5.008")
    : ()),
   AUTHOR           => "Sullivan Beck (sbeck\@cpan.org)",
   "dist"           => {COMPRESS=>"gzip",SUFFIX=>"gz"},
   PL_FILES         => {},
   PREREQ_PM        => \%module_prereq,
   ($ExtUtils::MakeMaker::VERSION >= 6.52
    ? (CONFIGURE_REQUIRES => \%config_prereq)
    : ()),
   ($ExtUtils::MakeMaker::VERSION >= 6.64
    ? (TEST_REQUIRES   => \%test_prereq)
    : ()),
);
