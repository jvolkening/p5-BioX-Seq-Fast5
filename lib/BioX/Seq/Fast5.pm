package BioX::Seq::Fast5;

use strict;
use warnings;
use 5.012;

use Carp;
use Data::Dumper;
use Time::Piece;

use Data::HDF5 qw/:all/;

our $VERSION = '0.001';

sub new {

    my ($class, $fn) = @_;

    die "$fn not found or not readable\n"
        if (! -r $fn);

    my $self = bless {fn => $fn} => $class;

    my $fid = H5Fopen($fn, H5F_ACC_RDONLY, H5P_DEFAULT);
    die "Failed to open HDF5 file for reading\n"
        if ($fid < 0);
    $self->{fid} = $fid;

    $self->_parse_meta;
    $self->_parse_raw;

    return $self;

}

sub DESTROY {

    my ($self) = @_;

    my $ret = H5Fclose($self->{fid});
    die "Failed to close HDF5 file\n"
        if ($ret < 0);

    return 1;

}

sub _parse_test {

    my ($self) = @_;

    my $gp = H5Gopen(
        $self->{fid},
        "/UniqueGlobalKey",
        &H5P_DEFAULT
    );
    die "UniqueGlobalKey not found. Is this a valid FAST5 file?\n"
        if ($gp < 0);
    my $info = H5Gget_info($gp)
        or die "failed to get info for meta group\n";
    my $n = $info->{nlinks} // die "No attribute count specified\n";
#
    for my $i (0..$n-1) {
#
        my $gp_name = H5Lget_name_by_idx(
            $gp,
            '.',
            &H5_INDEX_NAME,
            &H5_ITER_INC,
            $i,
            &H5P_DEFAULT
        );
#
        die "Failed to get group name\n"
            if ($gp_name lt 0);
#
        my $sub_gp = H5Gopen(
            $gp,
            $gp_name,
            &H5P_DEFAULT
        );
        die "subgroup $gp_name not found\n"
            if ($sub_gp < 0);
        $info = H5Oget_info($sub_gp)
            or die "failed to get info for meta group\n";
        my $n2 = $info->{num_attrs} // die "No attribute count specified\n";
#
        for my $j (0..$n2-1) {
#
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
            $self->{meta}->{$gp_name}->{$name} = H5Aread($id)->[0]
                if ($id >= 0);
            H5Aclose($id);
        }
        H5Gclose($sub_gp);
#
    }
    H5Gclose($gp);

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

    # the path to actual data depends on whether reads are packed
    my $is_packed = 0;
    my $sub_gp = H5Gopen(
        $gp,
        "$read_name/Signal_Pack",
        &H5P_DEFAULT
    );
    if ($sub_gp >= 0) {
        $is_packed = 1;
    }
    else {
        H5Gclose($sub_gp);
        $sub_gp = H5Gopen(
            $gp,
            $read_name,
            &H5P_DEFAULT
        );
    }
    die "subgroup $read_name not found\n"
        if ($sub_gp < 0);
    $self->{is_packed} = $is_packed;

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

sub _parse_meta {

    my ($self) = @_;

    my $gp = H5Gopen(
        $self->{fid},
        "/UniqueGlobalKey",
        &H5P_DEFAULT
    );
    die "UniqueGlobalKey not found. Is this a valid FAST5 file?\n"
        if ($gp < 0);
    my $info = H5Gget_info($gp)
        or die "failed to get info for meta group\n";
    my $n = $info->{nlinks} // die "No attribute count specified\n";

    for my $i (0..$n-1) {

        my $gp_name = H5Lget_name_by_idx(
            $gp,
            '.',
            &H5_INDEX_NAME,
            &H5_ITER_INC,
            $i,
            &H5P_DEFAULT
        );

        die "Failed to get group name\n"
            if ($gp_name lt 0);

        my $sub_gp = H5Gopen(
            $gp,
            $gp_name,
            &H5P_DEFAULT
        );
        die "subgroup $gp_name not found\n"
            if ($sub_gp < 0);
        $info = H5Oget_info($sub_gp)
            or die "failed to get info for meta group\n";
        my $n2 = $info->{num_attrs} // die "No attribute count specified\n";

        for my $j (0..$n2-1) {

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
            $self->{meta}->{$gp_name}->{$name} = H5Aread($id)->[0]
                if ($id >= 0);
            H5Aclose($id);
        }
        H5Gclose($sub_gp);

    }
    H5Gclose($gp);

}

sub exp_start_time {

    my ($self) = @_;

    return $self->{cache}->{exp_start_time}
        if (defined $self->{cache}->{exp_start_time});

    my $t_str = $self->{meta}->{tracking_id}->{exp_start_time}
        // return undef;

    if ($t_str =~ /\D/) { # string timestamp
        my $t = Time::Piece->strptime($t_str, "%Y-%m-%dT%TZ")
            or die "Error parsing timestamp: $@\n";
        $t_str = $t->epoch;
    }
    
    $self->{cache}->{exp_start_time} = $t_str;
    return $t_str;
        
} 

sub read_start_time {

    my ($self) = @_;

    return $self->{cache}->{read_start_time}
        if (defined $self->{cache}->{read_start_time});

    my $t = $self->{raw}->{start_time}
        // return undef;

    my $f = $self->{meta}->{context_tags}->{sample_frequency}
        // return undef;

    my $s = $self->exp_start_time() + $t/$f;
    
    $self->{cache}->{read_start_time} = $s;
    return $s;
        
} 

sub read_duration {

    my ($self) = @_;

    return $self->{cache}->{read_duration}
        if (defined $self->{cache}->{read_duration});

    my $d = $self->{raw}->{duration}
        // return undef;
    my $f = $self->{meta}->{context_tags}->{sample_frequency}
        // return undef;
   
    $d = $d/$f;
    $self->{cache}->{read_duration} = $d;

    return $d;

}

1;
__END__

=head1 NAME

Data::HDF5 - Perl wrappers for HDF5 libary

=head1 SYNOPSIS

  use Data::HDF5;

=head1 ABSTRACT

Bindings to the HDF5 library 

=head1 DESCRIPTION


=head1 SEE ALSO

Documentation can found at
http://hdfgroup.org/projects/bioinformatics/bio_software.html

=cut
