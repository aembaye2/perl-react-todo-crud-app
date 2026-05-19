FROM perl:5.38

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        cpanminus \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY cpanfile ./
RUN cpanm --notest --installdeps .

COPY . .
RUN chmod +x script/start.sh script/todo_app script/migrate_and_seed.pl script/wait_for_db.pl

EXPOSE 3000

CMD ["./script/start.sh"]
