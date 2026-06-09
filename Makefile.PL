use strict;
use warnings;
use ExtUtils::MakeMaker;
use File::Find;

# Install EVERYTHING under lib/ — modules AND the resources tree
# (.ep / .yml / .po / .mo / .js / .svg). EUMM's default PM detection only picks
# up .pm/.pod, so we build the PM map ourselves (the Mojolicious-style mechanism:
# ship resources under lib/Samizdat/resources/ so they land in site_perl).
my %pm;
find(
  sub {
    return unless -f;
    return if /\.(bak|orig|rej|swp)$/;
    my $path = $File::Find::name;       # e.g. lib/Samizdat/resources/templates/fortnox/index.js
    (my $rel = $path) =~ s{^lib/}{};
    $pm{$path} = "\$(INST_LIB)/$rel";
  },
  'lib',
);

WriteMakefile(
  NAME             => 'Samizdat::Plugin::Fortnox',
  VERSION          => '0.01',
  ABSTRACT         => 'Fortnox accounting integration for Samizdat',
  AUTHOR           => 'Hans Svensson <hans@alipang.se>',
  LICENSE          => 'artistic_2',
  MIN_PERL_VERSION => '5.036',
  PM               => \%pm,
  PREREQ_PM        => {
    'Mojolicious' => '9.0',
    'Hash::Merge' => 0,
    # Samizdat (core) provides Samizdat::Model::Cache + the settings resolver;
    # declared as a runtime requirement in META below (not on CPAN yet).
  },
  TEST_REQUIRES => { 'Test::More' => 0 },
  META_MERGE    => {
    'meta-spec' => { version => 2 },
    prereqs     => { runtime => { requires => { 'Samizdat' => 0 } } },
    no_index    => { directory => ['lib/Samizdat/resources'] },
    resources   => { license => ['https://dev.perl.org/licenses/artistic.html'] },
  },
  dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
  clean => { FILES => 'Samizdat-Plugin-Fortnox-*' },
);
