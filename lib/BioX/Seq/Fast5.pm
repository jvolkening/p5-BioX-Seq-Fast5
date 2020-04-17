package BioX::Seq::Fast5;

use strict;
use warnings;
use 5.012;

use Time::Piece;

use Data::HDF5 qw/:all/;

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

sub DESTROY {

    my ($self) = @_;

    my $ret = H5Fclose($self->{fid});
    die "Failed to close HDF5 file\n"
        if ($ret < 0);

    return 1;

}

sub _meta {

    my ($self) = @_;
    
    $self->_parse_meta()
        if (! defined $self->{meta});

    return $self->{meta}

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

        for my $i (0..$n-1) {

            my $gp_name = H5Lget_name_by_idx(
                $root,
                '.',
                &H5_INDEX_NAME,
                &H5_ITER_INC,
                $i,
                &H5P_DEFAULT
            );

            die "Failed to get group name\n"
                if ($gp_name lt 0);

            #my $sub_gp = H5Gopen(
                #$gp,
                #$gp_name,
                #&H5P_DEFAULT
            #);
            #die "subgroup $gp_name not found\n"
                #if ($sub_gp < 0);
            say $gp_name;
        }
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

    my $t_str = $self->_meta()->{tracking_id}->{exp_start_time}
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

    my $t = $self->_raw()->{start_time}
        // return undef;

    my $f = $self->_meta()->{context_tags}->{sample_frequency}
        // return undef;

    my $s = $self->exp_start_time() + $t/$f;
    
    $self->{cache}->{read_start_time} = $s;
    return $s;
        
} 

sub read_duration {

    my ($self) = @_;

    my $d = $self->_raw()->{duration}
        // return undef;
    my $f = $self->_meta()->{context_tags}->{sample_frequency}
        // return undef;
   
    return $d/$f;

}

# other accessors
# TODO: make more slots available

sub file_version   { $_[0]->{_root_attr}->{file_version}              }
sub n_seqs         { $_[0]->{_n_seqs}                                 }
sub fastq          { $_[0]->_called()->{fastq}                        }
sub read_id        { $_[0]->_raw()->{read_id}                         }
sub read_number    { $_[0]->_raw()->{read_number}                     }
sub channel_number { $_[0]->_meta()->{channel_id}->{channel_number}   }
sub sequencing_kit { $_[0]->_meta()->{context_tags}->{sequencing_kit} }
sub flowcell       { $_[0]->_meta()->{context_tags}->{flowcell}
    // $_[0]->_meta()->{content_tags}->{flowcell_type}                }
sub run_id         { $_[0]->_meta()->{tracking_id}->{run_id}          }
sub flowcell_id    { $_[0]->_meta()->{tracking_id}->{flow_cell_id}    }

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
