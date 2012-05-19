#!/usr/bin/perl -Tw

use strict;
use warnings;

use Mac::PropertyList qw(parse_plist_file);

use Getopt::Std;

my %options;
getopts( 'h?d:o:', \%options ) or show_usage();
if ( $options{'h'} or $options{'?'} ) {
	show_usage();
	exit;
}

my $outfile = $options{'o'} || "ipainfo.tsv";
my $ipadir = $options{'d'} || ".";

my $fnamefilter = qr{\.plist$};

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

# things we expect to be a certain way
my %consistent_values =
  (
   # these are completely free-form as far as I'm concerned:
   #artistName
   #copyright
   #itemName
   #playlistArtistName
   #playlistName
   #softwareVersionBundleId

   # these are probably from a limited list, but I don't know the universe of possible values
   #genre

   # a free-for-all, because of how I'm mangling the data
   #UIRequiredDeviceCapabilities

   appleId => qr{^[\w.]+\@[\w.]+\.\w\w+$}, # I'm hoping at this point that it's always a simple email address
   artistId => qr{^\d{9}$}, # numeric (always 9?)
   vendorId => qr{^\d+$}, # numeric

   bundleVersionString => qr{^[.\d]+$}, # never empty
   bundleShortVersionString => qr{^(?:[.\d]+)?$}, # can be empty

   gameCenterEverEnabled => qr{^(?:true)?$}, # empty or "true"
   gameCenterEnabled => qr{^(?:true)?$}, # empty or "true"

   genreId => qr{^\d{4}$}, # numeric
   itemId => qr{^\d{9}$}, # numeric
   kind => qr{^software$}, # always "software"
   "product-type" => qr{^ios-app$}, # always "ios-app"
   "software-type" => qr{^(?:newsstand)?$}, # this has been blank for me for everything but one
   fileExtension => qr{^\.app$}, # always ".app"

   softwareIcon57x57URL =>
   qr{
	     ^
	   http://
	   a\d+
	   \.phobos\.apple\.com
	   /us/r1000
	   /\d{3}
	   /Purple
	   (
		   (?:/[0-9a-f]{2}){3} # three 2-hex-digit subdirectories
		   /mz[il]\.[a-z]{8} # gibberish?  but it always seems to start with "mzi" or "mzl" for me
	   |
		   /v4 # I guess there's a "version 4" of this
		   (?:/[0-9a-f]{2}){3} # three 2-hex-digit subdirectories
		   /[0-9a-f]{8} # the first 6 of these match the 3 directory buckets directly ahead of this
		   (?:-[0-9a-f]{4}){3}
		   -[0-9a-f]{12}
		   /[\w-]+ # allowing any image name, whatever is in the package it seems
	   )
	   \.png
	   $
}x,
   softwareIconNeedsShine => qr{^(true|false)$}, # never blank

   softwareSupportedDeviceIds => qr{^[1249]+(?::[1249]+)*$}, # set of: 1, 2, 4, 9 (actually, I've only ever seen "1" on its own, and never "4" on its own)
   softwareVersionExternalIdentifier => qr{^\d+$}, # numeric
   softwareVersionExternalIdentifiers => qr{^\d+(?::\d+)*$}, # numeric, and the last one is always the same as: softwareVersionExternalIdentifier
   versionRestrictions => qr{^16843008$}, # I've only ever seen "16843008"

   purchaseDate => qr{^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$}, # date format
   releaseDate => qr{^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$}, # date format

#   "rating-content" => qr{^.*$}, # TODO: this is somewhat structured... analyze?
# comma-separated, "[degree] [attribute]"
# degree: "Frequent/Intense" | "Infrequent/Mild" | ???
# attribute: "Cartoon or Fantasy Violence", "Sexual Content or Nudity", "Realistic Violence", "Alcohol, Tobacco, or Drug Use or References", "Simulated Gambling", "Profanity or Crude Humor", "Mature/Suggestive Themes", "Horror/Fear Themes"
# final one (if multiple) has "and" instead of comma separation
# e.g.: "Frequent/Intense Cartoon or Fantasy Violence , Frequent/Intense Sexual Content or Nudity , Frequent/Intense Realistic Violence , Frequent/Intense Alcohol, Tobacco, or Drug Use or References , Frequent/Intense Simulated Gambling , Frequent/Intense Profanity or Crude Humor , Frequent/Intense Mature/Suggestive Themes and Frequent/Intense Horror/Fear Themes"
# e.g.: "Infrequent/Mild Mature/Suggestive Themes and Infrequent/Mild Alcohol, Tobacco, or Drug Use or References"
   "rating-label" => qr{^((4|9|12|17)\+)|Not yet rated$}, # 4+, 9+, 12+, 17+, "Not yet rated"
   "rating-rank" => qr{^[1236]000$}, # 100, 200, 300, 600
   "rating-system" => qr{^itunes-games$},

   s => qr{^\d{6}$}, # not sure what this is, but for me it's always been the same.  is it purchaser ID?
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
my @plists = grep /$fnamefilter/, readdir DIR;
closedir DIR;

open OUTFILE, ">$outfile" or die "Couldn't open '$outfile' for writing: $!";

# print the header row
print OUTFILE join "\t", qw( filename filesize accesstime lastmoddate creationdate );
print OUTFILE "\t";
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

# now loop through all the files and print a data row each
for my $fname (@plists) {
#	print STDERR "processing: $fname\n";
	my $data = parse_plist_file($fname);
	my ($ipa_fname) = $fname =~ m{(.*)\.plist$};
	my $ipa_path = "$ipadir/$ipa_fname";
#	print STDERR "IPA: $ipa_fname :: $ipa_path\n";
	if (!-f $ipa_path) {
		print STDERR "QUITTING: Couldn't find $ipa_path\n";
		exit 33;
	}
	my ($size, $atime, $mtime, $ctime) = (stat($ipa_path))[7,8,9,10];
	printf OUTFILE "%s\t%d\t%d\t%d\t%d\t", $ipa_fname, $size, $atime, $mtime, $ctime;
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
				check_and_emit($fname, $key, $pdata->{$key}->{$subkey});
			}
		} elsif (defined $with_subkeys_array{$key}) {
#			print STDERR "WITH SUBKEY ARRAY: $key\n";
			for my $count (0..4) {
				for my $subkey (sort @{$with_subkeys_array{$key}}) {
					if ($pdata->{$key}[$count]) {
						check_and_emit($fname, $key, $pdata->{$key}[$count]->{$subkey});
					} else {
						check_and_emit($fname, $key, "");
					}
				}
			}
		} elsif (grep /^$key$/, @with_boolean_subkeys) {
#			print STDERR "WITH BOOLEAN SUBKEY: $key\n";
			check_and_emit($fname, $key, join ":", sort keys %{$pdata->{$key}});
		} elsif (grep /^$key$/, @array_keys) {
#			print STDERR "WITH ARRAY: $key\n";
			check_and_emit($fname, $key, join ":", sort @{$pdata->{$key}});
		} else {
			check_and_emit($fname, $key, $pdata->{$key} || "");
		}
	}
	print OUTFILE "\n";

	for my $skey (sort keys %seen) {
		print STDERR "\tWe weren't expecting: $skey\n";
	}
}

close OUTFILE;

sub check_and_emit {
	my ($fname, $key, $printvalue) = @_;

	if (defined $consistent_values{$key}) {
		if ($printvalue !~ /$consistent_values{$key}/) {
			print STDERR "NOMATCH in $fname: $key =? $printvalue\n";
		}
	}

	print OUTFILE "$printvalue\t";
}
