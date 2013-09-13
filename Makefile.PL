
use ExtUtils::MakeMaker;
use 5.008;
use strict;
use warnings;
my %requires = (
                 'Capture::Tiny'            => '0',
                 'Net::OpenSSH'             => '0',
                 'Parallel::ForkManager'    => '0',
                 'File::Basename'           => '0',
                 'Test::Inter'              => '0',
                 'Test::More'               => '0',
                 'ExtUtils::MakeMaker'      => '0',
               );


WriteMakefile(
        NAME             => 'Shell::Cmd',
        VERSION          => '1.00',
        ($] >= 5.008
        ? (ABSTRACT=>'run shell commands with enhanced support',
           AUTHOR  =>'Sullivan Beck (sbeck@cpan.org)')
        : ()),
        'dist' => {COMPRESS=>'gzip',SUFFIX=>'gz'},
        PL_FILES  => {},
        PREREQ_PM => \%requires,
        EXE_FILES => [
           'examples/dry-run.pl',
           'examples/ssh-parallel-script.pl',
           'examples/ssh-dry-run.pl',
           'examples/run.pl',
           'examples/dry-run-2.pl',
           'examples/ssh-parallel-run.pl',
           'examples/run-2.pl',
           'examples/ssh-run.pl',
        ],
);
