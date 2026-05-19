#!/usr/bin/env perl
use strict;
use warnings;
use Mojo::Pg;
use Digest::SHA qw(sha256_hex);

my $database_url = $ENV{DATABASE_URL} // die "DATABASE_URL is required\n";
my $password_salt = $ENV{PASSWORD_SALT} // 'dev-salt-change-me';

my $admin_username = $ENV{DEMO_ADMIN_USERNAME} // 'admin';
my $admin_password = $ENV{DEMO_ADMIN_PASSWORD} // 'admin123';
my $user_username = $ENV{DEMO_USER_USERNAME} // 'demo';
my $user_password = $ENV{DEMO_USER_PASSWORD} // 'demo123';

sub password_hash {
  my ($password) = @_;
  return sha256_hex($password . $password_salt);
}

my $pg = Mojo::Pg->new($database_url);
my $db = $pg->db;

$db->query(q{
  CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('admin', 'user')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )
});

$db->query(q{
  CREATE TABLE IF NOT EXISTS todos (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )
});

$db->query(
  q{
    INSERT INTO users (username, password_hash, role)
    VALUES (?, ?, 'admin')
    ON CONFLICT (username)
    DO UPDATE SET password_hash = EXCLUDED.password_hash, role = EXCLUDED.role
  },
  $admin_username,
  password_hash($admin_password),
);

$db->query(
  q{
    INSERT INTO users (username, password_hash, role)
    VALUES (?, ?, 'user')
    ON CONFLICT (username)
    DO UPDATE SET password_hash = EXCLUDED.password_hash, role = EXCLUDED.role
  },
  $user_username,
  password_hash($user_password),
);

my $demo_admin = $db->query('SELECT id FROM users WHERE username = ?', $admin_username)->hash;
my $demo_user = $db->query('SELECT id FROM users WHERE username = ?', $user_username)->hash;

$db->query(
  q{
    INSERT INTO todos (user_id, title, completed)
    SELECT ?, ?, false
    WHERE NOT EXISTS (
      SELECT 1 FROM todos WHERE user_id = ? AND title = ?
    )
  },
  $demo_admin->{id},
  'Review production release checklist',
  $demo_admin->{id},
  'Review production release checklist',
);

$db->query(
  q{
    INSERT INTO todos (user_id, title, completed)
    SELECT ?, ?, false
    WHERE NOT EXISTS (
      SELECT 1 FROM todos WHERE user_id = ? AND title = ?
    )
  },
  $demo_user->{id},
  'Try the todo CRUD demo',
  $demo_user->{id},
  'Try the todo CRUD demo',
);

print "Migration and seed completed\n";
print "Admin user: $admin_username / $admin_password\n";
print "Demo user: $user_username / $user_password\n";
