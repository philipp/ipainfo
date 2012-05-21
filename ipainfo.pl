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
($outfile) = $outfile =~ m{([\w.-]+)};

my $ipadir = $options{'d'} || ".";

my $fnamefilter = qr{\.plist$};

# artistName and artistId must form a consistent mapping...
# what about vendorId?  Seems like it would, too
# artistName and playlistArtistName?  Always the same, too?
my %artist_info_found;
my @artist_cross_reference_keys = qw( artistId artistName playlistArtistName vendorId );


my @device_capabilities_expected =
  qw(
	    accelerometer
	    magnetometer
	    gyroscope

	    armv6
	    armv7

	    gamekit

	    opengles-1
	    opengles-2

	    microphone
	    still-camera
	    video-camera
	    front-facing-camera

	    telephony
	    wifi
	    peer-peer
	    gps
	    location-services
   );
my %device_capabilities_found;


# what's in softwareSupportedDeviceIds
# TODO: figure out what they each really mean, and if there are more
my %device_types = (1 => "iPhone", 2 => "iPod Touch", 4 => "iPad", 9 => "Something");

my %rating_degrees = ("Frequent/Intense" => "Lots", "Infrequent/Mild" => "Some");
my %rating_concerns =
  (
   "Alcohol, Tobacco, or Drug Use or References" => "Substance",
   "Cartoon or Fantasy Violence" => "Anvils",
   "Horror/Fear Themes" => "Scary",
   "Mature/Suggestive Themes" => "Innuendo",
   "Profanity or Crude Humor" => "Farts",
   "Realistic Violence" => "Guns",
   "Sexual Content or Nudity" => "Sex",
   "Simulated Gambling" => "Gambling"
  );

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
   #genre, genreId

   # a free-for-all, because of how I'm mangling the data
   #UIRequiredDeviceCapabilities

   appleId => qr{^[\w.]+\@[\w.]+\.\w\w+$}, # I'm hoping at this point that it's always a simple email address
   artistId => qr{^\d{9}$}, # numeric (always 9?)
   vendorId => qr{^\d+$}, # numeric

   drmVersionNumber => qr{^$}, # always empty

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
# degree: "Frequent/Intense" | "Infrequent/Mild"
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
   {
    howMany => 2,
    names =>
    [ qw(
	        genreId
	        genre
       )
    ]
   }
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
			if ($subkey eq "content") {
				for my $concern (sort keys %rating_concerns) {
					print OUTFILE "$rating_concerns{$concern}\t";
				}
			}
		}
	} elsif (defined $with_subkeys_array{$key}) {
		for my $count (1..$with_subkeys_array{$key}->{howMany}) {
			for my $subkey (sort @{$with_subkeys_array{$key}->{names}}) {
				print OUTFILE "$key-$subkey$count\t";
			}
		}
	} else {
		print OUTFILE "$key\t";
	}

	if ($key eq "softwareSupportedDeviceIds") {
		for my $device_type_key (sort keys %device_types) {
			print OUTFILE "$device_types{$device_type_key}\t";
		}
	}

	if ($key eq "UIRequiredDeviceCapabilities") {
		for my $device_capability (sort @device_capabilities_expected) {
			print OUTFILE "$device_capability\t";
		}
	}
} # end of the header row
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

	# collect all the keys in the file.  we'll delete them as we process them, and then check at the end to see if there's anything left over.
	# If there is, it represents some piece of data we don't yet know about, and therefore is falling through the cracks
	my %seen;
	for my $pkey (keys %$pdata) {
		$seen{$pkey}++;
	}

	sanity_check($pdata);

	# now loop the columns in order to emit the data row
	for my $key (sort @top_level_keys) {
		delete $seen{$key};
		if (defined $with_subkeys{$key}) {
#			print STDERR "WITH SUBKEY: $key\n";
			for my $subkey (sort @{$with_subkeys{$key}}) {
				check_and_emit($fname, $key, $pdata->{$key}->{$subkey});

				if ($subkey eq "content") {
					#my @components = split m{ , | and }, $pdata->{$key}->{$subkey};
					for my $concern (sort keys %rating_concerns) {
						my $how_much = "";
						for my $degree (sort keys %rating_degrees) {
							if ($pdata->{$key}->{$subkey} =~ m{$degree $concern}) {
								$how_much = $rating_degrees{$degree};
								last; # in principle this could skip following ones, but in practice, there should *be* only one
							}
						}
						print OUTFILE "$how_much\t";
					}
				}
			}
		} elsif (defined $with_subkeys_array{$key}) {
#			print STDERR "WITH SUBKEY ARRAY: $key\n";
			# TODO: don't just arbitrarily assume the max is 5, do something smart here
			for my $count (1..$with_subkeys_array{$key}->{howMany}) {
				for my $subkey (sort @{$with_subkeys_array{$key}->{names}}) {
					if ($pdata->{$key}[$count-1]) {
						check_and_emit($fname, $key, $pdata->{$key}[$count-1]->{$subkey});
					} else {
						check_and_emit($fname, $key, "");
					}
				}
			}
		} elsif (grep /^$key$/, @with_boolean_subkeys) {
#			print STDERR "WITH BOOLEAN SUBKEY: $key\n";
			check_and_emit($fname, $key, join ":", sort keys %{$pdata->{$key}});

			if ($key eq "UIRequiredDeviceCapabilities") {
				for my $device_capability (sort @device_capabilities_expected) {
					if (grep {$_ eq $device_capability} keys %{$pdata->{$key}}) {
						print OUTFILE "Y\t";
					} else {
						print OUTFILE "\t";
					}
				}
			}
		} elsif (grep /^$key$/, @array_keys) {
#			print STDERR "WITH ARRAY: $key\n";
			check_and_emit($fname, $key, join ":", sort @{$pdata->{$key}});

			if ($key eq "softwareSupportedDeviceIds") {
				my $keystring = join ":", "", sort(@{$pdata->{$key}}), "";
				for my $device_type_key (sort keys %device_types) {
					if ($keystring =~ m{:$device_type_key:}) {
						print OUTFILE "Y\t";
					} else {
						print OUTFILE "\t";
					}
				}
			}
		} else {
			check_and_emit($fname, $key, $pdata->{$key} || "");
		}
	} # end of the data row
	print OUTFILE "\n";

	for my $skey (sort keys %seen) {
		print STDERR "\tWe weren't expecting: $skey\n";
	}
}

close OUTFILE;

# make sure that the value conforms to what we expect for this key, and then print it out
sub check_and_emit {
	my ($fname, $key, $printvalue) = @_;

	if (defined $consistent_values{$key}) {
		if ($printvalue !~ /$consistent_values{$key}/) {
			print STDERR "NOMATCH in $fname: $key =? $printvalue\n";
		}
	}

	print OUTFILE "$printvalue\t";
}

sub sanity_check {
	my ($pdata) = @_;

	for my $device_capability_found (keys %{$pdata->{'UIRequiredDeviceCapabilities'}}) {
		$device_capabilities_found{$device_capability_found}++;
		unless (grep {$_ eq $device_capability_found} @device_capabilities_expected) {
			print STDERR "Unexpected Device Capability encountered: $device_capability_found\n";
		}
	}

	# artistName and artistId must form a consistent mapping...
	# what about vendorId?  Seems like it would, too
	# artistName and playlistArtistName?  Always the same, too?
	for my $key ( @artist_cross_reference_keys ) {
		my $info_for_key = $artist_info_found{$key}{$pdata->{$key}};
		if (defined $info_for_key) { # we've already seen this value for this key
			for my $other_key ( grep { $_ ne $key } @artist_cross_reference_keys ) {
				if ($info_for_key->{$other_key} ne $pdata->{$other_key}) {
					printf STDERR "%s %s was previously seen to match with %s %s, but now it's %s\n",
					  $key, $pdata->{$key}, $other_key, $info_for_key->{$other_key}, $pdata->{$other_key};
				}
			}
		} else { # never seen this one before, so populate it
			for my $other_key ( grep { $_ ne $key } @artist_cross_reference_keys ) {
				$artist_info_found{$key}{$pdata->{$key}}{$other_key} = $pdata->{$other_key};
			}
		}
	}
}
