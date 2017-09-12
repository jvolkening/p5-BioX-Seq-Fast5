package BioX::Seq::Fast5;

use strict;
use warnings;
use 5.012;

use Carp;
use Data::Dumper;
require Exporter;

our $VERSION = '0.001';

our @ISA = qw(Exporter);

my @constants = qw/

    H5_ITER_UNKNOWN
    H5_ITER_INC
    H5_ITER_DEC
    H5_ITER_NATIVE
    H5_ITER_N

    H5_INDEX_UNKNOWN
    H5_INDEX_NAME
    H5_INDEX_CRT_ORDER
    H5_INDEX_N

    H5O_TYPE_UNKNOWN
    H5O_TYPE_GROUP
    H5O_TYPE_DATASET
    H5O_TYPE_NAMED_DATATYPE
    H5O_TYPE_NTYPES

    H5T_NATIVE_INT
    H5T_NATIVE_DOUBLE
    H5T_NATIVE_FLOAT
    H5T_NATIVE_CHAR
    H5T_VARIABLE
    H5F_ACC_TRUNC
    H5P_DEFAULT
    H5F_ACC_RDONLY
    H5F_ACC_RDWR
    H5P_FILE_CREATE
    H5P_FILE_ACCESS
    H5P_DATASET_CREATE
    H5P_DATASET_XFER
    H5P_FILE_MOUNT
    H5F_SCOPE_GLOBAL
    H5F_SCOPE_LOCAL
    H5S_UNLIMITED
    H5S_SELECT_SET
    H5T_C_S1
    H5D_FILL_TIME_ALLOC

    H5G_NTYPES
    H5G_NLIBTYPES
    H5G_NUSERTYPES
    H5G_SAME_LOC
    H5G_LINK_ERROR
    H5G_LINK_HARD
    H5G_LINK_SOFT

    H5G_UNKNOWN
    H5G_GROUP
    H5G_DATASET
    H5G_TYPE
    H5G_LINK
    H5G_UDLINK

    H5I_UNINIT
    H5I_BADID
    H5I_FILE
    H5I_GROUP
    H5I_DATATYPE
    H5I_DATASPACE
    H5I_DATASET
    H5I_ATTR
    H5I_REFERENCE
    H5I_VFL
    H5I_GENPROP_CLS
    H5I_GENPROP_LST
    H5I_ERROR_CLASS
    H5I_ERROR_MSG
    H5I_ERROR_STACK
    H5I_NTYPES

    H5D_LAYOUT_ERROR
    H5D_COMPACT
    H5D_CONTIGUOUS
    H5D_CHUNKED
    H5D_NLAYOUTS

    H5T_DIR_DEFAULT
    H5T_DIR_ASCEND
    H5T_DIR_DESCEND

    H5T_NO_CLASS
    H5T_INTEGER
    H5T_FLOAT
    H5T_TIME
    H5T_STRING
    H5T_BITFIELD
    H5T_OPAQUE
    H5T_COMPOUND
    H5T_REFERENCE
    H5T_ENUM
    H5T_VLEN
    H5T_ARRAY
    H5T_NCLASSES

    H5T_ORDER_ERROR
    H5T_ORDER_LE
    H5T_ORDER_BE
    H5T_ORDER_VAX
    H5T_ORDER_MIXED
    H5T_ORDER_NONE

    H5T_SGN_NONE
    H5T_SGN_2
/;

our %EXPORT_TAGS = (
    constants => [ @constants ],
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'constants'} } );


require XSLoader;
XSLoader::load('BioX::Seq::Fast5', $VERSION);


sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.

    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "&Data::HDF5::constant not defined" if $constname eq 'constant';
    my ($error, $val) = constant($constname);
    if ($error) { croak $error; }
    {
        no strict 'refs';
	    *$AUTOLOAD = sub { $val };
    }
    goto &$AUTOLOAD;
}

sub new {

    my ($class, $fn) = @_;

    die "$fn not found or not readable\n"
        if (! -r $fn);

    my $self = bless {fn => $fn} => $class;

    my $fid = H5Fopen($fn, &H5F_ACC_RDONLY, &H5P_DEFAULT);
    die "Failed to open HDF5 file for reading\n"
        if ($fid < 0);
    $self->{fid} = $fid;

    $self->_parse_meta;

    return $self;

}

sub DESTROY {

    my ($self) = @_;

    my $ret = H5Fclose($self->{fid});
    die "Failed to close HDF5 file\n"
        if ($ret < 0);

    return 1;

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

    #my $n = $info->{num_attrs} // die "No attribute count specified\n";

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
            if ($gp_name < 0);

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
                if ($name < 0);
            $self->{$gp_name}->{$name} = H5Aread($id)
                if ($id >= 0);
        }

    }

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
