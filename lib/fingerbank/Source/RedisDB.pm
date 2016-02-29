package fingerbank::Source::RedisDB;

=head1 NAME

fingerbank::Source::TCPFingerprinting

=head1 DESCRIPTION

Source for TCPFingerprinting (p0f)

=cut

use Moose;
extends 'fingerbank::Base::Source';

use strict;
use warnings;

use fingerbank::DB;
use fingerbank::Redis;
use fingerbank::Constant qw($TRUE);
use fingerbank::Status;
use fingerbank::Util qw(is_error is_success is_enabled);
use fingerbank::Model::Device;
use fingerbank::Model::Combination;
use Data::PowerSet qw(powerset);
use Time::HiRes qw(time);

=head2 match

Check whether or not the arguments match this source

=cut

sub match {
    my ($self, $args, $other_results) = @_;

    my $start = time;

    my $logger = fingerbank::Log::get_logger;

    my $redis = fingerbank::Redis->new;
    my $connection = $redis->connection;
            
    # searching for the perfect match with the empty values
    my @sets = map{$_."-".$args->{$_}} keys(%$args);
    my @found = $connection->sinter(@sets);

    if(@found){
        $logger->info("Found perfect match ! : ".$found[0]);
        my (@infos) = $self->_buildResult($self->combination_to_device($found[0]));
        $logger->info("Took : ".(time-$start));
        return @infos;
    }

    my $failing = 1;
    my $i = scalar(@sets);
    while($failing && $i > 0){
        my $subsets = powerset({min => $i, max => $i}, @sets);
        my %found;
        foreach my $subset (@$subsets){
            my @intersections = $connection->sinter(@$subset);
            if(@intersections){
                $found{join(',',@$subset)} = \@intersections;
            }
        }
        if(keys(%found)){
            my $combinations;
            if(keys(%found) > 1){
                my @ordered = sort { @{$found{$a}} <=> @{$found{$b}} } keys(%found);
                $combinations = $found{$ordered[-1]};
            }
            else{
                $combinations = $found{[keys(%found)]->[0]};
            }
            $logger->info("The best match in found has : ".@$combinations." results in it");


#        my $big_or = join(',', @$combinations);
#        $big_or = "($big_or)";
#        my $devices_count = $db->handle->storage->dbh->selectall_hashref("select id,count(device_id) as device_count from combination where id IN $big_or group by device_id order by device_count DESC", "id");

            my $devices_count = $self->combinations_device_count(@$combinations);

            
            my $max = -1;
            my $max_device_id = undef;
            while(my ($device_id, $count) = each(%$devices_count)){
                if($count > $max){
                    $max = $count;
                    $max_device_id = $device_id;
                }
            }

            my (@infos) = $self->_buildResult($max_device_id);
            $logger->info("Took : ".(time-$start));
            return @infos;

            $failing = 0;
        }
        $i -= 1;
    }

}

sub _build_combination2device {
    my $db = fingerbank::DB->new(schema => "Upstream");
    return $db->handle->storage->dbh->selectall_hashref("select id,device_id from combination", "id");
}

sub _get_combination2device {
    my ($self) = @_;
    my $logger = fingerbank::Log::get_logger;

    my $start = time;
    if(!$self->cache->{dummy} && ( my $combination2device = $self->cache->compute("combination2device", sub { _build_combination2device() }, {expires_in => 0xffffffff} ) ) ){
        $logger->info("Deserialization took : ".(time-$start));
        return $combination2device;
    }
}

sub combination_to_device {
    my ($self, $combination_id) = @_;
    if(my $combination2device = $self->_get_combination2device()){
        return $combination2device->{$combination_id}->{device_id};
    }
    else {
        my $db = fingerbank::DB->new(schema => "Upstream");
        return fingerbank::Model::Combination->read($combination_id)->{device_id};
    }

}

sub combinations_device_count {
    my ($self, @combination_ids) = @_;

    if(my $combination2device = $self->_get_combination2device()){
        my %devices_count;
        foreach my $combination_id (@combination_ids){
            my $device_id = $combination2device->{$combination_id}->{device_id};
            $devices_count{$device_id} //= 0;
            $devices_count{$device_id} += 1;
        }
        return \%devices_count;
    }
    else {
        my $db = fingerbank::DB->new(schema => "Upstream");
        my $big_or = join(',', @combination_ids);
        $big_or = "($big_or)";
        my $devices_count = $db->handle->storage->dbh->selectall_hashref("select device_id,count(device_id) as device_count from combination where id IN $big_or group by device_id order by device_count DESC", "device_id");
        return { map { $_ => $devices_count->{$_}->{device_count} } keys(%$devices_count) };
    }
}

=head2 _buildResult

Build expected resulting output (hash) from the information p0f has returned

=cut

sub _buildResult {
    my ($self, $device_id, $combination_id) = @_;
    my $result = {};

    if(defined($combination_id)){
        my ($status, $combination) = fingerbank::Model::Combination->read($combination_id);
        return $status if ( is_error($status) );
        $result->{score} = $combination->score;
    }
    else {
        $result->{score} = 30;
    }

    # Get device info
    my ( $status, $device ) = fingerbank::Model::Device->read($device_id, $TRUE);
    return $status if ( is_error($status) );


    foreach my $key ( keys %$device ) {
        $result->{device}->{$key} = $device->{$key};
    }

    return ($fingerbank::Status::OK, $result);
}


=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2014 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

1;