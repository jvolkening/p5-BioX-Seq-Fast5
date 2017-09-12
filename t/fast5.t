#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Test::More;
use FindBin;
use Data::Dumper;

use BioX::Seq::Fast5 qw/:constants/;
use Data::Dumper;

my $DEBUG = 1;

chdir $FindBin::Bin;

use constant FN => 'test.fast5';

require_ok( "BioX::Seq::Fast5" );

# H5Fopen

ok( my $file = BioX::Seq::Fast5->new(FN), "open FAST5 file" );
say Dumper $file;

done_testing();

