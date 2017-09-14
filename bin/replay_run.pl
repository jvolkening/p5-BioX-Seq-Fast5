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
use Cwd qw/abs_path/;

my $dir_in;
my $dir_out;
my $verbose = 0;

GetOptions(
    'in=s'    => \$dir_in,
    'out=s'   => \$dir_out,
    'verbose' => \$verbose,
);

my @fast5;

$dir_in  = abs_path( $dir_in  );
$dir_out = abs_path( $dir_out );
chdir $dir_in;

$|++;

print STDERR "Finding FAST5 files...";
find(
    { wanted => sub { push @fast5, $_ if ($_ =~ /\.fast5$/)}, no_chdir => 1 },
    '.',
);

say STDERR "found ", scalar(@fast5), " files";
print STDERR "Building run...";

my %times;

my $c = 0;

for my $fn (@fast5) {
    ++$c;
    my $perc = sprintf "%02d%%", $c/scalar(@fast5)*100;
    print STDERR "\rBuilding run...$perc completed";
    my $p = BioX::Seq::Fast5->new($fn);
    my $s = $p->read_start_time;
    my $d = $p->read_duration;
    my $e = $s + $d;
    $times{$fn} = $e;
}
print STDERR "\n";


@fast5 = sort {$times{$a} <=> $times{$b}} @fast5;

my $ref   = $times{ $fast5[0] };
my $start = time;

say STDERR "Starting run...";

for my $i (0..$#fast5) {

    my $fn = $fast5[$i];
    my $t = $times{ $fn };
    #say join "\t",
        #$fn,
        #$t,
    #;
    my ($name, $path, $suff) = fileparse($fn);
    my $new_path = join '/', $dir_out, $path;
    if (! -e $new_path) {
        #say "make_path $new_path";
        #make_path(join '/', $out_dir, $path);
    }
    my $wait = $t - $ref + $start - time;
    sleep $wait if ($wait > 0);
    say "----->copy $fn to $new_path";
    
} 
