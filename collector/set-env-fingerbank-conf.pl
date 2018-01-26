#!/usr/bin/perl

# Allows to setup the environment of the collector based on the content of fingerbank.conf


# /usr/bin/systemctl set-environment FINGERBANK_API_KEY=$(perl -I/usr/local/fingerbank/lib -Mfingerbank::Config -e 'print fingerbank::Config->read_config ; print $fingerbank::Config::Config{upstream}->{api_key}')"

use lib '/usr/local/fingerbank/lib';
use fingerbank::Config;
use fingerbank::Log;
use Data::Dumper;

sub setenv {
    my ($variable, $value) = @_;
    system("/usr/bin/systemctl set-environment $variable=$value");
}

fingerbank::Config->read_config;

my %Config = %fingerbank::Config::Config;

my %TO_SET = (
    "FINGERBANK_API_KEY", $Config{upstream}->{api_key},,
    "COLLECTOR_DELETE_INACTIVE_ENDPOINTS", $Config{collector}->{inactive_endpoints_expiration} . "h",
    "COLLECTOR_ARP_LOOKUP", $Config{collector}->{arp_lookup},
    "COLLECTOR_QUERY_CACHE_TIME", $Config{collector}->{query_cache_time} . "m",
    "PORT", $Config{collector}->{port},
);

while(my ($k, $v) = each(%TO_SET)) {
    setenv($k, $v);
}

print "Starting with the following environment: \n";
print Dumper(\%ENV);