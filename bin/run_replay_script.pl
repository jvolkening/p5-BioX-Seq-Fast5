#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use Cwd qw/abs_path/;
use File::Copy qw/move/;
use File::Temp;
use Getopt::Long;
use IPC::Cmd qw/can_run run/;
use Time::HiRes qw/time sleep/;
use YAML::Tiny;

my $fn_in;
my $dir_out;

GetOptions(
    'in=s'    => \$fn_in,
    'out=s'   => \$dir_out,
);

$fn_in  = abs_path( $fn_in  );
$dir_out = abs_path( $dir_out );

# check for required software
my $SUBSET = can_run('fast5_subset')
    // die "fast5_subset is required but not found\n";

$|++;

my $start = time;

my $yaml = YAML::Tiny->read($fn_in)
    or die "Error reading input: $@\n";
my $config = shift @$yaml;
my $dir_in = $config->{directory}
    // die "Input file is missing directory listing on first page";

my $staging = File::Temp->newdir(CLEANUP => 1);
my $i_out = 0;

while (my $chunk = shift @$yaml) {

    my $to_emit = $chunk->{emit};
    my @ids = @{ $chunk->{reads} };
    my $batch_size = scalar @ids;

    my $tmp = File::Temp->new();
    say {$tmp} $_ for (@ids);
    close $tmp;

    my @cmd = (
        $SUBSET,
        '-i' => $dir_in,
        '-s' => $staging,
        '-l' => "$tmp",
        '-n' => $batch_size,
        '--recursive'
    );

    my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf )
        = run( command => \@cmd );
    die "Error running fast5_subset: $error_message"
        if (! $success);

    my $fn_out = "$staging/batch0.fast5";
    die "Missing temporary output\n"
        if (! -r $fn_out);
    my $fn_final = sprintf "%s/batch_%s.fast5", $dir_out, $i_out++;

    my $elapsed = time - $start;
    my $wait = $to_emit - $elapsed;
    if ($wait < 0) {
        die "Couldn't keep up with real-time speed!!!!\n";
    }
    print "Emitting $fn_final in $wait s...";
    sleep $wait;
    move $fn_out, $fn_final
        or die "Error moving $fn_out to $fn_final: $@\n";
    say "done";
}
