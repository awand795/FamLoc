-- FamLoc migration 001: skema awal (PostgreSQL + PostGIS)
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS users (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email              VARCHAR UNIQUE NOT NULL,
  password_hash      VARCHAR NOT NULL,
  name               VARCHAR NOT NULL,
  invite_code        VARCHAR UNIQUE NOT NULL,
  avatar_version     INTEGER DEFAULT 0,
  sharing_on         BOOLEAN DEFAULT FALSE,
  location_precision VARCHAR DEFAULT 'exact'
                     CHECK (location_precision IN ('exact','approx')),
  created_at         TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_avatars (
  user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  image      BYTEA NOT NULL CHECK (octet_length(image) <= 102400),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS geocode_cache (
  lat_lng_key VARCHAR PRIMARY KEY,
  address     TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS friend_requests (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID REFERENCES users(id) ON DELETE CASCADE,
  addressee_id UUID REFERENCES users(id) ON DELETE CASCADE,
  status       VARCHAR CHECK (status IN ('pending','accepted','rejected'))
               DEFAULT 'pending',
  created_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE (requester_id, addressee_id)
);
CREATE INDEX IF NOT EXISTS idx_fr_addressee ON friend_requests(addressee_id, status);
CREATE INDEX IF NOT EXISTS idx_fr_requester ON friend_requests(requester_id, status);

CREATE TABLE IF NOT EXISTS friendships (
  user_id_a  UUID REFERENCES users(id) ON DELETE CASCADE,
  user_id_b  UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  CHECK (user_id_a < user_id_b),
  PRIMARY KEY (user_id_a, user_id_b)
);

CREATE TABLE IF NOT EXISTS user_locations (
  user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  geom       GEOGRAPHY(POINT, 4326) NOT NULL,
  accuracy   REAL,
  heading    REAL,
  battery    SMALLINT CHECK (battery BETWEEN 0 AND 100),
  is_mocked  BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_user_locations_geom ON user_locations USING GIST (geom);

CREATE TABLE IF NOT EXISTS sharing_schedules (
  user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  days       SMALLINT[] NOT NULL,
  start_time TIME NOT NULL,
  end_time   TIME NOT NULL,
  enabled    BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS location_requests (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID REFERENCES users(id) ON DELETE CASCADE,
  target_id    UUID REFERENCES users(id) ON DELETE CASCADE,
  status       VARCHAR CHECK (status IN ('pending','accepted','dismissed'))
               DEFAULT 'pending',
  created_at   TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_lr_target ON location_requests(target_id, status);
