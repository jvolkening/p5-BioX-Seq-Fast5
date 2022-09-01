#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use BioX::Seq::Fast5;
use Getopt::Long;
use File::Find;
use File::Path qw/make_path/;
use File::Basename qw/fileparse/;
use Time::HiRes qw/time sleep/;
use YAML::Tiny;
use Cwd qw/abs_path/;

my $dir_in;
my $fn_out;
my $batch_size = 4000;
my $verbose = 0;

GetOptions(
    'in=s'    => \$dir_in,
    'out=s'   => \$fn_out,
    'batch_size=i' => \$batch_size,
    'verbose' => \$verbose,
);

my @fast5;

$dir_in  = abs_path( $dir_in  );
$fn_out  = abs_path( $fn_out  );
chdir $dir_in;

$|++;

print "Finding FAST5 files...";
find(
    { wanted => sub { push @fast5, $_ if ($_ =~ /\.fast5$/)}, no_chdir => 1 },
    '.',
);

say "found ", scalar(@fast5), " files";
print "Building run...";

my @reads;

my $c = 0;
my $run_id;

for my $fn (@fast5) {
    ++$c;
    my $perc = sprintf "%02d%%", $c/scalar(@fast5)*100;
    print "\rBuilding run...$perc completed";
    my $p = BioX::Seq::Fast5->new($fn);
    while (my $seq = $p->next_seq) {
        $run_id //= $seq->run_id;
        die "Multiple run IDs found. Data must be from the same run.\n"
            if ($run_id ne $seq->run_id);
        my $s = $seq->read_start_time;
        my $d = $seq->read_duration;
        my $e = ($s + $d) - $seq->exp_start_time;
        push @reads, [$e, $seq->read_id];
    }
}
print "\n";

@reads = sort {$a->[0] <=> $b->[0]} @reads;

my @curr;

my $yaml = YAML::Tiny->new({directory => $dir_in});

for my $r (@reads) {

    push @curr, $r->[1];

    if (scalar @curr == $batch_size) {
        
        my $page = {
            emit => $r->[0],
            reads => [@curr]
        };

        push @{ $yaml }, $page;

        @curr = ();

    }

}

if (scalar @curr) {
    
    my $page = {
        emit => $reads[-1]->[0],
        reads => [@curr]
    };

    push @{ $yaml }, $page;

    @curr = ();

}

$yaml->write($fn_out);
