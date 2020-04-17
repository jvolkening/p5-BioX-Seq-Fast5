package BioX::Seq::Fast5;

use strict;
use warnings;
use 5.012;

use Time::Piece;

use Data::HDF5 qw/:all/;

use BioX::Seq::Fast5::Seq;

our $VERSION = '0.002';

use constant MULTI_VERSION => 1.0;

sub new {

    my ($class, $fn) = @_;

    die "$fn not found or not readable\n"
        if (! -r $fn);

    my $self = bless {fn => $fn} => $class;

    my $fid = H5Fopen($fn, H5F_ACC_RDONLY, H5P_DEFAULT);
    die "Failed to open HDF5 file for reading\n"
        if ($fid < 0);
    $self->{fid} = $fid;

    $self->_parse_root();
    die "Failed to parse file version\n"
        if (! defined $self->file_version);

    return $self;

}

sub next_seq {

    my ($self) = @_;

    return undef
        if ($self->{_seq_iter} >= $self->{_n_seqs});

    my $iter = $self->{_seq_iter}++;

    return BioX::Seq::Fast5::Seq->new(
        fid   => $self->{fid},
        iter  => $iter,
        multi => $self->file_version >= MULTI_VERSION ? 1 : 0,
    );

}

sub DESTROY {

    my ($self) = @_;

    my $ret = H5Fclose($self->{fid});
    die "Failed to close HDF5 file\n"
        if ($ret < 0);

    return 1;

}

sub _raw {

    my ($self) = @_;
    
    $self->_parse_raw()
        if (! defined $self->{raw});

    return $self->{raw}

}

sub _called {

    my ($self) = @_;
    
    $self->_parse_called()
        if (! defined $self->{called});

    return $self->{called}

}

sub _parse_root {

    my ($self) = @_;

    $self->{_root_attr} = {};

    my $root = H5Gopen(
        $self->{fid},
        '/',
        &H5P_DEFAULT
    );

    # extract root attributes (currently only file version)
    my $info = H5Oget_info($root)
        or die "failed to get info for root group\n";
    my $n_attrs = $info->{num_attrs} // die "No attribute count specified\n";

    for my $j (0..$n_attrs-1) {

        my $id = H5Aopen_by_idx(
            $root,
            '.',
            &H5_INDEX_NAME,
            &H5_ITER_INC,
            $j,
            &H5P_DEFAULT,
            &H5P_DEFAULT
        );
        my $name = H5Aget_name($id);
        die "Failed to get attr name\n"
            if ($name lt 0);
        $self->{_root_attr}->{$name} = H5Aread($id)->[0]
            if ($id >= 0);
        H5Aclose($id);
    }

    # for newer file formats, find number of embedded reads
    if ($self->file_version >= MULTI_VERSION) {

        my $info = H5Gget_info($root)
            or die "failed to get info for meta group\n";
        my $n = $info->{nlinks} // die "No group count specified\n";

        $self->{_n_seqs} = $n;
        $self->{_seq_iter} = 0;

    }
    else {
        $self->{_n_seqs}   = 1;
        $self->{_seq_iter} = 0;
    }

    H5Gclose($root);

}

sub _parse_called {

    my ($self) = @_;

    $self->{called} = {};

    # Check if 'Analyses' group exists
    my $root = H5Gopen(
        $self->{fid},
        '/',
        &H5P_DEFAULT
    );
    my $is_called = H5Lexists(
        $root,
        "Analyses",
        &H5P_DEFAULT
    );
    $self->{is_called} = $is_called;

    # Not all FAST5 files will contain basecalling data
    if (! $self->{is_called}) {
        warn "No basecalling data in file\n";
        return;
    }

    my $gp = H5Gopen(
        $root,
        'Analyses',
        &H5P_DEFAULT
    );

    my $info = H5Gget_info($gp)
        or die "failed to get info for analyses group\n";
    my $n = $info->{nlinks} // die "No attribute count specified\n";
    die "Multiple basecalls not yet supported\n"
        if ($n > 2);

    my $basecall = 'Basecall_1D_000';
    my $found_1D = H5Lexists(
        $gp,
        $basecall,
        &H5P_DEFAULT
    );
    die "Only 1D data supported and none found\n"
        if (! $found_1D);

    my $sub_gp = H5Gopen(
        $gp,
        "$basecall/BaseCalled_template",
        &H5P_DEFAULT
    );
    die "subgroup $basecall/BaseCalled_template not found\n"
        if ($sub_gp < 0);

    my $ds_id = H5Dopen(
        $sub_gp,
        'Fastq',
        &H5P_DEFAULT,
    );
    my $fq;
    if ($ds_id >= 0) {
        $self->{called}->{fastq} = H5Dread($ds_id)->[0];
    }
    H5Dclose($ds_id);

    H5Gclose($sub_gp);
    H5Gclose($gp);
    H5Gclose($root);

}

sub _parse_raw {

    my ($self) = @_;

    my $gp = H5Gopen(
        $self->{fid},
        '/Raw/Reads',
        &H5P_DEFAULT
    );
    die "UniqueGlobalKey not found. Is this a valid FAST5 file?\n"
        if ($gp < 0);
    my $info = H5Gget_info($gp)
        or die "failed to get info for meta group\n";
    my $n = $info->{nlinks} // die "No attribute count specified\n";
    die "Exactly one read expected but no or multiple reads found\n"
        if ($n != 1);

    my $read_name = H5Lget_name_by_idx(
        $gp,
        '.',
        &H5_INDEX_NAME,
        &H5_ITER_INC,
        0,
        &H5P_DEFAULT
    );
    die "Failed to get read name\n"
        if ($read_name lt 0);

    my $sub_gp = H5Gopen(
        $gp,
        $read_name,
        &H5P_DEFAULT
    );
    die "Failed to open $read_name\n"
        if ($sub_gp < 0);

    # the path to actual data depends on whether reads are packed
    my $is_packed = H5Lexists(
        $sub_gp,
        "Signal_Pack",
        &H5P_DEFAULT
    );
    $self->{is_packed} = $is_packed;

    if ($is_packed) {
        H5Gclose($sub_gp);
        $sub_gp = H5Gopen(
            $gp,
            "$read_name/Signal_Pack",
            &H5P_DEFAULT
        );
        die "subgroup $read_name/Signal_Pack not found\n"
            if ($sub_gp < 0);
    }

    my $ds_id = H5Dopen(
        $sub_gp,
        'Signal',
        &H5P_DEFAULT,
    );
    die "Failed to find raw signal\n"
        if ($ds_id < 0);
    $self->{raw}->{signal} = H5Dread($ds_id);
    H5Dclose($ds_id);

    if ($is_packed) {
        H5Gclose($sub_gp);
        $sub_gp = H5Gopen(
            $gp,
            "$read_name/Signal_Pack/params",
            &H5P_DEFAULT
        );
    }

    $info = H5Oget_info($sub_gp)
        or die "failed to get info for meta group\n";
    my $n_attrs = $info->{num_attrs} // die "No attribute count specified\n";

    for my $j (0..$n_attrs-1) {

        my $id = H5Aopen_by_idx(
            $sub_gp,
            '.',
            &H5_INDEX_NAME,
            &H5_ITER_INC,
            $j,
            &H5P_DEFAULT,
            &H5P_DEFAULT
        );
        my $name = H5Aget_name($id);
        die "Failed to get attr name\n"
            if ($name lt 0);
        $self->{raw}->{$name} = H5Aread($id)->[0]
            if ($id >= 0);
        H5Aclose($id);
    }

    H5Gclose($sub_gp);
    H5Gclose($gp);

}

# other accessors
# TODO: make more slots available

sub file_version   { $_[0]->{_root_attr}->{file_version}              }
sub n_seqs         { $_[0]->{_n_seqs}                                 }
sub fastq          { $_[0]->_called()->{fastq}                        }
sub read_id        { $_[0]->_raw()->{read_id}                         }
sub read_number    { $_[0]->_raw()->{read_number}                     }

1;

__END__

=head1 NAME

BioX::Seq::Fast5 - Read access to Fast5 files

=head1 SYNOPSIS

  use BioX::Seq::Fast5;

=head1 ABSTRACT

Read access to Fast5 files

=head1 DESCRIPTION


=head1 SEE ALSO


=cut
