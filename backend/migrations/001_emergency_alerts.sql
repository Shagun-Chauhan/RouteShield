-- Assumes existing tables: users(id) and trusted_contacts(id, user_id, name, phone).
-- Adjust types/names to your schema. No new contacts table is created.

create table if not exists emergency_alerts (
  id                    bigserial primary key,
  user_id               bigint not null references users(id) on delete cascade,
  episode_id            text   not null,
  battery_level         smallint not null check (battery_level between 0 and 100),
  latitude              double precision,
  longitude             double precision,
  location_recorded_at  timestamptz,
  location_accuracy_m   real,
  captured_at           timestamptz not null,
  status                text not null default 'processing'
                        check (status in ('processing','accepted','partial','failed','no_contacts')),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (user_id, episode_id)            -- idempotency: one alert per low-battery episode
);

create table if not exists emergency_alert_deliveries (
  id              bigserial primary key,
  alert_id        bigint not null references emergency_alerts(id) on delete cascade,
  contact_id      text   not null,
  to_masked       text   not null,         -- never store the full number twice
  provider        text   not null,
  provider_sid    text,
  provider_status text,                    -- what the provider said at submit time (e.g. 'queued')
  error_code      text,
  error_message   text,
  created_at      timestamptz not null default now(),
  unique (alert_id, contact_id)            -- a retry never texts the same contact twice
);

create index if not exists emergency_alerts_user_created on emergency_alerts (user_id, created_at desc);

-- If any of this is exposed through Supabase/PostgREST: enable RLS and allow
-- clients SELECT-only on their own rows; inserts happen only from the backend.
-- alter table emergency_alerts enable row level security;
-- create policy own_alerts_read on emergency_alerts for select using (user_id = auth.uid());
