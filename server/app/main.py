from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession

from .db import SessionLocal, init_db
from .routers import account, archive, auth, inbox
from .schemas import HealthOut
from .seed import seed_demo_users
from .settings import data_root, settings


@asynccontextmanager
async def lifespan(_: FastAPI):
    data_root()
    await init_db()
    async with SessionLocal() as session:  # type: AsyncSession
        await seed_demo_users(session)
    yield


app = FastAPI(
    title="Ceiling Sync API",
    version="0.2.0",
    lifespan=lifespan,
)

origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins if origins != ["*"] else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(inbox.router)
app.include_router(archive.router)
app.include_router(account.router)


@app.get("/health", response_model=HealthOut)
async def health():
    return HealthOut(ok=True)
