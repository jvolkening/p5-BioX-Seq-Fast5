#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use FindBin;
use Data::Dumper;

use BioX::Seq::Fast5 qw/:constants/;

chdir $FindBin::Bin;

use constant FN => 't/test.fast5';

while (1) {
    my $file = BioX::Seq::Fast5->new(FN);
}
