FROM cloudflare/cloudflared:latest AS cf
FROM python:3.12-alpine

COPY --from=cf /usr/local/bin/cloudflared /usr/local/bin/cloudflared
WORKDIR /app
COPY server.py .

EXPOSE 9876

CMD ["python", "server.py"]
