const API_URL = import.meta.env.VITE_API_URL || '/api';

export async function request(path, options = {}) {
  const token = localStorage.getItem('token');
  const headers = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetch(`${API_URL}${path}`, {
    ...options,
    headers,
  });

  if (response.status === 204) {
    return null;
  }

  const contentType = response.headers.get('content-type') || '';
  const isJson = contentType.includes('application/json');
  const payload = isJson ? await response.json() : await response.text();

  if (!response.ok) {
    if (isJson) {
      throw new Error(payload.error || 'Request failed');
    }

    throw new Error('API returned a non-JSON response. Check frontend API URL/proxy configuration.');
  }

  if (!isJson) {
    throw new Error('API returned unexpected content type. Expected JSON.');
  }

  return payload;
}

export const apiUrl = API_URL;
