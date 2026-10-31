# Ceiling Sync API (local-first)

FastAPI service for phone/PC sync: auth/roles, project offers, price pushes,
mount kits inbox, director archive (files), seamless account snapshot restore.

**Develop here first.** Deploy to VPS only after the contract is stable.

## Run locally

```bash
cd server
python -m venv .venv
# Windows: .venv\Scripts\activate
# Linux:   source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --host 127.0.0.1 --port 8010
```

Or Docker:

```bash
docker compose up --build
```

- Health: `GET http://127.0.0.1:8010/health`
- OpenAPI: `http://127.0.0.1:8010/docs`

Default demo users (password `demo1234` for all):

| login     | role      |
|-----------|-----------|
| monter    | installer |
| brigadir  | foreman   |
| director  | director  |

## VPS (later — do not apply until approved)

Existing stack on `80.249.145.44`:

- `vysota-company.ru` → nginx → `site_visota` uvicorn `:8000`
- `crm.vysota-company.ru` → nginx → docker CRM `:3000`

Suggested deploy (separate from CRM/site):

1. Copy this folder to `/root/ceiling_sync`
2. `docker compose up -d` → bind `127.0.0.1:8010`
3. nginx site `calc.vysota-company.ru` (or path on existing host) → `proxy_pass http://127.0.0.1:8010`
4. Point Flutter `API_BASE` to that HTTPS URL

See `deploy/nginx.calc.example.conf`.
