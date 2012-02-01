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

# Code repo: github/xocel

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
my @manpages = ();
my @symlinks = ();

my $boolreq = 0; #make slack-required, default: 0 (false)
my $fullname = ""; #full package name (package_name.txz)

#check args
if (@ARGV > 0) {
	foreach (@ARGV) {
		chomp($_);
		if (($_ eq '-h') or ($_ eq '--help')) {
			&printUsage();
		} elsif(($_ eq '-r') or ($_ eq '--required')) {
			$boolreq = 1; #true.
		} else {
			$fullname = $_;
		}
	}
} 

#begin
print "preparepkg.pl 13.37 (120201)\n";

#get input from user.
if($fullname eq ""){
	print "Enter full package name (e.g bind-9.0.0-i486-1.txz) : ";
	$fullname = <STDIN>; chomp($fullname);
} 
print "Enter short description (e.g Web Browser) : ";
my $shortdesc = <STDIN>; chomp($shortdesc);
print "Enter full description (press Ctrl+d when finished): ";

#get full description. Ctrl+d to end input so the newline character '\n' 
#doesnt end input early while pasting blocks of text.
my @input = ();
while(my $line = <STDIN>) {
	chomp($line);
	push(@input, $line);
}
my $fulldesc = join(' ', @input);

print "Enter your name : ";
my $authname = <STDIN>; chomp($authname);

#clear screen so it looks nice. 
system("clear");
print "Creating slack-desc..\n\n";

my @description = (); #package description.

#get package info from name. 
my @pkgdata = &slackpkgname($fullname);

#add template text to description.
push(@description, "# HOW TO EDIT THIS FILE:");
push(@description, "# The \"handy ruler\" below makes it easier to edit a package description. Line");
push(@description, "# up the first '|' above the ':' following the base package name, and the '|'");
push(@description, "# on the right side marks the last column you can put a character in. You must");
push(@description, "# make exactly 11 lines for the formatting to be correct. It's also");
push(@description, "# customary to leave one space after the ':'.");
push(@description, "");

#position the handy ruler.
my $handyruler = "";
for ( my $x = 0; $x < length($pkgdata[0]); $x++) {
	$handyruler .= " "; #a single space for correctly alligning the ruler.
}
$handyruler .= "|-----handy-ruler------------------------------------------------------|";
push(@description, "$handyruler");

#add first line ( [name] [ver] [short-description] ) + an empty line for formatting.
push(@description, "$pkgdata[0]: $pkgdata[0] $pkgdata[1] ($shortdesc)");
push(@description, "$pkgdata[0]:");


my $MAXLEN = 69; #max characters per line, excluding 'package_name:' ;D
my $index = 0;
my $line = "";
my $last = 6; #used for formatting. a value of 6 will result in a total number of 11 lines.

#add full description.
for (my $y = 0; $y <= $last; $y++){
	if(length($fulldesc) > $MAXLEN) {
		if($y == $last) {
			$index = rindex($fulldesc, ".", $MAXLEN) + 1;
		} else {
			$index = rindex($fulldesc, " ", $MAXLEN) + 1;
		}
		$line = substr($fulldesc, 0, $index);
		push(@description, "$pkgdata[0]: $line");
		$fulldesc = substr($fulldesc, $index);
		
	} else {
		unless($fulldesc eq "") {
			push(@description, "$pkgdata[0]: $fulldesc");
			$fulldesc = "";
		}
	}
}

#add empty line for formatting, then add last line ( Package created by [author-name] ).
push(@description, "$pkgdata[0]:");
push(@description, "$pkgdata[0]: Package created by $authname");

#add a completly empty line (end of document).
push(@description, ""); 

#create install dir.
unless( -e "$CWD/install" ) {
	mkdir("$CWD/install") or die "Permission denied\n";
}

#write description to file.
my @slackdesc = ();
tie(@slackdesc, 'Tie::File', "$CWD/install/slack-desc") or die "Permission Denied.\n";
@slackdesc = @description;
untie(@slackdesc);

#print to screen
foreach (@description) {
	if( $_ =~ m/^$pkgdata[0]:/ ) {
		print "$_\n";
	}
}

#clean up.
undef @pkgdata;
undef @description;
undef @slackdesc;

#slack-required
if($boolreq == 1) {
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
}

#gzip man pages.	
if( -e "$CWD/usr/man"){
	#need to check for and fix broken symlinks.
	find(\&findManPages,"$CWD/usr/man");
	if(@manpages > 0) {
		print("Compressing man pages.\n");
		foreach (@manpages) {
			system("gzip $_");
		}
	}
	if(@symlinks > 0) {
		#fix broken symlinks.
		my $old = "";
		my @prs = ();
		foreach (@symlinks) {
			$old = readlink($_);
			$old .= ".gz";
			@prs = fileparse($_);
			unlink($_);
			$_ = "$prs[0].gz";
			system("cd $prs[1]; ln -s $old $_");
		}
		undef @prs;
	}
	undef @manpages;
	undef @symlinks;
}

print("All operations completed successfully.\n");

sub printUsage() {
	#Prints usage then exits.
	print "Usage: preparepkg.pl [options] package_name.txz\n\n";
	print "Prepares the current and all subdirectories for makepkg by creating\n";
	print "install/slack-desc and install/slack-required. Automatically determines\n" ;
	print "required packages for slack-required. If man pages exist they will be gzipped.\n\n";
	print "options: -r, --required       Generate slack-required.\n";
	print "         -h, --help           Display usage.\n\n";
	print "If these options are not set, preparepkg.pl will prompt as appropriate.\n";
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

sub findManPages()
#File::Find wanted function, uncompressed man pages
{
	my $file = $File::Find::name;
	chomp($file);
	if (-l $file) {
		unless( $file =~ m/.gz$/) {
			push (@symlinks, $file);
		}
	} elsif (-T $file) {
		push (@manpages, $file);
	}
}
