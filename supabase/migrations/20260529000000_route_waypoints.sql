-- Per-route waypoints (rest stop / water / hazard / etc.). Encrypted client-side
-- in the same zero-knowledge style as the route itself.
--
-- Apply with `supabase db push` from the project root, or paste into the
-- Supabase SQL editor and run.

CREATE TABLE public.route_waypoints (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  route_id          UUID NOT NULL REFERENCES public.routes(id) ON DELETE CASCADE,
  party_id          UUID NOT NULL REFERENCES public.parties(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  encrypted_payload TEXT NOT NULL, -- {name, icon, lat, lng, note?}
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX route_waypoints_route_id_idx ON public.route_waypoints(route_id);
CREATE INDEX route_waypoints_party_id_idx ON public.route_waypoints(party_id);

ALTER TABLE public.route_waypoints ENABLE ROW LEVEL SECURITY;

CREATE POLICY "route_waypoints read members" ON public.route_waypoints
  FOR SELECT USING (public.is_party_member(party_id));
CREATE POLICY "route_waypoints insert own" ON public.route_waypoints
  FOR INSERT WITH CHECK (user_id = auth.uid() AND public.is_party_member(party_id));
CREATE POLICY "route_waypoints update own" ON public.route_waypoints
  FOR UPDATE USING (user_id = auth.uid());
CREATE POLICY "route_waypoints delete own" ON public.route_waypoints
  FOR DELETE USING (user_id = auth.uid());

-- Add to the realtime publication so route waypoint changes stream to
-- subscribed clients (same pattern as routes / messages / pins).
ALTER PUBLICATION supabase_realtime ADD TABLE public.route_waypoints;
