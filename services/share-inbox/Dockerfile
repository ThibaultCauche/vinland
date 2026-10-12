# Image generique des petits services Python maison : copie le dossier,
# installe requirements.txt s'il existe, lance server.py. Si le service a
# deja son propre Dockerfile sur le NAS, il remplace celui-ci.
FROM python:3.12-slim
WORKDIR /app
COPY . .
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi
ENV PYTHONUNBUFFERED=1
CMD ["python", "server.py"]
