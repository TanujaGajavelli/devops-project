FROM node:16-alpine

WORKDIR /app
COPY . .
RUN echo "Build successful"

CMD ["echo", "Running container..."]
