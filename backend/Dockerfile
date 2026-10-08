# Image du backend methe (FastAPI). Construite par Render (render.yaml) ou :
#   docker build -t methe-api backend && docker run -p 8000:8000 --env-file backend/.env methe-api
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8000
WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY main.py .

# Pas de droits root dans le conteneur
RUN useradd --create-home --uid 10001 methe
USER methe

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import os, urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ[\"PORT\"]}/health', timeout=4)"
CMD ["sh", "-c", "exec uvicorn main:app --host 0.0.0.0 --port ${PORT} --workers 2 --no-server-header"]
