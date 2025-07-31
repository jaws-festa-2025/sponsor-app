FROM public.ecr.aws/docker/library/node:20-bookworm-slim as nodebuilder
WORKDIR /app

COPY package.json /app/
COPY yarn.lock /app/
RUN yarn install --frozen-lockfile

COPY . /app/
RUN yarn run build

###

FROM public.ecr.aws/sorah/ruby:3.2.8-dev-noble as builder

RUN apt-get update \
    && apt-get install -y libpq-dev git-core \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile /app/
COPY Gemfile.lock /app/

RUN bundle install --path /gems --jobs 100 --deployment --without development:test

###

FROM public.ecr.aws/sorah/ruby:3.2.8-noble

RUN apt-get update \
    && apt-get install -y libpq5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /gems /gems
COPY --from=builder /app/.bundle /app/.bundle
COPY --from=nodebuilder /app/public/packs /app/public/packs
COPY . /app/

ENV PORT=3000 LANG=C.UTF-8
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
