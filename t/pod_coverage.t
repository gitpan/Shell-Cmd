#!/usr/bin/perl

#
# Test that the POD documentation is complete.
#

use strict;
use Test::More;

# Don't run tests for installs
unless ( $ENV{RELEASE_TESTING} ) {
   plan( skip_all => "Author tests not required for installation" );
}

eval "use Test::Pod::Coverage 1.00";
plan skip_all => "Test::Pod::Coverage 1.00 required for testing POD coverage"
  if $@;

all_pod_coverage_ok();
