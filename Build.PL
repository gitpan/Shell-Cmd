use Module::Build;
use strict;
use warnings;

my %requires = (
                 'perl'                     => '5.008',
                 'Capture::Tiny'            => '0',
                 'Net::OpenSSH'             => '0',
                 'Parallel::ForkManager'    => '0',
               );
my %build_mods = (
                 'File::Basename'           => '0',
                 'Test::Inter'              => '0',
                 'Test::More'               => '0',
               );
my %config_mods = (
                 'Module::Build'            => '0.21',
               );


my $class = Module::Build->subclass(
   class => "Module::Build::Custom",
   code  => q { sub ACTION_html { my $self = shift ; $self->SUPER::ACTION_html ( @_ ) if ( $ENV{ MAKE_HTML } ) ; } }
);

my $build = $class->new(
        license            => 'perl',
        dist_version       => '1.10',
        dist_author        => 'Sullivan Beck <sbeck@cpan.org>',
        module_name        => 'Shell::Cmd',
        dist_abstract      => 'run shell commands with enhanced support',
        requires           => \%requires,
        build_requires     => \%build_mods,
        configure_requires => \%config_mods,
        sign               => 1,
);

$build->create_build_script;
