#!/usr/bin/env perl
use strict;
use warnings;
use Mojo::Pg;

my $database_url = $ENV{DATABASE_URL} // die "DATABASE_URL is required\n";
my $max_attempts = 30;

for my $attempt (1 .. $max_attempts) {
  eval {
    my $pg = Mojo::Pg->new($database_url);
    $pg->db->query('SELECT 1');
    print "Database is ready\n";
    exit 0;
  };

  warn "Waiting for database ($attempt/$max_attempts)...\n";
  sleep 2;
}

die "Database did not become ready in time\n";
