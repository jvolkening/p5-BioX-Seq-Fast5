#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Test::More;
use FindBin;
use List::Util qw/min max/;

use BioX::Seq::Fast5 qw/:constants/;

my $DEBUG = 1;

chdir $FindBin::Bin;

use constant FN => 'test.fast5';

require_ok( "BioX::Seq::Fast5" );

# H5Fopen

ok( my $file = BioX::Seq::Fast5->new(FN), "open FAST5 file" );

ok( $file->file_version eq '0.6', "check file version" );

ok( my $read = $file->next_seq, "get first read" );

# test time calculations
ok( $read->exp_start_time eq '1503961912',
    "exp_start_time" );
ok( abs($read->read_start_time - 1503963484.5) < 0.1,
    "read_start_time" );
ok( abs($read->read_duration - 1.969) < 0.001,
    "read_duration" );

# test misc accessors
ok( $read->read_id eq '8d069286-b6ad-4185-9f74-8386bb71b78b',
    'read_id' );
ok( $read->read_number eq '1107', 'read_number' );
ok( $read->channel_number eq '316', 'channel_number' );
ok( $read->sequencing_kit eq 'sqk-lsk108', 'sequencing_kit' );
ok( $read->flowcell eq 'flo-min107', 'flowcell' );
ok( $read->run_id eq 'f54935eaa7db14eeb8cd7e5a6f5a8fd32ad282c1',
    'run_id' );
ok( $read->flowcell_id eq 'FAH24066', 'flowcell_id' );
ok( $read->basecall_software eq 'MinKNOW-Live-Basecalling', 'basecall software' );
ok( $read->basecall_version eq '1.7.14', 'basecall version' );
ok( $read->basecall_timestamp eq '2017-08-28T23:38:11Z', 'basecall timestamp' );

#sub fastq              { $_[0]->_called()->{fastq}                        }
#sub signal             { $_[0]->_raw()->{signal}                          }
ok( length($read->fastq) == 1700, "extract fastq" );
ok( my $signal = $read->signal, "extract signal" );
ok( scalar @$signal == 11863, "correct signal size" );
ok( min(@$signal) == 267 && max(@$signal) == 617, "correct signal limits" );

ok( ! $file->next_seq, "only one read" );

done_testing();

