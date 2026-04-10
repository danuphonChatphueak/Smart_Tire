# JWT authentication removed — not currently needed
# This file is kept as a placeholder in case auth is needed later.

from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_pw(pw: str) -> str:
    return pwd_context.hash(pw)

def verify_pw(pw: str, hashed: str) -> bool:
    return pwd_context.verify(pw, hashed)

# If you need JWT in the future, uncomment:
# from datetime import datetime, timedelta
# from jose import jwt, JWTError
# from .config import settings
#
# def create_token(sub: str, role: str) -> str:
#     exp = datetime.utcnow() + timedelta(minutes=settings.JWT_EXPIRE_MIN)
#     payload = {"sub": sub, "role": role, "exp": exp}
#     return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALG)
#
# def decode_token(token: str) -> dict:
#     try:
#         return jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALG])
#     except JWTError:
#         raise ValueError("Invalid token")
