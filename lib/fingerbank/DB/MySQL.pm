package fingerbank::DB::MySQL;

=head1 NAME

fingerbank::DB::MySQL

=head1 DESCRIPTION

Databases related interaction class

=cut

use Moose;

extends 'fingerbank::DB';

use fingerbank::Log;
use fingerbank::Util qw(is_error is_success);
use fingerbank::Status;
use fingerbank::FilePath qw($INSTALL_PATH);
use fingerbank::Config;
use fingerbank::Constant qw($UPSTREAM_SCHEMA);

has 'username'         => (is => 'rw');
has 'password'         => (is => 'rw');
has 'host'             => (is => 'rw');
has 'port'             => (is => 'rw');
has 'database'         => (is => 'rw');
has 'incrementals_url' => (is => 'rw');

our @schemas = ($UPSTREAM_SCHEMA);

our %_HANDLES = ();

=head1 METHODS

=head2 _build_handle

Build the database handle

=cut

sub build_handle {
    my ( $self ) = @_;
    my $logger = fingerbank::Log::get_logger;

    my $schema = $self->{schema};

    $logger->trace("Requesting schema '$schema' DB handle");

    # Check if the requested schema is a valid one
    my %schemas = map { $_ => 1 } @schemas;
    if ( !exists($schemas{$schema}) ) {
        $self->status_code($fingerbank::Status::INTERNAL_SERVER_ERROR);
        $self->status_msg("Requested schema '$schema' does not exists");
        $logger->warn($self->status_msg);
        return;
    }

    $self->status_code($fingerbank::Status::OK);
    # Returning the requested schema db handle
    my $handle = "fingerbank::Schema::$schema"->connect("dbi:mysql:database=".$self->database.";host=".$self->host.";port=".$self->port, $self->username, $self->password, { RaiseError => 0, PrintError => 0, mysql_auto_reconnect => 1, unsafe => 1 } );
    
    $_HANDLES{$schema} = { handle => $handle };

    return $handle;
}

=head2 initialize_from_sqlite

Initialize the database from an SQLite dump and activate MySQL as the backend

=cut

sub initialize_from_sqlite {
    my ($self, $from_file) = @_;
    die("Missing or inexisting source SQLite file") unless(defined($from_file) && -f $from_file);

    my $mysql_cli = $self->_mysql_cli;
    my $database = $self->database;
    print `$mysql_cli -e 'drop database $database'`;
    print `$mysql_cli -e 'create database $database'`;
    my $result = `sqlite3 $from_file .dump 2>&1 | python $INSTALL_PATH/db/sqlite3-to-mysql.py 2>&1 | $mysql_cli $database 2>&1`;
    if($? == 0) {
        fingerbank::Config::write_config({ mysql => { state => 'enabled' } });
        fingerbank::Util::fix_permissions();
        return ($fingerbank::Status::OK, "Imported $from_file to $database successfully.");
    }
    else {
        return ($fingerbank::Status::INTERNAL_SERVER_ERROR, "Output of the import : $result");
    }
}

=head2 _mysql_cli

Helper to get a MySQL CLI command with the proper arguments based on the configuration

=cut

sub _mysql_cli {
    my ($self) = @_;
    my $mysql_args = "-h '".$self->host."' -u '".$self->username."' -p'".$self->password."'";
    return "mysql $mysql_args";
}

=head2 update_from_incrementals

Fetch the necessary incrementals from the API and apply them on the database

=cut

sub update_from_incrementals {
    my ($self) = @_;
    my $logger = fingerbank::Log::get_logger;

    my ($last_timestamp) = $self->handle->storage->dbh->selectrow_array("SELECT id from incrementals_applied ORDER by id DESC LIMIT 1;");

    my $download_dest = $INSTALL_PATH."/db/incremental-".int(rand()*10**10).".sql";
    my $mysql_cli = $self->_mysql_cli;
    my $database = $self->database;
    my ($status, $result) = fingerbank::Util::fetch_file(destination => $download_dest, download_url => $self->incrementals_url, get_params => {start => $last_timestamp});
    if(is_success($status)) {
        my $output = `$mysql_cli $database < $download_dest 2>&1`;
        my $rt = $?;
        unlink $download_dest;
        if($rt != 0) {
            my $msg = "MySQL incremental apply failed with code $rt : $output";
            $logger->error($msg);
            return ($fingerbank::Status::INTERNAL_SERVER_ERROR, $msg);
        }
        return ($fingerbank::Status::OK, "Successfully applied incremental to MySQL database.");
    }
    else {
        my $msg = "Can't fetch incrementals : ".$result;
        $logger->error($msg);
        return ($status, $msg);
    }
}

=head1 AUTHOR

Inverse inc. <info@inverse.ca>

=head1 COPYRIGHT

Copyright (C) 2005-2016 Inverse inc.

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

__PACKAGE__->meta->make_immutable;

1;

