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

ok( $file->file_version eq '0.6', "check file version" );

# test time calculations
ok( $file->exp_start_time eq '1503961912',
    "exp_start_time" );
ok( abs($file->read_start_time - 1503963484.5) < 0.1,
    "read_start_time" );
ok( abs($file->read_duration - 1.969) < 0.001,
    "read_duration" );

# test misc accessors
ok( $file->read_id eq '8d069286-b6ad-4185-9f74-8386bb71b78b',
    'read_id' );
ok( $file->read_number eq '1107', 'read_number' );
ok( $file->channel_number eq '316', 'channel_number' );
ok( $file->sequencing_kit eq 'sqk-lsk108', 'sequencing_kit' );
ok( $file->flowcell eq 'flo-min107', 'flowcell' );
ok( $file->run_id eq 'f54935eaa7db14eeb8cd7e5a6f5a8fd32ad282c1',
    'run_id' );
ok( $file->flowcell_id eq 'FAH24066', 'flowcell_id' );

done_testing();

