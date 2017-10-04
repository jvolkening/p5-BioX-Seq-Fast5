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
ok( $file->exp_start_time eq '1503961912',
    "exp_start_time" );
ok( abs($file->read_start_time - 1503963484.5) < 0.1,
    "read_start_time" );
ok( abs($file->read_duration - 1.969) < 0.001,
    "read_duration" );

done_testing();

