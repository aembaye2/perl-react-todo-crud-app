#!/usr/bin/env bash
set -euo pipefail

perl script/wait_for_db.pl
perl script/migrate_and_seed.pl

exec morbo -l "http://0.0.0.0:3000" script/todo_app
