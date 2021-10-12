package BioX::Seq::Fast5::Seq;

use strict;
use warnings;
use 5.012;

use Time::Piece;

use Data::HDF5 qw/:all/;

our $VERSION = '0.002';

use constant MULTI_VERSION => 1.0;


sub new {

    my ($class, %args) = @_;

    my $self = bless {%args} => $class;
        #fid => $self->{fid},
        #iter => $iter,
        #multi => $self->file_version >= MULTI_VERSION ? 1 : 0,

    $self->{_cache} = {};
    $self->{_root} = '/';
    if ($self->{multi}) {
        my $root = H5Gopen(
            $self->{fid},
            '/',
            &H5P_DEFAULT
        );
        my $gp_name = H5Lget_name_by_idx(
            $root,
            '.',
            &H5_INDEX_NAME,
            &H5_ITER_INC,
            $self->{iter},
            &H5P_DEFAULT
        );

        die "Failed to get subgroup name\n"
            if ($gp_name lt 0);

        my $sub_gp = H5Gopen(
            $root,
            $gp_name,
            &H5P_DEFAULT
        );
        die "subgroup $gp_name not found\n"
            if ($sub_gp < 0);
        $self->{_root} .= $gp_name;
        H5Gclose($sub_gp);
        H5Gclose($root);
    }

    return $self;

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

sub _parse_called {

    my ($self) = @_;

    $self->{called} = {};

    # Check if 'Analyses' group exists
    my $root = H5Gopen(
        $self->{fid},
        $self->{_root},
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
        $basecall,
        &H5P_DEFAULT
    );
    die "subgroup $basecall not found\n"
        if ($sub_gp < 0);

    # parse basecalling metadata
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
        $self->{called}->{meta}->{$name} = H5Aread($id)->[0]
            if ($id >= 0);
        H5Aclose($id);
    }
    H5Gclose($sub_gp);

    # read FASTQ basecalls
    $sub_gp = H5Gopen(
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

    my $path = "$self->{_root}/Raw";
    if (! $self->{multi}) {

        $path .= "/Reads";
        my $gp = H5Gopen(
            $self->{fid},
            $path,
            &H5P_DEFAULT
        );
        die "Raw key not found. Is this a valid FAST5 file?\n"
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
        $path .= "/$read_name";
        H5Gclose($gp);

    }

    my $gp = H5Gopen(
        $self->{fid},
        $path,
        &H5P_DEFAULT
    );
    die "Failed to open $path\n"
        if ($gp < 0);

    # the path to actual data depends on whether reads are packed
    my $is_packed = H5Lexists(
        $gp,
        "Signal_Pack",
        &H5P_DEFAULT
    );
    $self->{is_packed} = $is_packed;

    if ($is_packed) {
        H5Gclose($gp);
        $gp = H5Gopen(
            $self->{fid},
            "$path/Signal_Pack",
            &H5P_DEFAULT
        );
        die "subgroup $path/Signal_Pack not found\n"
            if ($gp < 0);
    }

    my $ds_id = H5Dopen(
        $gp,
        'Signal',
        &H5P_DEFAULT,
    );
    die "Failed to find raw signal\n"
        if ($ds_id < 0);
    $self->{raw}->{signal} = H5Dread($ds_id);
    H5Dclose($ds_id);

    if ($is_packed) {
        H5Gclose($gp);
        $gp = H5Gopen(
            $self->{fid},
            "$path/Signal_Pack/params",
            &H5P_DEFAULT
        );
    }

    my $info = H5Oget_info($gp)
        or die "failed to get info for meta group\n";
    my $n_attrs = $info->{num_attrs} // die "No attribute count specified\n";

    for my $j (0..$n_attrs-1) {

        my $id = H5Aopen_by_idx(
            $gp,
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

    H5Gclose($gp);

}

sub _parse_meta {

    my ($self) = @_;

    my $path = $self->{_root};
    if (! $self->{multi}) {
        $path .= 'UniqueGlobalKey';
    }
    my $gp = H5Gopen(
        $self->{fid},
        $path,
        &H5P_DEFAULT
    );
    die "Meta root not found. Is this a valid FAST5 file?\n"
        if ($gp < 0);

    my $info = H5Gget_info($gp)
        or die "failed to get info for meta group\n";
    my $n = $info->{nlinks} // die "No attribute count specified\n";

    my %wanted = qw/
        context_tags 1
        channel_id   1
        tracking_id  1
    /;

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

        next if ( ! $wanted{$gp_name} );

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

    return $self->{_cache}->{exp_start_time}
        if (defined $self->{_cache}->{exp_start_time});

    my $t_str = $self->_meta()->{tracking_id}->{exp_start_time}
        // return undef;

    if ($t_str =~ /\D/) { # string timestamp
        my $t = Time::Piece->strptime($t_str, "%Y-%m-%dT%TZ")
            or die "Error parsing timestamp: $@\n";
        $t_str = $t->epoch;
    }
    
    $self->{_cache}->{exp_start_time} = $t_str;
    return $t_str;
        
} 

sub read_start_time {

    my ($self) = @_;

    return $self->{_cache}->{read_start_time}
        if (defined $self->{_cache}->{read_start_time});

    my $t = $self->_raw()->{start_time}
        // return undef;

    my $f = $self->_meta()->{context_tags}->{sample_frequency}
        // return undef;

    my $s = $self->exp_start_time() + $t/$f;
    
    $self->{_cache}->{read_start_time} = $s;
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

sub fastq              { $_[0]->_called()->{fastq}                        }
sub read_id            { $_[0]->_raw()->{read_id}                         }
sub read_number        { $_[0]->_raw()->{read_number}                     }
sub channel_number     { $_[0]->_meta()->{channel_id}->{channel_number}   }
sub sequencing_kit     { $_[0]->_meta()->{context_tags}->{sequencing_kit} }
sub run_id             { $_[0]->_meta()->{tracking_id}->{run_id}          }
sub flowcell_id        { $_[0]->_meta()->{tracking_id}->{flow_cell_id}    }
sub signal             { $_[0]->_raw()->{signal}                          }
sub basecall_software  { $_[0]->_called()->{meta}->{name}                 }
sub basecall_version   { $_[0]->_called()->{meta}->{version}              }
sub basecall_timestamp { $_[0]->_called()->{meta}->{time_stamp}           }
# naming changed between file versions
sub flowcell           { $_[0]->_meta()->{context_tags}->{flowcell}
    // $_[0]->_meta()->{context_tags}->{flowcell_type}
    // $_[0]->_meta()->{tracking_id}->{flow_cell_product_code}            }
sub device_type        { $_[0]->_meta()->{tracking_id}->{device_type}     }
sub device_id          { $_[0]->_meta()->{tracking_id}->{device_id}       }

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
