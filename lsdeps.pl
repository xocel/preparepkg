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
sub findLogs();
sub rmDuplicates() {
    return keys %{{ map { $_ => 1 } @_ }};
}

my $PKG = "/var/log/packages";
my $pkgname = "";
my $pkglog = "";
my @logs = ();

#open package install
find(\&findLogs, "$PKG");

#check args
if (@ARGV > 0) {
	$pkgname = $ARGV[0];
} else {
	&printUsage();
}

foreach (@logs) {
	if($_ =~ m/^$PKG\/$pkgname/) {
		$pkglog = $_;
		chomp($pkglog);
		last;
	}
}

if($pkglog eq "") {
	print "Package: $pkgname not found.\n";
	exit;
}

my @logfile = ();
my @binaries = ();

print "Detecting required packages, this may take a while..\n"; 

my @tiefile = ();
tie(@tiefile, 'Tie::File', $pkglog, mode => O_RDONLY) or die;
@logfile = @tiefile;
untie @tiefile;
foreach( @logfile) {
	$_ = "/$_";
	if( -e $_) {
		if( -x $_ ) {
			push(@binaries, $_) unless (-d $_) or (-T $_);
		}
	}
}


	#resolve required shared libraries using ldd.
my @libraries = ();
my @elements = ();
my @library = ();
my @ldd = ();

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
my @parsed = ();
@libraries = &rmDuplicates(@libraries); #remove dups
foreach (@libraries){
	if ( -l $_ ) {
		$_ = readlink($_);
	}
	#remove path.
	@parsed = fileparse($_);
	$_ = $parsed[0];
	#print "$_\n";
}


#Search for required libraries in /var/log/packages/
my @required = ();
my @pkgfile = ();
my $libcount = 0;

foreach my $package (@logs) {
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


@required = &rmDuplicates(@required); #remove dups
my $reqlen = @required;
foreach (@required) {
	#remove path
	@parsed = fileparse($_);
	$_ = $parsed[0];
	#shortname
	@parsed = &slackpkgname($_);
	$_ = $parsed[0];
	if($_ eq $pkgname) {
		$reqlen = $reqlen -1;
	}
}
@required = sort @required;
@parsed = fileparse($pkglog);
$pkglog = $parsed[0];

print "\n$pkglog requires $reqlen packages :\n\n";
foreach (@required) {
	print "$_\n" unless ($_ eq $pkgname);
}
print "\nFinished.\n";
#END

#SUBROUTINES
sub printUsage() {
	#Prints usage then exits.
	print "Usage: lsdeps.pl package_name\n";
	print "       e.g lsdeps.pl xchat\n\n" ;
	print "Lists dependencies for an installed package.\n";
	exit;
}

sub findLogs()
#File::Find wanted function, install logs
{
	my $file = $File::Find::name;
	if (-T $file) {
		chomp($file);
		push (@logs, $file) unless (-d $file) or (-B $file);
	}
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
