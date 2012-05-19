#!/usr/bin/perl -Tw

use strict;
use warnings;

use Mac::PropertyList qw(parse_plist_file);
use Data::Dumper;

my $outfile = "zzzout.tsv";

my $extrafilter = qr{^Mag.*};
$extrafilter = qr{.};

my @top_level_keys =
  qw(
	    softwareVersionBundleId
	    artistName
	    softwareSupportedDeviceIds
	    copyright
	    artistId
	    genreId
	    rating
	    vendorId
	    kind
	    releaseDate
	    softwareIcon57x57URL
	    product-type
	    softwareVersionExternalIdentifier
	    playlistName
	    purchaseDate
	    softwareIconNeedsShine
	    appleId
	    s
	    genre
	    subgenres
	    bundleVersion
	    bundleShortVersionString
	    itemId
	    drmVersionNumber
	    playlistArtistName
	    itemName
	    softwareVersionExternalIdentifiers
	    fileExtension
	    versionRestrictions
	    UIRequiredDeviceCapabilities
	    gameCenterEnabled
	    gameCenterEverEnabled
	    software-type
   );

my %with_subkeys =
  (
   rating =>
   [
    qw(
	      system
	      content
	      label
	      rank
     )
   ]
  );

my %with_subkeys_array =
  (
   subgenres =>
   [
    qw(
	      genreId
	      genre
     )
   ]
  );

my @with_boolean_subkeys =
  qw(
	    UIRequiredDeviceCapabilities
   );

my @array_keys =
  qw(
	    softwareSupportedDeviceIds
	    softwareVersionExternalIdentifiers
   );

opendir DIR, "." or die "Whaaa? $!";
my @plists = grep /$extrafilter\.plist$/, readdir DIR;
closedir DIR;

open OUTFILE, ">$outfile" or die "Couldn't open '$outfile' for writing: $!";

print OUTFILE "filename\t";
for my $key (sort @top_level_keys) {
	if (defined $with_subkeys{$key}) {
		for my $subkey (sort @{$with_subkeys{$key}}) {
			print OUTFILE "$key-$subkey\t";
		}
	} elsif (defined $with_subkeys_array{$key}) {
		for my $count (1..5) {
			for my $subkey (sort @{$with_subkeys_array{$key}}) {
				print OUTFILE "$key-$subkey$count\t";
			}
		}
	} else {
		print OUTFILE "$key\t";
	}
}
print OUTFILE "\n";

for my $fname (@plists) {
#	print STDERR "processing: $fname\n";
	my $data = parse_plist_file($fname);
	print OUTFILE $fname, "\t";
	my $pdata = $data->as_perl;

	my %seen;
	for my $pkey (keys %$pdata) {
		$seen{$pkey}++;
	}

	for my $key (sort @top_level_keys) {
		delete $seen{$key};
		if (defined $with_subkeys{$key}) {
#			print STDERR "WITH SUBKEY: $key\n";
			for my $subkey (sort @{$with_subkeys{$key}}) {
				print OUTFILE $pdata->{$key}->{$subkey}, "\t";
			}
		} elsif (defined $with_subkeys_array{$key}) {
#			print STDERR "WITH SUBKEY ARRAY: $key\n";
			for my $count (0..4) {
				for my $subkey (sort @{$with_subkeys_array{$key}}) {
					if ($pdata->{$key}[$count]) {
						print OUTFILE $pdata->{$key}[$count]->{$subkey}, "\t";
					} else {
						print OUTFILE "\t";
					}
				}
			}
		} elsif (grep /^$key$/, @with_boolean_subkeys) {
#			print STDERR "WITH BOOLEAN SUBKEY: $key\n";
			print OUTFILE join ":", sort keys %{$pdata->{$key}};
			print OUTFILE "\t";
		} elsif (grep /^$key$/, @array_keys) {
#			print STDERR "WITH ARRAY: $key\n";
			print OUTFILE join ":", @{$pdata->{$key}};
			print OUTFILE "\t";
		} else {
			if ($pdata->{$key}) {
#				print STDERR "REGULAR: $key\n";
				print OUTFILE $pdata->{$key}, "\t";
			} else {
				print OUTFILE "\t";
			}
		}
	}
	print OUTFILE "\n";

	for my $skey (sort keys %seen) {
		print STDERR "\t$skey\n";
	}

#	print OUTFILE Dumper($pdata);
}

close OUTFILE;
