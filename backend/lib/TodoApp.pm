package TodoApp;

use Mojo::Base 'Mojolicious', -signatures;
use Mojo::Pg;
use Mojo::JSON qw(decode_json encode_json);
use MIME::Base64 qw(decode_base64 encode_base64);
use Digest::SHA qw(hmac_sha256 sha256_hex);

sub _b64url_encode ($data) {
  my $encoded = encode_base64($data, '');
  $encoded =~ tr!+/!-_!;
  $encoded =~ s/=+$//;
  return $encoded;
}

sub _b64url_decode ($data) {
  $data =~ tr!-_!+/!;
  my $pad = length($data) % 4;
  $data .= '=' x (4 - $pad) if $pad;
  return decode_base64($data);
}

sub _jwt_encode ($claims, $secret) {
  my $header = _b64url_encode(encode_json({alg => 'HS256', typ => 'JWT'}));
  my $payload = _b64url_encode(encode_json($claims));
  my $signature = _b64url_encode(hmac_sha256("$header.$payload", $secret));
  return "$header.$payload.$signature";
}

sub _jwt_decode ($token, $secret) {
  my ($header, $payload, $signature) = split /\./, $token, 3;
  die 'Invalid token' if !$header || !$payload || !$signature;

  my $expected = _b64url_encode(hmac_sha256("$header.$payload", $secret));
  die 'Invalid token signature' if $signature ne $expected;

  my $claims_json = _b64url_decode($payload);
  my $claims = decode_json($claims_json);
  return $claims;
}

sub startup ($self) {
  my $config = {
    jwt_secret    => $ENV{JWT_SECRET} // 'super-secret-change-me',
    password_salt => $ENV{PASSWORD_SALT} // 'dev-salt-change-me',
    cors_origin   => $ENV{CORS_ORIGIN} // '*',
  };

  $self->secrets([$config->{jwt_secret}]);

  my $pg = Mojo::Pg->new($ENV{DATABASE_URL});
  $self->helper(pg => sub { $pg });

  $self->helper(password_hash => sub ($c, $password) {
    return sha256_hex($password . $config->{password_salt});
  });

  $self->hook(before_dispatch => sub ($c) {
    $c->res->headers->header('Access-Control-Allow-Origin' => $config->{cors_origin});
    $c->res->headers->header('Access-Control-Allow-Headers' => 'Authorization, Content-Type');
    $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS');

    if ($c->req->method eq 'OPTIONS') {
      $c->rendered(204);
      return;
    }
  });

  my $r = $self->routes;

  $r->get('/health' => sub ($c) {
    $c->render(json => {status => 'ok'});
  });

  my $auth = $r->under('/api/auth');

  $auth->post('/login' => sub ($c) {
    my $body = $c->req->json // {};
    my $username = $body->{username} // '';
    my $password = $body->{password} // '';

    if (!$username || !$password) {
      return $c->render(status => 400, json => {error => 'Username and password are required'});
    }

    my $user = $c->pg->db->query(
      'SELECT id, username, password_hash, role FROM users WHERE username = ?',
      $username,
    )->hash;

    if (!$user || $user->{password_hash} ne $c->password_hash($password)) {
      return $c->render(status => 401, json => {error => 'Invalid credentials'});
    }

    my $token = _jwt_encode({
      uid => $user->{id},
      role => $user->{role},
      exp => time + 24 * 60 * 60,
    }, $config->{jwt_secret});

    return $c->render(json => {
      token => $token,
      user => {
        id => $user->{id},
        username => $user->{username},
        role => $user->{role},
      },
    });
  });

  my $api = $r->under('/api' => sub ($c) {
    my $authz = $c->req->headers->authorization // '';
    my ($token) = $authz =~ /^Bearer\s+(.+)$/;

    if (!$token) {
      $c->render(status => 401, json => {error => 'Missing bearer token'});
      return undef;
    }

    my $claims;
    eval {
      $claims = _jwt_decode($token, $config->{jwt_secret});
      1;
    } or do {
      $c->render(status => 401, json => {error => 'Invalid token'});
      return undef;
    };

    if (($claims->{exp} // 0) < time) {
      $c->render(status => 401, json => {error => 'Token expired'});
      return undef;
    }

    $c->stash(current_user => {
      id => $claims->{uid},
      role => $claims->{role},
    });

    return 1;
  });

  $api->get('/me' => sub ($c) {
    my $current = $c->stash('current_user');
    my $user = $c->pg->db->query(
      'SELECT id, username, role FROM users WHERE id = ?',
      $current->{id},
    )->hash;

    return $c->render(json => {user => $user});
  });

  $api->get('/users' => sub ($c) {
    my $current = $c->stash('current_user');
    return $c->render(status => 403, json => {error => 'Admin only'}) if $current->{role} ne 'admin';

    my $users = $c->pg->db->query('SELECT id, username, role FROM users ORDER BY id ASC')->hashes->to_array;
    return $c->render(json => {users => $users});
  });

  $api->get('/todos' => sub ($c) {
    my $current = $c->stash('current_user');
    my $all = ($c->param('all') // '') eq '1';

    my $todos;
    if ($current->{role} eq 'admin' && $all) {
      $todos = $c->pg->db->query(
        q{
          SELECT t.id, t.user_id, u.username, t.title, t.completed, t.created_at, t.updated_at
          FROM todos t
          JOIN users u ON u.id = t.user_id
          ORDER BY t.id DESC
        }
      )->hashes->to_array;
    } else {
      $todos = $c->pg->db->query(
        q{
          SELECT t.id, t.user_id, u.username, t.title, t.completed, t.created_at, t.updated_at
          FROM todos t
          JOIN users u ON u.id = t.user_id
          WHERE t.user_id = ?
          ORDER BY t.id DESC
        },
        $current->{id},
      )->hashes->to_array;
    }

    return $c->render(json => {todos => $todos});
  });

  $api->post('/todos' => sub ($c) {
    my $current = $c->stash('current_user');
    my $body = $c->req->json // {};
    my $title = $body->{title} // '';

    if (!$title) {
      return $c->render(status => 400, json => {error => 'Title is required'});
    }

    my $todo = $c->pg->db->query(
      q{
        INSERT INTO todos (user_id, title, completed)
        VALUES (?, ?, false)
        RETURNING id, user_id, title, completed, created_at, updated_at
      },
      $current->{id},
      $title,
    )->hash;

    return $c->render(status => 201, json => {todo => $todo});
  });

  $api->put('/todos/:id' => sub ($c) {
    my $current = $c->stash('current_user');
    my $todo_id = $c->param('id');
    my $body = $c->req->json // {};

    my $existing = $c->pg->db->query(
      'SELECT id, user_id FROM todos WHERE id = ?',
      $todo_id,
    )->hash;

    if (!$existing) {
      return $c->render(status => 404, json => {error => 'Todo not found'});
    }

    if ($current->{role} ne 'admin' && $existing->{user_id} != $current->{id}) {
      return $c->render(status => 403, json => {error => 'Not allowed'});
    }

    my $title = exists $body->{title} ? $body->{title} : undef;
    my $completed = exists $body->{completed} ? ($body->{completed} ? 1 : 0) : undef;

    my @sets;
    my @bind;

    if (defined $title) {
      push @sets, 'title = ?';
      push @bind, $title;
    }

    if (defined $completed) {
      push @sets, 'completed = ?';
      push @bind, $completed;
    }

    if (!@sets) {
      return $c->render(status => 400, json => {error => 'No fields to update'});
    }

    push @sets, 'updated_at = NOW()';

    my $sql = 'UPDATE todos SET ' . join(', ', @sets) . ' WHERE id = ? RETURNING id, user_id, title, completed, created_at, updated_at';
    push @bind, $todo_id;

    my $todo = $c->pg->db->query($sql, @bind)->hash;
    return $c->render(json => {todo => $todo});
  });

  $api->delete('/todos/:id' => sub ($c) {
    my $current = $c->stash('current_user');
    my $todo_id = $c->param('id');

    my $existing = $c->pg->db->query(
      'SELECT id, user_id FROM todos WHERE id = ?',
      $todo_id,
    )->hash;

    if (!$existing) {
      return $c->render(status => 404, json => {error => 'Todo not found'});
    }

    if ($current->{role} ne 'admin' && $existing->{user_id} != $current->{id}) {
      return $c->render(status => 403, json => {error => 'Not allowed'});
    }

    $c->pg->db->query('DELETE FROM todos WHERE id = ?', $todo_id);
    return $c->render(status => 204, data => '');
  });
}

1;
