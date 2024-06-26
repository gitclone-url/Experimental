#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use File::Basename;
use File::Spec;
use Log::Log4perl;

my $script_dir = File::Basename::dirname($0);
my $log4perl_conf = File::Spec->catfile($script_dir, "log4perl.conf");

# Load the log configuration from the file
if (-e $log4perl_conf) {
    Log::Log4perl->init($log4perl_conf);
} else {
    print STDERR "Error: Unable to find log4perl.conf file. Please ensure the file is in the same directory as the script.\n";
    exit 1;
}

my $log = Log::Log4perl->get_logger();


if (@ARGV < 1) {
    $log->error("Usage: $0 <dmesg_log_file>");
    exit 1;
}

my $dmesg_file = $ARGV[0];


$log->info("Reading dmesg log file: $dmesg_file");
open(my $fh, '<', $dmesg_file) or die "Could not open file '$dmesg_file': $!";
my @dmesg_lines = <$fh>;
close($fh);

# Analyze the dmesg log for boot issues
my $boot_issues = analyze_boot_issues(\@dmesg_lines);

my $now = `date +"%Y-%m-%d %H.%M.%S"`;
chomp($now);
my $output_file = "$dmesg_file.report_$now.txt";

open(my $out_fh, '>', $output_file) or die "Could not open file '$output_file' for writing: $!";
print $out_fh "Boot Issues Report\n";
print $out_fh "================\n\n";
print $out_fh "Generated on: $now\n\n";

foreach my $issue (@$boot_issues) {
    print $out_fh "- Type: $issue->{type}\n";
    if (ref $issue->{details} eq 'ARRAY') {
        print $out_fh "  - Details:\n";
        foreach my $detail (@{$issue->{details}}) {
            print $out_fh "    - $detail\n";
        }
    } else {
        print $out_fh "  - Details: $issue->{details}\n";
    }
    print $out_fh "\n";
}

close($out_fh);

sub analyze_boot_issues {
    my ($dmesg_lines) = @_;
    my @issues = ();

    # Check for kernel panic messages
    if (grep /Kernel panic/, @$dmesg_lines) {
        push @issues, { type => "Kernel panic", details => "Kernel panic detected" };
    }

    # Check for initramfs or init-related errors
    if (grep /initramfs|init: /, @$dmesg_lines) {
        my @initramfs_errors = grep /initramfs|init: /, @$dmesg_lines;
        push @issues, { type => "Initramfs/Init issue", details => \@initramfs_errors };
    }

    # Check for device driver errors
    if (grep /device driver/, @$dmesg_lines) {
        my @driver_errors = grep /device driver/, @$dmesg_lines;
        push @issues, { type => "Device driver issue", details => \@driver_errors };
    }

    # Check for missing firmware
    if (grep /firmware/, @$dmesg_lines) {
        my @firmware_issues = grep /firmware/, @$dmesg_lines;
        push @issues, { type => "Missing firmware", details => \@firmware_issues };
    }

    # Check for hardware-related errors
    if (grep /hardware error/, @$dmesg_lines) {
        my @hardware_errors = grep /hardware error/, @$dmesg_lines;
        push @issues, { type => "Hardware-related issue", details => \@hardware_errors };
    }

    # Check for boot time issues
    my $boot_time = get_boot_time(@$dmesg_lines);
    if (defined $boot_time && $boot_time > 60) {
        push @issues, { type => "Slow boot time", details => "$boot_time seconds" };
    } elsif (!defined $boot_time) {
        push @issues, { type => "Unable to determine boot time", details => "" };
    }

    # Check for module loading errors
    my $module_issues = check_module_issues(@$dmesg_lines);
    if (@$module_issues) {
        push @issues, { type => "Kernel module issue", details => $module_issues };
    }

    # Check for file system issues
    my $fs_issues = check_filesystem_issues(@$dmesg_lines);
    if (@$fs_issues) {
        push @issues, { type => "Filesystem issue", details => $fs_issues };
    }

    # Check for memory allocation issues
    my $memory_issues = check_memory_issues(@$dmesg_lines);
    if (@$memory_issues) {
        push @issues, { type => "Memory allocation issue", details => $memory_issues };
    }

    # Check for boot parameter issues
    my $boot_param_issues = check_boot_parameters(@$dmesg_lines);
    if (@$boot_param_issues) {
        push @issues, { type => "Boot parameter issue", details => $boot_param_issues };
    }

    # Check for ACPI issues
    my $acpi_issues = check_acpi_issues(@$dmesg_lines);
    if (@$acpi_issues) {
        push @issues, { type => "ACPI issue", details => $acpi_issues };
    }

    # Check for network interface issues
    my $network_issues = check_network_issues(@$dmesg_lines);
    if (@$network_issues) {
        push @issues, { type => "Network interface issue", details => $network_issues };
    }

    return \@issues;
}

sub get_boot_time {
    my ($dmesg_lines) = @_;
    my $boot_time;

    # Find the earliest timestamp in the dmesg log
    foreach my $line (@dmesg_lines) {
        if ($line =~ /\[([\d\.]+)\]/) {
            my $timestamp = $1;
            if (!defined $boot_time || $timestamp < $boot_time) {
                $boot_time = $timestamp;
            }
        }
    }

    return $boot_time;
}

sub check_module_issues {
    my ($dmesg_lines) = @_;
    my @issues = ();
    foreach my $line (@dmesg_lines) {
        if ($line =~ /module .* not found/) {
            push @issues, "Missing kernel module: $1";
        } elsif ($line =~ /module .* version (.+) for symbol .+ is different/) {
            push @issues, "Kernel module version mismatch: $1";
        }
    }
    return \@issues;
}

sub check_filesystem_issues {
    my ($dmesg_lines) = @_;
    my @issues = ();
    foreach my $line (@dmesg_lines) {
        if ($line =~ /ext4_lookup: deleted inode referenced: (\d+)/) {
            push @issues, "Corrupted inode: $1";
        } elsif ($line =~ /EXT4-fs \((\S+)\): error/) {
            push @issues, "Filesystem error on $1";
        } elsif ($line =~ /VFS: Can't find ext4 superblock/) {
            push @issues, "Unable to find ext4 superblock";
        }
    }
    return \@issues;
}
            
sub check_memory_issues {
    my ($dmesg_lines) = @_;
    my @issues = ();
    foreach my $line (@dmesg_lines) {
        if ($line =~ /Out of memory: Kill process (\d+) \((\w+)\) score (\d+) or sacrifice child/) {
            push @issues, "Out of memory: Killed process $2 (PID $1) with score $3";
        } elsif ($line =~ /Out of memory and no killable processes/) {
            push @issues, "Out of memory and no processes could be killed";
        }
    }
    return \@issues;
}

sub check_boot_parameters {
    my ($dmesg_lines) = @_;
    my @issues = ();
    foreach my $line (@dmesg_lines) {
        if ($line =~ /parameter '(\w+)' is obsolete, use '(\w+)'/) {
            push @issues, "Obsolete boot parameter '$1', use '$2' instead";
        } elsif ($line =~ /parameter '(\w+)' is deprecated/) {
            push @issues, "Deprecated boot parameter '$1'";
        }
    }
    return \@issues;
}

sub check_acpi_issues {
    my ($dmesg_lines) = @_;
    my @issues = ();
    foreach my $line (@dmesg_lines) {
        if ($line =~ /ACPI Error: (\[.*\]) /) {
            push @issues, "ACPI Error: $1";
        } elsif ($line =~ /ACPI Warning: (\[.*\]) /) {
            push @issues, "ACPI Warning: $1";
        } elsif ($line =~ /ACPI: (\[.*\]) /) {
            push @issues, "ACPI: $1";
        }
    }
    return \@issues;
}

sub check_network_issues {
    my ($dmesg_lines) = @_;
    my @issues = ();
    foreach my $line (@dmesg_lines) {
        if ($line =~ /(\w+): link is not ready/) {
            push @issues, "Network interface $1 link is not ready";
        } elsif ($line =~ /(\w+): NIC Link is Down/) {
            push @issues, "Network interface $1 link is down";
        } elsif ($line =~ /(\w+): failed to load driver/) {
            push @issues, "Failed to load driver for network interface $1";
        }
    }
    return \@issues;
}

# Ensure that all the issues are captured and reported
if (scalar(@$boot_issues) == 0) {
    $log->info("No boot issues found in the dmesg log file.");
} else {
    $log->info("Boot issues found and reported to $output_file");
}
