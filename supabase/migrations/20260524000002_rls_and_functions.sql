-- innawoods — RLS, membership helpers, and party lifecycle RPCs.
--
-- RLS here is pure ACCESS CONTROL: it decides who may read/write which rows.
-- It never inspects content (content is ciphertext). The guiding rule: you can
-- only ever touch rows for parties you belong to, and you can only write rows
-- attributed to yourself.

-- ---------------------------------------------------------------------------
-- Membership helpers (SECURITY DEFINER to avoid RLS recursion on party_members)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.is_party_member(p_party_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.party_members
    WHERE party_id = p_party_id AND user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.shares_party_with(p_user UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.party_members me
    JOIN public.party_members them ON them.party_id = me.party_id
    WHERE me.user_id = auth.uid() AND them.user_id = p_user
  );
$$;

-- ---------------------------------------------------------------------------
-- Enable RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.users            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parties          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.party_members    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.location_updates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pins             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages         ENABLE ROW LEVEL SECURITY;

-- USERS: read self + anyone you share a party with; write only self.
CREATE POLICY "users read self or co-members" ON public.users
  FOR SELECT USING (id = auth.uid() OR public.shares_party_with(id));
CREATE POLICY "users insert self" ON public.users
  FOR INSERT WITH CHECK (id = auth.uid());
CREATE POLICY "users update self" ON public.users
  FOR UPDATE USING (id = auth.uid());

-- PARTIES: members (and the creator) can read; only creator can mutate.
CREATE POLICY "parties read members" ON public.parties
  FOR SELECT USING (public.is_party_member(id) OR created_by = auth.uid());
CREATE POLICY "parties insert own" ON public.parties
  FOR INSERT WITH CHECK (created_by = auth.uid());
CREATE POLICY "parties update creator" ON public.parties
  FOR UPDATE USING (created_by = auth.uid());
CREATE POLICY "parties delete creator" ON public.parties
  FOR DELETE USING (created_by = auth.uid());

-- PARTY_MEMBERS: members see the roster; you can only add/modify/remove YOURSELF.
CREATE POLICY "members read roster" ON public.party_members
  FOR SELECT USING (public.is_party_member(party_id));
CREATE POLICY "members insert self" ON public.party_members
  FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY "members update self" ON public.party_members
  FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "members leave" ON public.party_members
  FOR DELETE USING (user_id = auth.uid());

-- LOCATION_UPDATES
CREATE POLICY "loc read members" ON public.location_updates
  FOR SELECT USING (public.is_party_member(party_id));
CREATE POLICY "loc insert own" ON public.location_updates
  FOR INSERT WITH CHECK (user_id = auth.uid() AND public.is_party_member(party_id));
CREATE POLICY "loc update own" ON public.location_updates
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "loc delete own" ON public.location_updates
  FOR DELETE USING (user_id = auth.uid());

-- PINS
CREATE POLICY "pins read members" ON public.pins
  FOR SELECT USING (public.is_party_member(party_id));
CREATE POLICY "pins insert own" ON public.pins
  FOR INSERT WITH CHECK (user_id = auth.uid() AND public.is_party_member(party_id));
CREATE POLICY "pins update own" ON public.pins
  FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "pins delete own" ON public.pins
  FOR DELETE USING (user_id = auth.uid());

-- ROUTES
CREATE POLICY "routes read members" ON public.routes
  FOR SELECT USING (public.is_party_member(party_id));
CREATE POLICY "routes insert own" ON public.routes
  FOR INSERT WITH CHECK (user_id = auth.uid() AND public.is_party_member(party_id));
CREATE POLICY "routes update own" ON public.routes
  FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "routes delete own" ON public.routes
  FOR DELETE USING (user_id = auth.uid());

-- MESSAGES
CREATE POLICY "messages read members" ON public.messages
  FOR SELECT USING (public.is_party_member(party_id));
CREATE POLICY "messages insert own" ON public.messages
  FOR INSERT WITH CHECK (sender_id = auth.uid() AND public.is_party_member(party_id));
CREATE POLICY "messages delete own" ON public.messages
  FOR DELETE USING (sender_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Party lifecycle RPCs (atomic create/join; capacity + expiry enforced here)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_party(
  p_invite_code TEXT,
  p_callsign    TEXT,
  p_color       TEXT DEFAULT '#C19A6B',
  p_name        TEXT DEFAULT NULL,
  p_ephemeral   BOOLEAN DEFAULT true,
  p_expires_at  TIMESTAMPTZ DEFAULT NULL
) RETURNS public.parties
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_party public.parties;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  INSERT INTO public.parties (invite_code, name, created_by, ephemeral, expires_at)
  VALUES (p_invite_code, p_name, auth.uid(), p_ephemeral, p_expires_at)
  RETURNING * INTO v_party;
  INSERT INTO public.party_members (party_id, user_id, callsign, color)
  VALUES (v_party.id, auth.uid(), p_callsign, p_color);
  RETURN v_party;
END;
$$;

CREATE OR REPLACE FUNCTION public.join_party(
  p_invite_code TEXT,
  p_callsign    TEXT,
  p_color       TEXT DEFAULT '#C19A6B'
) RETURNS public.parties
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_party public.parties;
  v_count INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO v_party FROM public.parties WHERE invite_code = p_invite_code;
  IF NOT FOUND THEN RAISE EXCEPTION 'party not found'; END IF;
  IF v_party.ended_at IS NOT NULL
     OR (v_party.expires_at IS NOT NULL AND v_party.expires_at < now()) THEN
    RAISE EXCEPTION 'party has ended';
  END IF;
  IF EXISTS (SELECT 1 FROM public.party_members
             WHERE party_id = v_party.id AND user_id = auth.uid()) THEN
    RETURN v_party; -- idempotent re-join
  END IF;
  SELECT count(*) INTO v_count FROM public.party_members WHERE party_id = v_party.id;
  IF v_count >= v_party.max_members THEN RAISE EXCEPTION 'party is full'; END IF;
  INSERT INTO public.party_members (party_id, user_id, callsign, color)
  VALUES (v_party.id, auth.uid(), p_callsign, p_color);
  RETURN v_party;
END;
$$;

-- Ephemeral self-destruct: only the creator may end a session.
CREATE OR REPLACE FUNCTION public.end_party(p_party_id UUID)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_party public.parties;
BEGIN
  SELECT * INTO v_party FROM public.parties WHERE id = p_party_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'party not found'; END IF;
  IF v_party.created_by <> auth.uid() THEN
    RAISE EXCEPTION 'only the party creator can end the session';
  END IF;
  DELETE FROM public.location_updates WHERE party_id = p_party_id;
  DELETE FROM public.messages WHERE party_id = p_party_id;
  IF v_party.ephemeral THEN
    DELETE FROM public.parties WHERE id = p_party_id; -- cascades members/pins/routes
  ELSE
    UPDATE public.parties SET ended_at = now() WHERE id = p_party_id;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Grants (RLS still gates rows; roles need table/function privileges too)
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
