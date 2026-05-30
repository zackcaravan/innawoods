-- innawoods — Phase 1 schema
--
-- PRIVACY MODEL: every *_payload column below is an opaque ciphertext blob
-- (base64 of nonce || ciphertext || Poly1305 MAC), sealed client-side with the
-- party group key. The server has no key and therefore no plaintext coordinates
-- or message content. RLS (next migration) controls *who may read which rows*,
-- never *what the rows contain*.

-- USERS — extends auth.users with the public profile + identity public key.
CREATE TABLE public.users (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name  TEXT,
  avatar_color  TEXT NOT NULL DEFAULT '#8A9A5B', -- olive
  public_key    TEXT NOT NULL,                   -- base64 X25519 public key
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- PARTIES — an ephemeral (or named persistent) crew session.
-- The group SECRET that derives the encryption key is NOT stored here; only the
-- non-secret lookup code is. Knowing invite_code reveals nothing about content.
CREATE TABLE public.parties (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_code TEXT NOT NULL UNIQUE,                 -- short public lookup code
  name        TEXT,                                 -- optional, for persistent crews
  created_by  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  ephemeral   BOOLEAN NOT NULL DEFAULT true,
  max_members INTEGER NOT NULL DEFAULT 12 CHECK (max_members BETWEEN 1 AND 50),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ,                          -- NULL = no auto-expiry
  ended_at    TIMESTAMPTZ                           -- set when the session ends
);

-- PARTY_MEMBERS — who is in a party, with their per-party callsign/color.
CREATE TABLE public.party_members (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id  UUID NOT NULL REFERENCES public.parties(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  callsign  TEXT NOT NULL,
  color     TEXT NOT NULL DEFAULT '#C19A6B',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (party_id, user_id)
);

-- LOCATION_UPDATES — one upserted row per member per party (live position).
-- Purged on session end. encrypted_payload = {lat,lng,speed,heading,ts}.
CREATE TABLE public.location_updates (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id          UUID NOT NULL REFERENCES public.parties(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  encrypted_payload TEXT NOT NULL,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (party_id, user_id)
);

-- PINS — dropped markers. pin_type is kept in the clear (low-sensitivity enum,
-- useful for rendering icons offline); name/notes/coords live in the payload.
CREATE TABLE public.pins (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id          UUID NOT NULL REFERENCES public.parties(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  pin_type          TEXT NOT NULL DEFAULT 'waypoint'
                      CHECK (pin_type IN ('waypoint','meet','hazard','camp','poi','custom')),
  encrypted_payload TEXT NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ROUTES — shared planned routes. The route NAME is folded into the encrypted
-- payload (a name like "back way past the gate" can itself be sensitive).
CREATE TABLE public.routes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id          UUID NOT NULL REFERENCES public.parties(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  encrypted_payload TEXT NOT NULL, -- {name, points:[{lat,lng}], ...}
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- MESSAGES — per-party encrypted chat.
CREATE TABLE public.messages (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id          UUID NOT NULL REFERENCES public.parties(id) ON DELETE CASCADE,
  sender_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  encrypted_payload TEXT NOT NULL,
  sent_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for the hot read paths (everything is fetched by party).
CREATE INDEX idx_party_members_party   ON public.party_members(party_id);
CREATE INDEX idx_party_members_user    ON public.party_members(user_id);
CREATE INDEX idx_location_updates_party ON public.location_updates(party_id);
CREATE INDEX idx_pins_party            ON public.pins(party_id);
CREATE INDEX idx_routes_party          ON public.routes(party_id);
CREATE INDEX idx_messages_party_sent   ON public.messages(party_id, sent_at);
CREATE INDEX idx_parties_invite_code   ON public.parties(invite_code);
