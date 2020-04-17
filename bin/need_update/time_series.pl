#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use autodie;
use BioX::Seq::Stream;
use BioX::Seq::Fast5;
use Cwd qw/abs_path/;
use File::Basename qw/basename/;
use File::Find;
use Getopt::Long;
use Term::ANSIColor;

my $in_dir;
my $in_fq;
my $out_dir = '.';
my @durations; # in minutes

GetOptions(
    'in_dir=s'    => \$in_dir,
    'in_fq=s'     => \$in_fq,
    'durations=s' => \@durations,
    'out_dir=s'   => \$out_dir,
);

# allow durations to be specified separately or as comma-joined string
@durations = split ',', join(',', @durations);

# set up output directories and output fastq filehandles
my %fhs;
for my $d (@durations) {
    my $tgt = "$out_dir/$d";
    die "$tgt exists and won't overwrite"
        if (-e $tgt);
    mkdir $tgt;
    mkdir "$tgt/fast5";
    if (defined $in_fq) {
        open my $fh, '>', "$tgt/reads.fq";
        $fhs{$d} = $fh;
    }
}

my $n_parsed = 0;
my %counts;
my %want;

# recurse over FAST5 files
find( {
    wanted => \&wanted,
    no_chdir => 1,
}, $in_dir );

# write FASTQ output if asked
if (defined $in_fq) {

    my $p = BioX::Seq::Stream->new($in_fq);

    while (my $seq = $p->next_seq) {
        for my $tgt ( keys %{$want{$seq->id}} ) {
            print {$fhs{$tgt}} $seq->as_fastq;
        }
    }

}


sub wanted {

    # skip non-FAST5 files
    return if (! -f $_);
    return if ($_ !~ /\.fast5$/);

    my $read = BioX::Seq::Fast5->new($_)
        or die "Error reading FAST5 file $_: $@\n";

    # print status messages
    ++$n_parsed;
    if (($n_parsed % 1000) == 0) {
        my $cnts = join ", ",
            (map {"$_:$counts{$_}"} sort {$a <=> $b} keys %counts);
        if (-t STDOUT) {
            print "Parsed ";
            print colored($n_parsed, 'bold green');
            print " ($cnts)\r";
        }
        else {
            print "Parsed $n_parsed ($cnts)\n";
        }
    }

    my $id = $read->read_id;

    # in minutes
    my $elapsed = ($read->read_start_time - $read->exp_start_time) / 60;

    for my $d (@durations) {
        
        next if ($elapsed > $d);

        my $fn_out = "$out_dir/$d/fast5/" . basename($_);
        symlink abs_path($_), $fn_out;
        ++$counts{$d};

        $want{$id}->{$d} = 1;

    }

}

