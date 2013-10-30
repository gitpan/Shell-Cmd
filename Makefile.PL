
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
        VERSION          => '1.10',
        ($] >= 5.008
        ? (ABSTRACT=>'run shell commands with enhanced support',
           AUTHOR  =>'Sullivan Beck (sbeck@cpan.org)')
        : ()),
        'dist' => {COMPRESS=>'gzip',SUFFIX=>'gz'},
        PL_FILES  => {},
        PREREQ_PM => \%requires,
);
