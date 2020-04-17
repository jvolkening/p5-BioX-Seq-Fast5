use 5.008;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'BioX::Seq::Fast5',
    AUTHOR        => q{Jeremy Volkening <jdv@base2bio.com>},
    VERSION_FROM  => 'lib/BioX/Seq/Fast5.pm',
    ABSTRACT_FROM => 'lib/BioX/Seq/Fast5.pm',
    LICENSE       => 'GPL_3',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    PREREQ_PM     => {
        'Data::HDF5' => 0, 
    },

    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url => 'https://github.com/jvolkening/p5-BioX-Seq-Fast5.git',
                web => 'https://github.com/jvolkening/p5-BioX-Seq-Fast5',
            },
        },
    },
    EXE_FILES => [qw|
        bin/f5_to_fq
    |],
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => ['BioX-Seq-Fast5-*'] },
);
