# Perl Mojolicious + React Todo CRUD (Auth)

Dockerized full-stack todo app with:

- Mojolicious backend API (JWT auth)
- PostgreSQL database
- React frontend (Vite)
- Auto migration + auto seed of demo users on startup

## Run

From the repository root:

```bash
docker compose up --build -d
```

After startup:

- Frontend: `http://localhost:5173`
- Backend health: `http://localhost:3000/health`

The frontend uses a Vite proxy (`/api` and `/health`) to reach the backend, so API calls work correctly even when accessing the app through forwarded/container URLs.

## Demo Credentials

- Admin
	- Username: `admin`
	- Password: `admin123`
- User
	- Username: `demo`
	- Password: `demo123`

These users are created automatically by the backend startup migration/seed script.

## Features

- Authentication:
	- `POST /api/auth/login`
	- JWT bearer token
- Current user:
	- `GET /api/me`
- Todo CRUD:
	- `GET /api/todos`
	- `POST /api/todos`
	- `PUT /api/todos/:id`
	- `DELETE /api/todos/:id`
- Admin extras:
	- `GET /api/users`
	- `GET /api/todos?all=1` to view all users' todos

## Environment Variables

Configured in `docker-compose.yml`:

- `DATABASE_URL`
- `JWT_SECRET`
- `PASSWORD_SALT`
- `CORS_ORIGIN`
- `DEMO_ADMIN_USERNAME`
- `DEMO_ADMIN_PASSWORD`
- `DEMO_USER_USERNAME`
- `DEMO_USER_PASSWORD`

Override them in compose for production values.