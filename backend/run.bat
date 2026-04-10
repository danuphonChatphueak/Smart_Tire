@echo off
cd backend

IF NOT EXIST .venv (
    echo Creating virtual environment...
    python -m venv .venv
)

echo Activating virtual environment...
call .venv\Scripts\activate.bat

IF NOT EXIST .env (
    echo Copying .env.example to .env...
    copy .env.example .env
)

echo Installing dependencies...
pip install -r requirements.txt

echo Starting server...
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
