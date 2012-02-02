#!/usr/bin/perl 
# Copyright 2012 xocel lox, xocellox@gmail.com
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

# Repo: https://github.com/xocel/preparepkg

use strict;
use File::Find;
use File::Basename;
use Tie::File;
use Fcntl 'O_RDONLY';

#declare subroutines.
sub printUsage();
sub slackpkgname();
sub findBinaries();
sub findPackages();
sub findManPages();
sub rmDuplicates() {
    return keys %{{ map { $_ => 1 } @_ }};
}

#declare constants.
my $CWD = `pwd`; chomp($CWD); #Current working dir. 
my $PKG = "/var/log/packages"; #install log dir.
my $LDDV = "2.13"; #ldd version.

#declare vars.
my @binaries = ();
my @packages = ();

#begin
print "mkslack-required.pl 13.37 (120201)\n";

#make slack required.
print "\nCreating slack-required..\n";
#check ldd exists and is correct version.
my @ldd = split( '\n', `ldd --version`);
unless($ldd[0] =~ m/$LDDV/){
	print "Error: preparepkg.pl requires ldd $LDDV\n";
	exit;
}
@ldd = ();

print "\nDetecting required libraries, this may take a while.. \n";

#recursivly find binaries
find(\&findBinaries,"$CWD");

#resolve required shared libraries using ldd.
my @libraries = ();
my @elements = ();
my @library = ();

foreach (@binaries) {
	@ldd = split( '\n', `ldd $_`);	
	foreach my $line (@ldd) {
		$line =~ s/\s\s/\s/; #replace duplicate spaces with a single space. 
		@elements = split('\s', $line);
		if (@elements gt 4) { 
			@library = splice(@elements, 3, (@elements-4));
			if (@library gt 1) { #name contained '\s', rejoin elements.
				$library[0] = join(' ', @library);
			}
			unless ($library[0] eq "not") { #filters out ldd errors.
				push (@libraries, $library[0]);
			}
		}
	}
}
undef @ldd;
undef @elements;
undef @library;

#resolve symlinks, remove path.
my $liblen = @libraries;

#print "\nFound $liblen required libraries.\n";
my @parsed = ();
foreach (@libraries){
	if ( -l $_ ) {
		$_ = readlink($_);
	}
	#remove path.
	@parsed = fileparse($_);
	$_ = $parsed[0];
	#print "$_\n";
}

#scan /var/log/packages.
find(\&findPackages,"$PKG");

#Search for required libraries in /var/log/packages/
my @required = ();
my @pkgfile = ();
my $libcount = 0;
foreach my $package (@packages) {
    @pkgfile = ();
	tie(@pkgfile, 'Tie::File', $package, mode => O_RDONLY) or die;
	foreach my $line (@pkgfile){
		$libcount = 0;
		@parsed = fileparse($line);
		if (($parsed[1] ne ',') and ($parsed[0] ne ',')) {
			foreach (@libraries) {
				chomp($_);
				if ( $_ eq $parsed[0] ) {
					push (@required, $package);
					splice(@libraries, $libcount, 1);
				}
				$libcount++;
			}
		}
	}
	untie @pkgfile;	
}
undef @pkgfile;

#remove any duplicates
@required = &rmDuplicates(@required); 

#get slackpkg shortname
my @slackpkg = ();

foreach (@required) {
	#remove path
	@parsed = fileparse($_);
	$_ = $parsed[0];
	#get package name
	@slackpkg = &slackpkgname($_);
	$_ = $slackpkg[0];
}
undef @slackpkg;
undef @parsed;

#Inform user of any unresolved libraries.
if (@libraries gt 0) {
	@libraries = &rmDuplicates(@libraries);
	@libraries = sort(@libraries);
	$liblen = @libraries;
	print "\nWARNING: $liblen required libraries were unable to be resolved:\n";
	foreach (@libraries) {
		print "$_\n";
	}
}
undef @libraries;

#create install dir.
unless( -e "$CWD/install" ) {
	mkdir("$CWD/install") or die "Permission denied\n";
}

#write to file.	
my @slackrequired = ();
tie(@slackrequired, 'Tie::File', "$CWD/install/slack-required") or die;
@required = sort @required;
@slackrequired = @required;
push(@slackrequired, ""); #blank line at eof.
untie @slackrequired;

my $reqlen = @required;
print "\nslack-required written with $reqlen dependancies.\n";

undef @slackrequired;
undef @required;

sub printUsage() {
	#Prints usage then exits.
	print "Usage: mkslack-required.pl\n\n";
	print "Run from package root dir. Automatically determines dependencies\n";
	print "of package and writes them to install/slack-required " ;
	exit;
}

sub slackpkgname() {
	#breaks package name up into seperate elements 
	#returns @slackpkg where $slackpkg[0] = name; and $slackpkg[1] = ver
	#no need to return arch, build or extension as none are used. 
	
	my @slackpkg = ();
	my @split = split('-', $_[0]);
	my @splice = splice(@split, 0, (@split-3));
	if (@splice gt 1) { #name contained '-', rejoin elements. 
		push(@slackpkg, join('-', @splice)); #rejoined name
	} else {
	    push(@slackpkg, $splice[0]); #name
	}
	push(@slackpkg, $split[0]); #version
	
	undef @split;
	undef @splice;
	return @slackpkg;
}

sub findBinaries()
#File::Find wanted function, binaries
{
	my $file = $File::Find::name;
	if (-x $file) {
		push (@binaries, $file) unless (-d $file) or (-T $file);
	}
}

sub findPackages()
#File::Find wanted function, install logs
{
	my $file = $File::Find::name;
	if (-T $file) {
		chomp($file);
		push (@packages, $file) unless (-d $file) or (-B $file);
	}
}


