FROM postgres:latest

ENV POSTGRES_USER root
ENV POSTGRES_PASSWORD root

COPY init.sql /docker-entrypoint-initdb.d/
