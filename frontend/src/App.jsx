import { useEffect, useMemo, useState } from 'react';
import { request } from './api';

function App() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [user, setUser] = useState(null);
  const [token, setToken] = useState(localStorage.getItem('token') || '');
  const [todos, setTodos] = useState([]);
  const [newTodoTitle, setNewTodoTitle] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [showAll, setShowAll] = useState(false);

  const isAdmin = useMemo(() => user?.role === 'admin', [user]);

  async function loadProfile() {
    const data = await request('/me');
    setUser(data.user);
  }

  async function loadTodos(allFlag = showAll) {
    const query = allFlag ? '?all=1' : '';
    const data = await request(`/todos${query}`);
    setTodos(data.todos);
  }

  async function handleLogin(event) {
    event.preventDefault();
    setError('');
    setLoading(true);

    try {
      const data = await request('/auth/login', {
        method: 'POST',
        body: JSON.stringify({ username, password }),
      });
      localStorage.setItem('token', data.token);
      setToken(data.token);
      setUser(data.user);
      setUsername('');
      setPassword('');
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }

  function handleLogout() {
    localStorage.removeItem('token');
    setToken('');
    setUser(null);
    setTodos([]);
    setShowAll(false);
  }

  async function handleCreateTodo(event) {
    event.preventDefault();
    if (!newTodoTitle.trim()) {
      return;
    }

    setError('');
    try {
      await request('/todos', {
        method: 'POST',
        body: JSON.stringify({ title: newTodoTitle.trim() }),
      });
      setNewTodoTitle('');
      await loadTodos();
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleToggleTodo(todo) {
    setError('');
    try {
      await request(`/todos/${todo.id}`, {
        method: 'PUT',
        body: JSON.stringify({ completed: !todo.completed }),
      });
      await loadTodos();
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleEditTodo(todo) {
    const nextTitle = window.prompt('Edit todo title', todo.title);
    if (nextTitle === null) {
      return;
    }

    setError('');
    try {
      await request(`/todos/${todo.id}`, {
        method: 'PUT',
        body: JSON.stringify({ title: nextTitle.trim() }),
      });
      await loadTodos();
    } catch (err) {
      setError(err.message);
    }
  }

  async function handleDeleteTodo(todo) {
    setError('');
    try {
      await request(`/todos/${todo.id}`, {
        method: 'DELETE',
      });
      await loadTodos();
    } catch (err) {
      setError(err.message);
    }
  }

  useEffect(() => {
    if (!token) {
      return;
    }

    loadProfile().catch((err) => {
      setError(err.message);
      handleLogout();
    });
  }, [token]);

  useEffect(() => {
    if (!token || !user) {
      return;
    }

    loadTodos().catch((err) => setError(err.message));
  }, [token, user, showAll]);

  if (!token) {
    return (
      <main className="page">
        <section className="card auth-card">
          <h1>Todo App</h1>
          <p className="subtitle">Sign in to manage your todos.</p>
          {error ? <p className="error">{error}</p> : null}
          <form onSubmit={handleLogin}>
            <label>
              Username
              <input
                value={username}
                onChange={(event) => setUsername(event.target.value)}
                autoComplete="username"
                required
              />
            </label>
            <label>
              Password
              <input
                type="password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                autoComplete="current-password"
                required
              />
            </label>
            <button type="submit" disabled={loading}>
              {loading ? 'Signing in...' : 'Sign in'}
            </button>
          </form>
        </section>
      </main>
    );
  }

  return (
    <main className="page">
      <section className="card app-card">
        <header className="app-header">
          <div>
            <h1>Todo App</h1>
            <p className="subtitle">
              Signed in as <strong>{user?.username}</strong> ({user?.role})
            </p>
          </div>
          <button type="button" className="ghost" onClick={handleLogout}>
            Logout
          </button>
        </header>

        {isAdmin ? (
          <label className="toggle-row">
            <input
              type="checkbox"
              checked={showAll}
              onChange={(event) => setShowAll(event.target.checked)}
            />
            Show all users' todos
          </label>
        ) : null}

        {error ? <p className="error">{error}</p> : null}

        <form className="todo-form" onSubmit={handleCreateTodo}>
          <input
            value={newTodoTitle}
            onChange={(event) => setNewTodoTitle(event.target.value)}
            placeholder="Add a new todo"
            required
          />
          <button type="submit">Add</button>
        </form>

        <ul className="todo-list">
          {todos.map((todo) => (
            <li key={todo.id} className={todo.completed ? 'completed' : ''}>
              <label>
                <input
                  type="checkbox"
                  checked={todo.completed}
                  onChange={() => handleToggleTodo(todo)}
                />
                <span>{todo.title}</span>
              </label>
              <div className="todo-meta">
                <small>{todo.username ? `Owner: ${todo.username}` : ''}</small>
                <div className="actions">
                  <button type="button" className="ghost" onClick={() => handleEditTodo(todo)}>
                    Edit
                  </button>
                  <button type="button" className="danger" onClick={() => handleDeleteTodo(todo)}>
                    Delete
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      </section>
    </main>
  );
}

export default App;
